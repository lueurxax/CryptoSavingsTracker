#!/usr/bin/env python3
"""Navigation policy gate:

1) Forbid legacy iOS navigation/presentation APIs in active code.
2) Optionally require NAV-MOD decision annotations for changed modal call-sites.

The checker is preview-aware:
- Excludes #Preview blocks.
- Excludes PreviewProvider declarations.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


FORBIDDEN_RULES: list[tuple[str, re.Pattern[str], str]] = [
    ("NAV001", re.compile(r"\bNavigationView\b"), "NavigationView is forbidden in active iOS source"),
    ("NAV001", re.compile(r"\.actionSheet\s*\("), ".actionSheet is forbidden in active iOS source"),
    ("NAV001", re.compile(r"\bActionSheet\b"), "ActionSheet type is forbidden in active iOS source"),
]
MODAL_CALL_RE = re.compile(r"\.(sheet|fullScreenCover|confirmationDialog|popover)\s*\(")
NAV_MOD_ANY_RE = re.compile(r"NAV-MOD:\s*(MOD-\d+)\b")
VALID_MOD_IDS = {"MOD-01", "MOD-02", "MOD-03", "MOD-04", "MOD-05"}
PREVIEW_PROVIDER_RE = re.compile(r"\bstruct\s+\w+\s*:\s*PreviewProvider\b")


@dataclass
class Finding:
    rule_id: str
    file: str
    line: int
    message: str
    suggested_fix: str


def load_allowlist(repo_root: Path, allowlist_path: str | None) -> dict[str, set[str]]:
    if not allowlist_path:
        return {}
    path = repo_root / allowlist_path
    if not path.is_file():
        return {}
    payload = json.loads(path.read_text(encoding="utf-8"))
    exemptions = payload.get("exemptions", [])
    loaded: dict[str, set[str]] = {}
    if not isinstance(exemptions, list):
        return loaded
    for item in exemptions:
        if not isinstance(item, dict):
            continue
        rule_id = item.get("ruleId")
        rel_path = item.get("path")
        if not isinstance(rule_id, str) or not isinstance(rel_path, str):
            continue
        loaded.setdefault(rule_id, set()).add(rel_path)
    return loaded


def is_allowlisted(allowlist: dict[str, set[str]], rule_id: str, rel_path: str) -> bool:
    return rel_path in allowlist.get(rule_id, set())


def run_git(repo_root: Path, args: list[str]) -> tuple[int, str, str]:
    proc = subprocess.run(
        ["git", *args],
        cwd=repo_root,
        text=True,
        capture_output=True,
        check=False,
    )
    return proc.returncode, proc.stdout, proc.stderr


def list_changed_files(repo_root: Path, base_ref: str | None) -> set[str]:
    diff_args = ["diff", "--name-only", "--diff-filter=ACMR"]
    if base_ref:
        diff_args.append(f"{base_ref}...HEAD")
    code, out, _ = run_git(repo_root, diff_args)
    if code != 0 and base_ref:
        code, out, _ = run_git(repo_root, ["diff", "--name-only", "--diff-filter=ACMR"])
    changed = {line.strip() for line in out.splitlines() if line.strip()}

    # Local convenience: include untracked files when not using PR base.
    if not base_ref:
        code, out, _ = run_git(repo_root, ["ls-files", "--others", "--exclude-standard"])
        if code == 0:
            changed.update(line.strip() for line in out.splitlines() if line.strip())

    return changed


def file_is_tracked(repo_root: Path, relative_path: str) -> bool:
    code, _, _ = run_git(repo_root, ["ls-files", "--error-unmatch", relative_path])
    return code == 0


HUNK_RE = re.compile(r"^@@\s+-\d+(?:,\d+)?\s+\+(\d+)(?:,(\d+))?\s+@@")


def changed_lines_for_file(repo_root: Path, relative_path: str, base_ref: str | None) -> set[int] | None:
    # For untracked files all lines are effectively "changed".
    if not file_is_tracked(repo_root, relative_path):
        return None

    diff_args = ["diff", "--unified=0"]
    if base_ref:
        diff_args.append(f"{base_ref}...HEAD")
    diff_args.extend(["--", relative_path])
    code, out, _ = run_git(repo_root, diff_args)
    if code != 0 and base_ref:
        code, out, _ = run_git(repo_root, ["diff", "--unified=0", "--", relative_path])
    if code != 0:
        return set()

    changed_lines: set[int] = set()
    for line in out.splitlines():
        m = HUNK_RE.match(line)
        if not m:
            continue
        start = int(m.group(1))
        length = int(m.group(2) or "1")
        for ln in range(start, start + max(length, 1)):
            changed_lines.add(ln)
    return changed_lines


def excluded_preview_lines(lines: list[str]) -> tuple[set[int], list[int]]:
    excluded: set[int] = set()
    anchors: list[int] = []
    i = 0
    total = len(lines)
    while i < total:
        line = lines[i]
        if "#Preview" in line or PREVIEW_PROVIDER_RE.search(line):
            anchors.append(i + 1)
            depth = 0
            started = False
            j = i
            while j < total:
                current = lines[j]
                open_count = current.count("{")
                close_count = current.count("}")
                if open_count > 0:
                    started = True
                depth += open_count - close_count
                excluded.add(j + 1)
                if started and depth <= 0:
                    break
                j += 1
            i = max(j + 1, i + 1)
            continue
        i += 1
    return excluded, anchors


def nav_mod_annotation_status(lines: list[str], line_no: int) -> tuple[bool, str]:
    start = max(1, line_no - 3)
    for idx in range(start, line_no + 1):
        match = NAV_MOD_ANY_RE.search(lines[idx - 1])
        if not match:
            continue
        mod_id = match.group(1)
        if mod_id in VALID_MOD_IDS:
            return True, ""
        valid_ids = ", ".join(sorted(VALID_MOD_IDS))
        return False, f"Invalid NAV-MOD decision annotation '{mod_id}' (expected one of: {valid_ids})"
    return False, "Missing NAV-MOD decision annotation near modal call-site"


def has_active_code_outside_preview(lines: list[str], excluded: set[int]) -> bool:
    for idx, raw in enumerate(lines, start=1):
        if idx in excluded:
            continue
        code = raw.split("//", 1)[0].strip()
        if code:
            return True
    return False


def normalize_rel(path: Path, repo_root: Path) -> str:
    return path.relative_to(repo_root).as_posix()


def gather_swift_files(repo_root: Path, roots: list[str], changed: set[str] | None) -> list[Path]:
    files: list[Path] = []
    for root in roots:
        base = repo_root / root
        if not base.exists():
            continue
        for path in sorted(base.rglob("*.swift")):
            rel = normalize_rel(path, repo_root)
            if changed is not None and rel not in changed:
                continue
            files.append(path)
    return files


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--roots",
        nargs="+",
        default=["ios/CryptoSavingsTracker/Views", "ios/CryptoSavingsTracker/Navigation"],
        help="Project roots to scan for .swift files",
    )
    parser.add_argument("--changed-only", action="store_true")
    parser.add_argument("--base-ref", default=None, help="Git base ref for changed-only mode")
    parser.add_argument("--strict-mod-tags", action="store_true")
    parser.add_argument("--strict-preview-segregation", action="store_true")
    parser.add_argument(
        "--allowlist",
        default=None,
        help="Optional JSON allowlist file (relative to repo root)",
    )
    parser.add_argument("--report-out", default="artifacts/navigation/policy-report.json")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    allowlist = load_allowlist(repo_root, args.allowlist)
    changed_files = list_changed_files(repo_root, args.base_ref) if args.changed_only else None
    candidates = gather_swift_files(repo_root, args.roots, changed_files)

    issues: list[Finding] = []
    warnings: list[Finding] = []
    scanned_files: list[str] = []
    allowlisted_count = 0

    for file_path in candidates:
        rel = normalize_rel(file_path, repo_root)
        scanned_files.append(rel)
        text = file_path.read_text(encoding="utf-8")
        lines = text.splitlines()
        excluded, preview_anchors = excluded_preview_lines(lines)
        changed_lines = (
            changed_lines_for_file(repo_root, rel, args.base_ref) if args.changed_only else None
        )

        # NAV003 fallback path from proposal/ADR:
        # If preview and active declarations coexist in one file, previews must be split
        # into *Preview*.swift when strict mode is enabled.
        if preview_anchors and has_active_code_outside_preview(lines, excluded):
            if not file_path.name.endswith("Preview.swift"):
                finding = Finding(
                    "NAV003",
                    rel,
                    preview_anchors[0],
                    "Preview and active declarations are mixed in one file",
                    "Extract #Preview/PreviewProvider into dedicated *Preview*.swift file",
                )
                if is_allowlisted(allowlist, "NAV003", rel):
                    allowlisted_count += 1
                    finding.message = f"{finding.message} (allowlisted)"
                    warnings.append(finding)
                elif args.strict_preview_segregation:
                    issues.append(finding)
                else:
                    warnings.append(finding)

        for idx, raw in enumerate(lines, start=1):
            if idx in excluded:
                continue
            code = raw.split("//", 1)[0]
            if not code.strip():
                continue

            for rule_id, pattern, msg in FORBIDDEN_RULES:
                if pattern.search(code):
                    issues.append(
                        Finding(
                            rule_id,
                            rel,
                            idx,
                            msg,
                            "Replace with NavigationStack/confirmationDialog and modern navigation APIs",
                        )
                    )

            if MODAL_CALL_RE.search(code):
                if args.changed_only and changed_lines is not None and idx not in changed_lines:
                    continue
                valid, message = nav_mod_annotation_status(lines, idx)
                if not valid:
                    finding = Finding("NAV002", rel, idx, message, "Add // NAV-MOD: MOD-0x near this call-site")
                    if is_allowlisted(allowlist, "NAV002", rel):
                        allowlisted_count += 1
                        finding.message = f"{finding.message} (allowlisted)"
                        warnings.append(finding)
                    elif args.strict_mod_tags:
                        issues.append(finding)
                    else:
                        warnings.append(finding)

    report = {
        "passed": len(issues) == 0,
        "changedOnly": args.changed_only,
        "baseRef": args.base_ref,
        "strictModTags": args.strict_mod_tags,
        "strictPreviewSegregation": args.strict_preview_segregation,
        "allowlistPath": args.allowlist,
        "allowlistedCount": allowlisted_count,
        "scannedFileCount": len(scanned_files),
        "scannedFiles": scanned_files,
        "issueCount": len(issues),
        "warningCount": len(warnings),
        "issues": [finding.__dict__ for finding in issues],
        "warnings": [finding.__dict__ for finding in warnings],
    }

    report_path = repo_root / args.report_out
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    if issues:
        print("navigation policy check failed:")
        for issue in issues:
            print(f"- {issue.rule_id} {issue.file}:{issue.line} {issue.message}")
        print(f"report: {report_path}")
        return 1

    print("navigation policy check passed")
    if warnings:
        print("warnings:")
        for warning in warnings:
            print(f"- {warning.rule_id} {warning.file}:{warning.line} {warning.message}")
    print(f"report: {report_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

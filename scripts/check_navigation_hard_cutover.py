#!/usr/bin/env python3
"""Enforce hard-cutover: migration layer must not appear in active runtime code."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


FORBIDDEN_PATTERNS: list[tuple[str, re.Pattern[str], str]] = [
    (
        "CUT001",
        re.compile(r"\bNavigationMigration(?:Module|Registry|Evaluator|Resolution|Snapshot|Source|RemoteOverrideProvider)?\b"),
        "Navigation migration type reference is forbidden after hard cutover",
    ),
    (
        "CUT001",
        re.compile(r"\bnavigationMigration(?:Registry|Evaluator|RemoteOverrideProvider)\b"),
        "Navigation migration dependency/property reference is forbidden after hard cutover",
    ),
    (
        "CUT001",
        re.compile(r"\bmigrationEnabled\b"),
        "`migrationEnabled` branching is forbidden after hard cutover",
    ),
    (
        "CUT001",
        re.compile(r"nav\.migration\."),
        "Legacy migration key namespace is forbidden after hard cutover",
    ),
    (
        "CUT001",
        re.compile(r"\bisModuleEnabled\s*\("),
        "Module migration evaluator checks are forbidden after hard cutover",
    ),
]


@dataclass
class Finding:
    rule_id: str
    file: str
    line: int
    message: str
    snippet: str


def run_git(repo_root: Path, args: list[str]) -> tuple[int, str]:
    proc = subprocess.run(
        ["git", *args],
        cwd=repo_root,
        text=True,
        capture_output=True,
        check=False,
    )
    return proc.returncode, proc.stdout


def list_changed_files(repo_root: Path, base_ref: str | None) -> set[str]:
    diff_args = ["diff", "--name-only", "--diff-filter=ACMR"]
    if base_ref:
        diff_args.append(f"{base_ref}...HEAD")
    code, out = run_git(repo_root, diff_args)
    if code != 0 and base_ref:
        code, out = run_git(repo_root, ["diff", "--name-only", "--diff-filter=ACMR"])
    changed = {line.strip() for line in out.splitlines() if line.strip()}

    if not base_ref:
        code, out = run_git(repo_root, ["ls-files", "--others", "--exclude-standard"])
        if code == 0:
            changed.update(line.strip() for line in out.splitlines() if line.strip())
    return changed


def gather_source_files(
    repo_root: Path,
    roots: list[str],
    extensions: set[str],
    changed: set[str] | None,
) -> list[Path]:
    files: list[Path] = []
    for root in roots:
        base = repo_root / root
        if not base.exists():
            continue
        for path in sorted(base.rglob("*")):
            if not path.is_file():
                continue
            if path.suffix not in extensions:
                continue
            if changed is not None:
                try:
                    rel = path.relative_to(repo_root).as_posix()
                except ValueError:
                    # External roots are not representable in git diff, skip in changed-only mode.
                    continue
                if rel not in changed:
                    continue
            files.append(path)
    return files


def display_path(path: Path, repo_root: Path) -> str:
    try:
        return path.relative_to(repo_root).as_posix()
    except ValueError:
        return str(path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--roots",
        nargs="+",
        default=[
            "ios/CryptoSavingsTracker",
            "android/app/src/main/java/com/xax/CryptoSavingsTracker",
        ],
        help="Source roots to scan",
    )
    parser.add_argument(
        "--extensions",
        nargs="+",
        default=[".swift", ".kt", ".kts", ".java"],
        help="File extensions to scan",
    )
    parser.add_argument("--changed-only", action="store_true")
    parser.add_argument("--base-ref", default=None, help="Git base ref for changed-only mode")
    parser.add_argument(
        "--report-out",
        default="artifacts/navigation/hard-cutover-report.json",
        help="Machine-readable report path",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    changed_files = list_changed_files(repo_root, args.base_ref) if args.changed_only else None
    extensions = set(args.extensions)
    candidates = gather_source_files(repo_root, args.roots, extensions, changed_files)

    findings: list[Finding] = []
    scanned_files: list[str] = []

    for file_path in candidates:
        rel = display_path(file_path, repo_root)
        scanned_files.append(rel)
        lines = file_path.read_text(encoding="utf-8").splitlines()
        for line_no, raw in enumerate(lines, start=1):
            code = raw.split("//", 1)[0].strip()
            if not code:
                continue
            for rule_id, pattern, message in FORBIDDEN_PATTERNS:
                if pattern.search(code):
                    findings.append(
                        Finding(
                            rule_id=rule_id,
                            file=rel,
                            line=line_no,
                            message=message,
                            snippet=code[:200],
                        )
                    )

    report = {
        "passed": len(findings) == 0,
        "changedOnly": args.changed_only,
        "baseRef": args.base_ref,
        "roots": args.roots,
        "extensions": sorted(extensions),
        "scannedFileCount": len(scanned_files),
        "scannedFiles": scanned_files,
        "issueCount": len(findings),
        "issues": [finding.__dict__ for finding in findings],
    }

    out_path = repo_root / args.report_out
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    if findings:
        print("navigation hard-cutover check failed:")
        for item in findings:
            print(f"- {item.file}:{item.line} [{item.rule_id}] {item.message} :: {item.snippet}")
        print(f"report: {out_path}")
        return 1

    print("navigation hard-cutover check passed")
    print(f"report: {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

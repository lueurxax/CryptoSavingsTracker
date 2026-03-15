#!/usr/bin/env python3
"""Validate targeted planning/form copy contracts against the shared financial copy dictionary."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import asdict, dataclass
from pathlib import Path


DICTIONARY_PATH = Path("docs/copy/FINANCIAL_COPY_DICTIONARY.md")

PLACEHOLDER_SOURCE_PATTERNS = {
    "month": r"(?:\\\(.+\)|\$\{[^}]+\}|\$[A-Za-z_][A-Za-z0-9_]*)",
}

STRING_LITERAL_PATTERN = re.compile(r'"((?:[^"\\]|\\.)*)"')

AUDITED_FILE_SCOPES: dict[str, tuple[str, ...]] = {
    "ios/CryptoSavingsTracker/Views/Planning/BudgetSummaryCard.swift": ("planning_budget_not_applied",),
    "ios/CryptoSavingsTracker/Views/Planning/CompactGoalRequirementRow.swift": ("planning_goals_changed_review_plan",),
    "ios/CryptoSavingsTracker/Views/Planning/MonthlyPlanningContainer.swift": ("planning_finish_month_cta",),
    "ios/CryptoSavingsTracker/Views/AddGoalView.swift": ("goal_form_save_error_retry",),
    "ios/CryptoSavingsTracker/Views/EditGoalView.swift": ("goal_form_save_error_retry",),
    "android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/planning/components/BudgetCalculatorComponents.kt": (
        "planning_budget_not_applied",
    ),
    "android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/planning/MonthlyPlanningScreen.kt": (
        "planning_goals_changed_review_plan",
    ),
    "android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/planning/MonthlyPlanningContainer.kt": (
        "planning_finish_month_cta",
    ),
}

AUDITED_LITERAL_DETECTORS = {
    "planning_budget_not_applied": re.compile(r"budget saved|not applied to this month", re.IGNORECASE),
    "planning_goals_changed_review_plan": re.compile(r"review this plan|recalcul", re.IGNORECASE),
    "planning_finish_month_cta": re.compile(r"^finish\b|close month", re.IGNORECASE),
    "goal_form_save_error_retry": re.compile(r"unable to save this goal|please try again", re.IGNORECASE),
}

ALLOWED_LITERAL_VARIANTS = {
    "planning_finish_month_cta": [
        re.compile(r"^Finish (?:\\\(.+\)|\$\{[^}]+\}|\$[A-Za-z_][A-Za-z0-9_]*)\?$"),
    ],
}

IGNORED_LITERAL_PATTERNS = [
    re.compile(r"^[A-Za-z0-9_.-]+$"),
    re.compile(r"^[a-z]+(?:[A-Z][a-z0-9]+)+$"),
]


@dataclass
class GateResult:
    gate_id: str
    passed: bool
    details: str


@dataclass
class DictionaryEntry:
    key: str
    wording: str
    scope: str
    target_platforms: list[str]
    ios_paths: list[str]
    android_paths: list[str]
    notes: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", default=".", help="Repository root")
    parser.add_argument("--report-out", help="Optional JSON report output path")
    return parser.parse_args()


def split_paths(raw: str) -> list[str]:
    normalized = raw.replace("<br>", ";").replace("<br/>", ";")
    return [item.strip().strip("`") for item in normalized.split(";") if item.strip() and item.strip() != "-"]


def is_placeholder_path(raw: str) -> bool:
    return raw.strip().strip("`") in {"", "-", "—"}


def parse_dictionary(path: Path) -> list[DictionaryEntry]:
    if not path.exists():
        raise FileNotFoundError(f"Missing dictionary file: {path}")

    lines = path.read_text(encoding="utf-8").splitlines()
    rows = [line for line in lines if line.startswith("|")]
    if len(rows) < 3:
        raise ValueError("Dictionary table is missing or malformed")

    entries: list[DictionaryEntry] = []
    for row in rows[2:]:
        parts = [part.strip() for part in row.strip("|").split("|")]
        if len(parts) != 7:
            raise ValueError(f"Malformed dictionary row: {row}")

        key, wording, scope, platforms, ios_paths, android_paths, notes = parts
        entries.append(
            DictionaryEntry(
                key=key.strip("`"),
                wording=wording.strip("`"),
                scope=scope.strip("`"),
                target_platforms=[item.strip() for item in platforms.strip("`").split(",") if item.strip()],
                ios_paths=split_paths(ios_paths),
                android_paths=split_paths(android_paths),
                notes=notes,
            )
        )
    return entries


def compile_wording_pattern(wording: str, *, anchored: bool) -> re.Pattern[str]:
    parts: list[str] = []
    cursor = 0
    while cursor < len(wording):
        placeholder_start = wording.find("{", cursor)
        if placeholder_start == -1:
            parts.append(re.escape(wording[cursor:]))
            break

        placeholder_end = wording.find("}", placeholder_start)
        if placeholder_end == -1:
            parts.append(re.escape(wording[cursor:]))
            break

        parts.append(re.escape(wording[cursor:placeholder_start]))
        placeholder_name = wording[placeholder_start + 1:placeholder_end]
        placeholder_pattern = PLACEHOLDER_SOURCE_PATTERNS.get(placeholder_name, re.escape(wording[placeholder_start:placeholder_end + 1]))
        parts.append(placeholder_pattern)
        cursor = placeholder_end + 1

    pattern = "".join(parts)
    if anchored:
        pattern = f"^{pattern}$"
    return re.compile(pattern)


def extract_string_literals(text: str) -> list[str]:
    return [match.group(1) for match in STRING_LITERAL_PATTERN.finditer(text)]


def should_ignore_literal(literal: str) -> bool:
    if not literal.strip():
        return True
    return any(pattern.fullmatch(literal) for pattern in IGNORED_LITERAL_PATTERNS)


def gate_dictionary_shape(entries: list[DictionaryEntry]) -> GateResult:
    issues: list[str] = []
    seen_keys: set[str] = set()

    for entry in entries:
        if entry.key in seen_keys:
            issues.append(f"duplicate key {entry.key}")
        seen_keys.add(entry.key)

        if entry.scope not in {"shared", "platform-specific"}:
            issues.append(f"{entry.key}: invalid scope {entry.scope}")

        if not entry.target_platforms:
            issues.append(f"{entry.key}: missing target platforms")

        if "iOS" in entry.target_platforms and not entry.ios_paths:
            issues.append(f"{entry.key}: missing iOS path")

        if "Android" in entry.target_platforms and not entry.android_paths:
            issues.append(f"{entry.key}: missing Android path")

        if entry.scope == "shared" and {"iOS", "Android"}.issubset(set(entry.target_platforms)):
            if not entry.ios_paths or not entry.android_paths:
                issues.append(f"{entry.key}: shared entry requires both iOS and Android paths")

    return GateResult(
        gate_id="COPY-DICT-001",
        passed=not issues,
        details="Dictionary shape is valid." if not issues else "; ".join(issues),
    )


def gate_paths_exist(repo_root: Path, entries: list[DictionaryEntry]) -> GateResult:
    missing: list[str] = []
    for entry in entries:
        for rel_path in entry.ios_paths + entry.android_paths:
            if is_placeholder_path(rel_path):
                continue
            if not (repo_root / rel_path).exists():
                missing.append(f"{entry.key}:{rel_path}")

    return GateResult(
        gate_id="COPY-PATH-001",
        passed=not missing,
        details="All declared copy paths exist." if not missing else "Missing paths: " + ", ".join(missing),
    )


def gate_wording_presence(repo_root: Path, entries: list[DictionaryEntry]) -> GateResult:
    issues: list[str] = []

    for entry in entries:
        pattern = compile_wording_pattern(entry.wording, anchored=False)
        paths = entry.ios_paths + entry.android_paths
        if not paths:
            issues.append(f"{entry.key}: no paths declared")
            continue

        for rel_path in paths:
            if is_placeholder_path(rel_path):
                continue
            text = (repo_root / rel_path).read_text(encoding="utf-8")
            if pattern.search(text) is None:
                issues.append(f"{entry.key}: wording not found in {rel_path}")

    return GateResult(
        gate_id="COPY-LITERAL-001",
        passed=not issues,
        details="All dictionary entries resolve to declared file paths." if not issues else "; ".join(issues),
    )


def gate_unmanaged_inline_literals(repo_root: Path, entries: list[DictionaryEntry]) -> GateResult:
    issues: list[str] = []
    entries_by_key = {entry.key: entry for entry in entries}

    for rel_path, scoped_keys in AUDITED_FILE_SCOPES.items():
        path = repo_root / rel_path
        if not path.exists():
            issues.append(f"{rel_path}: audited scope path missing")
            continue

        text = path.read_text(encoding="utf-8")
        literals = [literal for literal in extract_string_literals(text) if not should_ignore_literal(literal)]

        for key in scoped_keys:
            entry = entries_by_key.get(key)
            detector = AUDITED_LITERAL_DETECTORS.get(key)
            if entry is None:
                issues.append(f"{rel_path}: missing dictionary entry for audited key {key}")
                continue
            if detector is None:
                issues.append(f"{rel_path}: missing detector for audited key {key}")
                continue

            literal_pattern = compile_wording_pattern(entry.wording, anchored=True)
            allowed_variants = ALLOWED_LITERAL_VARIANTS.get(key, [])
            for literal in literals:
                matches_allowed_variant = any(pattern.fullmatch(literal) for pattern in allowed_variants)
                if detector.search(literal) and literal_pattern.fullmatch(literal) is None and not matches_allowed_variant:
                    issues.append(f"{rel_path}: unmanaged inline literal `{literal}` for {key}")

    return GateResult(
        gate_id="COPY-LITERAL-002",
        passed=not issues,
        details="No unmanaged inline literals were found in audited planning/form surfaces." if not issues else "; ".join(issues),
    )


def main() -> int:
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()

    try:
        entries = parse_dictionary(repo_root / DICTIONARY_PATH)
    except Exception as exc:
        results = [GateResult("COPY-BOOTSTRAP-001", False, str(exc))]
    else:
        results = [
            gate_dictionary_shape(entries),
            gate_paths_exist(repo_root, entries),
            gate_wording_presence(repo_root, entries),
            gate_unmanaged_inline_literals(repo_root, entries),
        ]

    for result in results:
        status = "PASS" if result.passed else "FAIL"
        print(f"[{status}] {result.gate_id}: {result.details}")

    if args.report_out:
        report_path = repo_root / args.report_out
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(
            json.dumps([asdict(result) for result in results], indent=2) + "\n",
            encoding="utf-8",
        )

    return 0 if all(result.passed for result in results) else 1


if __name__ == "__main__":
    sys.exit(main())

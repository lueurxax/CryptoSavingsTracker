#!/usr/bin/env python3
"""Enforce approved_variant expiry controls for visual token governance."""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Any


@dataclass
class Variant:
    role: str
    expires_at: date
    parity: dict[str, Any]


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def parse_date(raw: str, field: str, role: str) -> date:
    try:
        year, month, day = raw.split("-")
        return date(int(year), int(month), int(day))
    except Exception as exc:  # noqa: BLE001
        raise ValueError(f"{role}: invalid {field} date '{raw}'") from exc


def collect_variants(tokens: dict[str, Any]) -> list[Variant]:
    variants: list[Variant] = []
    for role, cfg in tokens.get("roles", {}).items():
        parity = cfg.get("parity", {})
        if parity.get("status") != "approved_variant":
            continue
        expires_raw = parity.get("expiresAt")
        if not isinstance(expires_raw, str):
            raise ValueError(f"{role}: approved_variant requires expiresAt")
        expires_at = parse_date(expires_raw, "expiresAt", role)
        variants.append(Variant(role=role, expires_at=expires_at, parity=parity))
    return variants


def check_variants(
    variants: list[Variant],
    today: date,
    threshold_days: int,
    concentration_min_variants: int,
) -> tuple[list[str], dict[str, Any]]:
    issues: list[str] = []
    by_expiry: dict[str, list[Variant]] = {}

    for variant in variants:
        days_left = (variant.expires_at - today).days
        parity = variant.parity

        if days_left < 0:
            issues.append(f"{variant.role}: approved_variant expired on {variant.expires_at.isoformat()}")

        checkpoint_raw = parity.get("preExpiryCheckpointAt")
        closure_issue = parity.get("closureIssue")
        closure_pr = parity.get("closurePullRequest")

        if days_left <= threshold_days:
            if not closure_pr:
                issues.append(
                    f"{variant.role}: expires in {days_left} days and is missing closurePullRequest"
                )
            if not closure_issue:
                issues.append(
                    f"{variant.role}: expires in {days_left} days and is missing closureIssue"
                )

        if checkpoint_raw:
            checkpoint_date = parse_date(str(checkpoint_raw), "preExpiryCheckpointAt", variant.role)
            if checkpoint_date > variant.expires_at:
                issues.append(
                    f"{variant.role}: preExpiryCheckpointAt must be <= expiresAt "
                    f"({checkpoint_date.isoformat()} > {variant.expires_at.isoformat()})"
                )

        by_expiry.setdefault(variant.expires_at.isoformat(), []).append(variant)

    for expiry, group in by_expiry.items():
        if len(group) < concentration_min_variants:
            continue
        for variant in group:
            parity = variant.parity
            if not parity.get("preExpiryCheckpointAt"):
                issues.append(
                    f"{variant.role}: expiry {expiry} is concentrated ({len(group)} variants) "
                    "and missing preExpiryCheckpointAt"
                )
            if not parity.get("closureIssue"):
                issues.append(
                    f"{variant.role}: expiry {expiry} is concentrated ({len(group)} variants) "
                    "and missing closureIssue"
                )

    summary = {
        "today": today.isoformat(),
        "variantCount": len(variants),
        "thresholdDays": threshold_days,
        "concentrationMinVariants": concentration_min_variants,
        "groups": {
            expiry: [variant.role for variant in group]
            for expiry, group in sorted(by_expiry.items(), key=lambda x: x[0])
        },
    }
    return issues, summary


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tokens", default="docs/design/visual-tokens.v1.json")
    parser.add_argument("--threshold-days", type=int, default=30)
    parser.add_argument("--concentration-min-variants", type=int, default=3)
    parser.add_argument(
        "--today",
        help="Override current date in YYYY-MM-DD format",
    )
    parser.add_argument(
        "--report-out",
        default="artifacts/visual-system/variant-expiry-report.json",
    )
    args = parser.parse_args()

    token_path = Path(args.tokens)
    if not token_path.exists():
        print(f"error: token file not found: {token_path}")
        return 2

    today = date.today() if not args.today else parse_date(args.today, "today", "global")

    try:
        tokens = load_json(token_path)
        variants = collect_variants(tokens)
        issues, summary = check_variants(
            variants=variants,
            today=today,
            threshold_days=args.threshold_days,
            concentration_min_variants=args.concentration_min_variants,
        )
    except ValueError as exc:
        print(f"error: {exc}")
        return 2

    report = {
        "tokensPath": str(token_path),
        "passed": len(issues) == 0,
        "issueCount": len(issues),
        "summary": summary,
        "issues": issues,
    }

    report_path = Path(args.report_out)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    if issues:
        print("approved_variant expiry checks failed:")
        for issue in issues:
            print(f"- {issue}")
        print(f"report: {report_path}")
        return 1

    print("approved_variant expiry checks passed")
    print(f"report: {report_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Deterministic parity checker for cross-platform visual token roles."""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Any


@dataclass
class Issue:
    role: str
    message: str


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def parse_date(value: str) -> date:
    year, month, day = value.split("-")
    return date(int(year), int(month), int(day))


def compare_aligned_specs(
    role: str, role_type: str, ios_spec: dict[str, Any], android_spec: dict[str, Any]
) -> list[Issue]:
    issues: list[Issue] = []
    field_map = {
        "color": ("light", "dark", "alpha", "nonColorCueRequired"),
        "surface": ("lightStyle", "darkStyle", "strokeToken", "shadowPreset"),
        "elevation": ("defaultDp", "pressedDp"),
    }
    fields = field_map.get(role_type)
    if fields is None:
        issues.append(Issue(role, f"unsupported roleType for aligned comparison: {role_type}"))
        return issues

    for field in fields:
        ios_value = ios_spec.get(field)
        android_value = android_spec.get(field)
        if ios_value != android_value:
            issues.append(
                Issue(
                    role,
                    f"aligned role mismatch for '{field}' ({ios_value!r} vs {android_value!r})",
                )
            )

    return issues


def check_parity(tokens: dict[str, Any], today: date) -> list[Issue]:
    issues: list[Issue] = []
    roles = tokens["roles"]

    for role, cfg in roles.items():
        parity = cfg["parity"]
        status = parity["status"]

        if status == "approved_variant":
            expires_at = parse_date(parity["expiresAt"])
            if expires_at < today:
                issues.append(Issue(role, f"approved_variant expired at {expires_at.isoformat()}"))

        ios = cfg["ios"]
        android = cfg["android"]
        ios_spec = ios["spec"]
        android_spec = android["spec"]

        if ios_spec["kind"] != android_spec["kind"]:
            issues.append(Issue(role, "platform spec kinds differ"))

        role_type = cfg["roleType"]
        if status == "aligned":
            issues.extend(compare_aligned_specs(role, role_type, ios_spec, android_spec))

        if role_type == "elevation":
            ios_default = float(ios_spec["defaultDp"])
            android_default = float(android_spec["defaultDp"])
            if abs(ios_default - android_default) > 2.0 and status != "approved_variant":
                issues.append(
                    Issue(
                        role,
                        f"defaultDp delta too high without approved variant ({ios_default} vs {android_default})",
                    )
                )

    return issues


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--tokens",
        default="docs/design/visual-tokens.v1.json",
        help="Path to token contract JSON",
    )
    args = parser.parse_args()

    token_path = Path(args.tokens)
    if not token_path.exists():
        print(f"error: token file not found: {token_path}")
        return 2

    tokens = load_json(token_path)
    today = date.today()
    issues = check_parity(tokens, today)

    if issues:
        print("visual token parity check failed:")
        for issue in issues:
            print(f"- {issue.role}: {issue.message}")
        return 1

    print("visual token parity check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())

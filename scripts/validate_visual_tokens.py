#!/usr/bin/env python3
"""Validate visual token contract against strict schema and semantic invariants."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def validate_schema(data: dict[str, Any], schema: dict[str, Any]) -> list[str]:
    validator = Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(data), key=lambda e: list(e.path))
    messages: list[str] = []
    for err in errors:
        path = ".".join(str(x) for x in err.path)
        messages.append(f"schema: {path or '<root>'}: {err.message}")
    return messages


def validate_semantics(data: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    required_states = [
        "default",
        "pressed",
        "disabled",
        "error",
        "loading",
        "empty",
        "stale",
        "recovery",
    ]

    if data.get("requiredStates") != required_states:
        errors.append(
            "semantic: requiredStates must exactly match canonical order "
            "[default, pressed, disabled, error, loading, empty, stale, recovery]"
        )

    roles = data.get("roles", {})
    for role_name, role_data in roles.items():
        role_type = role_data["roleType"]
        ios_kind = role_data["ios"]["spec"]["kind"]
        android_kind = role_data["android"]["spec"]["kind"]

        if ios_kind != role_type:
            errors.append(
                f"semantic: roles.{role_name}.ios.spec.kind={ios_kind} must match roleType={role_type}"
            )
        if android_kind != role_type:
            errors.append(
                f"semantic: roles.{role_name}.android.spec.kind={android_kind} must match roleType={role_type}"
            )

        parity = role_data["parity"]
        status = parity["status"]
        if status not in {"aligned", "approved_variant"}:
            errors.append(
                f"semantic: roles.{role_name}.parity.status={status} is invalid"
            )

    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--tokens",
        default="docs/design/visual-tokens.v1.json",
        help="Path to token contract JSON",
    )
    parser.add_argument(
        "--schema",
        default="docs/design/schemas/visual-tokens.schema.json",
        help="Path to JSON schema",
    )
    args = parser.parse_args()

    tokens_path = Path(args.tokens)
    schema_path = Path(args.schema)

    if not tokens_path.exists():
        print(f"error: token file not found: {tokens_path}")
        return 2
    if not schema_path.exists():
        print(f"error: schema file not found: {schema_path}")
        return 2

    tokens = load_json(tokens_path)
    schema = load_json(schema_path)

    issues = validate_schema(tokens, schema)
    issues.extend(validate_semantics(tokens))

    if issues:
        print("visual token contract validation failed:")
        for issue in issues:
            print(f"- {issue}")
        return 1

    print("visual token contract validation passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())

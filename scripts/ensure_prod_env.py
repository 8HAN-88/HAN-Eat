#!/usr/bin/env python3
"""Keep production .env able to boot: no debug, no skip-Google, no default JWT secret."""
from __future__ import annotations

import argparse
import secrets
from pathlib import Path

WEAK_SECRETS = {
    "dev-only-change-with-SECRET_KEY-env-in-production",
    "changeme",
    "change-me",
    "changethis",
    "secret",
    "password",
    "your-secret-key",
}


def _parse_env(text: str) -> list[str]:
    return text.splitlines()


def _get(lines: list[str], key: str) -> tuple[int | None, str]:
    prefix = f"{key}="
    for i, line in enumerate(lines):
        if line.startswith(prefix):
            return i, line.split("=", 1)[1].strip().strip("'\"")
    return None, ""


def _set(lines: list[str], key: str, value: str) -> None:
    idx, _ = _get(lines, key)
    row = f"{key}={value}"
    if idx is None:
        lines.append(row)
    else:
        lines[idx] = row


def secret_is_weak(value: str) -> bool:
    current = (value or "").strip()
    if not current or len(current) < 32:
        return True
    lowered = current.lower()
    if lowered in {item.lower() for item in WEAK_SECRETS}:
        return True
    return lowered.startswith("dev-only") or lowered.startswith("changeme")


def ensure_prod_env(path: Path) -> list[str]:
    lines = _parse_env(path.read_text() if path.exists() else "")
    notes: list[str] = []

    _set(lines, "APP_ENV", "production")
    _set(lines, "DEBUG", "false")
    _set(lines, "SKIP_GOOGLE_ID_TOKEN_VERIFICATION", "false")
    _set(lines, "API_PUBLIC_BASE_URL", "https://api.haneat.app")

    _, secret = _get(lines, "SECRET_KEY")
    if secret_is_weak(secret):
        _set(lines, "SECRET_KEY", secrets.token_urlsafe(48))
        notes.append("SECRET_KEY replaced (was default/short)")
    else:
        notes.append("SECRET_KEY kept")

    path.write_text("\n".join(lines).rstrip() + "\n")
    return notes


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("env_path", nargs="?", default=".env")
    args = parser.parse_args()
    path = Path(args.env_path)
    for note in ensure_prod_env(path):
        print(f"ensure_prod_env: {note}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

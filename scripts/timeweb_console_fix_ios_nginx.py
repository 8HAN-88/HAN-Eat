#!/usr/bin/env python3
"""Fix nginx so iPhone can boot HAN Eat web.

Run on Timeweb console (Serial / VNC):

  python3 <<'PY'
  # paste file contents OR:
  # curl -fsSL -o /tmp/fix_ios.py URL && python3 /tmp/fix_ios.py
  PY
  nginx -t && systemctl reload nginx
"""
from __future__ import annotations

import re
from pathlib import Path

CONF = Path("/etc/nginx/sites-available/haneat-web")
BEGIN = "# BEGIN HAN-EAT IOS FIX"
END = "# END HAN-EAT IOS FIX"

BLOCK = f"""
    {BEGIN}
    location = / {{
        try_files /index.html =404;
        default_type text/html;
        add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0" always;
        add_header Clear-Site-Data '"cache"' always;
    }}
    location = /index.html {{
        try_files /index.html =404;
        default_type text/html;
        add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0" always;
        add_header Clear-Site-Data '"cache"' always;
    }}
    location = /fresh {{
        add_header Clear-Site-Data '"cache", "storage", "executionContexts"' always;
        add_header Cache-Control "no-store" always;
        return 302 /?fresh=1;
    }}
    location ^~ /assets/ {{ return 302 /app$request_uri; }}
    location ^~ /canvaskit/ {{ return 302 /app$request_uri; }}
    location ^~ /icons/ {{ return 302 /app$request_uri; }}
    location ^~ /main.dart.js {{ return 302 /app$request_uri; }}
    location = /flutter_bootstrap.js {{ return 302 /app/flutter_bootstrap.js; }}
    location = /flutter.js {{ return 302 /app/flutter.js; }}
    location = /flutter_service_worker.js {{ return 302 /app/flutter_service_worker.js; }}
    location = /manifest.json {{ return 302 /app/manifest.json; }}
    location = /favicon.png {{ return 302 /app/favicon.png; }}
    {END}
"""


def strip_conflicting_locations(text: str) -> str:
    """Remove previous exact locations that would duplicate after insert."""
    patterns = [
        r"\n\s*location\s*=\s*/\s*\{.*?\n\s*\}\n",
        r"\n\s*location\s*=\s*/index\.html\s*\{.*?\n\s*\}\n",
        r"\n\s*location\s*=\s*/fresh\s*\{.*?\n\s*\}\n",
        r"\n\s*location\s*\^~\s*/assets/\s*\{.*?\n\s*\}\n",
        r"\n\s*location\s*\^~\s*/canvaskit/\s*\{.*?\n\s*\}\n",
        r"\n\s*location\s*\^~\s*/icons/\s*\{.*?\n\s*\}\n",
        r"\n\s*location\s*\^~\s*/main\.dart\.js\s*\{.*?\n\s*\}\n",
        r"\n\s*location\s*=\s*/flutter_bootstrap\.js\s*\{.*?\n\s*\}\n",
        r"\n\s*location\s*=\s*/flutter\.js\s*\{.*?\n\s*\}\n",
        r"\n\s*location\s*=\s*/flutter_service_worker\.js\s*\{.*?\n\s*\}\n",
        r"\n\s*location\s*=\s*/manifest\.json\s*\{.*?\n\s*\}\n",
        r"\n\s*location\s*=\s*/favicon\.png\s*\{.*?\n\s*\}\n",
    ]
    out = text
    # Remove prior IOS FIX block first.
    out = re.sub(
        rf"\n\s*{re.escape(BEGIN)}.*?{re.escape(END)}\n",
        "\n",
        out,
        flags=re.DOTALL,
    )
    for pat in patterns:
        # Only strip unmanaged duplicates carefully: keep /app/assets etc.
        # These patterns are exact root locations.
        out = re.sub(pat, "\n", out, flags=re.DOTALL)
    return out


def main() -> None:
    if not CONF.exists():
        raise SystemExit(f"missing {CONF}")

    original = CONF.read_text(encoding="utf-8")
    bak = Path(str(CONF) + ".bak-ios")
    bak.write_text(original, encoding="utf-8")

    text = strip_conflicting_locations(original)

    # Also rewrite generic SPA fallback at root.
    text = re.sub(
        r"location\s*/\s*\{\s*try_files\s+\$uri\s+\$uri/\s+/index\.html;\s*(?:add_header\s+Cache-Control\s+\"no-cache\";\s*)?\}",
        "location / {\n        return 302 /app$request_uri;\n    }",
        text,
        count=1,
        flags=re.DOTALL,
    )

    anchor = "    location /api/"
    idx = text.find(anchor)
    if idx < 0:
        raise SystemExit("anchor location /api/ not found")
    text = text[:idx] + BLOCK + "\n" + text[idx:]

    CONF.write_text(text, encoding="utf-8")
    print(f"backup: {bak}")
    print(f"patched: {CONF}")
    print("NEXT: nginx -t && systemctl reload nginx")
    print("CHECK: curl -sSI https://haneat.app/ | head -12")
    print("CHECK: curl -sSI https://haneat.app/assets/assets/brand_logo.png | head -12")


if __name__ == "__main__":
    main()

"""HTML-страницы для ссылок из писем → deep link haneat:// в приложение."""
from __future__ import annotations

import html
from urllib.parse import quote

from app.core.config import settings

_BRAND = "#FF6B35"
_BG = "#0E1116"


def email_web_link(purpose: str, raw_token: str) -> str:
    """HTTPS-ссылка для кнопки в письме (открывается в браузере Gmail)."""
    base = (settings.AUTH_EMAIL_WEB_BASE_URL or "").strip()
    if not base:
        base = f"{settings.API_PUBLIC_BASE_URL.rstrip('/')}/api/v1/auth/open"
    return f"{base.rstrip('/')}/{purpose}?token={quote(raw_token, safe='')}"


def deep_link(purpose: str, raw_token: str) -> str:
    base = settings.AUTH_LINK_BASE_URL.rstrip("/")
    return f"{base}/{purpose}?token={quote(raw_token, safe='')}"


def render_open_link_page(purpose: str, raw_token: str) -> str:
    deep = deep_link(purpose, raw_token)
    safe_deep = html.escape(deep, quote=True)
    safe_token = html.escape(raw_token, quote=False)

    titles = {
        "reset-password": "Сброс пароля",
        "verify-email": "Подтверждение email",
        "confirm-email-change": "Смена email",
    }
    cta = {
        "reset-password": "Открыть в HAN Eat",
        "verify-email": "Подтвердить в приложении",
        "confirm-email-change": "Подтвердить в приложении",
    }
    title = titles.get(purpose, "HAN Eat")
    button = cta.get(purpose, "Открыть приложение")

    return f"""<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(title)} — HAN Eat</title>
  <style>
    body {{
      margin: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: #f3f5f8; color: #1a1d24; padding: 24px 16px;
    }}
    .card {{
      max-width: 420px; margin: 0 auto; background: #fff; border-radius: 16px;
      padding: 28px 24px; box-shadow: 0 4px 24px rgba(0,0,0,.08);
    }}
    .logo {{
      background: {_BG}; color: #fff; text-align: center; padding: 16px;
      border-radius: 12px; margin-bottom: 24px; font-weight: 700; font-size: 18px;
    }}
    .logo span {{ color: {_BRAND}; }}
    h1 {{ font-size: 20px; margin: 0 0 12px; }}
    p {{ font-size: 15px; line-height: 1.5; color: #5c6573; margin: 0 0 16px; }}
    .btn {{
      display: block; text-align: center; background: {_BRAND}; color: #fff !important;
      text-decoration: none; padding: 14px 20px; border-radius: 10px;
      font-weight: 600; font-size: 16px; margin: 20px 0;
    }}
    code {{
      display: block; word-break: break-all; background: #f3f5f8; padding: 12px;
      border-radius: 8px; font-size: 12px; margin-top: 8px;
    }}
  </style>
</head>
<body>
  <div class="card">
    <div class="logo">H<span>.</span>A<span>.</span>N. Eat</div>
    <h1>{html.escape(title)}</h1>
    <p>Нажмите кнопку ниже — откроется приложение HAN Eat на этом телефоне.</p>
    <a class="btn" href="{safe_deep}" id="open-app">{html.escape(button)}</a>
    <p style="font-size:13px;">Если кнопка не сработала, откройте приложение вручную → «Новый пароль» / «Код из письма» и вставьте:</p>
    <code id="token">{safe_token}</code>
  </div>
  <script>
    (function() {{
      var deep = {json_deep};
      try {{
        window.location.replace(deep);
      }} catch (e) {{}}
    }})();
  </script>
</body>
</html>""".replace(
        "{json_deep}", repr(deep)
    )

"""HTML-шаблоны транзакционных писем HAN Eat (совместимость с Gmail, Apple Mail)."""
from __future__ import annotations

import html
from typing import Optional

# Бренд приложения (lib/core/theme/color_schemes.dart)
_BRAND_PRIMARY = "#FF6B35"
_BRAND_PRIMARY_DARK = "#E85A2B"
_BG_PAGE = "#F3F5F8"
_BG_CARD = "#FFFFFF"
_BG_HEADER = "#0E1116"
_TEXT_MAIN = "#1A1D24"
_TEXT_MUTED = "#5C6573"
_TEXT_ON_DARK = "#FFFFFF"
_BORDER = "#E9ECF1"


def _esc(value: str) -> str:
    return html.escape(value, quote=True)


def render_branded_email(
    *,
    preheader: str,
    title: str,
    greeting: Optional[str],
    paragraphs: list[str],
    cta_label: str,
    cta_url: str,
    expiry_note: Optional[str] = None,
    security_note: str = (
        "Если вы не запрашивали это письмо, просто проигнорируйте его — "
        "пароль и доступ к аккаунту не изменятся."
    ),
) -> tuple[str, str]:
    """Возвращает (plain_text, html)."""
    greeting_block = ""
    if greeting:
        greeting_block = (
            f'<p style="margin:0 0 16px;font-size:16px;line-height:24px;color:{_TEXT_MAIN};">'
            f"{_esc(greeting)}</p>"
        )

    body_paragraphs = "".join(
        f'<p style="margin:0 0 12px;font-size:15px;line-height:22px;color:{_TEXT_MUTED};">'
        f"{_esc(p)}</p>"
        for p in paragraphs
    )

    expiry_html = ""
    if expiry_note:
        expiry_html = (
            f'<p style="margin:16px 0 0;font-size:13px;line-height:20px;color:{_TEXT_MUTED};">'
            f"⏱ {_esc(expiry_note)}</p>"
        )

    safe_url = _esc(cta_url)
    safe_cta = _esc(cta_label)
    safe_title = _esc(title)
    safe_preheader = _esc(preheader)

    html_doc = f"""<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{safe_title}</title>
</head>
<body style="margin:0;padding:0;background:{_BG_PAGE};font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">
    {safe_preheader}
  </div>
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:{_BG_PAGE};padding:32px 16px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:560px;">
          <tr>
            <td style="background:{_BG_HEADER};border-radius:16px 16px 0 0;padding:28px 32px;text-align:center;">
              <div style="font-size:22px;font-weight:700;color:{_TEXT_ON_DARK};letter-spacing:-0.3px;">
                H<span style="color:{_BRAND_PRIMARY};">.</span>A<span style="color:{_BRAND_PRIMARY};">.</span>N. Eat
              </div>
              <div style="margin-top:8px;font-size:13px;color:#9CA3AF;">Умный помощник в мире еды</div>
            </td>
          </tr>
          <tr>
            <td style="background:{_BG_CARD};padding:32px;border-left:1px solid {_BORDER};border-right:1px solid {_BORDER};">
              <h1 style="margin:0 0 20px;font-size:22px;line-height:28px;font-weight:700;color:{_TEXT_MAIN};">
                {safe_title}
              </h1>
              {greeting_block}
              {body_paragraphs}
              <table role="presentation" cellspacing="0" cellpadding="0" style="margin:28px 0 8px;">
                <tr>
                  <td style="border-radius:10px;background:{_BRAND_PRIMARY};">
                    <a href="{safe_url}" target="_blank" rel="noopener"
                       style="display:inline-block;padding:14px 28px;font-size:16px;font-weight:600;color:#FFFFFF;text-decoration:none;">
                      {safe_cta}
                    </a>
                  </td>
                </tr>
              </table>
              {expiry_html}
              <p style="margin:24px 0 0;font-size:13px;line-height:20px;color:{_TEXT_MUTED};">
                Кнопка не работает? Скопируйте ссылку в браузер на телефоне с приложением HAN Eat:
              </p>
              <p style="margin:8px 0 0;font-size:12px;line-height:18px;word-break:break-all;">
                <a href="{safe_url}" style="color:{_BRAND_PRIMARY_DARK};">{safe_url}</a>
              </p>
            </td>
          </tr>
          <tr>
            <td style="background:{_BG_CARD};padding:0 32px 28px;border-left:1px solid {_BORDER};border-right:1px solid {_BORDER};border-bottom:1px solid {_BORDER};border-radius:0 0 16px 16px;">
              <p style="margin:0;font-size:12px;line-height:18px;color:{_TEXT_MUTED};">
                {_esc(security_note)}
              </p>
            </td>
          </tr>
          <tr>
            <td style="padding:24px 8px;text-align:center;">
              <p style="margin:0;font-size:11px;line-height:16px;color:#9CA3AF;">
                © HAN Eat · Это автоматическое письмо, отвечать на него не нужно.
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>"""

    plain_parts = [title, ""]
    if greeting:
        plain_parts.extend([greeting, ""])
    plain_parts.extend(paragraphs)
    plain_parts.extend(
        [
            "",
            f"{cta_label}:",
            cta_url,
            "",
        ]
    )
    if expiry_note:
        plain_parts.append(expiry_note)
    plain_parts.extend(["", security_note, "", "— HAN Eat"])
    plain_text = "\n".join(plain_parts)

    return plain_text, html_doc

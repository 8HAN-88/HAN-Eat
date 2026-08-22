"""Чеклисты в сообщениях чата (Telegram Premium)."""
from __future__ import annotations

import json
from typing import Any, Dict, List, Optional


def build_checklist_content(title: str, item_texts: List[str]) -> str:
    heading = (title or "").strip()
    items = [t.strip() for t in item_texts if t and t.strip()]
    if len(heading) < 1:
        raise ValueError("checklist_title_required")
    if len(items) < 1:
        raise ValueError("checklist_items_required")
    if len(items) > 20:
        raise ValueError("checklist_too_many_items")
    payload = {
        "checklist": {
            "title": heading[:200],
            "items": [{"text": text[:120], "done": False} for text in items],
        }
    }
    return json.dumps(payload, ensure_ascii=False)


def parse_checklist(content: Optional[str]) -> Optional[Dict[str, Any]]:
    if not content:
        return None
    try:
        data = json.loads(content)
    except Exception:
        return None
    if not isinstance(data, dict):
        return None
    raw = data.get("checklist")
    if not isinstance(raw, dict):
        return None
    title = str(raw.get("title") or "").strip()
    items_raw = raw.get("items")
    if not title or not isinstance(items_raw, list):
        return None
    items = []
    for row in items_raw:
        if not isinstance(row, dict):
            continue
        text = str(row.get("text") or "").strip()
        if not text:
            continue
        items.append({"text": text, "done": bool(row.get("done"))})
    if not items:
        return None
    return {"title": title, "items": items}


def toggle_checklist_item(content: str, index: int, done: bool) -> str:
    parsed = parse_checklist(content)
    if parsed is None:
        raise ValueError("checklist_invalid")
    items = parsed["items"]
    if index < 0 or index >= len(items):
        raise ValueError("checklist_bad_index")
    items[index]["done"] = bool(done)
    payload = {"checklist": {"title": parsed["title"], "items": items}}
    return json.dumps(payload, ensure_ascii=False)


def checklist_preview_text(content: Optional[str]) -> str:
    from app.services.emoji_pack_service import preview_text_with_custom_emoji

    parsed = parse_checklist(content)
    if parsed is None:
        return "Чеклист"
    done = sum(1 for item in parsed["items"] if item["done"])
    total = len(parsed["items"])
    title = preview_text_with_custom_emoji(parsed["title"], limit=80)
    return f"☑ {title} ({done}/{total})"

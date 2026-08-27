"""Custom emoji packs: create, install, send/reaction access."""

from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from typing import Iterable, List, Optional

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.emoji_pack import CustomEmoji, EmojiPack, EmojiPackInstall, EmojiPackPurchase
from app.services.pack_marketplace_service import PackMarketplaceService
from app.services.subscription_service import SubscriptionService

CE_TOKEN_RE = re.compile(r"\[\[e:(\d+)\]\]")
CE_REACTION_RE = re.compile(r"^ce:(\d+)$")


def parse_custom_emoji_ids(text: Optional[str]) -> list[int]:
    ids: list[int] = []
    for match in CE_TOKEN_RE.finditer(text or ""):
        try:
            ids.append(int(match.group(1)))
        except (TypeError, ValueError):
            continue
    return ids


def parse_custom_reaction_id(emoji: Optional[str]) -> Optional[int]:
    match = CE_REACTION_RE.match((emoji or "").strip())
    if not match:
        return None
    try:
        return int(match.group(1))
    except (TypeError, ValueError):
        return None


_INCOMPLETE_CE_SUFFIX_RE = re.compile(r"\[\[e:\d*\]?\]?\s*$")


def clip_preserving_custom_emoji(text: Optional[str], limit: int) -> str:
    """Truncate without slicing a `[[e:id]]` token in half.

    Folder names (64) and similar tight columns used to persist `[[e:12`.
    An incomplete token is dropped so later saves do not store garbage.
    Also drops a trailing `[[e:` / `[[e:12` left by a client maxLength cut.
    """
    raw = text or ""
    if limit <= 0:
        return ""
    clipped = raw if len(raw) <= limit else raw[:limit]
    for match in CE_TOKEN_RE.finditer(raw):
        if match.start() >= limit:
            break
        if match.end() > limit:
            clipped = raw[: match.start()].rstrip()
            break
    incomplete = _INCOMPLETE_CE_SUFFIX_RE.search(clipped)
    if incomplete and not CE_TOKEN_RE.search(incomplete.group(0)):
        return clipped[: incomplete.start()].rstrip()
    return clipped


def preview_text_with_custom_emoji(text: Optional[str], *, limit: int = 120) -> str:
    replaced = CE_TOKEN_RE.sub("✦", text or "").strip()
    if not replaced:
        return "Сообщение"
    return replaced[: max(1, int(limit or 120))]


def strip_custom_emoji_tokens(text: Optional[str]) -> str:
    """Drop `[[e:id]]` tokens without substituting a glyph (OAuth/ASR/headers)."""
    if not text:
        return ""
    cleaned = CE_TOKEN_RE.sub("", text)
    return re.sub(r"\s+", " ", cleaned).strip()


def text_for_external(text: Optional[str]) -> str:
    """Replace `[[e:id]]` with ✦ without truncating or «Сообщение».

    Used when text leaves the chat as input to another service
    (translation, AI moderation). Empty stays empty.
    """
    raw = (text or "").strip()
    if not raw:
        return ""
    return CE_TOKEN_RE.sub("✦", raw).strip()


def text_for_moderation(text: Optional[str]) -> str:
    """Preview tokens for AI/heuristics; empty stays empty (not «Сообщение»)."""
    return text_for_external(text)


def text_for_translation(text: Optional[str]) -> str:
    """Preview tokens for the translator. Reading, not sending — never 403."""
    return text_for_external(text)


def keep_or_preview_tokens(
    svc: "EmojiPackService", user_id: int, text: Optional[str]
) -> Optional[str]:
    """Keep tokens if the actor may send them; otherwise preview.

    Receive-and-persist of someone else's text — do not 403, and do not
    write `[[e:id]]` the actor could not author.
    """
    if not (text or "").strip():
        return text
    try:
        svc.require_send_tokens(user_id, text)
    except ValueError:
        return text_for_external(text) or text
    return text


def keep_if_unchanged(
    svc: "EmojiPackService",
    user_id: int,
    incoming: Optional[str],
    stored: Optional[str],
) -> Optional[str]:
    """Flutter often resends stored text when saving any other field.

    Unchanged → keep-or-preview (no 403). A new string is authored.
    """
    if incoming is None:
        return None
    if (incoming or "").strip() == (stored or "").strip():
        return keep_or_preview_tokens(svc, user_id, incoming)
    svc.require_send_tokens(user_id, incoming)
    return incoming


def keep_if_unchanged_http(
    svc: "EmojiPackService",
    user_id: int,
    incoming: Optional[str],
    stored: Optional[str],
) -> Optional[str]:
    """HTTP wrapper: new tokens become 403, an unchanged resave is previewed."""
    try:
        return keep_if_unchanged(svc, user_id, incoming, stored)
    except ValueError:
        svc.require_send_tokens_http(user_id, incoming)
        return incoming


def keep_if_unchanged_items(
    svc: "EmojiPackService",
    user_id: int,
    incoming: Optional[list],
    stored: Optional[list],
    *,
    http: bool = False,
) -> Optional[list]:
    """Per-item keep_if_unchanged so adding a tag does not 403 on old ones."""
    if incoming is None:
        return None
    stored_set = {(item or "").strip() for item in (stored or [])}
    out: list = []
    for item in incoming:
        if (item or "").strip() in stored_set:
            out.append(keep_or_preview_tokens(svc, user_id, item) or item)
            continue
        if http:
            svc.require_send_tokens_http(user_id, item)
        else:
            svc.require_send_tokens(user_id, item)
        out.append(item)
    return out


def editor_or_preview_tokens(
    svc: "EmojiPackService",
    user_id: int,
    text: Optional[str],
    *,
    own: bool,
) -> Optional[str]:
    """Gate the author's own edit; preview an editor's copy of peer text.

    Channel admins resend the original title/tags when saving any change.
    Do not 403 them for the author's `[[e:id]]`.
    """
    if own:
        svc.require_send_tokens(user_id, text)
        return text
    return keep_or_preview_tokens(svc, user_id, text)


def prepare_forward_content(
    svc: "EmojiPackService",
    forwarder_id: int,
    content: Optional[str],
    *,
    original_author_id: Optional[int],
) -> Optional[str]:
    """Gate the author's own re-send; preview a peer's tokens.

    Forward and «в избранное» copy someone else's message. Do not 403 a
    user without custom_emoji (69) for the original author's `[[e:id]]`.
    Re-sending your own tokens after a downgrade still raises.
    """
    if int(original_author_id or 0) == int(forwarder_id):
        return content
    return keep_or_preview_tokens(svc, forwarder_id, content)


def authored_or_peer_label(
    svc: "EmojiPackService",
    user_id: int,
    authored: Optional[str],
    peer: Optional[str],
    *,
    default: str,
    limit: int,
) -> str:
    """Gate user-authored text; preview a peer/app name on deny."""
    own = (authored or "").strip()
    cap = max(1, int(limit or 1))
    if own:
        svc.require_send_tokens(user_id, own)
        return own[:cap] or default
    previewed = keep_or_preview_tokens(svc, user_id, peer) or peer or default
    clean = (previewed or default).strip()[:cap]
    return clean or default


def link_preview_for_persist(
    svc: "EmojiPackService",
    user_id: int,
    typed: Optional[str],
    *,
    og_title: Optional[str] = None,
    stored: Optional[str] = None,
) -> Optional[str]:
    """Persist a link-post preview without 403 on the webpage title.

    Flutter sends the OG title when the preview field is empty. That
    string is the page's — not the author's. Keep tokens if the user
    may send them; otherwise preview. A custom preview they typed is
    authored and still requires custom_emoji (69). Resaving the stored
    preview (edit without changing it) is receive-and-persist.
    """
    own = (typed or "").strip()
    og = (og_title or "").strip()
    prev = (stored or "").strip()
    if not own:
        if not og:
            return None
        return keep_or_preview_tokens(svc, user_id, og)
    if own == og or own == prev:
        return keep_or_preview_tokens(svc, user_id, own)
    svc.require_send_tokens(user_id, own)
    return own


def link_preview_for_persist_http(
    svc: "EmojiPackService",
    user_id: int,
    typed: Optional[str],
    *,
    og_title: Optional[str] = None,
    stored: Optional[str] = None,
) -> Optional[str]:
    """HTTP wrapper: authored tokens become 403, OG/stored stay previewed."""
    try:
        return link_preview_for_persist(
            svc,
            user_id,
            typed,
            og_title=og_title,
            stored=stored,
        )
    except ValueError:
        svc.require_send_tokens_http(user_id, typed)
        return (typed or "").strip() or None


def display_name_or_default(
    text: Optional[str],
    *,
    default: str,
    limit: int = 80,
) -> str:
    """Preview tokens in a name; empty/whitespace never becomes «Сообщение»."""
    raw = (text or "").strip()
    if not raw:
        return default
    return preview_text_with_custom_emoji(raw, limit=limit)


def avatar_letter_with_custom_emoji(text: Optional[str]) -> str:
    """First letter for avatars — skip `[[e:id]]` so the glyph is not `[`."""
    raw = (text or "").strip()
    if not raw:
        return "?"
    stripped = CE_TOKEN_RE.sub(" ", raw).strip()
    if not stripped:
        return "✦"
    return stripped[0].upper()


def is_contact_card_content(content: Optional[str]) -> bool:
    first = (content or "").lstrip().split("\n", 1)[0].strip().lower()
    if not first:
        return False
    return first == "han_contact" or first.endswith("контакт")


_HANWE_SHARE_MARKER = "\n\nОткрыть в HanWe: "
_HANWE_SHARE_URL = "https://haneat.app/"


def split_private_reply_quote(
    content: Optional[str],
) -> tuple[Optional[str], Optional[str]]:
    """Private-reply compose: `↩️ who: preview` then an optional body.

    The first line is a peer quote — not the sender's text. Returns
    `(header, body)` or `(None, content)` if this is not that format.
    """
    text = content or ""
    stripped = text.lstrip()
    if not stripped.startswith("↩️"):
        return None, content
    parts = stripped.split("\n\n", 1)
    header = parts[0]
    body = parts[1] if len(parts) > 1 else ""
    return header, body


def split_hanwe_share(content: Optional[str]) -> tuple[Optional[str], str]:
    """Share-to-chat of a post/reel/channel/profile.

    Flutter builds `{title}\\n\\nОткрыть в HanWe: https://haneat.app/...`.
    The title is the author's; only extra lines after the URL are user-typed.
    Returns `(subject, from_marker_onward)` or `(None, content)`.
    """
    text = content or ""
    idx = text.find(_HANWE_SHARE_MARKER)
    if idx < 0:
        return None, text
    after = text[idx + len(_HANWE_SHARE_MARKER) :]
    url_line = after.split("\n", 1)[0].strip()
    if not url_line.startswith(_HANWE_SHARE_URL):
        return None, text
    return text[:idx], text[idx:]


def _hanwe_share_tail(rest: str) -> str:
    after = (
        rest[len(_HANWE_SHARE_MARKER) :]
        if rest.startswith(_HANWE_SHARE_MARKER)
        else rest
    )
    nl = after.find("\n")
    return after[nl + 1 :] if nl >= 0 else ""


def authored_send_texts(
    msg_type: Optional[str], content: Optional[str]
) -> list[Optional[str]]:
    """Texts the sender wrote — not embedded peer names or sticker emoji."""
    kind = (msg_type or "").strip()
    if kind == "story_reply":
        try:
            data = json.loads(content or "")
        except Exception:
            return [content]
        if isinstance(data, dict):
            return [data.get("text")]
        return [content]
    if is_contact_card_content(content):
        return []
    if kind == "sticker":
        # Associated emoji is pack metadata, not the sender's caption.
        return []
    header, body = split_private_reply_quote(content)
    if header is not None:
        return [body]
    share, rest = split_hanwe_share(content)
    if share is not None:
        tail = _hanwe_share_tail(rest)
        return [tail] if tail.strip() else []
    return [content]


def preview_peer_tokens_in_content(
    svc: "EmojiPackService",
    user_id: int,
    msg_type: Optional[str],
    content: Optional[str],
) -> str:
    """Keep peer names / sticker emoji when the sender may use them; else preview.

    Story reply JSON embeds the author's name; a contact card embeds the
    peer's display name; a sticker carries the pack's associated emoji;
    a private-reply header quotes the original message; a HanWe share
    subject is the post/channel/profile title. Those are received texts
    — do not 403 the sender.
    """
    text = content or ""
    if not text:
        return text
    if (msg_type or "").strip() == "story_reply":
        try:
            data = json.loads(text)
        except Exception:
            return text
        if not isinstance(data, dict):
            return text
        name = data.get("author_name")
        if not (isinstance(name, str) and name.strip()):
            return text
        previewed = keep_or_preview_tokens(svc, user_id, name) or name
        if previewed == name:
            return text
        data["author_name"] = previewed
        return json.dumps(data, ensure_ascii=False)
    if is_contact_card_content(text):
        return keep_or_preview_tokens(svc, user_id, text) or text
    if (msg_type or "").strip() == "sticker":
        return keep_or_preview_tokens(svc, user_id, text) or text
    header, body = split_private_reply_quote(text)
    if header is not None:
        previewed = keep_or_preview_tokens(svc, user_id, header) or header
        if (body or "").strip():
            return f"{previewed}\n\n{body}"
        return previewed
    share, rest = split_hanwe_share(text)
    if share is not None:
        previewed = keep_or_preview_tokens(svc, user_id, share) or share
        return f"{previewed}{rest}"
    return text


def prepare_send_content(
    svc: "EmojiPackService",
    user_id: int,
    msg_type: Optional[str],
    content: Optional[str],
) -> str:
    """Gate the sender's own text; preview embedded peer names on deny.

    Used on send, schedule, edit, and reschedule so a contact card,
    story-reply name, private-reply quote, or HanWe share subject
    does not 403 a user without custom_emoji (69).
    """
    text = content or ""
    for part in authored_send_texts(msg_type, text):
        svc.require_send_tokens(user_id, part)
    return preview_peer_tokens_in_content(svc, user_id, msg_type, text)


def preview_reply_keyboard_content(
    svc: "EmojiPackService",
    db,
    user_id: int,
    conversation_id: int,
    msg_type: Optional[str],
    content: Optional[str],
) -> Optional[str]:
    """Preview bot ReplyKeyboard labels so a tap does not 403 without 69.

    The button text is the bot owner's — tapping sends it as the user's
    message. Keep tokens if the user may send them; otherwise preview.
    """
    kind = (msg_type or "text").strip() or "text"
    if kind != "text":
        return content
    from app.services.reply_keyboard_service import is_reply_keyboard_label

    if not is_reply_keyboard_label(db, conversation_id, user_id, content):
        return content
    return keep_or_preview_tokens(svc, user_id, content)


class EmojiPackService:
    def __init__(self, db: Session):
        self.db = db

    @staticmethod
    def _slugify(value: str) -> str:
        base = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
        return base or "emoji-pack"

    def _make_unique_slug(self, title: str, owner_user_id: int) -> str:
        seed = f"{self._slugify(title)}-{owner_user_id}"
        slug = seed
        idx = 2
        while self.db.query(EmojiPack.id).filter(EmojiPack.slug == slug).first():
            slug = f"{seed}-{idx}"
            idx += 1
        return slug

    def create_pack(self, user_id: int, title: str, is_public: bool = True) -> EmojiPack:
        clean = clip_preserving_custom_emoji((title or "").strip(), 120)
        if len(clean) < 2:
            raise ValueError("invalid_title")
        self.require_send_tokens(user_id, clean)
        SubscriptionService(self.db).require_feature(
            user_id,
            "emoji_pack_publish",
            "Публикация эмодзи-паков доступна с уровня 70",
        )
        pack = EmojiPack(
            title=clean,
            slug=self._make_unique_slug(clean, user_id),
            owner_user_id=user_id,
            is_public=bool(is_public),
        )
        self.db.add(pack)
        self.db.flush()
        self.install_pack(user_id, pack.id, skip_purchase_check=True)
        return pack

    def update_pack(
        self,
        *,
        user_id: int,
        pack_id: int,
        title: Optional[str] = None,
        is_public: Optional[bool] = None,
    ) -> EmojiPack:
        pack = self.get_pack(pack_id)
        if not pack:
            raise ValueError("pack_not_found")
        if int(pack.owner_user_id) != int(user_id):
            raise ValueError("forbidden")
        if title is not None:
            clean = title.strip()
            if len(clean) < 2:
                raise ValueError("invalid_title")
            # Flutter always resends title with is_public. Unchanged
            # title is keep-if-unchanged — do not 403 after a downgrade.
            pack.title = clip_preserving_custom_emoji(
                keep_if_unchanged(self, user_id, clean, pack.title) or clean,
                120,
            )
        if is_public is not None:
            pack.is_public = bool(is_public)
        pack.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
        self.db.flush()
        return pack

    def add_emoji(
        self,
        *,
        user_id: int,
        pack_id: int,
        media_url: str,
        shortcode: Optional[str] = None,
    ) -> CustomEmoji:
        self.require_send_tokens(user_id, shortcode)
        pack = self.db.query(EmojiPack).filter(EmojiPack.id == pack_id).first()
        if not pack:
            raise ValueError("pack_not_found")
        if int(pack.owner_user_id) != int(user_id):
            raise ValueError("forbidden")
        url = (media_url or "").strip()
        if not url:
            raise ValueError("missing_media")
        max_order = (
            self.db.query(func.max(CustomEmoji.order_index))
            .filter(CustomEmoji.pack_id == pack_id)
            .scalar()
        )
        item = CustomEmoji(
            pack_id=pack_id,
            media_url=url[:512],
            shortcode=(shortcode or "").strip()[:32] or None,
            order_index=int(max_order or 0) + 1,
        )
        self.db.add(item)
        pack.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
        self.db.flush()
        return item

    def delete_emoji(self, user_id: int, pack_id: int, emoji_id: int) -> None:
        pack = self.db.query(EmojiPack).filter(EmojiPack.id == pack_id).first()
        if not pack:
            raise ValueError("pack_not_found")
        if int(pack.owner_user_id) != int(user_id):
            raise ValueError("forbidden")
        row = (
            self.db.query(CustomEmoji)
            .filter(CustomEmoji.id == emoji_id, CustomEmoji.pack_id == pack_id)
            .first()
        )
        if not row:
            raise ValueError("emoji_not_found")
        self.db.delete(row)
        pack.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
        self.db.flush()

    def reorder_emojis(
        self,
        *,
        user_id: int,
        pack_id: int,
        emoji_ids: List[int],
    ) -> None:
        pack = self.get_pack(pack_id)
        if not pack:
            raise ValueError("pack_not_found")
        if int(pack.owner_user_id) != int(user_id):
            raise ValueError("forbidden")
        rows = (
            self.db.query(CustomEmoji)
            .filter(CustomEmoji.pack_id == pack_id)
            .order_by(CustomEmoji.order_index.asc(), CustomEmoji.id.asc())
            .all()
        )
        if not rows:
            return
        id_to_row = {row.id: row for row in rows}
        unique_ids: List[int] = []
        seen: set[int] = set()
        for eid in emoji_ids:
            if eid in id_to_row and eid not in seen:
                unique_ids.append(eid)
                seen.add(eid)
        for row in rows:
            if row.id not in seen:
                unique_ids.append(row.id)
                seen.add(row.id)
        for idx, eid in enumerate(unique_ids, start=1):
            id_to_row[eid].order_index = idx
        pack.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
        self.db.flush()

    def _is_installed(self, user_id: int, pack_id: int) -> bool:
        return (
            self.db.query(EmojiPackInstall.id)
            .filter(
                EmojiPackInstall.user_id == user_id,
                EmojiPackInstall.pack_id == pack_id,
            )
            .first()
            is not None
        )

    def _is_purchased(self, user_id: int, pack_id: int) -> bool:
        return (
            self.db.query(EmojiPackPurchase.id)
            .filter(
                EmojiPackPurchase.user_id == user_id,
                EmojiPackPurchase.pack_id == pack_id,
            )
            .first()
            is not None
        )

    def install_pack(
        self, user_id: int, pack_id: int, *, skip_purchase_check: bool = False
    ) -> None:
        pack = self.db.query(EmojiPack).filter(EmojiPack.id == pack_id).first()
        if not pack:
            raise ValueError("pack_not_found")
        if not pack.is_public and int(pack.owner_user_id) != int(user_id):
            if not self._is_purchased(user_id, pack.id) and not self._is_installed(
                user_id, pack.id
            ):
                raise ValueError("forbidden")
        priced = int(getattr(pack, "price_stars", 0) or 0) > 0
        if (
            not skip_purchase_check
            and priced
            and int(pack.owner_user_id) != int(user_id)
            and not self._is_purchased(user_id, pack.id)
        ):
            raise ValueError("pack_purchase_required")
        exists = (
            self.db.query(EmojiPackInstall.id)
            .filter(
                EmojiPackInstall.user_id == user_id,
                EmojiPackInstall.pack_id == pack_id,
            )
            .first()
        )
        if exists:
            return
        self.db.add(EmojiPackInstall(user_id=user_id, pack_id=pack_id))
        self.db.flush()

    def uninstall_pack(self, user_id: int, pack_id: int) -> None:
        row = (
            self.db.query(EmojiPackInstall)
            .filter(
                EmojiPackInstall.user_id == user_id,
                EmojiPackInstall.pack_id == pack_id,
            )
            .first()
        )
        if row:
            self.db.delete(row)
            self.db.flush()
        self._clear_status_if_pack_lost(user_id, pack_id)

    def _clear_status_if_pack_lost(self, user_id: int, pack_id: int) -> None:
        from app.models.user import User

        user = self.db.query(User).filter(User.id == user_id).first()
        if not user:
            return
        token = (getattr(user, "emoji_status", None) or "").strip()
        eid = parse_custom_reaction_id(token)
        if eid is None:
            ids = parse_custom_emoji_ids(token)
            eid = ids[0] if ids else None
        if eid is None:
            return
        row = self.db.query(CustomEmoji).filter(CustomEmoji.id == eid).first()
        if row is None or int(row.pack_id) != int(pack_id):
            return
        pack = self.get_pack(pack_id)
        if pack is not None and PackMarketplaceService(self.db).has_emoji_access(
            user_id, pack
        ):
            return
        user.emoji_status = None
        self.db.flush()

    def list_my_packs(self, user_id: int) -> List[EmojiPack]:
        installed = (
            self.db.query(EmojiPackInstall.pack_id)
            .filter(EmojiPackInstall.user_id == user_id)
            .subquery()
        )
        purchased = (
            self.db.query(EmojiPackPurchase.pack_id)
            .filter(EmojiPackPurchase.user_id == user_id)
            .subquery()
        )
        return (
            self.db.query(EmojiPack)
            .filter(
                (EmojiPack.owner_user_id == user_id)
                | EmojiPack.id.in_(installed)
                | EmojiPack.id.in_(purchased)
            )
            .order_by(EmojiPack.updated_at.desc(), EmojiPack.id.desc())
            .all()
        )

    def list_marketplace(self, *, query: Optional[str] = None, limit: int = 50) -> List[EmojiPack]:
        q = self.db.query(EmojiPack).filter(
            EmojiPack.is_public.is_(True),
            EmojiPack.price_stars > 0,
        )
        term = (query or "").strip()
        if term:
            q = q.filter(EmojiPack.title.ilike(f"%{term}%"))
        rows = q.order_by(EmojiPack.listed_at.desc(), EmojiPack.id.desc()).limit(limit * 3).all()
        return PackMarketplaceService(self.db).filter_active_listings(
            rows, kind="emoji"
        )[:limit]

    def list_catalog(self, *, query: Optional[str] = None, limit: int = 50) -> List[EmojiPack]:
        q = self.db.query(EmojiPack).filter(EmojiPack.is_public.is_(True))
        term = (query or "").strip()
        if term:
            q = q.filter(EmojiPack.title.ilike(f"%{term}%"))
        rows = q.order_by(EmojiPack.updated_at.desc(), EmojiPack.id.desc()).limit(limit * 3).all()
        return PackMarketplaceService(self.db).filter_active_listings(
            rows, kind="emoji"
        )[:limit]

    def get_public_pack_by_slug(self, slug: str) -> Optional[EmojiPack]:
        clean = (slug or "").strip().lower()
        if not clean:
            return None
        return (
            self.db.query(EmojiPack)
            .filter(EmojiPack.slug == clean, EmojiPack.is_public.is_(True))
            .first()
        )

    def get_pack_by_slug_for_user(self, user_id: int, slug: str) -> Optional[EmojiPack]:
        public = self.get_public_pack_by_slug(slug)
        if public is not None:
            return public
        clean = (slug or "").strip().lower()
        if not clean:
            return None
        pack = self.db.query(EmojiPack).filter(EmojiPack.slug == clean).first()
        if not pack:
            return None
        return self.get_pack_for_user(user_id, pack.id)

    def installed_pack_ids(self, user_id: int) -> set[int]:
        rows = (
            self.db.query(EmojiPackInstall.pack_id)
            .filter(EmojiPackInstall.user_id == user_id)
            .all()
        )
        return {pid for (pid,) in rows}

    def purchased_pack_ids(self, user_id: int) -> set[int]:
        rows = (
            self.db.query(EmojiPackPurchase.pack_id)
            .filter(EmojiPackPurchase.user_id == user_id)
            .all()
        )
        return {pid for (pid,) in rows}

    def emojis_by_pack_ids(self, pack_ids: List[int]) -> dict[int, list[CustomEmoji]]:
        if not pack_ids:
            return {}
        rows = (
            self.db.query(CustomEmoji)
            .filter(CustomEmoji.pack_id.in_(pack_ids))
            .order_by(CustomEmoji.order_index.asc(), CustomEmoji.id.asc())
            .all()
        )
        out: dict[int, list[CustomEmoji]] = {}
        for row in rows:
            out.setdefault(row.pack_id, []).append(row)
        return out

    def resolve_emojis(self, ids: Iterable[int]) -> list[CustomEmoji]:
        clean = [int(i) for i in ids if int(i) > 0]
        if not clean:
            return []
        return self.db.query(CustomEmoji).filter(CustomEmoji.id.in_(clean)).all()

    def can_use_emoji(self, user_id: int, emoji: CustomEmoji) -> bool:
        pack = self.db.query(EmojiPack).filter(EmojiPack.id == emoji.pack_id).first()
        if not pack:
            return False
        return PackMarketplaceService(self.db).has_emoji_access(user_id, pack)

    def can_view_emoji(self, user_id: int, emoji: CustomEmoji) -> bool:
        """Recipients may render public-pack emoji without buying.

        Private packs stay off the public resolve scrape: only owner / access.
        """
        pack = self.db.query(EmojiPack).filter(EmojiPack.id == emoji.pack_id).first()
        if not pack:
            return False
        if pack.is_public:
            return True
        return PackMarketplaceService(self.db).has_emoji_access(user_id, pack)

    def require_send_tokens(self, user_id: int, content: Optional[str]) -> None:
        ids = parse_custom_emoji_ids(content)
        if not ids:
            return
        billing = SubscriptionService(self.db)
        if not billing.has_feature(user_id, "custom_emoji"):
            raise ValueError("custom_emoji_required")
        items = {row.id: row for row in self.resolve_emojis(ids)}
        for eid in ids:
            row = items.get(eid)
            if row is None or not self.can_use_emoji(user_id, row):
                raise ValueError("custom_emoji_denied")

    def require_send_tokens_http(self, user_id: int, *parts: Optional[str]) -> None:
        from fastapi import HTTPException, status
        from app.core.entitlements import feature_required_detail

        try:
            for part in parts:
                self.require_send_tokens(user_id, part)
        except ValueError as exc:
            code = str(exc)
            if code == "custom_emoji_required":
                raise HTTPException(
                    status.HTTP_403_FORBIDDEN,
                    feature_required_detail(
                        "custom_emoji",
                        "Кастомные эмодзи в тексте доступны с уровня 69",
                    ),
                ) from exc
            if code == "custom_emoji_denied":
                raise HTTPException(
                    status.HTTP_403_FORBIDDEN,
                    {
                        "code": "custom_emoji_denied",
                        "message": "Этот эмодзи недоступен — купите пак",
                    },
                ) from exc
            raise

    def require_reaction_http(self, user_id: int, emoji: str) -> Optional[str]:
        from fastapi import HTTPException, status
        from app.core.entitlements import feature_required_detail

        try:
            return self.require_reaction(user_id, emoji)
        except ValueError as exc:
            code = str(exc)
            if code == "custom_emoji_reaction_required":
                raise HTTPException(
                    status.HTTP_403_FORBIDDEN,
                    feature_required_detail(
                        "custom_emoji_reactions",
                        "Реакции своими эмодзи доступны с уровня 72",
                    ),
                ) from exc
            if code == "custom_emoji_denied":
                raise HTTPException(
                    status.HTTP_403_FORBIDDEN,
                    {
                        "code": "custom_emoji_denied",
                        "message": "Этот эмодзи недоступен — купите пак",
                    },
                ) from exc
            raise

    def require_reaction(self, user_id: int, emoji: str) -> Optional[str]:
        eid = parse_custom_reaction_id(emoji)
        if eid is None:
            return None
        billing = SubscriptionService(self.db)
        if not billing.has_feature(user_id, "custom_emoji_reactions"):
            raise ValueError("custom_emoji_reaction_required")
        row = self.db.query(CustomEmoji).filter(CustomEmoji.id == eid).first()
        if row is None or not self.can_use_emoji(user_id, row):
            raise ValueError("custom_emoji_denied")
        return f"ce:{eid}"

    def require_status(self, user_id: int, raw: Optional[str]) -> Optional[str]:
        """Normalize a profile emoji-status. Custom tokens need pack access."""
        from app.services.profile_style import normalize_emoji_status

        token = normalize_emoji_status(raw)
        if not token:
            return None
        eid = parse_custom_reaction_id(token)
        if eid is None:
            return token
        billing = SubscriptionService(self.db)
        if not billing.has_feature(user_id, "custom_emoji"):
            raise ValueError("custom_emoji_required")
        row = self.db.query(CustomEmoji).filter(CustomEmoji.id == eid).first()
        if row is None or not self.can_use_emoji(user_id, row):
            raise ValueError("custom_emoji_denied")
        return f"ce:{eid}"

    def visible_emoji_status(self, user) -> Optional[str]:
        """Public status: hide custom tokens without flex 69 or pack access.

        The stored value stays so a later resub can restore it. Unicode
        statuses are unchanged.
        """
        token = (getattr(user, "emoji_status", None) or "").strip()
        if not token:
            return None
        eid = parse_custom_reaction_id(token)
        if eid is None:
            ids = parse_custom_emoji_ids(token)
            eid = ids[0] if ids else None
        if eid is None:
            return token
        billing = SubscriptionService(self.db)
        if not billing.has_feature(int(user.id), "custom_emoji"):
            return None
        row = self.db.query(CustomEmoji).filter(CustomEmoji.id == eid).first()
        if row is None or not self.can_use_emoji(int(user.id), row):
            return None
        return f"ce:{eid}"

    def get_pack(self, pack_id: int) -> Optional[EmojiPack]:
        return self.db.query(EmojiPack).filter(EmojiPack.id == pack_id).first()

    def get_pack_for_user(self, user_id: int, pack_id: int) -> Optional[EmojiPack]:
        pack = self.get_pack(pack_id)
        if not pack:
            return None
        if pack.is_public or int(pack.owner_user_id) == int(user_id):
            return pack
        if self._is_purchased(user_id, pack.id) or self._is_installed(user_id, pack.id):
            return pack
        return None

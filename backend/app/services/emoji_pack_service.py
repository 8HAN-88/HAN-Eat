"""Custom emoji packs: create, install, send/reaction access."""

from __future__ import annotations

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


def preview_text_with_custom_emoji(text: Optional[str], *, limit: int = 120) -> str:
    replaced = CE_TOKEN_RE.sub("✦", text or "").strip()
    if not replaced:
        return "Сообщение"
    return replaced[: max(1, int(limit or 120))]


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
        SubscriptionService(self.db).require_feature(
            user_id,
            "emoji_pack_publish",
            "Публикация эмодзи-паков доступна с уровня 70",
        )
        clean = (title or "").strip()
        if len(clean) < 2:
            raise ValueError("invalid_title")
        pack = EmojiPack(
            title=clean[:120],
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
            pack.title = clean[:120]
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
        return q.order_by(EmojiPack.listed_at.desc(), EmojiPack.id.desc()).limit(limit).all()

    def list_catalog(self, *, query: Optional[str] = None, limit: int = 50) -> List[EmojiPack]:
        q = self.db.query(EmojiPack).filter(EmojiPack.is_public.is_(True))
        term = (query or "").strip()
        if term:
            q = q.filter(EmojiPack.title.ilike(f"%{term}%"))
        return q.order_by(EmojiPack.updated_at.desc(), EmojiPack.id.desc()).limit(limit).all()

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

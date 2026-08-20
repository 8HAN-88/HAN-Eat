import re
from datetime import datetime, timezone
from typing import List, Optional

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.sticker import (
    Sticker,
    StickerFavorite,
    StickerPack,
    StickerPackInstall,
    StickerPackPin,
    StickerPackPurchase,
)


class StickerService:
    def __init__(self, db: Session):
        self.db = db

    @staticmethod
    def _slugify(value: str) -> str:
        base = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
        return base or "sticker-pack"

    def _make_unique_slug(self, title: str, owner_user_id: int) -> str:
        seed = f"{self._slugify(title)}-{owner_user_id}"
        slug = seed
        idx = 2
        while (
            self.db.query(StickerPack.id)
            .filter(StickerPack.slug == slug)
            .first()
            is not None
        ):
            slug = f"{seed}-{idx}"
            idx += 1
        return slug

    def _require_premium_stickers(self, user_id: int) -> None:
        from app.services.subscription_service import SubscriptionService

        if not SubscriptionService(self.db).has_feature(user_id, "premium_stickers"):
            raise ValueError("premium_sticker")

    def require_sticker_send(self, user_id: int, media_url: Optional[str]) -> None:
        url = (media_url or "").strip()
        if not url:
            return
        sticker = (
            self.db.query(Sticker)
            .filter(Sticker.media_url == url[:512])
            .first()
        )
        if not sticker:
            return
        pack = (
            self.db.query(StickerPack)
            .filter(StickerPack.id == sticker.pack_id)
            .first()
        )
        if not pack:
            return
        if int(pack.owner_user_id) == int(user_id):
            return
        if int(getattr(pack, "price_stars", 0) or 0) > 0:
            from app.services.pack_marketplace_service import PackMarketplaceService

            if not PackMarketplaceService(self.db).has_sticker_access(user_id, pack):
                raise ValueError("pack_purchase_required")
        if bool(getattr(pack, "is_premium", False)):
            self._require_premium_stickers(user_id)

    def create_pack(
        self, user_id: int, title: str, is_public: bool, is_premium: bool = False
    ) -> StickerPack:
        clean_title = (title or "").strip()
        if len(clean_title) < 2:
            raise ValueError("invalid_title")
        premium = bool(is_premium)
        if premium:
            self._require_premium_stickers(user_id)
        pack = StickerPack(
            title=clean_title[:120],
            slug=self._make_unique_slug(clean_title, user_id),
            owner_user_id=user_id,
            is_public=bool(is_public),
            is_premium=premium,
        )
        self.db.add(pack)
        self.db.flush()
        self.install_pack(user_id, pack.id)
        return pack

    def add_sticker(
        self,
        *,
        user_id: int,
        pack_id: int,
        media_url: str,
        emoji: Optional[str] = None,
        sticker_type: str = "static",
    ) -> Sticker:
        pack = self.db.query(StickerPack).filter(StickerPack.id == pack_id).first()
        if not pack:
            raise ValueError("pack_not_found")
        if pack.owner_user_id != user_id:
            raise ValueError("forbidden")
        clean_url = (media_url or "").strip()
        if not clean_url:
            raise ValueError("missing_media")
        clean_type = (sticker_type or "static").strip().lower()
        if clean_type not in ("static", "animated"):
            raise ValueError("invalid_sticker_type")
        max_order = (
            self.db.query(func.max(Sticker.order_index))
            .filter(Sticker.pack_id == pack_id)
            .scalar()
        )
        next_order = int(max_order or 0) + 1
        item = Sticker(
            pack_id=pack_id,
            media_url=clean_url[:512],
            emoji=(emoji or "").strip()[:16] or None,
            sticker_type=clean_type,
            order_index=next_order,
        )
        self.db.add(item)
        pack.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
        self.db.flush()
        return item

    def update_pack(
        self,
        *,
        user_id: int,
        pack_id: int,
        title: Optional[str] = None,
        is_public: Optional[bool] = None,
        is_premium: Optional[bool] = None,
    ) -> StickerPack:
        pack = self.db.query(StickerPack).filter(StickerPack.id == pack_id).first()
        if not pack:
            raise ValueError("pack_not_found")
        if pack.owner_user_id != user_id:
            raise ValueError("forbidden")
        if title is not None:
            clean_title = title.strip()
            if len(clean_title) < 2:
                raise ValueError("invalid_title")
            pack.title = clean_title[:120]
        if is_public is not None:
            pack.is_public = bool(is_public)
        if is_premium is not None:
            premium = bool(is_premium)
            if premium:
                self._require_premium_stickers(user_id)
            pack.is_premium = premium
        pack.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
        self.db.flush()
        return pack

    def delete_sticker(
        self,
        *,
        user_id: int,
        pack_id: int,
        sticker_id: int,
    ) -> None:
        pack = self.db.query(StickerPack).filter(StickerPack.id == pack_id).first()
        if not pack:
            raise ValueError("pack_not_found")
        if pack.owner_user_id != user_id:
            raise ValueError("forbidden")
        row = (
            self.db.query(Sticker)
            .filter(
                Sticker.id == sticker_id,
                Sticker.pack_id == pack_id,
            )
            .first()
        )
        if not row:
            raise ValueError("sticker_not_found")
        self.db.delete(row)
        pack.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
        self.db.flush()

    def reorder_stickers(
        self,
        *,
        user_id: int,
        pack_id: int,
        sticker_ids: List[int],
    ) -> None:
        pack = self.db.query(StickerPack).filter(StickerPack.id == pack_id).first()
        if not pack:
            raise ValueError("pack_not_found")
        if pack.owner_user_id != user_id:
            raise ValueError("forbidden")
        rows = (
            self.db.query(Sticker)
            .filter(Sticker.pack_id == pack_id)
            .order_by(Sticker.order_index.asc(), Sticker.id.asc())
            .all()
        )
        if not rows:
            return
        id_to_row = {row.id: row for row in rows}
        unique_ids: List[int] = []
        seen = set()
        for sid in sticker_ids:
            if sid in id_to_row and sid not in seen:
                unique_ids.append(sid)
                seen.add(sid)
        for row in rows:
            if row.id not in seen:
                unique_ids.append(row.id)
                seen.add(row.id)
        for idx, sid in enumerate(unique_ids, start=1):
            id_to_row[sid].order_index = idx
        pack.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
        self.db.flush()

    def install_pack(self, user_id: int, pack_id: int) -> None:
        pack = self.db.query(StickerPack).filter(StickerPack.id == pack_id).first()
        if not pack:
            raise ValueError("pack_not_found")
        if not pack.is_public and pack.owner_user_id != user_id:
            raise ValueError("forbidden")
        if bool(getattr(pack, "is_premium", False)) and pack.owner_user_id != user_id:
            self._require_premium_stickers(user_id)
        if (
            int(getattr(pack, "price_stars", 0) or 0) > 0
            and int(pack.owner_user_id) != int(user_id)
        ):
            from app.services.pack_marketplace_service import PackMarketplaceService

            if not PackMarketplaceService(self.db).has_sticker_access(user_id, pack):
                raise ValueError("pack_purchase_required")
        exists = (
            self.db.query(StickerPackInstall.id)
            .filter(
                StickerPackInstall.user_id == user_id,
                StickerPackInstall.pack_id == pack_id,
            )
            .first()
        )
        if exists:
            return
        self.db.add(StickerPackInstall(user_id=user_id, pack_id=pack_id))
        self.db.flush()

    def uninstall_pack(self, user_id: int, pack_id: int) -> None:
        row = (
            self.db.query(StickerPackInstall)
            .filter(
                StickerPackInstall.user_id == user_id,
                StickerPackInstall.pack_id == pack_id,
            )
            .first()
        )
        if row:
            self.db.delete(row)
        pin = (
            self.db.query(StickerPackPin)
            .filter(
                StickerPackPin.user_id == user_id,
                StickerPackPin.pack_id == pack_id,
            )
            .first()
        )
        if pin:
            self.db.delete(pin)
        if row or pin:
            self.db.flush()

    def get_pack_for_user(self, user_id: int, pack_id: int) -> Optional[StickerPack]:
        pack = self.db.query(StickerPack).filter(StickerPack.id == pack_id).first()
        if not pack:
            return None
        if pack.is_public or pack.owner_user_id == user_id:
            return pack
        installed = (
            self.db.query(StickerPackInstall.id)
            .filter(
                StickerPackInstall.user_id == user_id,
                StickerPackInstall.pack_id == pack_id,
            )
            .first()
        )
        return pack if installed else None

    def get_public_pack_by_slug(self, slug: str) -> Optional[StickerPack]:
        clean = (slug or "").strip().lower()
        if not clean:
            return None
        return (
            self.db.query(StickerPack)
            .filter(
                StickerPack.slug == clean,
                StickerPack.is_public.is_(True),
            )
            .first()
        )

    def list_my_packs(self, user_id: int) -> List[StickerPack]:
        installed_pack_ids = (
            self.db.query(StickerPackInstall.pack_id)
            .filter(StickerPackInstall.user_id == user_id)
            .subquery()
        )
        purchased_pack_ids = (
            self.db.query(StickerPackPurchase.pack_id)
            .filter(StickerPackPurchase.user_id == user_id)
            .subquery()
        )
        packs = (
            self.db.query(StickerPack)
            .filter(
                (StickerPack.owner_user_id == user_id)
                | StickerPack.id.in_(installed_pack_ids)
                | StickerPack.id.in_(purchased_pack_ids)
            )
            .order_by(
                StickerPack.owner_user_id.desc(),
                StickerPack.updated_at.desc().nullslast(),
                StickerPack.created_at.desc(),
            )
            .all()
        )
        pin_order = {
            pack_id: idx
            for idx, pack_id in enumerate(self.list_pinned_pack_ids(user_id))
        }
        if not pin_order:
            return packs
        return sorted(
            packs,
            key=lambda p: (
                0 if p.id in pin_order else 1,
                pin_order.get(p.id, 10_000),
                0 if p.owner_user_id == user_id else 1,
                -(p.updated_at.timestamp() if p.updated_at else 0),
            ),
        )

    def purchased_pack_ids(self, user_id: int) -> set[int]:
        rows = (
            self.db.query(StickerPackPurchase.pack_id)
            .filter(StickerPackPurchase.user_id == user_id)
            .all()
        )
        return {pid for (pid,) in rows}

    def list_marketplace_packs(
        self,
        *,
        query: Optional[str] = None,
        limit: int = 50,
    ) -> List[StickerPack]:
        q = self.db.query(StickerPack).filter(
            StickerPack.is_public.is_(True),
            StickerPack.price_stars > 0,
        )
        term = (query or "").strip()
        if term:
            q = q.filter(StickerPack.title.ilike(f"%{term}%"))
        return (
            q.order_by(StickerPack.listed_at.desc(), StickerPack.id.desc())
            .limit(limit)
            .all()
        )

    def list_catalog_packs(
        self,
        *,
        user_id: int,
        query: Optional[str] = None,
        limit: int = 50,
    ) -> List[StickerPack]:
        q = self.db.query(StickerPack).filter(StickerPack.is_public.is_(True))
        term = (query or "").strip()
        if term:
            q = q.filter(StickerPack.title.ilike(f"%{term}%"))
        return q.order_by(StickerPack.updated_at.desc(), StickerPack.id.desc()).limit(limit).all()

    def installed_pack_ids(self, user_id: int) -> set[int]:
        rows = (
            self.db.query(StickerPackInstall.pack_id)
            .filter(StickerPackInstall.user_id == user_id)
            .all()
        )
        return {pid for (pid,) in rows}

    def stickers_by_pack_ids(self, pack_ids: List[int]) -> dict[int, list[Sticker]]:
        if not pack_ids:
            return {}
        rows = (
            self.db.query(Sticker)
            .filter(Sticker.pack_id.in_(pack_ids))
            .order_by(Sticker.order_index.asc(), Sticker.id.asc())
            .all()
        )
        out: dict[int, list[Sticker]] = {}
        for row in rows:
            out.setdefault(row.pack_id, []).append(row)
        return out

    def stickers_count_by_pack_ids(self, pack_ids: List[int]) -> dict[int, int]:
        if not pack_ids:
            return {}
        rows = (
            self.db.query(Sticker.pack_id, func.count(Sticker.id))
            .filter(Sticker.pack_id.in_(pack_ids))
            .group_by(Sticker.pack_id)
            .all()
        )
        return {int(pack_id): int(count) for pack_id, count in rows}

    def _resolve_sticker(
        self,
        *,
        sticker_id: Optional[int] = None,
        media_url: Optional[str] = None,
    ) -> Optional[Sticker]:
        if sticker_id is not None and int(sticker_id) > 0:
            return (
                self.db.query(Sticker)
                .filter(Sticker.id == int(sticker_id))
                .first()
            )
        clean_url = (media_url or "").strip()
        if not clean_url:
            return None
        return (
            self.db.query(Sticker)
            .filter(Sticker.media_url == clean_url[:512])
            .order_by(Sticker.id.asc())
            .first()
        )

    def list_favorites(self, user_id: int) -> List[Sticker]:
        rows = (
            self.db.query(Sticker, StickerFavorite.created_at)
            .join(StickerFavorite, StickerFavorite.sticker_id == Sticker.id)
            .filter(StickerFavorite.user_id == user_id)
            .order_by(
                StickerFavorite.created_at.desc(),
                StickerFavorite.id.desc(),
            )
            .all()
        )
        return [sticker for sticker, _created in rows]

    def add_favorite(
        self,
        *,
        user_id: int,
        sticker_id: Optional[int] = None,
        media_url: Optional[str] = None,
    ) -> Sticker:
        sticker = self._resolve_sticker(sticker_id=sticker_id, media_url=media_url)
        if not sticker:
            raise ValueError("sticker_not_found")
        exists = (
            self.db.query(StickerFavorite.id)
            .filter(
                StickerFavorite.user_id == user_id,
                StickerFavorite.sticker_id == sticker.id,
            )
            .first()
        )
        if not exists:
            self.db.add(
                StickerFavorite(user_id=user_id, sticker_id=sticker.id)
            )
            self.db.flush()
        return sticker

    def remove_favorite(
        self,
        *,
        user_id: int,
        sticker_id: Optional[int] = None,
        media_url: Optional[str] = None,
    ) -> None:
        sticker = self._resolve_sticker(sticker_id=sticker_id, media_url=media_url)
        if not sticker:
            raise ValueError("sticker_not_found")
        row = (
            self.db.query(StickerFavorite)
            .filter(
                StickerFavorite.user_id == user_id,
                StickerFavorite.sticker_id == sticker.id,
            )
            .first()
        )
        if row:
            self.db.delete(row)
            self.db.flush()

    def toggle_favorite(
        self,
        *,
        user_id: int,
        sticker_id: Optional[int] = None,
        media_url: Optional[str] = None,
    ) -> tuple[Sticker, bool]:
        sticker = self._resolve_sticker(sticker_id=sticker_id, media_url=media_url)
        if not sticker:
            raise ValueError("sticker_not_found")
        row = (
            self.db.query(StickerFavorite)
            .filter(
                StickerFavorite.user_id == user_id,
                StickerFavorite.sticker_id == sticker.id,
            )
            .first()
        )
        if row:
            self.db.delete(row)
            self.db.flush()
            return sticker, False
        self.db.add(StickerFavorite(user_id=user_id, sticker_id=sticker.id))
        self.db.flush()
        return sticker, True

    def replace_favorites(
        self,
        *,
        user_id: int,
        sticker_ids: Optional[List[int]] = None,
        media_urls: Optional[List[str]] = None,
    ) -> List[Sticker]:
        resolved: List[Sticker] = []
        seen: set[int] = set()
        for sid in sticker_ids or []:
            sticker = self._resolve_sticker(sticker_id=sid)
            if sticker and sticker.id not in seen:
                resolved.append(sticker)
                seen.add(sticker.id)
        for url in media_urls or []:
            sticker = self._resolve_sticker(media_url=url)
            if sticker and sticker.id not in seen:
                resolved.append(sticker)
                seen.add(sticker.id)

        (
            self.db.query(StickerFavorite)
            .filter(StickerFavorite.user_id == user_id)
            .delete(synchronize_session=False)
        )
        # Newest-first UI: first item gets latest created_at.
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        for idx, sticker in enumerate(resolved):
            self.db.add(
                StickerFavorite(
                    user_id=user_id,
                    sticker_id=sticker.id,
                    created_at=now.replace(microsecond=max(0, 999999 - idx)),
                )
            )
        self.db.flush()
        return resolved

    def list_pinned_pack_ids(self, user_id: int) -> List[int]:
        rows = (
            self.db.query(StickerPackPin.pack_id)
            .filter(StickerPackPin.user_id == user_id)
            .order_by(
                StickerPackPin.pin_order.asc(),
                StickerPackPin.id.asc(),
            )
            .all()
        )
        return [int(pid) for (pid,) in rows]

    def replace_pinned_packs(
        self, *, user_id: int, pack_ids: List[int]
    ) -> List[int]:
        unique: List[int] = []
        seen: set[int] = set()
        for raw in pack_ids or []:
            try:
                pid = int(raw)
            except (TypeError, ValueError):
                continue
            if pid <= 0 or pid in seen:
                continue
            pack = self.db.query(StickerPack.id).filter(StickerPack.id == pid).first()
            if not pack:
                continue
            unique.append(pid)
            seen.add(pid)

        (
            self.db.query(StickerPackPin)
            .filter(StickerPackPin.user_id == user_id)
            .delete(synchronize_session=False)
        )
        for idx, pack_id in enumerate(unique):
            self.db.add(
                StickerPackPin(
                    user_id=user_id,
                    pack_id=pack_id,
                    pin_order=idx,
                )
            )
        self.db.flush()
        return unique

    def toggle_pinned_pack(self, *, user_id: int, pack_id: int) -> tuple[List[int], bool]:
        pack = self.db.query(StickerPack.id).filter(StickerPack.id == pack_id).first()
        if not pack:
            raise ValueError("pack_not_found")
        current = self.list_pinned_pack_ids(user_id)
        if pack_id in current:
            next_ids = [pid for pid in current if pid != pack_id]
            pinned = False
        else:
            next_ids = [pack_id, *current]
            pinned = True
        return self.replace_pinned_packs(user_id=user_id, pack_ids=next_ids), pinned

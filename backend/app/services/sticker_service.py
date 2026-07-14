import re
from datetime import datetime, timezone
from typing import List, Optional

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.sticker import Sticker, StickerPack, StickerPackInstall


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

    def create_pack(self, user_id: int, title: str, is_public: bool) -> StickerPack:
        clean_title = (title or "").strip()
        if len(clean_title) < 2:
            raise ValueError("invalid_title")
        pack = StickerPack(
            title=clean_title[:120],
            slug=self._make_unique_slug(clean_title, user_id),
            owner_user_id=user_id,
            is_public=bool(is_public),
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
        if not row:
            return
        self.db.delete(row)
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
        return (
            self.db.query(StickerPack)
            .filter(
                (StickerPack.owner_user_id == user_id)
                | StickerPack.id.in_(installed_pack_ids)
            )
            .order_by(
                StickerPack.owner_user_id.desc(),
                StickerPack.updated_at.desc().nullslast(),
                StickerPack.created_at.desc(),
            )
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

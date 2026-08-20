"""Custom emoji pack API."""

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.api.dependencies import get_current_user_required
from app.core.database import get_db
from app.models.user import User
from app.services.emoji_pack_service import EmojiPackService
from app.services.pack_marketplace_service import (
    PackMarketplaceService,
    marketplace_fee_stars,
    owner_labels,
)

router = APIRouter()


class EmojiItemOut(BaseModel):
    id: int
    media_url: str
    shortcode: str | None = None
    order_index: int = 0


class EmojiPackOut(BaseModel):
    id: int
    title: str
    slug: str
    owner_user_id: int
    owner_name: str = ""
    is_public: bool
    is_installed: bool = False
    is_owned: bool = False
    is_purchased: bool = False
    price_stars: int = 0
    fee_stars: int = 0
    items: list[EmojiItemOut] = []
    items_count: int = 0
    share_link: str | None = None


class EmojiPackListOut(BaseModel):
    items: list[EmojiPackOut]


class CreateEmojiPackIn(BaseModel):
    title: str = Field(..., min_length=2, max_length=120)
    is_public: bool = True


class AddEmojiIn(BaseModel):
    media_url: str = Field(..., min_length=1, max_length=512)
    shortcode: str | None = Field(default=None, max_length=32)


class ListPriceIn(BaseModel):
    price_stars: int = Field(0, ge=0, le=25000)


def _pack_out(
    pack,
    *,
    user_id: int,
    installed: set[int],
    purchased: set[int],
    items_by_pack: dict,
    authors: dict[int, str] | None = None,
) -> EmojiPackOut:
    items = items_by_pack.get(pack.id, [])
    price = int(getattr(pack, "price_stars", 0) or 0)
    owner_id = int(pack.owner_user_id)
    return EmojiPackOut(
        id=pack.id,
        title=pack.title,
        slug=pack.slug,
        owner_user_id=owner_id,
        owner_name=(authors or {}).get(owner_id, ""),
        is_public=bool(pack.is_public),
        is_installed=pack.id in installed,
        is_owned=int(pack.owner_user_id) == int(user_id),
        is_purchased=pack.id in purchased,
        price_stars=price,
        fee_stars=marketplace_fee_stars(price),
        items=[
            EmojiItemOut(
                id=row.id,
                media_url=row.media_url,
                shortcode=row.shortcode,
                order_index=row.order_index,
            )
            for row in items
        ],
        items_count=len(items),
        share_link=f"https://haneat.app/emoji/{pack.slug}",
    )


def _bundle(svc: EmojiPackService, user_id: int, packs) -> EmojiPackListOut:
    pack_ids = [p.id for p in packs]
    authors = owner_labels(svc.db, [p.owner_user_id for p in packs])
    return EmojiPackListOut(
        items=[
            _pack_out(
                p,
                user_id=user_id,
                installed=svc.installed_pack_ids(user_id),
                purchased=svc.purchased_pack_ids(user_id),
                items_by_pack=svc.emojis_by_pack_ids(pack_ids),
                authors=authors,
            )
            for p in packs
        ]
    )


@router.get("/emoji/my", response_model=EmojiPackListOut)
def list_my_emoji_packs(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = EmojiPackService(db)
    return _bundle(svc, current_user.id, svc.list_my_packs(current_user.id))


@router.get("/emoji/marketplace", response_model=EmojiPackListOut)
def list_emoji_marketplace(
    q: str = Query("", max_length=120),
    limit: int = Query(60, ge=1, le=120),
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = EmojiPackService(db)
    return _bundle(svc, current_user.id, svc.list_marketplace(query=q, limit=limit))


@router.get("/emoji/catalog", response_model=EmojiPackListOut)
def list_emoji_catalog(
    q: str = Query("", max_length=120),
    limit: int = Query(60, ge=1, le=120),
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = EmojiPackService(db)
    return _bundle(svc, current_user.id, svc.list_catalog(query=q, limit=limit))


@router.get("/emoji/by-slug/{slug}", response_model=EmojiPackOut)
def get_emoji_pack_by_slug(
    slug: str,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = EmojiPackService(db)
    pack = svc.get_public_pack_by_slug(slug)
    if not pack:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "pack_not_found")
    return _bundle(svc, current_user.id, [pack]).items[0]


@router.post("/emoji/import/{slug}")
def import_emoji_pack_by_slug(
    slug: str,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = EmojiPackService(db)
    pack = svc.get_public_pack_by_slug(slug)
    if not pack:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "pack_not_found")
    try:
        svc.install_pack(current_user.id, pack.id)
        db.commit()
    except ValueError as exc:
        db.rollback()
        code = str(exc)
        if code == "pack_purchase_required":
            raise HTTPException(
                status.HTTP_402_PAYMENT_REQUIRED,
                {"code": "pack_purchase_required", "message": "Сначала купите пак"},
            )
        raise HTTPException(status.HTTP_403_FORBIDDEN, code) from exc
    return {"ok": True, "pack_id": pack.id}


@router.get("/emoji/resolve")
def resolve_custom_emojis(
    ids: str = Query(""),
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    del current_user
    raw = [part.strip() for part in (ids or "").split(",") if part.strip()]
    parsed: list[int] = []
    for part in raw[:80]:
        try:
            parsed.append(int(part))
        except ValueError:
            continue
    rows = EmojiPackService(db).resolve_emojis(parsed)
    return {
        "items": [
            {"id": row.id, "media_url": row.media_url, "shortcode": row.shortcode}
            for row in rows
        ]
    }


@router.get("/emoji/packs/{pack_id}", response_model=EmojiPackOut)
def get_emoji_pack(
    pack_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = EmojiPackService(db)
    pack = svc.get_pack(pack_id)
    if not pack:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "pack_not_found")
    if not pack.is_public and int(pack.owner_user_id) != int(current_user.id):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "pack_not_found")
    return _bundle(svc, current_user.id, [pack]).items[0]


@router.post("/emoji/packs", response_model=EmojiPackOut)
def create_emoji_pack(
    body: CreateEmojiPackIn,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = EmojiPackService(db)
    try:
        pack = svc.create_pack(current_user.id, body.title, body.is_public)
        db.commit()
        db.refresh(pack)
    except HTTPException:
        db.rollback()
        raise
    except ValueError as exc:
        db.rollback()
        raise HTTPException(status.HTTP_400_BAD_REQUEST, str(exc)) from exc
    return _bundle(svc, current_user.id, [pack]).items[0]


@router.post("/emoji/packs/{pack_id}/items", response_model=EmojiPackOut)
def add_custom_emoji(
    pack_id: int,
    body: AddEmojiIn,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = EmojiPackService(db)
    try:
        svc.add_emoji(
            user_id=current_user.id,
            pack_id=pack_id,
            media_url=body.media_url,
            shortcode=body.shortcode,
        )
        db.commit()
    except ValueError as exc:
        db.rollback()
        code = str(exc)
        if code == "pack_not_found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, code)
        if code == "forbidden":
            raise HTTPException(status.HTTP_403_FORBIDDEN, code)
        raise HTTPException(status.HTTP_400_BAD_REQUEST, code) from exc
    from app.models.emoji_pack import EmojiPack

    pack = db.query(EmojiPack).filter(EmojiPack.id == pack_id).first()
    if not pack:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "pack_not_found")
    return _bundle(svc, current_user.id, [pack]).items[0]


@router.delete("/emoji/packs/{pack_id}/items/{emoji_id}")
def delete_custom_emoji(
    pack_id: int,
    emoji_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = EmojiPackService(db)
    try:
        svc.delete_emoji(current_user.id, pack_id, emoji_id)
        db.commit()
    except ValueError as exc:
        db.rollback()
        code = str(exc)
        if code in ("pack_not_found", "emoji_not_found"):
            raise HTTPException(status.HTTP_404_NOT_FOUND, code)
        if code == "forbidden":
            raise HTTPException(status.HTTP_403_FORBIDDEN, code)
        raise
    return {"ok": True}


@router.post("/emoji/packs/{pack_id}/list")
def list_emoji_pack_for_sale(
    pack_id: int,
    body: ListPriceIn,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    try:
        pack = PackMarketplaceService(db).list_emoji_pack(
            current_user.id, pack_id, body.price_stars
        )
        db.commit()
        db.refresh(pack)
    except HTTPException:
        db.rollback()
        raise
    except ValueError as exc:
        db.rollback()
        code = str(exc)
        if code == "pack_not_found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, code)
        if code == "forbidden":
            raise HTTPException(status.HTTP_403_FORBIDDEN, code)
        raise HTTPException(status.HTTP_400_BAD_REQUEST, code) from exc
    svc = EmojiPackService(db)
    return _bundle(svc, current_user.id, [pack]).items[0]


@router.post("/emoji/packs/{pack_id}/buy")
def buy_emoji_pack(
    pack_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    try:
        result = PackMarketplaceService(db).buy_emoji_pack(current_user.id, pack_id)
        db.commit()
        return result
    except HTTPException:
        db.rollback()
        raise


@router.post("/emoji/packs/{pack_id}/install")
def install_emoji_pack(
    pack_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = EmojiPackService(db)
    try:
        svc.install_pack(current_user.id, pack_id)
        db.commit()
    except ValueError as exc:
        db.rollback()
        code = str(exc)
        if code == "pack_not_found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, code)
        if code == "pack_purchase_required":
            raise HTTPException(
                status.HTTP_402_PAYMENT_REQUIRED,
                {"code": "pack_purchase_required", "message": "Сначала купите пак"},
            )
        raise HTTPException(status.HTTP_403_FORBIDDEN, code) from exc
    return {"ok": True}


@router.delete("/emoji/packs/{pack_id}/install")
def uninstall_emoji_pack(
    pack_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    EmojiPackService(db).uninstall_pack(current_user.id, pack_id)
    db.commit()
    return {"ok": True}

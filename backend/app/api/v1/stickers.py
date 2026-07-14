from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.api.dependencies import get_current_user_required
from app.core.database import get_db
from app.models.sticker import StickerPack
from app.models.user import User
from app.schemas.sticker import (
    AddStickerRequest,
    CreateStickerPackRequest,
    ReorderStickersRequest,
    StickerItemResponse,
    StickerPackListResponse,
    StickerPackResponse,
    UpdateStickerPackRequest,
)
from app.services.sticker_service import StickerService

router = APIRouter()


def _pack_share_link(slug: str) -> str:
    return f"https://haneat.app/stickers/{slug}"


def _pack_response(
    pack: StickerPack,
    *,
    installed_pack_ids: set[int],
    stickers_by_pack_id: dict[int, list],
    sticker_counts: dict[int, int],
) -> StickerPackResponse:
    stickers = stickers_by_pack_id.get(pack.id, [])
    return StickerPackResponse(
        id=pack.id,
        title=pack.title,
        slug=pack.slug,
        owner_user_id=pack.owner_user_id,
        is_public=pack.is_public,
        is_installed=pack.id in installed_pack_ids,
        stickers=[
            StickerItemResponse(
                id=item.id,
                media_url=item.media_url,
                emoji=item.emoji,
                sticker_type=item.sticker_type,
                order_index=item.order_index,
                created_at=item.created_at,
            )
            for item in stickers
        ],
        stickers_count=sticker_counts.get(pack.id, len(stickers)),
        share_link=_pack_share_link(pack.slug),
        created_at=pack.created_at,
        updated_at=pack.updated_at,
    )


@router.get("/stickers/my", response_model=StickerPackListResponse)
async def list_my_sticker_packs(
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = StickerService(db)
    packs = svc.list_my_packs(current_user.id)
    pack_ids = [p.id for p in packs]
    installed = svc.installed_pack_ids(current_user.id)
    stickers_by_pack_id = svc.stickers_by_pack_ids(pack_ids)
    sticker_counts = svc.stickers_count_by_pack_ids(pack_ids)
    return StickerPackListResponse(
        items=[
            _pack_response(
                p,
                installed_pack_ids=installed,
                stickers_by_pack_id=stickers_by_pack_id,
                sticker_counts=sticker_counts,
            )
            for p in packs
        ]
    )


@router.get("/stickers/catalog", response_model=StickerPackListResponse)
async def list_sticker_catalog(
    q: str = Query("", max_length=120),
    limit: int = Query(60, ge=1, le=120),
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = StickerService(db)
    packs = svc.list_catalog_packs(user_id=current_user.id, query=q, limit=limit)
    pack_ids = [p.id for p in packs]
    installed = svc.installed_pack_ids(current_user.id)
    stickers_by_pack_id = svc.stickers_by_pack_ids(pack_ids)
    sticker_counts = svc.stickers_count_by_pack_ids(pack_ids)
    return StickerPackListResponse(
        items=[
            _pack_response(
                p,
                installed_pack_ids=installed,
                stickers_by_pack_id=stickers_by_pack_id,
                sticker_counts=sticker_counts,
            )
            for p in packs
        ]
    )


@router.get("/stickers/packs/{pack_id}", response_model=StickerPackResponse)
async def get_sticker_pack(
    pack_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = StickerService(db)
    pack = svc.get_pack_for_user(current_user.id, pack_id)
    if not pack:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "pack_not_found")
    installed = svc.installed_pack_ids(current_user.id)
    stickers_by_pack_id = svc.stickers_by_pack_ids([pack_id])
    sticker_counts = svc.stickers_count_by_pack_ids([pack_id])
    return _pack_response(
        pack,
        installed_pack_ids=installed,
        stickers_by_pack_id=stickers_by_pack_id,
        sticker_counts=sticker_counts,
    )


@router.get("/stickers/packs/slug/{slug}", response_model=StickerPackResponse)
async def get_sticker_pack_by_slug(
    slug: str,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = StickerService(db)
    pack = svc.get_public_pack_by_slug(slug)
    if not pack:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "pack_not_found")
    installed = svc.installed_pack_ids(current_user.id)
    stickers_by_pack_id = svc.stickers_by_pack_ids([pack.id])
    sticker_counts = svc.stickers_count_by_pack_ids([pack.id])
    return _pack_response(
        pack,
        installed_pack_ids=installed,
        stickers_by_pack_id=stickers_by_pack_id,
        sticker_counts=sticker_counts,
    )


@router.post("/stickers/packs", response_model=StickerPackResponse)
async def create_sticker_pack(
    body: CreateStickerPackRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = StickerService(db)
    try:
        pack = svc.create_pack(
            user_id=current_user.id,
            title=body.title,
            is_public=body.is_public,
        )
        db.commit()
        db.refresh(pack)
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code == "invalid_title":
            raise HTTPException(status.HTTP_400_BAD_REQUEST, code)
        raise
    installed = svc.installed_pack_ids(current_user.id)
    stickers_by_pack_id = svc.stickers_by_pack_ids([pack.id])
    sticker_counts = svc.stickers_count_by_pack_ids([pack.id])
    return _pack_response(
        pack,
        installed_pack_ids=installed,
        stickers_by_pack_id=stickers_by_pack_id,
        sticker_counts=sticker_counts,
    )


@router.post("/stickers/packs/{pack_id}/stickers", response_model=StickerPackResponse)
async def add_sticker_to_pack(
    pack_id: int,
    body: AddStickerRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = StickerService(db)
    try:
        svc.add_sticker(
            user_id=current_user.id,
            pack_id=pack_id,
            media_url=body.media_url,
            emoji=body.emoji,
            sticker_type=body.sticker_type,
        )
        db.commit()
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code == "pack_not_found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, code)
        if code in ("forbidden",):
            raise HTTPException(status.HTTP_403_FORBIDDEN, code)
        if code in ("missing_media", "invalid_sticker_type"):
            raise HTTPException(status.HTTP_400_BAD_REQUEST, code)
        raise
    pack = svc.get_pack_for_user(current_user.id, pack_id)
    if not pack:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "pack_not_found")
    installed = svc.installed_pack_ids(current_user.id)
    stickers_by_pack_id = svc.stickers_by_pack_ids([pack.id])
    sticker_counts = svc.stickers_count_by_pack_ids([pack.id])
    return _pack_response(
        pack,
        installed_pack_ids=installed,
        stickers_by_pack_id=stickers_by_pack_id,
        sticker_counts=sticker_counts,
    )


@router.patch("/stickers/packs/{pack_id}", response_model=StickerPackResponse)
async def update_sticker_pack(
    pack_id: int,
    body: UpdateStickerPackRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    if body.title is None and body.is_public is None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "empty_patch")
    svc = StickerService(db)
    try:
        pack = svc.update_pack(
            user_id=current_user.id,
            pack_id=pack_id,
            title=body.title,
            is_public=body.is_public,
        )
        db.commit()
        db.refresh(pack)
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code == "pack_not_found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, code)
        if code == "forbidden":
            raise HTTPException(status.HTTP_403_FORBIDDEN, code)
        if code == "invalid_title":
            raise HTTPException(status.HTTP_400_BAD_REQUEST, code)
        raise
    installed = svc.installed_pack_ids(current_user.id)
    stickers_by_pack_id = svc.stickers_by_pack_ids([pack.id])
    sticker_counts = svc.stickers_count_by_pack_ids([pack.id])
    return _pack_response(
        pack,
        installed_pack_ids=installed,
        stickers_by_pack_id=stickers_by_pack_id,
        sticker_counts=sticker_counts,
    )


@router.delete("/stickers/packs/{pack_id}/stickers/{sticker_id}")
async def delete_sticker_from_pack(
    pack_id: int,
    sticker_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = StickerService(db)
    try:
        svc.delete_sticker(
            user_id=current_user.id,
            pack_id=pack_id,
            sticker_id=sticker_id,
        )
        db.commit()
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code in ("pack_not_found", "sticker_not_found"):
            raise HTTPException(status.HTTP_404_NOT_FOUND, code)
        if code == "forbidden":
            raise HTTPException(status.HTTP_403_FORBIDDEN, code)
        raise
    return {"ok": True}


@router.post("/stickers/packs/{pack_id}/stickers/reorder")
async def reorder_pack_stickers(
    pack_id: int,
    body: ReorderStickersRequest,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = StickerService(db)
    try:
        svc.reorder_stickers(
            user_id=current_user.id,
            pack_id=pack_id,
            sticker_ids=body.sticker_ids,
        )
        db.commit()
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code == "pack_not_found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, code)
        if code == "forbidden":
            raise HTTPException(status.HTTP_403_FORBIDDEN, code)
        raise
    return {"ok": True}


@router.post("/stickers/packs/{pack_id}/install")
async def install_sticker_pack(
    pack_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = StickerService(db)
    try:
        svc.install_pack(current_user.id, pack_id)
        db.commit()
    except ValueError as e:
        db.rollback()
        code = str(e)
        if code == "pack_not_found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, code)
        if code == "forbidden":
            raise HTTPException(status.HTTP_403_FORBIDDEN, code)
        raise
    return {"ok": True}


@router.post("/stickers/import/{slug}")
async def import_sticker_pack_by_slug(
    slug: str,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = StickerService(db)
    pack = svc.get_public_pack_by_slug(slug)
    if not pack:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "pack_not_found")
    svc.install_pack(current_user.id, pack.id)
    db.commit()
    return {"ok": True, "pack_id": pack.id}


@router.delete("/stickers/packs/{pack_id}/install")
async def uninstall_sticker_pack(
    pack_id: int,
    current_user: User = Depends(get_current_user_required),
    db: Session = Depends(get_db),
):
    svc = StickerService(db)
    svc.uninstall_pack(current_user.id, pack_id)
    db.commit()
    return {"ok": True}

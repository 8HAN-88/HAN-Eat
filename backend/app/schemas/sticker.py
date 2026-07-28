from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, Field


class StickerItemResponse(BaseModel):
    id: int
    media_url: str
    emoji: Optional[str] = None
    sticker_type: str = "static"
    order_index: int = 0
    created_at: datetime


class StickerPackResponse(BaseModel):
    id: int
    title: str
    slug: str
    owner_user_id: int
    is_public: bool
    is_installed: bool = False
    stickers: List[StickerItemResponse] = []
    stickers_count: int = 0
    share_link: Optional[str] = None
    created_at: datetime
    updated_at: Optional[datetime] = None


class StickerPackListResponse(BaseModel):
    items: List[StickerPackResponse]


class CreateStickerPackRequest(BaseModel):
    title: str = Field(..., min_length=2, max_length=120)
    is_public: bool = True


class AddStickerRequest(BaseModel):
    media_url: str = Field(..., min_length=1, max_length=512)
    emoji: Optional[str] = Field(default=None, max_length=16)
    sticker_type: str = Field(default="static", pattern="^(static|animated)$")


class UpdateStickerPackRequest(BaseModel):
    title: Optional[str] = Field(default=None, min_length=2, max_length=120)
    is_public: Optional[bool] = None


class ReorderStickersRequest(BaseModel):
    sticker_ids: List[int] = Field(default_factory=list)


class StickerFavoriteResponse(BaseModel):
    id: int
    media_url: str
    emoji: Optional[str] = None
    sticker_type: str = "static"
    pack_id: int
    created_at: Optional[datetime] = None


class StickerFavoriteListResponse(BaseModel):
    items: List[StickerFavoriteResponse]


class ToggleStickerFavoriteRequest(BaseModel):
    sticker_id: Optional[int] = None
    media_url: Optional[str] = Field(default=None, max_length=512)


class ReplaceStickerFavoritesRequest(BaseModel):
    """Full replace for multi-device sync / local→cloud migration."""

    sticker_ids: List[int] = Field(default_factory=list)
    media_urls: List[str] = Field(default_factory=list)


class StickerPinnedPacksResponse(BaseModel):
    pack_ids: List[int] = Field(default_factory=list)


class ReplaceStickerPinnedPacksRequest(BaseModel):
    pack_ids: List[int] = Field(default_factory=list)

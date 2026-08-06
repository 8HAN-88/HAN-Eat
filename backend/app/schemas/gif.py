"""GIF catalog (Tenor proxy) response schemas."""
from typing import List, Optional

from pydantic import BaseModel, Field


class GifItemResponse(BaseModel):
    id: str
    title: str = ""
    preview_url: str
    url: str
    width: Optional[int] = None
    height: Optional[int] = None


class GifSearchResponse(BaseModel):
    configured: bool = True
    next: Optional[str] = None
    items: List[GifItemResponse] = Field(default_factory=list)

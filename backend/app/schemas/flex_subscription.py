from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, Field


class FlexBlockItem(BaseModel):
    id: int
    key: str
    title: str
    min_level: int
    max_level: int
    sort_order: int = 0


class FlexFeatureItem(BaseModel):
    id: int
    slug: str
    title: str
    description: Optional[str] = None
    icon: Optional[str] = None
    price_rub: Optional[float] = None
    min_level: int
    max_level: int
    default_level: int
    assigned_level: int
    feature_type: str
    movable: bool
    required: bool
    block_key: Optional[str] = None
    status: str = "active"
    available: bool = True
    unlocked: bool = False
    launch_at: Optional[str] = None
    shop_state: Optional[str] = None


class FlexPresetItem(BaseModel):
    key: str
    title: str
    level: int


class FlexMeResponse(BaseModel):
    current_level: int
    price_rub: int
    yearly_price_rub: int = 0
    next_level: Optional[int] = None
    next_price_rub: Optional[int] = None
    max_level: int
    base_price_rub: int
    step_price_rub: int
    yearly_months: int = 10
    plan: str = "monthly"
    active: bool
    auto_renew: bool = False
    pending_level: Optional[int] = None
    pending_plan: Optional[str] = None
    pending_level_at: Optional[str] = None
    expires_at: Optional[str] = None
    next_feature: Optional[FlexFeatureItem] = None
    levels: List[FlexFeatureItem]
    blocks: List[FlexBlockItem]
    presets: List[FlexPresetItem] = []


class FlexShopResponse(BaseModel):
    current_level: int
    features: List[FlexFeatureItem]


class FlexPreviewResponse(BaseModel):
    level: int
    price_rub: int
    period_price_rub: int = 0
    plan: str = "monthly"
    current_plan: str = "monthly"
    next_level: Optional[int] = None
    next_price_rub: Optional[int] = None
    features: List[FlexFeatureItem]
    next_feature: Optional[FlexFeatureItem] = None
    disabled: List[FlexFeatureItem] = []
    added: List[FlexFeatureItem] = []
    needs_confirm: bool = False
    delta_rub: int = 0
    kind: str = "new"
    amount_due: float = 0
    credit_rub: float = 0
    remaining_days: int = 0
    keep_expires: bool = False
    needs_payment: bool = True
    applies_at: Optional[str] = None
    pending_plan: Optional[str] = None


class FlexSlotIn(BaseModel):
    feature_id: int
    level: int = Field(ge=1, le=16)


class FlexSaveLayoutRequest(BaseModel):
    slots: List[FlexSlotIn]


class FlexMoveRequest(BaseModel):
    feature_id: int
    target_level: int = Field(ge=1, le=16)


class FlexLevelRequest(BaseModel):
    level: int = Field(ge=1, le=16)
    plan: str = "monthly"


class FlexGiftRequest(BaseModel):
    recipient_user_id: int
    level: int = Field(ge=1, le=16)
    plan: str = "monthly"


class FlexFeatureWrite(BaseModel):
    slug: Optional[str] = None
    title: Optional[str] = None
    description: Optional[str] = None
    icon: Optional[str] = None
    price_rub: Optional[float] = None
    min_level: Optional[int] = Field(default=None, ge=1, le=16)
    max_level: Optional[int] = Field(default=None, ge=1, le=16)
    default_level: Optional[int] = Field(default=None, ge=1, le=16)
    feature_type: Optional[str] = None
    movable: Optional[bool] = None
    required: Optional[bool] = None
    block_key: Optional[str] = None
    launch_at: Optional[datetime] = None
    status: Optional[str] = None
    available: Optional[bool] = None
    sort_order: Optional[int] = None


class FlexBlockWrite(BaseModel):
    key: Optional[str] = None
    title: Optional[str] = None
    min_level: Optional[int] = Field(default=None, ge=1, le=16)
    max_level: Optional[int] = Field(default=None, ge=1, le=16)
    sort_order: Optional[int] = None

"""First-party ads: advertiser campaigns, review, and live inventory."""
from __future__ import annotations

from datetime import datetime
from typing import Any, Optional
from urllib.parse import urlparse

from sqlalchemy.orm import Session

from app.models.ad import AdCampaign, AdCreative, AdHide
from app.models.community import Channel
from app.models.post import Post
from app.models.user import User
from app.services.subscription_service import SubscriptionService

SURFACES = ("feed", "reels", "channel")
DESTINATION_TYPES = ("url", "channel", "post")
EDITABLE_STATUSES = ("draft", "rejected")
MAX_ACTIVE_CAMPAIGNS = 20

STATUS_DRAFT = "draft"
STATUS_PENDING = "pending_review"
STATUS_APPROVED = "approved"
STATUS_REJECTED = "rejected"
STATUS_PAUSED = "paused"
STATUS_ARCHIVED = "archived"


class AdsError(Exception):
    def __init__(self, message: str, status_code: int = 400):
        super().__init__(message)
        self.message = message
        self.status_code = status_code


def _now() -> datetime:
    return datetime.utcnow()


def _clip(value: Optional[str], limit: int) -> str:
    return (value or "").strip()[:limit]


def _parse_surfaces(raw: Any) -> list[str]:
    if raw is None:
        return ["feed"]
    if isinstance(raw, str):
        raw = [raw]
    if not isinstance(raw, (list, tuple)):
        raise AdsError("Укажите площадки размещения")
    out: list[str] = []
    for item in raw:
        key = str(item or "").strip().lower()
        if key not in SURFACES:
            raise AdsError(f"Неизвестная площадка: {item}")
        if key not in out:
            out.append(key)
    if not out:
        raise AdsError("Выберите хотя бы одну площадку: лента, рилсы или канал")
    return out


def _parse_optional_dt(value: Any) -> Optional[datetime]:
    if value is None or value == "":
        return None
    if isinstance(value, datetime):
        return value
    text = str(value).strip()
    if not text:
        return None
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00")).replace(tzinfo=None)
    except ValueError as exc:
        raise AdsError("Некорректная дата") from exc


def _valid_http_url(url: str) -> bool:
    parsed = urlparse(url.strip())
    if parsed.scheme not in ("https", "http"):
        return False
    host = (parsed.hostname or "").strip().lower()
    return bool(host)


def campaign_is_live(campaign: AdCampaign, now: Optional[datetime] = None) -> bool:
    if campaign.status != STATUS_APPROVED:
        return False
    moment = now or _now()
    if campaign.starts_at and campaign.starts_at > moment:
        return False
    if campaign.ends_at and campaign.ends_at < moment:
        return False
    return True


class AdsService:
    def __init__(self, db: Session):
        self.db = db

    def _get_owned(self, campaign_id: int, user_id: int) -> AdCampaign:
        campaign = (
            self.db.query(AdCampaign)
            .filter(AdCampaign.id == campaign_id, AdCampaign.advertiser_id == user_id)
            .first()
        )
        if not campaign:
            raise AdsError("Кампания не найдена", 404)
        return campaign

    def _creative_for(self, campaign_id: int) -> Optional[AdCreative]:
        return (
            self.db.query(AdCreative)
            .filter(AdCreative.campaign_id == campaign_id)
            .order_by(AdCreative.id.asc())
            .first()
        )

    def _count_active(self, user_id: int) -> int:
        return (
            self.db.query(AdCampaign.id)
            .filter(
                AdCampaign.advertiser_id == user_id,
                AdCampaign.status != STATUS_ARCHIVED,
            )
            .count()
        )

    def _validate_destination(
        self,
        destination_type: str,
        destination_url: Optional[str],
        destination_channel_id: Optional[int],
        destination_post_id: Optional[int],
        *,
        require_ready: bool,
    ) -> None:
        if destination_type not in DESTINATION_TYPES:
            raise AdsError("Тип перехода: ссылка, канал или пост")
        if destination_type == "url":
            url = (destination_url or "").strip()
            if require_ready and not url:
                raise AdsError("Укажите ссылку для перехода")
            if url and not _valid_http_url(url):
                raise AdsError("Ссылка должна начинаться с https://")
            return
        if destination_type == "channel":
            if not destination_channel_id:
                if require_ready:
                    raise AdsError("Укажите канал для перехода")
                return
            channel = (
                self.db.query(Channel.id)
                .filter(Channel.id == destination_channel_id)
                .first()
            )
            if not channel:
                raise AdsError("Канал не найден", 404)
            return
        if not destination_post_id:
            if require_ready:
                raise AdsError("Укажите пост для перехода")
            return
        post = (
            self.db.query(Post.id)
            .filter(Post.id == destination_post_id, Post.deleted_at.is_(None))
            .first()
        )
        if not post:
            raise AdsError("Пост не найден", 404)

    def _apply_payload(
        self,
        campaign: AdCampaign,
        payload: dict[str, Any],
        *,
        user: User,
        require_ready: bool = False,
    ) -> AdCreative:
        if "name" in payload or campaign.name is None:
            name = _clip(payload.get("name", campaign.name), 80)
            if not name:
                raise AdsError("Введите название кампании")
            campaign.name = name
        if "surfaces" in payload or not campaign.surfaces:
            campaign.surfaces = _parse_surfaces(payload.get("surfaces", campaign.surfaces))
        if "destination_type" in payload:
            campaign.destination_type = str(payload.get("destination_type") or "url")
        if "destination_url" in payload:
            url = _clip(payload.get("destination_url"), 2000) or None
            campaign.destination_url = url
        if "destination_channel_id" in payload:
            raw = payload.get("destination_channel_id")
            campaign.destination_channel_id = int(raw) if raw not in (None, "") else None
        if "destination_post_id" in payload:
            raw = payload.get("destination_post_id")
            campaign.destination_post_id = int(raw) if raw not in (None, "") else None
        if "starts_at" in payload:
            campaign.starts_at = _parse_optional_dt(payload.get("starts_at"))
        if "ends_at" in payload:
            campaign.ends_at = _parse_optional_dt(payload.get("ends_at"))
        if campaign.starts_at and campaign.ends_at and campaign.ends_at <= campaign.starts_at:
            raise AdsError("Дата окончания должна быть позже начала")
        if "daily_cap" in payload:
            raw_cap = payload.get("daily_cap")
            if raw_cap in (None, ""):
                campaign.daily_cap = None
            else:
                cap = int(raw_cap)
                if cap < 1 or cap > 100000:
                    raise AdsError("Дневной лимит показов — от 1 до 100000")
                campaign.daily_cap = cap

        self._validate_destination(
            campaign.destination_type,
            campaign.destination_url,
            campaign.destination_channel_id,
            campaign.destination_post_id,
            require_ready=require_ready,
        )

        creative = self._creative_for(campaign.id)
        if creative is None:
            creative = AdCreative(campaign_id=campaign.id)
            self.db.add(creative)
            self.db.flush()

        raw_creative = payload.get("creative")
        if isinstance(raw_creative, dict):
            if "title" in raw_creative:
                creative.title = _clip(raw_creative.get("title"), 80)
            if "body" in raw_creative:
                creative.body = _clip(raw_creative.get("body"), 500)
            if "cta_label" in raw_creative:
                creative.cta_label = _clip(raw_creative.get("cta_label"), 32) or "Подробнее"
            if "image_url" in raw_creative:
                image = _clip(raw_creative.get("image_url"), 2000) or None
                if image and not _valid_http_url(image):
                    raise AdsError("Некорректная ссылка на изображение")
                creative.image_url = image
            if "video_url" in raw_creative:
                video = _clip(raw_creative.get("video_url"), 2000) or None
                if video and not _valid_http_url(video):
                    raise AdsError("Некорректная ссылка на видео")
                creative.video_url = video
            if "advertiser_name" in raw_creative:
                creative.advertiser_name = _clip(raw_creative.get("advertiser_name"), 80) or None

        if not creative.advertiser_name:
            creative.advertiser_name = _clip(user.name, 80) or None
        if not creative.cta_label:
            creative.cta_label = "Подробнее"

        if require_ready:
            if not (creative.title or "").strip():
                raise AdsError("Укажите заголовок объявления")
            if not ((creative.image_url or "").strip() or (creative.body or "").strip()):
                raise AdsError("Добавьте текст или изображение")
        return creative

    def serialize(
        self,
        campaign: AdCampaign,
        *,
        include_advertiser: bool = False,
    ) -> dict[str, Any]:
        creative = self._creative_for(campaign.id)
        payload: dict[str, Any] = {
            "id": campaign.id,
            "advertiser_id": campaign.advertiser_id,
            "name": campaign.name,
            "status": campaign.status,
            "is_live": campaign_is_live(campaign),
            "surfaces": list(campaign.surfaces or []),
            "destination_type": campaign.destination_type,
            "destination_url": campaign.destination_url,
            "destination_channel_id": campaign.destination_channel_id,
            "destination_post_id": campaign.destination_post_id,
            "starts_at": campaign.starts_at.isoformat() if campaign.starts_at else None,
            "ends_at": campaign.ends_at.isoformat() if campaign.ends_at else None,
            "daily_cap": campaign.daily_cap,
            "rejection_reason": campaign.rejection_reason,
            "reviewed_at": campaign.reviewed_at.isoformat() if campaign.reviewed_at else None,
            "created_at": campaign.created_at.isoformat() if campaign.created_at else None,
            "updated_at": campaign.updated_at.isoformat() if campaign.updated_at else None,
            "creative": {
                "id": creative.id if creative else None,
                "title": creative.title if creative else "",
                "body": creative.body if creative else "",
                "cta_label": (creative.cta_label if creative else None) or "Подробнее",
                "image_url": creative.image_url if creative else None,
                "video_url": creative.video_url if creative else None,
                "advertiser_name": creative.advertiser_name if creative else None,
            },
        }
        if include_advertiser:
            advertiser = (
                self.db.query(User).filter(User.id == campaign.advertiser_id).first()
            )
            payload["advertiser"] = {
                "id": advertiser.id if advertiser else campaign.advertiser_id,
                "name": advertiser.name if advertiser else None,
                "username": advertiser.username if advertiser else None,
            }
        return payload

    def list_mine(self, user_id: int) -> list[dict[str, Any]]:
        rows = (
            self.db.query(AdCampaign)
            .filter(AdCampaign.advertiser_id == user_id)
            .order_by(AdCampaign.updated_at.desc(), AdCampaign.id.desc())
            .limit(100)
            .all()
        )
        return [self.serialize(row) for row in rows]

    def get_mine(self, campaign_id: int, user_id: int) -> dict[str, Any]:
        return self.serialize(self._get_owned(campaign_id, user_id))

    def create(self, user: User, payload: dict[str, Any]) -> dict[str, Any]:
        if self._count_active(user.id) >= MAX_ACTIVE_CAMPAIGNS:
            raise AdsError(
                f"Не больше {MAX_ACTIVE_CAMPAIGNS} активных кампаний. "
                "Архивируйте старые, чтобы создать новую."
            )
        campaign = AdCampaign(
            advertiser_id=user.id,
            name="Новая кампания",
            status=STATUS_DRAFT,
            surfaces=["feed"],
            destination_type="url",
        )
        self.db.add(campaign)
        self.db.flush()
        self._apply_payload(campaign, payload, user=user)
        self.db.commit()
        self.db.refresh(campaign)
        return self.serialize(campaign)

    def update(self, campaign_id: int, user: User, payload: dict[str, Any]) -> dict[str, Any]:
        campaign = self._get_owned(campaign_id, user.id)
        if campaign.status not in EDITABLE_STATUSES:
            raise AdsError("Редактировать можно черновик или отклонённую кампанию")
        if campaign.status == STATUS_REJECTED:
            campaign.status = STATUS_DRAFT
            campaign.rejection_reason = None
        self._apply_payload(campaign, payload, user=user)
        self.db.commit()
        self.db.refresh(campaign)
        return self.serialize(campaign)

    def submit(self, campaign_id: int, user: User, payload: Optional[dict[str, Any]] = None) -> dict[str, Any]:
        campaign = self._get_owned(campaign_id, user.id)
        if campaign.status not in (*EDITABLE_STATUSES, STATUS_PENDING):
            raise AdsError("На модерацию можно отправить только черновик")
        self._apply_payload(campaign, payload or {}, user=user, require_ready=True)
        if user.is_admin or user.is_moderator:
            campaign.status = STATUS_APPROVED
            campaign.reviewed_by_user_id = user.id
            campaign.reviewed_at = _now()
            campaign.rejection_reason = None
        else:
            campaign.status = STATUS_PENDING
            campaign.reviewed_by_user_id = None
            campaign.reviewed_at = None
            campaign.rejection_reason = None
        self.db.commit()
        self.db.refresh(campaign)
        return self.serialize(campaign)

    def pause(self, campaign_id: int, user: User) -> dict[str, Any]:
        campaign = self._get_owned(campaign_id, user.id)
        if campaign.status != STATUS_APPROVED:
            raise AdsError("Пауза доступна только для одобренной кампании")
        campaign.status = STATUS_PAUSED
        self.db.commit()
        self.db.refresh(campaign)
        return self.serialize(campaign)

    def resume(self, campaign_id: int, user: User) -> dict[str, Any]:
        campaign = self._get_owned(campaign_id, user.id)
        if campaign.status != STATUS_PAUSED:
            raise AdsError("Возобновить можно только поставленную на паузу кампанию")
        campaign.status = STATUS_APPROVED
        self.db.commit()
        self.db.refresh(campaign)
        return self.serialize(campaign)

    def archive(self, campaign_id: int, user: User) -> dict[str, Any]:
        campaign = self._get_owned(campaign_id, user.id)
        if campaign.status == STATUS_PENDING:
            raise AdsError("Дождитесь решения модерации или отзовите кампанию через правку")
        campaign.status = STATUS_ARCHIVED
        self.db.commit()
        self.db.refresh(campaign)
        return self.serialize(campaign)

    def list_review_queue(self, *, status: str = STATUS_PENDING) -> list[dict[str, Any]]:
        allowed = {STATUS_PENDING, STATUS_APPROVED, STATUS_REJECTED}
        if status not in allowed:
            status = STATUS_PENDING
        rows = (
            self.db.query(AdCampaign)
            .filter(AdCampaign.status == status)
            .order_by(AdCampaign.updated_at.asc(), AdCampaign.id.asc())
            .limit(100)
            .all()
        )
        return [self.serialize(row, include_advertiser=True) for row in rows]

    def approve(self, campaign_id: int, reviewer: User) -> dict[str, Any]:
        campaign = self.db.query(AdCampaign).filter(AdCampaign.id == campaign_id).first()
        if not campaign:
            raise AdsError("Кампания не найдена", 404)
        if campaign.status not in (STATUS_PENDING, STATUS_REJECTED, STATUS_PAUSED):
            raise AdsError("Эту кампанию нельзя одобрить")
        campaign.status = STATUS_APPROVED
        campaign.reviewed_by_user_id = reviewer.id
        campaign.reviewed_at = _now()
        campaign.rejection_reason = None
        self.db.commit()
        self.db.refresh(campaign)
        return self.serialize(campaign, include_advertiser=True)

    def reject(self, campaign_id: int, reviewer: User, reason: Optional[str]) -> dict[str, Any]:
        campaign = self.db.query(AdCampaign).filter(AdCampaign.id == campaign_id).first()
        if not campaign:
            raise AdsError("Кампания не найдена", 404)
        if campaign.status not in (STATUS_PENDING, STATUS_APPROVED, STATUS_PAUSED):
            raise AdsError("Эту кампанию нельзя отклонить")
        text = _clip(reason, 400)
        if not text:
            raise AdsError("Укажите причину отклонения")
        campaign.status = STATUS_REJECTED
        campaign.reviewed_by_user_id = reviewer.id
        campaign.reviewed_at = _now()
        campaign.rejection_reason = text
        self.db.commit()
        self.db.refresh(campaign)
        return self.serialize(campaign, include_advertiser=True)

    def pick_live_for_surface(
        self,
        *,
        surface: str,
        user_id: int,
        exclude_campaign_ids: Optional[set[int]] = None,
    ) -> Optional[dict[str, Any]]:
        if surface not in SURFACES:
            return None
        try:
            if SubscriptionService(self.db).has_entitlement(user_id, "ad_free"):
                return None
        except Exception:
            pass
        hidden_ids = {
            row[0]
            for row in self.db.query(AdHide.campaign_id)
            .filter(AdHide.user_id == user_id)
            .all()
        }
        rows = (
            self.db.query(AdCampaign)
            .filter(AdCampaign.status == STATUS_APPROVED)
            .order_by(AdCampaign.updated_at.desc(), AdCampaign.id.desc())
            .limit(50)
            .all()
        )
        now = _now()
        skip = exclude_campaign_ids or set()
        for campaign in rows:
            if campaign.id in skip or campaign.id in hidden_ids:
                continue
            if surface not in list(campaign.surfaces or []):
                continue
            if not campaign_is_live(campaign, now):
                continue
            creative = self._creative_for(campaign.id)
            if not creative or not (creative.title or "").strip():
                continue
            item = self.serialize(campaign)
            return {
                "kind": "ad",
                "surface": surface,
                "campaign_id": campaign.id,
                "creative_id": creative.id,
                "label": "Реклама",
                "advertiser_name": creative.advertiser_name,
                "title": creative.title,
                "body": creative.body,
                "cta_label": creative.cta_label or "Подробнее",
                "image_url": creative.image_url,
                "video_url": creative.video_url,
                "destination_type": campaign.destination_type,
                "destination_url": campaign.destination_url,
                "destination_channel_id": campaign.destination_channel_id,
                "destination_post_id": campaign.destination_post_id,
                "campaign": item,
            }
        return None

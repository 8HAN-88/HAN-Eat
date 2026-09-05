from datetime import datetime, timedelta

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.models.ad import AdCampaign, AdCreative, AdHide
from app.models.subscription import Subscription
from app.models.user import User
from app.services.ads_service import (
    AdsError,
    AdsService,
    STATUS_APPROVED,
    STATUS_PENDING,
    normalize_destination_url,
    strip_ad_items,
    valid_media_url,
)


@pytest.fixture()
def db_session():
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    from app.core.database import Base

    Base.metadata.create_all(
        bind=engine,
        tables=[
            User.__table__,
            Subscription.__table__,
            AdCampaign.__table__,
            AdCreative.__table__,
            AdHide.__table__,
        ],
    )
    Session = sessionmaker(bind=engine)
    session = Session()
    try:
        yield session
    finally:
        session.close()
        engine.dispose()


def _user(db, user_id: int = 1, *, admin: bool = False) -> User:
    u = User(
        id=user_id,
        email=f"u{user_id}@t.test",
        password_hash="h",
        name=f"U{user_id}",
        is_admin=admin,
        is_moderator=admin,
    )
    db.add(u)
    db.commit()
    return u


def _ready_payload(**overrides):
    data = {
        "name": "Летняя акция",
        "surfaces": ["feed", "reels"],
        "destination_type": "url",
        "destination_url": "https://haneat.app",
        "creative": {
            "title": "Попробуйте HanWe",
            "body": "Чаты, лента и каналы в одном месте",
            "cta_label": "Открыть",
            "image_url": "https://cdn.haneat.com/ads/demo.jpg",
            "advertiser_name": "HanWe",
        },
    }
    data.update(overrides)
    return data


def test_create_and_submit_goes_to_review(db_session):
    user = _user(db_session)
    svc = AdsService(db_session)
    created = svc.create(user, {"name": "Черновик"})
    assert created["status"] == "draft"
    assert created["creative"]["cta_label"] == "Подробнее"

    submitted = svc.submit(created["id"], user, _ready_payload())
    assert submitted["status"] == STATUS_PENDING
    assert submitted["is_live"] is False


def test_admin_submit_auto_approves_and_is_live(db_session):
    admin = _user(db_session, admin=True)
    svc = AdsService(db_session)
    created = svc.create(admin, _ready_payload())
    submitted = svc.submit(created["id"], admin)
    assert submitted["status"] == STATUS_APPROVED
    assert submitted["is_live"] is True

    picked = svc.pick_live_for_surface(surface="feed", user_id=admin.id)
    assert picked is not None
    assert picked["kind"] == "ad"
    assert picked["title"] == "Попробуйте HanWe"
    assert picked["surface"] == "feed"


def test_pick_live_respects_surface_and_hide(db_session):
    admin = _user(db_session, admin=True)
    viewer = _user(db_session, user_id=2)
    svc = AdsService(db_session)
    created = svc.create(admin, _ready_payload(surfaces=["reels"]))
    svc.submit(created["id"], admin)

    assert svc.pick_live_for_surface(surface="feed", user_id=viewer.id) is None
    picked = svc.pick_live_for_surface(surface="reels", user_id=viewer.id)
    assert picked is not None

    db_session.add(AdHide(campaign_id=created["id"], user_id=viewer.id))
    db_session.commit()
    assert svc.pick_live_for_surface(surface="reels", user_id=viewer.id) is None


def test_ad_free_skips_inventory(db_session, monkeypatch):
    admin = _user(db_session, admin=True)
    viewer = _user(db_session, user_id=2)
    svc = AdsService(db_session)
    created = svc.create(admin, _ready_payload())
    svc.submit(created["id"], admin)

    monkeypatch.setattr(
        "app.services.ads_service.SubscriptionService.has_entitlement",
        lambda self, user_id, slug: slug == "ad_free" and user_id == viewer.id,
    )
    assert svc.pick_live_for_surface(surface="feed", user_id=viewer.id) is None
    assert svc.pick_live_for_surface(surface="feed", user_id=admin.id) is not None


def test_pause_resume_and_review(db_session):
    advertiser = _user(db_session)
    reviewer = _user(db_session, user_id=9, admin=True)
    svc = AdsService(db_session)
    created = svc.create(advertiser, _ready_payload())
    pending = svc.submit(created["id"], advertiser)
    approved = svc.approve(pending["id"], reviewer)
    assert approved["is_live"] is True
    with pytest.raises(AdsError):
        svc.update(approved["id"], advertiser, {"name": "нельзя"})

    paused = svc.pause(approved["id"], advertiser)
    assert paused["status"] == "paused"
    assert paused["is_live"] is False

    resumed = svc.resume(approved["id"], advertiser)
    assert resumed["status"] == STATUS_APPROVED

    rejected = svc.reject(approved["id"], reviewer, "Слишком агрессивный оффер")
    assert rejected["status"] == "rejected"
    assert rejected["rejection_reason"] == "Слишком агрессивный оффер"

    updated = svc.update(approved["id"], advertiser, {"name": "Исправленная"})
    assert updated["status"] == "draft"
    assert updated["name"] == "Исправленная"


def test_future_schedule_is_not_live(db_session):
    admin = _user(db_session, admin=True)
    svc = AdsService(db_session)
    starts = (datetime.utcnow() + timedelta(days=2)).isoformat()
    created = svc.create(admin, _ready_payload(starts_at=starts))
    submitted = svc.submit(created["id"], admin)
    assert submitted["status"] == STATUS_APPROVED
    assert submitted["is_live"] is False
    assert svc.pick_live_for_surface(surface="feed", user_id=admin.id) is None


def test_client_next_step_and_auto_name(db_session):
    user = _user(db_session)
    svc = AdsService(db_session)
    created = svc.create(user, {"creative": {"title": "Кофе с собой"}})
    assert created["name"] == "Кофе с собой"
    assert created["ready_to_submit"] is False
    assert "destination" in created["missing"]
    assert "заявку" in created["next_step"].lower() or "Допишите" in created["next_step"]

    filled = svc.update(
        created["id"],
        user,
        _ready_payload(name="Кофе с собой"),
    )
    assert filled["ready_to_submit"] is True
    assert "Проверьте" in filled["next_step"]


def test_insert_feed_ad_after_enough_posts(db_session):
    admin = _user(db_session, admin=True)
    viewer = _user(db_session, user_id=2)
    svc = AdsService(db_session)
    created = svc.create(admin, _ready_payload())
    svc.submit(created["id"], admin)
    posts = [{"kind": "post", "id": i} for i in range(1, 10)]
    mixed = svc.insert_into_feed_items(
        posts,
        viewer.id,
        following_only=False,
        feed_type="all",
        cursor=None,
    )
    kinds = [item.get("kind") for item in mixed]
    assert kinds.count("ad") == 1
    assert kinds.index("ad") >= 3
    assert (
        svc.insert_into_feed_items(
            posts[:2],
            viewer.id,
            following_only=False,
            feed_type="all",
            cursor=None,
        )
        == posts[:2]
    )


def test_hide_removes_from_inventory(db_session):
    admin = _user(db_session, admin=True)
    viewer = _user(db_session, user_id=2)
    svc = AdsService(db_session)
    created = svc.create(admin, _ready_payload())
    svc.submit(created["id"], admin)
    svc.hide_for_user(user_id=viewer.id, campaign_id=created["id"])
    assert svc.pick_live_for_surface(surface="feed", user_id=viewer.id) is None


def test_submit_requires_title_and_destination(db_session):
    user = _user(db_session)
    svc = AdsService(db_session)
    created = svc.create(user, {"name": "Пустая"})
    with pytest.raises(AdsError):
        svc.submit(created["id"], user, {"creative": {"title": ""}})


def test_draft_allows_empty_name_and_relative_image(db_session):
    user = _user(db_session)
    svc = AdsService(db_session)
    created = svc.create(user, {"name": ""})
    assert created["name"] == "Новая кампания"

    updated = svc.update(
        created["id"],
        user,
        {
            "name": "",
            "destination_type": "url",
            "destination_url": "haneat.app/promo",
            "destination_channel_id": None,
            "destination_post_id": None,
            "creative": {
                "title": "Акция",
                "image_url": "/api/v1/uploads/file/uploads/user_1/ad.jpg",
            },
        },
    )
    assert updated["name"] == "Акция"
    assert updated["destination_url"] == "https://haneat.app/promo"
    assert updated["destination_channel_id"] is None
    image = updated["creative"]["image_url"]
    assert image
    assert "uploads/user_1/ad.jpg" in image


def test_url_and_media_helpers():
    assert normalize_destination_url("site.ru") == "https://site.ru"
    assert normalize_destination_url("https://ok.example") == "https://ok.example"
    assert valid_media_url("/uploads/file/uploads/user_1/a.jpg") is True
    assert valid_media_url("uploads/user_1/a.jpg") is True
    assert valid_media_url("javascript:alert(1)") is False
    assert strip_ad_items(
        [{"kind": "post", "id": 1}, {"kind": "ad", "campaign_id": 9}, {"kind": "post", "id": 2}]
    ) == [{"kind": "post", "id": 1}, {"kind": "post", "id": 2}]


def test_insert_feed_strips_stale_ads_and_supports_reels_filter(db_session):
    admin = _user(db_session, admin=True)
    viewer = _user(db_session, user_id=2)
    svc = AdsService(db_session)
    created = svc.create(admin, _ready_payload(surfaces=["reels"]))
    svc.submit(created["id"], admin)
    stale = [{"kind": "post", "id": i} for i in range(1, 10)]
    stale.insert(4, {"kind": "ad", "campaign_id": 999, "title": "старая"})
    mixed = svc.insert_into_feed_items(
        stale,
        viewer.id,
        following_only=False,
        feed_type="reels",
        cursor=None,
    )
    ads = [item for item in mixed if item.get("kind") == "ad"]
    assert len(ads) == 1
    assert ads[0]["campaign_id"] == created["id"]
    assert svc.insert_into_feed_items(
        stale,
        viewer.id,
        following_only=False,
        feed_type="all",
        cursor=None,
    ) == strip_ad_items(stale)

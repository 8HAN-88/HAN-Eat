from datetime import datetime, timedelta

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

from app.models.paid_features import PaidContentPurchase, PostBoost
from app.models.post import Post
from app.services.paid_features_service import PaidFeaturesService, expire_due_post_boosts


@pytest.fixture()
def db_session():
    engine = create_engine("sqlite:///:memory:")
    with engine.begin() as conn:
        conn.exec_driver_sql(
            """
            CREATE TABLE users (
                id INTEGER PRIMARY KEY,
                email VARCHAR(255) NOT NULL,
                email_verified_at DATETIME,
                password_hash VARCHAR(255) NOT NULL,
                name VARCHAR(255) NOT NULL,
                username VARCHAR(100),
                avatar_url TEXT,
                bio TEXT,
                is_private BOOLEAN DEFAULT 0,
                is_verified BOOLEAN DEFAULT 0,
                subscription_type VARCHAR(20) DEFAULT 'free',
                subscription_status VARCHAR(20) DEFAULT 'active',
                subscription_expires_at DATETIME,
                subscription_platform VARCHAR(20),
                subscription_auto_renew BOOLEAN DEFAULT 0,
                yookassa_payment_method_id VARCHAR(64),
                tbank_rebill_id VARCHAR(64),
                legal_consent_version VARCHAR(32),
                legal_consent_at DATETIME,
                scan_credits INTEGER DEFAULT 5,
                last_scan_credit_at DATETIME,
                meal_plan_last_generated_at DATETIME,
                meal_plan_cooldown_ends_at DATETIME,
                is_admin BOOLEAN DEFAULT 0,
                is_moderator BOOLEAN DEFAULT 0,
                trust_score FLOAT DEFAULT 0.5,
                account_warnings INTEGER DEFAULT 0,
                shadow_moderation BOOLEAN DEFAULT 0,
                banned_at DATETIME,
                fcm_token VARCHAR(500),
                device_platform VARCHAR(20),
                country_code VARCHAR(2),
                last_seen_at DATETIME,
                phone_hash VARCHAR(64),
                phone_e164 VARCHAR(20),
                phone_linked_at DATETIME,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                deleted_at DATETIME
            )
            """
        )
        conn.exec_driver_sql(
            """
            CREATE TABLE posts (
                id INTEGER PRIMARY KEY,
                user_id INTEGER NOT NULL,
                channel_id INTEGER,
                type VARCHAR(20) NOT NULL,
                title VARCHAR(500),
                description TEXT,
                body JSON,
                status VARCHAR(20) DEFAULT 'pending',
                visibility VARCHAR(20) DEFAULT 'public',
                is_global_visible BOOLEAN DEFAULT 1,
                is_indexed BOOLEAN DEFAULT 1,
                publish_to TEXT,
                tags TEXT,
                location_name VARCHAR(255),
                location_lat VARCHAR,
                location_lng VARCHAR,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                published_at DATETIME,
                scheduled_publish_at DATETIME,
                deleted_at DATETIME,
                views_count INTEGER DEFAULT 0,
                is_promoted BOOLEAN DEFAULT 0,
                is_pinned BOOLEAN DEFAULT 0,
                is_exclusive BOOLEAN DEFAULT 0,
                is_paid BOOLEAN DEFAULT 0,
                price_stars INTEGER DEFAULT 0,
                preview_mode VARCHAR(20) DEFAULT 'teaser',
                hidden_from_recommendations BOOLEAN DEFAULT 0
            )
            """
        )
        conn.exec_driver_sql(
            """
            CREATE TABLE channels (
                id INTEGER PRIMARY KEY,
                name VARCHAR(255) NOT NULL,
                slug VARCHAR(100) NOT NULL,
                description TEXT,
                cover_url TEXT,
                avatar_url TEXT,
                admin_user_id INTEGER NOT NULL,
                is_public BOOLEAN DEFAULT 1,
                recipe_visibility_mode VARCHAR(20) DEFAULT 'mixed',
                category VARCHAR(50),
                tags TEXT,
                rules TEXT,
                members_count INTEGER DEFAULT 0,
                posts_count INTEGER DEFAULT 0,
                auto_publish_to_feed BOOLEAN DEFAULT 1,
                auto_publish_to_menu BOOLEAN DEFAULT 0,
                allow_comments BOOLEAN DEFAULT 1,
                allow_likes BOOLEAN DEFAULT 1,
                allow_reposts BOOLEAN DEFAULT 1,
                role_permissions JSON,
                accent_color VARCHAR(16),
                auto_publish_reels BOOLEAN DEFAULT 1,
                is_paid BOOLEAN DEFAULT 0,
                monthly_price_stars INTEGER DEFAULT 0,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
            """
        )
        conn.exec_driver_sql(
            """
            CREATE TABLE star_transactions (
                id INTEGER PRIMARY KEY,
                user_id INTEGER NOT NULL,
                counterparty_user_id INTEGER,
                amount INTEGER NOT NULL,
                type VARCHAR(32) NOT NULL,
                status VARCHAR(24) NOT NULL DEFAULT 'completed',
                reference_type VARCHAR(32),
                reference_id INTEGER,
                provider VARCHAR(32),
                provider_payment_id VARCHAR(128),
                idempotency_key VARCHAR(128) UNIQUE,
                meta JSON,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL
            )
            """
        )
        conn.exec_driver_sql(
            """
            CREATE TABLE paid_content_purchases (
                id INTEGER PRIMARY KEY,
                user_id INTEGER NOT NULL,
                post_id INTEGER NOT NULL,
                author_id INTEGER,
                amount_stars INTEGER NOT NULL,
                status VARCHAR(24) NOT NULL DEFAULT 'completed',
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,
                UNIQUE(user_id, post_id)
            )
            """
        )
        conn.exec_driver_sql(
            """
            CREATE TABLE creator_balances (
                user_id INTEGER PRIMARY KEY,
                available_stars INTEGER NOT NULL DEFAULT 0,
                pending_stars INTEGER NOT NULL DEFAULT 0,
                paid_out_stars INTEGER NOT NULL DEFAULT 0,
                updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
            """
        )
        conn.exec_driver_sql(
            """
            CREATE TABLE paid_channel_subscriptions (
                id INTEGER PRIMARY KEY,
                user_id INTEGER NOT NULL,
                channel_id INTEGER NOT NULL,
                amount_stars INTEGER NOT NULL,
                status VARCHAR(24) NOT NULL DEFAULT 'active',
                started_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,
                expires_at DATETIME,
                auto_renew BOOLEAN NOT NULL DEFAULT 0,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,
                updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                UNIQUE(user_id, channel_id)
            )
            """
        )
        conn.exec_driver_sql(
            """
            CREATE TABLE post_boosts (
                id INTEGER PRIMARY KEY,
                post_id INTEGER NOT NULL,
                buyer_id INTEGER NOT NULL,
                amount_stars INTEGER NOT NULL,
                duration_days INTEGER NOT NULL DEFAULT 7,
                status VARCHAR(24) NOT NULL DEFAULT 'active',
                impressions INTEGER NOT NULL DEFAULT 0,
                clicks INTEGER NOT NULL DEFAULT 0,
                starts_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,
                expires_at DATETIME,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL
            )
            """
        )
    Session = sessionmaker(bind=engine)
    session = Session()
    try:
        yield session
    finally:
        session.close()
        engine.dispose()


def _add_user(db, user_id: int) -> None:
    db.execute(
        text(
            "INSERT INTO users (id, email, password_hash, name) "
            "VALUES (:id, :email, 'hash', :name)"
        ),
        {"id": user_id, "email": f"user{user_id}@example.com", "name": f"User {user_id}"},
    )


def _add_paid_post(db, post_id: int, author_id: int, price_stars: int = 40) -> None:
    db.execute(
        text(
            """
            INSERT INTO posts (
                id, user_id, type, status, visibility, is_paid, price_stars, preview_mode
            ) VALUES (:id, :author_id, 'text', 'published', 'public', 1, :price, 'teaser')
            """
        ),
        {"id": post_id, "author_id": author_id, "price": price_stars},
    )


def _add_paid_channel(db, channel_id: int, owner_id: int, monthly_price_stars: int = 25) -> None:
    db.execute(
        text(
            """
            INSERT INTO channels (
                id, name, slug, admin_user_id, is_paid, monthly_price_stars
            ) VALUES (:id, :name, :slug, :owner_id, 1, :price)
            """
        ),
        {
            "id": channel_id,
            "name": f"Channel {channel_id}",
            "slug": f"channel-{channel_id}",
            "owner_id": owner_id,
            "price": monthly_price_stars,
        },
    )


def test_purchase_paid_post_moves_stars_and_grants_access(db_session):
    _add_user(db_session, 1)
    _add_user(db_session, 2)
    _add_paid_post(db_session, post_id=10, author_id=2, price_stars=40)
    service = PaidFeaturesService(db_session)

    service.add_stars(1, 100, tx_type="purchase", idempotency_key="topup-1")
    purchase = service.purchase_post(1, 10, idempotency_key="buy-post-10")

    assert purchase.amount_stars == 40
    assert service.star_balance(1) == 60
    assert service.star_balance(2) == 40
    assert service.creator_balance(2).available_stars == 40
    assert db_session.get(PaidContentPurchase, purchase.id) is not None
    assert service.has_purchased_post(1, db_session.get(Post, 10))


def test_reusing_idempotency_key_for_different_purchase_is_rejected(db_session):
    _add_user(db_session, 1)
    _add_user(db_session, 2)
    _add_paid_post(db_session, post_id=10, author_id=2, price_stars=40)
    _add_paid_post(db_session, post_id=11, author_id=2, price_stars=40)
    service = PaidFeaturesService(db_session)

    service.add_stars(1, 100, tx_type="purchase")
    service.purchase_post(1, 10, idempotency_key="same-key")

    with pytest.raises(HTTPException) as exc:
        service.purchase_post(1, 11, idempotency_key="same-key")

    assert exc.value.status_code == 409


def test_subscribe_channel_extends_active_subscription(db_session):
    _add_user(db_session, 1)
    _add_user(db_session, 2)
    _add_paid_channel(db_session, channel_id=100, owner_id=2, monthly_price_stars=25)
    service = PaidFeaturesService(db_session)

    service.add_stars(1, 100, tx_type="purchase")
    first = service.subscribe_channel(1, 100, months=1)
    first_expires_at = first.expires_at
    second = service.subscribe_channel(1, 100, months=2)

    assert second.id == first.id
    assert second.amount_stars == 50
    assert second.expires_at >= first_expires_at + timedelta(days=59)
    assert service.star_balance(1) == 25
    assert service.creator_balance(2).available_stars == 75


def test_donate_requires_existing_recipient_and_rejects_self(db_session):
    _add_user(db_session, 1)
    service = PaidFeaturesService(db_session)
    service.add_stars(1, 10, tx_type="purchase")

    with pytest.raises(HTTPException) as missing:
        service.donate(1, 2, 1)
    assert missing.value.status_code == 404

    with pytest.raises(HTTPException) as self_donation:
        service.donate(1, 1, 1)
    assert self_donation.value.status_code == 400


def test_expire_due_post_boosts_keeps_post_promoted_until_last_boost_expires(db_session):
    _add_user(db_session, 1)
    _add_paid_post(db_session, post_id=10, author_id=1, price_stars=5)
    db_session.execute(text("UPDATE posts SET is_promoted = 1 WHERE id = 10"))
    now = datetime.utcnow()
    expired = PostBoost(
        post_id=10,
        buyer_id=1,
        amount_stars=5,
        duration_days=1,
        expires_at=now - timedelta(days=1),
    )
    active = PostBoost(
        post_id=10,
        buyer_id=1,
        amount_stars=5,
        duration_days=7,
        expires_at=now + timedelta(days=1),
    )
    db_session.add_all([expired, active])
    db_session.flush()

    assert expire_due_post_boosts(db_session) == 1
    db_session.flush()
    assert db_session.get(PostBoost, expired.id).status == "expired"
    assert db_session.execute(text("SELECT is_promoted FROM posts WHERE id = 10")).scalar() == 1

    active.expires_at = now - timedelta(minutes=1)
    db_session.flush()

    assert expire_due_post_boosts(db_session) == 1
    db_session.flush()
    assert db_session.execute(text("SELECT is_promoted FROM posts WHERE id = 10")).scalar() == 0


def test_service_rejects_out_of_range_paid_periods(db_session):
    _add_user(db_session, 1)
    _add_user(db_session, 2)
    _add_paid_channel(db_session, channel_id=100, owner_id=2, monthly_price_stars=25)
    _add_paid_post(db_session, post_id=10, author_id=2, price_stars=40)
    service = PaidFeaturesService(db_session)
    service.add_stars(1, 100, tx_type="purchase")

    with pytest.raises(HTTPException) as months:
        service.subscribe_channel(1, 100, months=13)
    assert months.value.status_code == 400

    with pytest.raises(HTTPException) as duration:
        service.boost_post(1, 10, 10, duration_days=31)
    assert duration.value.status_code == 400

from datetime import datetime, timedelta

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

from app.models.community import Channel
from app.models.paid_features import PaidContentPurchase, PostBoost, StarGiveawayParticipant
from app.models.post import Post
from app.models.user import User
from app.services.paid_features_service import (
    PaidFeaturesService,
    expire_due_channel_subscriptions,
    expire_due_post_boosts,
    finalize_due_star_giveaways,
)


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
                is_bot BOOLEAN DEFAULT 0,
                bot_username VARCHAR(32),
                bot_token VARCHAR(128),
                bot_description TEXT,
                bot_short_description TEXT,
                bot_avatar_url TEXT,
                bot_webhook_url TEXT,
                bot_webhook_secret VARCHAR(128),
                bot_webhook_enabled BOOLEAN DEFAULT 0,
                bot_webhook_last_error TEXT,
                bot_webhook_last_ok_at DATETIME,
                created_by_user_id INTEGER,
                show_last_seen BOOLEAN DEFAULT 1,
                last_seen_privacy VARCHAR(20) DEFAULT 'everybody',
                show_read_receipts BOOLEAN DEFAULT 1,
                paid_message_stars INTEGER DEFAULT 0,
                trust_score FLOAT DEFAULT 0.5,
                account_warnings INTEGER DEFAULT 0,
                shadow_moderation BOOLEAN DEFAULT 0,
                banned_at DATETIME,
                fcm_token VARCHAR(500),
                voip_token VARCHAR(500),
                device_platform VARCHAR(20),
                country_code VARCHAR(2),
                last_seen_at DATETIME,
                phone_hash VARCHAR(64),
                phone_e164 VARCHAR(20),
                phone_linked_at DATETIME,
                totp_secret VARCHAR(64),
                totp_enabled BOOLEAN DEFAULT 0,
                totp_enabled_at DATETIME,
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
            CREATE TABLE channel_members (
                id INTEGER PRIMARY KEY,
                channel_id INTEGER NOT NULL,
                user_id INTEGER NOT NULL,
                role VARCHAR(20) DEFAULT 'member',
                status VARCHAR(20) DEFAULT 'active' NOT NULL,
                is_favorite BOOLEAN DEFAULT 0 NOT NULL,
                inbox_archived BOOLEAN DEFAULT 0 NOT NULL,
                show_in_feed BOOLEAN DEFAULT 1 NOT NULL,
                notifications_enabled BOOLEAN DEFAULT 1 NOT NULL,
                last_seen_posts_count INTEGER DEFAULT 0 NOT NULL,
                joined_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                UNIQUE(channel_id, user_id)
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
        conn.exec_driver_sql(
            """
            CREATE TABLE star_giveaways (
                id INTEGER PRIMARY KEY,
                channel_id INTEGER NOT NULL,
                creator_user_id INTEGER NOT NULL,
                prize_stars INTEGER NOT NULL,
                winners_count INTEGER NOT NULL,
                total_escrow_stars INTEGER NOT NULL,
                status VARCHAR(24) NOT NULL DEFAULT 'active',
                ends_at DATETIME NOT NULL,
                require_membership BOOLEAN NOT NULL DEFAULT 1,
                participants_count INTEGER NOT NULL DEFAULT 0,
                title VARCHAR(160),
                prize_type VARCHAR(16) NOT NULL DEFAULT 'stars',
                premium_months INTEGER NOT NULL DEFAULT 0,
                completed_at DATETIME,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL
            )
            """
        )
        conn.exec_driver_sql(
            """
            CREATE TABLE star_giveaway_participants (
                id INTEGER PRIMARY KEY,
                giveaway_id INTEGER NOT NULL,
                user_id INTEGER NOT NULL,
                is_winner BOOLEAN NOT NULL DEFAULT 0,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,
                UNIQUE(giveaway_id, user_id)
            )
            """
        )
        conn.exec_driver_sql(
            """
            CREATE TABLE channel_suggested_posts (
                id INTEGER PRIMARY KEY,
                channel_id INTEGER NOT NULL,
                author_id INTEGER NOT NULL,
                text VARCHAR(2000) NOT NULL,
                media_url VARCHAR(1024),
                amount_stars INTEGER NOT NULL,
                status VARCHAR(24) NOT NULL DEFAULT 'pending',
                post_id INTEGER,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL
            )
            """
        )
        conn.exec_driver_sql(
            """
            CREATE TABLE star_invoices (
                id INTEGER PRIMARY KEY,
                bot_id INTEGER NOT NULL,
                creator_user_id INTEGER NOT NULL,
                payer_user_id INTEGER,
                title VARCHAR(160) NOT NULL,
                description VARCHAR(512),
                amount_stars INTEGER NOT NULL,
                payload VARCHAR(256),
                status VARCHAR(24) NOT NULL DEFAULT 'pending',
                expires_at DATETIME,
                paid_at DATETIME,
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


def test_expire_channel_subscription_revokes_membership(db_session):
    _add_user(db_session, 1)
    _add_user(db_session, 2)
    _add_paid_channel(db_session, channel_id=100, owner_id=2, monthly_price_stars=25)
    service = PaidFeaturesService(db_session)
    service.add_stars(1, 50, tx_type="purchase")
    sub = service.subscribe_channel(1, 100, months=1)
    db_session.flush()

    member_count = db_session.execute(
        text(
            "SELECT COUNT(*) FROM channel_members "
            "WHERE channel_id = 100 AND user_id = 1 AND status = 'active'"
        )
    ).scalar()
    assert member_count == 1

    sub.expires_at = datetime.utcnow() - timedelta(minutes=1)
    sub.auto_renew = False
    db_session.flush()

    assert expire_due_channel_subscriptions(db_session) == 1
    db_session.flush()
    assert sub.status == "expired"
    member_count = db_session.execute(
        text(
            "SELECT COUNT(*) FROM channel_members "
            "WHERE channel_id = 100 AND user_id = 1"
        )
    ).scalar()
    assert member_count == 0


def test_cancel_channel_subscription_keeps_access_until_expiry(db_session):
    _add_user(db_session, 1)
    _add_user(db_session, 2)
    _add_paid_channel(db_session, channel_id=100, owner_id=2, monthly_price_stars=25)
    service = PaidFeaturesService(db_session)
    service.add_stars(1, 50, tx_type="purchase")
    sub = service.subscribe_channel(1, 100, months=1, auto_renew=True)
    db_session.flush()
    assert sub.auto_renew is True

    cancelled = service.cancel_channel_subscription(1, 100)
    db_session.flush()
    assert cancelled.auto_renew is False
    assert cancelled.status == "active"
    channel = db_session.get(Channel, 100)
    assert channel is not None
    assert service.has_paid_channel_access(1, channel)

    renewed = service.update_channel_subscription_auto_renew(
        1, 100, auto_renew=True
    )
    db_session.flush()
    assert renewed.auto_renew is True


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


def _add_member(db, channel_id: int, user_id: int, role: str = "member") -> None:
    db.execute(
        text(
            "INSERT INTO channel_members (channel_id, user_id, role, status) "
            "VALUES (:cid, :uid, :role, 'active')"
        ),
        {"cid": channel_id, "uid": user_id, "role": role},
    )


def test_giveaway_join_finalize_and_cancel(db_session):
    _add_user(db_session, 1)
    _add_user(db_session, 2)
    _add_user(db_session, 3)
    _add_paid_channel(db_session, channel_id=100, owner_id=1, monthly_price_stars=0)
    _add_member(db_session, 100, 2)
    _add_member(db_session, 100, 3)
    service = PaidFeaturesService(db_session)
    service.add_stars(1, 200, tx_type="purchase")

    giveaway = service.create_star_giveaway(
        1, 100, prize_stars=50, winners_count=1, duration_hours=1, title="Test"
    )
    db_session.flush()
    assert service.star_balance(1) == 150

    service.join_star_giveaway(2, giveaway.id)
    service.join_star_giveaway(3, giveaway.id)
    db_session.flush()
    assert giveaway.participants_count == 2

    giveaway.ends_at = datetime.utcnow() - timedelta(minutes=1)
    db_session.flush()
    assert finalize_due_star_giveaways(db_session) == 1
    db_session.flush()
    assert giveaway.status == "completed"
    winners = (
        db_session.query(StarGiveawayParticipant)
        .filter(
            StarGiveawayParticipant.giveaway_id == giveaway.id,
            StarGiveawayParticipant.is_winner.is_(True),
        )
        .all()
    )
    assert len(winners) == 1
    assert service.star_balance(winners[0].user_id) == 50

    listed_giveaway, winner_rows = service.list_giveaway_winners(giveaway.id)
    assert listed_giveaway.id == giveaway.id
    assert listed_giveaway.status == "completed"
    assert len(winner_rows) == 1
    participant, user = winner_rows[0]
    assert participant.is_winner is True
    assert user.id == winners[0].user_id

    # Fresh giveaway + cancel refunds escrow.
    service.add_stars(1, 50, tx_type="purchase")
    g2 = service.create_star_giveaway(
        1, 100, prize_stars=20, winners_count=2, duration_hours=6
    )
    before = service.star_balance(1)
    service.cancel_star_giveaway(1, g2.id)
    db_session.flush()
    assert g2.status == "cancelled"
    assert service.star_balance(1) == before + 40


def test_giveaway_requires_membership(db_session):
    _add_user(db_session, 1)
    _add_user(db_session, 2)
    _add_paid_channel(db_session, channel_id=100, owner_id=1, monthly_price_stars=0)
    service = PaidFeaturesService(db_session)
    service.add_stars(1, 50, tx_type="purchase")
    giveaway = service.create_star_giveaway(
        1, 100, prize_stars=10, winners_count=1, duration_hours=2
    )
    db_session.flush()
    with pytest.raises(HTTPException) as exc:
        service.join_star_giveaway(2, giveaway.id)
    assert exc.value.status_code == 403


def test_giveaway_winners_empty_until_completed(db_session):
    _add_user(db_session, 1)
    _add_user(db_session, 2)
    _add_paid_channel(db_session, channel_id=100, owner_id=1, monthly_price_stars=0)
    _add_member(db_session, 100, 2)
    service = PaidFeaturesService(db_session)
    service.add_stars(1, 100, tx_type="purchase")
    giveaway = service.create_star_giveaway(
        1, 100, prize_stars=25, winners_count=1, duration_hours=3
    )
    service.join_star_giveaway(2, giveaway.id)
    db_session.flush()
    active, rows = service.list_giveaway_winners(giveaway.id)
    assert active.status == "active"
    assert rows == []
    service.finalize_star_giveaway(giveaway.id)
    db_session.flush()
    done, winners = service.list_giveaway_winners(giveaway.id)
    assert done.status == "completed"
    assert len(winners) == 1
    assert winners[0][1].id == 2


def test_star_invoice_pay_and_expire(db_session):
    _add_user(db_session, 1)
    _add_user(db_session, 2)
    db_session.execute(
        text(
            "INSERT INTO users (id, email, password_hash, name, is_bot, bot_username, created_by_user_id) "
            "VALUES (9, 'bot@example.com', 'hash', 'PayBot', 1, 'paybot', 1)"
        )
    )
    service = PaidFeaturesService(db_session)
    service.add_stars(2, 80, tx_type="purchase")

    invoice = service.create_star_invoice(
        1, 9, title="Premium tip", amount_stars=30, payload="order-1"
    )
    db_session.flush()
    paid = service.pay_star_invoice(2, invoice.id)
    db_session.flush()
    assert paid.status == "paid"
    assert service.star_balance(2) == 50
    assert service.creator_balance(1).available_stars == 30

    invoice2 = service.create_star_invoice(
        1, 9, title="Late", amount_stars=10, expires_in_hours=1
    )
    invoice2.expires_at = datetime.utcnow() - timedelta(minutes=1)
    db_session.flush()
    with pytest.raises(HTTPException) as exc:
        service.pay_star_invoice(2, invoice2.id)
    assert exc.value.status_code == 400
    db_session.refresh(invoice2)
    assert invoice2.status == "expired"


def test_star_invoice_cancel(db_session):
    _add_user(db_session, 1)
    _add_user(db_session, 2)
    db_session.execute(
        text(
            "INSERT INTO users (id, email, password_hash, name, is_bot, bot_username, created_by_user_id) "
            "VALUES (9, 'bot2@example.com', 'hash', 'PayBot2', 1, 'paybot2', 1)"
        )
    )
    service = PaidFeaturesService(db_session)
    invoice = service.create_star_invoice(
        1, 9, title="Cancel me", amount_stars=20, payload="x"
    )
    db_session.flush()
    cancelled = service.cancel_star_invoice(1, invoice.id)
    db_session.flush()
    assert cancelled.status == "cancelled"

    with pytest.raises(HTTPException) as again:
        service.cancel_star_invoice(1, invoice.id)
    assert again.value.status_code == 400

    with pytest.raises(HTTPException) as pay:
        service.pay_star_invoice(2, invoice.id)
    assert pay.value.status_code == 400

    with pytest.raises(HTTPException) as forbidden:
        service.cancel_star_invoice(2, invoice.id)
    assert forbidden.value.status_code in (400, 403)


def test_star_invoice_list_and_refund(db_session):
    _add_user(db_session, 1)
    _add_user(db_session, 2)
    db_session.execute(
        text(
            "INSERT INTO users (id, email, password_hash, name, is_bot, bot_username, created_by_user_id) "
            "VALUES (11, 'bot3@example.com', 'hash', 'PayBot3', 1, 'paybot3', 1)"
        )
    )
    service = PaidFeaturesService(db_session)
    service.add_stars(2, 100, tx_type="purchase")

    pending = service.create_star_invoice(
        1, 11, title="Pending", amount_stars=10, payload="p1"
    )
    paid = service.create_star_invoice(
        1, 11, title="Paid", amount_stars=40, payload="p2"
    )
    db_session.flush()
    service.pay_star_invoice(2, paid.id)
    db_session.flush()

    listed = service.list_bot_star_invoices(1, 11)
    assert len(listed) == 2
    paid_only = service.list_bot_star_invoices(1, 11, status_filter="paid")
    assert len(paid_only) == 1
    assert paid_only[0].id == paid.id

    with pytest.raises(HTTPException) as not_owner:
        service.list_bot_star_invoices(2, 11)
    assert not_owner.value.status_code == 403

    assert service.star_balance(1) == 40
    assert service.creator_balance(1).available_stars == 40
    assert service.star_balance(2) == 60

    refunded = service.refund_star_invoice(1, paid.id)
    db_session.flush()
    assert refunded.status == "refunded"
    assert service.star_balance(1) == 0
    assert service.creator_balance(1).available_stars == 0
    assert service.star_balance(2) == 100

    # Idempotent second refund.
    again = service.refund_star_invoice(1, paid.id)
    assert again.status == "refunded"
    assert service.star_balance(2) == 100

    with pytest.raises(HTTPException) as pending_refund:
        service.refund_star_invoice(1, pending.id)
    assert pending_refund.value.status_code == 400


def test_premium_giveaway_grants_pro(db_session):
    _add_user(db_session, 1)
    _add_user(db_session, 2)
    _add_paid_channel(db_session, channel_id=100, owner_id=1, monthly_price_stars=0)
    _add_member(db_session, 100, 2)
    service = PaidFeaturesService(db_session)
    service.add_stars(1, 1000, tx_type="purchase")

    giveaway = service.create_star_giveaway(
        1,
        100,
        prize_type="premium",
        premium_months=3,
        winners_count=1,
        duration_hours=1,
        title="Pro",
    )
    db_session.flush()
    assert giveaway.prize_type == "premium"
    assert giveaway.premium_months == 3
    assert giveaway.prize_stars == 250 * 3
    assert service.star_balance(1) == 1000 - 750

    service.join_star_giveaway(2, giveaway.id)
    service.finalize_star_giveaway(giveaway.id)
    db_session.flush()
    assert giveaway.status == "completed"
    winner = db_session.query(User).filter(User.id == 2).first()
    assert winner.subscription_type == "pro"
    assert winner.subscription_status == "active"
    assert winner.subscription_expires_at is not None
    assert service.star_balance(2) == 0


def test_suggested_post_accept_and_reject(db_session):
    _add_user(db_session, 1)
    _add_user(db_session, 2)
    _add_user(db_session, 3)
    _add_paid_channel(db_session, channel_id=100, owner_id=1, monthly_price_stars=0)
    service = PaidFeaturesService(db_session)
    service.add_stars(2, 200, tx_type="purchase")
    service.add_stars(3, 80, tx_type="purchase")

    pending = service.suggest_channel_post(
        2, 100, text="Hello channel", amount_stars=40
    )
    rejected = service.suggest_channel_post(
        3, 100, text="Skip me", amount_stars=20
    )
    db_session.flush()
    assert pending.status == "pending"
    assert service.star_balance(2) == 160
    assert service.star_balance(3) == 60

    own = service.list_channel_suggested_posts(2, 100)
    assert [row.id for row in own] == [pending.id]
    admin_list = service.list_channel_suggested_posts(1, 100)
    assert {row.id for row in admin_list} == {pending.id, rejected.id}

    accepted = service.review_suggested_post(1, pending.id, approve=True)
    db_session.flush()
    assert accepted.status == "accepted"
    assert accepted.post_id is not None
    assert service.creator_balance(1).available_stars == 40
    post = db_session.query(Post).filter(Post.id == accepted.post_id).first()
    assert post is not None
    assert post.description == "Hello channel"
    assert post.channel_id == 100

    declined = service.review_suggested_post(1, rejected.id, approve=False)
    db_session.flush()
    assert declined.status == "rejected"
    assert service.star_balance(3) == 80

    with pytest.raises(HTTPException) as owner_self:
        service.suggest_channel_post(1, 100, text="own", amount_stars=10)
    assert owner_self.value.status_code == 400

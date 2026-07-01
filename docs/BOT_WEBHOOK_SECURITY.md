# Bot Webhook Security

## Outbound headers from HANWE

When HANWE sends a bot webhook update, it includes:

- `X-HanWe-Update-Type`
- `X-HanWe-Delivery-Id` (stable ID for retries of same delivery)
- `X-HanWe-Timestamp` (unix seconds)
- `X-HanWe-Nonce` (random token)
- `X-HanWe-Signature-Alg: hmac-sha256`
- `X-HanWe-Signature` (hex HMAC)
- `X-HanWe-Bot-Secret` (optional, if configured)

Signature formula:

`HMAC_SHA256(secret, "{timestamp}.{nonce}.{raw_body}")`

Request body also includes:

- `delivery_id` (same value as `X-HanWe-Delivery-Id`)
- `update_type`
- `update`
- `timestamp`

## Verify helper (Python)

Use backend helper:

`app/services/bot_webhook_verify.py`

```python
from app.services.bot_webhook_verify import verify_signed_webhook

ok, reason = verify_signed_webhook(
    headers=request.headers,
    raw_body=raw_bytes,
    secret=BOT_SECRET,
    replay_protection=True,
)
if not ok:
    return {"ok": False, "reason": reason}, 401
```

## Replay protection

- Default signature time window: `BOT_WEBHOOK_SIGNATURE_TTL_SECONDS=300`.
- If Redis is enabled, nonce reuse is blocked automatically.
- If Redis is disabled, helper still validates signature and timestamp, but replay blocking is best-effort.

## Idempotency / duplicate guard

- Store processed `delivery_id` values on the receiver side (Redis/DB) with TTL.
- If the same `delivery_id` appears again, return `200 OK` and skip processing.
- HANWE keeps `delivery_id` stable across retry attempts for the same queued delivery.

## Operational notes

- Keep `BOT_WEBHOOK_SIGN_WITH_SECRET=true` in production.
- Keep async queue enabled (`BOT_WEBHOOK_QUEUE_ENABLED=true`) to avoid blocking chat API.
- Tune retries with `BOT_WEBHOOK_DELIVERY_MAX_ATTEMPTS` and worker cadence via `BOT_WEBHOOK_QUEUE_POLL_SECONDS`.
- Per-bot enqueue quota:
  - `BOT_WEBHOOK_MAX_PER_BOT_PER_MINUTE` (default `120`)
  - Excess updates are dropped to dead-letter with reason `rate_limited_per_bot` and increase `throttled_total`.
- Operational safety guardrails for manual/system recovery actions:
  - `BOT_WEBHOOK_OP_MAX_REQUEUE_LIMIT` (default `500`)
  - `BOT_WEBHOOK_OP_MAX_PROMOTE_LIMIT` (default `500`)
  - `BOT_WEBHOOK_OP_MAX_RUNBOOK_REQUEUE_LIMIT` (default `500`)
  - `BOT_WEBHOOK_OP_MAX_RUNBOOK_PROMOTE_LIMIT` (default `500`)
  - Limits requested via moderation control-plane are clamped server-side to prevent accidental oversized recoveries.
- Circuit breaker for failing endpoints:
  - `BOT_WEBHOOK_AUTO_DISABLE_AFTER_FAIL_STREAK` (default `10`)
  - `BOT_WEBHOOK_FAIL_STREAK_TTL_SECONDS` (default `3600`)
  - When fail streak reaches threshold, webhook is auto-disabled and `bot_webhook_auto_disabled` analytics event is emitted.
- Moderation dashboard alert thresholds:
  - `BOT_WEBHOOK_ALERT_DEAD_DEPTH`
  - `BOT_WEBHOOK_ALERT_AUTO_DISABLED_24H`
  - `BOT_WEBHOOK_ALERT_FAILS_1H`
  - `BOT_WEBHOOK_ALERT_FAIL_RATE_PERCENT_1H`
  - `BOT_WEBHOOK_ALERT_MIN_ATTEMPTS_1H`
  - `BOT_WEBHOOK_ALERT_DROPPED_TOTAL`
  - `BOT_WEBHOOK_ALERT_THROTTLED_TOTAL`
- Queue metrics are exposed in moderation dashboard payload (`bot_webhook_queue`) and system readiness (`bot_webhooks`).
- Admin control-plane endpoints:
  - `POST /moderation/system/webhooks/promote-delayed` (move delayed tasks to active queue)
  - `POST /moderation/system/webhooks/clear` (clear active queue, optional delayed)
  - `POST /moderation/system/webhooks/reset-metrics` (reset sent/failed/retried/dropped counters)
  - `POST /moderation/system/webhooks/recovery-playbook` (requeue dead-letter + promote delayed queue)
  - `GET /moderation/system/webhooks/ops` (operations history with pagination/filter)
  - `GET /moderation/system/webhooks/ops/export` (export filtered operations as plain text payload)
  - `GET /moderation/system/webhooks/ops/incident-report` (single text incident snapshot: queue stats + alerts + filtered operations)
  - `GET /moderation/system/webhooks/dead-letter` (inspect dropped deliveries with `limit`, `offset`, optional `query`)
  - `POST /moderation/system/webhooks/dead-letter/requeue` (requeue by `limit`, selected `task_ids`, or filter presets using `drop_reason` / `query`)
  - `POST /moderation/system/webhooks/dead-letter/clear` (clear dead-letter storage)
  - All admin actions above emit analytics audit events (`entity_type=system`) for traceability.
- Per-bot troubleshooting endpoints:
  - `POST /bots/{bot_id}/webhook/test` (manual delivery test)
  - `GET /bots/{bot_id}/webhook/attempts` (recent delivery attempts timeline)
- Rotate `secret_token` if you suspect leakage.
- Use HTTPS-only webhook URLs.

## Release Regression Smoke

Before release, run focused webhook moderation smoke locally:

`./scripts/webhook_moderation_smoke.sh`

This smoke covers:

- webhook moderation API smoke tests (`backend/tests/test_webhook_api_smoke.py`)
- queue behavior smoke tests (`backend/tests/test_bot_webhook_queue_service.py`)
- Flutter analyze for webhook moderation/bot screens and service

Handoff summary for this module:

- `docs/WEBHOOK_MODERATION_HANDOFF.md`

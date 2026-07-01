# Webhook Moderation Handoff

Краткий handoff по production-ready блоку webhook delivery + moderation control-plane.

## Что реализовано

- Асинхронная очередь доставки webhook (`queue` + `delayed` + `dead-letter`).
- Retry/backoff, `delivery_id` idempotency, HMAC signature, replay protection.
- Circuit breaker (auto-disable webhook при fail streak).
- Per-bot quota/rate-limit с учетом `throttled` и `dropped`.
- Observability:
  - queue stats в readiness/moderation dashboard,
  - per-bot webhook health и attempts timeline,
  - operations history (pagination/filter/export/incident report).
- Moderation control-plane:
  - promote delayed / clear queue / reset metrics,
  - dead-letter list (pagination/filter),
  - dead-letter requeue (selected task ids + presets),
  - recovery playbook,
  - audit trail для опасных действий.
- UX polish:
  - runbook section в moderation dashboard,
  - bulk DLQ selection/actions,
  - short local timestamps в ops/attempts/history.

## Основные API

- Moderation:
  - `POST /moderation/system/webhooks/promote-delayed`
  - `POST /moderation/system/webhooks/clear`
  - `POST /moderation/system/webhooks/reset-metrics`
  - `GET /moderation/system/webhooks/dead-letter`
  - `POST /moderation/system/webhooks/dead-letter/requeue`
  - `POST /moderation/system/webhooks/dead-letter/clear`
  - `POST /moderation/system/webhooks/recovery-playbook`
  - `GET /moderation/system/webhooks/ops`
  - `GET /moderation/system/webhooks/ops/export`
  - `GET /moderation/system/webhooks/ops/incident-report`
- Bot troubleshooting:
  - `POST /bots/{bot_id}/webhook/test`
  - `GET /bots/{bot_id}/webhook/attempts`

## Безопасные лимиты (guardrails)

Параметры recovery-операций ограничены server-side clamp:

- `BOT_WEBHOOK_OP_MAX_REQUEUE_LIMIT`
- `BOT_WEBHOOK_OP_MAX_PROMOTE_LIMIT`
- `BOT_WEBHOOK_OP_MAX_RUNBOOK_REQUEUE_LIMIT`
- `BOT_WEBHOOK_OP_MAX_RUNBOOK_PROMOTE_LIMIT`

В audit metadata сохраняются `requested` и `effective` значения.

## Regression / Release checks

Запускать перед релизом:

`./scripts/webhook_moderation_smoke.sh`

Скрипт проверяет:

- `backend/tests/test_webhook_api_smoke.py`
- `backend/tests/test_bot_webhook_queue_service.py`
- `dart analyze` по webhook moderation/bot UI.

## Прод-мониторинг (минимум)

- Следить за ростом:
  - `dead_depth`
  - `throttled_total`
  - `dropped_total`
  - fail-rate за 1ч
- Проверять alerts в moderation dashboard:
  - `dead_letter_backlog`
  - `high_fail_rate`
  - `throttled_deliveries`
  - `auto_disabled_bots`

## Быстрый инцидент-плейбук

1. Скопировать `incident report`.
2. Requeue `max_attempts_exhausted`.
3. Requeue `rate_limited_per_bot`.
4. Promote delayed backlog.
5. Run recovery playbook.
6. Проверить `dead_depth`, `queue_depth`, свежие `ops`.

## Rollback/mitigation

- Временное снижение нагрузки:
  - уменьшить `BOT_WEBHOOK_MAX_PER_BOT_PER_MINUTE` только при перегреве.
- Ограничить агрессивные ручные операции:
  - понизить `BOT_WEBHOOK_OP_MAX_*` лимиты.
- При тяжелой деградации доставки:
  - временно выключить queue worker (`BOT_WEBHOOK_QUEUE_ENABLED=false`) только как emergency-меру и после фиксации причин.


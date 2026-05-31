# Smoke-чеклист перед релизом (HAN Eat)

Ручная проверка после деплоя API и сборки приложения.

## Реализовано в коде (до ручного прогона)

| Блок | Статус |
|------|--------|
| Каналы: вкладки mine / subscribed / для вас | готово |
| Опросы: голос, смена голоса, закрытие, редактирование без голосов | готово |
| Ссылки: preview, edit, open in browser | готово |
| Пост профиля: edit / delete | готово |
| Комментарии REST + счётчик после возврата | готово |
| Репост на стену + в канал (mine) | готово |
| Ошибки API на русском (репост, жалобы, сохранение, лента) | готово |
| Deep link `/post/:id` — экран с retry | готово |
| Smoke-скрипт + автотесты | готово |

Ручная проверка на устройстве и деплой на production — ниже. Пароль тестовых аккаунтов: см. [backend/docs/TEST_ACCOUNTS.md](../backend/docs/TEST_ACCOUNTS.md). Инструкция деплоя: [DEPLOYMENT.md](DEPLOYMENT.md).

## Деплой API (production)

```bash
cd /root/HAN-Eat && git pull
cd backend && source venv/bin/activate
alembic upgrade head   # в т.ч. 037_post_poll_votes_v1
sudo systemctl restart haneat-api
curl -sS https://api.haneat.app/health
```

## Auth

- [ ] Регистрация по email, письмо / токен подтверждения
- [ ] Вход, выход, refresh сессии
- [ ] Сброс и смена пароля

## Лента и профиль

- [ ] Лента «Для вас» / подписки загружаются
- [ ] Лайк, сохранение, репост (с комментарием и без)
- [ ] Комментарий к посту — счётчик обновляется после возврата
- [ ] Свой пост в профиле: редактирование текста / ссылки / рецепта
- [ ] Свой пост в профиле: удаление, пост исчезает из списка
- [ ] Пост по deep link `/post/{id}` открывается

## Опросы

- [ ] Создать опрос (профиль и канал)
- [ ] Проголосовать, сменить голос (другой вариант)
- [ ] «Кто проголосовал» открывается
- [ ] Автор закрывает опрос — голосование недоступно
- [ ] Редактирование опроса **без голосов**: вопрос и варианты
- [ ] После первого голоса: только комментарий к опросу

## Ссылки

- [ ] Создать link-пост, превью подтягивается
- [ ] Редактировать URL и подпись
- [ ] Карточка в ленте открывает ссылку во внешнем браузере

## Каналы

- [ ] Вкладки «Мои каналы» / «Подписки» / «Для вас»
- [ ] Создание поста в канале (текст, фото, рецепт, опрос, ссылка)
- [ ] Редактирование и удаление поста в канале
- [ ] Репост в канал one-click

## Рецепты и меню

- [ ] Создание рецепта с КБЖУ и видимостью
- [ ] Spoonacular / избранное / детальная страница рецепта

## Оффлайн / ошибки

- [ ] При недоступном API — понятное сообщение, кэш ленты (если был)
- [ ] Ошибки API на русском (репост, удаление, модерация)

## Автотесты (локально)

Одной командой:

```bash
chmod +x scripts/pre_release_check.sh
./scripts/pre_release_check.sh
# со smoke API (нужен запущенный backend):
RUN_SMOKE=1 API_BASE=http://127.0.0.1:5001 ./scripts/pre_release_check.sh
```

Или вручную:

```bash
cd backend && pytest tests/test_post_poll_service.py -q
cd .. && flutter test test/url_validator_test.dart test/feed_load_helper_test.dart test/api_error_parser_test.dart
flutter analyze lib/features/feed lib/features/posts lib/widgets/post_poll_section.dart
```

## Быстрая проверка API (скрипт)

Локально или production:

```bash
cd backend
python3 scripts/smoke_api_check.py --base https://api.haneat.app
# с авторизацией (тестовый аккаунт):
python3 scripts/smoke_api_check.py --base https://api.haneat.app --login han.test.creator@haneat.dev
```

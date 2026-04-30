# Как запустить Flutter Web

На Windows Flutter часто не может сам открыть Chrome («Failed to launch browser after 3 tries»). Ниже — рабочие способы.

## Из терминала

### Вариант 1: Chrome (один запуск)
```bash
run_web_chrome.bat
```
Либо:
```bash
flutter run -d chrome --web-browser-flag=--user-data-dir=C:\Temp\flutter_chrome_profile
```
Не выбирайте устройство вручную — устройство и флаг уже заданы.

### Вариант 2: Web-server (всегда работает)
```bash
flutter run -d web-server --web-port=8080
```
После появления в консоли строки с адресом откройте в браузере: **http://localhost:8080**

## Из Cursor / VS Code (F5)

1. Нажмите **F5** (или Run → Start Debugging).
2. Выберите конфигурацию:
   - **Flutter Web (Chrome)** — запуск в Chrome (если сработает на вашей системе).
   - **Flutter Web (web-server)** — сервер на порту 8080, откройте вручную http://localhost:8080.

## Важно

- Не запускайте **`flutter run`** без параметров и не выбирайте вручную пункт «Chrome» — в этом случае флаг с профилем не применится и ошибка может повториться.
- Если Chrome всё равно не открывается — используйте **web-server** и открывайте http://localhost:8080 вручную.

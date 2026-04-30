# Запуск приложения

## Почему приложение «не запускается»

Первая сборка под Android (**Gradle `assembleDebug`**) может занимать **5–15 минут**.  
В терминале при этом видно: `Running Gradle task 'assembleDebug'...` — это нормально, нужно дождаться окончания.

## Как запустить

### 1. Эмулятор

- Запустите эмулятор (например Pixel 6) в **Android Studio** → Device Manager → Run.
- Либо проверьте устройства: `flutter devices` — в списке должен быть `emulator-5554` или ваше устройство.

### 2. Терминал в Cursor

Откройте **Terminal** (Ctrl+`) и выполните **по очереди** в двух вкладках:

**Вкладка 1 — бэкенд:**
```powershell
cd "d:\HAN Eat 1\backend"
python run.py
```
Оставьте это окно открытым. Должно появиться: `Uvicorn running on http://0.0.0.0:5000`.

**Вкладка 2 — приложение:**
```powershell
cd "d:\HAN Eat 1"
flutter run -d android
```
Или явно эмулятор: `flutter run -d emulator-5554`.

Дождитесь окончания сборки (может быть 5–15 минут при первом запуске).  
Когда увидите `Flutter run key commands` и приложение откроется на эмуляторе — всё готово.

### 3. Если Flutter «зависает» в Cursor

Запустите команды в **отдельном PowerShell** (не в Cursor):

1. Откройте PowerShell.
2. Сервер: `cd "d:\HAN Eat 1\backend"` → `python run.py`.
3. Новое окно PowerShell: `cd "d:\HAN Eat 1"` → `flutter run -d android`.

Окна не закрывайте — в них будет вывод и логи.

## Быстрая проверка без эмулятора

- В браузере: `flutter run -d chrome`
- На Windows: `flutter run -d windows`

Сборка там обычно быстрее, чем под Android.

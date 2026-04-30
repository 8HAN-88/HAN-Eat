@echo off
REM Запуск Flutter Web в Chrome с фиксом "Failed to launch browser" / нескольких окон
REM Папка профиля: C:\Temp\flutter_chrome_profile (создаётся при первом запуске)
flutter run -d chrome --web-browser-flag=--user-data-dir=C:\Temp\flutter_chrome_profile

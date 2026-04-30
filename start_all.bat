@echo off
REM Скрипт для запуска всего приложения HAN Eat
REM Запуск: start_all.bat

echo =======================================
echo Запуск HAN Eat приложения
echo =======================================
echo.

echo Проверка Python...
python --version
if errorlevel 1 (
    echo ОШИБКА: Python не найден!
    echo Установите Python с https://www.python.org/
    pause
    exit /b 1
)

echo.
echo Проверка Flutter...
flutter --version
if errorlevel 1 (
    echo ОШИБКА: Flutter не найден!
    pause
    exit /b 1
)

echo.
echo Запуск бэкенд сервера...
echo   Сервер будет запущен в отдельном окне
echo.

REM Запуск бэкенд сервера в новом окне
start "HAN Eat Backend Server" cmd /k "cd RecipeApp && python app_simple.py"

echo   Бэкенд сервер запускается...
echo   Подождите 5 секунд...
timeout /t 5 /nobreak >nul

echo.
echo Запуск Flutter приложения...
echo.

REM Запуск Flutter приложения
flutter run -d chrome

echo.
echo =======================================
echo Приложение запущено!
echo =======================================
echo.
echo ВАЖНО:
echo   - Бэкенд сервер работает в отдельном окне
echo   - НЕ закрывайте окно с бэкенд сервером!
echo   - Приложение откроется в браузере Chrome
echo.
pause


@echo off
REM Скрипт для создания .env файлов из шаблонов
REM Запустите: create_env_files.bat

echo ========================================
echo Создание .env файлов из шаблонов
echo ========================================
echo.

REM Проверка существования шаблонов
if not exist "backend\env_template.txt" (
    echo ❌ Файл backend\env_template.txt не найден!
    pause
    exit /b 1
)

if not exist "env_template.txt" (
    echo ❌ Файл env_template.txt не найден!
    pause
    exit /b 1
)

REM Создание backend/.env
if exist "backend\.env" (
    echo ⚠️  Файл backend\.env уже существует
    set /p overwrite="Перезаписать? (y/n): "
    if /i "%overwrite%"=="y" (
        copy /Y "backend\env_template.txt" "backend\.env" >nul
        echo ✅ Создан backend\.env
    ) else (
        echo Пропущено
    )
) else (
    copy "backend\env_template.txt" "backend\.env" >nul
    echo ✅ Создан backend\.env
)

REM Создание .env в корне
if exist ".env" (
    echo ⚠️  Файл .env уже существует
    set /p overwrite="Перезаписать? (y/n): "
    if /i "%overwrite%"=="y" (
        copy /Y "env_template.txt" ".env" >nul
        echo ✅ Создан .env
    ) else (
        echo Пропущено
    )
) else (
    copy "env_template.txt" ".env" >nul
    echo ✅ Создан .env
)

echo.
echo ========================================
echo ✅ Готово!
echo ========================================
echo.
echo Теперь откройте файлы и заполните значения:
echo   1. backend\.env - обязательные переменные
echo   2. .env - опционально (для поиска рецептов)
echo.
echo Все ссылки для получения ключей уже указаны в файлах!
echo.
pause


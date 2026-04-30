# Скрипт для создания .env файлов из шаблонов
# Запустите: .\create_env_files.ps1

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Создание .env файлов из шаблонов" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Проверка существования шаблонов
if (-not (Test-Path "backend\env_template.txt")) {
    Write-Host "❌ Файл backend\env_template.txt не найден!" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path "env_template.txt")) {
    Write-Host "❌ Файл env_template.txt не найден!" -ForegroundColor Red
    exit 1
}

# Создание backend/.env
if (Test-Path "backend\.env") {
    Write-Host "⚠️  Файл backend\.env уже существует" -ForegroundColor Yellow
    $overwrite = Read-Host "Перезаписать? (y/n)"
    if ($overwrite -ne "y") {
        Write-Host "Пропущено" -ForegroundColor Yellow
    } else {
        Copy-Item "backend\env_template.txt" "backend\.env" -Force
        Write-Host "✅ Создан backend\.env" -ForegroundColor Green
    }
} else {
    Copy-Item "backend\env_template.txt" "backend\.env"
    Write-Host "✅ Создан backend\.env" -ForegroundColor Green
}

# Создание .env в корне
if (Test-Path ".env") {
    Write-Host "⚠️  Файл .env уже существует" -ForegroundColor Yellow
    $overwrite = Read-Host "Перезаписать? (y/n)"
    if ($overwrite -ne "y") {
        Write-Host "Пропущено" -ForegroundColor Yellow
    } else {
        Copy-Item "env_template.txt" ".env" -Force
        Write-Host "✅ Создан .env" -ForegroundColor Green
    }
} else {
    Copy-Item "env_template.txt" ".env"
    Write-Host "✅ Создан .env" -ForegroundColor Green
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "✅ Готово!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Теперь откройте файлы и заполните значения:" -ForegroundColor Yellow
Write-Host "  1. backend\.env - обязательные переменные" -ForegroundColor Yellow
Write-Host "  2. .env - опционально (для поиска рецептов)" -ForegroundColor Yellow
Write-Host ""
Write-Host "Все ссылки для получения ключей уже указаны в файлах!" -ForegroundColor Cyan


# Скрипт для обновления .env файла с настройками оптимизации

$envFile = "backend\.env"

if (-not (Test-Path $envFile)) {
    Write-Host "Error: $envFile not found" -ForegroundColor Red
    exit 1
}

Write-Host "Updating .env file with optimization settings..." -ForegroundColor Yellow

# Читаем текущий файл
$content = Get-Content $envFile -Raw

# Настройки для добавления
$settingsToAdd = @"
# Database Connection Pool (для 100k пользователей)
DB_POOL_SIZE=20
DB_MAX_OVERFLOW=40
DB_POOL_RECYCLE=3600
DB_POOL_TIMEOUT=30

# Redis Connection Pool
REDIS_MAX_CONNECTIONS=50

# Rate Limiting (увеличено для production)
RATE_LIMIT_PER_MINUTE=120
RATE_LIMIT_PER_HOUR=5000
RATE_LIMIT_BURST=20
"@

# Проверяем, есть ли уже эти настройки
$needsUpdate = $false
$settings = @("DB_POOL_SIZE", "DB_MAX_OVERFLOW", "REDIS_MAX_CONNECTIONS", "RATE_LIMIT_PER_MINUTE")

foreach ($setting in $settings) {
    if ($content -notmatch "$setting=") {
        $needsUpdate = $true
        break
    }
}

if ($needsUpdate) {
    # Добавляем настройки в конец файла
    Add-Content -Path $envFile -Value "`n$settingsToAdd"
    Write-Host "Settings added to .env file" -ForegroundColor Green
} else {
    Write-Host "Settings already exist in .env file" -ForegroundColor Yellow
}

Write-Host "Done!" -ForegroundColor Green


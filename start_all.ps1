# Скрипт для запуска всего приложения HAN Eat
# Запуск: .\start_all.ps1

Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "Запуск HAN Eat приложения" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host ""

# Проверка Python
Write-Host "Проверка Python..." -ForegroundColor Yellow
try {
    $pythonVersion = python --version 2>&1
    Write-Host "  $pythonVersion" -ForegroundColor Green
} catch {
    Write-Host "  ОШИБКА: Python не найден!" -ForegroundColor Red
    Write-Host "  Установите Python с https://www.python.org/" -ForegroundColor Red
    exit 1
}

# Проверка Flutter
Write-Host "Проверка Flutter..." -ForegroundColor Yellow
try {
    $flutterVersion = flutter --version 2>&1 | Select-Object -First 1
    Write-Host "  $flutterVersion" -ForegroundColor Green
} catch {
    Write-Host "  ОШИБКА: Flutter не найден!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Запуск бэкенд сервера..." -ForegroundColor Yellow
Write-Host "  Сервер будет запущен в отдельном окне" -ForegroundColor Gray
Write-Host ""

# Запуск бэкенд сервера в новом окне
$backendScript = @"
cd "$PSScriptRoot\RecipeApp"
python app_simple.py
pause
"@

$backendScriptPath = "$env:TEMP\han_eat_backend.ps1"
$backendScript | Out-File -FilePath $backendScriptPath -Encoding UTF8

Start-Process powershell -ArgumentList "-NoExit", "-File", $backendScriptPath

Write-Host "  Бэкенд сервер запускается..." -ForegroundColor Green
Write-Host "  Подождите 5 секунд..." -ForegroundColor Gray
Start-Sleep -Seconds 5

Write-Host ""
Write-Host "Запуск Flutter приложения..." -ForegroundColor Yellow
Write-Host ""

# Запуск Flutter приложения
cd "$PSScriptRoot"
flutter run -d chrome

Write-Host ""
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "Приложение запущено!" -ForegroundColor Green
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "ВАЖНО:" -ForegroundColor Yellow
Write-Host "  - Бэкенд сервер работает в отдельном окне" -ForegroundColor Gray
Write-Host "  - НЕ закрывайте окно с бэкенд сервером!" -ForegroundColor Yellow
Write-Host "  - Приложение откроется в браузере Chrome" -ForegroundColor Gray
Write-Host ""


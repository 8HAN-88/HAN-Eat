# Запуск бэкенда (порт 5000) и Flutter на эмуляторе Android
# Запуск: .\start_server_and_app.ps1

$root = $PSScriptRoot

# Окно 1: бэкенд
$backendScript = @"
Set-Location '$root\backend'
Write-Host '=== Backend (port 5000) ===' -ForegroundColor Cyan
python run.py
Write-Host ''
pause
"@
$backendPath = "$env:TEMP\han_eat_backend.ps1"
$backendScript | Out-File -FilePath $backendPath -Encoding UTF8
Start-Process powershell -ArgumentList "-NoExit", "-File", $backendPath

# Подождать, чтобы сервер успел подняться
Start-Sleep -Seconds 3

# Окно 2: Flutter на Android
$flutterScript = @"
Set-Location '$root'
Write-Host '=== Flutter (Android emulator) ===' -ForegroundColor Cyan
flutter run -d android
pause
"@
$flutterPath = "$env:TEMP\han_eat_flutter.ps1"
$flutterScript | Out-File -FilePath $flutterPath -Encoding UTF8
Start-Process powershell -ArgumentList "-NoExit", "-File", $flutterPath

Write-Host "Открыты 2 окна: Backend (5000) и Flutter (Android)." -ForegroundColor Green
Write-Host "Не закрывайте окно с бэкендом." -ForegroundColor Yellow

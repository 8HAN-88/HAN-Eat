# Скрипт проверки готовности проекта HAN Eat
# Запуск: .\check_setup.ps1

Write-Host "Проверка готовности проекта HAN Eat..." -ForegroundColor Cyan
Write-Host ""

$errors = @()
$warnings = @()
$success = @()

# Проверка .env файла
Write-Host "Проверка .env файла..." -ForegroundColor Yellow
if (Test-Path ".env") {
    $envContent = Get-Content ".env" -Raw
    if ($envContent -match "SPOONACULAR_API_KEY") {
        $success += "[OK] Файл .env найден с SPOONACULAR_API_KEY"
    } else {
        $warnings += "[!] Файл .env найден, но SPOONACULAR_API_KEY не найден"
    }
} else {
    $errors += "[X] Файл .env не найден. Создайте его с SPOONACULAR_API_KEY=ваш_ключ"
}

# Проверка go_router в pubspec.yaml
Write-Host "Проверка зависимостей..." -ForegroundColor Yellow
$pubspec = Get-Content "pubspec.yaml" -Raw
if ($pubspec -match "go_router") {
    $success += "[OK] go_router найден в pubspec.yaml"
} else {
    $errors += "[X] go_router не найден в pubspec.yaml"
}

# Проверка Firebase файлов для Android
Write-Host "Проверка Firebase конфигурации..." -ForegroundColor Yellow
if (Test-Path "android/app/google-services.json") {
    $success += "[OK] google-services.json найден для Android"
} else {
    $warnings += "[!] google-services.json не найден (нужен для Android)"
}

# Проверка Firebase файлов для iOS
if (Test-Path "ios/Runner/GoogleService-Info.plist") {
    $success += "[OK] GoogleService-Info.plist найден для iOS"
} else {
    $warnings += "[!] GoogleService-Info.plist не найден (нужен для iOS)"
}

# Проверка плагина google-services в build.gradle.kts
$buildGradle = Get-Content "android/app/build.gradle.kts" -Raw
if ($buildGradle -match "com.google.gms.google-services") {
    $success += "[OK] Плагин google-services добавлен в build.gradle.kts"
} else {
    $warnings += "[!] Плагин google-services не найден в build.gradle.kts"
}

# Проверка бэкенд сервера
Write-Host "Проверка бэкенд сервера..." -ForegroundColor Yellow
if (Test-Path "RecipeApp/app.py") {
    $success += "[OK] Бэкенд сервер найден (RecipeApp/app.py)"
    $warnings += "[!] Убедитесь что сервер запущен: cd RecipeApp && python app.py"
} else {
    $warnings += "[!] Бэкенд сервер не найден"
}

# Вывод результатов
Write-Host ""
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "РЕЗУЛЬТАТЫ ПРОВЕРКИ" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host ""

if ($success.Count -gt 0) {
    Write-Host "Успешно:" -ForegroundColor Green
    foreach ($item in $success) {
        Write-Host "   $item" -ForegroundColor Green
    }
    Write-Host ""
}

if ($warnings.Count -gt 0) {
    Write-Host "Предупреждения:" -ForegroundColor Yellow
    foreach ($item in $warnings) {
        Write-Host "   $item" -ForegroundColor Yellow
    }
    Write-Host ""
}

if ($errors.Count -gt 0) {
    Write-Host "Ошибки (критично):" -ForegroundColor Red
    foreach ($item in $errors) {
        Write-Host "   $item" -ForegroundColor Red
    }
    Write-Host ""
}

# Итоговая оценка
Write-Host "=======================================" -ForegroundColor Cyan
if ($errors.Count -eq 0) {
    if ($warnings.Count -eq 0) {
        Write-Host "ВСЕ ГОТОВО! Приложение можно запускать!" -ForegroundColor Green
    } else {
        Write-Host "Основные проверки пройдены. Есть предупреждения." -ForegroundColor Yellow
        Write-Host "   Приложение может работать, но некоторые функции могут быть недоступны." -ForegroundColor Yellow
    }
} else {
    Write-Host "ЕСТЬ КРИТИЧЕСКИЕ ОШИБКИ!" -ForegroundColor Red
    Write-Host "   Исправьте ошибки перед запуском приложения." -ForegroundColor Red
}
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host ""

# Рекомендации
Write-Host "Документация:" -ForegroundColor Cyan
Write-Host "   - SETUP_INSTRUCTIONS.md - подробная инструкция" -ForegroundColor White
Write-Host "   - QUICK_CHECKLIST.md - быстрый чек-лист" -ForegroundColor White
Write-Host "   - ASSESSMENT.md - оценка готовности" -ForegroundColor White
Write-Host ""

#!/bin/bash
# Скрипт проверки готовности проекта HAN Eat
# Запуск: bash check_setup.sh

echo "🔍 Проверка готовности проекта HAN Eat..."
echo ""

errors=()
warnings=()
success=()

# Проверка .env файла
echo "📄 Проверка .env файла..."
if [ -f ".env" ]; then
    if grep -q "SPOONACULAR_API_KEY" .env; then
        success+=("✅ Файл .env найден с SPOONACULAR_API_KEY")
    else
        warnings+=("⚠️  Файл .env найден, но SPOONACULAR_API_KEY не найден")
    fi
else
    errors+=("❌ Файл .env не найден. Создайте его с SPOONACULAR_API_KEY=ваш_ключ")
fi

# Проверка go_router в pubspec.yaml
echo "📦 Проверка зависимостей..."
if grep -q "go_router" pubspec.yaml; then
    success+=("✅ go_router найден в pubspec.yaml")
else
    errors+=("❌ go_router не найден в pubspec.yaml")
fi

# Проверка Firebase файлов для Android
echo "🔥 Проверка Firebase конфигурации..."
if [ -f "android/app/google-services.json" ]; then
    success+=("✅ google-services.json найден для Android")
else
    warnings+=("⚠️  google-services.json не найден (нужен для Android)")
fi

# Проверка Firebase файлов для iOS
if [ -f "ios/Runner/GoogleService-Info.plist" ]; then
    success+=("✅ GoogleService-Info.plist найден для iOS")
else
    warnings+=("⚠️  GoogleService-Info.plist не найден (нужен для iOS)")
fi

# Проверка плагина google-services в build.gradle.kts
if grep -q "com.google.gms.google-services" android/app/build.gradle.kts; then
    success+=("✅ Плагин google-services добавлен в build.gradle.kts")
else
    warnings+=("⚠️  Плагин google-services не найден в build.gradle.kts")
fi

# Проверка бэкенд сервера
echo "🖥️  Проверка бэкенд сервера..."
if [ -f "RecipeApp/app.py" ]; then
    success+=("✅ Бэкенд сервер найден (RecipeApp/app.py)")
    warnings+=("⚠️  Убедитесь что сервер запущен: cd RecipeApp && python app.py")
else
    warnings+=("⚠️  Бэкенд сервер не найден")
fi

# Вывод результатов
echo ""
echo "═══════════════════════════════════════"
echo "📊 РЕЗУЛЬТАТЫ ПРОВЕРКИ"
echo "═══════════════════════════════════════"
echo ""

if [ ${#success[@]} -gt 0 ]; then
    echo "✅ Успешно:"
    for item in "${success[@]}"; do
        echo "   $item"
    done
    echo ""
fi

if [ ${#warnings[@]} -gt 0 ]; then
    echo "⚠️  Предупреждения:"
    for item in "${warnings[@]}"; do
        echo "   $item"
    done
    echo ""
fi

if [ ${#errors[@]} -gt 0 ]; then
    echo "❌ Ошибки (критично):"
    for item in "${errors[@]}"; do
        echo "   $item"
    done
    echo ""
fi

# Итоговая оценка
echo "═══════════════════════════════════════"
if [ ${#errors[@]} -eq 0 ]; then
    if [ ${#warnings[@]} -eq 0 ]; then
        echo "🎉 ВСЁ ГОТОВО! Приложение можно запускать!"
    else
        echo "✅ Основные проверки пройдены. Есть предупреждения."
        echo "   Приложение может работать, но некоторые функции могут быть недоступны."
    fi
else
    echo "❌ ЕСТЬ КРИТИЧЕСКИЕ ОШИБКИ!"
    echo "   Исправьте ошибки перед запуском приложения."
fi
echo "═══════════════════════════════════════"
echo ""

# Рекомендации
echo "📚 Документация:"
echo "   - SETUP_INSTRUCTIONS.md - подробная инструкция"
echo "   - QUICK_CHECKLIST.md - быстрый чек-лист"
echo "   - ASSESSMENT.md - оценка готовности"
echo ""


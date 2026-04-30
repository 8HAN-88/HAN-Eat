@echo off
echo Установка зависимостей для RecipeApp...
echo.

pip install Flask==3.0.3
pip install Flask-Cors==4.0.1
pip install requests==2.32.3
pip install python-dotenv==1.0.1

echo.
echo Попытка установить googletrans (может не получиться)...
pip install googletrans==4.0.0rc1

echo.
echo Попытка установить langdetect...
pip install langdetect==1.0.9

echo.
echo ✅ Готово! Если googletrans не установился - не страшно, используйте app_simple.py
pause


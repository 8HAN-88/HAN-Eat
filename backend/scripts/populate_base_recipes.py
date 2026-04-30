"""
Скрипт для заполнения базовой базы популярными русскими рецептами
Можно запускать периодически для добавления новых рецептов

Использование:
    python -m scripts.populate_base_recipes
"""
import sys
import os

# Добавляем корневую директорию в путь
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from app.core.database import SessionLocal
from app.models.base_recipe import BaseRecipe


def add_base_recipe(
    title: str,
    ingredients: list,
    steps: list,
    image_url: str = None,
    calories: int = None,
    nutrition: dict = None,
    tags: list = None,
    search_keywords: list = None,
    source: str = "manual",
    popularity_score: int = 0
):
    """Добавить рецепт в базовую базу"""
    db = SessionLocal()
    try:
        # Проверяем, не существует ли уже такой рецепт
        existing = db.query(BaseRecipe).filter(BaseRecipe.title == title).first()
        if existing:
            print(f"⚠️ Рецепт уже существует: {title}")
            return
        
        recipe = BaseRecipe(
            title=title,
            ingredients=ingredients,
            steps=steps,
            image_url=image_url,
            calories=calories,
            nutrition=nutrition or {},
            tags=tags or [],
            search_keywords=search_keywords or [],
            source=source,
            popularity_score=popularity_score
        )
        db.add(recipe)
        db.commit()
        print(f"✅ Добавлен рецепт: {title}")
    except Exception as e:
        print(f"❌ Ошибка при добавлении {title}: {e}")
        db.rollback()
    finally:
        db.close()


def populate_initial_recipes():
    """Заполнить базовую базу начальными популярными рецептами"""
    
    # Пример 1: Борщ классический
    add_base_recipe(
        title="Борщ классический",
        ingredients=[
            "Свекла - 2 шт",
            "Капуста белокочанная - 300 г",
            "Морковь - 1 шт",
            "Лук репчатый - 1 шт",
            "Мясо (говядина) - 500 г",
            "Томатная паста - 2 ст.л.",
            "Чеснок - 3 зубчика",
            "Соль, перец по вкусу",
            "Лавровый лист - 2 шт"
        ],
        steps=[
            {"number": 1, "step": "Отварить мясо до готовности в подсоленной воде (около 1.5 часа)"},
            {"number": 2, "step": "Нарезать овощи: свеклу и морковь натереть на терке, лук мелко нарезать, капусту нашинковать"},
            {"number": 3, "step": "Обжарить лук и морковь на растительном масле до мягкости"},
            {"number": 4, "step": "Добавить свеклу и томатную пасту, тушить 5-7 минут"},
            {"number": 5, "step": "Добавить овощи в бульон с мясом, варить 15 минут"},
            {"number": 6, "step": "Добавить капусту, варить еще 15 минут"},
            {"number": 7, "step": "Добавить измельченный чеснок, лавровый лист, соль и перец, варить 5 минут"},
            {"number": 8, "step": "Дать настояться 10-15 минут перед подачей"}
        ],
        tags=["суп", "борщ", "русская кухня", "обед", "мясо"],
        search_keywords=["борщ", "свекла", "капуста", "суп", "говядина"],
        calories=250,
        nutrition={"protein": 15, "fat": 8, "carbs": 30},
        popularity_score=100
    )
    
    # Пример 2: Оливье
    add_base_recipe(
        title="Салат Оливье",
        ingredients=[
            "Картофель - 4 шт",
            "Морковь - 2 шт",
            "Яйца куриные - 4 шт",
            "Огурцы соленые - 3 шт",
            "Горошек консервированный - 200 г",
            "Колбаса вареная - 200 г",
            "Майонез - 150 г",
            "Соль по вкусу"
        ],
        steps=[
            {"number": 1, "step": "Отварить картофель, морковь и яйца до готовности"},
            {"number": 2, "step": "Остудить и очистить все ингредиенты"},
            {"number": 3, "step": "Нарезать все ингредиенты кубиками одинакового размера"},
            {"number": 4, "step": "Добавить горошек"},
            {"number": 5, "step": "Заправить майонезом, посолить и перемешать"},
            {"number": 6, "step": "Дать настояться в холодильнике 1-2 часа перед подачей"}
        ],
        tags=["салат", "оливье", "праздничный", "новый год"],
        search_keywords=["оливье", "салат", "картофель", "майонез"],
        calories=320,
        nutrition={"protein": 12, "fat": 22, "carbs": 25},
        popularity_score=90
    )
    
    # Пример 3: Плов
    add_base_recipe(
        title="Плов узбекский",
        ingredients=[
            "Рис - 500 г",
            "Мясо (баранина) - 500 г",
            "Морковь - 3 шт",
            "Лук репчатый - 2 шт",
            "Чеснок - 1 головка",
            "Масло растительное - 100 мл",
            "Зира - 1 ч.л.",
            "Соль, перец по вкусу"
        ],
        steps=[
            {"number": 1, "step": "Нарезать мясо кубиками, обжарить на сильном огне до румяной корочки"},
            {"number": 2, "step": "Добавить нарезанный лук, обжарить до золотистого цвета"},
            {"number": 3, "step": "Добавить морковь, нарезанную соломкой, обжарить 5-7 минут"},
            {"number": 4, "step": "Добавить зиру, соль, перец, залить горячей водой"},
            {"number": 5, "step": "Тушить на медленном огне 30 минут"},
            {"number": 6, "step": "Добавить промытый рис, вставить головку чеснока, залить водой на 2 см выше риса"},
            {"number": 7, "step": "Варить на сильном огне до испарения воды"},
            {"number": 8, "step": "Уменьшить огонь до минимума, накрыть крышкой, готовить 20 минут"},
            {"number": 9, "step": "Перемешать перед подачей"}
        ],
        tags=["плов", "рис", "мясо", "узбекская кухня", "обед"],
        search_keywords=["плов", "рис", "баранина", "морковь"],
        calories=380,
        nutrition={"protein": 20, "fat": 15, "carbs": 45},
        popularity_score=85
    )
    
    print("\n✅ Заполнение базовой базы завершено!")


if __name__ == "__main__":
    print("🚀 Начинаем заполнение базовой базы рецептов...")
    populate_initial_recipes()





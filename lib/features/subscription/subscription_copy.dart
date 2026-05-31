import 'package:flutter/material.dart';

/// Русские тексты подписок и AI scan (premium UX, без pressure).
class SubscriptionCopy {
  // —— Soft paywall (free) ——
  static const aiScanExhaustedTitle =
      'Бесплатные AI-сканирования закончились';
  static const aiScanExhaustedSubtitle =
      'Получите больше AI-возможностей с H.A.N. AI';

  /// Перед последним бесплатным сканом (мягко, без красного UI).
  static const aiScanSoftWarning =
      'Скоро закончатся бесплатные AI-сканирования';

  // —— Подписчик AI/Pro без сканов (без цифр и таймеров) ——
  static const aiScanPlusExhaustedTitle =
      'AI-сканирования временно недоступны';
  static const aiScanPlusExhaustedSubtitle =
      'Новые сканирования скоро снова будут доступны. '
      'Пока можно пользоваться рецептами и планом питания.';

  static const List<SubscriptionBenefitItem> aiScanBenefits = [
    SubscriptionBenefitItem(
      icon: Icons.document_scanner_outlined,
      text: 'Больше AI-сканов блюд',
    ),
    SubscriptionBenefitItem(
      icon: Icons.monitor_heart_outlined,
      text: 'Расширенный анализ питания',
    ),
    SubscriptionBenefitItem(
      icon: Icons.restaurant_menu_outlined,
      text: 'Планы питания и рекомендации',
    ),
    SubscriptionBenefitItem(
      icon: Icons.auto_awesome_outlined,
      text: 'Умные рекомендации блюд',
    ),
    SubscriptionBenefitItem(
      icon: Icons.bolt_outlined,
      text: 'Быстрее работает AI',
    ),
  ];

  static const paywallCta = 'Оформить подписку';
  static const paywallLater = 'Позже';

  static const nutritionUpsellTitle = 'Калории и БЖУ — в подписке';
  static const nutritionUpsellSubtitle =
      'Оформите H.A.N. AI или Pro, чтобы видеть калории, белки, жиры и углеводы '
      'и фильтровать рецепты по питательности.';
  static const nutritionUpsellCta = 'Оформить подписку';
  static const nutritionLockedValue = 'Pro';

  static const List<SubscriptionBenefitItem> nutritionBenefits = [
    SubscriptionBenefitItem(
      icon: Icons.local_fire_department_outlined,
      text: 'Калории на карточках и в рецепте',
    ),
    SubscriptionBenefitItem(
      icon: Icons.fitness_center_outlined,
      text: 'Белки, жиры и углеводы',
    ),
    SubscriptionBenefitItem(
      icon: Icons.tune_outlined,
      text: 'Фильтры «низкокалорийное» и «высокий белок»',
    ),
    SubscriptionBenefitItem(
      icon: Icons.restaurant_menu_outlined,
      text: 'Лимиты калорий и БЖУ в настройках диеты',
    ),
  ];

  // —— AI meal plan cooldown (free, без таймеров) ——
  static const mealPlanCooldownTitle =
      'Следующий AI meal plan будет доступен позже';
  static const mealPlanCooldownSubtitle =
      'С H.A.N. AI вы можете создавать meal plans без ожидания';
  static const mealPlanCooldownCta = 'Попробовать H.A.N. AI';

  // —— Приватные рецепты в канале (Creator / Pro) ——
  static const creatorRecipeUpsellTitle =
      'Приватные рецепты — тариф Creator';
  static const creatorRecipeUpsellSubtitle =
      'Публикуйте индивидуальные рецепты в своём канале. Они не попадают '
      'в общий Menu и доступны только подписчикам канала.';
  static const creatorRecipeUpsellCta = 'Подключить H.A.N. Creator';
  static const channelRecipeMenuHint =
      'Рецепт виден только в этом канале и не отображается в общем Menu. '
      'Подписчики канала смогут открыть его здесь.';

  static const recipeVisibilitySectionTitle = 'Видимость рецепта';
  static const recipeVisibilityChangeTitle = 'Изменить видимость';

  static const recipeNutritionSectionTitle = 'Питание (на порцию)';
  static const recipeNutritionAiCta = 'AI расчёт';
  static const recipeNutritionAiLockedCta = 'AI · Creator';
  static const recipeNutritionAiLockedHint =
      'AI подставит калории и БЖУ по ингредиентам — в тарифе Creator или Pro.';
  static const recipeVisibilityPublicTitle = 'Публичный рецепт';
  static const recipeVisibilityPublicShort = 'Публичный';
  static const recipeVisibilityPublicSubtitle =
      'Рецепт появится в Menu и рекомендациях';
  static const recipeVisibilityPrivateTitle = 'Приватный рецепт';
  static const recipeVisibilityPrivateShort = 'Приватный';
  static const recipeVisibilityPrivateSubtitle =
      'Доступен только внутри вашего канала';
  static const recipeVisibilityPrivateLockedSubtitle =
      'Приватные рецепты доступны в Creator-подписке';
  static const recipeVisibilityPrivateCta = 'Узнать о Creator';
  static const recipeVisibilityChannelPublicHint =
      'Канал в режиме «все публичные» — рецепты попадают в общий Menu.';
  static const recipeVisibilityChannelPrivateHint =
      'Канал в режиме «все приватные» — рецепты только для подписчиков канала.';

  static const channelVisibilityModeTitle = 'Режим видимости рецептов';
  static const channelVisibilityModePublic = 'Все публичные';
  static const channelVisibilityModePublicHint =
      'Новые рецепты появляются в Menu и рекомендациях';
  static const channelVisibilityModePrivate = 'Все приватные';
  static const channelVisibilityModePrivateHint =
      'Рецепты только в канале, не в общем Menu';
  static const channelVisibilityModeMixed = 'Смешанный';
  static const channelVisibilityModeMixedHint =
      'Для каждого рецепта выбираете public или private';

  static const List<SubscriptionBenefitItem> creatorRecipeBenefits = [
    SubscriptionBenefitItem(
      icon: Icons.restaurant_menu_outlined,
      text: 'Индивидуальные рецепты в вашем канале',
    ),
    SubscriptionBenefitItem(
      icon: Icons.lock_outline,
      text: 'Не попадают в общий Menu — только для аудитории канала',
    ),
    SubscriptionBenefitItem(
      icon: Icons.groups_outlined,
      text: 'Эксклюзивный контент для подписчиков',
    ),
  ];

  static const List<SubscriptionBenefitItem> mealPlanAiBenefits = [
    SubscriptionBenefitItem(
      icon: Icons.calendar_month_outlined,
      text: 'Планы на 7, 14, 21 и 30 дней',
    ),
    SubscriptionBenefitItem(
      icon: Icons.autorenew_outlined,
      text: 'Обновление блюд и дней без лимита',
    ),
    SubscriptionBenefitItem(
      icon: Icons.tune_outlined,
      text: 'Расширенная персонализация питания',
    ),
    SubscriptionBenefitItem(
      icon: Icons.shopping_bag_outlined,
      text: 'Умный список покупок',
    ),
  ];

  static const screenTitle = 'Подписка';
  static const heroTitle = 'Больше возможностей\nдля готовки и творчества';
  static const heroSubtitle =
      'Оплата через СБП в приложении банка. Отмена подписки в любой момент.';

  static IconData tierIcon(String id) {
    switch (id) {
      case 'ai':
        return Icons.auto_awesome_outlined;
      case 'creator':
        return Icons.movie_creation_outlined;
      case 'pro':
        return Icons.workspace_premium_outlined;
      default:
        return Icons.star_outline;
    }
  }

  static String tierTitle(String id) {
    switch (id) {
      case 'ai':
        return 'H.A.N. AI';
      case 'creator':
        return 'H.A.N. Creator';
      case 'pro':
        return 'H.A.N. Pro';
      default:
        return id;
    }
  }

  static String tierSubtitle(String id) {
    switch (id) {
      case 'ai':
        return 'AI-сканы, питание, планы меню';
      case 'creator':
        return 'Аналитика, продвижение, инструменты автора';
      case 'pro':
        return 'Полный доступ: AI + Creator';
      default:
        return '';
    }
  }

  /// Преимущества тарифа: API + запасной список из копирайта.
  static List<String> normalizeBenefits(String id, List<String> fromApi) {
    if (fromApi.isNotEmpty) return fromApi;
    return tierBenefits(id);
  }

  static List<String> tierBenefits(String id) {
    switch (id) {
      case 'ai':
        return [
          'Больше AI-сканов',
          'Расширенный анализ питания',
          'Планы питания и рекомендации',
          'Умные рекомендации блюд',
        ];
      case 'creator':
        return [
          'Приватные рецепты в канале (не в общем Menu)',
          'Аналитика канала',
          'Продвижение контента',
          'Инструменты для авторов',
        ];
      case 'pro':
        return [
          'Всё из H.A.N. AI и Creator',
          'Приоритетная поддержка',
          'Эксклюзивные рецепты',
        ];
      default:
        return [];
    }
  }
}

class SubscriptionBenefitItem {
  const SubscriptionBenefitItem({required this.icon, required this.text});

  final IconData icon;
  final String text;
}

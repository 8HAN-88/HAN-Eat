import 'package:flutter/material.dart';

/// Русские тексты подписок и AI scan (premium UX, без pressure).
class SubscriptionCopy {
  // —— Soft paywall (free) ——
  static const aiScanExhaustedTitle = 'Бесплатные AI-сканирования закончились';
  static const aiScanExhaustedSubtitle =
      'Получите больше AI-возможностей с H.A.N. AI';

  /// Перед последним бесплатным сканом (мягко, без красного UI).
  static const aiScanSoftWarning =
      'Скоро закончатся бесплатные AI-сканирования';

  // —— Подписчик AI/Pro без сканов (без цифр и таймеров) ——
  static const aiScanPlusExhaustedTitle = 'AI-сканирования временно недоступны';
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

  /// Релиз v1 без ЮKassa (оплата после публикации в сторе).
  static const paymentsComingSoonTitle = 'Оплата скоро';
  static const paymentsComingSoonBody =
      'Подключим оплату по СБП сразу после публикации в App Store. '
      'Сейчас можно оформить бесплатный пробный период, если он вам доступен.';
  static const paymentsComingSoonCta = 'Оплата появится после релиза';

  static const nutritionUpsellTitle = 'Калории и БЖУ — в H.A.N. AI';
  static const nutritionUpsellSubtitle =
      'Оформите H.A.N. AI, чтобы видеть калории, белки, жиры и углеводы '
      'и фильтровать рецепты по питательности.';
  static const nutritionUpsellCta = 'Оформить подписку';
  static const nutritionLockedValue = 'AI';

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

  // —— Creator upsell (legacy recipe sheet → subscription) ——
  static const creatorRecipeUpsellTitle = 'Инструменты автора — тариф Creator';
  static const creatorRecipeUpsellSubtitle =
      'Отложенные посты, аналитика канала и продвижение контента '
      'для авторов в HanWe.';
  static const creatorRecipeUpsellCta = 'Подключить H.A.N. Creator';
  static const channelRecipeMenuHint =
      'Контент доступен подписчикам этого канала.';

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
      icon: Icons.schedule_outlined,
      text: 'Отложенная публикация постов',
    ),
    SubscriptionBenefitItem(
      icon: Icons.insights_outlined,
      text: 'Аналитика канала и контента',
    ),
    SubscriptionBenefitItem(
      icon: Icons.groups_outlined,
      text: 'Инструменты для роста аудитории',
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
  static const heroTitle = 'Больше возможностей\nдля авторов и общения';
  static const heroSubtitle =
      'Разовая оплата через СБП в приложении банка. Доступ на выбранный период; '
      'продление — снова в этом разделе. Автосписания подключим позже.';

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
        return 'AI-подсказки, офлайн-сохранения, без рекламы';
      case 'creator':
        return 'Канал, аналитика, отложенные посты, продвижение';
      case 'pro':
        return 'AI + Creator и приоритетная поддержка';
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
        return List.unmodifiable(_aiBenefits);
      case 'creator':
        return List.unmodifiable(_creatorBenefits);
      case 'pro':
        return List.unmodifiable(_proBenefits);
      default:
        return [];
    }
  }

  static const List<String> _aiBenefits = [
    'Ускоренная работа AI в приложении',
    'Сохранённые посты офлайн',
    'Расширенные рекомендации в ленте',
    'Без рекламы (когда появится в приложении)',
  ];

  static const List<String> _creatorBenefits = [
    'Аналитика канала и контента',
    'Продвижение постов',
    'Закрепление важных публикаций',
    'Отложенная публикация',
    'Оформление и бейдж канала',
    'Инструменты для авторов',
    'Без рекламы (когда появится в приложении)',
  ];

  static const List<String> _proBenefits = [
    'Всё из тарифа H.A.N. AI',
    'Всё из тарифа H.A.N. Creator',
    'Приоритетная поддержка',
    'Максимальный доступ ко всем функциям',
  ];
}

class SubscriptionBenefitItem {
  const SubscriptionBenefitItem({required this.icon, required this.text});

  final IconData icon;
  final String text;
}

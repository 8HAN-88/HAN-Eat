import 'package:flutter/material.dart';

/// Русские тексты подписок (messenger / HanWe).
class SubscriptionCopy {
  // —— Soft paywall (legacy AiScanExhaustedPaywall widget) ——
  static const aiScanExhaustedTitle = 'Лимит AI на сегодня закончился';
  static const aiScanExhaustedSubtitle =
      'Оформите H.A.N. AI, чтобы пользоваться AI без ограничений.';

  static const aiScanPlusExhaustedTitle = 'AI временно недоступен';
  static const aiScanPlusExhaustedSubtitle =
      'Новые AI-запросы скоро снова будут доступны. '
      'Пока можно пользоваться чатами, лентой и каналами.';

  static const List<SubscriptionBenefitItem> aiScanBenefits = [
    SubscriptionBenefitItem(
      icon: Icons.auto_awesome_outlined,
      text: 'Больше AI-подсказок в приложении',
    ),
    SubscriptionBenefitItem(
      icon: Icons.offline_bolt_outlined,
      text: 'Сохранённые посты офлайн',
    ),
    SubscriptionBenefitItem(
      icon: Icons.dynamic_feed_outlined,
      text: 'Расширенные рекомендации в ленте',
    ),
    SubscriptionBenefitItem(
      icon: Icons.bolt_outlined,
      text: 'Быстрее работает AI',
    ),
    SubscriptionBenefitItem(
      icon: Icons.block_outlined,
      text: 'Без рекламы (когда появится)',
    ),
  ];

  static const paywallCta = 'Оформить подписку';
  static const paywallLater = 'Позже';

  static const paymentsComingSoonTitle = 'Оплата скоро';
  static const paymentsComingSoonBody =
      'Подключим оплату по СБП сразу после публикации в App Store. '
      'Сейчас можно оформить бесплатный пробный период, если он вам доступен.';
  static const paymentsComingSoonCta = 'Оплата появится после релиза';

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

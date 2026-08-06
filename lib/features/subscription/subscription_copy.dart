import 'package:flutter/material.dart';

/// Русские тексты подписок (messenger / HanWe).
class SubscriptionCopy {
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
        return 'HanWe AI';
      case 'creator':
        return 'HanWe Creator';
      case 'pro':
        return 'HanWe Pro';
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
    'Всё из тарифа HanWe AI',
    'Всё из тарифа HanWe Creator',
    'Приоритетная поддержка',
    'Максимальный доступ ко всем функциям',
  ];
}

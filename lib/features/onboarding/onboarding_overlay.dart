import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/color_schemes.dart';


const _keyOnboardingDone = 'onboarding_done';

class OnboardingOverlay extends StatefulWidget {
  const OnboardingOverlay({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<OnboardingOverlay> createState() => _OnboardingOverlayState();
}

class _OnboardingOverlayState extends State<OnboardingOverlay> {
  bool _showOnboarding = false;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool(_keyOnboardingDone) ?? false;
    if (mounted) {
      setState(() {
        _showOnboarding = !done;
        _checked = true;
      });
    }
  }

  Future<void> _complete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOnboardingDone, true);
    if (mounted) {
      setState(() => _showOnboarding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Avoid a blank white flash while SharedPreferences resolves after login.
    if (!_checked) {
      return Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          const ColoredBox(
            color: Color(0xFF0F1319),
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ],
      );
    }
    if (!_showOnboarding) {
      return widget.child;
    }
    return Stack(
      children: [
        widget.child,
        Material(
          color: const Color(0xFF0F1319),
          child: Theme(
            data: Theme.of(context).copyWith(
              brightness: Brightness.dark,
              colorScheme: Theme.of(context).colorScheme.copyWith(
                    brightness: Brightness.dark,
                    surface: const Color(0xFF0F1319),
                    onSurface: const Color(0xFFF7F8FA),
                    onSurfaceVariant: const Color(0xFFA8B0BB),
                  ),
            ),
            child: _OnboardingContent(onComplete: _complete),
          ),
        ),
      ],
    );
  }
}

class _OnboardingContent extends StatefulWidget {
  const _OnboardingContent({required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<_OnboardingContent> createState() => _OnboardingContentState();
}

class _OnboardingContentState extends State<_OnboardingContent> {
  final _pageController = PageController();
  int _currentPage = 0;
  static const _infoPages = [
    _OnboardingPage(
      icon: Icons.restaurant_menu,
      title: 'Добро пожаловать в H.A.N. Eat',
      body: 'Ищите рецепты, сканируйте блюда по фото и планируйте питание.',
    ),
    _OnboardingPage(
      icon: Icons.dynamic_feed_outlined,
      title: 'Лента',
      body:
          'Подписки — посты друзей. Рекомендации — новое по вашим интересам. '
          'Рилсы — короткие видео на весь экран.',
    ),
    _OnboardingPage(
      icon: Icons.camera_alt_outlined,
      title: 'Сканер блюд',
      body: 'Сфотографируйте тарелку — узнайте калории и получите похожие рецепты.',
    ),
    _OnboardingPage(
      icon: Icons.calendar_today_outlined,
      title: 'План и список покупок',
      body: 'Добавляйте рецепты в план на неделю и формируйте список покупок одним нажатием.',
    ),
    _OnboardingPage(
      icon: Icons.auto_awesome_rounded,
      title: 'AI-план питания',
      body:
          'Персональный план составляется в разделе «План питания» — '
          'короткая анкета откроется только когда вы решите его создать.',
    ),
    _OnboardingPage(
      icon: Icons.forum_outlined,
      title: 'Чаты и папки',
      body:
          'Личные сообщения, группы и каналы — в одном месте. '
          'Создавайте папки как в Telegram: перетаскивайте их и '
          'добавляйте автофильтры по непрочитанным и типу чата.',
    ),
    _OnboardingPage(
      icon: Icons.notifications_active_outlined,
      title: 'Уведомления',
      body:
          'Колокольчик в ленте показывает новую активность. '
          'В профиле можно настроить, о чём получать push-уведомления.',
    ),
  ];

  int get _pageCount => _infoPages.length;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: widget.onComplete,
              child: const Text('Пропустить'),
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: _pageCount,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemBuilder: (context, index) {
                final p = _infoPages[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        p.icon,
                        size: 80,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        p.title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        p.body,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: FilledButton(
              onPressed: () async {
                if (_currentPage < _pageCount - 1) {
                  await _pageController.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                } else {
                  widget.onComplete();
                }
              },
              child: Text(
                _currentPage < _pageCount - 1 ? 'Далее' : 'Начать',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPage {
  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;
}

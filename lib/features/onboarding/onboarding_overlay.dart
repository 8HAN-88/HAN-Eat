import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';


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
    if (!_checked || !_showOnboarding) {
      return widget.child;
    }
    return Stack(
      children: [
        widget.child,
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: _OnboardingContent(onComplete: _complete),
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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/platform/pwa_install.dart';

/// Баннер «Установить HAN Eat» для PWA (Chrome / iOS Safari).
class PwaInstallBanner extends StatefulWidget {
  const PwaInstallBanner({super.key});

  @override
  State<PwaInstallBanner> createState() => _PwaInstallBannerState();
}

class _PwaInstallBannerState extends State<PwaInstallBanner> {
  final _controller = PwaInstallController.instance;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _controller.init();
      _controller.visible.addListener(_onVisibilityChanged);
    }
  }

  @override
  void dispose() {
    if (kIsWeb) {
      _controller.visible.removeListener(_onVisibilityChanged);
    }
    super.dispose();
  }

  void _onVisibilityChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || !_controller.visible.value) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    final isIos = _controller.isIosManualInstall.value;

    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.95),
      elevation: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.install_mobile_rounded,
                size: 22,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Установите HAN Eat',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isIos
                          ? 'Нажмите «Поделиться» → «На экран Домой»'
                          : 'Добавьте на рабочий стол — быстрый запуск без браузера',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              if (!isIos)
                TextButton(
                  onPressed: () => _controller.promptInstall(),
                  child: Text(
                    'Установить',
                    style: TextStyle(color: scheme.primary),
                  ),
                ),
              IconButton(
                tooltip: 'Скрыть',
                onPressed: () => _controller.dismiss(),
                icon: Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Экран запуска мини-приложения.
/// В будущем здесь будет WebView + JS bridge (window.HanWe.WebApp).
class MiniAppLauncherScreen extends StatelessWidget {
  const MiniAppLauncherScreen({
    super.key,
    required this.title,
    required this.subtitle,
    this.url, // для будущих внешних мини-приложений
  });

  final String title;
  final String subtitle;
  final String? url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Заглушка для WebView / контента мини-приложения
          Expanded(
            child: Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.web_asset_rounded,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Мини-приложение',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    if (url != null)
                      Text(
                        'URL: $url',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                    const SizedBox(height: 32),
                    FilledButton.icon(
                      onPressed: () {
                        // TODO: Здесь будет запуск WebView + initData + bridge
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('WebView + JS bridge будет добавлен в следующей итерации'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Запустить (демо)'),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Нижняя панель управления (как в Telegram WebApp)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const Spacer(),
                Text(
                  'HanWe Mini App',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

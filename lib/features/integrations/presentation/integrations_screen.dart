import 'package:flutter/material.dart';

/// Экран доступных интеграций (3rd party services)
class IntegrationsScreen extends StatelessWidget {
  const IntegrationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final integrations = [
      _Integration('Погода', 'Получайте уведомления о погоде', Icons.wb_sunny_outlined),
      _Integration('Календарь', 'Синхронизация событий', Icons.event_outlined),
      _Integration('Посылки', 'Отслеживание доставок', Icons.local_shipping_outlined),
      _Integration('Биржа', 'Курсы валют и крипты', Icons.show_chart_outlined),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Интеграции')),
      body: ListView.separated(
        itemCount: integrations.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = integrations[index];
          return ListTile(
            leading: Icon(item.icon, size: 32),
            title: Text(item.name),
            subtitle: Text(item.description),
            trailing: OutlinedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Подключение «${item.name}» будет доступно позже')),
                );
              },
              child: const Text('Подключить'),
            ),
          );
        },
      ),
    );
  }
}

class _Integration {
  final String name;
  final String description;
  final IconData icon;
  _Integration(this.name, this.description, this.icon);
}

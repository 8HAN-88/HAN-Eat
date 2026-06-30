import 'package:flutter/material.dart';
import 'miniapp_webview_screen.dart';
import '../../integrations/presentation/integrations_screen.dart';

class MiniAppsCatalogScreen extends StatelessWidget {
  const MiniAppsCatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: _MiniAppsCatalogBody(),
    );
  }
}

class _MiniAppsCatalogBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final apps = [
      _MiniApp(
        'Калькулятор калорий',
        'Считает БЖУ и калории',
        'HanWe',
        true,
        Icons.calculate_outlined,
        _calorieCalculatorHtml,
      ),
      _MiniApp('Погода', 'Погода по городу', 'HanWe', true, Icons.wb_sunny_outlined, null),
      _MiniApp('Рецепты по фото', 'Распознаёт ингредиенты', 'HanWe', true, Icons.camera_alt_outlined, null),
      _MiniApp('Переводчик', 'Перевод текста', 'Community', false, Icons.translate_outlined, null),
      _MiniApp('Напоминания', 'Todo и reminders', 'Community', false, Icons.alarm_outlined, null),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Мини-приложения'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Опубликовать своё приложение',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Публикация приложений будет доступна позже')),
              );
            },
          ),
        ],
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Все'),
            Tab(text: 'Интеграции'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          // Вкладка "Все"
          GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.05,
        ),
        itemCount: apps.length,
        itemBuilder: (context, index) {
          final app = apps[index];
          return Card(
            child: InkWell(
              onTap: () {
                if (app.htmlContent != null) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MiniAppWebViewScreen(
                        title: app.title,
                        subtitle: app.subtitle,
                        htmlContent: app.htmlContent,
                      ),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('«${app.title}» будет добавлено позже')),
                  );
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(app.icon, size: 36, color: Theme.of(context).colorScheme.primary),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: app.isOfficial
                                ? Colors.blue.withOpacity(0.1)
                                : Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            app.isOfficial ? 'Официальное' : 'От разработчиков',
                            style: TextStyle(
                              fontSize: 10,
                              color: app.isOfficial ? Colors.blue : Colors.green,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(app.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(app.subtitle, style: const TextStyle(fontSize: 12)),
                    const Spacer(),
                    Row(
                      children: [
                        Text(
                          'от ${app.developer}',
                          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline),
                        ),
                        const Spacer(),
                        if (app.htmlContent != null)
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => MiniAppWebViewScreen(
                                    title: app.title,
                                    subtitle: app.subtitle,
                                    htmlContent: app.htmlContent,
                                  ),
                                ),
                              );
                            },
                            child: const Text('Открыть'),
                          )
                        else
                          OutlinedButton(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Установка будет доступна позже')),
                              );
                            },
                            child: const Text('Установить'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
          // Вкладка "Интеграции"
          const IntegrationsScreen(),
        ],
      ),
    );
  }
}

class _MiniApp {
  final String title;
  final String subtitle;
  final String developer;
  final bool isOfficial;
  final IconData icon;
  final String? htmlContent;

  _MiniApp(this.title, this.subtitle, this.developer, this.isOfficial, this.icon, this.htmlContent);
}

/// Self-contained HTML + JS для демо мини-приложения "Калькулятор калорий"
const String _calorieCalculatorHtml = r'''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>Калькулятор калорий</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 0; padding: 16px; background: #f8f9fa; color: #1a1a1a; }
    .dark body { background: #121212; color: #e0e0e0; }
    h1 { font-size: 22px; margin: 0 0 16px; }
    .card { background: white; border-radius: 12px; padding: 16px; margin-bottom: 12px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
    .dark .card { background: #1e1e1e; }
    input, select { width: 100%; padding: 10px; margin: 6px 0; border: 1px solid #ddd; border-radius: 8px; font-size: 16px; }
    .dark input, .dark select { background: #2a2a2a; border-color: #444; color: #e0e0e0; }
    button { width: 100%; padding: 12px; background: #007AFF; color: white; border: none; border-radius: 10px; font-size: 16px; font-weight: 600; margin-top: 8px; }
    .result { font-size: 18px; font-weight: 600; color: #007AFF; margin-top: 12px; }
    .row { display: flex; gap: 8px; }
    .row > * { flex: 1; }
  </style>
</head>
<body>
  <h1>🥗 Калькулятор калорий</h1>
  
  <div class="card">
    <div class="row">
      <div>
        <label>Вес (кг)</label>
        <input type="number" id="weight" value="70" />
      </div>
      <div>
        <label>Рост (см)</label>
        <input type="number" id="height" value="175" />
      </div>
    </div>
    <div class="row">
      <div>
        <label>Возраст</label>
        <input type="number" id="age" value="30" />
      </div>
      <div>
        <label>Пол</label>
        <select id="gender">
          <option value="male">Мужской</option>
          <option value="female">Женский</option>
        </select>
      </div>
    </div>
    <div>
      <label>Активность</label>
      <select id="activity">
        <option value="1.2">Сидячий образ жизни</option>
        <option value="1.375">Лёгкая активность</option>
        <option value="1.55" selected>Умеренная активность</option>
        <option value="1.725">Высокая активность</option>
        <option value="1.9">Очень высокая</option>
      </select>
    </div>
    <button onclick="calculate()">Рассчитать</button>
  </div>

  <div class="card" id="resultCard" style="display:none;">
    <div>Базовый метаболизм (BMR):</div>
    <div class="result" id="bmr"></div>
    <div style="margin-top:8px;">Суточная норма калорий:</div>
    <div class="result" id="tdee"></div>
    <div style="margin-top:12px; font-size:14px; color:#666;">Рекомендация: 0.5–1 кг в неделю</div>
  </div>

  <script>
    function calculate() {
      const w = parseFloat(document.getElementById('weight').value);
      const h = parseFloat(document.getElementById('height').value);
      const a = parseFloat(document.getElementById('age').value);
      const g = document.getElementById('gender').value;
      const act = parseFloat(document.getElementById('activity').value);

      let bmr;
      if (g === 'male') {
        bmr = 88.362 + (13.397 * w) + (4.799 * h) - (5.677 * a);
      } else {
        bmr = 447.593 + (9.247 * w) + (3.098 * h) - (4.330 * a);
      }

      const tdee = Math.round(bmr * act);

      document.getElementById('bmr').innerText = Math.round(bmr) + ' ккал';
      document.getElementById('tdee').innerText = tdee + ' ккал';
      document.getElementById('resultCard').style.display = 'block';

      // Отправляем данные обратно в HanWe (демо)
      if (window.HanWe && window.HanWe.WebApp) {
        window.HanWe.WebApp.sendData(JSON.stringify({bmr: Math.round(bmr), tdee}));
      }
    }

    // Авто-расчёт при загрузке
    window.onload = () => {
      if (window.HanWe && window.HanWe.WebApp) {
        window.HanWe.WebApp.ready();
      }
    };
  </script>
</body>
</html>
''';

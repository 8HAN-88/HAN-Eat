import 'package:flutter/material.dart';

import '../../../core/platform/device_location.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/user_service.dart';
import '../../bots/data/bot_models.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/highlighted_text.dart';
import '../../subscription/creator_upsell.dart';
import '../application/dm_privacy.dart';

const _weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
const _greetingDays = [7, 14, 21, 28];
const _timezones = [
  'Europe/Moscow',
  'Europe/Samara',
  'Asia/Yekaterinburg',
  'Asia/Novosibirsk',
  'Asia/Irkutsk',
  'Asia/Vladivostok',
  'Europe/Kyiv',
  'Asia/Almaty',
  'UTC',
];

class BusinessSettingsScreen extends StatefulWidget {
  const BusinessSettingsScreen({super.key});

  @override
  State<BusinessSettingsScreen> createState() => _BusinessSettingsScreenState();
}

class _BusinessSettingsScreenState extends State<BusinessSettingsScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Map<String, bool> _unlocked = const {};

  final _greetingCtrl = TextEditingController();
  final _awayCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _introTitleCtrl = TextEditingController();
  final _introTextCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();

  bool _greetingEnabled = false;
  int _greetingDays = 7;
  bool _awayEnabled = false;
  String _awayMode = 'manual';
  String _timezone = 'Europe/Moscow';
  final Map<int, ({TimeOfDay start, TimeOfDay end})> _hours = {};
  double? _lat;
  double? _lng;
  int? _supportBotId;
  String? _supportBotName;
  List<BotListItem> _bots = const [];
  String _dmPrivacy = dmPrivacyEverybody;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _greetingCtrl.dispose();
    _awayCtrl.dispose();
    _addressCtrl.dispose();
    _introTitleCtrl.dispose();
    _introTextCtrl.dispose();
    _websiteCtrl.dispose();
    super.dispose();
  }

  bool _has(String slug) => _unlocked[slug] == true;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await UserService.getBusinessSettings();
      List<BotListItem> bots = const [];
      try {
        bots = await ApiService.getMyBots();
      } catch (_) {}
      if (!mounted) return;
      final hours = data['hours'];
      final intervals = hours is Map ? hours['intervals'] : null;
      _hours.clear();
      if (intervals is List) {
        for (final raw in intervals) {
          if (raw is! Map) continue;
          final dow = (raw['dow'] as num?)?.toInt();
          final start = _parseTime(raw['start']?.toString());
          final end = _parseTime(raw['end']?.toString());
          if (dow == null || start == null || end == null) continue;
          _hours[dow] = (start: start, end: end);
        }
      }
      final bot = data['support_bot'];
      setState(() {
        _unlocked = {
          for (final e in ((data['unlocked'] as Map?) ?? const {}).entries)
            e.key.toString(): e.value == true,
        };
        _greetingEnabled = data['greeting_enabled'] == true;
        _greetingCtrl.text = data['greeting_text'] as String? ?? '';
        _greetingDays = (data['greeting_inactivity_days'] as num?)?.toInt() ?? 7;
        _awayEnabled = data['away_enabled'] == true;
        _awayCtrl.text = data['away_text'] as String? ?? '';
        _awayMode = data['away_mode'] as String? ?? 'manual';
        _timezone = hours is Map
            ? (hours['timezone'] as String? ?? 'Europe/Moscow')
            : 'Europe/Moscow';
        _lat = (data['location_lat'] as num?)?.toDouble();
        _lng = (data['location_lng'] as num?)?.toDouble();
        _addressCtrl.text = data['location_address'] as String? ?? '';
        _introTitleCtrl.text = data['intro_title'] as String? ?? '';
        _introTextCtrl.text = data['intro_text'] as String? ?? '';
        _websiteCtrl.text = data['website_url'] as String? ?? '';
        _supportBotId = bot is Map ? (bot['id'] as num?)?.toInt() : null;
        _supportBotName = bot is Map ? bot['name'] as String? : null;
        _bots = bots;
        _dmPrivacy = normalizeDmPrivacy(data['dm_privacy'] as String?);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = userVisibleError(e);
      });
    }
  }

  TimeOfDay? _parseTime(String? raw) {
    final parts = (raw ?? '').split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String _fmt(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  Future<void> _save(Map<String, dynamic> body) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final data = await UserService.updateBusinessSettings(body);
      if (!mounted) return;
      setState(() {
        _unlocked = {
          for (final e in ((data['unlocked'] as Map?) ?? const {}).entries)
            e.key.toString(): e.value == true,
        };
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (offerFlexIfRequired(context, e)) return;
      if (offerPackStoreIfRequired(context, e)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _saveGreeting() => _save({
        'greeting_enabled': _greetingEnabled,
        'greeting_text': _greetingCtrl.text.trim(),
        'greeting_inactivity_days': _greetingDays,
      });

  Future<void> _saveAway() => _save({
        'away_enabled': _awayEnabled,
        'away_text': _awayCtrl.text.trim(),
        'away_mode': _awayMode,
      });

  Future<void> _saveHours() => _save({
        'hours': {
          'timezone': _timezone,
          'intervals': [
            for (final e in _hours.entries)
              {
                'dow': e.key,
                'start': _fmt(e.value.start),
                'end': _fmt(e.value.end),
              },
          ],
        },
      });

  Widget _lockTile({
    required String slug,
    required Widget child,
  }) {
    if (_has(slug)) return child;
    return Column(
      children: [
        IgnorePointer(
          child: Opacity(opacity: 0.55, child: child),
        ),
        ListTile(
          leading: const Icon(Icons.lock_outline),
          title: const Text('Нужна подписка'),
          subtitle: const Text('Откроется на этом уровне лестницы'),
          onTap: () => showCreatorUpsell(context),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Бизнес-профиль')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    _lockTile(
                      slug: 'business_greeting',
                      child: Card(
                        child: Column(
                          children: [
                            SwitchListTile(
                              title: const Text('Приветствие'),
                              subtitle: const Text(
                                'Автоответ при первом сообщении или после паузы',
                              ),
                              value: _greetingEnabled,
                              onChanged: (v) {
                                setState(() => _greetingEnabled = v);
                                _saveGreeting();
                              },
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: TextField(
                                controller: _greetingCtrl,
                                maxLength: 400,
                                minLines: 2,
                                maxLines: 4,
                                decoration: const InputDecoration(
                                  labelText: 'Текст приветствия',
                                ),
                                onEditingComplete: _saveGreeting,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Wrap(
                                spacing: 8,
                                children: [
                                  for (final days in _greetingDays)
                                    ChoiceChip(
                                      label: Text('$days дн.'),
                                      selected: _greetingDays == days,
                                      onSelected: (_) {
                                        setState(() => _greetingDays = days);
                                        _saveGreeting();
                                      },
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _lockTile(
                      slug: 'business_away',
                      child: Card(
                        child: Column(
                          children: [
                            SwitchListTile(
                              title: const Text('Меня нет'),
                              subtitle: const Text('Автоответ, пока вас нет'),
                              value: _awayEnabled,
                              onChanged: (v) {
                                setState(() => _awayEnabled = v);
                                _saveAway();
                              },
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: TextField(
                                controller: _awayCtrl,
                                maxLength: 400,
                                minLines: 2,
                                maxLines: 4,
                                decoration: const InputDecoration(
                                  labelText: 'Текст автоответа',
                                ),
                                onEditingComplete: _saveAway,
                              ),
                            ),
                            RadioListTile<String>(
                              title: const Text('Пока включено'),
                              value: 'manual',
                              groupValue: _awayMode,
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() => _awayMode = v);
                                _saveAway();
                              },
                            ),
                            RadioListTile<String>(
                              title: const Text('Вне часов работы'),
                              value: 'outside_hours',
                              groupValue: _awayMode,
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() => _awayMode = v);
                                _saveAway();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _lockTile(
                      slug: 'business_hours',
                      child: Card(
                        child: Column(
                          children: [
                            const ListTile(
                              title: Text('Часы работы'),
                              subtitle: Text('Показываются в профиле'),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                              child: DropdownButtonFormField<String>(
                                value: _timezones.contains(_timezone)
                                    ? _timezone
                                    : 'UTC',
                                decoration: const InputDecoration(
                                  labelText: 'Часовой пояс',
                                ),
                                items: [
                                  for (final tz in _timezones)
                                    DropdownMenuItem(value: tz, child: Text(tz)),
                                ],
                                onChanged: (v) {
                                  if (v == null) return;
                                  setState(() => _timezone = v);
                                  _saveHours();
                                },
                              ),
                            ),
                            for (var dow = 0; dow < 7; dow++)
                              SwitchListTile(
                                title: Text(_weekdays[dow]),
                                subtitle: _hours[dow] == null
                                    ? const Text('Выходной')
                                    : Text(
                                        '${_fmt(_hours[dow]!.start)}–${_fmt(_hours[dow]!.end)}',
                                      ),
                                value: _hours.containsKey(dow),
                                onChanged: (on) async {
                                  if (on) {
                                    setState(() {
                                      _hours[dow] = (
                                        start: const TimeOfDay(hour: 9, minute: 0),
                                        end: const TimeOfDay(hour: 18, minute: 0),
                                      );
                                    });
                                    await _saveHours();
                                  } else {
                                    setState(() => _hours.remove(dow));
                                    await _saveHours();
                                  }
                                },
                                secondary: _hours[dow] == null
                                    ? null
                                    : IconButton(
                                        icon: const Icon(Icons.schedule),
                                        onPressed: () async {
                                          final start = await showTimePicker(
                                            context: context,
                                            initialTime: _hours[dow]!.start,
                                          );
                                          if (start == null || !mounted) return;
                                          final end = await showTimePicker(
                                            context: context,
                                            initialTime: _hours[dow]!.end,
                                          );
                                          if (end == null || !mounted) return;
                                          setState(() {
                                            _hours[dow] = (start: start, end: end);
                                          });
                                          await _saveHours();
                                        },
                                      ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _lockTile(
                      slug: 'business_location',
                      child: Card(
                        child: Column(
                          children: [
                            ListTile(
                              title: const Text('Адрес на карте'),
                              subtitle: Text(
                                _lat == null
                                    ? 'Не указан'
                                    : '${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                              ),
                              trailing: TextButton(
                                onPressed: () async {
                                  final pos = await getDeviceLocation();
                                  if (pos == null) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Не удалось определить место'),
                                      ),
                                    );
                                    return;
                                  }
                                  setState(() {
                                    _lat = pos.latitude;
                                    _lng = pos.longitude;
                                  });
                                  await _save({
                                    'location_lat': _lat,
                                    'location_lng': _lng,
                                    'location_address': _addressCtrl.text.trim(),
                                  });
                                },
                                child: const Text('Гео'),
                              ),
                            ),
                            if (_lat != null)
                              ListTile(
                                title: const Text('Убрать точку'),
                                onTap: () {
                                  setState(() {
                                    _lat = null;
                                    _lng = null;
                                  });
                                  _save({
                                    'location_lat': null,
                                    'location_lng': null,
                                    'location_address': _addressCtrl.text.trim(),
                                  });
                                },
                              ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: TextField(
                                controller: _addressCtrl,
                                maxLength: 120,
                                decoration: const InputDecoration(
                                  labelText: 'Адрес',
                                ),
                                onEditingComplete: () => _save({
                                  'location_lat': _lat,
                                  'location_lng': _lng,
                                  'location_address': _addressCtrl.text.trim(),
                                }),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _lockTile(
                      slug: 'business_intro',
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Стартовая страница'),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _introTitleCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Заголовок',
                                ),
                                onEditingComplete: () => _save({
                                  'intro_title': _introTitleCtrl.text.trim(),
                                  'intro_text': _introTextCtrl.text.trim(),
                                }),
                              ),
                              TextField(
                                controller: _introTextCtrl,
                                maxLength: 200,
                                minLines: 2,
                                maxLines: 4,
                                decoration: const InputDecoration(
                                  labelText: 'Текст',
                                ),
                                onEditingComplete: () => _save({
                                  'intro_title': _introTitleCtrl.text.trim(),
                                  'intro_text': _introTextCtrl.text.trim(),
                                }),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _lockTile(
                      slug: 'business_bot',
                      child: Card(
                        child: Column(
                          children: [
                            const ListTile(
                              title: Text('Бот поддержки'),
                              subtitle: Text('Клиент откроет чат с вашим ботом'),
                            ),
                            RadioListTile<int?>(
                              title: const Text('Не привязан'),
                              value: null,
                              groupValue: _supportBotId,
                              onChanged: (_) {
                                setState(() {
                                  _supportBotId = null;
                                  _supportBotName = null;
                                });
                                _save({'support_bot_id': null});
                              },
                            ),
                            for (final bot in _bots)
                              RadioListTile<int?>(
                                title: HighlightedText(
                                  text: bot.name,
                                  style: Theme.of(context).textTheme.bodyLarge ??
                                      const TextStyle(fontSize: 16),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text('@${bot.username}'),
                                value: bot.id,
                                groupValue: _supportBotId,
                                onChanged: (_) {
                                  setState(() {
                                    _supportBotId = bot.id;
                                    _supportBotName = bot.name;
                                  });
                                  _save({'support_bot_id': bot.id});
                                },
                              ),
                            if (_bots.isEmpty)
                              const ListTile(
                                subtitle: Text(
                                  'Сначала создайте бота в разделе «Мои боты»',
                                ),
                              ),
                            if (_supportBotName != null &&
                                _bots.every((b) => b.id != _supportBotId))
                              ListTile(
                                title: HighlightedText(
                                  text: _supportBotName!,
                                  style: Theme.of(context).textTheme.bodyLarge ??
                                      const TextStyle(fontSize: 16),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: const Text('Текущий бот'),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _lockTile(
                      slug: 'profile_website',
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          child: TextField(
                            controller: _websiteCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Сайт в профиле',
                              hintText: 'haneat.app',
                            ),
                            onEditingComplete: () => _save({
                              'website_url': _websiteCtrl.text.trim(),
                            }),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _lockTile(
                      slug: 'dm_privacy',
                      child: Card(
                        child: Column(
                          children: [
                            const ListTile(
                              title: Text('Кто пишет первым'),
                              subtitle: Text(
                                'Уже открытые чаты остаются. Сброс на «Все» бесплатный',
                              ),
                            ),
                            for (final value in dmPrivacyValues)
                              RadioListTile<String>(
                                title: Text(dmPrivacyLabel(value)),
                                value: value,
                                groupValue: _dmPrivacy,
                                onChanged: (next) async {
                                  if (next == null) return;
                                  final previous = _dmPrivacy;
                                  setState(() => _dmPrivacy = next);
                                  try {
                                    final updated = await UserService.updateProfile(
                                      dmPrivacy: next,
                                    );
                                    await AuthService.persistUpdatedUser(updated);
                                    if (!mounted) return;
                                    setState(() {
                                      _dmPrivacy = normalizeDmPrivacy(
                                        updated.dmPrivacy,
                                      );
                                    });
                                  } catch (e) {
                                    if (!mounted) return;
                                    setState(() => _dmPrivacy = previous);
                                    if (offerFlexIfRequired(context, e)) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(userVisibleError(e)),
                                      ),
                                    );
                                  }
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

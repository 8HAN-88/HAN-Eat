import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../widgets/app_avatar.dart';

/// Parsed contact payload from chat text (HAN Eat / Telegram-style card).
class ChatContactPayload {
  const ChatContactPayload({
    required this.displayName,
    this.username,
    this.phone,
    this.userId,
  });

  final String displayName;
  final String? username;
  final String? phone;
  final int? userId;

  bool get hasAction =>
      userId != null ||
      (phone != null && phone!.isNotEmpty) ||
      (username != null && username!.isNotEmpty);

  static ChatContactPayload? tryParse(String content) {
    final lines = content
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (lines.isEmpty) return null;
    final head = lines.first.toLowerCase();
    final isContact = head.contains('контакт') ||
        head == '👤 контакт' ||
        head.startsWith('👤') ||
        head == 'han_contact';
    if (!isContact) return null;

    String? name;
    String? username;
    String? phone;
    int? userId;

    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      final lower = line.toLowerCase();
      if (lower.startsWith('user_id:') || lower.startsWith('haneat_user:')) {
        final raw = line.split(':').last.trim();
        userId = int.tryParse(raw);
        continue;
      }
      if (line.startsWith('@')) {
        username = line;
        continue;
      }
      if (RegExp(r'^\+?\d[\d\s\-()]{5,}$').hasMatch(line)) {
        phone = line.replaceAll(' ', '');
        continue;
      }
      name ??= line;
    }

    name ??= username?.replaceFirst('@', '') ?? phone ?? 'Контакт';
    return ChatContactPayload(
      displayName: name,
      username: username,
      phone: phone,
      userId: userId,
    );
  }

  static String encode({
    required String displayName,
    String? username,
    String? phone,
    int? userId,
  }) {
    final lines = <String>['👤 Контакт', displayName.trim()];
    final u = username?.trim();
    if (u != null && u.isNotEmpty) {
      lines.add(u.startsWith('@') ? u : '@$u');
    }
    final p = phone?.trim();
    if (p != null && p.isNotEmpty) lines.add(p);
    if (userId != null && userId > 0) {
      lines.add('haneat_user:$userId');
    }
    return lines.join('\n');
  }
}

class ChatContactBubble extends StatelessWidget {
  const ChatContactBubble({
    super.key,
    required this.payload,
    required this.foregroundColor,
    required this.accentColor,
    required this.cardColor,
    this.onOpenProfile,
  });

  final ChatContactPayload payload;
  final Color foregroundColor;
  final Color accentColor;
  final Color cardColor;
  final VoidCallback? onOpenProfile;

  Future<void> _callPhone() async {
    final phone = payload.phone;
    if (phone == null || phone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone);
    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = payload.username ?? payload.phone ?? 'Контакт';
    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: payload.userId != null ? onOpenProfile : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  AppUserAvatar(
                    radius: 22,
                    displayName: payload.displayName,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          payload.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: foregroundColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: foregroundColor.withValues(alpha: 0.7),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (payload.hasAction) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (payload.userId != null)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onOpenProfile,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: accentColor,
                            side: BorderSide(
                              color: accentColor.withValues(alpha: 0.45),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Профиль'),
                        ),
                      ),
                    if (payload.userId != null && payload.phone != null)
                      const SizedBox(width: 8),
                    if (payload.phone != null)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _callPhone,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: accentColor,
                            side: BorderSide(
                              color: accentColor.withValues(alpha: 0.45),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Позвонить'),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/share/system_share.dart';
import '../features/referral/pending_referral.dart';
import 'auth_service.dart';
import 'pending_referral_store.dart';

/// Приглашение друзей в HanWe (ссылка + SMS / системный шаринг).
class AppInviteService {
  AppInviteService._();

  static const webBase = PendingReferral.webInviteBase;

  static void rememberOfficialCode(String? code) {
    final normalized = PendingReferral.extract(code);
    if (normalized == null) return;
    PendingReferralStore.officialMemory = normalized;
  }

  static void clearOfficialCode() {
    PendingReferralStore.officialMemory = null;
  }

  @visibleForTesting
  static void debugResetOfficialCode() {
    clearOfficialCode();
  }

  static String inviteRef([User? user]) {
    final official = PendingReferralStore.officialMemory?.trim();
    if (official != null && official.isNotEmpty) return official;
    final u = user ?? AuthService.instance.currentUser;
    final username = u?.username?.trim();
    if (username != null && username.isNotEmpty) return username;
    if (u != null) return 'u${u.id}';
    return '';
  }

  static Future<String> resolvedRef({String? ref, User? user}) async {
    final explicit = PendingReferral.extract(ref);
    if (explicit != null) {
      return explicit;
    }
    if (PendingReferralStore.officialMemory == null ||
        PendingReferralStore.officialMemory!.isEmpty) {
      final stored = await PendingReferralStore.officialCode();
      if (stored != null) rememberOfficialCode(stored);
    }
    return inviteRef(user);
  }

  static String webInviteUrl({String? ref}) {
    final r = PendingReferral.extract(ref) ?? inviteRef();
    if (r.isEmpty) return webBase;
    return PendingReferral.shareUrl(r);
  }

  static String deepInviteUrl({String? ref}) {
    final r = PendingReferral.extract(ref) ?? inviteRef();
    if (r.isEmpty) return 'haneat://invite';
    return 'haneat://invite?ref=${Uri.encodeComponent(r)}';
  }

  static bool _looksLikePhone(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 10;
  }

  static String _greeting(String? contactName) {
    final name = contactName?.trim();
    if (name == null || name.isEmpty || _looksLikePhone(name)) {
      return 'Привет!';
    }
    return 'Привет, $name!';
  }

  static String inviteMessage({
    String? contactName,
    String? inviterName,
    String? ref,
  }) {
    final inviter = inviterName?.trim();
    final who = inviter != null && inviter.isNotEmpty ? inviter : 'Я';
    final link = webInviteUrl(ref: ref);
    return '${_greeting(contactName)}\n'
        '$who приглашает вас в HanWe — чаты, лента и каналы.\n\n'
        '$link';
  }

  static Future<void> shareInvite(
    BuildContext context, {
    String? contactName,
    String? ref,
    Rect? shareOrigin,
  }) async {
    final user = AuthService.instance.currentUser;
    final resolved = await resolvedRef(ref: ref, user: user);
    await SystemShare.shareText(
      context,
      text: inviteMessage(
        contactName: contactName,
        inviterName: user?.name,
        ref: resolved,
      ),
      subject: 'Приглашение в HanWe',
      sharePositionOrigin: shareOrigin,
      webSnackBarText: 'Ссылка скопирована',
    );
  }

  static Future<bool> sendSmsInvite({
    required String phoneE164,
    required String message,
  }) async {
    if (kIsWeb) return false;
    final digits = phoneE164.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.isEmpty) return false;
    // queryParameters кодирует пробелы как «+» — iOS SMS показывает их буквально.
    final uri = Uri.parse('sms:$digits?body=${Uri.encodeComponent(message)}');
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri);
    }
    return false;
  }

  static Future<void> inviteContact(
    BuildContext context, {
    required String displayName,
    required String phoneE164,
  }) async {
    final user = AuthService.instance.currentUser;
    final resolved = await resolvedRef(user: user);
    final message = inviteMessage(
      contactName: displayName,
      inviterName: user?.name,
      ref: resolved,
    );

    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.sms_outlined),
              title: const Text('Отправить SMS'),
              subtitle: Text(phoneE164),
              onTap: () => Navigator.pop(ctx, 'sms'),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('Поделиться ссылкой'),
              onTap: () => Navigator.pop(ctx, 'share'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || choice == null) return;

    if (choice == 'sms') {
      final ok = await sendSmsInvite(
        phoneE164: phoneE164,
        message: message,
      );
      if (!context.mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Не удалось открыть SMS. Попробуйте «Поделиться».',
            ),
            action: SnackBarAction(
              label: 'Поделиться',
              onPressed: () {
                unawaited(shareInvite(context, contactName: displayName));
              },
            ),
          ),
        );
      }
      return;
    }

    if (choice == 'share') {
      await shareInvite(context, contactName: displayName);
    }
  }
}

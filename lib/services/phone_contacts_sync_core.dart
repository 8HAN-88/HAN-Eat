import '../core/phone/phone_hash.dart';
import '../models/chat_models.dart';
import 'chat_service.dart';
import 'phone_contacts_match_cache.dart';
import 'phone_contacts_types.dart';

const _maxInvitees = 500;
const _apiBatchSize = 500;

Future<List<ChatUserSearchItem>> matchPhoneHashesInBatches(
  List<String> hashes,
) async {
  final out = <ChatUserSearchItem>[];
  for (var i = 0; i < hashes.length; i += _apiBatchSize) {
    final end = (i + _apiBatchSize).clamp(0, hashes.length);
    final batch = hashes.sublist(i, end);
    final items = await ChatService.syncPhoneContacts(batch);
    out.addAll(items);
  }
  return out;
}

Future<PhoneContactsSyncResult> buildPhoneContactsSyncResult({
  required Map<String, String> hashToName,
  required Map<String, String> hashToE164,
  required Set<String> hashes,
}) async {
  if (hashes.isEmpty) {
    return const PhoneContactsSyncResult(
      phoneBook: [],
      onApp: [],
      invitees: [],
    );
  }

  Object? apiError;
  List<ChatUserSearchItem> users = [];
  try {
    users = await matchPhoneHashesInBatches(hashes.toList());
    await PhoneContactsMatchCache.merge(users);
  } catch (e) {
    apiError = e;
    users = await PhoneContactsMatchCache.loadForHashes(hashes);
  }

  final hashToUser = <String, ChatUserSearchItem>{};
  for (final u in users) {
    final h = u.phoneHash;
    if (h != null && h.isNotEmpty) {
      hashToUser[h] = u;
    }
  }

  final phoneBook = <PhoneBookContact>[];
  final onApp = <PhoneContactMatch>[];
  final invitees = <PhoneContactInvite>[];

  final sortedHashes = hashes.toList()
    ..sort(
      (a, b) => (hashToName[a] ?? '').compareTo(hashToName[b] ?? ''),
    );

  for (final hash in sortedHashes) {
    final e164 = hashToE164[hash];
    if (e164 == null) continue;
    final name = hashToName[hash] ?? e164;
    final matched = hashToUser[hash];
    phoneBook.add(
      PhoneBookContact(
        displayName: name,
        phoneE164: e164,
        matchedUser: matched,
      ),
    );
    if (matched != null) {
      onApp.add(
        PhoneContactMatch(
          user: matched,
          addressBookName: name,
        ),
      );
    } else if (invitees.length < _maxInvitees) {
      invitees.add(PhoneContactInvite(displayName: name, phoneE164: e164));
    }
  }

  return PhoneContactsSyncResult(
    phoneBook: phoneBook,
    onApp: onApp,
    invitees: invitees,
    apiError: apiError,
  );
}

void collectPhoneHashes({
  required String displayName,
  required String phoneRaw,
  required Map<String, String> hashToName,
  required Map<String, String> hashToE164,
  required Set<String> hashes,
  String defaultRegion = 'RU',
}) {
  final label = displayName.trim();
  final e164 = normalizePhoneE164(phoneRaw, defaultRegion: defaultRegion);
  if (e164 == null) return;
  final hash = hashPhoneE164(e164);
  hashes.add(hash);
  hashToName.putIfAbsent(
    hash,
    () => label.isNotEmpty ? label : phoneRaw,
  );
  hashToE164.putIfAbsent(hash, () => e164);
}

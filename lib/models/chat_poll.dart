import 'dart:convert';

/// Настройки опроса в чате (как в Telegram).
class ChatPollSettings {
  const ChatPollSettings({
    this.showVoterNames = true,
    this.multipleChoice = false,
    this.allowAddOptions = false,
    this.allowChangeVote = true,
    this.randomOrder = false,
    this.quizMode = false,
    this.correctOptionIndices = const [],
    this.timeLimitEnabled = false,
    this.durationHours = 24,
    this.hideResultsUntilClosed = false,
  });

  final bool showVoterNames;
  final bool multipleChoice;
  final bool allowAddOptions;
  final bool allowChangeVote;
  final bool randomOrder;
  final bool quizMode;
  final List<int> correctOptionIndices;
  final bool timeLimitEnabled;
  final int durationHours;
  final bool hideResultsUntilClosed;

  ChatPollSettings copyWith({
    bool? showVoterNames,
    bool? multipleChoice,
    bool? allowAddOptions,
    bool? allowChangeVote,
    bool? randomOrder,
    bool? quizMode,
    List<int>? correctOptionIndices,
    bool? timeLimitEnabled,
    int? durationHours,
    bool? hideResultsUntilClosed,
  }) {
    return ChatPollSettings(
      showVoterNames: showVoterNames ?? this.showVoterNames,
      multipleChoice: multipleChoice ?? this.multipleChoice,
      allowAddOptions: allowAddOptions ?? this.allowAddOptions,
      allowChangeVote: allowChangeVote ?? this.allowChangeVote,
      randomOrder: randomOrder ?? this.randomOrder,
      quizMode: quizMode ?? this.quizMode,
      correctOptionIndices: correctOptionIndices ?? this.correctOptionIndices,
      timeLimitEnabled: timeLimitEnabled ?? this.timeLimitEnabled,
      durationHours: durationHours ?? this.durationHours,
      hideResultsUntilClosed:
          hideResultsUntilClosed ?? this.hideResultsUntilClosed,
    );
  }

  Map<String, dynamic> toJson() => {
        'show_voter_names': showVoterNames,
        'multiple_choice': multipleChoice,
        'allow_add_options': allowAddOptions,
        'allow_change_vote': allowChangeVote,
        'random_order': randomOrder,
        'quiz_mode': quizMode,
        'correct_option_indices': correctOptionIndices,
        'time_limit_enabled': timeLimitEnabled,
        'duration_hours': durationHours,
        'hide_results_until_closed': hideResultsUntilClosed,
      };

  factory ChatPollSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ChatPollSettings();
    return ChatPollSettings(
      showVoterNames: json['show_voter_names'] as bool? ?? true,
      multipleChoice: json['multiple_choice'] as bool? ?? false,
      allowAddOptions: json['allow_add_options'] as bool? ?? false,
      allowChangeVote: json['allow_change_vote'] as bool? ?? true,
      randomOrder: json['random_order'] as bool? ?? false,
      quizMode: json['quiz_mode'] as bool? ?? false,
      correctOptionIndices: (json['correct_option_indices'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [],
      timeLimitEnabled: json['time_limit_enabled'] as bool? ?? false,
      durationHours: (json['duration_hours'] as num?)?.toInt() ?? 24,
      hideResultsUntilClosed:
          json['hide_results_until_closed'] as bool? ?? false,
    );
  }
}

class ChatPollOption {
  const ChatPollOption({
    required this.index,
    required this.text,
    this.votes = 0,
    this.percentage = 0,
  });

  final int index;
  final String text;
  final int votes;
  final double percentage;

  factory ChatPollOption.fromJson(Map<String, dynamic> json) {
    return ChatPollOption(
      index: (json['index'] as num?)?.toInt() ?? 0,
      text: json['text'] as String? ?? '',
      votes: (json['votes'] as num?)?.toInt() ?? 0,
      percentage: (json['percentage'] as num?)?.toDouble() ?? 0,
    );
  }
}

class ChatPollMessage {
  const ChatPollMessage({
    required this.question,
    this.description = '',
    required this.options,
    this.settings = const ChatPollSettings(),
    this.isClosed = false,
    this.closesAt,
    this.votedOptionIndices = const [],
    this.totalVotes = 0,
  });

  final String question;
  final String description;
  final List<ChatPollOption> options;
  final ChatPollSettings settings;
  final bool isClosed;
  final DateTime? closesAt;
  final List<int> votedOptionIndices;
  final int totalVotes;

  bool get hasVoted => votedOptionIndices.isNotEmpty;

  /// Closed by owner/server, or past `closes_at` deadline.
  bool get isEffectivelyClosed {
    if (isClosed) return true;
    final at = closesAt;
    if (at == null) return false;
    return !at.toUtc().isAfter(DateTime.now().toUtc());
  }

  bool get hideResults =>
      settings.hideResultsUntilClosed && !isEffectivelyClosed && !hasVoted;

  bool get showResults =>
      isEffectivelyClosed || hasVoted || (totalVotes > 0 && !hideResults);

  factory ChatPollMessage.fromJson(Map<String, dynamic> json) {
    final options = (json['options'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .map(ChatPollOption.fromJson)
            .toList() ??
        [];
    final voted = <int>[];
    final rawIndices = json['voted_option_indices'] as List<dynamic>?;
    if (rawIndices != null) {
      voted.addAll(rawIndices.map((e) => (e as num).toInt()));
    } else if (json['voted_option_index'] != null) {
      voted.add((json['voted_option_index'] as num).toInt());
    }
    DateTime? closesAt;
    final rawCloses = json['closes_at'];
    if (rawCloses is String && rawCloses.isNotEmpty) {
      closesAt = DateTime.tryParse(rawCloses)?.toUtc();
    }
    return ChatPollMessage(
      question: json['question'] as String? ?? '',
      description: json['description'] as String? ?? '',
      options: options,
      settings: ChatPollSettings.fromJson(
        json['settings'] as Map<String, dynamic>?,
      ),
      isClosed: json['is_closed'] as bool? ?? false,
      closesAt: closesAt,
      votedOptionIndices: voted,
      totalVotes: (json['total_votes'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Human-readable remaining time for an open timed poll.
String? formatPollTimeRemaining(DateTime closesAt, {DateTime? now}) {
  final left = closesAt.toUtc().difference((now ?? DateTime.now()).toUtc());
  if (left.inSeconds <= 0) return null;
  if (left.inDays >= 1) {
    final d = left.inDays;
    return 'осталось $d ${_ruDays(d)}';
  }
  if (left.inHours >= 1) {
    final h = left.inHours;
    final m = left.inMinutes % 60;
    return m > 0 ? 'осталось $h ч $m мин' : 'осталось $h ч';
  }
  if (left.inMinutes >= 1) {
    return 'осталось ${left.inMinutes} мин';
  }
  return 'осталось ${left.inSeconds} сек';
}

String _ruDays(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 14) return 'д';
  if (mod10 == 1) return 'д';
  return 'д';
}

ChatPollMessage? parseChatPollFromContent(String content) {
  if (content.trim().isEmpty) return null;
  try {
    final data = jsonDecode(content);
    if (data is! Map<String, dynamic>) return null;
    final poll = data['poll'];
    if (poll is! Map<String, dynamic>) return null;
    return ChatPollMessage.fromJson(poll);
  } catch (_) {
    return null;
  }
}

String chatPollPreviewText(ChatPollMessage poll) {
  final q = poll.question.trim();
  if (q.isEmpty) return poll.settings.quizMode ? '📊 Викторина' : '📊 Опрос';
  return '📊 $q';
}

/// Maps a quiz "correct" controller index onto compacted non-empty option indices.
List<int> resolveQuizCorrectIndices({
  required List<String> rawOptionTexts,
  required int? correctControllerIndex,
}) {
  if (correctControllerIndex == null) return const [];
  if (correctControllerIndex < 0 ||
      correctControllerIndex >= rawOptionTexts.length) {
    return const [];
  }
  var optionIndex = 0;
  for (var i = 0; i < rawOptionTexts.length; i++) {
    final text = rawOptionTexts[i].trim();
    if (text.isEmpty) continue;
    if (i == correctControllerIndex) return [optionIndex];
    optionIndex++;
  }
  return const [];
}

class ChatPollVoter {
  const ChatPollVoter({
    required this.id,
    this.name,
    this.username,
    this.avatarUrl,
  });

  final int id;
  final String? name;
  final String? username;
  final String? avatarUrl;

  String get displayName {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    final u = username?.trim();
    if (u != null && u.isNotEmpty) return u.startsWith('@') ? u : '@$u';
    return 'Пользователь';
  }

  factory ChatPollVoter.fromJson(Map<String, dynamic> json) {
    return ChatPollVoter(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String?,
      username: json['username'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}

class ChatPollVotersOption {
  const ChatPollVotersOption({
    required this.index,
    required this.text,
    required this.voters,
  });

  final int index;
  final String text;
  final List<ChatPollVoter> voters;

  factory ChatPollVotersOption.fromJson(Map<String, dynamic> json) {
    return ChatPollVotersOption(
      index: (json['index'] as num?)?.toInt() ?? 0,
      text: json['text'] as String? ?? '',
      voters: (json['voters'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ChatPollVoter.fromJson)
          .toList(),
    );
  }
}

class ChatPollVotersResult {
  const ChatPollVotersResult({
    required this.options,
    required this.total,
  });

  final List<ChatPollVotersOption> options;
  final int total;

  factory ChatPollVotersResult.fromJson(Map<String, dynamic> json) {
    return ChatPollVotersResult(
      options: (json['options'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ChatPollVotersOption.fromJson)
          .toList(),
      total: (json['total'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Патчит `is_closed` в JSON-содержимом опроса.
String patchChatPollClosedInContent(String content, {required bool isClosed}) {
  if (content.trim().isEmpty) return content;
  try {
    final data = jsonDecode(content);
    if (data is! Map<String, dynamic>) return content;
    final poll = data['poll'];
    if (poll is! Map<String, dynamic>) return content;
    poll['is_closed'] = isClosed;
    data['poll'] = poll;
    return jsonEncode(data);
  } catch (_) {
    return content;
  }
}

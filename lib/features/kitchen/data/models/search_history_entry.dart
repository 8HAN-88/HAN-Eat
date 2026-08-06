import 'package:hive/hive.dart';

import 'analysis_mode.dart';

class SearchHistoryEntry {
  SearchHistoryEntry({
    required this.query,
    required this.timestamp,
    required this.mode,
  });

  final String query;
  final DateTime timestamp;
  final AnalysisMode mode;

  static const boxName = 'search_history';

  Map<String, dynamic> toMap() => {
        'query': query,
        'timestamp': timestamp.toIso8601String(),
        'mode': mode.apiValue,
      };

  factory SearchHistoryEntry.fromMap(Map<String, dynamic> map) {
    return SearchHistoryEntry(
      query: map['query'] as String? ?? '',
      timestamp: DateTime.tryParse(map['timestamp'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(map['ts'] as int? ?? 0),
      mode: analysisModeFromString(map['mode'] as String? ?? 'all'),
    );
  }
}

class SearchHistoryEntryAdapter extends TypeAdapter<SearchHistoryEntry> {
  @override
  final int typeId = 0;

  @override
  SearchHistoryEntry read(BinaryReader reader) {
    final query = reader.readString();
    final millis = reader.readInt();
    final modeRaw = reader.readString();
    return SearchHistoryEntry(
      query: query,
      timestamp: DateTime.fromMillisecondsSinceEpoch(millis),
      mode: analysisModeFromString(modeRaw),
    );
  }

  @override
  void write(BinaryWriter writer, SearchHistoryEntry obj) {
    writer
      ..writeString(obj.query)
      ..writeInt(obj.timestamp.millisecondsSinceEpoch)
      ..writeString(obj.mode.apiValue);
  }
}


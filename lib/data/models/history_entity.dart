class HistoryEntity {
  const HistoryEntity({
    required this.id,
    required this.modeId,
    required this.modeNameSnapshot,
    required this.originalText,
    required this.resultsJson,
    this.scenarioKey,
    this.lengthChannel,
    required this.createdAtMs,
  });

  final int id;
  final int modeId;
  final String modeNameSnapshot;
  final String originalText;
  final String resultsJson;
  final String? scenarioKey;
  final String? lengthChannel;
  final int createdAtMs;

  factory HistoryEntity.fromMap(Map<String, Object?> map) {
    return HistoryEntity(
      id: map['id']! as int,
      modeId: map['mode_id']! as int,
      modeNameSnapshot: map['mode_name_snapshot']! as String,
      originalText: map['original_text']! as String,
      resultsJson: map['results_json']! as String,
      scenarioKey: map['scenario_key'] as String?,
      lengthChannel: map['length_channel'] as String?,
      createdAtMs: map['created_at']! as int,
    );
  }
}

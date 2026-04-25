import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/llm/rewrite_result.dart';
import 'app_database.dart';
import 'models/history_entity.dart';

class HistoryRepository {
  HistoryRepository(AppDatabase db) : _db = db.raw;

  final Database _db;

  Future<List<HistoryEntity>> recent({int limit = 100}) async {
    final rows = await _db.rawQuery(
      'SELECT * FROM history ORDER BY created_at DESC LIMIT ?',
      [limit],
    );
    return rows.map(HistoryEntity.fromMap).toList();
  }

  Future<int> insert({
    required int modeId,
    required String modeNameSnapshot,
    required String originalText,
    required List<RewriteVariant> variants,
    String? scenarioKey,
    String? lengthChannel,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final payload = jsonEncode(variants.map((e) => e.toJson()).toList());
    return _db.insert('history', {
      'mode_id': modeId,
      'mode_name_snapshot': modeNameSnapshot,
      'original_text': originalText,
      'results_json': payload,
      'scenario_key': scenarioKey,
      'length_channel': lengthChannel,
      'created_at': now,
    });
  }

  Future<void> clear() async {
    await _db.delete('history');
  }
}

import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'models/mode_entity.dart';

class ModeRepository {
  ModeRepository(AppDatabase db) : _db = db.raw;

  final Database _db;

  String _typeString(ModeType t) {
    switch (t) {
      case ModeType.preset:
        return 'preset';
      case ModeType.custom:
        return 'custom';
      case ModeType.persona:
        return 'persona';
    }
  }

  Future<List<ModeEntity>> listByType(ModeType? type, {String? query}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (type != null) {
      where.add('mode_type = ?');
      args.add(_typeString(type));
    }
    if (query != null && query.trim().isNotEmpty) {
      where.add('name LIKE ?');
      args.add('%${query.trim()}%');
    }
    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final rows = await _db.rawQuery(
      'SELECT * FROM modes $whereSql ORDER BY is_builtin DESC, updated_at DESC',
      args,
    );
    return rows.map(ModeEntity.fromMap).toList();
  }

  Future<ModeEntity?> getById(int id) async {
    final rows = await _db.rawQuery('SELECT * FROM modes WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    return ModeEntity.fromMap(rows.first);
  }

  Future<int> insertCustom({
    required String name,
    required String description,
    required String stylePrompt,
    String? examplesJson,
    String? negativeExamplesJson,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.insert('modes', {
      'name': name,
      'description': description,
      'mode_type': 'custom',
      'style_prompt': stylePrompt,
      'examples_json': examplesJson,
      'negative_examples_json': negativeExamplesJson,
      'is_builtin': 0,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<int> insertPersona({
    required String name,
    required String description,
    required String stylePrompt,
    String? memoryJson,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.insert('modes', {
      'name': name,
      'description': description,
      'mode_type': 'persona',
      'style_prompt': stylePrompt,
      'examples_json': memoryJson,
      'negative_examples_json': null,
      'is_builtin': 0,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> updateCustom(
    int id, {
    required String name,
    required String description,
    required String stylePrompt,
    String? examplesJson,
    String? negativeExamplesJson,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'modes',
      {
        'name': name,
        'description': description,
        'style_prompt': stylePrompt,
        'examples_json': examplesJson,
        'negative_examples_json': negativeExamplesJson,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteIfEditable(int id) async {
    await _db.delete(
      'modes',
      where: 'id = ? AND is_builtin = 0',
      whereArgs: [id],
    );
  }
}

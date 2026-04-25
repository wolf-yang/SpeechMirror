import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

class KvRepository {
  KvRepository(AppDatabase db) : _db = db.raw;

  final Database _db;

  Future<String?> get(String key) async {
    final rows = await _db.rawQuery('SELECT v FROM app_kv WHERE k = ?', [key]);
    if (rows.isEmpty) return null;
    return rows.first['v'] as String?;
  }

  Future<void> set(String key, String value) async {
    await _db.insert('app_kv', {'k': key, 'v': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> remove(String key) async {
    await _db.delete('app_kv', where: 'k = ?', whereArgs: [key]);
  }

  Future<void> removeWhereKeyLike(String pattern) async {
    await _db.delete('app_kv', where: 'k LIKE ?', whereArgs: [pattern]);
  }

  Future<List<String>> allKeys() async {
    final rows = await _db.rawQuery('SELECT k FROM app_kv');
    return rows.map((e) => e['k']! as String).toList();
  }
}

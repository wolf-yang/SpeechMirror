import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;

  static Future<AppDatabase> open() async {
    final dbPath = await getDatabasePath();
    final db = await openDatabase(
      dbPath,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE modes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  description TEXT NOT NULL,
  mode_type TEXT NOT NULL,
  style_prompt TEXT NOT NULL,
  examples_json TEXT,
  negative_examples_json TEXT,
  is_builtin INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''');
        await db.execute('''
CREATE TABLE history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  mode_id INTEGER NOT NULL,
  mode_name_snapshot TEXT NOT NULL,
  original_text TEXT NOT NULL,
  results_json TEXT NOT NULL,
  scenario_key TEXT,
  length_channel TEXT,
  tone_0_100 INTEGER,
  created_at INTEGER NOT NULL
);
''');
        await db.execute('''
CREATE TABLE app_kv (
  k TEXT PRIMARY KEY,
  v TEXT NOT NULL
);
''');
        final now = DateTime.now().millisecondsSinceEpoch;
        for (final row in _presetSeedRows(now)) {
          await db.insert('modes', row);
        }
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          final now = DateTime.now().millisecondsSinceEpoch;
          final rows = await db.query('modes', where: 'name = ?', whereArgs: ['据理回击模式']);
          if (rows.isEmpty) {
            await db.insert('modes', _mode(now, '据理回击模式', _sharpRebuttalDesc, _sharpRebuttalPrompt));
          }
        }
      },
    );
    return AppDatabase._(db);
  }

  static Future<String> getDatabasePath() async {
    final dir = await getDatabasesPath();
    return p.join(dir, 'speechmirror.db');
  }

  Database get raw => _db;

  Future<void> close() => _db.close();

  /// 清除历史、非内置模式与本地 KV；内置预设模式保留。
  Future<void> wipeUserData() async {
    await _db.delete('history');
    await _db.delete('modes', where: 'is_builtin = ?', whereArgs: [0]);
    await _db.delete('app_kv');
  }

  static List<Map<String, Object?>> _presetSeedRows(int now) {
    return [
      _mode(now, '尊敬模式', '对老师、长辈、领导：敬语、谦逊、条理清晰。', _respectPrompt),
      _mode(now, '安慰模式', '先共情，再支持；避免说教与否定对方感受。', _comfortPrompt),
      _mode(now, '正式模式', '商务与正式通知：严谨、清晰、可执行。', _formalPrompt),
      _mode(now, '委婉模式', '拒绝与提意见：温和、留余地、减少对抗。', _indirectPrompt),
      _mode(now, '幽默模式', '朋友闲聊：轻松有趣，不冒犯、不低俗。', _humorPrompt),
      _mode(now, '道歉模式', '真诚道歉，承担责任，提出补救。', _apologyPrompt),
      _mode(now, '感谢模式', '表达感谢，具体说明感谢点，语气真诚。', _thanksPrompt),
      _mode(now, '据理回击模式', _sharpRebuttalDesc, _sharpRebuttalPrompt),
    ];
  }

  static Map<String, Object?> _mode(int now, String name, String desc, String style) {
    return {
      'name': name,
      'description': desc,
      'mode_type': 'preset',
      'style_prompt': style,
      'examples_json': null,
      'negative_examples_json': null,
      'is_builtin': 1,
      'created_at': now,
      'updated_at': now,
    };
  }
}

const _sharpRebuttalDesc =
    '面对不讲理、胡搅蛮缠或甩锅时：有理有据、守住边界；坚定不怂，但不脏话、不人身攻击。';

const _respectPrompt = '''
你是中文话术改写助手。将用户原话改写为更尊敬、谦逊、得体的表达。
要求：称呼得体；适度使用「您」「请」「望」等敬语；避免生硬套话；保持原意。
''';

const _comfortPrompt = '''
你是中文话术改写助手。将用户原话改写为更适合安慰他人的表达。
要求：先承认对方感受，再表达支持；避免「你应该」式说教；语气真诚克制。
''';

const _formalPrompt = '''
你是中文话术改写助手。将用户原话改写为更正式的商务/书面表达。
要求：结构清晰、用词准确、可执行信息完整；避免口语碎词。
''';

const _indirectPrompt = '''
你是中文话术改写助手。将用户原话改写为更委婉、易接受的表达。
要求：先肯定或感谢，再提出限制/意见；给对方台阶；避免攻击性措辞。
''';

const _humorPrompt = '''
你是中文话术改写助手。将用户原话改写为更轻松幽默的朋友聊天风格。
要求：自然不尬；不低俗；不拿敏感话题开玩笑；保持原意。
''';

const _apologyPrompt = '''
你是中文话术改写助手。将用户原话改写为更真诚的道歉表达。
要求：明确责任与共情；提出补救或改进；避免辩解甩锅。
''';

const _thanksPrompt = '''
你是中文话术改写助手。将用户原话改写为更有诚意的感谢表达。
要求：具体点出感谢原因；语气真诚；避免空洞夸张。
''';

const _sharpRebuttalPrompt = '''
你是中文话术改写助手。用户正面对不讲理、双标、甩锅或胡搅蛮缠的沟通对象，需要把原话改成「有理有据、守住底线」的回击或澄清。
要求：指出对方逻辑或事实问题；语气坚定、冷静、不卑不亢；避免脏话与人身攻击；不煽动违法或暴力；可适度短句加强节奏；保持可发送的文明表达。
''';

import '../../data/models/mode_entity.dart';

class PromptBuilder {
  static String systemForRewriteJson({
    required ModeEntity mode,
    String? scenarioHint,
    String? lengthChannel,
    String? userHint,
  }) {
    final buf = StringBuffer();
    buf.writeln(mode.stylePrompt.trim());
    if (mode.examplesJson != null && mode.examplesJson!.trim().isNotEmpty) {
      buf.writeln('\n【正面示例（JSON 或纯文本）】\n${mode.examplesJson!.trim()}');
    }
    if (mode.negativeExamplesJson != null &&
        mode.negativeExamplesJson!.trim().isNotEmpty) {
      buf.writeln('\n【应避免的说法】\n${mode.negativeExamplesJson!.trim()}');
    }
    if (scenarioHint != null && scenarioHint.isNotEmpty) {
      buf.writeln('\n【场景意图】$scenarioHint');
    }
    if (lengthChannel != null && lengthChannel.isNotEmpty) {
      buf.writeln('\n【长度/渠道】$lengthChannel');
    }
    if (userHint != null && userHint.trim().isNotEmpty) {
      buf.writeln('\n【用户附加提示】${userHint.trim()}');
    }
    buf.writeln('''
【输出契约】
只输出一个 JSON 对象（不要 Markdown、不要代码围栏），格式如下：
{"variants":[{"label":"更稳","text":"..."},{"label":"更暖","text":"..."},{"label":"更简","text":"..."}],"rationale":"用一句话解释整体改写思路"}
其中三个 label 必须严格为：更稳、更暖、更简；text 为中文改写结果。
禁止输出任何思考过程、推理过程或中间分析内容；不要输出除 JSON 外的任何文字。
''');
    return buf.toString();
  }

  static String systemForRewritePlainText({
    required ModeEntity mode,
    String? scenarioHint,
    String? lengthChannel,
    String? userHint,
  }) {
    final buf = StringBuffer();
    buf.writeln(mode.stylePrompt.trim());
    if (mode.examplesJson != null && mode.examplesJson!.trim().isNotEmpty) {
      buf.writeln('\n【正面示例（JSON 或纯文本）】\n${mode.examplesJson!.trim()}');
    }
    if (mode.negativeExamplesJson != null &&
        mode.negativeExamplesJson!.trim().isNotEmpty) {
      buf.writeln('\n【应避免的说法】\n${mode.negativeExamplesJson!.trim()}');
    }
    if (scenarioHint != null && scenarioHint.isNotEmpty) {
      buf.writeln('\n【场景意图】$scenarioHint');
    }
    if (lengthChannel != null && lengthChannel.isNotEmpty) {
      buf.writeln('\n【长度/渠道】$lengthChannel');
    }
    if (userHint != null && userHint.trim().isNotEmpty) {
      buf.writeln('\n【用户附加提示】${userHint.trim()}');
    }
    buf.writeln('''
【输出契约】
只输出最终改写后的单句中文，不要 JSON，不要 Markdown，不要解释，不要前后缀，不要编号。
''');
    return buf.toString();
  }

  static String userForRewrite(String original) {
    return '【用户原话】\n$original';
  }

  static String systemForModeDraft({
    required String modeName,
    required String oneLineStyle,
  }) {
    return '''
你是产品设计助手。请根据用户一句话需求，生成可用于「语言模式」的结构化草稿。
只输出 JSON（不要 Markdown），且顶层键必须严格为：
{"style_description":"字符串","positive_examples":["字符串", ...共5条],"negative_examples":["字符串", ...共3条]}
其中 positive_examples 每条建议使用「原话→改写」格式。
模式名称：$modeName
用户描述：$oneLineStyle
''';
  }

  static String systemForDistillPersona(String chunk) {
    return '''
你是人格风格分析助手。根据给定「对方发言」文本，总结其说话风格与人格要点。
只输出 JSON（不要 Markdown），格式：
{"memory":{"topics":[],"habits":[],"catchphrases":[]},"persona":{"rules":[],"identity":"","style":"","emotion":"","social":""}}
文本如下：
---
$chunk
---
''';
  }
}

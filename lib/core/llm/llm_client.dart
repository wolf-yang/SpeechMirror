import 'dart:convert';

import 'package:dio/dio.dart';

import '../../data/secure_credential_store.dart';
import '../prompt/prompt_builder.dart';
import 'rewrite_result.dart';
import 'rewrite_stream_event.dart';

class LlmClient {
  LlmClient({
    required SecureCredentialStore credentials,
    Dio? dio,
  })  : _credentials = credentials,
        _dio = dio ?? Dio();

  final SecureCredentialStore _credentials;
  final Dio _dio;

  static const _glm47MaxTokens = 131072;
  static const _glm47ContextTokens = 200000;

  String _chatCompletionsUrl(String baseUrl) {
    var b = baseUrl.trim();
    if (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    if (b.endsWith('/v1')) {
      return '$b/chat/completions';
    }
    return '$b/v1/chat/completions';
  }

  bool _isGlmModel(String model) => model.toLowerCase().contains('glm');

  int _effectiveMaxTokens({
    required String model,
    required String system,
    required String user,
  }) {
    if (!_isGlmModel(model)) return 3072;
    final promptApprox = ((system.length + user.length) / 1.5).ceil();
    final reserve = 4096;
    final budget = _glm47ContextTokens - promptApprox - reserve;
    return budget.clamp(1024, _glm47MaxTokens);
  }

  Future<LlmRewriteResult> rewrite({
    required String model,
    required String system,
    required String user,
  }) async {
    final baseUrl = await _credentials.readBaseUrl();
    final apiKey = await _credentials.readApiKey();
    if (baseUrl == null || baseUrl.isEmpty) {
      throw LlmException('未配置 Base URL');
    }
    if (apiKey == null || apiKey.isEmpty) {
      throw LlmException('未配置 API Key');
    }

    final url = _chatCompletionsUrl(baseUrl);
    try {
      final resp = await _dio.post<Map<String, dynamic>>(
        url,
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          receiveTimeout: const Duration(seconds: 45),
          sendTimeout: const Duration(seconds: 15),
        ),
        data: {
          'model': model,
          'temperature': 0.45,
          'max_tokens': _effectiveMaxTokens(
            model: model,
            system: system,
            user: user,
          ),
          'messages': [
            {'role': 'system', 'content': system},
            {'role': 'user', 'content': user},
          ],
          if (_isGlmModel(model)) 'thinking': {'type': 'disabled'},
        },
      );
      final data = resp.data;
      final content = _extractAssistantTextFromChatResponse(data).trim();
      if (content.isEmpty) {
        final dbg = _extractResponseDebug(data);
        throw LlmException('模型返回为空（响应结构不兼容或无正文）：$dbg');
      }
      return _parseContent(content);
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 401) {
        throw LlmException('401：API Key 或 Base URL 可能不正确');
      }
      throw LlmException('调用失败：$e');
    }
  }

  /// 单条改写的流式输出，只产出纯文本。
  Stream<RewriteStreamEvent> rewritePlainTextStream({
    required String model,
    required String system,
    required String user,
  }) async* {
    final baseUrl = await _credentials.readBaseUrl();
    final apiKey = await _credentials.readApiKey();
    if (baseUrl == null || baseUrl.isEmpty) {
      yield RewriteStreamFailed('未配置 Base URL');
      return;
    }
    if (apiKey == null || apiKey.isEmpty) {
      yield RewriteStreamFailed('未配置 API Key');
      return;
    }

    final url = _chatCompletionsUrl(baseUrl);
    final payload = <String, dynamic>{
      'model': model,
      'temperature': 0.45,
      'max_tokens': _effectiveMaxTokens(
        model: model,
        system: system,
        user: user,
      ),
      'stream': true,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
      if (_isGlmModel(model)) 'thinking': {'type': 'disabled'},
    };

    try {
      final response = await _dio.post<ResponseBody>(
        url,
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
          },
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(seconds: 45),
          sendTimeout: const Duration(seconds: 15),
        ),
        data: jsonEncode(payload),
      );
      final body = response.data;
      if (body == null) {
        yield RewriteStreamFailed('流式响应体为空');
        return;
      }
      final answerAcc = StringBuffer();
      String? lastDeltaKeys;
      String? lastRawDataLine;
      await for (final line in utf8.decoder.bind(body.stream).transform(const LineSplitter())) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith(':')) continue;
        if (trimmed == 'data: [DONE]' || trimmed == '[DONE]') continue;
        if (!trimmed.startsWith('data:')) continue;
        final jsonStr = trimmed.substring(5).trimLeft();
        if (jsonStr == '[DONE]') continue;
        lastRawDataLine = jsonStr.length > 220 ? '${jsonStr.substring(0, 220)}...' : jsonStr;
        Map<String, dynamic>? deltaRoot;
        try {
          deltaRoot = jsonDecode(jsonStr) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
        final choices = deltaRoot['choices'] as List<dynamic>?;
        if (choices == null || choices.isEmpty) continue;
        final choice0 = choices.first as Map<String, dynamic>?;
        final delta = choice0?['delta'] as Map<String, dynamic>?;
        if (delta == null) continue;
        lastDeltaKeys = delta.keys.join(',');
        final answerPiece = _extractStreamDeltaText(delta);
        if (answerPiece.isEmpty) continue;
        answerAcc.write(answerPiece);
        yield RewriteStreamPartial(answerAccumulated: answerAcc.toString());
      }
      final full = answerAcc.toString().trim();
      if (full.isEmpty) {
        yield RewriteStreamFailed('模型未返回正文内容；delta_keys=${lastDeltaKeys ?? '-'}；last_data=${lastRawDataLine ?? '-'}');
        return;
      }
      yield RewriteStreamCompleted.text(full);
    } catch (e) {
      if (e is LlmException) {
        yield RewriteStreamFailed(e.message);
      } else {
        yield RewriteStreamFailed('流式请求异常：${e.toString()}');
      }
    }
  }

  /// 三条结果：非流式直出 JSON，避免前台逐字显示。
  Stream<RewriteStreamEvent> rewriteStream({
    required String model,
    required String system,
    required String user,
  }) async* {
    try {
      final parsed = await rewrite(model: model, system: system, user: user);
      yield RewriteStreamCompleted.json(parsed);
    } catch (e) {
      if (e is LlmException) {
        yield RewriteStreamFailed(e.message);
      } else {
        yield RewriteStreamFailed('流式请求异常：${e.toString()}');
      }
    }
  }

  String _extractAssistantTextFromChatResponse(Map<String, dynamic>? data) {
    final choice0 = data?['choices']?[0];
    if (choice0 is Map<String, dynamic>) {
      final msg = choice0['message'];
      if (msg is Map<String, dynamic>) {
        final s = _extractTextFromDynamic(msg['content']);
        if (s.isNotEmpty) return s;
      }
      final legacyText = _extractTextFromDynamic(choice0['text']);
      if (legacyText.isNotEmpty) return legacyText;
    }
    return '';
  }

  String _extractStreamDeltaText(Map<String, dynamic> delta) {
    final contentText = _extractTextFromDynamic(delta['content']);
    if (contentText.isNotEmpty) return contentText;
    return _extractTextFromDynamic(delta['text']);
  }

  String _extractTextFromDynamic(Object? content) {
    if (content is String) return content;
    if (content is List) {
      final sb = StringBuffer();
      for (final item in content) {
        sb.write(_extractTextFromDynamic(item));
      }
      return sb.toString();
    }
    if (content is Map<String, dynamic>) {
      final direct = content['text'];
      if (direct is String && direct.isNotEmpty) return direct;
      final out = content['output_text'];
      if (out is String && out.isNotEmpty) return out;
      final nestedContent = content['content'];
      final nested = _extractTextFromDynamic(nestedContent);
      if (nested.isNotEmpty) return nested;
    }
    return '';
  }

  String _extractResponseDebug(Map<String, dynamic>? data) {
    if (data == null) return '空响应体';
    final choice0 = data['choices'] is List && (data['choices'] as List).isNotEmpty
        ? (data['choices'] as List).first
        : null;
    if (choice0 is Map<String, dynamic>) {
      final msg = choice0['message'];
      final finish = choice0['finish_reason']?.toString() ?? '-';
      if (msg is Map<String, dynamic>) {
        final keys = msg.keys.join(',');
        return 'message.keys=$keys, finish_reason=$finish';
      }
      final keys = choice0.keys.join(',');
      return 'choice.keys=$keys, finish_reason=$finish';
    }
    return 'top.keys=${data.keys.join(',')}';
  }

  /// 极小连通性检测（不计入缓存）。
  Future<void> ping() async {
    final baseUrl = await _credentials.readBaseUrl();
    final apiKey = await _credentials.readApiKey();
    final m = await _credentials.readModel();
    if (baseUrl == null || baseUrl.isEmpty) {
      throw LlmException('未配置 Base URL');
    }
    if (apiKey == null || apiKey.isEmpty) {
      throw LlmException('未配置 API Key');
    }
    final model = (m == null || m.isEmpty) ? 'gpt-4o-mini' : m;
    final url = _chatCompletionsUrl(baseUrl);
    final resp = await _dio.post<Map<String, dynamic>>(
      url,
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        receiveTimeout: const Duration(seconds: 30),
      ),
      data: {
        'model': model,
        'max_tokens': 8,
        'messages': [
          {'role': 'user', 'content': 'ping'},
        ],
      },
    );
    if (resp.statusCode != 200) {
      throw LlmException('HTTP ${resp.statusCode}');
    }
  }

  /// AI 辅助创建模式：返回 JSON 字符串解析前的原始 content。
  Future<Map<String, dynamic>> generateModeDraftJson({
    required String modeName,
    required String oneLineStyle,
  }) async {
    final baseUrl = await _credentials.readBaseUrl();
    final apiKey = await _credentials.readApiKey();
    final m = await _credentials.readModel();
    if (baseUrl == null || apiKey == null) {
      throw LlmException('请先配置 Base URL 与 API Key');
    }
    final model = (m == null || m.isEmpty) ? 'gpt-4o-mini' : m;
    final url = _chatCompletionsUrl(baseUrl);
    final system = PromptBuilder.systemForModeDraft(
      modeName: modeName,
      oneLineStyle: oneLineStyle,
    );
    final resp = await _dio.post<Map<String, dynamic>>(
      url,
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        receiveTimeout: const Duration(seconds: 120),
      ),
      data: {
        'model': model,
        'temperature': 0.5,
        'messages': [
          {'role': 'system', 'content': system},
          {'role': 'user', 'content': '请生成草稿。'},
        ],
      },
    );
    final content = resp.data?['choices']?[0]?['message']?['content'] as String?;
    if (content == null || content.trim().isEmpty) {
      throw LlmException('模型返回为空');
    }
    final cleaned = _stripJsonFence(content);
    return jsonDecode(cleaned) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> distillPersona(String chunk) async {
    final baseUrl = await _credentials.readBaseUrl();
    final apiKey = await _credentials.readApiKey();
    final m = await _credentials.readModel();
    if (baseUrl == null || apiKey == null) {
      throw LlmException('请先配置 Base URL 与 API Key');
    }
    final model = (m == null || m.isEmpty) ? 'gpt-4o-mini' : m;
    final url = _chatCompletionsUrl(baseUrl);
    final system =
        '你是人格风格分析助手。只输出 JSON。根据用户提供的聊天记录片段总结对方说话风格。';
    final trimmed = chunk.trim();
    if (trimmed.isEmpty) {
      throw LlmException('蒸馏文本为空');
    }
    final clipped = trimmed.length > 8000 ? trimmed.substring(0, 8000) : trimmed;
    final user = '片段如下（可能不完整）：\n---\n$clipped\n---';
    final resp = await _dio.post<Map<String, dynamic>>(
      url,
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        receiveTimeout: const Duration(seconds: 120),
      ),
      data: {
        'model': model,
        'temperature': 0.4,
        'messages': [
          {'role': 'system', 'content': system},
          {'role': 'user', 'content': user},
        ],
      },
    );
    final content = resp.data?['choices']?[0]?['message']?['content'] as String?;
    if (content == null || content.trim().isEmpty) {
      throw LlmException('模型返回为空');
    }
    final cleaned = _stripJsonFence(content);
    return jsonDecode(cleaned) as Map<String, dynamic>;
  }

  /// 为蒸馏生成的人物模式起一个列表展示用短名（不含时间戳编号）。
  Future<String> suggestPersonaListName(Map<String, dynamic> analysis) async {
    final baseUrl = await _credentials.readBaseUrl();
    final apiKey = await _credentials.readApiKey();
    final m = await _credentials.readModel();
    if (baseUrl == null || apiKey == null) {
      throw LlmException('请先配置 Base URL 与 API Key');
    }
    final model = (m == null || m.isEmpty) ? 'gpt-4o-mini' : m;
    final url = _chatCompletionsUrl(baseUrl);
    final payload = <String, dynamic>{};
    for (final k in ['style_label', 'tone', 'persona', 'summary', 'communication_tactics', 'core_characteristics']) {
      if (analysis.containsKey(k)) payload[k] = analysis[k];
    }
    var userBody = '根据以下人格蒸馏 JSON，输出一个简短的中文模式名，用于应用内列表（6-14 个汉字）。'
        '只输出名称本身：不要引号、不要编号、不要「人物模式」前缀、不要换行或解释。\n'
        '${jsonEncode(payload)}';
    if (userBody.length > 6000) {
      userBody = userBody.substring(0, 6000);
    }
    final resp = await _dio.post<Map<String, dynamic>>(
      url,
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        receiveTimeout: const Duration(seconds: 60),
      ),
      data: {
        'model': model,
        'temperature': 0.35,
        'max_tokens': 48,
        'messages': [
          {
            'role': 'system',
            'content': '你是应用文案助手，只按要求输出一行中文名称。',
          },
          {'role': 'user', 'content': userBody},
        ],
      },
    );
    final content = resp.data?['choices']?[0]?['message']?['content'] as String?;
    if (content == null || content.trim().isEmpty) {
      throw LlmException('模型返回为空');
    }
    var name = content.trim().split('\n').first.trim();
    while (name.length >= 2) {
      final a = name.codeUnitAt(0);
      final b = name.codeUnitAt(name.length - 1);
      final stripPair = (a == 0x22 && b == 0x22) || (a == 0x201C && b == 0x201D);
      final stripCn = (name.startsWith('「') && name.endsWith('」'));
      if (!stripPair && !stripCn) break;
      name = name.substring(1, name.length - 1).trim();
    }
    if (name.length > 20) {
      name = name.substring(0, 20);
    }
    if (name.length < 2) {
      throw LlmException('名称过短');
    }
    return name.startsWith('人物') ? name : '人物·$name';
  }

  LlmRewriteResult _parseContent(String content) {
    final cleaned = _stripJsonFence(content);
    final map = jsonDecode(cleaned) as Map<String, dynamic>;
    final vars = (map['variants'] as List<dynamic>? ?? [])
        .map((e) => RewriteVariant.fromJson(e as Map<String, dynamic>))
        .toList();
    if (vars.length != 3) {
      throw LlmException('模型返回 variants 数量不为 3');
    }
    final rationale = (map['rationale'] as String?) ?? '';
    return LlmRewriteResult(variants: vars, rationale: rationale);
  }

  static String _stripJsonFence(String content) {
    var s = content.trim();
    if (s.startsWith('```')) {
      final firstNl = s.indexOf('\n');
      if (firstNl != -1) {
        s = s.substring(firstNl + 1);
      }
      final fence = s.lastIndexOf('```');
      if (fence != -1) {
        s = s.substring(0, fence).trim();
      }
    }
    return s;
  }
}

class LlmException implements Exception {
  LlmException(this.message);
  final String message;
  @override
  String toString() => message;
}

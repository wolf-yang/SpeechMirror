import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import 'core/llm/llm_client.dart';
import 'core/llm/rewrite_stream_event.dart';
import 'core/prompt/prompt_builder.dart';
import 'core/prompt/rewrite_input_parser.dart';
import 'core/scenarios.dart';
import 'data/app_database.dart';
import 'data/models/mode_entity.dart';
import 'data/kv_repository.dart';
import 'data/secure_credential_store.dart';
import 'overlay/overlay_panel_screen.dart';
import 'platform/overlay_bridge.dart';
import 'providers/app_providers.dart';

/// Android 悬浮窗内第二 Flutter 引擎入口（与 [main] 隔离）。
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _OverlayBootstrap());
}

class _OverlayBootstrap extends StatefulWidget {
  const _OverlayBootstrap();

  @override
  State<_OverlayBootstrap> createState() => _OverlayBootstrapState();
}

class _OverlayBootstrapState extends State<_OverlayBootstrap> {
  Object? _error;
  Widget? _app;
  static const _panelChannel = MethodChannel('com.speechmirror.app/overlay_panel');
  static const _kRecent = 'recent_mode_ids';
  static const _kSelectedModeId = 'selected_mode_id';
  KvRepository? _kv;
  SecureCredentialStore? _secure;
  LlmClient? _llm;
  List<ModeEntity> _modes = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sw = Stopwatch()..start();
    try {
      final db = await AppDatabase.open();
      final secure = SecureCredentialStore();
      final kv = KvRepository(db);
      _kv = kv;
      _secure = secure;
      unawaited(OverlayBridge.syncOverlayPrefs(
        overlayAutoShow: await kv.get('overlay_auto_show') == '1',
        collectDialogEnabled: await kv.get('collect_dialog_enabled') == '1',
      ));
      final llm = LlmClient(credentials: secure);
      _llm = llm;
      _modes = await ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          secureCredentialStoreProvider.overrideWithValue(secure),
          kvRepositoryProvider.overrideWithValue(kv),
          llmClientProvider.overrideWithValue(llm),
        ],
      ).read(modeRepositoryProvider).listByType(null);
      _installPanelChannel();
      if (!mounted) return;
      setState(() {
        _app = ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            secureCredentialStoreProvider.overrideWithValue(secure),
            kvRepositoryProvider.overrideWithValue(kv),
            llmClientProvider.overrideWithValue(llm),
          ],
          child: const SpeechMirrorOverlayApp(),
        );
      });
      debugPrint('overlayMain init cost=${sw.elapsedMilliseconds}ms');
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(child: Text('浮窗初始化失败：$_error', textAlign: TextAlign.center)),
        ),
      );
    }
    if (_app == null) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return _app!;
  }

  void _installPanelChannel() {
    _panelChannel.setMethodCallHandler((call) async {
      if (call.method != 'startCompactConvert') return null;
      final text = (call.arguments as Map?)?['text']?.toString().trim() ?? '';
      if (text.isEmpty) {
        return {'ok': false, 'error': '输入为空'};
      }
      final llm = _llm;
      final kv = _kv;
      if (llm == null || kv == null) {
        return {'ok': false, 'error': '转换服务未就绪'};
      }
      final model = await _secure?.readModel();
      final m = (model == null || model.isEmpty) ? 'gpt-4o-mini' : model;
      final outputCount = await kv.get('rewrite_output_count') == '1' ? 1 : 3;
      final mode = await _resolvePreferredMode(kv);
      if (mode == null) return {'ok': false, 'error': '暂无可用模式'};
      final parsedInput = RewriteInputParser.parse(text);
      if (parsedInput.originalText.isEmpty) {
        return {'ok': false, 'error': '输入为空'};
      }
      if (outputCount == 1) {
        final system = PromptBuilder.systemForRewritePlainText(
          mode: mode,
          scenarioHint: ScenarioPack.byKey('none')?.hint,
          lengthChannel: '短消息',
          userHint: parsedInput.userHint,
        );
        final user = PromptBuilder.userForRewrite(parsedInput.originalText);
        await for (final ev in llm.rewritePlainTextStream(
              model: m,
              system: system,
              user: user,
            )) {
          switch (ev) {
            case RewriteStreamCompleted(:final plainText):
              final resultText = plainText?.trim();
              if (resultText == null || resultText.isEmpty) {
                return {'ok': false, 'error': '模型未返回可用结果'};
              }
              return {
                'ok': true,
                'variants': [
                  {'label': '结果', 'text': resultText},
                ],
              };
            case RewriteStreamFailed(:final message):
              return {'ok': false, 'error': message};
            case RewriteStreamPartial():
              break;
          }
        }
      } else {
        final system = PromptBuilder.systemForRewriteJson(
          mode: mode,
          scenarioHint: ScenarioPack.byKey('none')?.hint,
          lengthChannel: '短消息',
          userHint: parsedInput.userHint,
        );
        final user = PromptBuilder.userForRewrite(parsedInput.originalText);
        await for (final ev in llm.rewriteStream(
              model: m,
              system: system,
              user: user,
            )) {
          switch (ev) {
            case RewriteStreamCompleted(:final result):
              if (result == null) {
                return {'ok': false, 'error': '模型未返回可用结果'};
              }
              return {
                'ok': true,
                'variants': result.variants
                    .take(3)
                    .map((v) => {'label': v.label, 'text': v.text})
                    .toList(),
              };
            case RewriteStreamFailed(:final message):
              return {'ok': false, 'error': message};
            case RewriteStreamPartial():
              break;
          }
        }
      }
      return {'ok': false, 'error': '模型未返回结果'};
    });
  }

  Future<ModeEntity?> _resolvePreferredMode(KvRepository kv) async {
    if (_modes.isEmpty) return null;
    final selectedRaw = await kv.get(_kSelectedModeId);
    final selectedId = int.tryParse(selectedRaw ?? '');
    if (selectedId != null) {
      for (final m in _modes) {
        if (m.id == selectedId) return m;
      }
    }
    final recentRaw = await kv.get(_kRecent);
    if (recentRaw != null && recentRaw.isNotEmpty) {
      try {
        final recent = (jsonDecode(recentRaw) as List<dynamic>).map((e) => e as int).toList();
        for (final id in recent) {
          for (final m in _modes) {
            if (m.id == id) return m;
          }
        }
      } catch (_) {}
    }
    return _modes.first;
  }
}

class SpeechMirrorOverlayApp extends StatelessWidget {
  const SpeechMirrorOverlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '语镜',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2B4C7E)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2B4C7E),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const OverlayPanelScreen(),
    );
  }
}

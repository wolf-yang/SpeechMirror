import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/llm/llm_error_mapper.dart';
import '../core/llm/rewrite_result.dart';
import '../core/llm/rewrite_stream_event.dart';
import '../core/prompt/prompt_builder.dart';
import '../core/prompt/rewrite_input_parser.dart';
import '../core/scenarios.dart';
import '../data/models/mode_entity.dart';
import '../platform/overlay_bridge.dart';
import '../platform/overlay_panel_bridge.dart';
import '../platform/paste_fallback.dart';
import '../providers/app_providers.dart';

/// 悬浮窗内话术改写（对齐 PRD §3.1.2 主流程）。
class OverlayPanelScreen extends ConsumerStatefulWidget {
  const OverlayPanelScreen({super.key});

  @override
  ConsumerState<OverlayPanelScreen> createState() => _OverlayPanelScreenState();
}

class _OverlayPanelScreenState extends ConsumerState<OverlayPanelScreen> {
  final _input = TextEditingController();
  ModeEntity? _selected;
  List<ModeEntity> _allModes = [];
  List<int> _recentIds = [];
  String _scenarioKey = 'none';
  String _lengthChannel = '短消息';
  int _outputCount = 3;
  LlmRewriteResult? _result;
  String? _singleResultText;
  String? _error;
  bool _loading = false;
  String? _streamPreview;
  bool _collectEnabled = false;
  double _outerKeyboardLogicalPx = 0;
  Timer? _keyboardPoll;

  static const _kRecent = 'recent_mode_ids';
  static const _kCollect = 'collect_dialog_enabled';
  static const _kOutputCount = 'rewrite_output_count';
  static const _kSelectedModeId = 'selected_mode_id';

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
    Future.microtask(_consumePendingTopInput);
    _keyboardPoll = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      final v = await OverlayBridge.getOuterKeyboardInsetPx();
      if (!mounted) return;
      if ((v - _outerKeyboardLogicalPx).abs() > 0.5) {
        setState(() => _outerKeyboardLogicalPx = v);
      }
    });
  }

  Future<void> _consumePendingTopInput() async {
    final data = await OverlayPanelBridge.consumeOverlayLaunchPayload();
    if (!mounted || data == null) return;
    if ((data['mode']?.toString() ?? 'full') != 'full') return;
    final text = (data['text']?.toString() ?? '').trim();
    final autoConvert = data['autoConvert'] == true;
    if (text.isEmpty) return;
    setState(() {
      _input.text = text;
    });
    if (autoConvert) {
      await _convert();
    }
  }

  Future<void> _load() async {
    final modes = await ref.read(modeRepositoryProvider).listByType(null);
    final kv = ref.read(kvRepositoryProvider);
    final raw = await kv.get(_kRecent);
    final collectRaw = await kv.get(_kCollect);
    final outputRaw = await kv.get(_kOutputCount);
    final selectedModeRaw = await kv.get(_kSelectedModeId);
    List<int> recent = [];
    if (raw != null && raw.isNotEmpty) {
      try {
        recent = (jsonDecode(raw) as List<dynamic>).map((e) => e as int).toList();
      } catch (_) {}
    }
    ModeEntity? sel;
    final selectedModeId = int.tryParse(selectedModeRaw ?? '');
    if (selectedModeId != null) {
      for (final m in modes) {
        if (m.id == selectedModeId) {
          sel = m;
          break;
        }
      }
    }
    if (sel == null && recent.isNotEmpty) {
      for (final id in recent) {
        for (final m in modes) {
          if (m.id == id) {
            sel = m;
            break;
          }
        }
        if (sel != null) break;
      }
    }
    sel ??= modes.isNotEmpty ? modes.first : null;
    if (!mounted) return;
    setState(() {
      _allModes = modes;
      _recentIds = recent;
      _selected = sel;
      _collectEnabled = collectRaw == '1';
      _outputCount = outputRaw == '1' ? 1 : 3;
    });
  }

  Future<void> _collectContext() async {
    final r = await OverlayBridge.collectDialogContext(maxChars: 4000);
    if (!mounted) return;
    final ok = r?['ok'] == true;
    final text = r?['text']?.toString().trim() ?? '';
    if (!ok || text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r?['error']?.toString() ?? '采集失败（需无障碍与开关）')),
      );
      return;
    }
    setState(() {
      if (_input.text.trim().isNotEmpty) {
        _input.text = '${_input.text.trim()}\n\n$text';
      } else {
        _input.text = text;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已合并到输入框')),
    );
  }

  Future<void> _persistRecent(int modeId) async {
    final next = <int>[modeId, ..._recentIds.where((e) => e != modeId)].take(3).toList();
    _recentIds = next;
    final kv = ref.read(kvRepositoryProvider);
    await kv.set(_kRecent, jsonEncode(next));
    await kv.set(_kSelectedModeId, modeId.toString());
  }

  Future<void> _convert() async {
    final mode = _selected;
    if (mode == null) {
      setState(() => _error = '请先选择模式');
      return;
    }
    final text = _input.text.trim();
    if (text.isEmpty) {
      setState(() => _error = '请输入内容');
      return;
    }
    final key = await ref.read(secureCredentialStoreProvider).readApiKey();
    if (key == null || key.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先在主应用「我的 → API 与模型」配置 Key')),
        );
      }
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
      _singleResultText = null;
      _streamPreview = null;
    });

    try {
      final model = await ref.read(secureCredentialStoreProvider).readModel();
      final m = (model == null || model.isEmpty) ? 'gpt-4o-mini' : model;
      final parsedInput = RewriteInputParser.parse(text);
      if (parsedInput.originalText.isEmpty) {
        setState(() {
          _error = '请输入内容';
          _loading = false;
        });
        return;
      }
      final scenario = ScenarioPack.byKey(_scenarioKey);
      if (_outputCount == 1) {
        final system = PromptBuilder.systemForRewritePlainText(
          mode: mode,
          scenarioHint: scenario?.hint,
          lengthChannel: _lengthChannel,
          userHint: parsedInput.userHint,
        );
        final user = PromptBuilder.userForRewrite(parsedInput.originalText);
        await for (final ev in ref.read(llmClientProvider).rewritePlainTextStream(
              model: m,
              system: system,
              user: user,
            )) {
          if (!mounted) return;
          switch (ev) {
            case RewriteStreamPartial(:final answerAccumulated):
              setState(() => _streamPreview = answerAccumulated);
            case RewriteStreamCompleted(:final plainText):
              final textResult = plainText?.trim();
              if (textResult == null || textResult.isEmpty) {
                setState(() {
                  _error = '模型未返回可用结果';
                  _loading = false;
                });
                return;
              }
              setState(() {
                _singleResultText = textResult;
                _streamPreview = null;
                _loading = false;
              });
              try {
                await ref.read(historyRepositoryProvider).insert(
                      modeId: mode.id,
                      modeNameSnapshot: mode.name,
                      originalText: parsedInput.originalText,
                      variants: [RewriteVariant(label: '结果', text: textResult)],
                      scenarioKey: _scenarioKey == 'none' ? null : _scenarioKey,
                      lengthChannel: _lengthChannel,
                    );
                await _persistRecent(mode.id);
              } catch (_) {}
              return;
            case RewriteStreamFailed(:final message):
              setState(() {
                _error = message;
                _streamPreview = null;
                _loading = false;
              });
              return;
          }
        }
      } else {
        final system = PromptBuilder.systemForRewriteJson(
          mode: mode,
          scenarioHint: scenario?.hint,
          lengthChannel: _lengthChannel,
          userHint: parsedInput.userHint,
        );
        final user = PromptBuilder.userForRewrite(parsedInput.originalText);
        await for (final ev in ref.read(llmClientProvider).rewriteStream(
              model: m,
              system: system,
              user: user,
            )) {
          if (!mounted) return;
          switch (ev) {
            case RewriteStreamCompleted(:final result):
              if (result == null) {
                setState(() {
                  _error = '模型未返回可用结果';
                  _loading = false;
                });
                return;
              }
              setState(() {
                _result = result;
                _loading = false;
              });
              try {
                await ref.read(historyRepositoryProvider).insert(
                      modeId: mode.id,
                      modeNameSnapshot: mode.name,
                      originalText: parsedInput.originalText,
                      variants: result.variants,
                      scenarioKey: _scenarioKey == 'none' ? null : _scenarioKey,
                      lengthChannel: _lengthChannel,
                    );
                await _persistRecent(mode.id);
              } catch (_) {}
              return;
            case RewriteStreamFailed(:final message):
              setState(() {
                _error = message;
                _loading = false;
              });
              return;
            case RewriteStreamPartial():
              break;
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = mapLlmUserMessage(e);
        _loading = false;
        _streamPreview = null;
      });
    }
  }

  ModeEntity? _validSelected() {
    final s = _selected;
    if (s == null) return _allModes.isNotEmpty ? _allModes.first : null;
    for (final m in _allModes) {
      if (m.id == s.id) return m;
    }
    return _allModes.isNotEmpty ? _allModes.first : null;
  }

  /// 无障碍上报键盘高度偶发偏大；做上限保护，避免界面被挤没。
  double _clampedBottomInset(BuildContext context) {
    final mq = MediaQuery.of(context);
    final h = mq.size.height;
    final combined = math.max(mq.viewInsets.bottom, _outerKeyboardLogicalPx);
    if (h <= 1) return combined.clamp(0.0, 800.0);
    final minContent = math.max(220.0, h * 0.34);
    final maxPad = (h - minContent).clamp(0.0, h);
    return combined.clamp(0.0, maxPad);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = _clampedBottomInset(context);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('语镜 · 浮窗'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => OverlayPanelBridge.closePanel(),
        ),
        actions: [
          IconButton(
            tooltip: '打开主应用',
            onPressed: () => OverlayPanelBridge.openMainApp(),
            icon: const Icon(Icons.open_in_new),
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + bottomInset),
        child: _allModes.isEmpty
            ? const Center(child: Text('暂无模式'))
            : ListView(
                children: [
                  InputDecorator(
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: '模式',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<ModeEntity>(
                        isExpanded: true,
                        value: _validSelected(),
                        items: _allModes
                            .map(
                              (m) => DropdownMenuItem(
                                value: m,
                                child: Text('${m.name}（${m.typeString}）', overflow: TextOverflow.ellipsis),
                              ),
                            )
                            .toList(),
                        onChanged: (v) async {
                          setState(() => _selected = v);
                          final id = v?.id;
                          if (id != null) {
                            await ref.read(kvRepositoryProvider).set(_kSelectedModeId, id.toString());
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  InputDecorator(
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: '场景包',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _scenarioKey,
                        items: ScenarioPack.all.map((s) => DropdownMenuItem(value: s.key, child: Text(s.label))).toList(),
                        onChanged: (v) => setState(() => _scenarioKey = v ?? 'none'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  InputDecorator(
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: '长度 / 渠道',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _lengthChannel,
                        items: const [
                          DropdownMenuItem(value: '短消息', child: Text('短消息（IM）')),
                          DropdownMenuItem(value: '一段话', child: Text('一段话')),
                          DropdownMenuItem(value: '邮件体例', child: Text('邮件体例')),
                        ],
                        onChanged: (v) => setState(() => _lengthChannel = v ?? '短消息'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  InputDecorator(
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: '输出条数',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        isExpanded: true,
                        value: _outputCount,
                        items: const [
                          DropdownMenuItem(value: 3, child: Text('三条结果（非流式）')),
                          DropdownMenuItem(value: 1, child: Text('单条结果（流式）')),
                        ],
                        onChanged: (v) async {
                          final next = v ?? 3;
                          await ref.read(kvRepositoryProvider).set(_kOutputCount, next.toString());
                          if (!mounted) return;
                          setState(() => _outputCount = next);
                        },
                      ),
                    ),
                  ),
                  TextField(
                    controller: _input,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: '输入原话',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  if (_collectEnabled) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _collectContext,
                      icon: const Icon(Icons.plagiarism_outlined, size: 18),
                      label: const Text('采集当前界面文本到输入框'),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton(
                        onPressed: _loading ? null : _convert,
                        child: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('转换'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => setState(() {
                          _input.clear();
                          _result = null;
                          _singleResultText = null;
                          _error = null;
                          _streamPreview = null;
                        }),
                        child: const Text('清空'),
                      ),
                    ],
                  ),
                  if (_loading) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text('回答中', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13)),
                  ],
                  if (_singleResultText != null && _singleResultText!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _singleResultCard(_singleResultText!),
                  ],
                  if ((_streamPreview?.isNotEmpty ?? false) && (_singleResultText == null || _singleResultText!.isEmpty)) ...[
                    const SizedBox(height: 8),
                    _singleResultCard(_streamPreview!),
                  ],
                  if (_result != null) ...[
                    const SizedBox(height: 12),
                    Text('说明：${_result!.rationale}', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 8),
                    ..._result!.variants.map(_variantCard),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _variantCard(RewriteVariant v) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(v.label, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            SelectableText(v.text, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => pasteToFocusedWithCopyFallback(context, v.text),
                  child: const Text('填充'),
                ),
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: v.text));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制')));
                    }
                  },
                  child: const Text('复制'),
                ),
                TextButton(
                  onPressed: () async {
                    final r = await OverlayBridge.clickSend();
                    if (!mounted) return;
                    final ok = r?['ok'] == true;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(ok ? '已尝试点击发送' : (r?['error']?.toString() ?? '发送失败'))),
                    );
                  },
                  child: const Text('发送'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _singleResultCard(String text) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('结果', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            SelectableText(text, style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _keyboardPoll?.cancel();
    _input.dispose();
    super.dispose();
  }
}

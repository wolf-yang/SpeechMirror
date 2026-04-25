import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/llm/llm_error_mapper.dart';
import '../../core/llm/rewrite_result.dart';
import '../../core/llm/rewrite_stream_event.dart';
import '../../core/prompt/prompt_builder.dart';
import '../../core/prompt/rewrite_input_parser.dart';
import '../../core/scenarios.dart';
import '../../data/models/mode_entity.dart';
import '../../platform/overlay_bridge.dart';
import '../../platform/paste_fallback.dart';
import '../../providers/app_providers.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
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

  static const _kRecent = 'recent_mode_ids';
  static const _kOutputCount = 'rewrite_output_count';
  static const _kSelectedModeId = 'selected_mode_id';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final modes = await ref.read(modeRepositoryProvider).listByType(null);
    final kv = ref.read(kvRepositoryProvider);
    final raw = await kv.get(_kRecent);
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
      _outputCount = outputRaw == '1' ? 1 : 3;
    });
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
          const SnackBar(content: Text('请先在「我的 → API 与模型」配置 Key')),
        );
        context.push('/settings/llm');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('语镜 · 快速试一句'),
        actions: [
          IconButton(
            tooltip: 'API 与模型',
            onPressed: () => context.push('/settings/llm'),
            icon: const Icon(Icons.key_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _modeSection(),
          const SizedBox(height: 12),
          _scenarioSection(),
          const SizedBox(height: 12),
          _lengthAndOutput(),
          const SizedBox(height: 12),
          TextField(
            controller: _input,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: '把你的话写在这里',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
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
              const SizedBox(width: 12),
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
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (_singleResultText != null && _singleResultText!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _singleResultCard(_singleResultText!),
          ],
          if ((_streamPreview?.isNotEmpty ?? false) && (_singleResultText == null || _singleResultText!.isEmpty)) ...[
            const SizedBox(height: 16),
            _singleResultCard(_streamPreview!),
          ],
          if (_result != null) ...[
            const SizedBox(height: 16),
            Text('改写说明：${_result!.rationale}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            ..._result!.variants.map((v) => _variantCard(v)),
          ],
        ],
      ),
    );
  }

  Widget _modeSection() {
    if (_allModes.isEmpty) {
      return const Text('暂无可用模式，请稍后重试或清空数据后重启应用。');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<ModeEntity>(
          value: _validSelected(),
          decoration: const InputDecoration(border: OutlineInputBorder(), labelText: '全部模式'),
          items: _allModes
              .map(
                (m) => DropdownMenuItem(
                  value: m,
                  child: Text('${m.name}（${m.typeString}）'),
                ),
              )
              .toList(),
          onChanged: (m) async {
            setState(() => _selected = m);
            final id = m?.id;
            if (id != null) {
              await ref.read(kvRepositoryProvider).set(_kSelectedModeId, id.toString());
            }
          },
        ),
      ],
    );
  }

  Widget _scenarioSection() {
    return DropdownButtonFormField<String>(
      value: _scenarioKey,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        labelText: '场景包',
      ),
      items: ScenarioPack.all.map((s) => DropdownMenuItem(value: s.key, child: Text(s.label))).toList(),
      onChanged: (v) => setState(() => _scenarioKey = v ?? 'none'),
    );
  }

  Widget _lengthAndOutput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: _lengthChannel,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: '长度 / 渠道',
          ),
          items: const [
            DropdownMenuItem(value: '短消息', child: Text('短消息（IM）')),
            DropdownMenuItem(value: '一段话', child: Text('一段话')),
            DropdownMenuItem(value: '邮件体例', child: Text('邮件体例')),
          ],
          onChanged: (v) => setState(() => _lengthChannel = v ?? '短消息'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          value: _outputCount,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: '输出条数',
          ),
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
      ],
    );
  }

  Widget _singleResultCard(String text) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('结果', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            SelectableText(text),
          ],
        ),
      ),
    );
  }

  Widget _variantCard(RewriteVariant v) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(v.label, style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
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
                  onPressed: () => pasteToFocusedWithCopyFallback(context, v.text),
                  child: const Text('填充'),
                ),
                TextButton(
                  onPressed: () async {
                    final r = await OverlayBridge.clickSend();
                    if (!mounted) return;
                    final ok = r?['ok'] == true;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(ok ? '已尝试点击发送' : (r?['error']?.toString() ?? '发送需要映射表与无障碍'))),
                    );
                  },
                  child: const Text('发送'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SelectableText(v.text),
          ],
        ),
      ),
    );
  }

  ModeEntity? _validSelected() {
    if (_selected == null) return _allModes.isNotEmpty ? _allModes.first : null;
    for (final m in _allModes) {
      if (m.id == _selected!.id) return m;
    }
    return _allModes.isNotEmpty ? _allModes.first : null;
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }
}

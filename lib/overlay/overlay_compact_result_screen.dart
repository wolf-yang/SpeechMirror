import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/llm/llm_error_mapper.dart';
import '../core/llm/rewrite_result.dart';
import '../core/llm/rewrite_stream_event.dart';
import '../core/prompt/prompt_builder.dart';
import '../core/scenarios.dart';
import '../data/models/mode_entity.dart';
import '../platform/overlay_panel_bridge.dart';
import '../providers/app_providers.dart';

class OverlayCompactResultScreen extends ConsumerStatefulWidget {
  const OverlayCompactResultScreen({
    super.key,
    required this.initialText,
    required this.autoConvert,
  });

  final String initialText;
  final bool autoConvert;

  @override
  ConsumerState<OverlayCompactResultScreen> createState() => _OverlayCompactResultScreenState();
}

class _OverlayCompactResultScreenState extends ConsumerState<OverlayCompactResultScreen> {
  LlmRewriteResult? _result;
  String? _error;
  bool _loading = false;
  ModeEntity? _mode;

  @override
  void initState() {
    super.initState();
    Future.microtask(_boot);
  }

  Future<void> _boot() async {
    final modes = await ref.read(modeRepositoryProvider).listByType(null);
    if (!mounted) return;
    setState(() {
      _mode = modes.isNotEmpty ? modes.first : null;
    });
    if (widget.autoConvert && widget.initialText.trim().isNotEmpty) {
      await _convert(widget.initialText.trim());
    }
  }

  Future<void> _convert(String text) async {
    final mode = _mode;
    if (mode == null) {
      setState(() => _error = '暂无模式');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final model = await ref.read(secureCredentialStoreProvider).readModel();
      final m = (model == null || model.isEmpty) ? 'gpt-4o-mini' : model;
      final system = PromptBuilder.systemForRewriteJson(
        mode: mode,
        scenarioHint: ScenarioPack.byKey('none')?.hint,
        lengthChannel: '短消息',
      );
      final user = PromptBuilder.userForRewrite(text);
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = mapLlmUserMessage(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [BoxShadow(blurRadius: 10, color: Color(0x22000000))],
          ),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Row(
                      children: [
                        Expanded(child: Text(_error!, maxLines: 2, overflow: TextOverflow.ellipsis)),
                        IconButton(
                          tooltip: '关闭',
                          onPressed: OverlayPanelBridge.closePanel,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    )
                  : _result == null
                      ? const Text('暂无结果')
                      : ListView(
                          shrinkWrap: true,
                          children: _result!.variants.take(3).map((v) {
                            return Card(
                              margin: const EdgeInsets.only(bottom: 6),
                              child: ListTile(
                                dense: true,
                                title: Text(v.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text(v.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                                trailing: IconButton(
                                  tooltip: '复制',
                                  onPressed: () => Clipboard.setData(ClipboardData(text: v.text)),
                                  icon: const Icon(Icons.copy, size: 18),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
        ),
      ),
    );
  }
}

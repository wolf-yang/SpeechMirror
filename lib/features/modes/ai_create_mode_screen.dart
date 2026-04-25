import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/llm/llm_client.dart';
import '../../providers/app_providers.dart';

class AiCreateModeScreen extends ConsumerStatefulWidget {
  const AiCreateModeScreen({super.key});

  @override
  ConsumerState<AiCreateModeScreen> createState() => _AiCreateModeScreenState();
}

class _AiCreateModeScreenState extends ConsumerState<AiCreateModeScreen> {
  final _name = TextEditingController();
  final _hint = TextEditingController();
  final _style = TextEditingController();
  final _pos = TextEditingController();
  final _neg = TextEditingController();
  bool _loading = false;

  Future<void> _gen() async {
    final name = _name.text.trim();
    final hint = _hint.text.trim();
    if (name.isEmpty || hint.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写模式名称与一句话风格描述')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final map = await ref.read(llmClientProvider).generateModeDraftJson(
            modeName: name,
            oneLineStyle: hint,
          );
      final style = map['style_description']?.toString() ?? '';
      final pos = map['positive_examples'];
      final neg = map['negative_examples'];
      _style.text = style;
      _pos.text = pos is List ? jsonEncode(pos) : (pos?.toString() ?? '');
      _neg.text = neg is List ? jsonEncode(neg) : (neg?.toString() ?? '');
    } on LlmException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final desc = _hint.text.trim();
    final style = _style.text.trim();
    if (name.isEmpty || desc.isEmpty || style.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先生成并确认风格描述')),
      );
      return;
    }
    final pos = _pos.text.trim();
    final neg = _neg.text.trim();
    await ref.read(modeRepositoryProvider).insertCustom(
          name: name,
          description: desc,
          stylePrompt: style,
          examplesJson: pos.isEmpty ? null : pos,
          negativeExamplesJson: neg.isEmpty ? null : neg,
        );
    bumpModesRefresh(ref);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存为自定义模式')));
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 辅助创建模式')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: '模式名称')),
          const SizedBox(height: 12),
          TextField(controller: _hint, decoration: const InputDecoration(labelText: '一句话风格描述')),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: _loading ? null : _gen,
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('生成草稿'),
          ),
          const Divider(height: 32),
          TextField(
            controller: _style,
            minLines: 4,
            maxLines: 12,
            decoration: const InputDecoration(
              labelText: '详细风格描述（可编辑）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pos,
            minLines: 3,
            maxLines: 10,
            decoration: const InputDecoration(
              labelText: '正面示例（JSON 或文本，可编辑）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _neg,
            minLines: 2,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: '负面示例（可编辑）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('确认保存')),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _hint.dispose();
    _style.dispose();
    _pos.dispose();
    _neg.dispose();
    super.dispose();
  }
}

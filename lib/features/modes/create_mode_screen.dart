import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/mode_entity.dart';
import '../../providers/app_providers.dart';

class CreateModeScreen extends ConsumerStatefulWidget {
  const CreateModeScreen({super.key, this.initial});

  final ModeEntity? initial;

  @override
  ConsumerState<CreateModeScreen> createState() => _CreateModeScreenState();
}

class _CreateModeScreenState extends ConsumerState<CreateModeScreen> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _style = TextEditingController();
  final _pos = TextEditingController();
  final _neg = TextEditingController();

  @override
  void initState() {
    super.initState();
    final m = widget.initial;
    if (m != null) {
      _name.text = m.name;
      _desc.text = m.description;
      _style.text = m.stylePrompt;
      _pos.text = m.examplesJson ?? '';
      _neg.text = m.negativeExamplesJson ?? '';
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final desc = _desc.text.trim();
    final style = _style.text.trim();
    if (name.isEmpty || desc.isEmpty || style.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('名称、简述、风格描述为必填')),
      );
      return;
    }
    final pos = _pos.text.trim();
    final neg = _neg.text.trim();
    final repo = ref.read(modeRepositoryProvider);
    final m = widget.initial;
    if (m == null) {
      await repo.insertCustom(
        name: name,
        description: desc,
        stylePrompt: style,
        examplesJson: pos.isEmpty ? null : pos,
        negativeExamplesJson: neg.isEmpty ? null : neg,
      );
    } else {
      await repo.updateCustom(
        m.id,
        name: name,
        description: desc,
        stylePrompt: style,
        examplesJson: pos.isEmpty ? null : pos,
        negativeExamplesJson: neg.isEmpty ? null : neg,
      );
    }
    bumpModesRefresh(ref);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存')));
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? '编辑模式' : '手动创建模式')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: '模式名称（必填）')),
          const SizedBox(height: 12),
          TextField(controller: _desc, decoration: const InputDecoration(labelText: '简述（必填）')),
          const SizedBox(height: 12),
          TextField(
            controller: _style,
            minLines: 4,
            maxLines: 12,
            decoration: const InputDecoration(
              labelText: '风格描述（必填）',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pos,
            minLines: 3,
            maxLines: 10,
            decoration: const InputDecoration(
              labelText: '正面示例（可选，纯文本或 JSON）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _neg,
            minLines: 2,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: '负面示例（可选）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _style.dispose();
    _pos.dispose();
    _neg.dispose();
    super.dispose();
  }
}

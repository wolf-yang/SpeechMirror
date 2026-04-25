import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/llm/llm_client.dart';
import '../../providers/app_providers.dart';

class DistillScreen extends ConsumerStatefulWidget {
  const DistillScreen({super.key});

  @override
  ConsumerState<DistillScreen> createState() => _DistillScreenState();
}

class _DistillScreenState extends ConsumerState<DistillScreen> {
  int _step = 0;
  final _raw = TextEditingController();
  Map<String, dynamic>? _analysis;
  bool _busy = false;

  Future<void> _pickFile() async {
    final r = await FilePicker.platform.pickFiles(withData: true);
    if (r == null || r.files.isEmpty) return;
    final f = r.files.single;
    final bytes = f.bytes;
    if (bytes == null) return;
    final text = utf8.decode(bytes, allowMalformed: true);
    setState(() => _raw.text = text);
  }

  Future<String> _runStubParser(String input) async {
    try {
      final script = await rootBundle.loadString('assets/tools/parse_stub.py');
      final dir = await getTemporaryDirectory();
      final scriptFile = File('${dir.path}/parse_stub.py');
      await scriptFile.writeAsString(script);
      final inputFile = File('${dir.path}/distill_input.txt');
      await inputFile.writeAsString(input);
      final pr = await Process.run(
        'python3',
        [scriptFile.path, inputFile.path],
        workingDirectory: dir.path,
      );
      if (pr.exitCode == 0) {
        final out = pr.stdout.toString().trim();
        if (out.isNotEmpty) return out;
      }
    } catch (_) {}
    return input;
  }

  Future<void> _analyze() async {
    if (_raw.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先粘贴或导入文本')));
      return;
    }
    setState(() => _busy = true);
    try {
      final parsed = await _runStubParser(_raw.text);
      final map = await ref.read(llmClientProvider).distillPersona(parsed);
      setState(() {
        _analysis = map;
        _step = 2;
      });
    } on LlmException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _fallbackPersonaListName(Map<String, dynamic> a) {
    String clip(String s) {
      var t = s.split('\n').first.trim();
      if (t.length > 16) t = t.substring(0, 16);
      return t;
    }

    final sl = a['style_label'];
    if (sl is String && sl.trim().isNotEmpty) {
      final head = sl.split('/').first.trim();
      if (head.isNotEmpty) return '人物·${clip(head)}';
    }
    final p = a['persona'];
    if (p is Map) {
      final id = p['identity'];
      if (id is String && id.trim().isNotEmpty) {
        return '人物·${clip(id)}';
      }
    }
    return '人物·蒸馏模式';
  }

  Future<void> _savePersona() async {
    final a = _analysis;
    if (a == null) return;
    setState(() => _busy = true);
    String name;
    try {
      name = await ref.read(llmClientProvider).suggestPersonaListName(a);
    } on LlmException catch (_) {
      name = _fallbackPersonaListName(a);
    } catch (_) {
      name = _fallbackPersonaListName(a);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    final desc = (a['persona'] is Map && (a['persona'] as Map)['identity'] != null)
        ? (a['persona'] as Map)['identity'].toString()
        : '由蒸馏工坊生成';
    final style = const JsonEncoder.withIndent('  ').convert(a);
    final memory = a['memory'];
    await ref.read(modeRepositoryProvider).insertPersona(
          name: name,
          description: desc,
          stylePrompt: style,
          memoryJson: memory == null ? null : jsonEncode(memory),
        );
    bumpModesRefresh(ref);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已保存到模式库（人物）：$name')));
      setState(() => _step = 3);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('风格蒸馏工坊')),
      body: Stepper(
        currentStep: _step,
        onStepContinue: () {},
        controlsBuilder: (context, details) => const SizedBox.shrink(),
        steps: [
          Step(
            title: const Text('导入数据'),
            subtitle: const Text('手动粘贴或选择文本文件（占位解析可在桌面端用 Python 强化）'),
            isActive: _step >= 0,
            state: _step > 0 ? StepState.complete : StepState.indexed,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _raw,
                  minLines: 6,
                  maxLines: 16,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '对方发言 / 聊天记录文本',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('选择文本文件'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          try {
                            final parsed = await _runStubParser(_raw.text);
                            if (!mounted) return;
                            setState(() {
                              _raw.text = parsed;
                              _step = 1;
                            });
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                  child: const Text('下一步（轻量解析）'),
                ),
              ],
            ),
          ),
          Step(
            title: const Text('分析风格'),
            subtitle: const Text('调用大模型生成人格与记忆草稿'),
            isActive: _step >= 1,
            state: _step > 1 ? StepState.complete : StepState.indexed,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.tonal(
                  onPressed: _busy ? null : _analyze,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('开始分析'),
                ),
              ],
            ),
          ),
          Step(
            title: const Text('生成模式'),
            isActive: _step >= 2,
            state: _step > 2 ? StepState.complete : StepState.indexed,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_analysis != null)
                  SelectableText(const JsonEncoder.withIndent('  ').convert(_analysis)),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: (_analysis == null || _busy) ? null : _savePersona,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('保存为人物模式'),
                ),
              ],
            ),
          ),
          Step(
            title: const Text('完成'),
            isActive: _step >= 3,
            state: _step >= 3 ? StepState.complete : StepState.indexed,
            content: const Text('可在「模式库 → 人物」中查看并用于首页转换。'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _raw.dispose();
    super.dispose();
  }
}

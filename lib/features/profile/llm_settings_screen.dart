import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/llm_client.dart';
import '../../providers/app_providers.dart';

class LlmSettingsScreen extends ConsumerStatefulWidget {
  const LlmSettingsScreen({super.key});

  @override
  ConsumerState<LlmSettingsScreen> createState() => _LlmSettingsScreenState();
}

class _LlmSettingsScreenState extends ConsumerState<LlmSettingsScreen> {
  final _base = TextEditingController();
  final _model = TextEditingController();
  final _key = TextEditingController();
  bool _mask = true;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = ref.read(secureCredentialStoreProvider);
    final b = await s.readBaseUrl();
    final m = await s.readModel();
    final k = await s.readApiKey();
    setState(() {
      _base.text = b ?? '';
      _model.text = m ?? '';
      _key.text = k ?? '';
    });
  }

  Future<void> _save() async {
    final s = ref.read(secureCredentialStoreProvider);
    await s.writeBaseUrl(_base.text.trim());
    await s.writeModel(_model.text.trim());
    await s.writeApiKey(_key.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存')));
    }
  }

  Future<void> _ping() async {
    setState(() => _testing = true);
    try {
      await ref.read(llmClientProvider).ping();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('连通性正常')));
      }
    } on LlmException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('API 与模型')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _base,
            decoration: const InputDecoration(
              labelText: 'Base URL（如 https://api.openai.com/v1）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _model,
            decoration: const InputDecoration(
              labelText: 'Model（如 gpt-4o-mini）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _key,
            obscureText: _mask,
            decoration: InputDecoration(
              labelText: 'API Key',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _mask = !_mask),
                icon: Icon(_mask ? Icons.visibility : Icons.visibility_off),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton(onPressed: _save, child: const Text('保存')),
              const SizedBox(width: 12),
              FilledButton.tonal(
                onPressed: _testing ? null : _ping,
                child: _testing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('试调用'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _base.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }
}

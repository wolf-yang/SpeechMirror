import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/mode_entity.dart';
import '../../providers/app_providers.dart';

class ModeDetailScreen extends ConsumerWidget {
  const ModeDetailScreen({super.key, required this.modeId});

  final int modeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<ModeEntity?>(
      future: ref.read(modeRepositoryProvider).getById(modeId),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final m = snap.data;
        if (m == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('模式详情')),
            body: const Center(child: Text('未找到该模式')),
          );
        }
        final canDelete = !m.isBuiltin;
        return Scaffold(
          appBar: AppBar(
            title: Text(m.name),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: '编辑',
                onPressed: () => context.push('/modes/create', extra: m),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('类型：${m.typeString}', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Text(m.description),
              const SizedBox(height: 16),
              Text('风格指令', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SelectableText(m.stylePrompt),
              if (m.examplesJson != null && m.examplesJson!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('示例 / 记忆', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                SelectableText(m.examplesJson!),
              ],
              if (m.negativeExamplesJson != null && m.negativeExamplesJson!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('负面约束', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                SelectableText(m.negativeExamplesJson!),
              ],
              if (canDelete) ...[
                const SizedBox(height: 24),
                FilledButton.tonal(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('删除模式？'),
                        content: const Text('此操作不可恢复。'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
                          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
                        ],
                      ),
                    );
                    if (ok == true && context.mounted) {
                      await ref.read(modeRepositoryProvider).deleteIfEditable(m.id);
                      bumpModesRefresh(ref);
                      if (context.mounted) context.pop();
                    }
                  },
                  child: const Text('删除模式'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

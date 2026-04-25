import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/rewrite_result.dart';
import '../../data/models/history_entity.dart';
import '../../providers/app_providers.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('历史记录')),
      body: FutureBuilder<List<HistoryEntity>>(
        future: ref.read(historyRepositoryProvider).recent(limit: 200),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data!;
          if (list.isEmpty) {
            return const Center(child: Text('暂无历史'));
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final h = list[i];
              List<RewriteVariant> vars = [];
              try {
                final decoded = jsonDecode(h.resultsJson) as List<dynamic>;
                vars = decoded.map((e) => RewriteVariant.fromJson(e as Map<String, dynamic>)).toList();
              } catch (_) {}
              return ExpansionTile(
                title: Text(h.modeNameSnapshot),
                subtitle: Text(
                  h.originalText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(h.originalText),
                        const SizedBox(height: 8),
                        ...vars.map(
                          (v) => ListTile(
                            dense: true,
                            title: Text(v.label),
                            subtitle: SelectableText(v.text),
                            trailing: IconButton(
                              icon: const Icon(Icons.copy),
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: v.text));
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('已复制该条结果')),
                                  );
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

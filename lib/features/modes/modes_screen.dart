import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/mode_entity.dart';
import '../../providers/app_providers.dart';

class ModesScreen extends ConsumerStatefulWidget {
  const ModesScreen({super.key});

  @override
  ConsumerState<ModesScreen> createState() => _ModesScreenState();
}

class _ModesScreenState extends ConsumerState<ModesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  final _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<List<ModeEntity>> _load(ModeType? t) {
    return ref.read(modeRepositoryProvider).listByType(t, query: _q.isEmpty ? null : _q);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(modesRefreshProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('模式库'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: '预设'),
            Tab(text: '自定义'),
            Tab(text: '人物'),
          ],
        ),
      ),
      floatingActionButton: PopupMenuButton<String>(
        icon: const Icon(Icons.add),
        onSelected: (v) {
          if (v == 'manual') context.push('/modes/create');
          if (v == 'ai') context.push('/modes/ai-create');
        },
        itemBuilder: (c) => const [
          PopupMenuItem(value: 'manual', child: Text('手动创建模式')),
          PopupMenuItem(value: 'ai', child: Text('AI 辅助创建')),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: '搜索模式名称',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          setState(() => _q = '');
                        },
                      ),
                    ),
                    onSubmitted: (_) => setState(() => _q = _search.text.trim()),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() => _q = _search.text.trim()),
                  child: const Text('搜索'),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _ModeList(loader: () => _load(ModeType.preset)),
                _ModeList(loader: () => _load(ModeType.custom)),
                _ModeList(loader: () => _load(ModeType.persona)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeList extends ConsumerWidget {
  const _ModeList({required this.loader});

  final Future<List<ModeEntity>> Function() loader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(modesRefreshProvider);
    return FutureBuilder<List<ModeEntity>>(
      future: loader(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snap.data!;
        if (list.isEmpty) {
          return const Center(child: Text('暂无模式'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final m = list[i];
            return Card(
              child: ListTile(
                title: Text(m.name),
                subtitle: Text(m.description, maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/modes/${m.id}'),
              ),
            );
          },
        );
      },
    );
  }
}

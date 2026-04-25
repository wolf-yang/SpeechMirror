import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../platform/overlay_bridge.dart';
import '../../providers/app_providers.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  static const _kOverlay = 'overlay_auto_show';
  static const _kCollect = 'collect_dialog_enabled';

  bool _overlay = false;
  bool _collect = false;
  bool _testingLlm = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final kv = ref.read(kvRepositoryProvider);
    final o = await kv.get(_kOverlay);
    final c = await kv.get(_kCollect);
    if (!mounted) return;
    setState(() {
      _overlay = o == '1';
      _collect = c == '1';
      _loaded = true;
    });
    await OverlayBridge.syncOverlayPrefs(
      overlayAutoShow: o == '1',
      collectDialogEnabled: c == '1',
    );
  }

  Future<void> _setOverlay(bool v) async {
    await ref.read(kvRepositoryProvider).set(_kOverlay, v ? '1' : '0');
    await OverlayBridge.syncOverlayPrefs(overlayAutoShow: v, collectDialogEnabled: _collect);
    if (v) {
      final r = await OverlayBridge.showBubble();
      if (mounted && r != null && r['ok'] != true) {
        final err = r['error']?.toString() ?? '请检查悬浮窗与通知权限，返回应用后会自动重试';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      }
    } else {
      await OverlayBridge.hideBubble();
    }
    setState(() => _overlay = v);
  }

  Future<void> _setCollect(bool v) async {
    await ref.read(kvRepositoryProvider).set(_kCollect, v ? '1' : '0');
    await OverlayBridge.syncOverlayPrefs(overlayAutoShow: _overlay, collectDialogEnabled: v);
    setState(() => _collect = v);
  }

  Future<void> _testLlmApi() async {
    if (_testingLlm) return;
    setState(() => _testingLlm = true);
    try {
      await ref.read(llmClientProvider).ping();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('模型 API 连通成功')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('模型 API 连通失败：$e')),
      );
    } finally {
      if (mounted) {
        setState(() => _testingLlm = false);
      }
    }
  }

  void _showOverlayHelpSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('悬浮窗权限', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              const Text(
                '若总列表里看不到「语镜」，多半是只显示了已允许的应用。可从下方入口进入本应用信息或系统悬浮窗页开启。',
                style: TextStyle(fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () {
                  Navigator.pop(ctx);
                  OverlayBridge.openAppDetailsSettings();
                },
                child: const Text('打开应用信息'),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: () {
                  Navigator.pop(ctx);
                  OverlayBridge.openManageOverlayPermission();
                },
                child: const Text('打开「显示在其他应用上层」'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Card(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('数据与隐私', style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        const Text(
                          '· 数据保存在本机，无语镜云端同步。\n'
                          '· 改写/蒸馏等仅在调用时把内容发到你配置的模型接口。',
                          style: TextStyle(fontSize: 12, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.key),
                  title: const Text('API 与模型'),
                  subtitle: const Text('Base URL / Model / Key'),
                  onTap: () => context.push('/settings/llm'),
                ),
                ListTile(
                  leading: const Icon(Icons.network_check),
                  title: const Text('临时：测试模型 API'),
                  subtitle: const Text('使用当前 Base URL / Model / Key'),
                  trailing: _testingLlm
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  onTap: _testingLlm ? null : _testLlmApi,
                ),
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('历史记录'),
                  onTap: () => context.push('/history'),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.bubble_chart_outlined),
                  title: const Text('启用悬浮球（Android）'),
                  subtitle: const Text('需悬浮窗与通知权限'),
                  value: _overlay,
                  onChanged: _setOverlay,
                ),
                ListTile(
                  leading: const Icon(Icons.help_outline),
                  title: const Text('悬浮窗权限帮助'),
                  subtitle: const Text('找不到「语镜」时点此'),
                  onTap: _showOverlayHelpSheet,
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.downloading_outlined),
                  title: const Text('允许浮窗采集对话'),
                  subtitle: const Text('默认关；需无障碍且手动触发'),
                  value: _collect,
                  onChanged: _setCollect,
                ),
                ListTile(
                  leading: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.error),
                  title: Text('一键清空数据', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  subtitle: const Text('历史、自定义/人物模式、本地设置与 Key'),
                  onTap: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('确认清空？'),
                        content: const Text('将删除历史与非内置模式，并清除已保存的 API Key。'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
                          FilledButton(
                            onPressed: () => Navigator.pop(c, true),
                            child: const Text('清空'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await ref.read(appDatabaseProvider).wipeUserData();
                      await ref.read(secureCredentialStoreProvider).wipeAll();
                      bumpModesRefresh(ref);
                      setState(() {
                        _overlay = false;
                        _collect = false;
                      });
                      await OverlayBridge.syncOverlayPrefs(overlayAutoShow: false, collectDialogEnabled: false);
                      await OverlayBridge.hideBubble();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已清空')));
                      }
                    }
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../platform/overlay_bridge.dart';
import '../../providers/app_providers.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> with WidgetsBindingObserver {
  static const _kOverlay = 'overlay_auto_show';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _restoreOverlayIfNeeded();
    }
  }

  /// 从系统设置授予悬浮窗/通知权限返回、或从桌面回到应用时重试显示悬浮球。
  Future<void> _restoreOverlayIfNeeded() async {
    final kv = ref.read(kvRepositoryProvider);
    final o = await kv.get(_kOverlay);
    if (o == '1') {
      await OverlayBridge.showBubbleIfPermitted();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.navigationShell.currentIndex,
        onDestinationSelected: (i) {
          widget.navigationShell.goBranch(i, initialLocation: i == widget.navigationShell.currentIndex);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: '首页'),
          NavigationDestination(icon: Icon(Icons.library_books_outlined), label: '模式库'),
          NavigationDestination(icon: Icon(Icons.science_outlined), label: '蒸馏工坊'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: '我的'),
        ],
      ),
    );
  }
}

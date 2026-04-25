import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'overlay_bridge.dart';

/// 无障碍粘贴失败时复制到剪贴板并提示（PRD §3.6 降级）。
Future<void> pasteToFocusedWithCopyFallback(BuildContext context, String text) async {
  final r = await OverlayBridge.pasteToFocused(text);
  final ok = r?['ok'] == true;
  if (!context.mounted) return;
  if (ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已尝试粘贴到焦点输入框')),
    );
    return;
  }
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('无法自动粘贴，已复制到剪贴板，请手动粘贴')),
  );
}

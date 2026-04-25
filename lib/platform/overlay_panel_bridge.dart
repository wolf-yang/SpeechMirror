import 'package:flutter/services.dart';

/// 浮窗 isolate 与 OverlayService 之间的 MethodChannel（仅浮窗引擎注册）。
class OverlayPanelBridge {
  static const _channel = MethodChannel('com.speechmirror.app/overlay_panel');

  static Future<void> closePanel() async {
    try {
      await _channel.invokeMethod<void>('closePanel');
    } on MissingPluginException {
      return;
    }
  }

  static Future<void> openMainApp() async {
    try {
      await _channel.invokeMethod<void>('openMainApp');
    } on MissingPluginException {
      return;
    }
  }

  static Future<Map<String, dynamic>?> consumeOverlayLaunchPayload() async {
    try {
      final r = await _channel.invokeMethod<dynamic>('consumeOverlayLaunchPayload');
      if (r is Map) {
        return r.map((k, v) => MapEntry(k.toString(), v));
      }
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

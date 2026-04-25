import 'package:flutter/services.dart';

/// Android 浮窗与无障碍（MethodChannel）；未实现平台时调用安全忽略。
class OverlayBridge {
  static const _channel = MethodChannel('com.speechmirror.app/overlay');

  static Future<Map<String, dynamic>?> showBubble() async {
    try {
      final r = await _channel.invokeMethod<dynamic>('showBubble');
      return _asMap(r);
    } on MissingPluginException {
      return null;
    }
  }

  /// 仅在悬浮窗与通知权限已就绪时启动悬浮球；不会打开系统设置（用于冷启动与生命周期恢复，避免循环跳转）。
  static Future<Map<String, dynamic>?> showBubbleIfPermitted() async {
    try {
      final r = await _channel.invokeMethod<dynamic>('showBubbleIfPermitted');
      return _asMap(r);
    } on MissingPluginException {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> hideBubble() async {
    try {
      final r = await _channel.invokeMethod<dynamic>('hideBubble');
      return _asMap(r);
    } on MissingPluginException {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> expandPanel() async {
    try {
      final r = await _channel.invokeMethod<dynamic>('expandPanel');
      return _asMap(r);
    } on MissingPluginException {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> pasteToFocused(String text) async {
    try {
      final r = await _channel.invokeMethod<dynamic>('pasteToFocused', {'text': text});
      return _asMap(r);
    } on MissingPluginException {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> clickSend() async {
    try {
      final r = await _channel.invokeMethod<dynamic>('clickSend');
      return _asMap(r);
    } on MissingPluginException {
      return null;
    }
  }

  /// 打开系统「语镜」应用详情（Android）；用于在总列表找不到时从权限入口进入。
  static Future<void> openAppDetailsSettings() async {
    try {
      await _channel.invokeMethod<void>('openAppDetailsSettings');
    } on MissingPluginException {
      return;
    }
  }

  /// 再次请求打开「显示在其他应用的上层」设置页（Android）。
  static Future<void> openManageOverlayPermission() async {
    try {
      await _channel.invokeMethod<void>('openManageOverlayPermission');
    } on MissingPluginException {
      return;
    }
  }

  /// 将开关镜像到 Android SharedPreferences，供无障碍 / 前台服务读取。
  static Future<void> syncOverlayPrefs({
    bool? overlayAutoShow,
    bool? collectDialogEnabled,
  }) async {
    try {
      final map = <String, dynamic>{};
      if (overlayAutoShow != null) map['overlay_auto_show'] = overlayAutoShow;
      if (collectDialogEnabled != null) map['collect_dialog_enabled'] = collectDialogEnabled;
      if (map.isEmpty) return;
      await _channel.invokeMethod<void>('syncOverlayPrefs', map);
    } on MissingPluginException {
      return;
    }
  }

  /// 无障碍估算的第三方键盘底部占用高度（px），无键盘时为 0。
  static Future<double> getOuterKeyboardInsetPx() async {
    try {
      final v = await _channel.invokeMethod<dynamic>('getOuterKeyboardInsetPx');
      if (v is int) return v.toDouble();
      if (v is double) return v;
      return 0;
    } on MissingPluginException {
      return 0;
    }
  }

  /// 仅在「允许浮窗采集对话」开启时由浮窗主动调用；遍历当前界面节点。
  static Future<Map<String, dynamic>?> collectDialogContext({int maxChars = 4000}) async {
    try {
      final r = await _channel.invokeMethod<dynamic>('collectDialogContext', {'maxChars': maxChars});
      return _asMap(r);
    } on MissingPluginException {
      return null;
    }
  }

  static Map<String, dynamic>? _asMap(dynamic r) {
    if (r is Map) {
      return r.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }
}

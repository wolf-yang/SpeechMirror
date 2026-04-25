package com.speechmirror.app

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 主引擎与浮窗引擎共用的 MethodChannel（com.speechmirror.app/overlay），
 * 以便浮窗内 Dart 可调用 pasteToFocused / clickSend 等。
 */
class OverlayFlutterChannel(private val host: Context) : MethodChannel.MethodCallHandler {

    companion object {
        private const val CHANNEL = "com.speechmirror.app/overlay"
        private const val REQ_POST_NOTIFICATIONS = 1002

        fun install(messenger: io.flutter.plugin.common.BinaryMessenger, host: Context) {
            MethodChannel(messenger, CHANNEL).setMethodCallHandler(OverlayFlutterChannel(host))
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "showBubble" -> handleShowBubble(result, openSettingsIfNoOverlay = true, requestNotificationIfDenied = true)
            "showBubbleIfPermitted" -> handleShowBubble(result, openSettingsIfNoOverlay = false, requestNotificationIfDenied = false)
            "hideBubble" -> {
                host.startService(Intent(host, OverlayService::class.java).apply { action = OverlayService.ACTION_HIDE })
                result.success(mapOf("ok" to true))
            }
            "expandPanel" -> {
                host.startService(Intent(host, OverlayService::class.java).apply { action = OverlayService.ACTION_EXPAND })
                result.success(mapOf("ok" to true))
            }
            "pasteToFocused" -> {
                val text = call.argument<String>("text") ?: ""
                val ok = SpeechMirrorAccessibilityService.instance?.pasteIntoFocused(text) ?: false
                result.success(
                    mapOf(
                        "ok" to ok,
                        "error" to if (ok) null else "需要开启语镜无障碍服务",
                    ),
                )
            }
            "clickSend" -> {
                val ok = SpeechMirrorAccessibilityService.instance?.clickSendMapped(host) ?: false
                result.success(
                    mapOf(
                        "ok" to ok,
                        "error" to if (ok) null else "未找到发送按钮或无障碍未开启",
                    ),
                )
            }
            "openAppDetailsSettings" -> {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.fromParts("package", host.packageName, null)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                host.startActivity(intent)
                result.success(mapOf("ok" to true))
            }
            "openManageOverlayPermission" -> {
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:${host.packageName}"),
                ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                host.startActivity(intent)
                result.success(mapOf("ok" to true))
            }
            "syncOverlayPrefs" -> {
                val map = call.arguments as? Map<*, *>
                if (map != null) {
                    val ed = OverlayPrefs.prefs(host).edit()
                    if (map.containsKey("overlay_auto_show")) {
                        ed.putBoolean(
                            OverlayPrefs.KEY_OVERLAY_AUTO,
                            map["overlay_auto_show"] == true,
                        )
                    }
                    if (map.containsKey("collect_dialog_enabled")) {
                        ed.putBoolean(
                            OverlayPrefs.KEY_COLLECT,
                            map["collect_dialog_enabled"] == true,
                        )
                    }
                    ed.apply()
                }
                result.success(mapOf("ok" to true))
            }
            "getOuterKeyboardInsetPx" -> {
                val px = SpeechMirrorAccessibilityService.lastKeyboardInsetPx.toFloat()
                val density = host.resources.displayMetrics.density
                val logical = if (density > 0f) px / density else px
                result.success(logical.toDouble())
            }
            "collectDialogContext" -> {
                if (!OverlayPrefs.isCollectDialogEnabled(host)) {
                    result.success(mapOf("ok" to false, "error" to "未开启采集开关", "text" to ""))
                    return
                }
                val maxChars = (call.argument<Number>("maxChars") ?: 4000).toInt().coerceIn(500, 12000)
                val text = SpeechMirrorAccessibilityService.instance?.collectChatContext(maxChars) ?: ""
                result.success(mapOf("ok" to true, "text" to text))
            }
            else -> result.notImplemented()
        }
    }

    private fun handleShowBubble(
        result: MethodChannel.Result,
        openSettingsIfNoOverlay: Boolean,
        requestNotificationIfDenied: Boolean,
    ) {
        if (!OverlayPermissionChecker.canDrawOverlay(host)) {
            if (openSettingsIfNoOverlay) {
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:${host.packageName}"),
                ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                host.startActivity(intent)
            }
            result.success(mapOf("ok" to false, "error" to "需要悬浮窗权限"))
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (!OverlayPermissionChecker.hasPostNotifications(host)) {
                if (requestNotificationIfDenied && host is Activity) {
                    ActivityCompat.requestPermissions(
                        host,
                        arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                        REQ_POST_NOTIFICATIONS,
                    )
                }
                result.success(mapOf("ok" to false, "error" to "需要通知权限（用于前台服务显示悬浮球）"))
                return
            }
        }
        val overlayIntent = Intent(host, OverlayService::class.java).apply { action = OverlayService.ACTION_SHOW }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            host.startForegroundService(overlayIntent)
        } else {
            host.startService(overlayIntent)
        }
        result.success(mapOf("ok" to true))
    }
}

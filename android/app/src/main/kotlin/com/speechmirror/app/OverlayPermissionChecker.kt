package com.speechmirror.app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.core.content.ContextCompat

object OverlayPermissionChecker {
    fun canDrawOverlay(ctx: Context): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(ctx)
    }

    fun hasPostNotifications(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            ctx,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    /** 与 [OverlayFlutterChannel] showBubbleIfPermitted 一致：可启动前台悬浮球。 */
    fun mayShowBubble(ctx: Context): Boolean = canDrawOverlay(ctx) && hasPostNotifications(ctx)
}

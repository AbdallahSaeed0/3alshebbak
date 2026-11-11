package com.shebbak.shebbak

import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "shebbak/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "brand" -> result.success(Build.MANUFACTURER.lowercase())
                    // Unique to this app on this phone, and the same after the
                    // app is deleted and installed again (settings backup).
                    "installKey" -> result.success(
                        Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
                    )
                    "openAutostart" -> result.success(openAutostart())
                    "openBattery" -> result.success(openBattery())
                    "openAppDetails" -> result.success(openAppDetails())
                    else -> result.notImplemented()
                }
            }
    }

    /** The phone maker's own "start in background" screen, where it has one. */
    private fun openAutostart(): Boolean {
        val screens = listOf(
            ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity"),
            ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity"),
            ComponentName("com.coloros.safecenter", "com.coloros.safecenter.startupapp.StartupAppListActivity"),
            ComponentName("com.oplus.safecenter", "com.oplus.safecenter.startupapp.StartupAppListActivity"),
            ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"),
            ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
        )
        for (screen in screens) {
            if (launch(Intent().setComponent(screen))) return true
        }
        return openAppDetails()
    }

    /** Xiaomi's per-app battery saver screen; elsewhere the app's info page. */
    private fun openBattery(): Boolean {
        if (Build.MANUFACTURER.equals("xiaomi", true)) {
            val miui = Intent("miui.intent.action.HIDDEN_APPS_CONFIG_ACTIVITY")
                .setClassName("com.miui.powerkeeper", "com.miui.powerkeeper.ui.HiddenAppsConfigActivity")
                .putExtra("package_name", packageName)
                .putExtra("package_label", packageManager.getApplicationLabel(applicationInfo).toString())
            if (launch(miui)) return true
        }
        return openAppDetails()
    }

    private fun openAppDetails(): Boolean = launch(
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
    )

    private fun launch(intent: Intent): Boolean = try {
        startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: Exception) {
        false
    }
}

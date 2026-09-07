package com.doit.app.permissions

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.doit.app.notifications.ReminderNotifier

/** Reads and requests everything reminder delivery depends on. Never throws. */
class PermissionHelper(private val context: Context) {

    companion object {
        const val REQUEST_POST_NOTIFICATIONS = 4711
    }

    fun notificationsEnabled(): Boolean =
        NotificationManagerCompat.from(context).areNotificationsEnabled()

    /** True on Android 13+ when the runtime permission has not been granted yet. */
    fun canRequestNotificationPermission(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED

    fun exactAlarmPermissionRequired(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S

    fun exactAlarmsAllowed(): Boolean {
        if (!exactAlarmPermissionRequired()) return true
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return alarmManager.canScheduleExactAlarms()
    }

    fun ignoringBatteryOptimizations(): Boolean {
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return powerManager.isIgnoringBatteryOptimizations(context.packageName)
    }

    /** Android 14+ gates lock-screen (full-screen) alarms behind a special access. */
    fun fullScreenIntentPermissionRequired(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE

    fun fullScreenIntentAllowed(): Boolean = ReminderNotifier.canUseFullScreenIntent(context)

    fun statusMap(): Map<String, Any> = mapOf(
        "notificationsEnabled" to notificationsEnabled(),
        "canRequestNotificationPermission" to canRequestNotificationPermission(),
        "exactAlarmsAllowed" to exactAlarmsAllowed(),
        "exactAlarmPermissionRequired" to exactAlarmPermissionRequired(),
        "ignoringBatteryOptimizations" to ignoringBatteryOptimizations(),
        "fullScreenIntentAllowed" to fullScreenIntentAllowed(),
        "fullScreenIntentPermissionRequired" to fullScreenIntentPermissionRequired(),
        "sdkInt" to Build.VERSION.SDK_INT,
    )

    /** Returns true when a dialog was shown (result arrives asynchronously). */
    fun requestNotificationPermission(activity: Activity): Boolean {
        if (!canRequestNotificationPermission()) return false
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_POST_NOTIFICATIONS,
        )
        return true
    }

    fun openNotificationSettings() {
        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
        startSettings(intent)
    }

    fun openNotificationChannelSettings() {
        ReminderNotifier.ensureChannels(context)
        val intent = Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            .putExtra(Settings.EXTRA_CHANNEL_ID, ReminderNotifier.CHANNEL_ID)
        startSettings(intent)
    }

    fun openExactAlarmSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
            .setData(Uri.parse("package:${context.packageName}"))
        startSettings(intent)
    }

    fun openBatteryOptimizationSettings() {
        // The list view needs no special permission (unlike the direct
        // REQUEST_IGNORE_BATTERY_OPTIMIZATIONS dialog).
        startSettings(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
    }

    fun openFullScreenIntentSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return
        val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT)
            .setData(Uri.parse("package:${context.packageName}"))
        startSettings(intent)
    }

    private fun startSettings(intent: Intent) {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(intent)
        } catch (e: ActivityNotFoundException) {
            // Fall back to the generic app details page.
            val fallback = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:${context.packageName}"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                context.startActivity(fallback)
            } catch (ignored: ActivityNotFoundException) {
                // Nothing sensible left to do; the UI already explains the state.
            }
        }
    }
}

package com.doit.app.channel

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.doit.app.db.DoItDatabase
import com.doit.app.notifications.AlarmRingService
import com.doit.app.notifications.ReminderNotifier
import com.doit.app.permissions.PermissionHelper
import com.doit.app.receivers.DoItIntents
import com.doit.app.scheduling.Engine
import com.doit.app.scheduling.ReminderEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.time.ZoneId

/**
 * Flutter <-> native bridge. Method names mirror `MethodChannelDoItPlatform` in
 * lib/core/platform/do_it_platform.dart.
 *
 * Engine work (which touches the database) runs on the engine thread; results
 * are delivered back on the main thread as the platform channel requires.
 */
class EngineChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val NAME = "com.doit.app/engine"
        private const val TAG = "DoIt.Channel"
        private const val TEST_RING_MINUTES = 1
    }

    private val channel = MethodChannel(messenger, NAME)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val permissions = PermissionHelper(activity.applicationContext)

    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingLaunchReminderId: Long? = null

    fun attach() {
        channel.setMethodCallHandler(this)
        FlutterBridge.attach(
            onDataChanged = { channel.invokeMethod("onDataChanged", null) },
            onRingingChanged = { id -> channel.invokeMethod("onRingingChanged", id?.toInt()) },
        )
    }

    fun detach() {
        FlutterBridge.detach()
        channel.setMethodCallHandler(null)
        pendingPermissionResult = null
    }

    /**
     * Notification taps carry the reminder id. On a cold start Flutter is not
     * ready to navigate yet, so the id is parked until `consumeLaunchReminderId`.
     */
    fun handleIntent(intent: Intent?, coldStart: Boolean) {
        val reminderId = intent?.getLongExtra(DoItIntents.EXTRA_REMINDER_ID, -1L) ?: -1L
        if (reminderId <= 0) return
        if (coldStart) {
            pendingLaunchReminderId = reminderId
        } else {
            channel.invokeMethod("onOpenReminder", reminderId.toInt())
        }
    }

    fun onRequestPermissionsResult(requestCode: Int) {
        if (requestCode != PermissionHelper.REQUEST_POST_NOTIFICATIONS) return
        val result = pendingPermissionResult ?: return
        pendingPermissionResult = null
        result.success(permissions.notificationsEnabled())
        // Newly granted permission: make sure the channels exist and alarms are set.
        Engine.submit(activity, "reschedule after permission change") { it.rescheduleAll() }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "getDatabasePath" -> result.success(DoItDatabase.file(activity).absolutePath)
                "getLocalTimeZone" -> result.success(ZoneId.systemDefault().id)

                "scheduleReminder" -> {
                    val id = reminderIdArg(call) ?: return result.error("bad_args", "reminderId missing", null)
                    runEngine(result, "scheduleReminder $id") { it.scheduleNext(id) }
                }
                "cancelReminder" -> {
                    val id = reminderIdArg(call) ?: return result.error("bad_args", "reminderId missing", null)
                    runEngine(result, "cancelReminder $id") { it.cancel(id) }
                }
                "rescheduleAll" -> runEngine(result, "rescheduleAll") { it.rescheduleAll() }

                "stopRinging" -> {
                    AlarmRingService.stop(activity, repostNotification = true)
                    result.success(null)
                }
                "getRingingReminderId" -> result.success(AlarmRingService.ringingReminderId?.toInt())

                "getPermissionStatus" -> result.success(permissions.statusMap())
                "requestNotificationPermission" -> {
                    if (pendingPermissionResult != null) {
                        result.error("busy", "A permission request is already in progress", null)
                    } else if (permissions.requestNotificationPermission(activity)) {
                        pendingPermissionResult = result
                    } else {
                        result.success(permissions.notificationsEnabled())
                    }
                }
                "openNotificationSettings" -> {
                    permissions.openNotificationSettings(); result.success(null)
                }
                "openNotificationChannelSettings" -> {
                    permissions.openNotificationChannelSettings(); result.success(null)
                }
                "openExactAlarmSettings" -> {
                    permissions.openExactAlarmSettings(); result.success(null)
                }
                "openBatteryOptimizationSettings" -> {
                    permissions.openBatteryOptimizationSettings(); result.success(null)
                }
                "openFullScreenIntentSettings" -> {
                    permissions.openFullScreenIntentSettings(); result.success(null)
                }

                "showTestNotification" -> {
                    ReminderNotifier(activity).showTest(TEST_RING_MINUTES)
                    result.success(null)
                }
                "consumeLaunchReminderId" -> {
                    val id = pendingLaunchReminderId
                    pendingLaunchReminderId = null
                    result.success(id?.toInt())
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Method ${call.method} failed", e)
            result.error("engine_error", e.message, null)
        }
    }

    private fun reminderIdArg(call: MethodCall): Long? =
        (call.argument<Number>("reminderId"))?.toLong()

    private fun runEngine(result: MethodChannel.Result, description: String, block: (ReminderEngine) -> Unit) {
        val future = Engine.submit(activity, description, block)
        // Complete the Dart future once the work is done, on the main thread.
        Thread {
            try {
                future.get()
            } catch (e: Exception) {
                Log.w(TAG, "$description did not complete cleanly", e)
            }
            mainHandler.post { result.success(null) }
        }.start()
    }
}

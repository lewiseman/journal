package com.lewiseman.journal

import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.StatFs
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Model storage and resource facts are independent of every inference engine. */
object LocalAiStorage {
    fun register(activity: Activity, messenger: BinaryMessenger) {
        val directory = File(activity.noBackupFilesDir, "ai_models").apply { mkdirs() }
        MethodChannel(messenger, "journal/local_ai_storage").setMethodCallHandler { call, result ->
            when (call.method) {
                "directory" -> result.success(directory.absolutePath)
                "resources" -> {
                    val memory = ActivityManager.MemoryInfo()
                    (activity.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(memory)
                    val cm = activity.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                    val network = cm.getNetworkCapabilities(cm.activeNetwork)
                    result.success(mapOf("freeBytes" to StatFs(directory.path).availableBytes,
                        "ramBytes" to memory.totalMem,
                        "wifi" to (network?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true && !cm.isActiveNetworkMetered)))
                }
                else -> result.notImplemented()
            }
        }
    }
}

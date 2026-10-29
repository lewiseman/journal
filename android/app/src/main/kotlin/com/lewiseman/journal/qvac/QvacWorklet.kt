// Adapted from qvac_flutter, Apache-2.0. See native/qvac/THIRD_PARTY_NOTICES.md.
package com.lewiseman.journal.qvac

import android.content.Context
import android.app.Activity
import android.app.Application
import android.os.Bundle
import io.flutter.embedding.engine.FlutterEngine
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import to.holepunch.bare.kit.IPC
import to.holepunch.bare.kit.Worklet
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.Executors

/** Runs the QVAC worker in a BareKit worklet and passes its IPC bytes to Dart. */
open class QvacWorklet(
    private val channel: String = "journal/qvac",
    private val asset: String = "worker.bundle",
) : FlutterPlugin, Application.ActivityLifecycleCallbacks, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private lateinit var context: Context
    private val main = Handler(Looper.getMainLooper())
    private val background = Executors.newSingleThreadExecutor()
    // Calls waiting for a start already in progress, such as one from after a hot restart.
    private var starting: MutableList<MethodChannel.Result>? = null
    private var attached = false

    companion object {
        @JvmStatic fun register(activity: Activity, engine: FlutterEngine) {
            val plugin = QvacWorklet()
            engine.plugins.add(plugin)
            plugin.activity = activity
            activity.application.registerActivityLifecycleCallbacks(plugin)
        }
        @JvmStatic fun registerPeople(activity: Activity, engine: FlutterEngine) {
            val plugin: QvacWorklet = PeopleWorklet()
            engine.plugins.add(plugin)
            plugin.activity = activity
            activity.application.registerActivityLifecycleCallbacks(plugin)
        }
    }
    private var activity: Activity? = null
    private var suspended = false
    override fun onActivityPaused(value: Activity) {
        if (value !== activity) return
        suspended = true
        emitState()
        worklet?.suspend(0)
    }
    override fun onActivityResumed(value: Activity) {
        if (value !== activity) return
        suspended = false
        worklet?.resume()
    }
    override fun onActivityCreated(a: Activity, b: Bundle?) {}
    override fun onActivityStarted(a: Activity) {}
    override fun onActivityStopped(a: Activity) {}
    override fun onActivitySaveInstanceState(a: Activity, b: Bundle) {}
    override fun onActivityDestroyed(a: Activity) {
        if (a === activity) a.application.unregisterActivityLifecycleCallbacks(this)
    }
    private fun emitState() { sink?.success(mapOf("state" to "interrupted")) }
    private var worklet: Worklet? = null
    private var ipc: IPC? = null
    private var sink: EventChannel.EventSink? = null
    // Bytes that arrived before Dart started listening.
    private val early = ArrayList<ByteArray>()
    private val outbox = ArrayDeque<ByteArray>()
    private var writing = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        attached = true
        methods = MethodChannel(binding.binaryMessenger, channel)
        methods.setMethodCallHandler(this)
        events = EventChannel(binding.binaryMessenger, "${channel}_ipc")
        events.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        activity?.application?.unregisterActivityLifecycleCallbacks(this)
        attached = false
        background.shutdown()
        stop()
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> start(call.argument<String>("homeDir"), result)
            "write" -> {
                val bytes = call.arguments as? ByteArray
                    ?: return result.error("bad_args", "write needs bytes", null)
                if (suspended) worklet?.resume() // Dart is cancelling/shutting down.
                outbox.addLast(bytes)
                flush()
                result.success(null)
            }
            "stop" -> {
                stop()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun start(homeDir: String?, result: MethodChannel.Result) {
        if (suspended) return result.error("NOT_READY", "Keep Journal in the foreground.", null)
        // Left over from before a hot restart. Dart shuts it down and starts again.
        if (worklet != null) {
            early.clear()
            return result.success("running")
        }
        starting?.let {
            it.add(result)
            return
        }
        val waiting = mutableListOf(result)
        starting = waiting
        // Reading the bundle and starting the worklet takes long enough to drop frames.
        background.execute {
            val outcome = runCatching { launch(homeDir) }
            main.post {
                starting = null
                outcome.fold(
                    onSuccess = { worklet ->
                        if (!attached) {
                            worklet.terminate()
                            return@fold
                        }
                        this.worklet = worklet
                        if (suspended) { worklet.suspend(0); emitState() }
                        ipc = IPC(worklet)
                        read()
                        flush()
                        // Later callers find a worker they didn't start, like after a hot restart.
                        waiting.forEachIndexed { i, r -> r.success(if (i == 0) "started" else "running") }
                    },
                    // Throwable: a missing native library is an Error, not an Exception.
                    onFailure = { e ->
                        waiting.forEach { it.error("start_failed", e.message ?: e.toString(), null) }
                    },
                )
            }
        }
    }

    private fun launch(homeDir: String?): Worklet {
        check("arm64-v8a" in Build.SUPPORTED_ABIS) {
            "qvac_flutter only runs on arm64-v8a. This device supports ${Build.SUPPORTED_ABIS.joinToString()}."
        }
        // No Auto Backup: models are big and can be downloaded again.
        val home = homeDir ?: File(context.noBackupFilesDir, "qvac").apply { mkdirs() }.absolutePath
        val worklet = Worklet(Worklet.Options())
        try {
            // Same argument shape as QVAC's Kotlin SDK: the JSON config must be third.
            val args = arrayOf(channel, asset, JSONObject().put("HOME_DIR", home).toString())
            context.assets.open(asset).use { worklet.start("/$asset", it, args) }
        } catch (e: Throwable) {
            worklet.terminate()
            throw e
        }
        return worklet
    }

    private fun read() {
        val current = ipc ?: return
        current.read { data, error ->
            main.post {
                if (ipc !== current) return@post
                when {
                    error != null -> sink?.error("ipc_error", error.message, null)
                    data == null -> sink?.endOfStream()
                    else -> {
                        emit(data.toByteArray())
                        read()
                    }
                }
            }
        }
    }

    private fun emit(bytes: ByteArray) {
        sink?.success(bytes) ?: early.add(bytes)
    }

    // One write at a time, so frames reach the worker in order.
    private fun flush() {
        val current = ipc ?: return
        if (writing || outbox.isEmpty()) return
        writing = true
        val bytes = outbox.removeFirst()
        val buffer = ByteBuffer.allocateDirect(bytes.size).put(bytes)
        buffer.flip()
        current.write(buffer) { error ->
            main.post {
                if (ipc !== current) return@post
                writing = false
                if (error != null) sink?.error("ipc_error", error.message, null)
                flush()
            }
        }
    }

    // Dart sends __shutdown__ first; terminating without it crashes the next start.
    private fun stop() {
        worklet?.resume()
        ipc?.close()
        ipc = null
        worklet?.terminate()
        worklet = null
        outbox.clear()
        early.clear()
        writing = false
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        early.forEach { events.success(it) }
        early.clear()
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    private fun ByteBuffer.toByteArray(): ByteArray {
        val out = ByteArray(remaining())
        get(out)
        return out
    }
}

// FlutterEngine keys plugins by concrete class; these must be distinct plugins.
class PeopleWorklet : QvacWorklet("journal/people", "people.bundle")

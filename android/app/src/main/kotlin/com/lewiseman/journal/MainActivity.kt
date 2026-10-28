package com.lewiseman.journal

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var permission: MethodChannel.Result? = null
    // Answers with a status string rather than a bool, so Dart can tell a
    // permanently denied microphone (only Settings can fix it) from a denied one.
    private var micStatusRequest: MethodChannel.Result? = null
    private var recorder: AudioRecord? = null
    private var worker: Thread? = null
    private val running = AtomicBoolean(false)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "journal/pcm_events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) { sink = events }
            override fun onCancel(arguments: Any?) { stopCapture(); sink = null }
        })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "journal/pcm").setMethodCallHandler { call, result ->
            when (call.method) {
                "permission" -> {
                    if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) result.success(true)
                    else if (permission != null) result.error("BUSY", "Microphone permission is already pending.", null)
                    else if (micStatusRequest != null) result.error("BUSY", "Microphone permission is already pending.", null)
                    else { permission = result; markMicAsked(); requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 7301) }
                }
                "micStatus" -> result.success(micStatus())
                "requestMic" -> {
                    if (micStatus() == "granted") result.success("granted")
                    else if (permission != null || micStatusRequest != null) result.error("BUSY", "Microphone permission is already pending.", null)
                    else { micStatusRequest = result; markMicAsked(); requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 7301) }
                }
                "openSettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(true)
                    } catch (e: Exception) { result.success(false) }
                }
                "start" -> {
                    try { startCapture(call.argument<String>("path") ?: ""); result.success(null) }
                    catch (e: Exception) { stopCapture(); result.error("MICROPHONE", "Could not open the microphone. Check permission and other recording apps.", null) }
                }
                "stop" -> { stopCapture(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 7301) {
            permission?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED); permission = null
            micStatusRequest?.success(micStatus()); micStatusRequest = null
        }
    }
    private val micPrefs get() = getSharedPreferences("journal_microphone", MODE_PRIVATE)
    private fun markMicAsked() { micPrefs.edit().putBoolean("asked", true).apply() }
    // Android only reports "don't ask again" indirectly: after an earlier request,
    // a denied permission with no rationale to show can no longer be requested.
    private fun micStatus(): String = when {
        checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED -> "granted"
        shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO) -> "denied"
        micPrefs.getBoolean("asked", false) -> "blocked"
        else -> "denied"
    }
    private fun startCapture(rawPath: String) {
        check(!running.get() && sink != null)
        check(checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED)
        val file = File(rawPath).canonicalFile
        check(file.path.startsWith(File(filesDir, "voice_sessions").canonicalPath + File.separator) && !file.exists())
        file.parentFile?.mkdirs()
        val minimum = AudioRecord.getMinBufferSize(16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        check(minimum > 0)
        val audio = AudioRecord.Builder()
            .setAudioSource(MediaRecorder.AudioSource.VOICE_RECOGNITION)
            .setAudioFormat(AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(16000).setChannelMask(AudioFormat.CHANNEL_IN_MONO).build())
            .setBufferSizeInBytes(maxOf(minimum * 2, 12800)).build()
        recorder = audio
        check(audio.state == AudioRecord.STATE_INITIALIZED)
        if (Build.VERSION.SDK_INT >= 29) {
            audio.registerAudioRecordingCallback(mainExecutor, object : android.media.AudioManager.AudioRecordingCallback() {
                override fun onRecordingConfigChanged(configs: MutableList<android.media.AudioRecordingConfiguration>) {
                    if (running.get() && audio.activeRecordingConfiguration?.isClientSilenced == true) {
                        main.post { stopCapture(); sink?.error("INTERRUPTED", "Android silenced the microphone. Review the audio captured so far.", null) }
                    }
                }
            })
        }
        val output = FileOutputStream(file, false)
        try { audio.startRecording(); check(audio.recordingState == AudioRecord.RECORDSTATE_RECORDING) }
        catch (e: Exception) { output.close(); throw e }
        running.set(true)
        worker = Thread({
            val buffer = ByteArray(3200) // 100 ms, mono 16 kHz signed PCM16 LE
            var total = 0
            try {
                while (running.get()) {
                    val count = audio.read(buffer, 0, buffer.size, AudioRecord.READ_BLOCKING)
                    if (count <= 0) { if (running.get()) throw IllegalStateException(); break }
                    if (total + count > 19200000) break
                    output.write(buffer, 0, count); total += count
                    val copy = buffer.copyOf(count)
                    main.post { sink?.success(copy) }
                }
            } catch (e: Exception) {
                main.post { sink?.error("INTERRUPTED", "Recording was interrupted. Audio already captured is retained for review.", null) }
            } finally {
                try { output.fd.sync() } catch (_: Exception) {}
                try { output.close() } catch (_: Exception) {}
                running.set(false)
                main.post { sink?.success(mapOf("stopped" to true)) }
            }
        }, "journal-microphone").also { it.start() }
    }
    private fun stopCapture() {
        running.set(false)
        try { recorder?.stop() } catch (_: Exception) {}
        worker?.join(2000); worker = null
        recorder?.release(); recorder = null
    }
    override fun onPause() { stopCapture(); super.onPause() }
    override fun onDestroy() { stopCapture(); super.onDestroy() }
}

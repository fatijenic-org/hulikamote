package com.hulikamote.hulikamote_camera

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.OpenableColumns
import android.net.Uri
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * The bridge between the app screen (Dart) and the broadcast (Kotlin).
 *   control channel:  start / stop / status / pickVideo
 *   preview channel:  a small JPEG a few times a second, so the screen shows what the laptop receives
 */
class MainActivity : FlutterActivity() {
    private lateinit var streamer: Streamer
    private var previewSink: EventChannel.EventSink? = null
    private var pendingStart: Pair<Map<*, *>, MethodChannel.Result>? = null
    private var pendingPick: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        streamer = Streamer(applicationContext) { jpeg -> runOnUiThread { previewSink?.success(jpeg) } }
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "hulikamote_camera/control").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> start(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>(), result)
                "stop" -> {
                    stopBroadcast()
                    result.success(null)
                }
                "status" -> result.success(streamer.status())
                "pickVideo" -> pickVideo(result)
                "loadPrefs" -> result.success(loadPrefs())
                "savePrefs" -> {
                    savePrefs(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>())
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "hulikamote_camera/preview").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                previewSink = events
            }

            override fun onCancel(arguments: Any?) {
                previewSink = null
            }
        })
    }

    // ── the last choice: the app opens and broadcasts by itself with it ──
    private val prefs by lazy { getSharedPreferences("hulikamote_camera", MODE_PRIVATE) }

    private fun loadPrefs(): Map<String, Any?> = mapOf(
        "mode" to prefs.getString("mode", null),
        "front" to prefs.getBoolean("front", false),
        "quality" to prefs.getString("quality", null),
        "wifi" to prefs.getBoolean("wifi", true),
        "videoUri" to prefs.getString("videoUri", null),
        "videoName" to prefs.getString("videoName", null),
    )

    private fun savePrefs(args: Map<*, *>) {
        prefs.edit().apply {
            (args["mode"] as? String)?.let { putString("mode", it) }
            (args["front"] as? Boolean)?.let { putBoolean("front", it) }
            (args["quality"] as? String)?.let { putString("quality", it) }
            (args["wifi"] as? Boolean)?.let { putBoolean("wifi", it) }
            (args["videoUri"] as? String)?.let { putString("videoUri", it) }
            (args["videoName"] as? String)?.let { putString("videoName", it) }
        }.apply()
    }

    // ── start / stop ──
    private fun start(args: Map<*, *>, result: MethodChannel.Result) {
        val mode = args["mode"] as? String ?: "camera"
        if (mode == "camera" && checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            pendingStart = args to result                         // asked once; continues in onRequestPermissionsResult
            requestPermissions(arrayOf(Manifest.permission.CAMERA), REQ_CAMERA)
            return
        }
        val error = streamer.start(
            Options(
                mode = mode,
                front = args["front"] as? Boolean ?: false,
                quality = args["quality"] as? String ?: "medium",
                allowNetwork = args["wifi"] as? Boolean ?: false,
                video = args["video"] as? String,
            )
        )
        if (error != null) {
            result.success(mapOf("ok" to false, "error" to error))
        } else {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)   // a phone used as CCTV must not fall asleep
            result.success(mapOf("ok" to true))
        }
    }

    private fun stopBroadcast() {
        streamer.stop()
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQ_CAMERA) return
        val pending = pendingStart ?: return
        pendingStart = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            start(pending.first, pending.second)
        } else {
            pending.second.success(mapOf("ok" to false, "error" to "The camera needs permission. Allow it in the phone's settings, or broadcast a gallery video instead."))
        }
    }

    // ── the gallery ──
    private fun pickVideo(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("busy", "A video is already being chosen.", null)
            return
        }
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "video/*"
        }
        startActivityForResult(intent, REQ_VIDEO)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_VIDEO) return
        val result = pendingPick ?: return
        pendingPick = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        try {
            // so the app can broadcast this video again the next time it opens by itself
            contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (_: Exception) {
        }
        result.success(mapOf("uri" to uri.toString(), "name" to displayName(uri)))
    }

    private fun displayName(uri: Uri): String {
        try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) return cursor.getString(0) ?: "video"
            }
        } catch (_: Exception) {
        }
        return uri.lastPathSegment ?: "video"
    }

    override fun onDestroy() {
        if (::streamer.isInitialized) streamer.stop()
        super.onDestroy()
    }

    private companion object {
        const val REQ_CAMERA = 41
        const val REQ_VIDEO = 42
    }
}

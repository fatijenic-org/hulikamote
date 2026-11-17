package com.hulikamote.hulikamote_camera

import android.content.Context
import android.net.Uri
import android.os.SystemClock
import java.io.IOException
import java.net.Inet4Address
import java.net.NetworkInterface

/** What the operator chose in the app. */
data class Options(val mode: String, val front: Boolean, val quality: String, val allowNetwork: Boolean, val video: String?)

/**
 * One broadcast: the web server (MjpegServer) plus the thing that makes pictures (CameraFeed or VideoFeed).
 * Main thread only, except the picture callbacks.
 */
class Streamer(private val context: Context, private val onPreview: (ByteArray) -> Unit) {
    private var server: MjpegServer? = null
    private var feed: Feed? = null
    private var mode = "idle"
    private var allowNetwork = false
    @Volatile private var lastError: String? = null
    @Volatile private var fps = 0.0
    private var windowStart = 0L
    private var windowFrames = 0
    private var lastPreview = 0L

    /** Returns null when the broadcast runs, or the reason it could not start. */
    fun start(options: Options): String? {
        stop()
        lastError = null
        val web = MjpegServer(PORT, options.allowNetwork)
        try {
            web.start()
        } catch (e: IOException) {
            return "Port $PORT is busy or blocked (${e.message}). Close other camera apps and try again."
        }
        server = web
        mode = options.mode
        allowNetwork = options.allowNetwork
        val preset = Preset.of(options.quality)
        feed = try {
            if (options.mode == "video") {
                VideoFeed(context, Uri.parse(options.video), preset, { onJpeg(it) }, { lastError = it }).also { it.start() }
            } else {
                CameraFeed(context, options.front, preset, { onJpeg(it) }, { lastError = it }).also { it.start() }
            }
        } catch (e: Exception) {
            stop()
            return "Could not start: ${e.message ?: e.javaClass.simpleName}"
        }
        return null
    }

    fun stop() {
        feed?.stop()
        feed = null
        server?.stop()
        server = null
        mode = "idle"
        fps = 0.0
        windowFrames = 0
        windowStart = 0L
    }

    private fun onJpeg(jpeg: ByteArray) {
        server?.push(jpeg)
        val now = SystemClock.elapsedRealtime()
        if (windowStart == 0L) windowStart = now
        windowFrames++
        if (now - windowStart >= 1000) {
            fps = windowFrames * 1000.0 / (now - windowStart)
            windowStart = now
            windowFrames = 0
        }
        if (now - lastPreview >= 250) {                   // the small picture in the app needs only a few a second
            lastPreview = now
            onPreview(jpeg)
        }
    }

    fun status(): Map<String, Any?> = mapOf(
        "running" to (server != null),
        "mode" to mode,
        "clients" to (server?.clientCount ?: 0),
        "fps" to fps,
        "port" to PORT,
        "error" to lastError,
        "addresses" to if (allowNetwork) addresses() else emptyList(),
    )

    /** The phone's own network addresses (only useful when "Also allow Wi-Fi / USB tethering" is on). */
    private fun addresses(): List<Map<String, String>> {
        val found = mutableListOf<Map<String, String>>()
        try {
            for (network in NetworkInterface.getNetworkInterfaces()?.toList().orEmpty()) {
                if (!network.isUp || network.isLoopback) continue
                for (address in network.inetAddresses.toList()) {
                    if (address !is Inet4Address || address.isLoopbackAddress) continue
                    val name = network.name.lowercase()
                    val label = when {
                        name.startsWith("wlan") -> "Wi-Fi"
                        name.contains("rndis") || name.startsWith("usb") || name.contains("ncm") -> "USB tethering"
                        else -> network.name
                    }
                    found += mapOf("label" to label, "url" to "http://${address.hostAddress}:$PORT/video")
                }
            }
        } catch (_: Exception) {
        }
        return found
    }

    companion object {
        const val PORT = 8080
    }
}

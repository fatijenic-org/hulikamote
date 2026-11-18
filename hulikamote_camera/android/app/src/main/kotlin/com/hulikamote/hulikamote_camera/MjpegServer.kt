package com.hulikamote.hulikamote_camera

import java.io.BufferedOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.thread
import kotlin.concurrent.withLock

/**
 * The phone as an IP camera: a tiny web server that streams the newest JPEG as MJPEG (the format cheap CCTV cameras speak).
 *   /video          the stream (what HULI-KAMOTE reads: http://127.0.0.1:8080/video through adb forward)
 *   /snapshot.jpg   one picture
 *   anything else   a small page that shows the stream, to check it in a browser
 * Only the newest picture is kept, so a slow reader never builds up lag. With [allowNetwork] false the server listens on the
 * phone's loopback only: nothing on Wi-Fi can look at the camera, only the USB cable (adb forward) can reach it.
 */
class MjpegServer(private val port: Int, private val allowNetwork: Boolean) {
    private var socket: ServerSocket? = null
    @Volatile private var running = false
    private val lock = ReentrantLock()
    private val fresh = lock.newCondition()
    private var latest: ByteArray? = null
    private var seq = 0L
    private val clients = AtomicInteger(0)

    val clientCount: Int get() = clients.get()

    /** Throws IOException when the port is busy. */
    fun start() {
        val server = ServerSocket()
        server.reuseAddress = true
        server.bind(InetSocketAddress(InetAddress.getByName(if (allowNetwork) "0.0.0.0" else "127.0.0.1"), port), 8)
        socket = server
        running = true
        thread(name = "mjpeg-accept", isDaemon = true) {
            while (running) {
                try {
                    val client = server.accept()
                    thread(name = "mjpeg-client", isDaemon = true) { serve(client) }
                } catch (e: IOException) {
                    if (!running) break
                }
            }
        }
    }

    fun push(jpeg: ByteArray) {
        lock.withLock {
            latest = jpeg
            seq++
            fresh.signalAll()
        }
    }

    fun stop() {
        running = false
        try {
            socket?.close()
        } catch (_: IOException) {
        }
        lock.withLock { fresh.signalAll() }
    }

    private fun serve(client: Socket) {
        client.use { sock ->
            try {
                sock.soTimeout = 5000
                val path = requestPath(sock.getInputStream())
                val out = BufferedOutputStream(sock.getOutputStream())
                when (path) {
                    "/video", "/stream", "/mjpeg" -> stream(sock, out)
                    "/snapshot.jpg", "/snapshot" -> snapshot(out)
                    else -> page(out)
                }
            } catch (_: IOException) {
            }
        }
    }

    /** "GET /video HTTP/1.1 ..." -> "/video" (the headers are read and ignored). */
    private fun requestPath(input: InputStream): String {
        val text = StringBuilder()
        while (text.length < 8192 && !text.endsWith("\r\n\r\n")) {
            val b = input.read()
            if (b < 0) break
            text.append(b.toChar())
        }
        return text.lineSequence().firstOrNull()?.split(" ")?.getOrNull(1)?.substringBefore('?') ?: "/"
    }

    private fun stream(sock: Socket, out: OutputStream) {
        clients.incrementAndGet()
        try {
            sock.soTimeout = 0
            out.write(("HTTP/1.0 200 OK\r\nServer: HulikamotePhoneCamera\r\nCache-Control: no-cache, private\r\nPragma: no-cache\r\n" +
                "Content-Type: multipart/x-mixed-replace; boundary=$BOUNDARY\r\n\r\n").toByteArray())
            out.flush()
            var sent = -1L
            while (running && !sock.isClosed) {
                var frame: ByteArray? = null
                lock.withLock {
                    if (seq == sent) fresh.await(1, TimeUnit.SECONDS)      // no new picture for a second: send the last one again (keeps the link alive)
                    frame = latest
                    sent = seq
                }
                val jpeg = frame ?: continue
                out.write("--$BOUNDARY\r\nContent-Type: image/jpeg\r\nContent-Length: ${jpeg.size}\r\n\r\n".toByteArray())
                out.write(jpeg)
                out.write("\r\n".toByteArray())
                out.flush()
            }
        } finally {
            clients.decrementAndGet()
        }
    }

    private fun snapshot(out: OutputStream) {
        val jpeg = lock.withLock { latest }
        if (jpeg == null) {
            out.write("HTTP/1.1 503 Service Unavailable\r\nServer: HulikamotePhoneCamera\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".toByteArray())
        } else {
            out.write("HTTP/1.1 200 OK\r\nServer: HulikamotePhoneCamera\r\nContent-Type: image/jpeg\r\nContent-Length: ${jpeg.size}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".toByteArray())
            out.write(jpeg)
        }
        out.flush()
    }

    private fun page(out: OutputStream) {
        val html = "<!doctype html><meta name=viewport content='width=device-width,initial-scale=1'><title>HULI-KAMOTE Camera</title>" +
            "<body style='margin:0;background:#0b1220;color:#cbd5e1;font-family:sans-serif;text-align:center'>" +
            "<p>HULI-KAMOTE phone camera</p><img src='/video' style='max-width:100%'></body>"
        val body = html.toByteArray()
        out.write("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: ${body.size}\r\nConnection: close\r\n\r\n".toByteArray())
        out.write(body)
        out.flush()
    }

    private companion object {
        const val BOUNDARY = "hkframe"
    }
}

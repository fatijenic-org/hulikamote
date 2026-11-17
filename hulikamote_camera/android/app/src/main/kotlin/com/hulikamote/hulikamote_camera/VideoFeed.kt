package com.hulikamote.hulikamote_camera

import android.content.Context
import android.graphics.ImageFormat
import android.media.ImageReader
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock

/**
 * A video from the phone's gallery played as if it were a live camera: decoded at the video's own speed (never faster), every
 * picture turned upright and handed on as JPEG, and started again from the beginning when it ends (a CCTV never "ends").
 * A phone too slow to keep up skips pictures instead of falling behind, so the speed on the laptop stays real.
 */
class VideoFeed(
    private val context: Context,
    private val uri: Uri,
    private val preset: Preset,
    private val onJpeg: (ByteArray) -> Unit,
    private val onError: (String) -> Unit,
) : Feed {
    @Volatile private var running = false
    private var worker: Thread? = null

    fun start() {
        running = true
        worker = Thread({ play() }, "video-feed").also {
            it.isDaemon = true
            it.start()
        }
    }

    override fun stop() {
        running = false
        worker?.interrupt()
        worker?.join(2000)
    }

    private fun play() {
        var extractor: MediaExtractor? = null
        var codec: MediaCodec? = null
        var reader: ImageReader? = null
        val encoderThread = HandlerThread("video-jpeg").also { it.start() }
        try {
            val source = MediaExtractor().apply { setDataSource(context, uri, null) }
            extractor = source
            val track = (0 until source.trackCount).firstOrNull {
                source.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true
            } ?: throw IllegalStateException("That file has no video.")
            source.selectTrack(track)
            val format = source.getTrackFormat(track)
            val mime = format.getString(MediaFormat.KEY_MIME)!!
            val width = format.getInteger(MediaFormat.KEY_WIDTH)
            val height = format.getInteger(MediaFormat.KEY_HEIGHT)
            val rotation = if (format.containsKey(MediaFormat.KEY_ROTATION)) format.getInteger(MediaFormat.KEY_ROTATION) else 0

            // Decode to an ImageReader: it hands over every picture as YUV, ready for Jpeg.encode.
            val minIntervalMs = 1000L / preset.fps
            var lastEncode = 0L
            val images = ImageReader.newInstance(width, height, ImageFormat.YUV_420_888, 3)
            reader = images
            images.setOnImageAvailableListener({ r ->
                val image = r.acquireLatestImage() ?: return@setOnImageAvailableListener
                try {
                    val now = SystemClock.elapsedRealtime()
                    if (now - lastEncode >= minIntervalMs) {
                        lastEncode = now
                        onJpeg(Jpeg.encode(Yuv.of(image), preset.longSide, rotation, preset.quality))
                    }
                } catch (e: Exception) {
                    onError("A video picture could not be read: ${e.message ?: e.javaClass.simpleName}")
                } finally {
                    image.close()
                }
            }, Handler(encoderThread.looper))

            val decoder = MediaCodec.createDecoderByType(mime)
            codec = decoder
            decoder.configure(format, images.surface, null, 0)
            decoder.start()

            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var firstPts = -1L
            var startNs = 0L
            while (running) {
                if (!inputDone) {
                    val index = decoder.dequeueInputBuffer(10_000)
                    if (index >= 0) {
                        val size = source.readSampleData(decoder.getInputBuffer(index)!!, 0)
                        if (size < 0) {
                            decoder.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            decoder.queueInputBuffer(index, 0, size, source.sampleTime, 0)
                            source.advance()
                        }
                    }
                }
                val out = decoder.dequeueOutputBuffer(info, 10_000)
                if (out >= 0) {
                    if (firstPts < 0) {
                        firstPts = info.presentationTimeUs
                        startNs = System.nanoTime()
                    }
                    val waitMs = (startNs + (info.presentationTimeUs - firstPts) * 1000 - System.nanoTime()) / 1_000_000
                    if (waitMs > 0) Thread.sleep(waitMs)
                    decoder.releaseOutputBuffer(out, waitMs > -100)         // more than 0.1 s late: skip this picture
                    if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        source.seekTo(0, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
                        decoder.flush()
                        inputDone = false
                        firstPts = -1L
                    }
                }
            }
        } catch (_: InterruptedException) {
            // stop() was called
        } catch (e: Exception) {
            if (running) onError("The video could not be played: ${e.message ?: e.javaClass.simpleName}")
        } finally {
            try { codec?.stop() } catch (_: Exception) {}
            try { codec?.release() } catch (_: Exception) {}
            try { reader?.close() } catch (_: Exception) {}
            try { extractor?.release() } catch (_: Exception) {}
            encoderThread.quitSafely()
        }
    }
}

package com.hulikamote.hulikamote_camera

import android.content.Context
import android.util.Size
import android.view.OrientationEventListener
import android.view.Surface
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import java.util.concurrent.Executors

/** What produces pictures: the camera or a gallery video. */
interface Feed {
    fun stop()
}

/** How good the stream is: picture size (long side), JPEG quality and the most pictures per second. */
data class Preset(val longSide: Int, val quality: Int, val fps: Int) {
    companion object {
        fun of(name: String?) = when (name) {
            "low" -> Preset(640, 60, 15)
            "high" -> Preset(1920, 80, 25)
            else -> Preset(1280, 70, 20)
        }
    }
}

/**
 * The live camera. Only CameraX's ImageAnalysis is used (no preview on the phone screen: the app shows what the laptop gets).
 * The picture turns with the phone: held upright it streams upright, held sideways it streams wide.
 * Must be created and stopped on the main thread.
 */
class CameraFeed(
    private val context: Context,
    private val front: Boolean,
    private val preset: Preset,
    private val onJpeg: (ByteArray) -> Unit,
    private val onError: (String) -> Unit,
) : Feed {
    // Always "resumed": the camera does not depend on the Flutter activity's own life cycle.
    private val owner = object : LifecycleOwner {
        val registry = LifecycleRegistry(this)
        override val lifecycle: Lifecycle get() = registry
    }
    private val executor = Executors.newSingleThreadExecutor()
    private var provider: ProcessCameraProvider? = null
    private var orientation: OrientationEventListener? = null
    @Volatile private var stopped = false
    private var lastNs = 0L
    private val minIntervalNs = 1_000_000_000L / preset.fps

    fun start() {
        owner.registry.currentState = Lifecycle.State.RESUMED
        val future = ProcessCameraProvider.getInstance(context)
        future.addListener({
            if (stopped) return@addListener
            try {
                val cameraProvider = future.get()
                provider = cameraProvider
                val analysis = ImageAnalysis.Builder()
                    .setResolutionSelector(
                        ResolutionSelector.Builder()
                            .setResolutionStrategy(
                                ResolutionStrategy(sizeFor(preset.longSide), ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER)
                            )
                            .build()
                    )
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                analysis.setAnalyzer(executor) { image -> analyze(image) }
                cameraProvider.unbindAll()
                cameraProvider.bindToLifecycle(
                    owner,
                    if (front) CameraSelector.DEFAULT_FRONT_CAMERA else CameraSelector.DEFAULT_BACK_CAMERA,
                    analysis,
                )
                orientation = object : OrientationEventListener(context) {
                    override fun onOrientationChanged(degrees: Int) {
                        if (degrees == ORIENTATION_UNKNOWN) return
                        analysis.targetRotation = when (degrees) {
                            in 45..134 -> Surface.ROTATION_270
                            in 135..224 -> Surface.ROTATION_180
                            in 225..314 -> Surface.ROTATION_90
                            else -> Surface.ROTATION_0
                        }
                    }
                }.also { it.enable() }
            } catch (e: Exception) {
                onError("The camera could not start: ${e.message ?: e.javaClass.simpleName}")
            }
        }, ContextCompat.getMainExecutor(context))
    }

    private fun sizeFor(longSide: Int) = when {
        longSide >= 1920 -> Size(1920, 1080)
        longSide >= 1280 -> Size(1280, 720)
        else -> Size(640, 480)
    }

    private fun analyze(image: ImageProxy) {
        try {
            val now = System.nanoTime()
            if (now - lastNs < minIntervalNs) return
            lastNs = now
            onJpeg(Jpeg.encode(Yuv.of(image), preset.longSide, image.imageInfo.rotationDegrees, preset.quality))
        } catch (e: Exception) {
            onError("A camera picture could not be read: ${e.message ?: e.javaClass.simpleName}")
        } finally {
            image.close()
        }
    }

    override fun stop() {
        stopped = true
        orientation?.disable()
        try {
            provider?.unbindAll()
        } catch (_: Exception) {
        }
        owner.registry.currentState = Lifecycle.State.DESTROYED
        executor.shutdown()
    }
}

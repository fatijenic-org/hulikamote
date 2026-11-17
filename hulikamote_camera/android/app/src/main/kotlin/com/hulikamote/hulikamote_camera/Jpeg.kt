package com.hulikamote.hulikamote_camera

import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.media.Image
import androidx.camera.core.ImageProxy
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import kotlin.math.ceil
import kotlin.math.max

/** One YUV_420_888 picture (from the camera or from the video decoder): the three planes and how they are laid out. */
class Yuv(
    val width: Int, val height: Int, val crop: Rect,
    val y: ByteBuffer, val yRow: Int, val yPix: Int,
    val u: ByteBuffer, val uRow: Int, val uPix: Int,
    val v: ByteBuffer, val vRow: Int, val vPix: Int,
) {
    companion object {
        fun of(image: Image): Yuv {
            val p = image.planes
            return Yuv(image.width, image.height, image.cropRect,
                p[0].buffer, p[0].rowStride, p[0].pixelStride,
                p[1].buffer, p[1].rowStride, p[1].pixelStride,
                p[2].buffer, p[2].rowStride, p[2].pixelStride)
        }

        fun of(image: ImageProxy): Yuv {
            val p = image.planes
            return Yuv(image.width, image.height, image.cropRect,
                p[0].buffer, p[0].rowStride, p[0].pixelStride,
                p[1].buffer, p[1].rowStride, p[1].pixelStride,
                p[2].buffer, p[2].rowStride, p[2].pixelStride)
        }
    }
}

/** YUV picture -> upright JPEG. One path for both sources, so the camera and the gallery video look the same to the laptop. */
object Jpeg {
    /**
     * [rotation]: degrees (clockwise) the picture must be turned to stand upright (camera: ImageInfo.rotationDegrees,
     * video: KEY_ROTATION). A picture much larger than [longSide] is sampled down (every 2nd, 3rd ... pixel) first.
     */
    fun encode(src: Yuv, longSide: Int, rotation: Int, quality: Int): ByteArray {
        val crop = src.crop
        val x0 = crop.left and 1.inv()
        val y0 = crop.top and 1.inv()
        val srcW = crop.width() and 1.inv()
        val srcH = crop.height() and 1.inv()
        val long = max(srcW, srcH)
        val step = if (long <= longSide * 3 / 2) 1 else ceil(long / longSide.toDouble()).toInt()
        val sw = (srcW / step) and 1.inv()            // the sampled picture, before turning
        val sh = (srcH / step) and 1.inv()
        val rot = ((rotation % 360) + 360) % 360
        val turned = rot == 90 || rot == 270
        val ow = if (turned) sh else sw
        val oh = if (turned) sw else sh
        val nv21 = ByteArray(ow * oh * 3 / 2)

        // brightness
        if (rot == 0 && step == 1 && src.yPix == 1) {
            val buf = src.y.duplicate()
            for (row in 0 until oh) {
                buf.position((y0 + row) * src.yRow + x0)
                buf.get(nv21, row * ow, ow)
            }
        } else {
            for (oy in 0 until oh) {
                for (ox in 0 until ow) {
                    val sx = srcX(ox, oy, sw, rot)
                    val sy = srcY(ox, oy, sh, rot)
                    nv21[oy * ow + ox] = src.y.get((y0 + sy * step) * src.yRow + (x0 + sx * step) * src.yPix)
                }
            }
        }

        // colour: NV21 wants V then U, interleaved, at half size
        val cw = ow / 2
        val ch = oh / 2
        val csw = sw / 2
        val csh = sh / 2
        val base = ow * oh
        for (oy in 0 until ch) {
            for (ox in 0 until cw) {
                val sx = srcX(ox, oy, csw, rot)
                val sy = srcY(ox, oy, csh, rot)
                val uIndex = (y0 / 2 + sy * step) * src.uRow + (x0 / 2 + sx * step) * src.uPix
                val vIndex = (y0 / 2 + sy * step) * src.vRow + (x0 / 2 + sx * step) * src.vPix
                val at = base + oy * ow + ox * 2
                nv21[at] = src.v.get(vIndex)
                nv21[at + 1] = src.u.get(uIndex)
            }
        }

        val out = ByteArrayOutputStream(ow * oh / 6)
        YuvImage(nv21, ImageFormat.NV21, ow, oh, null).compressToJpeg(Rect(0, 0, ow, oh), quality, out)
        return out.toByteArray()
    }

    // Where a pixel of the turned picture comes from in the sampled one ([w] x [h] = the sampled picture's size).
    private fun srcX(ox: Int, oy: Int, w: Int, rot: Int) = when (rot) {
        90 -> oy
        180 -> w - 1 - ox
        270 -> w - 1 - oy
        else -> ox
    }

    private fun srcY(ox: Int, oy: Int, h: Int, rot: Int) = when (rot) {
        90 -> h - 1 - ox
        180 -> h - 1 - oy
        270 -> ox
        else -> oy
    }
}

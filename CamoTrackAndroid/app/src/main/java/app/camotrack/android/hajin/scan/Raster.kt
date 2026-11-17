package app.camotrack.android.hajin.scan

import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * An opaque RGB picture as packed ARGB ints, row by row, origin top left:
 * the scanner's own image type, so all of it runs (and is tested) on the
 * JVM. `AndroidImages.toRaster` makes one from a Bitmap.
 */
class Raster(val width: Int, val height: Int, val pixels: IntArray) {
    init { require(pixels.size == width * height) { "pixels don't fit ${width}x$height" } }

    fun r(i: Int) = (pixels[i] shr 16) and 0xFF
    fun g(i: Int) = (pixels[i] shr 8) and 0xFF
    fun b(i: Int) = pixels[i] and 0xFF

    /** Whole pixels, clamped to the picture; null when nothing's left. */
    fun cropped(box: Box): Raster? {
        val r = box.integral()
        val x0 = max(0, r.minX.toInt()); val y0 = max(0, r.minY.toInt())
        val x1 = min(width, r.maxX.toInt()); val y1 = min(height, r.maxY.toInt())
        if (x1 <= x0 || y1 <= y0) return null
        val w = x1 - x0; val h = y1 - y0
        val out = IntArray(w * h)
        for (y in 0 until h) System.arraycopy(pixels, (y0 + y) * width + x0, out, y * w, w)
        return Raster(w, h, out)
    }

    /** Stretched to w x h: averaged over each output pixel's footprint when
     *  shrinking (so thin frame lines survive), bilinear when growing. */
    fun resized(w: Int, h: Int): Raster {
        if (w == width && h == height) return this
        val shrunk = if (w < width || h < height) areaShrink(min(w, width), min(h, height)) else this
        return if (shrunk.width == w && shrunk.height == h) shrunk else shrunk.bilinear(w, h)
    }

    private fun bilinear(w: Int, h: Int): Raster {
        val out = IntArray(w * h)
        val sx = width.toDouble() / w; val sy = height.toDouble() / h
        for (y in 0 until h) for (x in 0 until w) {
            out[y * w + x] = sample((x + 0.5) * sx - 0.5, (y + 0.5) * sy - 0.5)
        }
        return Raster(w, h, out)
    }

    private fun areaShrink(w: Int, h: Int): Raster {
        // separable box filter with fractional coverage
        val tmp = Array(3) { DoubleArray(w * height) }
        val fx = width.toDouble() / w
        for (y in 0 until height) for (x in 0 until w) {
            val a = x * fx; val b = (x + 1) * fx
            var rr = 0.0; var gg = 0.0; var bb = 0.0; var total = 0.0
            var k = floor(a).toInt()
            while (k < b && k < width) {
                val cover = min(b, k + 1.0) - max(a, k.toDouble())
                if (cover > 0) {
                    val i = y * width + k
                    rr += r(i) * cover; gg += g(i) * cover; bb += b(i) * cover; total += cover
                }
                k++
            }
            val o = y * w + x
            tmp[0][o] = rr / total; tmp[1][o] = gg / total; tmp[2][o] = bb / total
        }
        val out = IntArray(w * h)
        val fy = height.toDouble() / h
        for (y in 0 until h) {
            val a = y * fy; val b = (y + 1) * fy
            for (x in 0 until w) {
                var rr = 0.0; var gg = 0.0; var bb = 0.0; var total = 0.0
                var k = floor(a).toInt()
                while (k < b && k < height) {
                    val cover = min(b, k + 1.0) - max(a, k.toDouble())
                    if (cover > 0) {
                        val i = k * w + x
                        rr += tmp[0][i] * cover; gg += tmp[1][i] * cover; bb += tmp[2][i] * cover; total += cover
                    }
                    k++
                }
                out[y * w + x] = rgb(rr / total, gg / total, bb / total)
            }
        }
        return Raster(w, h, out)
    }

    /** Bilinear sample at a pixel position (pixel centres at whole numbers), edges clamped. */
    fun sample(x: Double, y: Double): Int {
        val cx = x.coerceIn(0.0, width - 1.0); val cy = y.coerceIn(0.0, height - 1.0)
        val x0 = cx.toInt(); val y0 = cy.toInt()
        val x1 = min(x0 + 1, width - 1); val y1 = min(y0 + 1, height - 1)
        val ax = cx - x0; val ay = cy - y0
        val p00 = pixels[y0 * width + x0]; val p10 = pixels[y0 * width + x1]
        val p01 = pixels[y1 * width + x0]; val p11 = pixels[y1 * width + x1]
        fun ch(p: Int, s: Int) = ((p shr s) and 0xFF).toDouble()
        fun mix(s: Int) = (ch(p00, s) * (1 - ax) + ch(p10, s) * ax) * (1 - ay) + (ch(p01, s) * (1 - ax) + ch(p11, s) * ax) * ay
        return rgb(mix(16), mix(8), mix(0))
    }

    /** The quad (TL, TR, BR, BL as fractions) as a flat w x h picture: CIPerspectiveCorrection
     *  then a stretch, as on iPhone. A big shrink is pre-averaged so lines don't alias away. */
    fun straightened(corners: List<Pt>, w: Int, h: Int): Raster? {
        if (w <= 0 || h <= 0 || corners.size != 4) return null
        val px = corners.map { Pt(it.x * width, it.y * height) }
        val across = (hypot(px[1].x - px[0].x, px[1].y - px[0].y) + hypot(px[2].x - px[3].x, px[2].y - px[3].y)) / 2
        val down = (hypot(px[3].x - px[0].x, px[3].y - px[0].y) + hypot(px[2].x - px[1].x, px[2].y - px[1].y)) / 2
        if (across < 1 || down < 1) return null
        val shrink = min(across / w, down / h)
        val src = if (shrink >= 2.5) shrunkBy(floor(shrink / 1.5).toInt()) else this
        val sx = src.width.toDouble() / width; val sy = src.height.toDouble() / height
        val q = px.map { Pt(it.x * sx, it.y * sy) }
        val out = IntArray(w * h)
        for (y in 0 until h) {
            val v = (y + 0.5) / h
            for (x in 0 until w) {
                val p = quadPoint(q, (x + 0.5) / w, v)
                out[y * w + x] = src.sample(p.x - 0.5, p.y - 0.5)
            }
        }
        return Raster(w, h, out)
    }

    private val shrinkCache = HashMap<Int, Raster>()

    /** This picture an integer factor smaller (kept: straightening asks again and again). */
    @Synchronized fun shrunkBy(factor: Int): Raster {
        if (factor <= 1) return this
        return shrinkCache.getOrPut(factor) { resized(max(1, width / factor), max(1, height / factor)) }
    }

    /** One byte a pixel of luminance, for `StashGrid.snapped` (CG's device grey). */
    fun grey(): IntArray = IntArray(width * height) { i ->
        (0.299 * r(i) + 0.587 * g(i) + 0.114 * b(i)).roundToInt().coerceIn(0, 255)
    }

    companion object {
        fun rgb(r: Double, g: Double, b: Double): Int =
            (0xFF shl 24) or (r.roundToInt().coerceIn(0, 255) shl 16) or (g.roundToInt().coerceIn(0, 255) shl 8) or b.roundToInt().coerceIn(0, 255)

        fun rgb(r: Int, g: Int, b: Int): Int = (0xFF shl 24) or (r shl 16) or (g shl 8) or b

        fun filled(w: Int, h: Int, color: Int) = Raster(w, h, IntArray(w * h) { color })
    }
}

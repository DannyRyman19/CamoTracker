package app.camotrack.android.hajin.scan

import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

/** A point. Corners passed around the scanner are fractions of the photo
 *  (0...1, origin top left) unless a function says pixels. */
data class Pt(val x: Double, val y: Double) {
    operator fun plus(o: Pt) = Pt(x + o.x, y + o.y)
    operator fun minus(o: Pt) = Pt(x - o.x, y - o.y)
    operator fun times(k: Double) = Pt(x * k, y * k)
    fun length() = hypot(x, y)
}

/** An axis-aligned rectangle, origin top left (CGRect's fields, for the port). */
data class Box(val x: Double, val y: Double, val width: Double, val height: Double) {
    val minX get() = x
    val minY get() = y
    val maxX get() = x + width
    val maxY get() = y + height
    val midX get() = x + width / 2
    val midY get() = y + height / 2
    val isEmpty get() = width <= 0 || height <= 0

    fun offsetBy(dx: Double, dy: Double) = Box(x + dx, y + dy, width, height)
    fun insetBy(dx: Double, dy: Double) = Box(x + dx, y + dy, width - 2 * dx, height - 2 * dy)

    /** Null when they don't meet (CGRect's `isNull`). */
    fun intersection(o: Box): Box? {
        val x0 = max(minX, o.minX); val y0 = max(minY, o.minY)
        val x1 = min(maxX, o.maxX); val y1 = min(maxY, o.maxY)
        if (x1 < x0 || y1 < y0) return null
        return Box(x0, y0, x1 - x0, y1 - y0)
    }

    fun intersects(o: Box): Boolean {
        val i = intersection(o) ?: return false
        return i.width > 0 && i.height > 0
    }

    /** The smallest whole-pixel box holding it (CGRect.integral). */
    fun integral(): Box {
        val x0 = floor(minX); val y0 = floor(minY)
        return Box(x0, y0, ceil(maxX) - x0, ceil(maxY) - y0)
    }

    companion object {
        fun ltrb(l: Double, t: Double, r: Double, b: Double) = Box(l, t, r - l, b - t)
    }
}

/** Where (u, v) of the unit square lands on the quad (TL, TR, BR, BL):
 *  the perspective mapping that straightening undoes. */
internal fun quadPoint(q: List<Pt>, u: Double, v: Double): Pt {
    val sx = q[0].x - q[1].x + q[2].x - q[3].x
    val sy = q[0].y - q[1].y + q[2].y - q[3].y
    val dx1 = q[1].x - q[2].x; val dx2 = q[3].x - q[2].x
    val dy1 = q[1].y - q[2].y; val dy2 = q[3].y - q[2].y
    val det = dx1 * dy2 - dx2 * dy1
    val g = if (det == 0.0) 0.0 else (sx * dy2 - dx2 * sy) / det
    val h = if (det == 0.0) 0.0 else (dx1 * sy - sx * dy1) / det
    val a = q[1].x - q[0].x + g * q[1].x; val b = q[3].x - q[0].x + h * q[3].x
    val d = q[1].y - q[0].y + g * q[1].y; val e = q[3].y - q[0].y + h * q[3].y
    val w = g * u + h * v + 1
    return Pt((a * u + b * v + q[0].x) / w, (d * u + e * v + q[0].y) / w)
}

/** A box blur of a profile with the given radius. */
internal fun smoothed(p: DoubleArray, r: Int): DoubleArray {
    val prefix = DoubleArray(p.size + 1)
    for (i in p.indices) prefix[i + 1] = prefix[i] + p[i]
    return DoubleArray(p.size) { i ->
        val lo = max(0, i - r); val hi = min(p.size - 1, i + r)
        (prefix[hi + 1] - prefix[lo]) / (hi - lo + 1)
    }
}

/** What stands above the profile's local average (radius `r`): thin lines, not wide shapes. */
internal fun narrow(p: DoubleArray, r: Int): DoubleArray {
    val wide = smoothed(p, r)
    return DoubleArray(p.size) { max(0.0, p[it] - wide[it]) }
}

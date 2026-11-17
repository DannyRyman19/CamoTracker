package app.camotrack.android.hajin.scan

/**
 * The scanner's three outside services, behind small interfaces so the
 * logic runs on the JVM with fakes: the tile classifier and tile detector
 * (TensorFlow Lite, `TfliteModels.kt`) and text recognition (ML Kit,
 * `MlKitText.kt`).
 */

/** Names a straightened 200 px tile: classes (item ids, `x-<first id>` for a
 *  shared picture, `empty`) with confidences, best first. */
fun interface TileClassifier {
    fun classify(tile: Raster): List<Classification>
}

data class Classification(val id: String, val confidence: Float)

/** Finds stash tiles (filled or empty) in a photo: boxes in the photo's pixels. */
fun interface TileDetector {
    fun detect(image: Raster): List<Detection>
}

data class Detection(val box: Box, val confidence: Float)

/** Reads the text in a photo, a line at a time. */
fun interface TextReader {
    fun lines(image: Raster): List<TextLine>
}

/**
 * A line of text as Vision gives it on iPhone (so the port reads the same):
 * `box` is normalised with the origin at the BOTTOM left. `bottomLeft` and
 * `bottomRight` are the line's own corners (it can be tilted), in the same
 * space; without them they're the box's.
 */
data class TextLine(
    val text: String,
    val box: Box,
    val bottomLeft: Pt = Pt(box.minX, box.minY),
    val bottomRight: Pt = Pt(box.maxX, box.minY),
) {
    companion object {
        /** From a box in pixels with the origin top left (ML Kit's), on a w x h photo. */
        fun fromPixels(text: String, left: Double, top: Double, right: Double, bottom: Double, w: Int, h: Int,
                       bottomLeft: Pt? = null, bottomRight: Pt? = null): TextLine {
            val box = Box(left / w, 1 - bottom / h, (right - left) / w, (bottom - top) / h)
            fun flip(p: Pt) = Pt(p.x / w, 1 - p.y / h)
            return TextLine(text, box, bottomLeft?.let(::flip) ?: Pt(box.minX, box.minY),
                            bottomRight?.let(::flip) ?: Pt(box.maxX, box.minY))
        }
    }
}

/** A guide item, as much of it as the readers need (`hajin.json`'s items). */
data class ScanItem(val id: String, val name: String, val kind: String, val blueprint: Boolean = false)

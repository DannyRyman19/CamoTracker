package app.camotrack.android.hajin.scan

import android.graphics.Bitmap
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import java.io.Closeable

/**
 * On-device text recognition (ML Kit, Latin script), as `TextLine`s the
 * way iPhone's Vision gives them. Blocking: call off the main thread.
 */
class MlKitTextReader : TextReader, Closeable {
    private val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)

    override fun lines(image: Raster): List<TextLine> = lines(image.toBitmap())

    fun lines(bitmap: Bitmap): List<TextLine> {
        val text = Tasks.await(recognizer.process(InputImage.fromBitmap(bitmap, 0)))
        return toLines(text, bitmap.width, bitmap.height)
    }

    override fun close() = recognizer.close()

    companion object {
        fun toLines(text: Text, width: Int, height: Int): List<TextLine> =
            text.textBlocks.flatMap { block -> block.lines }.flatMap { line ->
                val words = line.elements.mapNotNull { e ->
                    val b = e.boundingBox ?: return@mapNotNull null
                    val c = e.cornerPoints
                    TextSegments.Word(e.text, b.left.toDouble(), b.top.toDouble(), b.right.toDouble(), b.bottom.toDouble(),
                                      c?.getOrNull(3)?.let { Pt(it.x.toDouble(), it.y.toDouble()) },
                                      c?.getOrNull(2)?.let { Pt(it.x.toDouble(), it.y.toDouble()) })
                }
                TextSegments.split(words, width, height)
            }
    }
}

/**
 * ML Kit joins words far apart on one baseline into a line ("ALL   9/18
 * WEAPONS   79/94 ITEMS"); Vision gives such runs as separate lines, and the
 * readers look for a lone "ALL". So a line is split wherever the gap between
 * two words is wider than the text is tall.
 */
object TextSegments {
    /** A word in pixels, origin top left; its own bottom corners when known. */
    data class Word(val text: String, val left: Double, val top: Double, val right: Double, val bottom: Double,
                    val bottomLeft: Pt? = null, val bottomRight: Pt? = null)

    fun split(words: List<Word>, width: Int, height: Int, gapFactor: Double = 1.2): List<TextLine> {
        if (words.isEmpty()) return emptyList()
        val sorted = words.sortedBy { it.left }
        val runs = ArrayList<MutableList<Word>>()
        for (w in sorted) {
            val last = runs.lastOrNull()?.last()
            val tall = last?.let { maxOf(it.bottom - it.top, w.bottom - w.top) } ?: 0.0
            if (last == null || w.left - last.right > tall * gapFactor) runs.add(mutableListOf(w)) else runs.last().add(w)
        }
        return runs.map { run ->
            TextLine.fromPixels(run.joinToString(" ") { it.text },
                                run.minOf { it.left }, run.minOf { it.top }, run.maxOf { it.right }, run.maxOf { it.bottom },
                                width, height, run.first().bottomLeft, run.last().bottomRight)
        }
    }
}

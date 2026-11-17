package app.camotrack.android.hajin.scan

import android.content.Context
import org.tensorflow.lite.Interpreter
import java.io.Closeable
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * The two TensorFlow Lite models in `assets/models` (trained by
 * `tools/stash-scan`): the tile classifier and the tile detector. Each holds
 * an interpreter; calls are serialised, so one instance can be shared.
 */
internal object ModelFiles {
    const val ICONS = "models/stash_icons.tflite"
    const val ICON_LABELS = "models/stash_icons_labels.txt"
    const val TILES = "models/stash_tiles.tflite"

    fun buffer(context: Context, path: String): ByteBuffer {
        val bytes = context.assets.open(path).use { it.readBytes() }
        return ByteBuffer.allocateDirect(bytes.size).order(ByteOrder.nativeOrder()).apply { put(bytes); rewind() }
    }

    fun options(threads: Int) = Interpreter.Options().apply { setNumThreads(threads) }
}

/** Fills a float input (1 x S x S x 3, RGB 0...255) with the picture stretched to the square. */
internal fun Raster.toInput(side: Int, into: ByteBuffer) {
    val img = resized(side, side)
    into.rewind()
    for (i in img.pixels.indices) {
        into.putFloat(img.r(i).toFloat()); into.putFloat(img.g(i).toFloat()); into.putFloat(img.b(i).toFloat())
    }
    into.rewind()
}

/** HajinStashIcons.mlmodel's counterpart: MobileNetV3 + softmax over the classes in the labels file. */
class TfliteTileClassifier(model: ByteBuffer, private val labels: List<String>, threads: Int = 2) : TileClassifier, Closeable {
    private val interpreter = Interpreter(model, ModelFiles.options(threads))
    private val side = interpreter.getInputTensor(0).shape()[1]
    private val input = ByteBuffer.allocateDirect(4 * side * side * 3).order(ByteOrder.nativeOrder())
    private val output = Array(1) { FloatArray(labels.size) }

    init {
        val classes = interpreter.getOutputTensor(0).shape().last()
        require(classes == labels.size) { "model has $classes classes, labels ${labels.size}" }
    }

    @Synchronized override fun classify(tile: Raster): List<Classification> {
        tile.toInput(side, input)
        interpreter.run(input, output)
        return output[0].indices.sortedByDescending { output[0][it] }.map { Classification(labels[it], output[0][it]) }
    }

    @Synchronized override fun close() = interpreter.close()

    companion object {
        fun fromAssets(context: Context, threads: Int = 2): TfliteTileClassifier {
            val labels = context.assets.open(ModelFiles.ICON_LABELS).bufferedReader().readLines().filter { it.isNotBlank() }
            return TfliteTileClassifier(ModelFiles.buffer(context, ModelFiles.ICONS), labels, threads)
        }
    }
}

/** HajinStashTiles.mlmodel's counterpart: a small CenterNet, the photo stretched to its square. */
class TfliteTileDetector(model: ByteBuffer, threads: Int = 2) : TileDetector, Closeable {
    private val interpreter = Interpreter(model, ModelFiles.options(threads))
    private val side = interpreter.getInputTensor(0).shape()[1]
    private val grid = interpreter.getOutputTensor(0).shape()[1]
    private val input = ByteBuffer.allocateDirect(4 * side * side * 3).order(ByteOrder.nativeOrder())
    private val output = Array(1) { Array(grid) { Array(grid) { FloatArray(5) } } }

    @Synchronized override fun detect(image: Raster): List<Detection> {
        image.toInput(side, input)
        interpreter.run(input, output)
        val flat = FloatArray(grid * grid * 5)
        var k = 0
        for (y in 0 until grid) for (x in 0 until grid) for (c in 0 until 5) flat[k++] = output[0][y][x][c]
        return TileHeatmap.decode(flat, grid, side, image.width, image.height)
    }

    @Synchronized override fun close() = interpreter.close()

    companion object {
        fun fromAssets(context: Context, threads: Int = 2) = TfliteTileDetector(ModelFiles.buffer(context, ModelFiles.TILES), threads)
    }
}

/** Decodes the detector's map: each cell (row major) holds a tile-centre score,
 *  the centre's place in the cell, and the box's size in cells. */
object TileHeatmap {
    fun decode(out: FloatArray, grid: Int, side: Int, width: Int, height: Int, threshold: Float = 0.2f): List<Detection> {
        val stride = side.toDouble() / grid
        val sx = width.toDouble() / side; val sy = height.toDouble() / side
        fun at(x: Int, y: Int, c: Int) = out[(y * grid + x) * 5 + c]
        val found = ArrayList<Detection>()
        for (y in 0 until grid) for (x in 0 until grid) {
            val v = at(x, y, 0)
            if (v < threshold) continue
            // a peak: no stronger neighbour
            var peak = true
            for (dy in -1..1) for (dx in -1..1) {
                val nx = x + dx; val ny = y + dy
                if ((dx != 0 || dy != 0) && nx in 0 until grid && ny in 0 until grid && at(nx, ny, 0) > v) peak = false
            }
            if (!peak) continue
            val cx = (x + at(x, y, 1)) * stride; val cy = (y + at(x, y, 2)) * stride
            val w = at(x, y, 3) * stride; val h = at(x, y, 4) * stride
            found.add(Detection(Box((cx - w / 2) * sx, (cy - h / 2) * sy, w * sx, h * sy), v))
        }
        return found.sortedByDescending { it.confidence }
    }
}

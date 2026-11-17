package app.camotrack.android.hajin.scan

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build

/** Bitmap <-> Raster, and photos decoded the right way up. */
fun Bitmap.toRaster(): Raster {
    val src = if (config == Bitmap.Config.ARGB_8888) this else copy(Bitmap.Config.ARGB_8888, false)
    val px = IntArray(src.width * src.height)
    src.getPixels(px, 0, src.width, 0, 0, src.width, src.height)
    // opaque, as the scanner assumes
    for (i in px.indices) px[i] = px[i] or (0xFF shl 24)
    return Raster(src.width, src.height, px)
}

fun Raster.toBitmap(): Bitmap = Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)

object AndroidImages {
    /**
     * A picked or captured photo, upright (its EXIF rotation applied, as
     * iPhone's `normalisedUp`), software-backed so its pixels can be read,
     * and at most `maxSide` on its long side.
     */
    fun decodeUpright(context: Context, uri: Uri, maxSide: Int = 4096): Bitmap? = runCatching {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, uri)) { decoder, info, _ ->
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                val long = maxOf(info.size.width, info.size.height)
                if (long > maxSide) {
                    val s = maxSide.toDouble() / long
                    decoder.setTargetSize((info.size.width * s).toInt(), (info.size.height * s).toInt())
                }
            }
        } else {
            context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it) }
        }
    }.getOrNull()
}

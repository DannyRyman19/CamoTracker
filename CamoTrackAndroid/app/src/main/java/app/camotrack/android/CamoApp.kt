package app.camotrack.android

import android.app.Application
import android.content.Context
import android.content.SharedPreferences
import app.camotrack.android.core.KeyValueStore
import app.camotrack.android.core.LocalizedText
import app.camotrack.android.core.SeedSource
import app.camotrack.android.i18n.Strings

class CamoApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Strings.init(this)
        // Data text (weapon and camo names) follows the same language as the app's own
        LocalizedText.preferredLanguages = { listOf(Strings.language, "en") }
        AppState.start(this)
    }
}

/** Progress and settings, kept as the iPhone app keeps them in UserDefaults. */
class PrefsStore(context: Context, name: String = "camotrack") : KeyValueStore {
    private val prefs: SharedPreferences = context.getSharedPreferences(name, Context.MODE_PRIVATE)
    override fun getString(key: String): String? = prefs.all[key] as? String
    override fun putString(key: String, value: String?) { prefs.edit().apply { if (value == null) remove(key) else putString(key, value) }.apply() }
    override fun getBoolean(key: String, default: Boolean): Boolean = prefs.all[key] as? Boolean ?: default
    override fun putBoolean(key: String, value: Boolean) { prefs.edit().putBoolean(key, value).apply() }
    override fun getInt(key: String): Int? = prefs.all[key] as? Int
    override fun putInt(key: String, value: Int?) { prefs.edit().apply { if (value == null) remove(key) else putInt(key, value) }.apply() }
    override fun contains(key: String): Boolean = prefs.contains(key)
    override fun remove(key: String) { prefs.edit().remove(key).apply() }
    override fun keys(): Set<String> = prefs.all.keys
}

/** The bundled data, from assets/seeds (copied from the iPhone app's Resources at build time). */
class AssetSeeds(private val context: Context) : SeedSource {
    override fun read(fileName: String): String? =
        runCatching { context.assets.open("seeds/$fileName").bufferedReader().use { it.readText() } }.getOrNull()
}

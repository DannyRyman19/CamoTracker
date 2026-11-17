package app.camotrack.android.i18n

import android.content.Context
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.util.Locale

/**
 * The app's own text, keyed exactly as the iPhone app's Localizable.strings
 * (assets/strings/<lang>.json, made by tools/convert_strings.py), so a screen
 * ports with `"mw4.ui.x".localized()` becoming `L("mw4.ui.x")`.
 *
 * The language follows the phone unless one is picked in Customise (the same
 * `mw4_language` setting as on iPhone). A key missing in a language falls
 * back to English, then to the key itself.
 */
object Strings {
    /** Every language the app is translated into, in its own name. */
    val supported = listOf(
        "en" to "English", "de" to "Deutsch", "es" to "Español", "fr" to "Français",
        "it" to "Italiano", "nl" to "Nederlands", "pt" to "Português",
    )
    const val KEY = "mw4_language"

    @Serializable
    private data class Table(val strings: Map<String, String> = emptyMap(), val plurals: Map<String, Plural> = emptyMap())

    @Serializable
    private data class Plural(val format: String, val forms: Map<String, String>)

    private val json = Json { ignoreUnknownKeys = true }
    private val tables = mutableMapOf<String, Table>()
    private lateinit var app: Context

    /** The language in use: the one picked in Customise, else the phone's if supported, else English. */
    var language: String = "en"
        private set

    fun init(context: Context) {
        app = context.applicationContext
        refresh()
    }

    /** Re-reads the Customise choice (call after it changes). */
    fun refresh() {
        val picked = app.getSharedPreferences("settings", Context.MODE_PRIVATE).getString(KEY, null)
        val phone = Locale.getDefault().language
        language = listOf(picked, phone).firstOrNull { code -> supported.any { it.first == code } } ?: "en"
    }

    private fun table(lang: String): Table = synchronized(tables) {
        tables.getOrPut(lang) {
            runCatching {
                app.assets.open("strings/$lang.json").bufferedReader().use { json.decodeFromString<Table>(it.readText()) }
            }.getOrDefault(Table())
        }
    }

    fun raw(key: String): String =
        table(language).strings[key] ?: table("en").strings[key] ?: key

    /** The text for `key`, with `args` put in (Java format: %s, %d, %1$s). */
    fun get(key: String, vararg args: Any?): String {
        val text = raw(key)
        return if (args.isEmpty()) text else runCatching { String.format(Locale(language), text, *args) }.getOrDefault(text)
    }

    /** A counted text from the iPhone app's .stringsdict: `count` picks the form. */
    fun plural(key: String, count: Int, vararg args: Any?): String {
        val p = table(language).plurals[key] ?: table("en").plurals[key] ?: return get(key, count, *args)
        val form = p.forms[category(count)] ?: p.forms["other"] ?: return key
        return runCatching { String.format(Locale(language), form, count, *args) }.getOrDefault(form)
    }

    // One and other cover every language here; French counts 0 as one.
    private fun category(n: Int): String = when {
        language == "fr" && (n == 0 || n == 1) -> "one"
        n == 1 -> "one"
        else -> "other"
    }
}

/** Shorthand for screens: L("mw4.ui.section.camos"). */
fun L(key: String, vararg args: Any?): String = Strings.get(key, *args)

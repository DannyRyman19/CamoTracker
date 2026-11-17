package app.camotrack.android.core

/**
 * Where progress and settings are kept (the iOS app's UserDefaults). The app
 * backs it with SharedPreferences; tests use [InMemoryKeyValueStore]. Values
 * are the same JSON the iOS app stores, as strings.
 */
interface KeyValueStore {
    fun getString(key: String): String?
    /** null removes the key. */
    fun putString(key: String, value: String?)
    fun getBoolean(key: String, default: Boolean = false): Boolean
    fun putBoolean(key: String, value: Boolean)
    fun getInt(key: String): Int?
    fun putInt(key: String, value: Int?)
    fun contains(key: String): Boolean
    fun remove(key: String)
    fun keys(): Set<String>
}

class InMemoryKeyValueStore : KeyValueStore {
    private val values = linkedMapOf<String, Any>()

    @Synchronized override fun getString(key: String): String? = values[key] as? String
    @Synchronized override fun putString(key: String, value: String?) {
        if (value == null) values.remove(key) else values[key] = value
    }
    @Synchronized override fun getBoolean(key: String, default: Boolean): Boolean = values[key] as? Boolean ?: default
    @Synchronized override fun putBoolean(key: String, value: Boolean) { values[key] = value }
    @Synchronized override fun getInt(key: String): Int? = values[key] as? Int
    @Synchronized override fun putInt(key: String, value: Int?) {
        if (value == null) values.remove(key) else values[key] = value
    }
    @Synchronized override fun contains(key: String): Boolean = key in values
    @Synchronized override fun remove(key: String) { values.remove(key) }
    @Synchronized override fun keys(): Set<String> = values.keys.toSet()
}

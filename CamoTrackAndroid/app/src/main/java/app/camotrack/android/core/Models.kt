package app.camotrack.android.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.util.Locale

/** The decoder every data file goes through. Unknown keys (`_note`) are ignored, as Swift's decoders do. */
val CamoJson: Json = Json {
    ignoreUnknownKeys = true
    encodeDefaults = false
    explicitNulls = false
}

/**
 * Per-language text carried in the network JSON (`{"en": "...", "de": "..."}`),
 * so content added over the air shows in every language without an app update.
 */
@Serializable(with = LocalizedTextSerializer::class)
data class LocalizedText(val values: Map<String, String>) {
    constructor(value: String) : this(mapOf("en" to value))

    /** The user's language, else English, else whatever translation exists. */
    fun resolved(languages: List<String> = preferredLanguages()): String {
        for (code in languages) values[code]?.let { return it }
        return values["en"] ?: values.values.firstOrNull() ?: ""
    }

    companion object {
        /** The languages to try, in order. The UI can replace it (an in-app language override). */
        @Volatile
        var preferredLanguages: () -> List<String> = { listOf(Locale.getDefault().language) }
    }
}

object LocalizedTextSerializer : KSerializer<LocalizedText> {
    private val delegate = MapSerializer(String.serializer(), String.serializer())
    override val descriptor: SerialDescriptor = delegate.descriptor
    override fun serialize(encoder: Encoder, value: LocalizedText) = delegate.serialize(encoder, value.values)
    override fun deserialize(decoder: Decoder): LocalizedText = LocalizedText(delegate.deserialize(decoder))
}

// MARK: - Weapon catalog (shared across every mode)

@Serializable
data class WeaponCatalog(
    val version: String,
    /** The roster size at launch, frozen; absent falls back to the live weapon count. */
    val baseWeaponCount: Int? = null,
    /** The Weapon Prestige stages after a weapon's normal levels, in order. */
    val weaponPrestige: List<PrestigeStage>? = null,
    /** Camos earned by Weapon Prestige, the same in every mode. */
    val prestigeCamos: List<PrestigeCamo>? = null,
    val categories: List<WeaponCategory>,
)

/** A Weapon Prestige camo. `stage` counts from 1, null = the last stage. */
@Serializable
data class PrestigeCamo(
    val name: LocalizedText,
    val stage: Int? = null,
    val level: Int? = null,
    val afterWeaponMaxLevel: Boolean? = null,
    val imageURL: String? = null,
    val colors: List<String>? = null,
    /** Per-weapon name/image/level/colours, keyed by `weaponId` as a string. */
    val byWeapon: Map<String, PrestigeCamoOverride>? = null,
    /** Earned on every weapon once this many weapons reach its stage and level. */
    val weaponsNeeded: Int? = null,
)

@Serializable
data class PrestigeCamoOverride(
    val name: LocalizedText? = null,
    val imageURL: String? = null,
    val level: Int? = null,
    val colors: List<String>? = null,
)

/** One Weapon Prestige stage; `maxLevel` null = the weapon's own max again. */
@Serializable
data class PrestigeStage(val name: LocalizedText, val maxLevel: Int? = null)

@Serializable
data class WeaponCategory(
    val categoryId: Int,
    val name: LocalizedText,
    val weapons: List<WeaponEntry>,
)

@Serializable
data class WeaponEntry(
    val weaponId: Int,
    val name: LocalizedText,
    val imageURL: String? = null,
    val maxLevel: Int,
    val unlockRequirement: LocalizedText? = null,
    /** "battlePass", "event", "armory", "challenge"; absent = unlocked by default/by level. */
    val acquiredBy: String? = null,
) {
    /** The level this weapon unlocks at: the first number in its resolved unlock sentence. */
    fun unlockLevel(languages: List<String> = LocalizedText.preferredLanguages()): Int? {
        if (acquiredBy != null) return null
        val text = unlockRequirement?.resolved(languages) ?: return null
        return DIGITS.find(text)?.value?.toIntOrNull()
    }

    private companion object {
        val DIGITS = Regex("\\d+")
    }
}

// MARK: - Per-mode data (multiplayer.json / warzone.json / dmz.json)

@Serializable
data class ModeFile(
    val version: String,
    val mode: String,
    val weaponCamos: List<WeaponCamoEntry>,
    val objectives: List<ObjectiveCategory>,
    val mastery: MasteryConfig? = null,
    val completionist: CompletionistConfig? = null,
    /** Another mode whose camo list and Completionist progress this mode shares. */
    val trackFrom: String? = null,
    /** true keeps every Special shut until all Military camos are earned. */
    val specialsAfterMilitary: Boolean? = null,
    /** true hides this mode's tab (not playable yet). */
    val hidden: Boolean? = null,
)

@Serializable
data class CompletionistConfig(
    val steps: List<CompletionistStepConfig>? = null,
    val final: CompletionistFinalConfig? = null,
)

@Serializable
data class CompletionistStepConfig(
    val name: LocalizedText? = null,
    val colors: List<String>? = null,
    val imageURL: String? = null,
    val requirement: Requirement? = null,
    val byCategory: Map<String, Requirement>? = null,
    val byWeapon: Map<String, Requirement>? = null,
    /** "weapon", "category" or "mode". */
    val unlock: String? = null,
    val needed: Int? = null,
    val neededByCategory: Map<String, Int>? = null,
)

@Serializable
data class CompletionistFinalConfig(
    val enabled: Boolean? = null,
    val name: LocalizedText? = null,
    val colors: List<String>? = null,
    val imageURL: String? = null,
    val harmonicBreaksNeeded: Int? = null,
)

@Serializable
data class MasteryConfig(
    /** "count" (absent), "challenge" or "mode". */
    val unlock: String? = null,
    val tier1: MasteryTierConfig? = null,
    val tier2: MasteryTierConfig? = null,
    val tier3: MasteryTierConfig? = null,
)

@Serializable
data class MasteryTierConfig(
    val kind: String? = null,
    val name: LocalizedText? = null,
    val weaponsNeeded: Int? = null,
    val colors: List<String>? = null,
    val imageURL: String? = null,
    val requirement: Requirement? = null,
    val byCategory: Map<String, Requirement>? = null,
    val byWeapon: Map<String, Requirement>? = null,
    val unlock: String? = null,
    val needed: Int? = null,
)

@Serializable
data class WeaponCamoEntry(val weaponId: Int, val camos: List<ChallengeItem>)

/** A mode's objective category (Swift's `Category`). */
@Serializable
data class ObjectiveCategory(
    val categoryId: Int,
    val name: LocalizedText,
    val items: List<ChallengeItem>,
    /** true: one track across every mode with this categoryId. */
    val shared: Boolean? = null,
)

/** A camo tier or an objective (sub-)tier: the same node either way. */
@Serializable
data class ChallengeItem(
    val itemId: Int,
    val name: LocalizedText,
    val imageURL: String? = null,
    val tier: Int? = null,
    val unlockLevel: Int? = null,
    val requirement: Requirement? = null,
    val children: List<ChallengeItem>,
    /** "military" or "special". */
    val group: String? = null,
    val section: LocalizedText? = null,
    /** On the weapon's page but not part of the camo chain. */
    val extra: Boolean? = null,
    /** The itemId whose running count this camo reads. */
    val counter: Int? = null,
    /** "yyyy-MM-dd", UTC days, both inclusive. */
    val starts: String? = null,
    val ends: String? = null,
    /** false: children in any order. */
    val ordered: Boolean? = null,
    /** true: waits for every other child. */
    val afterSiblings: Boolean? = null,
    /** Opens once the weapon has this Completionist camo (0..2 steps, 3 final). */
    val afterCompletionist: Int? = null,
    /** Opens once the camo with this itemId on the same weapon is earned. */
    val afterItem: Int? = null,
) {
    enum class Window { UNDATED, UPCOMING, LIVE, ENDED }

    fun window(now: Instant = Instant.now()): Window {
        val start = starts?.let(::dayStart)
        // `ends` is inclusive: live until the end of that day (UTC)
        val end = ends?.let(::dayStart)?.plusSeconds(86_400)
        if (start == null && end == null) return Window.UNDATED
        if (start != null && now < start) return Window.UPCOMING
        if (end != null && now >= end) return Window.ENDED
        return Window.LIVE
    }

    val endDate: Instant? get() = ends?.let(::dayStart)

    val isLeaf: Boolean get() = children.isEmpty()

    companion object {
        /** Midnight UTC of a "yyyy-MM-dd" day; null for anything else. */
        fun dayStart(day: String): Instant? =
            runCatching { LocalDate.parse(day).atStartOfDay().toInstant(ZoneOffset.UTC) }.getOrNull()
    }
}

@Serializable
data class Requirement(
    val amount: Int,
    val unit: String,
    val description: LocalizedText,
    val lead: LocalizedText? = null,
    val byMode: List<ModeChallenge>? = null,
)

@Serializable
data class ModeChallenge(val mode: String, val description: LocalizedText)

/** Where an objective can be earned: every mode, or only some. */
sealed interface ObjectiveScope {
    data object AllModes : ObjectiveScope
    data class Only(val modes: List<String>) : ObjectiveScope
}

/** A time-limited objective live now, with its category (progress is keyed by it). */
data class LiveObjective(val categoryId: Int, val item: ChallengeItem) {
    val id: String get() = "$categoryId-${item.itemId}"
}

// MARK: - Manifest

@Serializable
data class Manifest(
    val catalog: Entry,
    val modes: Map<String, Entry>,
    val notification: Announcement? = null,
    val guides: Map<String, Entry>? = null,
) {
    @Serializable
    data class Entry(val version: String, val path: String)

    /** The "new content" notification's words, or `silent`. */
    @Serializable
    data class Announcement(
        val title: LocalizedText? = null,
        val body: LocalizedText? = null,
        val silent: Boolean? = null,
        val id: String? = null,
        val link: String? = null,
    )
}

package app.camotrack.android.services

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import app.camotrack.android.R
import app.camotrack.android.core.GameTracker
import app.camotrack.android.core.KeyValueStore
import app.camotrack.android.i18n.L

/**
 * The unlockable launcher icons (iOS AppIcons.swift): the usual icon's
 * lettering over a camo's picture. Earn the camo and its icon unlocks; Gold's
 * is free, the rest come with Premium too; Flashpoint needs every Mastery
 * camo in every mode. On Android each is a launcher alias in the manifest
 * (`.Icon<Name>`), and switching enables one and disables the rest.
 */
enum class AppIconChoice(val alias: String, val preview: Int) {
    STANDARD("IconDefault", R.drawable.icon_preview),
    GOLD("IconGold", R.drawable.icon_preview_gold),
    PLATINUM("IconPlatinum", R.drawable.icon_preview_platinum),
    HARMONIC_BREAK("IconHarmonicBreak", R.drawable.icon_preview_harmonic_break),
    DIVERGENCE("IconDivergence", R.drawable.icon_preview_divergence),
    MERCURIAL_DRIFT("IconMercurialDrift", R.drawable.icon_preview_mercurial_drift),
    POLYATOMIC_REFORGED("IconPolyatomicReforged", R.drawable.icon_preview_polyatomic_reforged),
    ORION_REFORGED("IconOrionReforged", R.drawable.icon_preview_orion_reforged),
    PARALLAX("IconParallax", R.drawable.icon_preview_parallax),
    DAMASCUS_REFORGED("IconDamascusReforged", R.drawable.icon_preview_damascus_reforged),
    EMPYROS("IconEmpyros", R.drawable.icon_preview_empyros),
    CHIRAL("IconChiral", R.drawable.icon_preview_chiral),
    RIPPLE_TIDE("IconRippleTide", R.drawable.icon_preview_ripple_tide),
    HELIO("IconHelio", R.drawable.icon_preview_helio),
    FLASHPOINT("IconFlashpoint", R.drawable.icon_preview_flashpoint);

    /** Gold is the free one. */
    val needsPremium: Boolean get() = this != STANDARD && this != GOLD

    /** Which Completionist step (0 Gold … 3 the final camo) this is, if any. */
    private val step: Int?
        get() = when (this) { GOLD -> 0; PLATINUM -> 1; HARMONIC_BREAK -> 2; DIVERGENCE -> 3; else -> null }

    /** Which mode's Mastery tier this is, if any. */
    private val mastery: Pair<String, Int>?
        get() = when (this) {
            MERCURIAL_DRIFT -> "multiplayer" to 1; POLYATOMIC_REFORGED -> "multiplayer" to 2; ORION_REFORGED -> "multiplayer" to 3
            PARALLAX -> "warzone" to 1; DAMASCUS_REFORGED -> "warzone" to 2; EMPYROS -> "warzone" to 3
            CHIRAL -> "dmz" to 1; RIPPLE_TIDE -> "dmz" to 2; HELIO -> "dmz" to 3
            else -> null
        }

    /** The camo's name, as the rest of the app shows it. */
    fun title(t: GameTracker): String {
        step?.let { s ->
            val track = t.completionist("multiplayer")
            return if (s < track.steps.size) track.steps[s].displayName() else track.final.displayName()
        }
        mastery?.let { (mode, tier) -> return t.masteryCamos(mode).getOrNull(tier - 1)?.displayName() ?: name }
        if (this == FLASHPOINT) return t.game.capstone?.name?.resolved() ?: "Flashpoint"
        return L("mw4.ui.app_icon.standard")
    }

    /** What earns it, for a locked one. */
    fun requirement(t: GameTracker): String = when {
        step != null -> L("mw4.ui.app_icon.need_weapon", title(t))
        mastery != null -> L("mw4.ui.app_icon.need_mode", title(t), L(t.modeNameKey(mastery!!.first)))
        this == FLASHPOINT -> L("ct.app_icon.need_all_mastery", title(t))
        else -> ""
    }

    /** Earned: the camo on any weapon in any mode, that mode's Mastery tier, or every Mastery camo. */
    fun isEarned(t: GameTracker): Boolean {
        step?.let { s ->
            return t.modeIds.any { mode ->
                if (s < t.completionist(mode).steps.size) t.completionistCount(mode, s) > 0
                else t.finalEnabled(mode) && t.finalCamoCount(mode) > 0
            }
        }
        mastery?.let { (mode, tier) -> return t.isMode(mode) && t.isMasteryAchieved(mode, tier) }
        if (this == FLASHPOINT) return t.isGlobalMasteryAchieved
        return true
    }
}

object AppIcons {
    /** Where the manifest declares the icon aliases: the code's package, not the app id (a debug build can add a suffix to that). */
    private const val NAMESPACE = "app.camotrack.android"

    private const val KEY = "ct_app_icon"
    /** Icons already earned when last looked (iOS IconUnlocks), so each new one is told once. */
    const val KNOWN_KEY = "ct_icons_known"

    fun current(store: KeyValueStore): AppIconChoice =
        store.getString(KEY)?.let { runCatching { AppIconChoice.valueOf(it) }.getOrNull() } ?: AppIconChoice.STANDARD

    /** Switches the launcher icon. The home screen picks it up in a moment. */
    fun pick(context: Context, store: KeyValueStore, choice: AppIconChoice) {
        val pm = context.packageManager
        // The new one on first, so the app is never without a launcher entry
        val ordered = listOf(choice) + AppIconChoice.entries.filter { it != choice }
        for (c in ordered) {
            pm.setComponentEnabledSetting(
                ComponentName(context, "$NAMESPACE.${c.alias}"),
                if (c == choice) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP,
            )
        }
        store.putString(KEY, choice.name)
    }

    /**
     * After a restore from backup (or an update) the saved choice comes back
     * but the launcher entries don't: puts the saved icon back if they differ.
     */
    fun reapply(context: Context, store: KeyValueStore) {
        val choice = current(store)
        val state = context.packageManager.getComponentEnabledSetting(ComponentName(context, "$NAMESPACE.${choice.alias}"))
        val enabled = state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED ||
            (state == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT && choice == AppIconChoice.STANDARD)
        if (!enabled) pick(context, store, choice)
    }

    /**
     * The icon earned since last time, if any (the latest when several). The
     * first look only notes what's earned, so an existing player isn't told
     * about every icon at once.
     */
    fun newlyEarned(t: GameTracker, store: KeyValueStore): AppIconChoice? {
        val earned = AppIconChoice.entries.filter { it != AppIconChoice.STANDARD && it.isEarned(t) }
        val known = store.getString(KNOWN_KEY)?.split(",")?.filter { it.isNotEmpty() }
        if (known == null) {
            store.putString(KNOWN_KEY, earned.joinToString(",") { it.name })
            return null
        }
        val fresh = earned.filter { it.name !in known }
        if (fresh.isEmpty()) return null
        store.putString(KNOWN_KEY, (known + fresh.map { it.name }).distinct().joinToString(","))
        return fresh.last()
    }
}

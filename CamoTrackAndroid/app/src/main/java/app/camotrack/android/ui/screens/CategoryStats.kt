package app.camotrack.android.ui.screens

import app.camotrack.android.core.GameTracker
import app.camotrack.android.core.MasteryKind
import app.camotrack.android.core.WeaponCategory
import app.camotrack.android.i18n.L
import app.camotrack.android.ui.CamoGold
import app.camotrack.android.ui.PlatinumColors
import app.camotrack.android.ui.Stat
import app.camotrack.android.ui.colors
import app.camotrack.android.ui.name
import app.camotrack.android.ui.tint

/**
 * What a mode-wide step still waits for ("Needs 33 Platinum"), null once
 * it's open (iOS's CategoryStats.Locks).
 */
class Locks(private val t: GameTracker, private val mode: String) {
    private val track = t.completionist(mode)

    val harmonic: String?
        get() {
            val gate = t.completionistModeGateProgress(mode, 2)
            if (gate.done >= gate.total) return null
            return needs(gate.total, track.steps[1].name)
        }

    val final: String?
        get() {
            val needed = t.harmonicBreaksNeeded(mode)
            val have = t.harmonicBreakCount(mode)
            if (needed <= 0 || have >= needed) return null
            return needs(needed, track.steps[2].name)
        }

    fun mastery(tier: Int): String? {
        if (t.masteryKind(mode, tier) != MasteryKind.MODE || t.isModeMasteryAvailable(mode, tier)) return null
        if (tier == 1) return needs(t.weaponCount(mode), t.lastCompletionist(mode).name)
        return L("ct.lock.needs_camo", t.masteryCamos(mode)[tier - 2].name)
    }

    companion object {
        fun needs(count: Int, camo: String) = L("ct.lock.needs", count, camo)
    }
}

/** A weapon class's Gold, Platinum, Harmonic Break and final-camo rings. */
fun categoryStats(t: GameTracker, category: WeaponCategory, mode: String): List<Stat> {
    val count = category.weapons.size
    fun fraction(n: Int) = if (count > 0) n.toDouble() / count else 0.0
    val track = t.completionist(mode)
    val locks = Locks(t, mode)
    val gold = t.goldWeaponCount(category, mode)
    val platinum = track.steps[1]
    val platinumCount = t.categoryCompletionistCount(category, mode, 1)
    val harmonic = track.steps[2]
    val harmonicCount = t.categoryCompletionistCount(category, mode, 2)
    val final = track.final
    val finalCount = t.categoryFinalCount(category, mode)
    val stats = mutableListOf(
        Stat("$gold/$count", track.steps[0].name, if (count > 0 && gold == count) track.steps[0].colors else null,
            t.weaponCategoryProgressFraction(category, mode), CamoGold),
        Stat("$platinumCount/$count", platinum.name, if (count > 0 && platinumCount == count) platinum.colors else null,
            fraction(platinumCount), platinum.tint, platinum.colors,
            lockedHint = if (platinumCount == 0 && gold < count) Locks.needs(count, track.steps[0].name) else null),
        Stat("$harmonicCount/$count", harmonic.name, if (count > 0 && harmonicCount == count) harmonic.colors else null,
            fraction(harmonicCount), harmonic.tint, harmonic.colors, lockedHint = if (harmonicCount == 0) locks.harmonic else null),
    )
    if (t.finalEnabled(mode)) {
        stats += Stat("$finalCount/$count", final.name, if (count > 0 && finalCount == count) final.colors else null,
            fraction(finalCount), final.tint, final.colors, lockedHint = if (finalCount == 0) locks.final else null)
    }
    return stats
}

/** The home tab's summary: Gold, Platinum, Harmonic Break, then the final camo or the Mastery tier, then 100%+. */
fun summaryStats(t: GameTracker, mode: String): List<Stat> {
    val total = t.launchRoster(mode)
    fun capped(n: Int) = t.launchProgress(n, mode).done
    fun fraction(done: Int, of: Int) = if (of > 0) done.toDouble() / of else 0.0
    val track = t.completionist(mode)
    val completeCount = capped(t.totalGoldWeaponCount(mode))
    val harmonic = track.steps[2]
    val harmonicCount = capped(t.harmonicBreakCount(mode))
    val final = track.final
    val finalCount = capped(t.finalCamoCount(mode))
    val tier = (1..3).firstOrNull { !t.isMasteryAchieved(mode, it) } ?: 3
    val mastery = t.masteryCamos(mode)[tier - 1]
    val masteryProgress = t.masteryProgress(mode, tier)
    val masteryDone = t.isMasteryAchieved(mode, tier)
    val locks = Locks(t, mode)
    val gold = track.steps[0]
    val platinum = track.steps[1]
    val platinumCount = capped(t.completionistCount(mode, 1))
    val stats = mutableListOf(
        Stat("$completeCount/$total", gold.name, if (total > 0 && completeCount == total) gold.colors else null,
            fraction(completeCount, total), CamoGold),
        Stat("$platinumCount/$total", platinum.name, if (total > 0 && platinumCount == total) platinum.colors else null,
            fraction(platinumCount, total), platinum.tint, platinum.colors),
        Stat("$harmonicCount/$total", harmonic.name, if (total > 0 && harmonicCount == total) harmonic.colors else null,
            fraction(harmonicCount, total), harmonic.tint, harmonic.colors, lockedHint = if (harmonicCount == 0) locks.harmonic else null),
    )
    val hasFinal = t.finalEnabled(mode)
    val divergenceDone = !hasFinal || (total > 0 && finalCount >= total)
    val hasMastery = t.game.hasAccountMastery
    if (divergenceDone) {
        if (hasMastery) {
            stats += Stat("${masteryProgress.done}/${masteryProgress.total}", mastery.name, if (masteryDone) mastery.colors else null,
                fraction(masteryProgress.done, masteryProgress.total), mastery.tint, mastery.colors,
                lockedHint = if (masteryProgress.done == 0) locks.mastery(tier) else null)
        }
    } else {
        stats += Stat("$finalCount/$total", final.name, null, fraction(finalCount, total), final.tint, final.colors,
            lockedHint = if (finalCount == 0) locks.final else null)
    }
    val showsHundred = if (hasMastery) t.isMasteryAchieved(mode, 3) else (if (hasFinal) finalCount else harmonicCount) >= total
    if (showsHundred) {
        val full = t.fullRosterFinalProgress(mode)
        stats += Stat("${full.done}/${full.total}", L("mw4.ui.stats.100_plus"), if (t.is100PlusAchieved(mode)) PlatinumColors else null,
            fraction(full.done, full.total), PlatinumColors[0], PlatinumColors)
    }
    return stats
}

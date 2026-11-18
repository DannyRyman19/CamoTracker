package app.camotrack.android

import app.camotrack.android.core.ChallengeItem
import app.camotrack.android.services.Premium
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Debug builds only: fills in a believable player for store screenshots
 * (`adb shell am start -n app.camotrack.android/.MainActivity --ez debug_seed true`).
 */
object DebugSeed {
    private const val MP = "multiplayer"

    fun run() {
        if (!BuildConfig.DEBUG) return
        AppState.scope.launch {
            val t = AppState.tracker
            repeat(100) { if (t.weapons(MP).isEmpty()) delay(100) }
            AppState.store.putBoolean(AppState.HAS_ONBOARDED, true)
            Premium.fakeBuy()
            t.isPremium = true
            AppState.pickMode(MP)

            val weapons = t.weapons(MP)
            fun leaves(id: Int): List<ChallengeItem> = t.camos(id, MP).flatMap(t::leafItems)
            fun finishCamos(id: Int) {
                val w = t.weapon(id) ?: return
                t.setLevel(t.maxLevel(w), w)
                for (c in leaves(id)) {
                    if (t.isCamoComplete(MP, id, c)) continue
                    val req = c.requirement
                    if (req != null) t.setCamoAmount(MP, id, c, req.amount)
                    else if (t.militaryLevel(MP, id, c) == null) t.toggleCamo(MP, id, c)
                }
            }
            fun finishStep(id: Int, step: Int) {
                if (t.isCompletionistComplete(MP, id, step)) return
                val req = t.completionistRequirement(MP, id, step)
                if (req != null) t.setCompletionistAmount(MP, id, step, req.amount) else t.toggleCompletionist(MP, id, step)
            }

            // Everything partway: levels and a share of Military
            weapons.forEachIndexed { i, w ->
                val max = t.maxLevel(w)
                t.setLevel(maxOf(2, max * (25 + (i * 37) % 60) / 100), w)
            }
            // Gold on a good spread, the next step on the Assault Rifles and SMGs
            val gold = listOf(0, 1, 2, 3, 4, 19, 20, 21, 33, 5, 6, 7, 22, 23, 34, 8, 24, 9, 11, 13, 15, 16)
            gold.forEach { finishCamos(it); finishStep(it, 0) }
            listOf(0, 1, 2, 3, 4, 19, 20, 21, 33, 5, 6, 7, 22, 23, 34).forEach { if (t.isCompletionistAvailable(MP, it, 1)) finishStep(it, 1) }
            // Specials partway on a few more
            listOf(10, 12, 14, 26, 28).forEach { id ->
                val w = t.weapon(id) ?: return@forEach
                t.setLevel(t.maxLevel(w), w)
                leaves(id).filter { it.group != "military" }.forEachIndexed { k, c ->
                    val req = c.requirement ?: return@forEachIndexed
                    t.setCamoAmount(MP, id, c, if (k < 2) req.amount else req.amount * 2 / 5)
                }
            }
            // The pinned weapon: Military done, specials under way
            val pinned = 25
            t.weapon(pinned)?.let { w ->
                t.setLevel(t.maxLevel(w), w)
                leaves(pinned).filter { it.group != "military" }.forEachIndexed { k, c ->
                    val req = c.requirement ?: return@forEachIndexed
                    t.setCamoAmount(MP, pinned, c, when (k) { 0 -> req.amount; 1 -> req.amount * 3 / 5; else -> 0 })
                }
            }
            t.pin(13)
            t.pin(pinned)

            // DMZ: a level, cash, a stocked stash and a couple of things tracked
            val h = app.camotrack.android.ui.hajin.Hajin.store
            h.setLevel(27)
            h.setCash(184_500)
            val items = h.guide?.items.orEmpty()
            items.filter { it.kind == "Ingredient" || it.kind == "Resource" || it.kind == "Valuable" }
                .forEachIndexed { i, it ->
                    if (it.kind == "Resource") h.setCount(listOf(312, 185, 240, 96)[i % 4], it.id)
                    else if (i % 3 != 2) h.setCount(1 + (i * 7) % 9, it.id)
                }
            items.filter { it.kind == "FOB Upgrade" }.take(2).forEach { if (!h.isTracked(it.id)) h.toggleTracked(it.id) }
            AppState.touch()
        }
    }
}

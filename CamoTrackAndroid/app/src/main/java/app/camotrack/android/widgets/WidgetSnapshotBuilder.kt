package app.camotrack.android.widgets

import app.camotrack.android.core.GameTracker
import app.camotrack.android.core.HexColor
import app.camotrack.android.core.MasteryCamo
import app.camotrack.android.core.WeaponEntry

/**
 * The widgets' figures from the tracker (iOS TrackerViewModel.widgetSnapshot):
 * every mode played with its Completionist counts and Mastery tiers, the
 * pinned weapon in [startMode] with its next camo, and the overall ring.
 * [text] translates a string key (the app's `L`; tests pass their own).
 */
fun GameTracker.widgetSnapshot(startMode: String, text: (String, Array<out Any?>) -> String): WidgetSnapshot? {
    if (catalog == null) return null
    fun t(key: String, vararg args: Any?) = text(key, args)
    fun MasteryCamo.label() = dataName() ?: t(nameKey)

    val modes = visibleModes.map { mode ->
        val roster = launchRoster(mode)
        val steps = completionistCamos(mode).mapIndexed { index, camo ->
            WidgetSnapshot.Step(camo.label(), launchProgress(completionistCount(mode, index), mode).done, roster, HexColor.toHex(camo.color))
        }
        // Black Ops has no account Mastery after the weapon camos
        val mastery = if (!game.hasAccountMastery) emptyList() else masteryCamos(mode).take(3).mapIndexed { index, camo ->
            val tier = index + 1
            val progress = masteryProgress(mode, tier)
            val total = maxOf(progress.total, 1)
            val done = if (isMasteryAchieved(mode, tier)) total else minOf(progress.done, progress.total)
            WidgetSnapshot.Step(camo.label(), done, total, HexColor.toHex(camo.color))
        }
        WidgetSnapshot.Mode(mode, t(modeNameKey(mode)), HexColor.toHex(modeAccent(mode)),
            trueCompletionFraction(mode), weaponCount(mode), steps, mastery)
    }
    val start = startMode.takeIf { it in visibleModes } ?: visibleModes.first()
    val pinned = pinnedWeaponId?.let(::weapon)?.let { pinnedSnapshot(it, start, text) { camo -> camo.label() } }
    val overall = if (modes.isEmpty()) 0.0 else modes.sumOf { it.fraction } / modes.size
    return WidgetSnapshot(
        modes = modes, pinned = pinned, overall = overall,
        overallLabel = t("mw4.ui.stats.overall"),
        pinPrompt = t("mw4.widget.pin_prompt"),
        allDoneLabel = t("mw4.widget.all_done"),
        masteryLabel = t("mw4.ui.section.mastery"),
        game = game.id, gameName = game.shortName, startMode = start,
    )
}

/** The pinned weapon in `mode`: its camo count and the next thing to earn on it, a camo with its challenge, else the next Completionist camo. */
private fun GameTracker.pinnedSnapshot(
    weapon: WeaponEntry, mode: String,
    t: (String, Array<out Any?>) -> String, label: (MasteryCamo) -> String,
): WidgetSnapshot.Pinned {
    val id = weapon.weaponId
    val counts = camoCounts(id, mode)
    var nextName: String? = null
    var nextDetail: String? = null
    var nextDone = 0
    var nextTotal = 1
    val camo = camos(id, mode).flatMap(::leafItems).firstOrNull { !isCamoComplete(mode, id, it) }
    if (camo != null) {
        nextName = camo.name.resolved()
        val requirement = camo.requirement
        val gateLevel = militaryLevel(mode, id, camo)
        if (requirement != null) {
            nextDetail = (requirement.byMode?.firstOrNull { it.mode == mode }?.description ?: requirement.description).resolved()
            nextTotal = maxOf(requirement.amount, 1)
            nextDone = camoAmount(mode, id, camo)
        } else if (gateLevel != null) {
            val gate = levelGate(gateLevel, id)
            nextDetail = t(if (gate.countsUnlocks) "mw4.ui.camo_unlocks_reach" else "mw4.ui.camo_level_reach", arrayOf(gate.value))
            if (gate.countsUnlocks) {
                nextTotal = maxOf(gate.value, 1)
                nextDone = minOf(GameTracker.unlocks(level(id)), gate.value)
            } else {
                nextTotal = gateLevel
                nextDone = minOf(level(id), gateLevel)
            }
        }
    } else {
        val step = (0 until GameTracker.COMPLETIONIST_STEP_COUNT).firstOrNull { !isCompletionistComplete(mode, id, it) }
        if (step != null) nextName = label(completionistCamos(mode)[step])
    }
    return WidgetSnapshot.Pinned(
        weaponId = id, name = weapon.name.resolved(), category = category(id)?.name?.resolved() ?: "",
        mode = mode, modeName = t(modeNameKey(mode), emptyArray()), accentHex = HexColor.toHex(modeAccent(mode)),
        camosDone = counts.done, camosTotal = counts.total,
        nextName = nextName, nextDetail = nextDetail, nextDone = nextDone, nextTotal = nextTotal,
    )
}

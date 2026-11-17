package app.camotrack.android

/**
 * The app's links (`mw4camo://mode/<mode>/...`), from notifications (iOS
 * Navigation.swift's DeepLink):
 *
 *     mw4camo://mode/warzone                       the Weapons tab in Warzone
 *     mw4camo://mode/warzone/weapon/12             a weapon's page
 *     mw4camo://mode/warzone/event/1/102           an event (objective category 1, item 102)
 *     mw4camo://mode/warzone/events/1              an objective category
 *     mw4camo://mode/current/event/1/102           the same, in whichever mode the player is on
 *
 * `?game=bo7` switches game first. A mode the player doesn't play (or
 * `current`) opens in their own.
 */
object DeepLink {
    data class Target(
        /** null: the player's current mode */
        val mode: String?,
        val route: Route?,
        val game: String?,
    )

    fun parse(link: String): Target? = parse(link.substringBefore('?').removePrefix("mw4camo://").split('/'), link)

    private fun parse(segments: List<String>, link: String): Target? {
        if (!link.startsWith("mw4camo://")) return null
        if (segments.firstOrNull() != "mode") return null
        val parts = segments.drop(1).filter { it.isNotEmpty() }
        val first = parts.firstOrNull() ?: return null
        val mode = if (first == "current") null else first
        val route: Route? = when {
            parts.size >= 3 && parts[1] == "weapon" -> parts[2].toIntOrNull()?.let { Route.Weapon(it) }
            parts.size >= 4 && parts[1] == "event" -> {
                val category = parts[2].toIntOrNull()
                val item = parts[3].toIntOrNull()
                if (category != null && item != null) Route.ObjectiveItem(category, item) else null
            }
            parts.size >= 3 && parts[1] == "events" -> parts[2].toIntOrNull()?.let { Route.ObjectiveCategory(it) }
            else -> null
        }
        val game = link.substringAfter('?', "").split('&')
            .firstOrNull { it.startsWith("game=") }?.removePrefix("game=")?.let { java.net.URLDecoder.decode(it, "UTF-8") }?.takeIf { it.isNotEmpty() }
        return Target(mode, route, game)
    }
}

# Forever Chef

A Cooking companion for **World of Warcraft: Forever**: which recipes use an
ingredient, which ones you know, where to learn the rest, and a map waypoint to
get there.

## Features

- **Ingredient tooltips.** Hover any cooking ingredient to see every Cooking
  recipe that uses it, in **green if you know it** and **red if you don't**, with
  how to learn the unknown ones ("Vendor (Horde)", "Trainer", "Drop", ...).
  All 133 Cooking recipes are built in, so this works right away, even on
  characters without Cooking.
- **Recipe window** (minimap cooking scroll, the AddOns menu, or `/fchef`):
  every Cooking recipe, whether you know it, how it is learned, and the zone
  to learn it in ("Multiple Zones" when there is more than one). Click a
  column header to sort; *Status*, *Learn from* and *Zone* also group the list.
  Headers stack: click *Status* then *Zone* to see zones inside each status
  group. Click an active header again to reverse it, a third time to remove it.
- **Recipe details.** Click a recipe for its ingredients (and how many you
  carry), required skill, every vendor, trainer, quest giver or drop that
  teaches it, and the food's effect (health/mana and the Well Fed buff).
- **Waypoints.** Each place with a known map position has a radio button that
  sets a waypoint. Track as many recipes as you like (one place each): they are
  all shown in gold, TomTom (if installed) gets an arrow for each, and the map
  pin, which the game allows only one of, points at your latest choice; when you
  learn that recipe it moves to the closest remaining one. Click a selected radio again to stop tracking
  it, or use **Reset All Waypoints**.
- **Faction aware.** Sources your faction cannot use are hidden; a recipe only
  the other faction can learn says so.
- **Learns as you play.** Opening a recipe vendor, looting a recipe, seeing a
  recipe as a quest reward, or talking to a vendor, trainer or quest giver
  records where it happened. Recorded sources are shown first and can be shared
  with `/fchef export`.
- **Pop-up messages** instead of chat spam: a small box above action bar 1
  (Shift+drag its gold border to move it).

## Commands

| Command | What it does |
| --- | --- |
| `/fchef` | Open or close the Forever Chef window |
| `/fchef status` | How many recipes you know and how much has been recorded |
| `/fchef export` | Copyable text of what you recorded (recipe sources, NPC positions) |
| `/fchef quiet` | Turn the pop-up messages off or on |
| `/fchef toast` | Show a sample pop-up so you can move it |
| `/fchef toast reset` | Put the pop-up back above action bar 1 |
| `/fchef debug` | Print diagnostic messages in chat |
| `/fchef reset` | Erase recorded sources and NPC positions on this account |

## Install

Install from CurseForge, or copy the `ForeverChef` folder into
`World of Warcraft/_classic_beta_/Interface/AddOns/` (the WoW: Forever beta
client) and restart the game.

## How reliable is the data?

- **Recipes, ingredients, recipe scrolls and food effects** are generated from
  the WoW: Forever client's own data (build 1.60.1.70450).
- **Where to learn** each recipe comes from public Forever guides, checked
  against each other, and from what players record in game.
- **Map positions** are only used from WoW: Forever or pre-Cataclysm sources,
  never from current-WoW maps. A position at least two sources agree on is used
  as is; a position from a single source is shown as *"1 source, unconfirmed"*;
  *"recorded in game"* means a player stood there.

WoW: Forever is still in beta, so vendors, recipes and positions can change.
If something is wrong, please open an issue with your `/fchef export` text.

## Credits

Recipe data generated from the game client via [wago.tools](https://wago.tools).
"Where to learn" facts and positions were cross-checked against
[wow-professions.com](https://www.wow-professions.com/forever/cooking-leveling-guide),
[foreverdb.net](https://foreverdb.net/profession/cooking),
[Icy Veins](https://www.icy-veins.com/wow-forever/cooking),
[Warcraft Wiki](https://warcraft.wiki.gg/) (quest and recipe facts),
[Warcraft Tavern](https://www.warcrafttavern.com/),
[classicwowforever.com](https://classicwowforever.com/professions/cooking/),
[Zockify](https://www.zockify.com/forever/professions/cooking/recipes/),
[wclbox](https://wowforever.wclbox.com/) and [SenseOS](https://senseos.gg/).
Forever Chef is not affiliated with Blizzard Entertainment or any of these sites.

## License

[MIT](LICENSE)

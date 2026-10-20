# Changelog

## 0.7.0

First CurseForge release.

- Every Cooking recipe in WoW: Forever (132) on ingredient tooltips: green when
  known, red when not, with how to learn it.
- Recipe window with recipe counters and a Zone column ("Multiple Zones" when a
  recipe can be learned in several). Click headers to sort and group; they
  stack, e.g. zones inside each Known / Not known group. Recipes new in
  WoW: Forever are marked [New].
- Detail pop-up per recipe: ingredients, required skill, where to learn it, and
  the food's effect.
- Where to learn a recipe is shown when two different websites agree or it was
  seen in game. When only one website names a place it is shown as
  "Suggested" (with coordinates and a waypoint) until it is found in game;
  recipes learned together with Cooking say "Automatic"; otherwise "Unknown".
  Faction aware; map positions are cross-checked the same way.
- Map waypoints (and TomTom arrows) to vendors, trainers and quest givers for
  as many recipes as you like, each shown as a Forever Chef icon on the world
  map and the minimap (a light blue arrow on the minimap's edge points to ones
  out of range); tracked recipes are highlighted, and each waypoint clears
  once its recipe is learned, or with the Reset All Waypoints button.
- Cooking ranks window: how to reach Apprentice, Journeyman, Expert (Expert
  Cookbook vendors) and Artisan (Clamlette Surprise quest line), with
  requirements, costs and waypoints. Every Cooking trainer of your faction is
  listed; a rank waypoint clears when you talk to that NPC or reach the rank.
- Records recipe vendors, trainers' recipe lists, drops, quest rewards and NPC
  positions while you play; `/fchef export` gives the ones the addon does not
  confirm yet as text to share.
- Pop-up messages above action bar 1 instead of chat lines.

# Changelog

## 0.8.0

- Ingredient tooltips now show three colours: **green** when you know the
  recipe and have every ingredient (bags or bank), **orange** when you know it
  but are missing ingredients, **red** when you have not learned it yet. Recipes
  you can make right away are listed first. The "Cooking recipes" heading is
  now off-white. Bank contents are remembered from your last bank visit.
- Recipe details count ingredients in your bank too.
- A "What's New" letter opens once after each update. Reopen it with
  `/fchef news` or the new **What's new** button in the window header.
- Sending in data is easier: the `/fchef export` window has a link to a short
  GitHub form ("Submit /fchef export") in a box you can copy from.
- A recipe find from players counts as confirmed once **two different
  players** have sent it in; until then it shows as Suggested. Exports carry a
  random code (never your character name) so players can be told apart.
- Data from the first player export: the Undercity Cooking trainer (Eunice
  Burch) and recipe vendor (Ronald Burch) have confirmed map positions. Thank
  you!

## 0.7.0

First CurseForge release.

- Every Cooking recipe in WoW: Forever (132) on ingredient tooltips: green when
  known, red when not, with how to learn it.
- Recipe window with recipe counters and a Zone column ("Multiple Zones" when a
  recipe can be learned in several). Click headers to sort and group; they
  stack, e.g. zones inside each Known / Not known group. Recipes new in
  WoW: Forever are marked [New]. A Buff drop-down narrows the list to recipes
  whose food gives a chosen buff (Strength, Stamina, Spell Damage, ...).
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

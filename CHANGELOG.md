# Changelog

## 1.0.0 (2026-11-14)

- First version: distance to your target next to the target frame, in yards.
- Estimates the distance from every range check the game allows (items, your spells, follow and duel distance) plus your own position, with a particle filter. Shows `27 yd`, `~27 yd` when unsure, `< 5 yd` in melee, `> 45 yd` beyond the last check, and a plain range like `30 - 35 yd` where the game hides your position (dungeons).
- `/dtt` for status, `on`, `off`, `unlock`, `lock`, `move <x> <y>`, `reset`, `checks`.
- Falls back to a spot below the screen centre when another addon replaces or hides the target frame; `/dtt unlock` lets you drag the text anywhere.
- Corpses and other units that answer "out" to every item no longer show as far away: item answers only count when at least one item says "in".
- Shows the exact distance where the game gives one (party and raid members in the open world, a few NPCs) instead of the estimate.
- Fixed a far target showing as ~26 yd for Warlocks: Health Funnel answers for your pet, not your target. Pet-only spells (Health Funnel, Mend Pet, Feed Pet, Revive Pet, Eyes of the Beast) and helpful-only spells on hostile targets are no longer used, and any spell that contradicts the item and interact checks is ignored.
- Fixed corpses showing nonsense like `> 5 yd`: item answers that contradict each other are ignored.
- Settings page (Options > AddOns, or `/dtt settings`): on/off, text size, updates per second, colour by kind, unlock/lock and reset position. Native page on Forever, basic page on Classic Era.
- If you update and only `/reload`, the new settings file isn't loaded yet: the addon keeps working and `/dtt settings` asks you to restart the game.
- Addon compartment entry on the minimap: left-click opens settings, right-click turns it on or off.
- `/dtt log` records every update (checks, estimate, shown text) to `DistanceToTargetLog` for checking accuracy.

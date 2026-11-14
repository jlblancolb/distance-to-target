# Distance to Target

Shows how far away your target is, next to the target frame, all the time, in and out of combat. Built for WoW Forever. The TOC also lists Classic Era, but it hasn't been tested there yet.

Install [Yards to Kilometers](https://github.com/jlblancolb/YardsToKm) too if you'd rather read metres: it converts this addon's text automatically.

## What you see

| Text | Meaning |
|---|---|
| `27 yd` | Estimated distance, usually within 1–2 yards. Exact for party and raid members in the open world |
| `~27 yd` | Estimate, but less sure (friendly targets, or the target just moved a lot) |
| `< 5 yd` | Melee range (`< 8 yd` when only the trade/duel distance answers, e.g. corpses) |
| `> 45 yd` | Further than any range check can tell |
| `> 28 yd` | Friendly NPCs: only the follow and trade distances work on them, so this is often all you get |
| `30 - 35 yd` | Range only: the game hides your position here (dungeons, some instances) |

Distances are spell distances, the number spell and item ranges use, not centre to centre.

## How it works, and its limits

The game doesn't tell addons the distance to most units. It only answers yes or no to "is this unit within N yards" for items, your spells, and the follow and duel distances. Each answer puts the target inside or outside a circle around you. The addon uses your own position (which the game does give in the open world) and a particle filter to combine those answers as you and the target move, which narrows a 5-yard range down to a single number.

- Hostile targets: about half a yard off typically, within 2 yards 90% of the time (measured on Forever against the few NPCs whose exact position the game reveals).
- Party and raid members in the open world: the game gives their exact position, so the number is exact.
- Friendly NPCs answer far fewer checks, so expect `~` estimates or just `< 8`, `8 - 28`, `> 28 yd`.
- Between 45 and 100 yards there are no checks at all.
- In dungeons the game hides your position, so you get the plain range.

## Settings

Options > AddOns > Distance to Target, the addon menu on the minimap (left-click: settings, right-click: on/off), or `/dtt settings`:

- **Show distance to target**
- **Text size:** small, normal, large
- **Updates per second:** 10 (smoothest), 5 or 2; fewer use less CPU but react more slowly
- **Colour by kind:** green in melee range, grey when unsure or out of range; off for always white
- **Unlock / lock** and **Reset position**

## Commands

`/dtt` status · `/dtt settings` · `/dtt on` / `off` · `/dtt unlock` drag the text anywhere, `/dtt lock` when done · `/dtt move <x> <y>` offset from the target frame · `/dtt reset` back to the target frame · `/dtt checks` lists every check and its answer for your target · `/dtt log` / `log off` records every update to the saved variables (for bug reports)

If another addon replaces the target frame (ElvUI, Shadowed Unit Frames and others), the text moves below the centre of the screen; use `/dtt unlock` to put it next to your new target frame.

## Credits

Uses [LibRangeCheck-3.0](https://github.com/WeakAuras/LibRangeCheck-3.0) for item range lists.

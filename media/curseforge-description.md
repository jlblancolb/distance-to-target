# Distance to Target

**How far away is your target?** Distance to Target shows it right next to the target frame, all the time, in and out of combat.

## What you see

| Text | Meaning |
|---|---|
| `27 yd` | Estimated distance, usually within 1–2 yards |
| `~27 yd` | Estimate, but less sure (the target just moved a lot) |
| `< 5 yd` | Melee range (green) |
| `> 45 yd` | Further than any range check can tell |
| `30 - 35 yd` | Range only, in dungeons where the game hides your position |

Party and raid members in the open world get their **exact** distance.

Prefer metres? Install **Yards to Kilometers** and the text is converted automatically.

## How it works

The game doesn't tell addons the exact distance to most units. It only says yes or no to "is this unit within N yards?" for items, your spells, and the follow and trade distances. Distance to Target asks all of them, ten times a second, and combines the answers with your own position as you move. That turns a vague "between 25 and 30 yards" into a single number.

Measured in game against NPCs whose real position the game reveals: about half a yard off typically, within 2 yards 90% of the time.

**Honest limits**

- Friendly NPCs answer very few checks, so you get rough ranges like `> 28 yd`.
- Between 45 and 100 yards there are no checks at all.
- In dungeons you get a range, not a single number.

## Settings

Options > AddOns > Distance to Target, the addon menu on the minimap, or `/dtt settings`:

- Show or hide the distance
- Text size: small, normal, large
- Updates per second: 10, 5 or 2
- Colour by kind (green in melee, grey when unsure), or always white
- Unlock to drag the text anywhere, reset position

Works with ElvUI, Shadowed Unit Frames and other unit frame addons: if Blizzard's target frame is replaced, the text moves below the screen centre and you can drag it next to your new frame.

## Commands

`/dtt` status · `/dtt settings` · `/dtt on` / `off` · `/dtt unlock` / `lock` · `/dtt reset` · `/dtt checks` (every range check and its answer) · `/dtt log` (records updates for bug reports)

## Found a wrong distance?

Type `/dtt log`, stand still where it looks wrong for a few seconds, then `/reload`. Open an issue on GitHub with your `WTF/Account/<account>/SavedVariables/DistanceToTarget.lua` and what distance you expected.

Source and issues: https://github.com/jlblancolb/distance-to-target

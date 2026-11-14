# DistanceToTarget plan

Goal: show how far away your current target (NPC or player) is, next to the target frame, all the time, in yards. Built for WoW Forever first (Mainline UI, interface `16001`, client 1.60.1) and loading on Classic Era too (`11509`), same as YardsToKm.

Status: MVP and 1.0 features done and checked on Forever 2026-11-14. 1.0.0 released on GitHub and CurseForge 2026-11-14 (Forever). Left: Classic Era check, screenshots, exact distance on a party member.

## 0. Decisions

- [x] **What and where:** distance to `target` only, as text next to the target frame, updated all the time while there's a target (2026-11-10)
- [x] **Units:** yards only. YardsToKm converts it for players who want metres, so this addon has no metric option (2026-11-10)
- [~] **Name and repo:** building as "DistanceToTarget" locally (2026-11-10); GitHub repo under `jlblancolb` + CurseForge project after the in-game check (maintainer)

How YardsToKm picks up the text (checked in `YardsToKm.lua`, 2026-11-10): it scans every frame with `EnumerateFrames` on load, on `PLAYER_LOGIN` and every 10 s, then hooks `SetText` on each FontString it finds. Every later update is converted right away. Ranges with `-`, `–`, `—` or `to` are converted (`8–10 yd` → `7 - 9 m`). So DistanceToTarget needs to:
- create its FontString when the file loads, so the `PLAYER_LOGIN` scan finds it
- write plain text with no `|T`/`|H` markup, because YardsToKm skips that (colour codes `|c` are fine)
- use `yd` or `yards` after the number
- leave room for longer text: "Yards and metric" mode shows `8 - 10 yd (7 - 9 m)`

## 1. Feasibility spike (do first)

The game never gives addons the exact distance to an enemy. Addons estimate a range bracket from which checks pass (spell range, item range, interact distance), so the display will read `8–10 yd` or `30–35 yd`, not `27 yd`. On Mainline several checks are blocked in combat, and Forever may return Midnight secret values. "All the time" means in combat too, so this has to be checked in-game first.

- [x] **Throwaway test addon:** `probe/DTTProbe` with `/dttp`; bundles LibRangeCheck-3.0 v39 (2026-11-07 commit, has Forever support), shows live range next to the target frame, auto-report 1 s into each combat, saves to `DTTProbeDB`. Smoke-tested with mocks; installed to the Forever AddOns folder (2026-11-10)
- [x] **First probe run, hostile NPC, open world, probably out of combat:** exact distance works. `UnitDistanceSquared("target")` = 1035, checked = true (32.2 yd); `UnitPosition` works for player and target and gives the same 32.2 yd; LibRangeCheck 30–35 yd agrees; `CheckInteractDistance` all false; `UnitInRange` secret (2026-11-10, Plainstrider)
- [x] **Probe shows exact + bracket live:** `32.2 yd  [30 - 35 yd]`, stats per source in and out of combat; reinstalled (2026-11-10)
- [x] **Exact distance is unreliable:** on a level 14 Warlock in Silverpine, `UnitDistanceSquared` = `0, false` and `UnitPosition("target")` = nil, in combat and out of combat; player position still works. On the Tauren in Mulgore it worked (567 readings). Cause unknown (zone, continent, starting area?). 2026-11-10, Moonrage Whitescalp
- [x] **LibRangeCheck works everywhere tested, including combat:** 135/135 in combat, 1107/1107 out of combat, no errors or secret values; brackets match the exact distance when both exist. `CheckInteractDistance` also works on hostile targets in combat (2026-11-10)
- [x] **Tauren trace result (2026-11-10, 784 samples, level 1 Warrior, no group, no PvP, out of combat):** exact distance depends on the **NPC type**, not on zone, distance or character. Always works: Plainstrider (NPC 2955), Mottled Boar (3098), Kaltunk (10176). Never works: Mountain Cougar (2961) in the same subzone at the same distances, Den Grunt, every other NPC in Mulgore, The Barrens and Durotar, and every player. When it fails, `UnitPosition("target")` is nil too. Best guess: Blizzard allows positions for a short list of starting-area tutorial NPCs; not confirmed. Conclusion: exact distance is not usable for this addon
- [x] **Why exact works only sometimes:** documented behaviour (warcraft.wiki.gg) is that `UnitPosition`/`UnitDistanceSquared` only work on you and group members, outdoors, and return nil in instances since 7.1.0, so the Warlock result is the expected one and the Tauren is the odd one. Probe now saves context with every new target (race/class/level, zone, map, instance, group, PvP/war mode, resting, trial account, pet/nameplate positions). Test matrix: Tauren in Mulgore again, Tauren in The Barrens, Warlock in Tirisfal, Warlock in Silverpine (maintainer)
- [x] **Position trace:** probe logs player/target position, `UnitDistanceSquared`, LibRangeCheck range, zone and combat every 0.5 s while targeting (last 6000 samples) plus `/dttp mark <note>`; `probe/tools/trace.py` turns the saved file into a CSV and a per-zone table. Smoke-tested and installed (2026-11-10)
- [x] **Calibration:** range checks measure to the target's hitbox edge; centre distance is ~2.5 yd (1.5–3.5) more than the bracket says. Show "spell distance" (edge), which is what range checks and players care about, so hitbox size drops out (2026-11-10)
- [x] **Estimator prototype:** particle filter over the target's position, using the player's exact position (`UnitPosition("player")` works in the open world) and every range bracket as a soft annulus constraint; target random-walks. Code: `probe/tools/pf_eval.py` (real 0.5 s trace), `probe/tools/pf_sim20.py` (real paths replayed at 20 Hz with simulated checks) (2026-11-10)
  Real trace, 0.5 s, after 2 s: midpoint median 1.7 yd / 90% 5.6; filter median 1.3 / 90% 4.8.
  Simulated 20 Hz, spell distance, under 45 yd: midpoint median 0.8 / 90% 2.1; filter median 0.6 / 90% 1.5. Over 45 yd both fail (no checks between 45 and 100 yd).
- [x] **20 Hz recorder:** `/dttp rec` logs every individual check (LibRangeCheck checkers, interact 1–5, every spellbook spell with a distinct range) plus own position, facing, player and target speed, exact distance, target position, target nameplate screen position, camera zoom and mouselook. Item/interact checks skipped on friendly targets in combat. Smoke-tested and installed (2026-11-10)
- [x] **Record a session on Plainstriders:** 1120 samples at 20 Hz with exact distance, 2 Plainstriders, Tauren Druid, incl. combat (2026-11-10, maintainer)
- [x] **Analyse the recording** (`probe/tools/rec_eval.py`, 2026-11-10):
  Item checks flip at nominal + 2.5 yd centre distance (10 yd item: +2.2), almost no misfits. Interact checks are sharp (0 misfits) and differ from LibRangeCheck's Tauren table: follow/inspect (1, 4) flip at 30.0, trade/duel/5 (2, 3, 5) at 9.9 yd centre distance. Friendly-only items/spells always "out" on hostiles; the 100 yd item never flipped (max 64.5 yd seen). In combat `GetUnitSpeed` is secret for player and target; items, interact and positions still work on a hostile target.
  Error under 45 yd (centre distance), hostile checks only:
  nominal items/spells only: midpoint median 1.6 / 90% 2.3; filter median 1.1 / 90% 2.2.
  + measured interact edges: midpoint median 0.8 / 90% 2.3 / max 8.9; filter median 0.6 / 90% 1.9 / max 4.9; standing still median 0.6; combat median 1.0–1.6.
  Caveat: one 56 s session, one NPC type, one race; interact edges measured on the same data.
- [x] **Second recording, male Troll Hunter, Valley of Trials** (`probe/data/2026-11-10-troll-hunter-valley.lua`, 1870 samples, Mottled Boar hostile + Kaltunk friendly, 131 in combat; Tauren recording in `probe/data/2026-11-10-tauren-druid-plainstrider.lua`) (2026-11-10)
  Items flip at nominal +2.0 (Boar/Troll) vs +2.5 (Plainstrider/Tauren): the offset is hitbox size, ~2–2.5 yd. 100 yd item flips at 101.4.
  Interact edges are the same for both races and every target: 29.8–30.0 and 9.8–9.9 yd centre distance, so they look centre-to-centre (LibRangeCheck's race table doesn't match).
  Auto Shot (8–35): inner edge at 10.0, outer at 36.6–37.0, so min ranges are usable edges too.
  Friendly NPC (Kaltunk): every item check is always "out"; only interact edges (10, 30) work, so friendly NPCs get a coarse estimate (`< 10`, `10–30`, `> 30`) unless the class has friendly spells.
- [x] **Filter fixes** (2026-11-10): clamp the estimate to the current bracket; 10% of particles move fast (7 yd/s) so a running mob isn't lost; innermost bracket shown as `≤ 5 yd` instead of a number (the filter drifted outward there: truth 0–3, filter ~6).
  Same settings on both recordings (nominal + 2.25, interact 29.9/9.85, sigma 0.5, wander 1.0), hostile, < 45 yd, outside melee:
  Tauren/Plainstrider: midpoint median 0.83 / 90% 2.5 / max 8.6; filter median 0.53 / 90% 2.05 / max 7.1.
  Troll/Boar: midpoint median 1.04 / 90% 2.2 / max 2.9; filter median 0.60 / 90% 1.76 / max 3.0.
- [x] **Nameplate bearing is blocked:** `NamePlate:GetCenter()` errors on Forever ("Can't measure restricted regions", taint on DTTProbe), which also stopped every sample. Recorder now only logs whether the target has a nameplate (2026-11-10)
Other ways to measure distance, studied 2026-11-10: more edges from own spells and interact distances; target bearing from the nameplate's screen position (if camera ≈ facing); target speed (`GetUnitSpeed`) to stop drift. No world-to-screen or target-position API exists for non-group units.
- [x] **Design (revised 2026-11-10):** filter estimate rounded to whole yards (`27 yd`), `~27 yd` when its spread is over ~2 yd, `< 5 yd` in melee, `> 45 yd` beyond the last check; plain bracket where the player's position is hidden (instances). OK'd by maintainer (2026-11-10)
- [x] **Probe logs from 2026-11-11 play (09:11–09:40, run alongside DistanceToTarget):** Troll Hunter in Valley of Trials: exact distance again only for Kaltunk and Mottled Boar, not Den Grunt or players. Orc Warlock in Silverpine incl. Deep Elem Mine, 314 in-combat samples: exact never, LibRangeCheck answered every hostile target in and out of combat; `UnitPosition("player")` works there (instance id 0), so the filter runs for that character too. Only empty range: a friendly player in combat (expected). DistanceToTargetDB has a `free` spot (x 373, y 21), so unlock/drag was used. BetterBlizzFrames is enabled (keeps Blizzard's TargetFrame). WoW's log files don't record Lua errors, and DistanceToTarget logs nothing, so its accuracy and errors can't be judged from files (2026-11-11)
- [x] **Corpse bug (from the 2026-11-11 logs):** a dead hostile answers "out" to every item and nothing to spells, so it showed as `> 28 yd` at 8–28 yd. Items now count only when one says "in" in the same round (also replaces the per-item friendly rule) (2026-11-11)
- [x] **`/dtt log`:** records target changes and every update (checks, lo/hi, estimate, shown text) to `DistanceToTargetLog`, last 20000 rows (2026-11-11)
- [x] **Wrong distance at Shadow Bolt range:** found with `/dtt log` (`probe/data/2026-11-14-dtt-log.lua`, 1044 rows, Kolkar Stormers/Wranglers, The Barrens). A 20 yd spell, almost certainly Health Funnel (it targets the pet), said "in" with the target 37+ yd away, so lo > hi and the estimate sat at ~25–27 yd. Fix: skip pet-only spells by name and helpful-only spells on hostile targets, read spells last and ignore any that contradict items/interact by > 1.5 yd (off after 5 contradictions). Replay of the log: contradictory rows 218 → 0 (2026-11-14)
- [x] **Corpse bug, second shape:** corpses say "in" to the 5 and 10 yd items and "out" to every larger one, which showed `> 5 yd`; contradicting item sets are now ignored (2026-11-14)
- [x] **Probe logs from 2026-11-13/14 (Orc Warlock 15–16, Durotar and The Barrens, 6000 trace rows, 2000+ in combat):** exact distance only for party members (two party members: 282/282 samples), never for any NPC or enemy. Spells answer plain true/false in combat (Immolate, Corruption, Drain Life). No data from that run explains the Shadow Bolt case: the trace has no individual checks and `/dtt log` was off (2026-11-14)
- [ ] **Still unchecked:** dungeon, enemy player, party member (MVP is installed; check when it comes up)
- [x] **Run the probe on Forever:** hostile and friendly NPCs and a party member, in and out of combat (2026-11-10 to 2026-11-14, maintainer)
- [x] **Spell range in combat:** plain true/false on hostile targets in combat (2026-11-14)
- [x] **Item range in combat:** items and `CheckInteractDistance` work on hostile targets in combat; blocked on friendly targets in combat (2026-11-10)
- [x] **Friendly targets:** party members give exact yards in the open world (2026-11-14); dungeons still unchecked
- [x] **LibRangeCheck-3.0:** loads and gives correct brackets everywhere tested, in and out of combat; used for its item list (2026-11-10)
- [x] **Write up results:** recorded above; design picked (2026-11-10)

## 2. MVP (after the spike)

- [x] **Project skeleton:** TOC with `## Interface: 11509, 16001`, `.pkgmeta`, `.luacheckrc`, `scripts/test.sh`, `scripts/package.py`, CI workflow, LICENSE, README, CHANGELOG, libs (LibStub, CallbackHandler, LibRangeCheck v39) (2026-11-10)
- [x] **Range engine (2026-11-10):** `Estimator.lua` (pure Lua: edges, bounds, particle filter, text) + `Checks.lua` (LibRangeCheck items, spellbook spells, interact 3/4); 0.1 s ticker only while a target exists; `SetText` only when the text changes
- [x] **Lua replay of the recordings:** `tools/replay.lua` runs the real `Estimator.lua` (200 particles, 10 Hz) on `probe/data/*.lua`; matches Python (2026-11-10)
  Tauren/Plainstrider hostile < 45 yd: median 0.50 / 90% 2.0 / max 2.8. Troll/Boar: median 0.60 / 90% 1.7 / max 3.0. Kaltunk friendly: median 4.3 / 90% 8.7, always shown with `~`.
- [x] **Display:** `DistanceToTargetFrame` FontString created at load, LEFT of it on `TargetFrame` RIGHT +4; hidden without a target; white estimate, light grey `~`, green melee, grey `>` (2026-11-10)
- [x] **Other target frames:** if `TargetFrame` has its events unregistered or sits under a hidden parent (ElvUI/oUF, SUF), the text goes to a free spot below the screen centre; checked at login, entering world and every target change out of combat. `/dtt unlock` / `lock` to drag it anywhere (saved as `free`, `/dtt reset` clears it) (2026-11-11)
- [x] **Saved settings:** `DistanceToTargetDB` has `enabled`, `x`, `y`, `free`. Colours and update rate stay fixed for the MVP and move to the 1.0 settings panel (2026-11-14)
- [x] **Exact distance when the game gives it:** `UnitDistanceSquared` with `checked = true` (party/raid members, a few NPCs) is shown directly, no range checks; secret answers fall back to the estimate; tests added (2026-11-14)
- [x] **Slash command:** `/dtt` status, `on`, `off`, `move <x> <y>`, `reset`, `checks` (each check and its answer) (2026-11-10)
- [x] **Combat safety (2026-11-10):** no protected calls in combat, never move or parent to `TargetFrame` in combat; guards for secret values and forbidden frames (lessons from YardsToKm)
- [x] **Tests:** `tests/estimator.lua` (edges, text, filter on a simulated walk), `tests/addon.lua` (mocked world: hostile, melee, far, secret answers, instance, friendly in combat, slash, anchor after combat), `tests/yardstokm.lua` (every text shape through the real YardsToKm). All pass under fengari; lua5.1/luacheck not installed locally, CI runs them (2026-11-10)
- [x] **In-game check on Forever (2026-11-14, `probe/data/2026-11-14-dtt-log2.lua`, 359 rows):** Orc Warlock in The Barrens, hostile mobs from melee to 100 yd, in and out of combat, a corpse, a friendly NPC. 0 contradictory rows and 0 ignored spells; Health Funnel no longer used. Mob at Shadow Bolt range (35 yd item in, 30 out, Shadow Bolt in) shows 33–35 yd; 36–40 yd shows 37–39; 40–45 shows 42–44; beyond that `> 45 yd`. Corpse shows `< 8 yd`, friendly NPC `> 28 yd`. Earlier checks: unlock/drag/lock and the free spot work (maintainer)
- [ ] **Exact distance on a party member:** not in the log yet (no party member targeted). Should show whole yards with no `~` (maintainer, whenever grouped)

## 3. 1.0 release

- [x] **Settings panel:** `Options.lua`, YardsToKm's pattern. Native page on Forever (show, text size, updates per second, colour by kind, Unlock / lock and Reset position buttons), canvas page on Classic Era or when the native API errors; `/dtt settings`; opens after combat. `tests/settings.lua` (2026-11-14)
- [x] **Addon compartment entry:** TOC fields, built-in spyglass icon (`INV_Misc_Spyglass_03`); left-click settings, right-click on/off, tooltip with state (2026-11-14)
- [x] **Load error after /reload (2026-11-14):** `DistanceToTarget.lua:405: attempt to call a nil value` on ADDON_LOADED, because WoW reads the TOC file list only at game start, so the new `Options.lua` wasn't loaded. The main file now has fallbacks (settings via `/dtt` still work, `/dtt settings` says to restart); test added. Lesson: any update that adds a file needs a full game restart
- [x] **In-game check of settings and compartment on Forever:** opened from Options > AddOns, the minimap menu and `/dtt settings`, options change and persist; works well (maintainer, 2026-11-14)
- [x] **Docs:** README (what you see, limits, settings, commands, YardsToKm note), CHANGELOG, CONTRIBUTING with how to send a `/dtt log` (2026-11-14)
- [ ] **Regression check on Classic Era** (maintainer); after it, add 1.15.9 on CurseForge and drop "untested" from the README
- [x] **Yellow label next to the target (2026-11-14):** that's DTTProbe's display (exact + bracket), not this addon. Fixed: DTTProbe removed from the Forever AddOns folder (source stays in `probe/DTTProbe`); it was never packaged
- [x] **Release prep:** version 1.0.0, local git repo with one commit, `probe/data/` gitignored (raw SavedVariables), party member names and local paths removed from this plan; remote `git@github.com:jlblancolb/distance-to-target.git` with the personal SSH key, like YardsToKm (2026-11-14)
- [x] **GitHub release:** repo https://github.com/jlblancolb/distance-to-target (created with gh's second account, jlblancolb, via `GH_TOKEN=$(gh auth token --user jlblancolb)`; the active work account can't create public repos). CI green after fixing luacheck warnings; tag `v1.0.0`, release https://github.com/jlblancolb/distance-to-target/releases/tag/v1.0.0 with `DistanceToTarget-1.0.0.zip` attached by CI (2026-11-14)
- [x] **CurseForge:** project set up with the description and icon from `media/`, 1.0.0 for 1.60.1 (Forever) only (maintainer, 2026-11-14)

- [ ] **Screenshots for CurseForge:** hero shot, melee, settings page, minimap menu; maintainer takes them, agent crops into `media/`

## Later ideas

- [ ] **Focus and mouseover:** same display for other units
- [ ] **Nameplate text:** distance on the target's nameplate

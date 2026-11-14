# Contributing

Bug reports, accuracy logs, compatibility fixes, documentation, and pull
requests are welcome. Discuss large behavior changes in an issue first.

## Reporting a wrong distance

The most useful report is a log: type `/dtt log`, reproduce the problem
(stand still for a few seconds where the number looks wrong), then `/reload`.
Attach `WTF/Account/<account>/SavedVariables/DistanceToTarget.lua` and say what
distance you expected and why (for example "at the edge of Shadow Bolt range").
`/dtt checks` prints every range check and its answer for your current target.

## Local setup

1. Fork the repository on GitHub and clone your fork.
2. Install Lua 5.1 and luacheck for syntax checks, lint and tests; Python 3
   for packaging.
3. Copy the addon files into a folder named `DistanceToTarget` in the WoW
   Forever or Classic Era `Interface/AddOns` directory, and `/reload` after
   changing Lua files.

## Layout

- `Estimator.lua`: pure Lua, no WoW API. Check edges, the particle filter
  and the shown text.
- `Checks.lua`: asks the game (items through LibRangeCheck-3.0, spellbook
  spells, interact distances) and turns the answers into a distance interval.
- `DistanceToTarget.lua`: display, anchoring, update loop, `/dtt`.
- `Options.lua`: settings page and addon compartment entry.
- `tools/replay.lua`: runs the real estimator on recorded sessions.
- `probe/`: the throwaway probe addon and recordings used to measure check
  edges on Forever. Not shipped.

## Implementation guidelines

- Keep the addon compatible with WoW Forever (Mainline UI), Classic Era and
  Lua 5.1. Guard client-specific APIs, and never compare or parse secret
  values: check `issecretvalue` first.
- No protected calls in combat: don't move, parent or anchor frames to
  `TargetFrame` in combat, and open the settings page only out of combat.
- Write plain text with `yd` after the number, so Yards to Kilometers can
  convert it. No texture or hyperlink markup in the distance text.
- Range checks can lie (corpses, pet-only spells). Prefer ignoring an answer
  that contradicts the others over trusting it.
- Never commit account data, SavedVariables you haven't checked, credentials,
  or private logs.

## Checks

```sh
scripts/test.sh
python3 scripts/package.py
```

`scripts/test.sh` runs the Lua 5.1 syntax check, `luacheck`, and every
`tests/*.lua` file. Without Lua 5.1 it falls back to fengari through npm and
skips the tools that aren't installed; CI always runs all of them.

Mocked tests do not prove behavior in WoW. For changes to checks or display,
also check in game with `/console scriptErrors 1`: hostile targets at several
distances in and out of combat, a friendly NPC, a party member, a corpse, the
settings page, and `/reload` with settings kept.

## Pull requests

Explain the problem, the change, and how it was tested. Add regression
coverage for fixes where feasible. Maintainers manage versions and tags.

## License

By submitting a contribution, you agree that it is distributed under the
project's [MIT license](LICENSE). Submit only material you have the right to
share.

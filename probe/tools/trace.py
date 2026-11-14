#!/usr/bin/env python3
"""Turn DTTProbe's saved position trace into a CSV and a per-zone summary.

Usage: trace.py <path to SavedVariables/DTTProbe.lua> [out.csv]
"""
import csv
import re
import sys
from collections import defaultdict

FIELDS = ["time", "combat", "map", "zone", "subzone", "player_pos", "target_pos",
          "dist_sq", "lrc", "hostile", "target"]


def lua_strings(block):
    for match in re.finditer(r'"((?:[^"\\]|\\.)*)"', block):
        yield match.group(1).replace('\\"', '"').replace("\\\\", "\\")


def trace_block(text):
    start = text.find('["trace"] = {')
    if start < 0:
        return ""
    depth, index = 0, text.index("{", start)
    for end in range(index, len(text)):
        if text[end] == "{":
            depth += 1
        elif text[end] == "}":
            depth -= 1
            if depth == 0:
                return text[index:end]
    return text[index:]


def main():
    path = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else None
    with open(path, encoding="utf-8", errors="replace") as handle:
        lines = list(lua_strings(trace_block(handle.read())))

    rows, marks = [], []
    for line in lines:
        parts = line.split("|")
        if len(parts) >= 3 and parts[1] == "MARK":
            marks.append((parts[0], "|".join(parts[2:])))
            rows.append({"time": parts[0], "combat": "MARK", "zone": "|".join(parts[2:])})
        elif len(parts) == len(FIELDS):
            rows.append(dict(zip(FIELDS, parts)))

    if out:
        with open(out, "w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=FIELDS)
            writer.writeheader()
            writer.writerows(rows)

    # exact = UnitDistanceSquared checked; tpos = target position available
    summary = defaultdict(lambda: {"n": 0, "exact": 0, "tpos": 0, "targets": set()})
    for row in rows:
        if row["combat"] == "MARK":
            continue
        key = (row["map"], row["zone"], row["subzone"], row["combat"])
        entry = summary[key]
        entry["n"] += 1
        entry["exact"] += row["dist_sq"].endswith(",true")
        entry["tpos"] += not row["target_pos"].startswith("nil")
        entry["targets"].add(row["target"])

    print(f"{len(rows)} rows, {len(marks)} marks")
    for time, note in marks:
        print(f"  MARK {time} {note}")
    print(f"{'map':>5} {'zone / subzone':40} {'combat':7} {'samples':>7} {'exact':>6} {'tpos':>6}  targets")
    for (map_id, zone, subzone, combat), entry in sorted(summary.items()):
        print(f"{map_id:>5} {(zone + ' / ' + subzone)[:40]:40} {combat:7} {entry['n']:>7} "
              f"{entry['exact']:>6} {entry['tpos']:>6}  {', '.join(sorted(entry['targets']))[:60]}")


if __name__ == "__main__":
    main()

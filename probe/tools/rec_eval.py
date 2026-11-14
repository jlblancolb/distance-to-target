#!/usr/bin/env python3
"""Analyse a DTTProbe 20 Hz recording (DTTProbeDB.rec) against the exact distance.

1. Where each range check really flips, in centre distance.
2. Distance estimators replayed on the real check results:
   - bracket midpoint (nominal ranges + hitbox offset)
   - particle filter (same measurements + the player's own exact position)

Usage: rec_eval.py <SavedVariables/DTTProbe.lua> [--verbose]
Note: item checkers from LibRangeCheck return nil instead of false ("-" = out of range).
"""
import math
import random
import re
import statistics
import sys

REACH = 2.25       # nominal range + REACH = centre distance where an item/spell check flips (2.0-2.5 seen)
FAST_P = 0.1       # share of particles that move fast (target starts running)
FAST = 7.0         # yd/s
N = 500
CLAMP = True


def load(path):
    text = open(path, encoding="utf-8", errors="replace").read()
    rec = text[text.find('["rec"]'):]
    checks = re.findall(r'"([^"]*)"', re.search(r'\["checks"\] = \{(.*?)\}', rec, re.S).group(1))
    rows = re.findall(r'"([DTM]\|[^"]*)"', rec)
    return checks, rows


def nominal(check):
    """(min, max) nominal range of a check, or None if unknown."""
    m = re.search(r"@(\d+(?:\.\d+)?)-(\d+(?:\.\d+)?)$", check)
    if m:
        return float(m.group(1)), float(m.group(2))
    m = re.search(r"@(\d+(?:\.\d+)?)$", check)
    if m:
        return 0.0, float(m.group(1))
    return None


def parse(rows):
    samples, target, hostile = [], None, True
    for row in rows:
        f = row.split("|")
        if f[0] == "T":
            target = f[3]
            hostile = f[4] == "true"
            continue
        if f[0] != "D":
            continue
        sq, checked = f[7].split(",")
        if checked != "true":
            continue
        px, py = map(float, f[3].split(","))
        tx, ty = map(float, f[8].split(","))
        samples.append({
            "t": float(f[1]), "combat": f[2] == "c", "p": (px, py), "tgt": (tx, ty),
            "d": math.sqrt(float(sq)), "speed": f[5], "bits": f[12], "target": target, "hostile": hostile,
        })
    return samples


def thresholds(checks, samples):
    print(f"{'check':22} {'nominal':>9}  {'last in':>8} {'first out':>9}  flip≈  offset")
    calibrated = {}
    for i, check in enumerate(checks):
        nom = nominal(check)
        if nom and nom[0] > 0:
            inner_in = [s["d"] for s in samples if s["bits"][i] == "1"]
            inner_out = [s["d"] for s in samples if s["bits"][i] in "0-" and s["d"] < (nom[0] + nom[1]) / 2]
            outer_out = [s["d"] for s in samples if s["bits"][i] in "0-" and s["d"] >= (nom[0] + nom[1]) / 2]
            if inner_in:
                print(f"{check:22} min {nom[0]:g}: last out {max(inner_out or [0]):5.1f} first in {min(inner_in):5.1f}"
                      f" | max {nom[1]:g}: last in {max(inner_in):5.1f} first out {min(outer_out or [999]):5.1f}")
                calibrated[i] = ((max(inner_out or [0]) + min(inner_in)) / 2, (max(inner_in) + min(outer_out or [999])) / 2)
            continue
        inside = [s["d"] for s in samples if s["bits"][i] == "1"]
        outside = [s["d"] for s in samples if s["bits"][i] in "0-"]
        if not inside or not outside:
            print(f"{check:22} {str(nom):>9}  {'-':>8} {'-':>9}  (always {'in' if inside else 'out'})")
            continue
        last_in, first_out = max(inside), min(outside)
        # flip = distance that best separates in/out
        candidates = sorted(set(inside + outside))
        best = min(candidates, key=lambda c: sum(d > c for d in inside) + sum(d <= c for d in outside))
        errors = sum(d > best for d in inside) + sum(d <= best for d in outside)
        offset = best - nom[1] if nom else float("nan")
        calibrated[i] = best
        print(f"{check:22} {str(nom[1]) if nom else '?':>9}  {last_in:8.1f} {first_out:9.1f}  {best:5.1f}  "
              f"{offset:+5.1f}  ({errors} misfits / {len(inside) + len(outside)})")
    return calibrated


def bounds(bits, edges):
    """Tightest (lo, hi) centre-distance interval implied by all checks."""
    lo, hi = 0.0, 200.0
    for i, r in edges.items():
        b = bits[i]
        if isinstance(r, tuple):          # min-range check: only "in range" is informative
            if b == "1":
                lo, hi = max(lo, r[0]), min(hi, r[1])
            continue
        if b == "1":
            hi = min(hi, r)
        elif b in "0-":
            lo = max(lo, r)
    if lo > hi:            # inconsistent checks (lag): widen
        lo, hi = hi, lo
    return lo, hi


def phi(x):
    return 0.5 * (1 + math.erf(x / math.sqrt(2)))


class Filter:
    def __init__(self, p, lo, hi, sigma, wander):
        self.sigma, self.wander = sigma, wander
        hi = min(hi, lo + 60)
        self.parts = []
        for _ in range(N):
            r, a = random.uniform(lo, hi), random.uniform(0, 2 * math.pi)
            self.parts.append([p[0] + r * math.cos(a), p[1] + r * math.sin(a)])
        self.w = [1.0 / N] * N

    def step(self, p, dt, lo, hi):
        root = math.sqrt(max(dt, 0.02))
        for part in self.parts:
            s = (FAST if random.random() < FAST_P else self.wander) * root
            part[0] += random.gauss(0, s)
            part[1] += random.gauss(0, s)
        total = 0.0
        for i, part in enumerate(self.parts):
            d = math.dist(p, part)
            self.w[i] *= phi((d - lo) / self.sigma) * phi((hi - d) / self.sigma) + 1e-12
            total += self.w[i]
        self.w = [w / total for w in self.w]
        if 1.0 / sum(w * w for w in self.w) < N / 2:
            self.resample()
        ds = [math.dist(p, part) for part in self.parts]
        mean = sum(w * d for w, d in zip(self.w, ds))
        return mean, math.sqrt(sum(w * (d - mean) ** 2 for w, d in zip(self.w, ds)))

    def resample(self):
        step, u = 1.0 / N, random.random() / N
        cum, i, new = self.w[0], 0, []
        for _ in range(N):
            while u > cum and i < N - 1:
                i += 1
                cum += self.w[i]
            new.append([self.parts[i][0] + random.gauss(0, 0.2), self.parts[i][1] + random.gauss(0, 0.2)])
            u += step
        self.parts, self.w = new, [1.0 / N] * N


def run(samples, edges, sigma, wander, verbose=False):
    random.seed(3)
    out = []
    f, prev, prev_target = None, None, None
    for s in samples:
        lo, hi = bounds(s["bits"], edges)
        if f is None or s["target"] != prev_target or s["t"] - prev["t"] > 1:
            f = Filter(s["p"], lo, hi, sigma, wander)
            prev = s
        est, spread = f.step(s["p"], s["t"] - prev["t"], lo, hi)
        if CLAMP:
            est = min(max(est, lo), hi)
        mid = (lo + min(hi, lo + 10)) / 2
        out.append((s, est, spread, mid, lo, hi))
        prev, prev_target = s, s["target"]
        if verbose:
            print(f"{s['t']:.2f} {'C' if s['combat'] else '-'} truth {s['d']:5.1f}  pf {est:5.1f}±{spread:3.1f}"
                  f"  [{lo:4.1f},{hi:5.1f}] mid {mid:5.1f}")
    return out


def summary(name, errs):
    errs = sorted(errs)
    if not errs:
        return
    print(f"  {name:30} n={len(errs):4}  median {statistics.median(errs):4.2f}  mean {statistics.mean(errs):4.2f}"
          f"  90% {errs[int(len(errs) * 0.9)]:4.2f}  max {errs[-1]:5.2f}")


def main():
    checks, rows = load(sys.argv[1])
    all_samples = parse(rows)
    group = sys.argv[2] if len(sys.argv) > 2 and not sys.argv[2].startswith("--") else "hostile"
    samples = [s for s in all_samples if s["hostile"] == (group == "hostile")]
    print(f"{len(samples)} {group} samples with exact distance, {len(checks)} checks\n")
    calibrated = thresholds(checks, samples)

    # The addon would use only checks that apply to the target (harm list for a
    # hostile mob), so drop checks that never said "in range" (friendly-only
    # items and spells) and the 100 yd item (never out in this data).
    usable = {i for i in range(len(checks)) if any(s["bits"][i] == "1" for s in samples)
              and any(s["bits"][i] in "0-" for s in samples)}
    nominal_edges = {}
    for i, check in enumerate(checks):
        nom = nominal(check)
        if i in usable and nom and not check.startswith("interact:"):
            nominal_edges[i] = (nom[0] + REACH, nom[1] + REACH) if nom[0] > 0 else nom[1] + REACH
    # Interact distances measured here (Tauren): follow/inspect 30.0, duel/trade 9.9, centre distance.
    nominal_plus_interact = dict(nominal_edges)
    for i, check in enumerate(checks):
        if i in usable and check in ("interact:1", "interact:4"):
            nominal_plus_interact[i] = 29.9
        elif i in usable and check in ("interact:2", "interact:3", "interact:5"):
            nominal_plus_interact[i] = 9.85

    calibrated = {i: r for i, r in calibrated.items() if i in usable}
    for label, edges in (("nominal ranges + 2.5 (items/spells only)", nominal_edges),
                         ("nominal + measured interact", nominal_plus_interact),
                         ("all calibrated (in-sample)", calibrated)):
        print(f"\n== {label} ==")
        for sigma, wander in ((0.5, 1.0), (1.0, 1.5), (0.7, 2.0)):
            res = run(samples, edges, sigma, wander)
            melee = [r for r in res if r[4] == 0]
            near = [r for r in res if r[0]["d"] < 45 and r[4] > 0]
            print(f" filter sigma={sigma} wander={wander}")
            summary("midpoint, < 45 yd", [abs(r[3] - r[0]["d"]) for r in near])
            summary("filter, < 45 yd", [abs(r[1] - r[0]["d"]) for r in near])
            summary("filter, < 45 yd, standing", [abs(r[1] - r[0]["d"]) for r in near if r[0]["speed"] == "0.00"])
            summary("filter, combat", [abs(r[1] - r[0]["d"]) for r in near if r[0]["combat"]])
            print(f"  melee bracket (shown as <= 5 yd): {len(melee)} samples, truth max "
                  f"{max([r[0]['d'] for r in melee] or [0]):.1f} yd centre")
    if "--verbose" in sys.argv:
        run(samples, nominal_edges, 0.5, 1.0, verbose=True)


if __name__ == "__main__":
    main()

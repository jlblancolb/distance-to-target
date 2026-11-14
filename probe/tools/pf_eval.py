#!/usr/bin/env python3
"""Offline test of a particle filter that estimates target distance from
range brackets + the player's own position, scored against samples where the
game gave the exact distance (starter NPCs).

Usage: pf_eval.py trace.csv [--verbose]
"""
import csv
import math
import random
import statistics
import sys

N = 600            # particles
REACH = 2.5        # yd: range checks measure to the hitbox edge, ~2.5 yd short of centre
EDGE_SIGMA = 1.5   # yd: soft bracket edges (sampling lag, per-target hitbox size)
WANDER = 1.5       # yd/s: target random-walk speed
JUMP_P = 0.05      # chance per step that a particle moves fast (target started running)
JUMP_SPEED = 7.0   # yd/s


def phi(x):
    return 0.5 * (1 + math.erf(x / math.sqrt(2)))


def parse_time(text):
    h, m, s = text.split(":")
    return int(h) * 3600 + int(m) * 60 + float(s)


def sequences(path):
    """Consecutive samples on one exact-distance target, split on gaps or jumps."""
    rows = [r for r in csv.DictReader(open(path)) if r["combat"] != "MARK"]
    seq, last = [], None
    for r in rows:
        if not r["dist_sq"].endswith(",true"):
            continue
        lo, hi = r["lrc"].split(",")
        sample = {
            "t": parse_time(r["time"]),
            "p": tuple(map(float, r["player_pos"].split(",")[:2])),
            "tgt": tuple(map(float, r["target_pos"].split(",")[:2])),
            "lo": float(lo),
            "hi": float(hi) if hi != "nil" else None,
            "name": r["target"],
        }
        if last and (sample["name"] != last["name"] or math.dist(sample["tgt"], last["tgt"]) > 8):
            if len(seq) > 3:
                yield seq
            seq = []
        seq.append(sample)
        last = sample
    if len(seq) > 3:
        yield seq


class Filter:
    def __init__(self, p, lo, hi):
        hi = hi if hi is not None else lo + 30
        self.parts = []
        for _ in range(N):
            r = random.uniform(lo, hi) + REACH
            a = random.uniform(0, 2 * math.pi)
            self.parts.append([p[0] + r * math.cos(a), p[1] + r * math.sin(a)])
        self.w = [1.0 / N] * N

    def predict(self, dt):
        for part in self.parts:
            speed = JUMP_SPEED if random.random() < JUMP_P else WANDER
            s = speed * math.sqrt(max(dt, 0.05))
            part[0] += random.gauss(0, s)
            part[1] += random.gauss(0, s)

    def update(self, p, lo, hi):
        lo_c = lo + REACH
        hi_c = (hi + REACH) if hi is not None else 1e9
        total = 0.0
        for i, part in enumerate(self.parts):
            d = math.dist(p, part)
            like = phi((d - lo_c) / EDGE_SIGMA) * phi((hi_c - d) / EDGE_SIGMA)
            self.w[i] *= like + 1e-9
            total += self.w[i]
        self.w = [w / total for w in self.w]
        ess = 1.0 / sum(w * w for w in self.w)
        if ess < N / 2:
            self.resample()

    def resample(self):
        step, u = 1.0 / N, random.random() / N
        cum, i, new = self.w[0], 0, []
        for _ in range(N):
            while u > cum:
                i += 1
                cum += self.w[i]
            x, y = self.parts[i]
            new.append([x + random.gauss(0, 0.3), y + random.gauss(0, 0.3)])
            u += step
        self.parts, self.w = new, [1.0 / N] * N

    def estimate(self, p):
        ds = [math.dist(p, part) for part in self.parts]
        mean = sum(w * d for w, d in zip(self.w, ds))
        var = sum(w * (d - mean) ** 2 for w, d in zip(self.w, ds))
        return mean, math.sqrt(var)


def midpoint(lo, hi):
    return (lo + (hi if hi is not None else lo + 10)) / 2 + REACH


def main():
    random.seed(1)
    verbose = "--verbose" in sys.argv
    pf_err, mid_err, steps = [], [], []
    for seq in sequences(sys.argv[1]):
        f = Filter(seq[0]["p"], seq[0]["lo"], seq[0]["hi"])
        prev_t = seq[0]["t"]
        for k, s in enumerate(seq):
            f.predict(abs(s["t"] - prev_t))
            prev_t = s["t"]
            f.update(s["p"], s["lo"], s["hi"])
            est, spread = f.estimate(s["p"])
            truth = math.dist(s["p"], s["tgt"])
            mid = midpoint(s["lo"], s["hi"])
            pf_err.append(abs(est - truth))
            mid_err.append(abs(mid - truth))
            steps.append(k)
            if verbose:
                print(f"{s['name'][:14]:14} k={k:2} truth {truth:5.1f}  pf {est:5.1f} ±{spread:4.1f}  "
                      f"bracket {s['lo']:.0f}-{s['hi'] if s['hi'] is not None else '∞'} mid {mid:5.1f}")
        if verbose:
            print()

    def report(name, errs):
        errs = sorted(errs)
        print(f"{name:22} mean {statistics.mean(errs):4.1f} yd  median {statistics.median(errs):4.1f}  "
              f"90% {errs[int(len(errs) * 0.9)]:4.1f}")

    print(f"{len(pf_err)} samples")
    report("bracket midpoint", mid_err)
    report("particle filter", pf_err)
    warm = [e for e, k in zip(pf_err, steps) if k >= 4]
    warm_mid = [e for e, k in zip(mid_err, steps) if k >= 4]
    report("midpoint, after 2 s", warm_mid)
    report("filter, after 2 s", warm)


if __name__ == "__main__":
    main()

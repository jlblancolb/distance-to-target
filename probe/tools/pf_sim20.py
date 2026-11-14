#!/usr/bin/env python3
"""Replay real player/target paths at 20 Hz with simulated range checks
(thresholds measured to the hitbox edge) and score filter vs bracket midpoint.
Optimistic: the bracket model is our own, so this shows potential, not proof."""
import math, random, statistics, sys
sys.path.insert(0, __import__("os").path.dirname(__file__))
import pf_eval as pe

THRESHOLDS = [5, 8, 10, 15, 20, 25, 28, 30, 35, 40, 45, 100]   # hostile items + interact on Forever
HZ = 20

def bracket(d_edge):
    lo, hi = 0, None
    for r in THRESHOLDS:
        if d_edge <= r:
            hi = r
            break
        lo = r
    return lo, hi

def main():
    random.seed(2)
    pe.N = 400
    if len(sys.argv) > 3: pe.REACH = float(sys.argv[3])
    pe.EDGE_SIGMA = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0
    errs = {"mid": [], "pf": []}
    for seq in pe.sequences(sys.argv[1]):
        reach = float(sys.argv[3]) if len(sys.argv) > 3 else random.uniform(1.5, 3.5)
        f = None
        for a, b in zip(seq, seq[1:]):
            dt = max(b["t"] - a["t"], 0.1)
            if dt > 2:
                continue
            for i in range(int(dt * HZ)):
                u = i / (dt * HZ)
                p = (a["p"][0] + u * (b["p"][0] - a["p"][0]), a["p"][1] + u * (b["p"][1] - a["p"][1]))
                t = (a["tgt"][0] + u * (b["tgt"][0] - a["tgt"][0]), a["tgt"][1] + u * (b["tgt"][1] - a["tgt"][1]))
                truth = math.dist(p, t)
                lo, hi = bracket(truth - reach)
                if f is None:
                    f = pe.Filter(p, lo, hi)
                f.predict(1 / HZ)
                f.update(p, lo, hi)
                est, _ = f.estimate(p)
                errs["pf"].append(abs(est - truth)); errs.setdefault("pf<45",[]); errs.setdefault("mid<45",[])
                if truth < 45: errs["pf<45"].append(abs(est-truth)); errs["mid<45"].append(abs(pe.midpoint(lo,hi)-truth))
                errs["mid"].append(abs(pe.midpoint(lo, hi) - truth))
    for k, v in errs.items():
        v = sorted(v)
        print(f"{k:4} n={len(v)} mean {statistics.mean(v):4.2f}  median {statistics.median(v):4.2f}  90% {v[int(len(v)*.9)]:4.2f}")

main()

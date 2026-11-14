-- Distance estimator. Pure Lua with no WoW API calls, so tests and
-- tools/replay.lua can run it on recorded sessions.
--
-- The game only says "in range" or "out of range" for each check. Each answer
-- puts the target inside or outside a circle around the player. A particle
-- filter tracks where the target probably is, using the player's own position
-- (which the game does give in the open world) to combine answers over time.
--
-- Distances here are centre to centre. Shown text is "spell distance"
-- (centre - REACH), the number spell and item ranges use.
local _, ns = ...
ns = ns or {}

local E = {}
ns.Estimator = E

local huge, sqrt, exp, abs, floor, cos, sin, log, min, max =
    math.huge, math.sqrt, math.exp, math.abs, math.floor, math.cos, math.sin, math.log, math.min, math.max
local format = string.format

-- Measured on Forever 1.60.1 (probe/data, 2026-11-10): item and spell checks
-- flip 2.0-2.5 yd past their nominal range (target hitbox); interact checks
-- flip at fixed centre distances for every race and target.
E.REACH = 2.25
E.INTERACT = { [3] = 9.85, [4] = 29.9 }

E.SIGMA = 0.5       -- yd, softness of each edge
E.WANDER = 1.0      -- yd/s, normal target movement
E.FAST_SHARE = 0.1  -- share of particles that move fast (target starts running)
E.FAST = 7.0        -- yd/s
E.PARTICLES = 200
E.UNSURE = 2.0      -- yd of spread above which the number gets a "~"
E.WIDE = 25         -- yd: a bracket this wide says too little for a number
E.HOLD = 0.75       -- yd the estimate must move before the shown number changes
E.GAP = 1.0         -- s without an update that restarts the filter
E.JUMP = 40         -- yd the player can move in one update before we restart

function E.ItemEdge(range)
    return range + E.REACH
end

-- Returns inner edge (nil without a minimum range) and outer edge.
function E.SpellEdges(minRange, maxRange)
    local inner = minRange and minRange > 0 and minRange + E.REACH or nil
    return inner, maxRange + E.REACH
end

-- Narrow the [lo, hi] interval with one check result.
-- A check with a minimum range only tells something when it says "in range"
-- (out could mean too close or too far).
function E.Narrow(lo, hi, inner, outer, inRange)
    if inner then
        if inRange then
            return max(lo, inner), min(hi, outer)
        end
        return lo, hi
    end
    if inRange then
        return lo, min(hi, outer)
    end
    return max(lo, outer), hi
end

-- Checks read a tick apart can disagree for a moment; widen instead of failing.
function E.Settle(lo, hi)
    if lo > hi then
        return hi, lo
    end
    return lo, hi
end

-- Standard normal CDF (Abramowitz-Stegun 7.1.26, error < 1.5e-7).
local SQRT2 = sqrt(2)
local function Phi(z)
    if z == huge then
        return 1
    elseif z == -huge then
        return 0
    end
    local x = abs(z) / SQRT2
    local t = 1 / (1 + 0.3275911 * x)
    local y = 1 - ((((1.061405429 * t - 1.453152027) * t + 1.421413741) * t - 0.284496736) * t + 0.254829592)
        * t * exp(-x * x)
    if z >= 0 then
        return 0.5 * (1 + y)
    end
    return 0.5 * (1 - y)
end
E.Phi = Phi

local Filter = {}
Filter.__index = Filter

function E.NewFilter(count, random)
    local filter = setmetatable({ n = count or E.PARTICLES, random = random or math.random,
        x = {}, y = {}, w = {}, nx = {}, ny = {} }, Filter)
    return filter
end

function Filter:Gauss()
    local spare = self.spare
    if spare then
        self.spare = nil
        return spare
    end
    local random = self.random
    local u = random()
    while u <= 1e-12 do
        u = random()
    end
    local r, a = sqrt(-2 * log(u)), 2 * math.pi * random()
    self.spare = r * sin(a)
    return r * cos(a)
end

-- Spread particles evenly over the ring the checks allow.
function Filter:Reset(px, py, lo, hi)
    hi = min(hi, lo + 60)
    local random, n = self.random, self.n
    for i = 1, n do
        local r, a = lo + (hi - lo) * random(), 2 * math.pi * random()
        self.x[i], self.y[i], self.w[i] = px + r * cos(a), py + r * sin(a), 1 / n
    end
end

function Filter:Resample()
    local n, x, y, w, nx, ny = self.n, self.x, self.y, self.w, self.nx, self.ny
    local step = 1 / n
    local u, cum, i = self.random() * step, w[1], 1
    for k = 1, n do
        while u > cum and i < n do
            i = i + 1
            cum = cum + w[i]
        end
        nx[k], ny[k] = x[i] + self:Gauss() * 0.2, y[i] + self:Gauss() * 0.2
        u = u + step
    end
    self.x, self.y, self.nx, self.ny = nx, ny, x, y
    for k = 1, n do
        w[k] = step
    end
end

-- Move every particle, weigh it by how well it fits [lo, hi], and return the
-- weighted mean distance and its spread.
function Filter:Step(px, py, dt, lo, hi)
    local n, random, sigma = self.n, self.random, E.SIGMA
    local x, y, w = self.x, self.y, self.w
    local root = sqrt(max(dt, 0.02))
    local slow, fast, share = E.WANDER * root, E.FAST * root, E.FAST_SHARE
    local total = 0
    for i = 1, n do
        local s = random() < share and fast or slow
        x[i] = x[i] + self:Gauss() * s
        y[i] = y[i] + self:Gauss() * s
        local dx, dy = x[i] - px, y[i] - py
        local d = sqrt(dx * dx + dy * dy)
        local fit = Phi((d - lo) / sigma) * (hi == huge and 1 or Phi((hi - d) / sigma))
        w[i] = w[i] * fit + 1e-12
        total = total + w[i]
    end
    local squares = 0
    for i = 1, n do
        w[i] = w[i] / total
        squares = squares + w[i] * w[i]
    end
    if 1 / squares < n / 2 then
        self:Resample()
        x, y = self.x, self.y
    end
    local mean, meanSq = 0, 0
    for i = 1, n do
        local dx, dy = x[i] - px, y[i] - py
        local d = sqrt(dx * dx + dy * dy)
        mean = mean + w[i] * d
        meanSq = meanSq + w[i] * d * d
    end
    return mean, sqrt(max(meanSq - mean * mean, 0))
end

local function Round(value)
    return floor(value + 0.5)
end

-- Text for the display, and a kind for colouring: "melee", "estimate",
-- "unsure", "bracket", "far", or nil text when no check says anything.
function E.Text(lo, hi, est, spread, shown)
    local reach = E.REACH
    if hi < huge and lo <= 0 then
        return format("< %d yd", max(Round(hi - reach), 1)), "melee"
    end
    if hi == huge or hi - lo > E.WIDE then
        if lo <= 0 then
            return nil
        end
        return format("> %d yd", Round(lo - reach)), "far"
    end
    if not est then
        return format("%d - %d yd", Round(lo - reach), Round(hi - reach)), "bracket"
    end
    local yards = est - reach
    if shown and abs(yards - shown) < E.HOLD then
        yards = shown
    end
    yards = max(Round(yards), 0)
    if spread > E.UNSURE then
        return format("~%d yd", yards), "unsure", yards
    end
    return format("%d yd", yards), "estimate", yards
end

-- Keeps one filter per target and turns check results into text.
local Tracker = {}
Tracker.__index = Tracker

function E.NewTracker(count, random)
    return setmetatable({ filter = E.NewFilter(count, random) }, Tracker)
end

function Tracker:Reset()
    self.time, self.px, self.py, self.shown = nil, nil, nil, nil
    self.est, self.spread = nil, nil
end

-- Exact centre distance, where the game gives one (group members in the open
-- world, a few NPCs): no filter needed.
function Tracker:Exact(centre)
    local shown = self.shown
    self:Reset()
    self.lo, self.hi = centre, centre
    local yards = centre - E.REACH
    if yards < 5 then
        return "< 5 yd", "melee"
    end
    if shown and abs(yards - shown) < E.HOLD then
        yards = shown
    end
    yards = Round(yards)
    self.shown = yards
    return format("%d yd", yards), "estimate"
end

-- px, py: the player's position, nil where the game hides it (instances).
-- lo, hi: centre-distance interval from this tick's checks.
function Tracker:Update(now, px, py, lo, hi)
    lo, hi = E.Settle(lo, hi)
    self.lo, self.hi = lo, hi
    if not px or lo <= 0 or hi == huge then
        -- No position, or no ring to put particles on: the bracket is all we have.
        self.time, self.est, self.spread = nil, nil, nil
    else
        local last = self.time
        local dt = last and now - last or 0
        if not last or dt > E.GAP or dt < 0 or abs(px - self.px) + abs(py - self.py) > E.JUMP then
            self.filter:Reset(px, py, lo, hi)
            self.shown = nil
            dt = 0
        end
        local est, spread = self.filter:Step(px, py, dt, lo, hi)
        self.est, self.spread = min(max(est, lo), hi), spread
        self.time, self.px, self.py = now, px, py
    end
    local text, kind, shown = E.Text(lo, hi, self.est, self.spread, self.shown)
    self.shown = shown
    return text, kind
end

-- Estimator.lua: edges, intervals, text and the filter on a simulated target.
local ns = {}
assert(loadfile("Estimator.lua"))("DistanceToTarget", ns)
local E = ns.Estimator
local huge = math.huge

local function eq(actual, expected, label)
    assert(actual == expected, string.format("%s: got %s, expected %s", label, tostring(actual), tostring(expected)))
end

-- Edges.
eq(E.ItemEdge(30), 32.25, "item edge")
local inner, outer = E.SpellEdges(8, 35)
eq(inner, 10.25, "spell inner")
eq(outer, 37.25, "spell outer")
inner = E.SpellEdges(0, 30)
eq(inner, nil, "no inner edge without a min range")

-- Narrowing.
local lo, hi = E.Narrow(0, huge, nil, 32.25, true)
eq(hi, 32.25, "in range sets hi")
lo, hi = E.Narrow(lo, hi, nil, 12.25, false)
eq(lo, 12.25, "out of range sets lo")
lo, hi = E.Narrow(lo, hi, 10.25, 37.25, false)
eq(lo, 12.25, "min-range check out of range says nothing (lo)")
eq(hi, 32.25, "min-range check out of range says nothing (hi)")
lo, hi = E.Narrow(0, huge, 10.25, 37.25, true)
eq(lo, 10.25, "min-range check in range sets lo")
lo, hi = E.Settle(20, 18)
eq(lo, 18, "inconsistent interval is swapped")

-- Text.
eq(E.Text(0, 7.25), "< 5 yd", "melee")
eq(E.Text(47.25, huge), "> 45 yd", "beyond the last check")
eq(E.Text(47.25, 102.25), "> 45 yd", "too wide a bracket")
eq(E.Text(0, huge), nil, "no information")
eq(E.Text(32.25, 37.25), "30 - 35 yd", "bracket without a position")
eq(E.Text(32.25, 37.25, 29.6, 0.5), "27 yd", "estimate")
eq(E.Text(32.25, 37.25, 29.6, 3), "~27 yd", "unsure estimate")
eq(E.Text(32.25, 37.25, 29.9, 0.5, 27), "27 yd", "small moves keep the shown number")
eq(E.Text(32.25, 37.25, 30.4, 0.5, 27), "28 yd", "bigger moves change it")
assert(math.abs(E.Phi(0) - 0.5) < 1e-6, "Phi(0)")
assert(math.abs(E.Phi(1.96) - 0.975) < 1e-4, "Phi(1.96)")

-- Filter on a standing target 27 yd away while the player walks a square,
-- with the checks a Hunter has on a hostile mob (as measured on Forever).
local seed = 11
local function Random()
    seed = (seed * 1103515245 + 12345) % 2147483648
    return seed / 2147483648
end
local edges = { { nil, E.ItemEdge(5) }, { nil, E.ItemEdge(10) }, { nil, E.ItemEdge(15) }, { nil, E.ItemEdge(20) },
    { nil, E.ItemEdge(25) }, { nil, E.ItemEdge(30) }, { nil, E.ItemEdge(35) }, { nil, E.ItemEdge(40) },
    { nil, E.INTERACT[3] }, { nil, E.INTERACT[4] }, { E.SpellEdges(8, 35) } }
local function Measure(distance)
    local l, h = 0, huge
    for _, edge in ipairs(edges) do
        local a, b = edge[1], edge[2]
        local inRange = distance <= b and (not a or distance >= a)
        l, h = E.Narrow(l, h, a, b, inRange)
    end
    return l, h
end

local tracker = E.NewTracker(200, Random)
local target = { 100, 100 }
local worst, sum, count = 0, 0, 0
for step = 0, 300 do
    local t = step * 0.1
    -- Walk a 12 yd square around a point 29 yd from the target.
    local side, along = math.floor(t / 3) % 4, (t % 3) * 4
    local corners = { { 0, 0 }, { 12, 0 }, { 12, 12 }, { 0, 12 } }
    local a, b = corners[side + 1], corners[side % 4 + 2] or corners[1]
    local px = 71 + a[1] + (b[1] - a[1]) * along / 12
    local py = 94 + a[2] + (b[2] - a[2]) * along / 12
    local truth = math.sqrt((px - target[1]) ^ 2 + (py - target[2]) ^ 2)
    local text, kind = tracker:Update(t, px, py, Measure(truth))
    assert(text and text:match("yd$"), "text every tick")
    if step > 50 then
        local err = math.abs(tracker.est - truth)
        worst, sum, count = math.max(worst, err), sum + err, count + 1
        assert(kind == "estimate" or kind == "unsure" or kind == "melee", kind)
    end
end
assert(sum / count < 1.5, string.format("mean error %.2f yd", sum / count))
assert(worst < 4, string.format("worst error %.2f yd", worst))

-- No position (instances): plain bracket, no filter.
tracker:Reset()
local text, kind = tracker:Update(0, nil, nil, Measure(33))
eq(text, "30 - 35 yd", "bracket text without a position")
eq(kind, "bracket", "bracket kind")
eq(tracker.est, nil, "no estimate without a position")

-- A teleport restarts the filter instead of dragging it along.
tracker:Reset()
tracker:Update(0, 0, 0, Measure(20))
tracker:Update(0.1, 500, 500, Measure(20))
eq(tracker.time, 0.1, "filter kept running after the jump")
assert(math.abs(tracker.est - 20) < 3, "estimate after a teleport")

print("estimator ok")

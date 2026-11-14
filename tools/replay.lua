-- Replays a DTTProbe recording (SavedVariables file) through Estimator.lua at
-- 10 Hz, the addon's update rate, and scores it against the exact distance.
--   npx --package=fengari-node-cli -- fengari tools/replay.lua <recording.lua> [hostile|friendly] [--verbose]
-- Check selection follows Checks.lua: items, spells with a range, interact 3
-- and 4. Hostile targets only use items that were both in and out at least
-- once (stands in for LibRangeCheck's harm list); friendly targets only trust
-- an item's "out" after it has been "in" on that target.
local path, group = arg[1], arg[2] or "hostile"
local verbose = arg[3] == "--verbose" or arg[2] == "--verbose"
if group == "--verbose" then
    group = "hostile"
end

local ns = {}
assert(loadfile("Estimator.lua"))("DistanceToTarget", ns)
local E = ns.Estimator
assert(loadfile(path))()
local rec = DTTProbeDB.rec

-- Column -> { kind, inner, outer }.
local columns = {}
for index, id in ipairs(rec.checks) do
    local item, range = id:match("^item:(%d+)@([%d.]+)$")
    local smin, smax = id:match("^spell:%d+@([%d.]+)-([%d.]+)$")
    local interact = tonumber(id:match("^interact:(%d)$"))
    if item then
        columns[index] = { kind = "item", outer = E.ItemEdge(tonumber(range)) }
    elseif smin then
        local inner, outer = E.SpellEdges(tonumber(smin), tonumber(smax))
        columns[index] = { kind = "spell", inner = inner, outer = outer }
    elseif interact and E.INTERACT[interact] then
        columns[index] = { kind = "interact", outer = E.INTERACT[interact] }
    end
end

local function Split(text)
    local out = {}
    for field in (text .. "|"):gmatch("([^|]*)|") do
        out[#out + 1] = field
    end
    return out
end

-- Samples with an exact distance, 10 Hz.
local samples, target, hostile, lastTime = {}, nil, true, -1
for _, row in ipairs(rec.rows) do
    local f = Split(row)
    if f[1] == "T" then
        target, hostile = f[4], f[5] == "true"
    elseif f[1] == "D" then
        local sq, checked = f[8]:match("^([^,]+),(%a+)$")
        local time = tonumber(f[2])
        if checked == "true" and time - lastTime >= 0.095 and hostile == (group == "hostile") then
            lastTime = time
            local px, py = f[4]:match("^([^,]+),([^,]+)$")
            samples[#samples + 1] = { time = time, combat = f[3] == "c", px = tonumber(px), py = tonumber(py),
                truth = math.sqrt(tonumber(sq)), bits = f[13], target = target }
        end
    end
end

local usable = {}
if group == "hostile" then
    local seenIn, seenOut = {}, {}
    for _, s in ipairs(samples) do
        for index = 1, #s.bits do
            local bit = s.bits:sub(index, index)
            seenIn[index] = seenIn[index] or bit == "1"
            seenOut[index] = seenOut[index] or bit == "0" or bit == "-"
        end
    end
    for index in pairs(columns) do
        usable[index] = seenIn[index] and seenOut[index]
    end
end

local seed = 7
local function Random()
    seed = (seed * 1103515245 + 12345) % 2147483648
    return seed / 2147483648
end

local tracker = E.NewTracker(E.PARTICLES, Random)
local errors, shownErrors, melee, far, kinds = {}, {}, 0, 0, {}
local currentTarget, itemSeenIn
for _, s in ipairs(samples) do
    if s.target ~= currentTarget then
        currentTarget, itemSeenIn = s.target, {}
        tracker:Reset()
    end
    local lo, hi = 0, math.huge
    for index, column in pairs(columns) do
        local bit = s.bits:sub(index, index)
        local inRange
        if bit == "1" then
            inRange = true
        elseif bit == "0" then
            inRange = false
        elseif bit == "-" and column.kind == "item" then
            inRange = false
        end
        if column.kind == "item" and inRange ~= nil then
            if group == "hostile" then
                if not usable[index] then
                    inRange = nil
                end
            elseif inRange then
                itemSeenIn[index] = true
            elseif not itemSeenIn[index] then
                inRange = nil
            end
        end
        if inRange ~= nil then
            lo, hi = E.Narrow(lo, hi, column.inner, column.outer, inRange)
        end
    end
    local text, kind = tracker:Update(s.time, s.px, s.py, lo, hi)
    kinds[kind or "none"] = (kinds[kind or "none"] or 0) + 1
    if kind == "melee" then
        melee = melee + 1
    elseif kind == "far" then
        far = far + 1
    elseif tracker.est and s.truth < 45 then
        errors[#errors + 1] = math.abs(tracker.est - s.truth)
        local shown = tonumber(text:match("(%d+) yd"))
        shownErrors[#shownErrors + 1] = math.abs(shown + E.REACH - s.truth)
    end
    if verbose then
        print(string.format("%8.2f %s truth %5.1f  [%5.1f, %5.1f]  est %s  %s", s.time, s.combat and "C" or "-",
            s.truth, tracker.lo, math.min(tracker.hi, 999), tracker.est and string.format("%5.1f", tracker.est)
            or "  -  ", text or "(none)"))
    end
end

local function Summary(name, list)
    table.sort(list)
    if #list == 0 then
        print(name .. ": no samples")
        return
    end
    local function At(share) return list[math.max(1, math.floor(#list * share + 0.5))] end
    local sum = 0
    for _, value in ipairs(list) do
        sum = sum + value
    end
    print(string.format("  %-28s n=%4d  median %4.2f  mean %4.2f  90%% %4.2f  max %5.2f", name, #list, At(0.5),
        sum / #list, At(0.9), list[#list]))
end

print(string.format("%s: %d %s samples at 10 Hz", path, #samples, group))
Summary("estimate, < 45 yd", errors)
Summary("shown number, < 45 yd", shownErrors)
local parts = {}
for kind, count in pairs(kinds) do
    parts[#parts + 1] = kind .. "=" .. count
end
table.sort(parts)
print("  shown as: " .. table.concat(parts, " "))

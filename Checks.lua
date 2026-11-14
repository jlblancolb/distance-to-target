-- Runs every range check that can say something about the target and turns
-- the answers into a centre-distance interval [lo, hi].
--   items:    LibRangeCheck-3.0's harm or friend item list (it caches the items)
--   spells:   every spellbook spell with a range, one per distinct min/max
--   interact: duel (3) and follow (4) distance
-- Mainline blocks item and interact checks on friendly units in combat, so
-- those are skipped there. Secret or errored answers are ignored.
-- Some units answer "out" to every item whatever the distance: friendly NPCs
-- (Kaltunk, 2026-11-10) and corpses (2026-11-11). So item answers only count
-- when at least one item says "in" in the same round. Corpses can also say
-- "in" to the 5 and 10 yd items and "out" to every larger one (2026-11-14):
-- items that contradict each other are all ignored.
-- Some spells answer for another unit: Health Funnel (pet only) said "in" to
-- a mob 37+ yd away, which pulled the estimate to ~26 yd (2026-11-14). So
-- helpful-only spells are skipped on hostile targets, and spells are read
-- last and ignored when they contradict the item and interact answers.
local _, ns = ...
local E = ns.Estimator
local LRC = LibStub("LibRangeCheck-3.0")
local isSecret = issecretvalue or function() return false end

local Checks = {}
ns.Checks = Checks

local spells = {}           -- { id, edges, helpOnly, conflicts }
local itemIds, itemRanges, itemIn = {}, {}, {} -- this round's item answers, reused

local function Plain(value)
    return value ~= nil and not isSecret(value)
end

local function SpellInfo(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and info then
            return info.minRange, info.maxRange
        end
    elseif GetSpellInfo then
        local ok, _, _, _, _, minRange, maxRange = pcall(GetSpellInfo, spellID)
        if ok then
            return minRange, maxRange
        end
    end
end

-- True when the spell can only be cast on friendly units.
local function HelpOnly(spellID)
    local help, harm
    if C_Spell and C_Spell.IsSpellHelpful and C_Spell.IsSpellHarmful then
        local okHelp, isHelp = pcall(C_Spell.IsSpellHelpful, spellID)
        local okHarm, isHarm = pcall(C_Spell.IsSpellHarmful, spellID)
        help, harm = okHelp and isHelp, okHarm and isHarm
    elseif IsHelpfulSpell and IsHarmfulSpell and GetSpellInfo then
        local name = GetSpellInfo(spellID)
        if name then
            local okHelp, isHelp = pcall(IsHelpfulSpell, name)
            local okHarm, isHarm = pcall(IsHarmfulSpell, name)
            help, harm = okHelp and isHelp, okHarm and isHarm
        end
    end
    if isSecret(help) or isSecret(harm) then
        return false
    end
    return help and not harm and true or false
end

-- Spells that only target your pet answer for the pet, not the target.
-- Matched by name so every rank counts: Health Funnel, Mend Pet, Feed Pet,
-- Revive Pet, Eyes of the Beast.
local PET_SPELLS = { 755, 136, 6991, 982, 1002 }

local function SpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        return ok and not isSecret(name) and name or nil
    elseif GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, spellID)
        return ok and not isSecret(name) and name or nil
    end
end

local function AddSpell(spellID, seen, petNames)
    local name = SpellName(spellID)
    if name and petNames[name] then
        return
    end
    local minRange, maxRange = SpellInfo(spellID)
    if not (Plain(maxRange) and Plain(minRange)) or maxRange <= 0 then
        return
    end
    local helpOnly = HelpOnly(spellID)
    local key = minRange .. "-" .. maxRange .. (helpOnly and "h" or "")
    if seen[key] then
        return
    end
    seen[key] = true
    local inner, outer = E.SpellEdges(minRange, maxRange)
    spells[#spells + 1] = { id = spellID, inner = inner, outer = outer, minRange = minRange, maxRange = maxRange,
        helpOnly = helpOnly, conflicts = 0 }
end

-- Spellbook IDs of the player's own active spells.
local function EachSpellbookSpell(callback)
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
        local ok, lines = pcall(C_SpellBook.GetNumSpellBookSkillLines)
        for line = 1, ok and lines or 0 do
            local okLine, info = pcall(C_SpellBook.GetSpellBookSkillLineInfo, line)
            if okLine and info then
                for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                    local okItem, item = pcall(C_SpellBook.GetSpellBookItemInfo, slot, bank)
                    if okItem and item and item.spellID and not item.isPassive then
                        callback(item.spellID)
                    end
                end
            end
        end
    elseif GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemInfo then
        for tab = 1, GetNumSpellTabs() do
            local _, _, offset, count = GetSpellTabInfo(tab)
            for slot = offset + 1, offset + count do
                local ok, kind, spellID = pcall(GetSpellBookItemInfo, slot, "spell")
                if ok and kind == "SPELL" and spellID and not (IsPassiveSpell and IsPassiveSpell(spellID)) then
                    callback(spellID)
                end
            end
        end
    end
end

function Checks.Build()
    for index = #spells, 1, -1 do
        spells[index] = nil
    end
    local seen, petNames = {}, {}
    for _, spellID in ipairs(PET_SPELLS) do
        local name = SpellName(spellID)
        if name then
            petNames[name] = true
        end
    end
    EachSpellbookSpell(function(spellID) AddSpell(spellID, seen, petNames) end)
    table.sort(spells, function(a, b) return a.outer < b.outer end)
end

function Checks.SpellCount()
    return #spells
end

local function SpellInRange(spellID, unit)
    if C_Spell and C_Spell.IsSpellInRange then
        return C_Spell.IsSpellInRange(spellID, unit)
    end
    local name = GetSpellInfo(spellID)
    local result = name and IsSpellInRange(name, unit)
    if result == nil then
        return nil
    end
    return result == 1
end

-- A spell answer further than this outside the item and interact interval
-- is wrong, not noise (item edges vary by about 0.5 yd).
Checks.TOLERANCE = 1.5
-- A spell that contradicts this many times is ignored until the next Build.
Checks.MAX_CONFLICTS = 5

-- True when every item that says "out" has a smaller range than every item
-- that says "in" (out means further than its range, in means closer).
local function ItemsAgree(count)
    local nearestIn = math.huge
    for index = 1, count do
        if itemIn[index] and itemRanges[index] < nearestIn then
            nearestIn = itemRanges[index]
        end
    end
    for index = 1, count do
        if not itemIn[index] and itemRanges[index] > nearestIn then
            return false
        end
    end
    return true
end

-- Calls report(kind, id, range, inRange) for every check that answered, when
-- given (debug output). Spells ignored for a contradiction are reported with
-- kind "conflict". Returns lo, hi, number of checks that answered.
function Checks.Measure(unit, hostile, inCombat, report)
    local lo, hi, used = 0, math.huge, 0
    local function Use(inRange, inner, outer, kind, id, range)
        lo, hi = E.Narrow(lo, hi, inner, outer, inRange)
        used = used + 1
        if report then
            report(kind, id, range, inRange)
        end
    end

    -- Items. LibRangeCheck turns "out" into nil, so nil means out here.
    if hostile or not inCombat then
        local list = hostile and LRC.harmRC or LRC.friendRC
        local count, anyIn = 0, false
        for _, rc in ipairs(list or {}) do
            local item = type(rc.info) == "string" and rc.info:match("^item:(%d+)")
            if item then
                local ok, result = pcall(rc.checker, unit, true)
                if ok and not isSecret(result) then
                    count = count + 1
                    itemIds[count], itemRanges[count], itemIn[count] = item, rc.range, result and true or false
                    anyIn = anyIn or itemIn[count]
                end
            end
        end
        if anyIn and ItemsAgree(count) then
            for index = 1, count do
                Use(itemIn[index], nil, E.ItemEdge(itemRanges[index]), "item", itemIds[index], itemRanges[index])
            end
        end
    end

    -- Interact distances.
    if (hostile or not inCombat) and CheckInteractDistance then
        for index, edge in pairs(E.INTERACT) do
            local ok, result = pcall(CheckInteractDistance, unit, index)
            if ok and not isSecret(result) then
                Use(result and true or false, nil, edge, "interact", index, edge - E.REACH)
            end
        end
    end

    -- Spells. nil means the spell can't be used on this unit.
    local tolerance = Checks.TOLERANCE
    for _, spell in ipairs(spells) do
        if spell.conflicts < Checks.MAX_CONFLICTS and not (hostile and spell.helpOnly) then
            local ok, result = pcall(SpellInRange, spell.id, unit)
            if ok and Plain(result) then
                local inRange = result == true or result == 1
                local range = spell.inner and (spell.minRange .. "-" .. spell.maxRange) or spell.maxRange
                local conflict
                if inRange then
                    conflict = spell.outer < lo - tolerance or (spell.inner and spell.inner > hi + tolerance)
                else
                    conflict = not spell.inner and spell.outer > hi + tolerance
                end
                if conflict then
                    spell.conflicts = spell.conflicts + 1
                    if report then
                        report("conflict", spell.id, range, inRange)
                    end
                else
                    Use(inRange, spell.inner, spell.outer, "spell", spell.id, range)
                end
            end
        end
    end

    return lo, hi, used
end

-- 20 Hz recorder: logs every individual range check plus everything that could
-- help estimate distance (own position, facing, speeds, target nameplate on
-- screen, camera zoom), next to the exact distance where the game gives it.
-- Offline analysis: probe/tools/rec_eval.py.
--
-- Saved in DTTProbeDB.rec:
--   checks = { "item:8149@5", "spell:403@0-30", "interact:4", ... }   (column order)
--   screen = "width,height" of UIParent
--   rows   = { "T|..." target header, "D|..." data rows, "M|..." marks }
-- Data row fields:
--   D|time|combat|px,py|facing|playerSpeed|targetSpeed|distSq,checked|tx,ty|
--     nameplate x,y (UIParent units, nil if none)|cameraZoom|mouselook|bits
--   bits: one char per check: 1 in range, 0 out, - nil, S secret, E error

local _, ns = ...
local LRC = LibStub("LibRangeCheck-3.0")
local isSecret = issecretvalue or function() return false end

local INTERVAL = 0.05
local MAX_ROWS = 30000

local checks = {}
local recording = false
local elapsed = 0
local rec

local function Num(value, fmt)
    if value == nil then
        return "nil"
    end
    if isSecret(value) then
        return "S"
    end
    if type(value) == "number" then
        return string.format(fmt or "%.2f", value)
    end
    return tostring(value)
end

local function Call(func, ...)
    if type(func) ~= "function" then
        return false
    end
    return pcall(func, ...)
end

local function AddCheck(id, run)
    checks[#checks + 1] = { id = id, run = run }
end

-- Every distinct range check we can run on the target.
local function BuildChecks()
    wipe(checks)
    local seen = {}

    -- LibRangeCheck's own checker lists (one per range, items and spells).
    for _, listName in ipairs({ "harmRC", "friendRC", "miscRC" }) do
        local list = LRC[listName]
        if type(list) == "table" then
            for _, rc in ipairs(list) do
                local id = (rc.info or "?") .. "@" .. tostring(rc.range)
                if not seen[id] then
                    seen[id] = true
                    local checker = rc.checker
                    AddCheck(id, function() return checker("target", true) end)
                end
            end
        end
    end

    -- Interact distances (follow/duel/trade/inspect), unfiltered.
    for index = 1, 5 do
        AddCheck("interact:" .. index, function() return CheckInteractDistance("target", index) end)
    end

    -- Every spell in the spellbook with a range, one per distinct min/max.
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_Spell and C_Spell.IsSpellInRange then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
        local okLines, lines = Call(C_SpellBook.GetNumSpellBookSkillLines)
        for line = 1, (okLines and lines or 0) do
            local okInfo, info = Call(C_SpellBook.GetSpellBookSkillLineInfo, line)
            if okInfo and info then
                for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                    local okItem, item = Call(C_SpellBook.GetSpellBookItemInfo, slot, bank)
                    local spellID = okItem and item and item.spellID
                    if spellID and not item.isPassive then
                        local okSpell, spell = Call(C_Spell.GetSpellInfo, spellID)
                        if okSpell and spell and (spell.maxRange or 0) > 0 then
                            local id = string.format("spell:%d@%s-%s", spellID, Num(spell.minRange, "%g"),
                                Num(spell.maxRange, "%g"))
                            local key = Num(spell.minRange, "%g") .. "-" .. Num(spell.maxRange, "%g")
                            if not seen[key] then
                                seen[key] = true
                                AddCheck(id, function() return C_Spell.IsSpellInRange(spellID, "target") end)
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Item and interact checks on friendly targets are blocked in combat on
-- Mainline; skip them there ("x") instead of risking a blocked-action error.
local function Bits()
    local out = {}
    local okAttack, canAttack = Call(UnitCanAttack, "player", "target")
    local restricted = InCombatLockdown() and not (okAttack and not isSecret(canAttack) and canAttack)
    for index, check in ipairs(checks) do
        local ok, result
        if restricted and (check.id:find("^item:") or check.id:find("^interact:")) then
            ok, result = true, "x"
        else
            ok, result = pcall(check.run)
        end
        local char
        if result == "x" then
            char = "x"
        elseif not ok then
            char = "E"
        elseif isSecret(result) then
            char = "S"
        elseif result == nil then
            char = "-"
        elseif result == true or result == 1 then
            char = "1"
        else
            char = "0"
        end
        out[index] = char
    end
    return table.concat(out)
end

local function Pair(func, unit)
    local ok, a, b = Call(func, unit)
    if not ok then
        return "E"
    end
    return Num(a) .. "," .. Num(b)
end

local function Nameplate()
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then
        return "nil,nil"
    end
    -- Forever blocks measuring nameplates ("Can't measure restricted regions",
    -- 2026-11-10), so only record whether the target has one.
    local ok, plate = Call(C_NamePlate.GetNamePlateForUnit, "target")
    if not ok then
        return "E,nil"
    end
    return (plate and "1" or "0") .. ",nil"
end

local function Add(row)
    table.insert(rec.rows, row)
    while #rec.rows > MAX_ROWS do
        table.remove(rec.rows, 1)
    end
end

local function TargetHeader()
    local okName, name = Call(UnitName, "target")
    local okGuid, guid = Call(UnitGUID, "target")
    local okAttack, canAttack = Call(UnitCanAttack, "player", "target")
    Add(string.format("T|%.3f|%s|%s|%s", GetTime(), okName and Num(name) or "E", okGuid and Num(guid) or "E",
        okAttack and Num(canAttack) or "E"))
end

local function Sample()
    local okSq, squared, checked = Call(UnitDistanceSquared, "target")
    local okFacing, facing = Call(GetPlayerFacing)
    local okPs, playerSpeed = Call(GetUnitSpeed, "player")
    local okTs, targetSpeed = Call(GetUnitSpeed, "target")
    local okZoom, zoom = Call(GetCameraZoom)
    local okLook, look = Call(IsMouselooking)
    Add(table.concat({
        "D",
        string.format("%.3f", GetTime()),
        InCombatLockdown() and "c" or "-",
        Pair(UnitPosition, "player"),
        okFacing and Num(facing, "%.3f") or "E",
        okPs and Num(playerSpeed) or "E",
        okTs and Num(targetSpeed) or "E",
        okSq and (Num(squared) .. "," .. Num(checked)) or "E",
        Pair(UnitPosition, "target"),
        Nameplate(),
        okZoom and Num(zoom) or "E",
        okLook and Num(look) or "E",
        Bits(),
    }, "|"))
end

local frame = CreateFrame("Frame")
frame:Hide()
frame:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed >= INTERVAL then
        elapsed = 0
        if UnitExists("target") then
            Sample()
        end
    end
end)
frame:SetScript("OnEvent", function()
    if recording and UnitExists("target") then
        TargetHeader()
    end
end)
frame:RegisterEvent("PLAYER_TARGET_CHANGED")

local function Start()
    DTTProbeDB.rec = DTTProbeDB.rec or { rows = {} }
    rec = DTTProbeDB.rec
    BuildChecks()
    rec.checks = {}
    for index, check in ipairs(checks) do
        rec.checks[index] = check.id
    end
    rec.screen = string.format("%.1f,%.1f", UIParent:GetWidth(), UIParent:GetHeight())
    Add(string.format("M|%.3f|start %d checks", GetTime(), #checks))
    if UnitExists("target") then
        TargetHeader()
    end
    recording = true
    elapsed = 0
    frame:Show()
    ns.Print(string.format("recording at 20 Hz with %d checks. /dttp rec again to stop, then /reload.", #checks))
end

local function Stop()
    recording = false
    frame:Hide()
    Add(string.format("M|%.3f|stop", GetTime()))
    ns.Print(string.format("recording stopped, %d rows. /reload to save.", #rec.rows))
end

ns.commands.rec = function()
    if recording then
        Stop()
    else
        Start()
    end
end

ns.commands.recmark = function(message)
    if rec then
        local note = (message or ""):match("^%s*%S+%s*(.-)%s*$")
        Add(string.format("M|%.3f|%s", GetTime(), note))
        ns.Print("marked: " .. note)
    end
end

ns.commands.recclear = function()
    DTTProbeDB.rec = { rows = {} }
    rec = DTTProbeDB.rec
    ns.Print("recording cleared")
end

-- DistanceToTarget probe: a throwaway addon that records which range checks
-- work on the current target, in and out of combat, on WoW Forever and
-- Classic Era. Results go to chat and to DTTProbeDB (saved on /reload or logout).

local _, ns = ...
ns.commands = {}
local LRC = LibStub("LibRangeCheck-3.0")
local isSecret = issecretvalue or function() return false end

local MAX_REPORTS = 150
local MAX_CHANGES = 300
local UPDATE_INTERVAL = 0.1
local TRACE_INTERVAL = 0.5
local MAX_TRACE = 6000

local db

-- Formatting that never compares, concatenates or tests a secret value.
local function Show(value)
    if isSecret(value) then
        return "SECRET"
    end
    if value == nil then
        return "nil"
    end
    return tostring(value)
end

local function Pack(...)
    return { n = select("#", ...), ... }
end

-- Calls func through pcall and describes every return value.
local function Try(func, ...)
    if type(func) ~= "function" then
        return "(missing API)"
    end
    local results = Pack(pcall(func, ...))
    if not results[1] then
        return "ERROR " .. Show(results[2])
    end
    local parts = {}
    for index = 2, results.n do
        parts[#parts + 1] = Show(results[index])
    end
    if #parts == 0 then
        return "(no values)"
    end
    return table.concat(parts, ", ")
end

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffDTTProbe|r " .. message)
end
ns.Print = Print

-- Unit flags as text; on Forever even these could in theory be secret.
local function Flag(func, ...)
    return Try(func, ...)
end

local function TargetIsHostile()
    local ok, canAttack = pcall(UnitCanAttack, "player", "target")
    return ok and not isSecret(canAttack) and canAttack == true
end

local function CheckerLists(hostile)
    if hostile then
        return { { "harm", LRC.harmRC }, { "harm in combat", LRC.harmRCInCombat } }
    end
    return { { "friend", LRC.friendRC }, { "friend in combat", LRC.friendRCInCombat } }
end

-- Builds one report on the target. With raw = true, item and interact checks
-- also run on friendly targets in combat, which retail blocks.
local function BuildReport(reason, raw)
    local lines = {}
    local function Add(text)
        lines[#lines + 1] = text
    end

    local version, build, _, interface = GetBuildInfo()
    local inCombat = InCombatLockdown()
    Add(string.format("%s | %s | client %s.%s, interface %s, project %s | combat %s",
        date("%Y-%m-%d %H:%M:%S"), reason, Show(version), Show(build), Show(interface),
        Show(WOW_PROJECT_ID), Show(inCombat)))

    -- Context that might explain why exact distance works for one character
    -- (Tauren, Mulgore) and not another (Warlock, Silverpine).
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    Add("me: " .. Flag(UnitRace, "player") .. " " .. Flag(UnitClass, "player")
        .. " lvl " .. Flag(UnitLevel, "player")
        .. " | zone " .. Flag(GetRealZoneText) .. " / " .. Flag(GetSubZoneText)
        .. " | map " .. Show(mapID)
        .. " | instance " .. Flag(GetInstanceInfo)
        .. " | inInstance " .. Flag(IsInInstance)
        .. " | group " .. Flag(IsInGroup) .. " members " .. Flag(GetNumGroupMembers)
        .. " | pvp " .. Flag(UnitIsPVP, "player")
        .. " | warMode " .. Flag(C_PvP and C_PvP.IsWarModeActive)
        .. " | resting " .. Flag(IsResting)
        .. " | trial " .. Flag(IsTrialAccount) .. " / " .. Flag(IsVeteranTrialAccount)
        .. " | restricted " .. Flag(IsRestrictedAccount))
    Add("other units: pet pos " .. Try(UnitPosition, "pet")
        .. " | pet dist " .. Try(UnitDistanceSquared, "pet")
        .. " | mouseover pos " .. Try(UnitPosition, "mouseover")
        .. " | nameplate1 pos " .. Try(UnitPosition, "nameplate1")
        .. " | party1 dist " .. Try(UnitDistanceSquared, "party1"))

    if not UnitExists("target") then
        Add("no target")
        return lines
    end

    Add("target: name " .. Flag(UnitName, "target") .. " | player " .. Flag(UnitIsPlayer, "target")
        .. " | level " .. Flag(UnitLevel, "target")
        .. " | classification " .. Flag(UnitClassification, "target")
        .. " | tapDenied " .. Flag(UnitIsTapDenied, "target")
        .. " | targetPvp " .. Flag(UnitIsPVP, "target")
        .. " | inCombat " .. Flag(UnitAffectingCombat, "target")
        .. " | canAttack " .. Flag(UnitCanAttack, "player", "target")
        .. " | canAssist " .. Flag(UnitCanAssist, "player", "target")
        .. " | dead " .. Flag(UnitIsDeadOrGhost, "target")
        .. " | visible " .. Flag(UnitIsVisible, "target")
        .. " | guid " .. Flag(UnitGUID, "target"))

    local minor = LibStub.minors and LibStub.minors["LibRangeCheck-3.0"]
    Add("LibRangeCheck v" .. Show(minor) .. " GetRange: " .. Try(LRC.GetRange, LRC, "target")
        .. " | noItems: " .. Try(LRC.GetRange, LRC, "target", false, true))

    Add("UnitDistanceSquared: " .. Try(UnitDistanceSquared, "target")
        .. " | UnitInRange: " .. Try(UnitInRange, "target"))
    Add("UnitPosition player: " .. Try(UnitPosition, "player")
        .. " | target: " .. Try(UnitPosition, "target"))

    local hostile = TargetIsHostile()
    local restricted = inCombat and not hostile and not raw
    if restricted then
        Add("CheckInteractDistance: skipped (friendly target in combat; /dttp raw forces it)")
    else
        local parts = {}
        for index = 1, 5 do
            parts[#parts + 1] = index .. "=" .. Try(CheckInteractDistance, "target", index)
        end
        Add("CheckInteractDistance: " .. table.concat(parts, " "))
    end

    for _, list in ipairs(CheckerLists(hostile)) do
        local name, checkers = list[1], list[2]
        if type(checkers) ~= "table" or #checkers == 0 then
            Add(name .. " checkers: none")
        else
            local parts = {}
            for _, rc in ipairs(checkers) do
                local info = rc.info or "?"
                local result
                if restricted and (info:find("^item:") or info:find("^interact:")) then
                    result = "skipped"
                else
                    result = Try(rc.checker, "target", true)
                end
                parts[#parts + 1] = rc.range .. "yd " .. info .. "=" .. result
            end
            Add(name .. " checkers: " .. table.concat(parts, " ; "))
        end
    end

    return lines
end

local function Report(reason, raw, quiet)
    local lines = BuildReport(reason, raw)
    if quiet == "silent" then
        -- saved only
    elseif quiet then
        Print("combat report saved (" .. #lines .. " lines); /reload to write it to disk")
    else
        for _, line in ipairs(lines) do
            Print(line)
        end
    end
    table.insert(db.reports, lines)
    while #db.reports > MAX_REPORTS do
        table.remove(db.reports, 1)
    end
end

-- Live display next to the target frame. Created at load so YardsToKm's
-- PLAYER_LOGIN scan finds the FontString and converts it.
local display = CreateFrame("Frame", "DTTProbeDisplay", UIParent)
display:SetSize(1, 1)
display:Hide()
local text = display:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
text:SetPoint("LEFT", display, "LEFT", 0, 0)

local function AnchorDisplay()
    display:ClearAllPoints()
    if TargetFrame then
        display:SetPoint("LEFT", TargetFrame, "RIGHT", 4, 0)
    else
        display:SetPoint("CENTER", UIParent, "CENTER", 200, 100)
    end
end

local lastText
local elapsedSinceUpdate = 0
local elapsedSinceTrace = 0

-- Position trace: one line every TRACE_INTERVAL while there is a target, so
-- positions can be analysed after /reload (tools/trace.py turns it into CSV).
-- Fields: time|combat|mapID|zone|subzone|player x,y,instance|target x,y,instance|
--         UnitDistanceSquared,checked|LibRangeCheck min,max|hostile|target name
local function AddTrace(line)
    table.insert(db.trace, line)
    while #db.trace > MAX_TRACE do
        table.remove(db.trace, 1)
    end
end

local function Position(unit)
    return (Try(UnitPosition, unit):gsub(", ", ","))
end

local function TraceSample()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    AddTrace(table.concat({
        date("%H:%M:%S") .. string.format(".%d", math.floor((GetTime() % 1) * 10)),
        InCombatLockdown() and "combat" or "-",
        Show(mapID),
        Flag(GetRealZoneText),
        Flag(GetSubZoneText),
        Position("player"),
        Position("target"),
        (Try(UnitDistanceSquared, "target"):gsub(", ", ",")),
        (Try(LRC.GetRange, LRC, "target"):gsub(", ", ",")),
        TargetIsHostile() and "hostile" or "friendly",
        (Flag(UnitName, "target"):gsub(", nil$", "")),
    }, "|"))
end

-- Exact distance from UnitDistanceSquared (works on hostile NPCs out of
-- combat in the open world on Forever, seen 2026-11-10).
local function ExactText()
    if type(UnitDistanceSquared) ~= "function" then
        return "exact n/a", "exactMissing"
    end
    local ok, squared, checked = pcall(UnitDistanceSquared, "target")
    if not ok then
        return "exact error", "exactErrors"
    end
    if isSecret(squared) or isSecret(checked) then
        return "exact secret", "exactSecrets"
    end
    if not checked or type(squared) ~= "number" then
        return "exact ?", "exactUnchecked"
    end
    return string.format("%.1f yd", math.sqrt(squared)), "exactOk"
end

local function RangeText()
    local ok, minRange, maxRange = pcall(LRC.GetRange, LRC, "target")
    if not ok then
        return "error", "errors"
    end
    if isSecret(minRange) or isSecret(maxRange) then
        return "secret", "secrets"
    end
    if not minRange then
        return "?", "unknown"
    end
    if not maxRange then
        return "> " .. minRange .. " yd", "ok"
    end
    return minRange .. " - " .. maxRange .. " yd", "ok"
end

local function UpdateDisplay()
    local range, outcome = RangeText()
    local exact, exactOutcome = ExactText()
    local value = exact .. "  [" .. range .. "]"
    local stats = db.watch[InCombatLockdown() and "combat" or "noCombat"]
    stats[outcome] = (stats[outcome] or 0) + 1
    stats[exactOutcome] = (stats[exactOutcome] or 0) + 1
    if value ~= lastText then
        lastText = value
        text:SetText(value)
        table.insert(db.changes, string.format("%s %s %s %s", date("%H:%M:%S"),
            InCombatLockdown() and "combat" or "-", TargetIsHostile() and "hostile" or "friendly", value))
        while #db.changes > MAX_CHANGES do
            table.remove(db.changes, 1)
        end
    end
end

display:SetScript("OnUpdate", function(_, elapsed)
    elapsedSinceUpdate = elapsedSinceUpdate + elapsed
    if elapsedSinceUpdate >= UPDATE_INTERVAL then
        elapsedSinceUpdate = 0
        UpdateDisplay()
    end
    elapsedSinceTrace = elapsedSinceTrace + elapsed
    if elapsedSinceTrace >= TRACE_INTERVAL then
        elapsedSinceTrace = 0
        TraceSample()
    end
end)

local function RefreshVisibility()
    lastText = nil
    if db and db.watchEnabled and UnitExists("target") then
        display:Show()
        UpdateDisplay()
    else
        display:Hide()
    end
end

local function ResetDB()
    DTTProbeDB = {
        watchEnabled = true,
        reports = {},
        changes = {},
        trace = {},
        watch = { combat = {}, noCombat = {} },
    }
    db = DTTProbeDB
end

SLASH_DTTPROBE1 = "/dttp"
SlashCmdList.DTTPROBE = function(message)
    local command = (message or ""):lower():match("^%s*(%S*)")
    if command == "" or command == "probe" then
        Report("manual", false)
    elseif command == "raw" then
        Report("manual raw", true)
    elseif command == "watch" then
        db.watchEnabled = not db.watchEnabled
        RefreshVisibility()
        Print("live display " .. (db.watchEnabled and "on" or "off"))
    elseif command == "stats" then
        for _, key in ipairs({ "noCombat", "combat" }) do
            local parts = {}
            for outcome, count in pairs(db.watch[key]) do
                parts[#parts + 1] = outcome .. "=" .. count
            end
            Print(key .. ": " .. (#parts > 0 and table.concat(parts, " ") or "no updates"))
        end
    elseif command == "mark" then
        local note = (message or ""):match("^%s*%S+%s*(.-)%s*$")
        AddTrace(date("%H:%M:%S") .. "|MARK|" .. note)
        Report("mark: " .. note, false, "silent")
        Print("marked: " .. note)
        if ns.commands.recmark then
            ns.commands.recmark(message)
        end
    elseif ns.commands[command] then
        ns.commands[command](message)
    elseif command == "clear" then
        local watchEnabled = db.watchEnabled
        ResetDB()
        db.watchEnabled = watchEnabled
        Print("saved results cleared")
    else
        Print("/dttp: report on target | /dttp raw: also friendly item checks in combat | "
            .. "/dttp watch: toggle live text | /dttp mark <note> | /dttp rec: 20 Hz recording | /dttp stats | /dttp clear")
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function(_, event, loadedAddon)
    if event == "ADDON_LOADED" and loadedAddon == "DTTProbe" then
        if type(DTTProbeDB) ~= "table" or type(DTTProbeDB.watch) ~= "table" then
            ResetDB()
        end
        db = DTTProbeDB
        db.trace = db.trace or {}
    elseif event == "PLAYER_LOGIN" then
        AnchorDisplay()
        RefreshVisibility()
        Print("loaded, tracing positions. /dttp mark <note> labels a moment; /reload saves the log.")
    elseif event == "PLAYER_TARGET_CHANGED" then
        RefreshVisibility()
        if UnitExists("target") then
            Report("auto: new target", false, "silent")
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        C_Timer.After(1, function()
            if InCombatLockdown() and UnitExists("target") then
                Report("auto: 1 s into combat", false, true)
            end
        end)
    end
end)

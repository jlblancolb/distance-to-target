-- Shows how far away the target is, next to the target frame.
-- Estimator.lua does the maths, Checks.lua asks the game.
local addonName, ns = ...
local E, Checks = ns.Estimator, ns.Checks
local isSecret = issecretvalue or function() return false end

-- Seconds between updates for each "updates per second" setting.
local INTERVALS = { ["10"] = 0.1, ["5"] = 0.2, ["2"] = 0.5 }
local FONTS = { small = "GameFontHighlightSmall", normal = "GameFontHighlight", large = "GameFontHighlightLarge" }
local DEFAULTS = { enabled = true, x = 4, y = 0, size = "normal", colors = true, rate = "10" }
ns.DEFAULTS = DEFAULTS
-- Where the text goes when there is no usable target frame: its left edge,
-- relative to the centre of the screen.
local FREE_DEFAULT = { x = -20, y = -120 }
local SAMPLE = "27 yd"
local COLORS = {
    estimate = { 1, 1, 1 },
    bracket = { 1, 1, 1 },
    unsure = { 0.8, 0.8, 0.8 },
    melee = { 0.5, 1, 0.5 },
    far = { 0.6, 0.6, 0.6 },
}

-- Saved variables replace this table after the file runs; defaults are applied
-- again on ADDON_LOADED.
DistanceToTargetDB = {}
-- /dtt log: one row per update, for checking accuracy after a session.
DistanceToTargetLog = nil
local LOG_LIMIT = 20000

local tracker = E.NewTracker()
local shownText
local anchorPending = false
local unlocked = false

-- Created when the file loads so YardsToKm's first scan finds the FontString
-- and converts the yards to metres.
local display = CreateFrame("Frame", "DistanceToTargetFrame", UIParent)
display:SetSize(1, 1)
display:SetMovable(true)
if display.SetDontSavePosition then
    display:SetDontSavePosition(true)
end
display:Hide()
local text = display:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
text:SetPoint("LEFT")
ns.text = text
-- Shown while unlocked, so there is something to grab.
local handle = display:CreateTexture(nil, "BACKGROUND")
handle:SetAllPoints()
handle:SetColorTexture(0, 0.4, 0.8, 0.4)
handle:Hide()

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffDistanceToTarget|r: " .. message)
end
ns.Print = Print

local function ApplyDefaults()
    if type(DistanceToTargetDB) ~= "table" then
        DistanceToTargetDB = {}
    end
    local db = DistanceToTargetDB
    db.enabled = db.enabled ~= false
    if type(db.x) ~= "number" then db.x = DEFAULTS.x end
    if type(db.y) ~= "number" then db.y = DEFAULTS.y end
    if not FONTS[db.size] then db.size = DEFAULTS.size end
    db.colors = db.colors ~= false
    if not INTERVALS[db.rate] then db.rate = DEFAULTS.rate end
    if type(db.free) ~= "table" or type(db.free.x) ~= "number" or type(db.free.y) ~= "number" then
        db.free = nil
    end
end

local function Try(method, frame, ...)
    local ok, result = pcall(frame[method], frame, ...)
    if ok and (type(result) == "table" or not isSecret(result)) then
        return true, result
    end
    return false
end

-- False when a unit frame addon (ElvUI, Shadowed Unit Frames, anything built
-- on oUF...) has switched Blizzard's target frame off: they unregister its
-- events and hide it, often under a hidden parent.
local function TargetFrameUsable()
    if type(TargetFrame) ~= "table" then
        return false
    end
    local ok, registered = Try("IsEventRegistered", TargetFrame, "PLAYER_TARGET_CHANGED")
    if ok and not registered then
        return false
    end
    local parent
    ok, parent = Try("GetParent", TargetFrame)
    if ok and parent and parent ~= UIParent then
        local visible
        ok, visible = Try("IsVisible", parent)
        if ok and not visible then
            return false
        end
    end
    return true
end

-- "target" or "free": where the text is (or will be after combat).
local function AnchorMode()
    if DistanceToTargetDB.free or not TargetFrameUsable() then
        return "free"
    end
    return "target"
end

local function Anchor()
    if InCombatLockdown() then
        anchorPending = true
        return
    end
    anchorPending = false
    display:ClearAllPoints()
    local db = DistanceToTargetDB
    if AnchorMode() == "target" then
        display:SetPoint("LEFT", TargetFrame, "RIGHT", db.x, db.y)
    else
        local free = db.free or FREE_DEFAULT
        display:SetPoint("LEFT", UIParent, "CENTER", free.x, free.y)
    end
end

-- Saves where the text was dropped, as an offset from the screen centre.
local function SaveFreePosition()
    local left, bottom, top = display:GetLeft(), display:GetBottom(), display:GetTop()
    local cx, cy = UIParent:GetCenter()
    if left and bottom and top and cx and cy then
        DistanceToTargetDB.free = { x = left - cx, y = (bottom + top) / 2 - cy }
    end
end

display:SetScript("OnDragStart", function(self)
    if unlocked and not InCombatLockdown() then
        self:StartMoving()
    end
end)
display:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if self.SetUserPlaced then
        pcall(self.SetUserPlaced, self, false)
    end
    SaveFreePosition()
    Anchor()
end)

-- The player's world position in yards, or nil where the game hides it.
local function PlayerPosition()
    local ok, y, x = pcall(UnitPosition, "player")
    if ok and type(x) == "number" and type(y) == "number" and not isSecret(x) and not isSecret(y) then
        return x, y
    end
end

local function TargetIsHostile()
    local ok, canAttack = pcall(UnitCanAttack, "player", "target")
    return ok and not isSecret(canAttack) and canAttack and true or false
end

-- Exact centre distance in yards, or nil. The game only gives it for group
-- members in the open world and a few NPCs (probe data, 2026-11-10 and 13).
local function ExactDistance()
    if not UnitDistanceSquared then
        return
    end
    local ok, squared, checked = pcall(UnitDistanceSquared, "target")
    if ok and not isSecret(squared) and not isSecret(checked) and checked == true
        and type(squared) == "number" and squared > 0 then
        return math.sqrt(squared)
    end
end

local function SetDisplay(value, kind)
    if unlocked and not value then
        value = SAMPLE
    end
    if value ~= shownText then
        shownText = value
        text:SetText(value or "")
    end
    local color = DistanceToTargetDB.colors and COLORS[kind] or COLORS.estimate
    text:SetTextColor(color[1], color[2], color[3])
end

local function LogRow(row)
    local log = DistanceToTargetLog
    log.count = log.count + 1
    log.rows[(log.count - 1) % LOG_LIMIT + 1] = row
end

local logChecks = {}
local function LogCheck(kind, _, range, inRange)
    -- i = item, s = spell, x = interact; + in range, - out
    local letter = kind == "interact" and "x" or kind:sub(1, 1)
    logChecks[#logChecks + 1] = letter .. tostring(range) .. (inRange and "+" or "-")
end

local function Update()
    local logging = type(DistanceToTargetLog) == "table" and DistanceToTargetLog.on
    if logging then
        for index = #logChecks, 1, -1 do
            logChecks[index] = nil
        end
    end
    local hostile, combat = TargetIsHostile(), InCombatLockdown()
    local x, y = PlayerPosition()
    local now = GetTime()
    local exact = ExactDistance()
    local lo, hi
    if exact then
        lo, hi = exact, exact
        if logging then
            logChecks[1] = "exact"
        end
        SetDisplay(tracker:Exact(exact))
    else
        lo, hi = Checks.Measure("target", hostile, combat, logging and LogCheck or nil)
        SetDisplay(tracker:Update(now, x, y, lo, hi))
    end
    if logging then
        -- time|combat|hostile|player x,y|centre lo,hi|estimate,spread|shown|checks
        LogRow(string.format("D|%.2f|%s|%s|%s|%.2f,%.2f|%s|%s|%s", now, combat and "c" or "-",
            hostile and "h" or "f", x and string.format("%.2f,%.2f", x, y) or "-", lo, math.min(hi, 999),
            tracker.est and string.format("%.2f,%.2f", tracker.est, tracker.spread) or "-", shownText or "",
            table.concat(logChecks, " ")))
    end
end
ns.Update = Update

local function LogTarget()
    if type(DistanceToTargetLog) == "table" and DistanceToTargetLog.on and UnitExists("target") then
        local okName, name = pcall(UnitName, "target")
        local okDead, dead = pcall(UnitIsDead, "target")
        LogRow(string.format("T|%.2f|%s|%s", GetTime(), okName and not isSecret(name) and tostring(name) or "?",
            okDead and not isSecret(dead) and dead and "dead" or "alive"))
    end
end

local function SetLogging(on)
    if on then
        DistanceToTargetLog = { on = true, count = 0, rows = {}, started = date and date("%Y-%m-%d %H:%M:%S") }
        LogTarget()
        Print("logging every update; /reload or log out to save it, /dtt log off to stop")
    else
        if type(DistanceToTargetLog) == "table" then
            DistanceToTargetLog.on = false
        end
        Print("logging off")
    end
end

local driver = CreateFrame("Frame")
driver:Hide()
local elapsed = 0
driver:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed >= (INTERVALS[DistanceToTargetDB.rate] or 0.1) then
        elapsed = 0
        Update()
    end
end)

-- New target (or none): restart the estimate and show or hide the display.
local function Refresh()
    tracker:Reset()
    shownText = nil
    text:SetText("")
    if not InCombatLockdown() then
        Anchor() -- picks up a target frame another addon replaced after login
    end
    if DistanceToTargetDB.enabled and UnitExists("target") then
        display:Show()
        driver:Show()
        elapsed = 0
        LogTarget()
        Update()
    else
        driver:Hide()
        if unlocked then
            display:Show()
            SetDisplay(nil)
        else
            display:Hide()
        end
    end
end
ns.Refresh = Refresh

-- Text size from the settings.
local function ApplyStyle()
    if text.SetFontObject then
        text:SetFontObject(FONTS[DistanceToTargetDB.size] or FONTS.normal)
    end
end
ns.ApplyStyle = ApplyStyle

local function ResetPosition()
    DistanceToTargetDB.x, DistanceToTargetDB.y = DEFAULTS.x, DEFAULTS.y
    DistanceToTargetDB.free = nil
    Anchor()
end
ns.ResetPosition = ResetPosition

function ns.IsUnlocked()
    return unlocked
end

-- Options.lua replaces these. They keep the addon working without it, e.g.
-- after an update that adds the file and only a /reload: WoW reads the TOC's
-- file list at game start (2026-11-14).
function ns.SetSetting(key, value)
    DistanceToTargetDB[key] = value
    if key == "size" then
        ApplyStyle()
    else
        Refresh()
    end
end
function ns.CreateSettings() end
function ns.AfterCombat() end
function ns.OpenSettings()
    Print("settings page not loaded: restart the game (a /reload doesn't load new addon files)")
end

local function SetLocked(locked)
    unlocked = not locked
    display:EnableMouse(unlocked)
    if unlocked then
        display:RegisterForDrag("LeftButton")
        display:SetSize(80, 20)
        handle:Show()
    else
        display:SetSize(1, 1)
        handle:Hide()
    end
    Refresh()
end
ns.SetLocked = SetLocked

local function Status()
    Print(DistanceToTargetDB.enabled and "on" or "off")
    if AnchorMode() == "target" then
        Print("shown next to the target frame")
    elseif DistanceToTargetDB.free then
        Print("shown where you put it (/dtt reset to go back to the target frame)")
    else
        Print("target frame replaced or hidden by another addon: shown below the screen centre (/dtt unlock to move)")
    end
    local x, y = PlayerPosition()
    Print(x and "your position: known (filter on)" or "your position: hidden here (ranges only)")
    Print(string.format("%d spells with a range", Checks.SpellCount()))
    if UnitExists("target") then
        local lo, hi, used = Checks.Measure("target", TargetIsHostile(), InCombatLockdown())
        local hiText = hi == math.huge and "?" or string.format("%.1f", hi - E.REACH)
        Print(string.format("target: %s, %d checks answered, %.1f - %s yd, shown %q",
            TargetIsHostile() and "hostile" or "friendly", used, math.max(lo - E.REACH, 0), hiText, shownText or ""))
    end
end

local function ListChecks()
    if not UnitExists("target") then
        Print("no target")
        return
    end
    Checks.Measure("target", TargetIsHostile(), InCombatLockdown(), function(kind, id, range, inRange)
        Print(string.format("%s %s (%s yd): %s%s", kind == "conflict" and "spell" or kind, tostring(id),
            tostring(range), inRange and "in" or "out", kind == "conflict" and " (ignored: contradicts the others)" or ""))
    end)
end

SLASH_DISTANCETOTARGET1 = "/dtt"
SlashCmdList.DISTANCETOTARGET = function(message)
    local command, rest = (message or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()
    if command == "on" or command == "off" then
        ns.SetSetting("enabled", command == "on")
        Print(command)
    elseif command == "move" then
        local x, y = rest:match("^(-?[%d.]+)%s+(-?[%d.]+)$")
        if not x then
            Print("usage: /dtt move <x> <y>  (offset from the target frame's right edge)")
            return
        end
        DistanceToTargetDB.x, DistanceToTargetDB.y = tonumber(x), tonumber(y)
        DistanceToTargetDB.free = nil
        Anchor()
    elseif command == "unlock" or command == "lock" then
        if InCombatLockdown() then
            Print("not in combat")
            return
        end
        SetLocked(command == "lock")
        Print(unlocked and "unlocked: drag the text, then /dtt lock" or "locked")
    elseif command == "reset" then
        ResetPosition()
        Print("position reset")
    elseif command == "settings" or command == "options" or command == "config" then
        ns.OpenSettings()
    elseif command == "checks" then
        ListChecks()
    elseif command == "log" then
        SetLogging(rest:lower() ~= "off")
    elseif command == "" then
        Status()
    else
        Print("/dtt  status | settings | on | off | unlock | lock | move <x> <y> | reset | checks | log [off]")
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            ApplyDefaults()
            ApplyStyle()
            ns.CreateSettings()
        end
    elseif event == "PLAYER_LOGIN" then
        ApplyDefaults()
        ApplyStyle()
        Checks.Build()
        Anchor()
        Refresh()
    elseif event == "SPELLS_CHANGED" then
        Checks.Build()
    elseif event == "PLAYER_TARGET_CHANGED" then
        Refresh()
    elseif event == "PLAYER_ENTERING_WORLD" then
        Anchor()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if anchorPending then
            Anchor()
        end
        ns.AfterCombat()
    end
end)
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")

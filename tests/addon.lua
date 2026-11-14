-- The whole addon against mocked WoW APIs: a simulated world where range
-- checks answer from the true distance, as measured on Forever.
local world = { player = { 0, 0 }, target = { 29, 0 }, exists = false, hostile = true, combat = false,
    position = true, now = 0, secretInteract = false, exact = false }
local calls = { item = 0, interact = 0 }
local REACH = 2.25

local function Distance()
    local dx, dy = world.player[1] - world.target[1], world.player[2] - world.target[2]
    return math.sqrt(dx * dx + dy * dy)
end

-- Frames record scripts, events, points and text.
local frames = {}
local function NewFrame(name)
    local frame = { scripts = {}, events = {}, shown = true, name = name, parent = UIParent }
    function frame:SetScript(event, callback) self.scripts[event] = callback end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterAllEvents() self.events = {} end
    function frame:IsEventRegistered(event) return self.events[event] == true end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:IsShown() return self.shown end
    function frame:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function frame:GetParent() return self.parent end
    function frame:SetParent(parent) self.parent = parent end
    function frame:SetSize(w, h) self.size = { w, h } end
    function frame:ClearAllPoints() self.point = nil end
    function frame:SetPoint(...) self.point = { ... } end
    function frame:SetMovable(movable) self.movable = movable end
    function frame:SetDontSavePosition() end
    function frame:EnableMouse(enabled) self.mouse = enabled end
    function frame:RegisterForDrag(button) self.drag = button end
    function frame:StartMoving() assert(self.movable, "movable"); self.moving = true end
    function frame:StopMovingOrSizing() self.moving = false end
    function frame:GetCenter() return 500, 400 end
    -- Where a drag dropped it: left 700, vertical centre 300 (screen centre 500, 400).
    function frame:GetLeft() return 700 end
    function frame:GetBottom() return 290 end
    function frame:GetTop() return 310 end
    function frame:CreateTexture()
        local texture = { shown = true }
        function texture:SetAllPoints() end
        function texture:SetColorTexture() end
        function texture:Show() self.shown = true end
        function texture:Hide() self.shown = false end
        frame.texture = texture
        return texture
    end
    function frame:CreateFontString()
        local fontString = { text = "" }
        function fontString:SetPoint() end
        function fontString:SetText(value) self.text = value end
        function fontString:GetText() return self.text end
        function fontString:SetTextColor(r, g, b) self.color = { r, g, b } end
        frame.fontString = fontString
        return fontString
    end
    frames[#frames + 1] = frame
    return frame
end
function CreateFrame(_, name) return NewFrame(name) end
UIParent = NewFrame("UIParent")
UIParent.parent = nil
TargetFrame = NewFrame("TargetFrame")
TargetFrame:RegisterEvent("PLAYER_TARGET_CHANGED")

local messages = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) messages[#messages + 1] = message end }
SlashCmdList = {}

local secret = setmetatable({}, { __eq = function() error("compared a secret value") end })
function issecretvalue(value) return value == secret end -- rawequal semantics for tables without __eq on both

function GetTime() return world.now end
function InCombatLockdown() return world.combat end
function UnitExists() return world.exists end
function UnitCanAttack() return world.hostile end
function UnitIsDead() return world.dead end
function UnitName() return "Moonrage Glutton" end
function UnitPosition(unit)
    if unit == "player" and world.position then
        return world.player[2], world.player[1], 0, 1
    end
end
-- Exact distance: group members only (and a few NPCs); 0, false otherwise.
function UnitDistanceSquared()
    if world.exact == "secret" then
        return secret, secret
    elseif world.exact then
        return Distance() ^ 2, true
    end
    return 0, false
end
function CheckInteractDistance(_, index)
    calls.interact = calls.interact + 1
    assert(world.hostile or not world.combat, "interact check on a friendly unit in combat")
    if world.secretInteract then
        return secret
    end
    return Distance() <= ({ [3] = 9.85, [4] = 29.9 })[index]
end

-- LibRangeCheck: item checkers return true or nil. Friendly NPCs answer
-- "out" to every item.
local function ItemList(range, friendly)
    local list = {}
    for _, yards in ipairs(range) do
        list[#list + 1] = { range = yards, info = "item:" .. (1000 + yards), checker = function()
            calls.item = calls.item + 1
            assert(world.hostile or not world.combat, "item check on a friendly unit in combat")
            if friendly then
                return nil
            end
            if world.dead then
                -- Corpses: "in" to the 5 and 10 yd items, "out" to the rest (2026-11-14).
                return yards <= 10 or nil
            end
            return Distance() <= yards + REACH or nil
        end }
    end
    list[#list + 1] = { range = 30, info = "interact:4", checker = function() error("not an item") end }
    return list
end
local lrc = { harmRC = ItemList({ 5, 10, 15, 20, 25, 30, 35, 40, 100 }),
    friendRC = ItemList({ 5, 10, 20, 30, 40 }, true) }
function LibStub(name)
    assert(name == "LibRangeCheck-3.0")
    return lrc
end

-- Spellbook: Auto Shot (8-35), a hostile spell (30), a heal (40, friendly only),
-- Health Funnel (20, answers for the pet, which is always close), a helpful
-- spell that wrongly answers "in" on hostile units (skipped there), and a
-- harmful spell that answers for the pet (caught only as a contradiction).
local spells = { [75] = { 8, 35, "harm" }, [403] = { 0, 30, "harm" }, [2050] = { 0, 40, "help" }, [6603] = { 0, 0 },
    [755] = { 0, 20, "pet", "Health Funnel" }, [3698] = { 0, 20, "pet", "Health Funnel" },
    [7000] = { 0, 20, "petHelp", "Pet Buff" }, [7001] = { 0, 20, "petHarm", "Odd Spell" } }
Enum = { SpellBookSpellBank = { Player = 0 } }
C_SpellBook = {
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = 8 } end,
    GetSpellBookItemInfo = function(slot)
        local ids = { 75, 403, 2050, 6603, 20154, 3698, 7000, 7001 }
        return { spellID = ids[slot], isPassive = ids[slot] == 20154 }
    end,
}
C_Spell = {
    GetSpellInfo = function(id)
        local spell = spells[id]
        return spell and { minRange = spell[1], maxRange = spell[2] } or { minRange = 0, maxRange = 0 }
    end,
    GetSpellName = function(id)
        local spell = spells[id]
        return spell and (spell[4] or ("Spell " .. id))
    end,
    IsSpellHelpful = function(id)
        local kind = spells[id] and spells[id][3]
        return kind == "help" or kind == "pet" or kind == "petHelp"
    end,
    IsSpellHarmful = function(id)
        local kind = spells[id] and spells[id][3]
        return kind == "harm" or kind == "petHarm"
    end,
    IsSpellInRange = function(id, _)
        local spell = spells[id]
        if spell[3] == "pet" then
            return true
        elseif spell[3] == "petHarm" or spell[3] == "petHelp" then
            if not world.hostile then
                return nil
            end
            return true
        end
        if (spell[3] == "harm") ~= world.hostile or world.dead then
            return nil
        end
        local d = Distance()
        return d <= spell[2] + REACH and d >= spell[1] + (spell[1] > 0 and REACH or 0)
    end,
}

-- Load the addon like the TOC does.
local ns = {}
for _, file in ipairs({ "Estimator.lua", "Checks.lua", "DistanceToTarget.lua", "Options.lua" }) do
    assert(loadfile(file))("DistanceToTarget", ns)
end
local display, driver, events = frames[3], frames[4], frames[5]
assert(display.name == "DistanceToTargetFrame", "display frame created at load")
local text = display.fontString

local function Fire(event, ...)
    events.scripts.OnEvent(events, event, ...)
end
local function Run(seconds, move)
    for _ = 1, math.floor(seconds * 20 + 0.5) do
        world.now = world.now + 0.05
        if move then
            move(world.now)
        end
        if driver.shown then
            driver.scripts.OnUpdate(driver, 0.05)
        end
    end
end
local function Circle(t)
    world.player[1], world.player[2] = 6 * math.cos(t), 6 * math.sin(t)
end

DistanceToTargetDB = nil -- first login: no saved variables yet
Fire("ADDON_LOADED", "DistanceToTarget")
Fire("PLAYER_LOGIN")
assert(DistanceToTargetDB.enabled == true and DistanceToTargetDB.x == 4, "defaults")
assert(display.point[2] == TargetFrame, "anchored to the target frame")
assert(not display.shown and not driver.shown, "hidden without a target")

-- Hostile mob ~29 yd (centre) away, player walking a small circle.
world.exists = true
Fire("PLAYER_TARGET_CHANGED")
assert(display.shown and driver.shown, "shown with a target")
Run(6, Circle)
local shown = tonumber(text.text:match("^~?(%d+) yd$"))
local truth = Distance() - REACH
assert(shown and math.abs(shown - truth) <= 2, ("hostile: shown %q, truth %.1f"):format(text.text, truth))

local first29 = #messages
SlashCmdList.DISTANCETOTARGET("checks")
local listed29 = table.concat(messages, "\n", first29 + 1)
assert(listed29:find("spell 7001 %(20 yd%): in %(ignored") or not listed29:find("spell 7001"),
    "contradicting spell ignored at 29 yd: " .. listed29)

-- Melee range.
world.target = { 2, 0 }
world.player = { 0, 0 }
Run(1)
assert(text.text == "< 5 yd", text.text)
assert(text.color[2] == 1 and text.color[1] < 1, "melee colour")

-- Far away: beyond every check but the 100 yd item.
world.target = { 70, 0 }
Run(1)
assert(text.text == "> 40 yd", text.text)

-- A corpse says "out" to every item and nothing to spells (2026-11-11);
-- only the interact checks still work.
world.dead = true
world.target = { 15, 0 }
Fire("PLAYER_TARGET_CHANGED")
Run(3, Circle)
local corpse = tonumber(text.text:match("^~?(%d+) yd$"))
assert(corpse and corpse >= 7 and corpse <= 28, "corpse between the interact edges: " .. text.text)
world.dead = false

-- Secret answers are ignored, not compared.
world.target = { 20, 0 }
world.secretInteract = true
Run(2, Circle)
assert(text.text:match("yd$"), "still shows a distance with secret interact answers")
world.secretInteract = false

-- No position (instances): plain bracket.
world.position = false
world.player = { 0, 0 }
world.target = { 33, 0 }
Run(0.2)
assert(text.text == "30 - 35 yd", text.text)
world.position = true

-- Friendly NPC in combat: no item or interact calls; spells say nothing on
-- a friendly unit except the heal.
world.hostile, world.combat = false, true
world.target = { 15, 0 }
Fire("PLAYER_TARGET_CHANGED")
calls.item, calls.interact = 0, 0
Run(1)
assert(calls.item == 0 and calls.interact == 0, "no item/interact checks on a friendly unit in combat")
assert(text.text == "< 40 yd", text.text)

-- Friendly NPC out of combat: items always say "out", so they're ignored
-- (otherwise the NPC would look 40+ yd away); interact edges still work.
world.combat = false
Fire("PLAYER_TARGET_CHANGED")
Run(3, Circle)
assert(calls.item > 0, "items asked out of combat")
local friendly = tonumber(text.text:match("^~?(%d+) yd$"))
assert(friendly and friendly < 28, "friendly: " .. text.text)

-- Anchoring waits for the end of combat.
world.combat = true
SlashCmdList.DISTANCETOTARGET("move 10 -5")
assert(display.point[4] == 4, "not moved in combat")
world.combat = false
Fire("PLAYER_REGEN_ENABLED")
assert(display.point[4] == 10 and display.point[5] == -5, "moved after combat")
SlashCmdList.DISTANCETOTARGET("reset")
assert(display.point[4] == 4 and display.point[5] == 0, "reset")

-- Another addon replaces the target frame (ElvUI/oUF style: events off,
-- hidden parent): the text moves to the free spot below the screen centre.
local hiddenParent = NewFrame("Hidden")
hiddenParent:Hide()
TargetFrame:UnregisterAllEvents()
TargetFrame:SetParent(hiddenParent)
Fire("PLAYER_ENTERING_WORLD")
assert(display.point[2] == UIParent and display.point[3] == "CENTER", "free spot when the target frame is replaced")
-- Shadowed Unit Frames style: events off, frame hidden but parent kept.
TargetFrame:SetParent(UIParent)
Fire("PLAYER_TARGET_CHANGED")
assert(display.point[2] == UIParent, "free spot when the target frame's events are off")
TargetFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
Fire("PLAYER_TARGET_CHANGED")
assert(display.point[2] == TargetFrame, "back on the target frame")

-- Unlock, drag, lock: the text stays where it was dropped.
SlashCmdList.DISTANCETOTARGET("unlock")
assert(display.mouse and display.texture.shown, "unlocked")
display.scripts.OnDragStart(display)
assert(display.moving, "dragging")
display.scripts.OnDragStop(display)
assert(DistanceToTargetDB.free.x == 200 and DistanceToTargetDB.free.y == -100, "free position saved")
assert(display.point[2] == UIParent and display.point[4] == 200 and display.point[5] == -100, "anchored where dropped")
world.exists = false
Fire("PLAYER_TARGET_CHANGED")
assert(display.shown and text.text == "27 yd", "sample text while unlocked without a target")
SlashCmdList.DISTANCETOTARGET("lock")
assert(not display.mouse and not display.texture.shown and not display.shown, "locked hides without a target")
world.exists = true
Fire("PLAYER_TARGET_CHANGED")
assert(display.point[2] == UIParent, "stays free after locking")
world.combat = true
SlashCmdList.DISTANCETOTARGET("unlock")
assert(not display.mouse, "no unlocking in combat")
world.combat = false
SlashCmdList.DISTANCETOTARGET("reset")
assert(DistanceToTargetDB.free == nil and display.point[2] == TargetFrame, "reset goes back to the target frame")

-- Slash commands.
SlashCmdList.DISTANCETOTARGET("off")
assert(not display.shown and not driver.shown, "off hides")
SlashCmdList.DISTANCETOTARGET("on")
assert(display.shown, "on shows")
local before = #messages
SlashCmdList.DISTANCETOTARGET("checks")
assert(#messages > before + 2, "checks lists results")
SlashCmdList.DISTANCETOTARGET("")
assert(messages[#messages]:find("checks answered"), messages[#messages])

-- Logging.
SlashCmdList.DISTANCETOTARGET("log")
assert(DistanceToTargetLog.on and DistanceToTargetLog.rows[1]:match("^T|.*|Moonrage Glutton|alive$"),
    tostring(DistanceToTargetLog.rows[1]))
Run(1)
local row = DistanceToTargetLog.rows[DistanceToTargetLog.count]
assert(row:match("^D|") and row:find("s40%+") and row:find("x27.65%+") and not row:find("i%d"), row)
SlashCmdList.DISTANCETOTARGET("log off")
local count = DistanceToTargetLog.count
Run(1)
assert(DistanceToTargetLog.count == count, "stops logging")

-- Shadow Bolt range case (2026-11-14): a hostile mob 37+ yd away. Pet-only
-- and helpful spells are skipped; a spell that answers "in" anyway is ignored,
-- so the text stays near the truth instead of ~26 yd.
world.hostile, world.combat, world.dead = true, true, false
world.player, world.target = { 0, 0 }, { 39, 0 }
Fire("PLAYER_TARGET_CHANGED")
Run(3)
local far = tonumber(text.text:match("^~?(%d+) yd$"))
assert(far and far >= 35 and far <= 38, "far mob: " .. text.text)
local first = #messages
SlashCmdList.DISTANCETOTARGET("checks")
local listed = table.concat(messages, "\n", first + 1)
assert(not listed:find("spell 3698") and not listed:find("spell 7000"), "pet and helpful spells skipped: " .. listed)
-- After 5 contradictions earlier in this run it isn't even asked any more.
assert(not listed:find("spell 7001 %(20 yd%): in\n") and not listed:find("spell 7001 %(20 yd%): in$"),
    "contradicting spell not used: " .. listed)
world.combat = false

-- Party member: the game gives the exact distance, so it is shown as is.
world.exact = true
world.player = { 0, 0 }
world.target = { 22.25, 0 }
Fire("PLAYER_TARGET_CHANGED")
calls.item, calls.interact = 0, 0
Run(0.5)
assert(text.text == "20 yd", text.text)
assert(calls.item == 0 and calls.interact == 0, "no range checks with an exact distance")
world.target = { 22.6, 0 }
Run(0.5)
assert(text.text == "20 yd", "small moves don't flicker: " .. text.text)
world.target = { 3, 0 }
Run(0.2)
assert(text.text == "< 5 yd", text.text)
-- Secret exact answers fall back to the range checks.
world.exact = "secret"
world.target = { 22.25, 0 }
Run(2, Circle)
assert(text.text:match("yd$") and calls.item > 0, "falls back to range checks: " .. text.text)
world.exact = false

-- Target lost.
world.exists = false
Fire("PLAYER_TARGET_CHANGED")
assert(not display.shown and not driver.shown and text.text == "", "hidden after losing the target")

print("addon ok")

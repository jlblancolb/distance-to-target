-- Settings page (native on Forever, canvas on Classic Era), compartment entry,
-- and the effect of each setting.

-- A widget that accepts any method call and records the useful ones.
local function NewWidget(kind)
    local widget = { kind = kind, scripts = {}, events = {} }
    return setmetatable(widget, { __index = function(_, method)
        if method == "CreateFontString" then
            return function() return NewWidget("FontString") end
        elseif method == "CreateTexture" then
            return function() return NewWidget("Texture") end
        elseif method == "SetScript" then
            return function(self, name, callback) self.scripts[name] = callback end
        elseif method == "RegisterEvent" then
            return function(self, event) self.events[event] = true end
        elseif method == "SetText" then
            return function(self, value) self.text = value end
        elseif method == "SetFontObject" then
            return function(self, value) self.font = value end
        elseif method == "SetTextColor" then
            return function(self, r, g, b) self.color = { r, g, b } end
        elseif method == "SetChecked" then
            return function(self, value) self.checked = value end
        elseif method == "GetChecked" then
            return function(self) return self.checked end
        end
        return function() end
    end })
end

local function Install(projectID, customize)
    local mock = { settings = {}, controls = {}, buttons = {}, messages = {}, frames = {}, opened = nil }
    DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) mock.messages[#mock.messages + 1] = message end }
    SlashCmdList = {}
    UIParent = NewWidget("Frame")
    TargetFrame = NewWidget("Frame")
    function CreateFrame(kind, name)
        local widget = NewWidget(kind)
        widget.name = name
        mock.frames[#mock.frames + 1] = widget
        return widget
    end
    function LibStub() return { harmRC = {}, friendRC = {} } end
    function InCombatLockdown() return mock.combat end
    function UnitExists() return mock.target end
    function UnitCanAttack() return true end
    function UnitPosition() end
    function CheckInteractDistance() return true end
    function GetTime() return 0 end
    GameTooltip = { lines = {} }
    function GameTooltip:SetOwner() self.lines = {} end
    function GameTooltip:SetText(value) self.lines[#self.lines + 1] = value end
    function GameTooltip:AddLine(value) self.lines[#self.lines + 1] = value end
    function GameTooltip:Show() self.shown = true end
    function GameTooltip:Hide() self.shown = false end
    C_Spell, C_SpellBook = nil, nil

    WOW_PROJECT_CLASSIC = 2
    WOW_PROJECT_ID = projectID
    local layout = { AddInitializer = function(_, init) mock.buttons[#mock.buttons + 1] = init end }
    function CreateSettingsButtonInitializer(name, buttonText, onClick, tooltip)
        return { name = name, text = buttonText, click = onClick, tooltip = tooltip }
    end
    Settings = {
        VarType = { Boolean = "boolean", String = "string" },
        RegisterVerticalLayoutCategory = function(name)
            mock.verticalName = name
            return { GetID = function() return 7 end }, layout
        end,
        RegisterCanvasLayoutCategory = function(_, name)
            mock.canvasName = name
            return { GetID = function() return 8 end }
        end,
        RegisterAddOnCategory = function(category) mock.registered = category end,
        RegisterAddOnSetting = function(_, variable, key, tbl, varType, name, default)
            local setting = { variable = variable, key = key, varType = varType, name = name, default = default }
            function setting:GetValue() return tbl[key] end
            function setting:SetValue(value)
                tbl[key] = value
                if self.callback then self.callback(self, value) end
            end
            function setting:SetValueChangedCallback(callback) self.callback = callback end
            mock.settings[key] = setting
            return setting
        end,
        CreateCheckbox = function(_, setting, tooltip)
            mock.controls[#mock.controls + 1] = { kind = "checkbox", setting = setting, tooltip = tooltip }
        end,
        CreateDropdown = function(_, setting, options, tooltip)
            mock.controls[#mock.controls + 1] = { kind = "dropdown", setting = setting, options = options,
                tooltip = tooltip }
        end,
        CreateControlTextContainer = function()
            local data = {}
            return { Add = function(_, value, label) data[#data + 1] = { value = value, label = label } end,
                GetData = function() return data end }
        end,
        OpenToCategory = function(id) mock.opened = id end,
    }
    if customize then customize(Settings) end

    local ns = {}
    for _, file in ipairs({ "Estimator.lua", "Checks.lua", "DistanceToTarget.lua", "Options.lua" }) do
        assert(loadfile(file))("DistanceToTarget", ns)
    end
    mock.ns = ns
    for _, frame in ipairs(mock.frames) do
        if frame.events.ADDON_LOADED then
            mock.events = frame
        elseif frame.name == "DistanceToTargetFrame" then
            mock.display = frame
        end
    end
    mock.text = ns.text
    -- A 0.1 save: no size, colors or rate yet.
    DistanceToTargetDB = { enabled = true, x = 4, y = 0 }
    mock.events.scripts.OnEvent(mock.events, "ADDON_LOADED", "DistanceToTarget")
    return mock
end

-- Forever: native page with a checkbox, two dropdowns, a checkbox and two buttons.
local mock = Install(1)
assert(mock.verticalName == "Distance to Target" and mock.canvasName == nil)
assert(#mock.controls == 4, #mock.controls)
local want = { { "checkbox", "enabled", true }, { "dropdown", "size", "normal", 3 }, { "dropdown", "rate", "10", 3 },
    { "checkbox", "colors", true } }
for index, item in ipairs(want) do
    local control = mock.controls[index]
    assert(control.kind == item[1] and control.setting.key == item[2], item[2])
    assert(control.setting.default == item[3] and control.tooltip, item[2] .. " default/tooltip")
    assert(control.setting.variable == "DistanceToTarget_" .. item[2], control.setting.variable)
    if item[4] then
        assert(#control.options() == item[4], item[2] .. " options")
    end
end
assert(#mock.buttons == 2 and mock.buttons[2].text == "Reset position", "position buttons")
-- Defaults filled in for an old save before the page reads them.
assert(DistanceToTargetDB.size == "normal" and DistanceToTargetDB.colors == true and DistanceToTargetDB.rate == "10")
assert(mock.text.font == "GameFontHighlight", tostring(mock.text.font))

-- Text size applies at once.
mock.settings.size:SetValue("large")
assert(mock.text.font == "GameFontHighlightLarge", tostring(mock.text.font))

-- Colours off: melee text is white.
mock.target = true
mock.ns.Refresh()
assert(mock.text.text == "< 8 yd" and mock.text.color[1] < 1, "melee colour on: " .. tostring(mock.text.text))
mock.settings.colors:SetValue(false)
assert(mock.text.color[1] == 1 and mock.text.color[2] == 1 and mock.text.color[3] == 1, "white with colours off")

-- Turning it off from the page hides the text; /dtt and the compartment move the control.
mock.settings.enabled:SetValue(false)
assert(not DistanceToTargetDB.enabled)
SlashCmdList.DISTANCETOTARGET("on")
assert(mock.settings.enabled:GetValue() == true)
DistanceToTarget_OnAddonCompartmentClick(nil, "RightButton")
assert(mock.settings.enabled:GetValue() == false)
DistanceToTarget_OnAddonCompartmentEnter(nil, {})
assert(GameTooltip.shown and GameTooltip.lines[1] == "Distance to Target" and GameTooltip.lines[2] == "Off")
DistanceToTarget_OnAddonCompartmentLeave()
assert(not GameTooltip.shown)

-- Left-click opens the page, but only out of combat.
mock.combat = true
DistanceToTarget_OnAddonCompartmentClick(nil, "LeftButton")
assert(mock.opened == nil, "opened in combat")
mock.combat = false
mock.events.scripts.OnEvent(mock.events, "PLAYER_REGEN_ENABLED")
assert(mock.opened == 7, "opens after combat")
mock.opened = nil
SlashCmdList.DISTANCETOTARGET("settings")
assert(mock.opened == 7)

-- Position buttons: unlock, lock, reset.
mock.buttons[1].click()
assert(mock.ns.IsUnlocked(), "unlocked")
mock.buttons[1].click()
assert(not mock.ns.IsUnlocked(), "locked")
DistanceToTargetDB.free = { x = 1, y = 2 }
mock.buttons[2].click()
assert(DistanceToTargetDB.free == nil, "reset position")

-- Update rate: 2 per second updates every 0.5 s.
mock.settings.enabled:SetValue(true)
mock.settings.rate:SetValue("2")
local driver
for _, frame in ipairs(mock.frames) do
    if frame.scripts.OnUpdate then driver = frame end
end
local updates = 0
local real = mock.text.SetTextColor
mock.text.SetTextColor = function(self, ...) updates = updates + 1; return real(self, ...) end
for _ = 1, 10 do driver.scripts.OnUpdate(driver, 0.1) end
assert(updates == 2, "updates in 1 s at rate 2: " .. updates)
mock.text.SetTextColor = nil

-- Classic Era: canvas page.
mock = Install(2)
assert(mock.verticalName == nil and mock.canvasName == "Distance to Target")
mock.ns.SetSetting("size", "small")
assert(mock.text.font == "GameFontHighlightSmall")

-- A native API error falls back to the canvas page and says why.
mock = Install(1, function(api) api.CreateDropdown = function() error("bad dropdown") end end)
assert(mock.canvasName == "Distance to Target" and mock.registered.GetID() == 8)
assert(mock.messages[1]:find("basic settings page", 1, true) and mock.messages[1]:find("bad dropdown", 1, true),
    tostring(mock.messages[1]))
-- The half-built native settings no longer exist, so changes don't call into them.
mock.ns.SetSetting("rate", "5")

-- No Settings API at all: no page, and /dtt settings says so.
mock = Install(1, function(api) api.RegisterAddOnCategory = nil end)
SlashCmdList.DISTANCETOTARGET("settings")
assert(mock.messages[#mock.messages]:find("no settings page"), mock.messages[#mock.messages])

-- Updated files but only a /reload: Options.lua isn't loaded (2026-11-14).
-- Loading, settings changes and /dtt still work.
do
    local frames = {}
    local base = CreateFrame
    CreateFrame = function(...) local f = base(...); frames[#frames + 1] = f; return f end
    local ns = {}
    for _, file in ipairs({ "Estimator.lua", "Checks.lua", "DistanceToTarget.lua" }) do
        assert(loadfile(file))("DistanceToTarget", ns)
    end
    local events
    for _, frame in ipairs(frames) do
        if frame.events.ADDON_LOADED then events = frame end
    end
    DistanceToTargetDB = { enabled = true }
    events.scripts.OnEvent(events, "ADDON_LOADED", "DistanceToTarget")
    events.scripts.OnEvent(events, "PLAYER_REGEN_ENABLED")
    SlashCmdList.DISTANCETOTARGET("off")
    assert(DistanceToTargetDB.enabled == false)
    SlashCmdList.DISTANCETOTARGET("settings")
    assert(mock.messages[#mock.messages]:find("restart the game"), mock.messages[#mock.messages])
    CreateFrame = base
end

print("settings ok")

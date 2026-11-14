-- Settings page and addon compartment entry.
-- Forever (Mainline API): Blizzard's native settings page. Classic Era, or a
-- client missing part of that API: a simple canvas page with the same options.
-- Same approach as YardsToKm, which works on both clients.
local addonName, ns = ...

local TITLE = "Distance to Target"
local ENABLED_LABEL = "Show distance to target"

-- Choices: { key, label, tooltip, { { value, text }, ... } }
local CHOICES = {
    { "size", "Text size", "Size of the distance text.",
        { { "small", "Small" }, { "normal", "Normal" }, { "large", "Large" } } },
    { "rate", "Updates per second", "Fewer updates use less CPU but the number reacts more slowly.",
        { { "10", "10 (smoothest)" }, { "5", "5" }, { "2", "2" } } },
}
local COLORS_LABEL = "Colour by kind"
local COLORS_TOOLTIP = "Green in melee range, grey when unsure or out of range. Off: always white."

local category
local nativeSettings = {} -- native Setting objects by saved-variable key
local canvasControls = {} -- canvas widgets by saved-variable key
local openAfterCombat = false

local function ChoiceText(choice)
    local current = DistanceToTargetDB[choice[1]]
    for _, value in ipairs(choice[4]) do
        if value[1] == current then
            return value[2]
        end
    end
    return choice[4][1][2]
end

local function UpdateControls()
    local db = DistanceToTargetDB
    -- Keep native controls in step with /dtt and the compartment. SetValue calls
    -- back into SetSetting, which then finds the value already matches.
    for key, setting in pairs(nativeSettings) do
        if setting:GetValue() ~= db[key] then
            setting:SetValue(db[key])
        end
    end
    if canvasControls.enabled then
        canvasControls.enabled:SetChecked(db.enabled)
        canvasControls.colors:SetChecked(db.colors)
        for _, choice in ipairs(CHOICES) do
            canvasControls[choice[1]]:SetText(ChoiceText(choice))
        end
    end
end

-- Every settings change goes through here: page, compartment and /dtt.
-- Native controls write the value before calling back, so this always applies
-- the effect; UpdateControls only touches controls that differ, so no loop.
function ns.SetSetting(key, value)
    DistanceToTargetDB[key] = value
    if key == "enabled" then
        ns.Refresh()
    elseif key == "size" then
        ns.ApplyStyle()
    elseif key == "colors" then
        ns.Refresh()
    end
    UpdateControls()
end

local function ToggleLock()
    if InCombatLockdown() then
        ns.Print("not in combat")
        return
    end
    ns.SetLocked(ns.IsUnlocked())
    ns.Print(ns.IsUnlocked() and "unlocked: drag the text, then lock it again (here or /dtt lock)" or "locked")
end

local function ResetPosition()
    if InCombatLockdown() then
        ns.Print("not in combat")
        return
    end
    ns.ResetPosition()
    ns.Print("position reset")
end

local function CreateNative()
    if WOW_PROJECT_ID and WOW_PROJECT_CLASSIC and WOW_PROJECT_ID == WOW_PROJECT_CLASSIC then
        return nil
    end
    for _, name in ipairs({ "RegisterVerticalLayoutCategory", "RegisterAddOnSetting", "CreateCheckbox",
            "CreateDropdown", "CreateControlTextContainer", "RegisterAddOnCategory" }) do
        if not Settings[name] then
            return nil
        end
    end
    local varTypes = Settings.VarType or {}
    local page, layout = Settings.RegisterVerticalLayoutCategory(TITLE)
    local registered = {}
    local function Register(key, varType, label)
        local setting = Settings.RegisterAddOnSetting(page, addonName .. "_" .. key, key, DistanceToTargetDB,
            varType, label, ns.DEFAULTS[key])
        setting:SetValueChangedCallback(function(_, value)
            ns.SetSetting(key, value)
        end)
        registered[key] = setting
        return setting
    end

    Settings.CreateCheckbox(page, Register("enabled", varTypes.Boolean or "boolean", ENABLED_LABEL),
        "Turn off to hide the distance text.")
    for _, choice in ipairs(CHOICES) do
        local setting = Register(choice[1], varTypes.String or "string", choice[2])
        Settings.CreateDropdown(page, setting, function()
            local container = Settings.CreateControlTextContainer()
            for _, value in ipairs(choice[4]) do
                container:Add(value[1], value[2])
            end
            return container:GetData()
        end, choice[3])
    end
    Settings.CreateCheckbox(page, Register("colors", varTypes.Boolean or "boolean", COLORS_LABEL), COLORS_TOOLTIP)

    -- Position buttons, where this client has them; /dtt unlock and reset work anyway.
    if CreateSettingsButtonInitializer and layout and layout.AddInitializer then
        layout:AddInitializer(CreateSettingsButtonInitializer("Position", "Unlock / lock", ToggleLock,
            "Unlock to drag the text anywhere, then click again to lock it.", true))
        layout:AddInitializer(CreateSettingsButtonInitializer("", "Reset position", ResetPosition,
            "Put the text back next to the target frame.", true))
    end

    Settings.RegisterAddOnCategory(page)
    nativeSettings = registered
    return page
end

local function CreateCanvas()
    local panel = CreateFrame("Frame")
    panel.name = TITLE
    panel:Hide()

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(TITLE)
    local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    description:SetText("How far away your target is, next to the target frame.")

    local function Checkbox(key, label, anchor)
        local box = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        box:SetSize(26, 26)
        box:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -16)
        local boxLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        boxLabel:SetPoint("LEFT", box, "RIGHT", 6, 0)
        boxLabel:SetText(label)
        box:SetScript("OnClick", function(self)
            ns.SetSetting(key, self:GetChecked() and true or false)
        end)
        canvasControls[key] = box
        return box
    end

    local previous = Checkbox("enabled", ENABLED_LABEL, description)
    for _, choice in ipairs(CHOICES) do
        local label = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        label:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -20)
        label:SetText(choice[2])
        local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        button:SetSize(160, 24)
        button:SetPoint("LEFT", label, "LEFT", 180, 0)
        button:SetScript("OnClick", function()
            local values, current = choice[4], 1
            for index, value in ipairs(values) do
                if value[1] == DistanceToTargetDB[choice[1]] then
                    current = index
                end
            end
            ns.SetSetting(choice[1], values[current % #values + 1][1])
        end)
        canvasControls[choice[1]] = button
        previous = label
    end
    previous = Checkbox("colors", COLORS_LABEL, previous)

    local unlock = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    unlock:SetSize(140, 24)
    unlock:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -20)
    unlock:SetText("Unlock / lock")
    unlock:SetScript("OnClick", ToggleLock)
    local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reset:SetSize(140, 24)
    reset:SetPoint("LEFT", unlock, "RIGHT", 10, 0)
    reset:SetText("Reset position")
    reset:SetScript("OnClick", ResetPosition)

    local page = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(page)
    return page
end

-- Called on ADDON_LOADED, after the saved variables have their defaults.
function ns.CreateSettings()
    if type(Settings) ~= "table" or not Settings.RegisterAddOnCategory then
        return
    end
    local ok, page = pcall(CreateNative)
    if ok and page then
        category = page
        return
    elseif not ok then
        nativeSettings = {}
        ns.Print("using the basic settings page (" .. tostring(page) .. ")")
    end
    if Settings.RegisterCanvasLayoutCategory then
        category = CreateCanvas()
        UpdateControls()
    end
end

-- The settings panel is protected UI, so it opens after combat.
function ns.OpenSettings()
    if not category or not Settings.OpenToCategory then
        ns.Print("no settings page in this client; type /dtt help for commands")
    elseif InCombatLockdown() then
        openAfterCombat = true
        ns.Print("settings will open when combat ends")
    else
        Settings.OpenToCategory(category:GetID())
    end
end

function ns.AfterCombat()
    if openAfterCombat then
        openAfterCombat = false
        ns.OpenSettings()
    end
end

-- Addon compartment (the minimap addon menu), named in the TOC. Clients
-- without the compartment ignore those TOC fields.
function DistanceToTarget_OnAddonCompartmentClick(_, mouseButton)
    if mouseButton == "RightButton" then
        ns.SetSetting("enabled", not DistanceToTargetDB.enabled)
        ns.Print(DistanceToTargetDB.enabled and "on" or "off")
    else
        ns.OpenSettings()
    end
end

function DistanceToTarget_OnAddonCompartmentEnter(_, button)
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:SetText(TITLE)
    GameTooltip:AddLine(DistanceToTargetDB.enabled and "On" or "Off", 1, 1, 1)
    GameTooltip:AddLine("Left-click: settings", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Right-click: turn on or off", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

function DistanceToTarget_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end

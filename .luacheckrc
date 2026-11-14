std = "lua51"
max_line_length = 120
exclude_files = { "libs", "probe" }

local wow = {
    "C_Spell", "C_SpellBook", "CheckInteractDistance", "CreateFrame", "DEFAULT_CHAT_FRAME", "Enum",
    "GetNumSpellTabs", "GetSpellBookItemInfo", "GetSpellInfo", "GetSpellTabInfo", "GetTime", "InCombatLockdown",
    "IsHarmfulSpell", "IsHelpfulSpell", "IsPassiveSpell", "IsSpellInRange", "issecretvalue", "LibStub", "TargetFrame", "UIParent", "UnitCanAttack",
    "UnitDistanceSquared", "UnitExists", "UnitIsDead", "UnitName", "UnitPosition", "date",
}

files["Estimator.lua"] = { read_globals = {} }
files["Checks.lua"] = { read_globals = wow }
files["DistanceToTarget.lua"] = {
    globals = { "DistanceToTargetDB", "DistanceToTargetLog", "SLASH_DISTANCETOTARGET1", "SlashCmdList" },
    read_globals = wow,
}
files["Options.lua"] = {
    globals = { "DistanceToTargetDB", "DistanceToTarget_OnAddonCompartmentClick",
        "DistanceToTarget_OnAddonCompartmentEnter", "DistanceToTarget_OnAddonCompartmentLeave" },
    read_globals = { "CreateFrame", "CreateSettingsButtonInitializer", "GameTooltip", "InCombatLockdown", "Settings",
        "WOW_PROJECT_CLASSIC", "WOW_PROJECT_ID" },
}
files["tools"] = { globals = { "DTTProbeDB" }, read_globals = { "arg" } }

-- Tests install WoW API mocks as globals.
-- Mocks shadow self, set globals other files read, and use Lua 5.2 table.unpack guards.
files["tests"] = { allow_defined_top = true, ignore = { "11", "131", "143", "212", "311", "431", "432" } }

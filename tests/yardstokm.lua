-- Every text shape we show, run through YardsToKm (if it's checked out next
-- to this repo) to be sure players who use it get metres.
local chunk = loadfile("../YardsToKm/YardsToKm.lua")
if not chunk then
    print("yardstokm skipped: ../YardsToKm not found")
    return
end

local ns = {}
assert(loadfile("Estimator.lua"))("DistanceToTarget", ns)
local E = ns.Estimator

SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
C_Timer = { NewTicker = function() end }
function hooksecurefunc(object, method, callback)
    local original = object[method]
    object[method] = function(self, ...)
        original(self, ...)
        callback(self, ...)
    end
end

local line = { text = "" }
function line:IsObjectType(kind) return kind == "FontString" end
function line:GetText() return self.text end
function line:SetText(value) self.text = value end
local frame = {}
function frame:IsObjectType() return false end
function frame:GetRegions() return line end
function EnumerateFrames(previous)
    if not previous then return frame end
end
local eventFrame = {}
function eventFrame:RegisterEvent() end
function eventFrame:SetScript(_, callback) self.callback = callback end
function CreateFrame() return eventFrame end

chunk("YardsToKm")
YardsToKmDB = {}
eventFrame.callback(eventFrame, "ADDON_LOADED", "YardsToKm")

local huge = math.huge
local cases = {
    { { 32.25, 37.25, 29.6, 0.5 }, "27 yd", "25 m" },
    { { 32.25, 37.25, 29.6, 3 }, "~27 yd", "~25 m" },
    { { 0, 7.25 }, "< 5 yd", "< 5 m" },
    { { 47.25, huge }, "> 45 yd", "> 41 m" },
    { { 32.25, 37.25 }, "30 - 35 yd", "27 m - 32 m" },
}
for _, case in ipairs(cases) do
    local shown = E.Text((unpack or table.unpack)(case[1]))
    assert(shown == case[2], shown)
    line:SetText(shown)
    assert(line.text == case[3], ("%q -> %q, expected %q"):format(shown, line.text, case[3]))
end
print("yardstokm ok")

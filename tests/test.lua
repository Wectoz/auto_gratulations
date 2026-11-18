-- Run from the addon folder: lua5.1 tests/test.lua
-- Stubs just enough of the WoW API to exercise level tracking and message sending.
local units, sent, timers, raid, lockdown = {}, {}, {}, false, false
local handler
local scripts = {} -- OnShow/OnClick handlers of the options UI, run at the end

-- Stands in for any UI object: every field and call yields another dummy.
local dummy = setmetatable({}, {})
getmetatable(dummy).__index = function() return dummy end
getmetatable(dummy).__call = function() return dummy end
function dummy.SetScript(_, name, fn) if type(fn) == "function" then table.insert(scripts, fn) end end
Settings = setmetatable({ VarType = { Boolean = 1, Number = 2, String = 3 } }, getmetatable(dummy))
MinimalSliderWithSteppersMixin = { Label = { Right = 2 } }
SlashCmdList = {}
YES, NO, StaticPopupDialogs = "Yes", "No", {}
function StaticPopup_Show(name) StaticPopupDialogs[name].OnAccept() end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function issecretvalue() return false end
function CreateFrame()
    if handler then return dummy end
    return {
        RegisterEvent = function() end,
        SetScript = function(_, _, fn) handler = fn end,
    }
end
function UnitExists(unit) return units[unit] ~= nil end
function UnitGUID(unit) return units[unit] and units[unit].guid end
function UnitLevel(unit) return units[unit].level end
function UnitFullName(unit) return units[unit].name, units[unit].realm end
function UnitName(unit) return units[unit].name end
function IsInRaid() return raid end
function IsInGroup() return true end
function GetMaxPlayerLevel() return 60 end
C_Timer = { After = function(_, fn) table.insert(timers, fn) end }
C_ChatInfo = {
    InChatMessagingLockdown = function() return lockdown end,
    SendChatMessage = function(text, chatType, _, target) table.insert(sent, { text, chatType, target }) end,
}

-- Any global the addon reads that is not stubbed above (or a misplaced local) is an error.
setmetatable(_G, { __index = function(_, key) error("undefined global " .. tostring(key), 2) end })
AutoGratulationsDB = false

assert(loadfile("AutoGratulations.lua"))("auto_gratulations")

local function fire(event, arg) handler(nil, event, arg) end
local function flush()
    local pending = timers
    timers = {}
    for _, fn in ipairs(pending) do fn() end
end
local function expect(count, text, chatType, target)
    flush()
    assert(#sent == count, "expected " .. count .. " messages, got " .. #sent)
    if text then
        local last = sent[#sent]
        assert(last[1] == text, last[1])
        assert(last[2] == chatType, last[2])
        assert(last[3] == target, tostring(last[3]))
    end
end

units.player = { guid = "P", level = 10, name = "Me" }
units.party1 = { guid = "A", level = 9, name = "Ann" }
AutoGratulationsDB = { enabled = true, nextMessage = 2 } -- 1.0.0 saved data
fire("ADDON_LOADED", "auto_gratulations")
local db = AutoGratulationsDB
assert(db.delay == 2 and db.every == 1 and db.target == "GROUP", "defaults not filled in")

fire("PLAYER_ENTERING_WORLD")
expect(0) -- joining never congratulates

units.party1.level = 10
fire("UNIT_LEVEL", "party1")
fire("GROUP_ROSTER_UPDATE") -- the same ding seen twice must be sent once
expect(1, "grats Ann, 10!", "PARTY")
assert(db.nextMessage == 3)

units.party1.level = 0 -- offline or out of range: keep the known level
fire("UNIT_LEVEL", "party1")
units.party1.level = 10
fire("UNIT_LEVEL", "party1")
expect(1)

db.every = 5
units.party1.level = 11
fire("UNIT_LEVEL", "party1")
expect(1) -- not a milestone
db.every = 1

db.enabled = false
units.party1.level = 12
fire("UNIT_LEVEL", "party1")
db.enabled = true
fire("GROUP_ROSTER_UPDATE")
expect(1) -- no retroactive grats after re-enabling

db.target = "WHISPER"
units.party1.realm = "Realm"
units.party1.level = 13
fire("UNIT_LEVEL", "party1")
expect(2, "nice, Ann hit 13. gz!", "WHISPER", "Ann-Realm")
db.target = "GROUP"

lockdown = true
units.party1.level = 14
fire("UNIT_LEVEL", "party1")
expect(2) -- chat is locked, nothing is sent
lockdown = false

db.messages = { "{name} {level} {other} %d" } -- custom text is never used as a format string
units.party1.level = 15
fire("UNIT_LEVEL", "party1")
expect(3, "Ann 15 {other} %d", "PARTY")

units.party2 = { guid = "B", level = 15, name = "Bob" }
units.party3 = { guid = "C", level = 20, name = "Cid" }
units.party4 = { guid = "D", level = 15, name = "Dee" }
fire("GROUP_ROSTER_UPDATE")
for _, unit in ipairs({ "party1", "party2", "party3", "party4" }) do
    units[unit].level = units[unit].level + 1
    fire("UNIT_LEVEL", unit)
end
flush() -- one line per level reached during the delay
assert(#sent == 5 and sent[4][1] == "Ann, Bob and Dee 16 {other} %d" and sent[5][1] == "Cid 21 {other} %d")
sent = { 1, 2, 3 }
units.party2, units.party3, units.party4 = nil, nil, nil
units.party1.level = 15

db.every = 10
units.party1.level = 60
fire("UNIT_LEVEL", "party1")
expect(4, "huge grats Ann, level 60!!", "PARTY") -- max level ignores the milestone filter
db.every = 1
sent = { 1, 2, 3 }

raid = true
units.party1 = nil
units.raid1 = { guid = "P", level = 10, name = "Me" }
units.raid2 = { guid = "A", level = 15, name = "Ann" }
fire("GROUP_ROSTER_UPDATE")
units.raid2.level = 16
fire("UNIT_LEVEL", "raid2")
expect(3) -- raids are off by default
db.raids = true
fire("GROUP_ROSTER_UPDATE")
units.raid1.level = 11 -- our own ding
units.raid2.level = 17
fire("UNIT_LEVEL", "raid2")
expect(4, "Ann 17 {other} %d", "RAID")

db.messages = { "a|b " .. string.rep("\195\169", 200) .. " {name}" } -- pipes and over-long text
units.raid2.level = 18
fire("UNIT_LEVEL", "raid2")
flush()
local long = sent[#sent][1]
assert(long:sub(1, 5) == "a||b " and #long <= 255 and #long % 2 == 1, "bad truncation: " .. #long)

assert(#scripts == 3, "expected 3 UI scripts, got " .. #scripts)
for _, fn in ipairs(scripts) do fn(dummy) end -- the options page must open and its buttons work
assert(db.messages == nil, "restore defaults did not reset the list")

print("ok")

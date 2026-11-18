local addonName = ...

local TITLE = "Auto Gratulations"
local MAX_MESSAGE_LENGTH = 200 -- leaves room for the name within the 255-byte chat limit

local DEFAULT_MESSAGES = {
    "gz {name} on {level}!",
    "grats {name}, {level}!",
    "nice, {name} hit {level}. gz!",
    "gz {name}, level {level}",
    "grats on the ding {name}! {level} now",
}

local defaults = {
    enabled = true,
    raids = false,
    target = "GROUP", -- or "WHISPER"
    every = 1,
    delay = 2,
    delayMax = 5,
    maxMessage = "huge grats {name}, level {level}!!", -- empty: use the normal list
    random = false,
    nextMessage = 1,
}

local db
local category
local playerGUID
local levels = {} -- GUID -> last known level
local pending -- level-ups waiting out the delay; nil while no timer is running
local frame = CreateFrame("Frame")

local function Print(text)
    print("|cff80ff80" .. TITLE .. ":|r " .. text)
end

local function Messages()
    return db.messages or DEFAULT_MESSAGES
end

-- One message per line; blank lines are dropped. No lines at all restores the defaults.
local function SetMessagesFromText(text)
    local list = {}
    for line in string.gmatch(text, "[^\r\n]+") do
        line = strtrim(line)
        if line ~= "" then
            table.insert(list, string.sub(line, 1, MAX_MESSAGE_LENGTH))
        end
    end
    db.messages = list[1] and list or nil
end

local function Format(message, name, level)
    return (string.gsub(message, "{(%a+)}", { name = name, level = level }))
end

local function NextMessage(advance)
    local messages = Messages()
    local index
    if db.random then
        index = math.random(#messages)
    else
        index = db.nextMessage
        if type(index) ~= "number" or not messages[index] then index = 1 end
        if advance then db.nextMessage = index % #messages + 1 end
    end
    return messages[index]
end

local function IsMaxLevel(level)
    return level >= GetMaxPlayerLevel()
end

local function Text(names, level)
    local message = db.maxMessage ~= "" and IsMaxLevel(level) and db.maxMessage or NextMessage(true)
    local name = names[1]
    if names[2] then
        name = table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
    end
    return Format(message, name, level)
end

local function Send()
    local dings = pending
    pending = nil
    -- Addon chat is blocked during encounters and on restricted maps.
    if not db.enabled or not IsInGroup() or C_ChatInfo.InChatMessagingLockdown() then return end
    if db.target == "WHISPER" then
        for _, ding in ipairs(dings) do
            C_ChatInfo.SendChatMessage(Text({ ding.name }, ding.level), "WHISPER", nil, ding.target)
        end
        return
    end
    -- One line per level, so a party that levels together is not spammed.
    local names, order = {}, {}
    for _, ding in ipairs(dings) do
        if not names[ding.level] then
            names[ding.level] = {}
            table.insert(order, ding.level)
        end
        table.insert(names[ding.level], ding.name)
    end
    for _, level in ipairs(order) do
        C_ChatInfo.SendChatMessage(Text(names[level], level), IsInRaid() and "RAID" or "PARTY")
    end
end

local function Congratulate(name, realm, level)
    if not db.enabled or (level % db.every ~= 0 and not IsMaxLevel(level)) then return end
    if not pending then
        pending = {}
        C_Timer.After(db.delay + math.random() * math.max(0, db.delayMax - db.delay), Send)
    end
    local target = name
    if realm and realm ~= "" then target = name .. "-" .. realm end
    table.insert(pending, { name = name, target = target, level = level })
end

-- Levels are always tracked, also while disabled, so enabling never sends stale grats.
local function Scan(announce)
    local raid = IsInRaid()
    local seen = {}
    if not raid or db.raids then
        for index = 1, raid and 40 or 4 do
            local unit = (raid and "raid" or "party") .. index
            local guid = UnitExists(unit) and UnitGUID(unit)
            if guid and not issecretvalue(guid) and guid ~= playerGUID then
                seen[guid] = true
                local level = UnitLevel(unit)
                local previous = levels[guid]
                -- Unknown levels (offline, out of range) must never replace a known one.
                if not issecretvalue(level) and level > 0 then
                    levels[guid] = level
                    if announce and previous and level > previous then
                        local name, realm = UnitFullName(unit)
                        if name and not issecretvalue(name) then
                            Congratulate(name, realm, level)
                        end
                    end
                end
            end
        end
    end
    for guid in pairs(levels) do
        if not seen[guid] then levels[guid] = nil end
    end
end

local function Preview()
    Print("Preview: " .. Format(NextMessage(false), UnitName("player"), UnitLevel("player") + 1))
end

local function CreateMessagesPanel()
    local panel = CreateFrame("Frame")

    local help = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    help:SetPoint("TOPLEFT", 16, -16)
    help:SetPoint("RIGHT", -16, 0)
    help:SetJustifyH("LEFT")
    help:SetText("One message per line. |cffffd100{name}|r becomes the player's name and "
        .. "|cffffd100{level}|r their new level. Changes are saved as you type.")

    local scroll = CreateFrame("ScrollFrame", nil, panel, "InputScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", help, "BOTTOMLEFT", 6, -16)
    scroll:SetSize(560, 220)
    scroll.EditBox:SetWidth(542) -- the template sized it before the frame had a width
    scroll.CharCount:Hide()
    scroll.EditBox:HookScript("OnTextChanged", function(self, userInput)
        if userInput then SetMessagesFromText(self:GetText()) end
    end)

    local function Refresh()
        scroll.EditBox:SetText(table.concat(Messages(), "\n"))
        maxBox:SetText(db.maxMessage)
    end

    local maxLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    maxLabel:SetPoint("TOPLEFT", scroll, "BOTTOMLEFT", -6, -20)
    maxLabel:SetText("Max level message (leave empty to use the list above)")

    local maxBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    maxBox:SetPoint("TOPLEFT", maxLabel, "BOTTOMLEFT", 6, -6)
    maxBox:SetSize(560, 22)
    maxBox:SetAutoFocus(false)
    maxBox:SetMaxLetters(MAX_MESSAGE_LENGTH)
    maxBox:HookScript("OnTextChanged", function(self, userInput)
        if userInput then db.maxMessage = strtrim(self:GetText()) end
    end)

    local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reset:SetPoint("TOPLEFT", maxBox, "BOTTOMLEFT", -6, -16)
    reset:SetSize(150, 22)
    reset:SetText("Restore defaults")
    reset:SetScript("OnClick", function()
        db.messages = nil
        db.maxMessage = defaults.maxMessage
        Refresh()
    end)

    local test = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    test:SetPoint("LEFT", reset, "RIGHT", 8, 0)
    test:SetSize(150, 22)
    test:SetText("Preview in chat")
    test:SetScript("OnClick", Preview)

    panel:SetScript("OnShow", Refresh)
    return panel
end

local function RegisterSettings()
    category = Settings.RegisterVerticalLayoutCategory(TITLE)

    local function Setting(key, label)
        local varType = Settings.VarType[type(defaults[key]) == "boolean" and "Boolean"
            or type(defaults[key]) == "number" and "Number" or "String"]
        return Settings.RegisterAddOnSetting(category, "AutoGratulations_" .. key, key, db,
            varType, label, defaults[key])
    end

    Settings.CreateCheckbox(category, Setting("enabled", "Congratulate level-ups"),
        "Send a congratulation when a group member gains a level.")

    Settings.CreateDropdown(category, Setting("target", "Send to"), function()
        local container = Settings.CreateControlTextContainer()
        container:Add("GROUP", "Group chat", "Party chat, or raid chat in a raid.")
        container:Add("WHISPER", "Whisper", "A private whisper to the player.")
        return container:GetData()
    end, "Where the congratulation is sent.")

    Settings.CreateDropdown(category, Setting("every", "Which levels"), function()
        local container = Settings.CreateControlTextContainer()
        container:Add(1, "Every level")
        container:Add(5, "Every 5th level")
        container:Add(10, "Every 10th level")
        return container:GetData()
    end, "Limit congratulations to milestone levels. Reaching max level always counts.")

    local seconds = Settings.CreateSliderOptions(0, 10, 1)
    seconds:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
        return value .. " s"
    end)
    Settings.CreateSlider(category, Setting("delay", "Shortest delay"), seconds,
        "The wait before sending is picked at random between the shortest and longest delay.")
    Settings.CreateSlider(category, Setting("delayMax", "Longest delay"), seconds,
        "Set it equal to the shortest delay for a fixed wait. Level-ups during the wait share one message.")

    Settings.CreateCheckbox(category, Setting("random", "Random message order"),
        "Pick a random message instead of rotating through the list.")

    Settings.CreateCheckbox(category, Setting("raids", "Also in raids"),
        "Congratulate raid members too. Off by default: raids are large and it gets noisy.")

    Settings.RegisterCanvasLayoutSubcategory(category, CreateMessagesPanel(), "Messages")
    Settings.RegisterAddOnCategory(category)
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("UNIT_LEVEL")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        if type(AutoGratulationsDB) ~= "table" then AutoGratulationsDB = {} end
        db = AutoGratulationsDB
        for key, value in pairs(defaults) do
            if type(db[key]) ~= type(value) then db[key] = value end
        end
        if type(db.messages) ~= "table" or type(db.messages[1]) ~= "string" then db.messages = nil end
        RegisterSettings()
    elseif not db then
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Fresh baseline after a loading screen; never send grats for an old ding.
        playerGUID = UnitGUID("player")
        levels = {}
        Scan(false)
    else
        Scan(true)
    end
end)

SLASH_AUTOGRATULATIONS1 = "/ag"
SLASH_AUTOGRATULATIONS2 = "/autogratulations"
SlashCmdList["AUTOGRATULATIONS"] = function(command)
    command = string.lower(strtrim(command or ""))
    if command == "on" or command == "off" then
        db.enabled = command == "on"
        Print(db.enabled and "Enabled." or "Disabled.")
    elseif command == "test" then
        Preview()
    else
        Settings.OpenToCategory(category:GetID())
    end
end

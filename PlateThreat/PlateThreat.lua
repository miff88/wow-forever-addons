-- Plate Threat (WoW Forever)
-- Shows your threat on each enemy nameplate as a percentage of what it takes to pull
-- aggro (100% = you have it). Sits beside the health bar so it doesn't clash with the
-- Overpower Plates icon above the bar.
--
-- Forever hands addons threat as "secret" values: they can be shown on screen but the
-- addon can't do maths on them. So the number is passed straight to the text, and the
-- colour only changes when the game lets the addon read the value. No combat log is used.
--
-- Needs enemy nameplates on (V by default).

local ADDON_NAME = ...

local defaults = {
    size = 11,         -- font size
    side = "right",    -- "right" or "left" of the health bar
    offsetX = 4,
}

local db
local labels = {}   -- [nameplate] = holder frame with .text
local testMode = false

local GetNamePlates = C_NamePlate.GetNamePlates
local GetNamePlateForUnit = C_NamePlate.GetNamePlateForUnit

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function PlateAnchor(plate)
    local uf = plate.UnitFrame
    if uf and uf.healthBar then return uf.healthBar end
    if uf and uf.HealthBar then return uf.HealthBar end
    return plate
end

local function PlateUnit(plate)
    return plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
end

-- Colour for a readable percentage: green when safe, yellow getting close, red about to pull.
local function PctColour(pct)
    if pct >= 100 then return 1, 0.15, 0.15 end
    if pct >= 85 then return 1, 0.5, 0.1 end
    if pct >= 65 then return 1, 0.9, 0.2 end
    return 0.4, 1, 0.4
end

local STATUS_COLOURS = {
    [0] = { 0.4, 1, 0.4 },   -- not near aggro
    [1] = { 1, 0.9, 0.2 },   -- higher threat than the tank, not tanking yet
    [2] = { 1, 0.5, 0.1 },   -- tanking, but someone is about to take it
    [3] = { 1, 0.15, 0.15 }, -- securely tanking
}

---------------------------------------------------------------------------
-- Labels
---------------------------------------------------------------------------
local function GetLabel(plate)
    local f = labels[plate]
    if not f then
        f = CreateFrame("Frame", nil, plate)
        f:SetFrameStrata("HIGH")
        f:SetSize(1, 1)
        f.text = f:CreateFontString(nil, "OVERLAY")
        f.text:SetPoint("CENTER")
        f:Hide()
        labels[plate] = f
    end

    f.text:SetFont(STANDARD_TEXT_FONT, db.size, "OUTLINE")
    f:ClearAllPoints()
    f.text:ClearAllPoints()
    local anchor = PlateAnchor(plate)
    if db.side == "left" then
        f:SetPoint("RIGHT", anchor, "LEFT", -db.offsetX, 0)
        f.text:SetPoint("RIGHT", f, "RIGHT")
    else
        f:SetPoint("LEFT", anchor, "RIGHT", db.offsetX, 0)
        f.text:SetPoint("LEFT", f, "LEFT")
    end
    return f
end

local function SetThreatText(fs, pct)
    -- SetFormattedText accepts secret values; fall back to plain SetText if it won't.
    if not pcall(fs.SetFormattedText, fs, "%.0f%%", pct) then
        pcall(fs.SetText, fs, pct)
    end
end

local function UpdatePlate(plate, unit)
    if not plate then return end
    local f = GetLabel(plate)
    unit = unit or PlateUnit(plate)

    if testMode then
        f.text:SetText("87%")
        f.text:SetTextColor(PctColour(87))
        f:Show()
        return
    end

    if not unit or not UnitAffectingCombat("player") then
        f:Hide()
        return
    end

    local ok, isTanking, status, pct = pcall(UnitDetailedThreatSituation, "player", unit)
    if not ok then
        f:Hide()
        return
    end

    -- nil means you aren't on this mob's threat list (only checkable when not secret)
    if not IsSecret(pct) and pct == nil then
        f:Hide()
        return
    end

    SetThreatText(f.text, pct)

    if not IsSecret(isTanking) and isTanking then
        f.text:SetTextColor(1, 0.15, 0.15)
    elseif not IsSecret(pct) and type(pct) == "number" then
        f.text:SetTextColor(PctColour(pct))
    elseif not IsSecret(status) and STATUS_COLOURS[status] then
        f.text:SetTextColor(unpack(STATUS_COLOURS[status]))
    else
        f.text:SetTextColor(1, 1, 1)
    end

    f:Show()
end

local function RefreshAll()
    if not db then return end
    for _, plate in ipairs(GetNamePlates()) do
        UpdatePlate(plate)
    end
end

local function HideAll()
    for _, f in pairs(labels) do f:Hide() end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")

local function SafeRegister(event)
    return pcall(ev.RegisterEvent, ev, event)
end

SafeRegister("ADDON_LOADED")
SafeRegister("PLAYER_LOGIN")

ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        PlateThreatDB = PlateThreatDB or {}
        for k, v in pairs(defaults) do
            if PlateThreatDB[k] == nil then PlateThreatDB[k] = v end
        end
        db = PlateThreatDB

    elseif event == "PLAYER_LOGIN" then
        SafeRegister("NAME_PLATE_UNIT_ADDED")
        SafeRegister("NAME_PLATE_UNIT_REMOVED")
        SafeRegister("PLAYER_REGEN_ENABLED")
        SafeRegister("PLAYER_REGEN_DISABLED")
        SafeRegister("UNIT_THREAT_LIST_UPDATE")
        SafeRegister("UNIT_THREAT_SITUATION_UPDATE")
        C_Timer.NewTicker(0.25, RefreshAll) -- threat changes constantly, keep it fresh

    elseif event == "NAME_PLATE_UNIT_ADDED" then
        UpdatePlate(GetNamePlateForUnit(arg1), arg1)

    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local plate = GetNamePlateForUnit(arg1)
        if plate and labels[plate] then labels[plate]:Hide() end

    elseif event == "PLAYER_REGEN_ENABLED" then
        if testMode then RefreshAll() else HideAll() end

    else
        RefreshAll()
    end
end)

---------------------------------------------------------------------------
-- Slash command: /pth
---------------------------------------------------------------------------
local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Plate Threat:|r " .. msg)
end

SLASH_PLATETHREAT1 = "/pth"
SlashCmdList.PLATETHREAT = function(msg)
    local cmd, val = (msg or ""):lower():match("^(%S*)%s*(.-)$")
    local n = tonumber(val)

    if cmd == "test" then
        testMode = not testMode
        if testMode then RefreshAll() else HideAll() end
        Print("test mode " .. (testMode and "on" or "off"))
    elseif cmd == "size" and n then
        db.size = n; RefreshAll(); Print("font size " .. n)
    elseif cmd == "left" or cmd == "right" then
        db.side = cmd; RefreshAll(); Print("shown on the " .. cmd .. " of the health bar")
    elseif cmd == "gap" and n then
        db.offsetX = n; RefreshAll(); Print("gap from the health bar " .. n)
    else
        Print("commands:")
        Print("/pth test - show a sample on every nameplate")
        Print("/pth left, /pth right - which side of the health bar (now " .. db.side .. ")")
        Print("/pth size <n> - font size (now " .. db.size .. ")")
        Print("/pth gap <n> - gap from the health bar (now " .. db.offsetX .. ")")
    end
end

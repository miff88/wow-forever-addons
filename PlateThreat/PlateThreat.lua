-- Plate Threat (WoW Forever)
-- Shows your threat on each enemy nameplate as a percentage of what it takes to pull
-- aggro (100% = you have it). Sits on the left of the health bar, clear of the level box
-- and of the Overpower Plates icon above the bar.
--
-- Forever hands addons threat as "secret" values: they can be shown on screen but the
-- addon can't do maths on them. So the number is passed straight to the text, and the
-- colour only changes when the game lets the addon read the value. No combat log is used.
--
-- It also puts a retail-style threat box on top of the target frame.
--
-- Needs enemy nameplates on (V by default) for the nameplate numbers.

local ADDON_NAME, ns = ...

local defaults = {
    size = 11,         -- font size
    side = "left",     -- "left" or "right" of the health bar (right overlaps the level box)
    offsetX = 4,
    portrait = true,   -- threat box on top of the target frame
    portraitX = 0,
    portraitY = 0,
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
        f:SetSize(48, 20)
        -- start from a built-in font object so the text always has a font, even if SetFont fails
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f:Hide()
        labels[plate] = f
    end

    if f.fontSize ~= db.size then
        local fontPath = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
        if pcall(f.text.SetFont, f.text, fontPath, db.size, "OUTLINE") then
            f.fontSize = db.size
        end
    end

    f:ClearAllPoints()
    f.text:ClearAllPoints()
    local anchor = PlateAnchor(plate)
    if db.side == "left" then
        f:SetPoint("RIGHT", anchor, "LEFT", -db.offsetX, 0)
        f.text:SetPoint("RIGHT", f, "RIGHT")
        f.text:SetJustifyH("RIGHT")
    else
        f:SetPoint("LEFT", anchor, "RIGHT", db.offsetX, 0)
        f.text:SetPoint("LEFT", f, "LEFT")
        f.text:SetJustifyH("LEFT")
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

local UpdateTargetBoxRef -- set below, once the target box code exists

local function RefreshAll()
    if not db then return end
    for _, plate in ipairs(GetNamePlates()) do
        UpdatePlate(plate)
    end
    if UpdateTargetBoxRef then UpdateTargetBoxRef() end
end

---------------------------------------------------------------------------
-- Target frame box (like retail's threat percentage on the target portrait)
---------------------------------------------------------------------------
local box

local function TargetAnchor()
    if not TargetFrame then return nil end
    local content = TargetFrame.TargetFrameContent
    local name = _G.TargetFrameTextureFrameName
        or (content and content.TargetFrameContentMain and content.TargetFrameContentMain.Name)
        or TargetFrame.name
    if name then return name, 0, 2 end
    return TargetFrame, -20, -8
end

local function GetBox()
    if box then return box end
    if not TargetFrame then return nil end

    box = CreateFrame("Frame", "PlateThreatTargetBox", TargetFrame)
    box:SetSize(49, 18)
    box:SetFrameLevel((TargetFrame:GetFrameLevel() or 1) + 10)

    -- same art the game uses for its own numeric threat box
    box.bg = box:CreateTexture(nil, "BACKGROUND")
    box.bg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    box.bg:SetSize(37, 14)
    box.bg:SetPoint("TOP", 0, -3)

    box.border = box:CreateTexture(nil, "ARTWORK")
    box.border:SetTexture("Interface\\TargetingFrame\\NumericThreatBorder")
    box.border:SetTexCoord(0, 0.765625, 0, 0.5625)
    box.border:SetSize(49, 18)
    box.border:SetPoint("TOP")

    box.text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    box.text:SetPoint("TOP", 0, -4)

    box:Hide()
    return box
end

local function BoxColour(isTanking, status, pct)
    if not IsSecret(status) and type(status) == "number" and GetThreatStatusColor then
        local ok, r, g, b = pcall(GetThreatStatusColor, status)
        if ok and r then return r, g, b end
    end
    if not IsSecret(isTanking) and isTanking then return 1, 0, 0 end
    if not IsSecret(pct) and type(pct) == "number" then return PctColour(pct) end
    return 0.69, 0.69, 0.69
end

local function UpdateTargetBox()
    local b = GetBox()
    if not b then return end

    if not db.portrait then b:Hide() return end

    local anchor, ax, ay = TargetAnchor()
    b:ClearAllPoints()
    b:SetPoint("BOTTOM", anchor, "TOP", ax + db.portraitX, ay + db.portraitY)

    if testMode then
        b.text:SetText("87%")
        b.bg:SetVertexColor(PctColour(87))
        b:Show()
        return
    end

    if not UnitExists("target") or not UnitCanAttack("player", "target") or not UnitAffectingCombat("player") then
        b:Hide()
        return
    end

    local ok, isTanking, status, pct = pcall(UnitDetailedThreatSituation, "player", "target")
    if not ok or (not IsSecret(pct) and pct == nil) then
        b:Hide()
        return
    end

    SetThreatText(b.text, pct)
    b.bg:SetVertexColor(BoxColour(isTanking, status, pct))
    b:Show()
end

local function HideAll()
    for _, f in pairs(labels) do f:Hide() end
    if box then box:Hide() end
end

UpdateTargetBoxRef = UpdateTargetBox

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
        -- 1.1: move existing installs to the left so the number stops covering the level box
        if (db.v or 0) < 2 then
            db.side = "left"
            db.v = 2
        end
        ns.BuildOptions()

    elseif event == "PLAYER_LOGIN" then
        SafeRegister("NAME_PLATE_UNIT_ADDED")
        SafeRegister("NAME_PLATE_UNIT_REMOVED")
        SafeRegister("PLAYER_REGEN_ENABLED")
        SafeRegister("PLAYER_REGEN_DISABLED")
        SafeRegister("UNIT_THREAT_LIST_UPDATE")
        SafeRegister("UNIT_THREAT_SITUATION_UPDATE")
        SafeRegister("PLAYER_TARGET_CHANGED")
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

---------------------------------------------------------------------------
-- Settings page (Options > AddOns) and minimap addon button
---------------------------------------------------------------------------
local ICON = "Interface\\Icons\\Ability_Warrior_Challange"

function ns.BuildOptions()
    ns.CreateOptions({
        title = "Plate Threat",
        icon = ICON,
        about = "Your threat % on enemy nameplates and the target frame",
        credit = "Created by Miff, supported by Claude",
        slash = "/pth",
        db = db,
        onChange = function()
            for _, f in pairs(labels) do f.fontSize = nil end
            RefreshAll()
        end,
        controls = {
            { type = "header", label = "Text" },
            { type = "choice", key = "side", label = "Side of the health bar", values = { "left", "right" } },
            { type = "range", key = "size", label = "Font size", min = 8, max = 20, step = 1 },
            { type = "range", key = "offsetX", label = "Gap from the health bar", min = 0, max = 20, step = 1 },
            { type = "header", label = "Target frame" },
            { type = "check", key = "portrait", label = "Show a threat box on the target frame" },
            { type = "range", key = "portraitX", label = "Move left / right", min = -150, max = 150, step = 2 },
            { type = "range", key = "portraitY", label = "Move up / down", min = -100, max = 100, step = 2 },
            { type = "header", label = "Preview" },
            { type = "button", dynamicLabel = function() return testMode and "Stop test" or "Test on nameplates" end,
              label = "Test on nameplates",
              func = function()
                  testMode = not testMode
                  if not testMode then HideAll() end
              end },
        },
    })
end

function PlateThreat_OnAddonCompartmentClick()
    if ns.OpenOptions then ns.OpenOptions() end
end

SLASH_PLATETHREAT1 = "/pth"
SlashCmdList.PLATETHREAT = function(msg)
    local cmd, val = (msg or ""):lower():match("^(%S*)%s*(.-)$")
    local n = tonumber(val)

    if cmd == "" then
        ns.OpenOptions()
        return
    elseif cmd == "test" then
        testMode = not testMode
        if testMode then RefreshAll() else HideAll() end
        Print("test mode " .. (testMode and "on" or "off"))
    elseif cmd == "size" and n then
        db.size = n; RefreshAll(); Print("font size " .. n)
    elseif cmd == "portrait" then
        db.portrait = not db.portrait
        RefreshAll()
        Print("target frame box " .. (db.portrait and "on" or "off"))
    elseif cmd == "left" or cmd == "right" then
        db.side = cmd; RefreshAll(); Print("shown on the " .. cmd .. " of the health bar")
    elseif cmd == "gap" and n then
        db.offsetX = n; RefreshAll(); Print("gap from the health bar " .. n)
    else
        Print("v" .. ns.version .. " commands (or just /pth for the settings page):")
        Print("/pth test - show a sample on every nameplate")
        Print("/pth left, /pth right - which side of the health bar (now " .. db.side .. ")")
        Print("/pth size <n> - font size (now " .. db.size .. ")")
        Print("/pth gap <n> - gap from the health bar (now " .. db.offsetX .. ")")
        Print("/pth portrait - threat box on the target frame (now " .. (db.portrait and "on" or "off") .. ")")
    end
    if ns.RefreshOptions then ns.RefreshOptions() end
end

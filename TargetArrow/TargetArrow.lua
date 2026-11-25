-- Target Arrow (WoW Forever)
-- A bobbing arrow above your target's nameplate. Sits higher than the Overpower Plates
-- icon by default so the two stack instead of overlapping.
-- Needs nameplates on (V for enemies). No combat log is used.

local ADDON_NAME, ns = ...

local defaults = {
    updateNotice = true,  -- "a newer version is out" chat notice (VersionCheck.lua)
    size    = 28,
    offsetY = 54,      -- above the health bar; Overpower Plates' icon sits at 18 to 48
    colour  = "red",
    bob     = true,
    enemiesOnly = false,
}

local COLOURS = {
    red    = { 1, 0.15, 0.15 },
    yellow = { 1, 0.85, 0.1 },
    green  = { 0.3, 1, 0.3 },
    blue   = { 0.3, 0.6, 1 },
    white  = { 1, 1, 1 },
}

local db
local GetNamePlateForUnit = C_NamePlate.GetNamePlateForUnit

---------------------------------------------------------------------------
-- Arrow frame
---------------------------------------------------------------------------
local arrow = CreateFrame("Frame", "TargetArrowFrame", UIParent)
arrow:SetFrameStrata("HIGH")
arrow:Hide()

local tex = arrow:CreateTexture(nil, "ARTWORK")
tex:SetAllPoints()

-- Use the game's tutorial down-arrow if it exists, otherwise turn the minimap arrow upside down.
local function SetupTexture()
    local hasAtlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("NPE_ArrowDown")
    if hasAtlas then
        tex:SetAtlas("NPE_ArrowDown")
        tex:SetRotation(0)
    else
        tex:SetTexture("Interface\\Minimap\\MinimapArrow")
        tex:SetRotation(math.pi)
    end
end
SetupTexture()

local bob = arrow:CreateAnimationGroup()
bob:SetLooping("BOUNCE")
local move = bob:CreateAnimation("Translation")
move:SetOffset(0, 8)
move:SetDuration(0.45)
move:SetSmoothing("IN_OUT")

local function ApplyLook()
    arrow:SetSize(db.size, db.size)
    local c = COLOURS[db.colour] or COLOURS.red
    tex:SetVertexColor(c[1], c[2], c[3])
end

local function PlateAnchor(plate)
    local uf = plate.UnitFrame
    if uf and uf.healthBar then return uf.healthBar end
    if uf and uf.HealthBar then return uf.HealthBar end
    return plate
end

local function Update()
    if not db then return end

    local plate = UnitExists("target") and GetNamePlateForUnit("target")
    if plate and db.enemiesOnly and not UnitCanAttack("player", "target") then
        plate = nil
    end

    if not plate then
        bob:Stop()
        arrow:Hide()
        return
    end

    arrow:SetParent(plate)
    arrow:SetFrameStrata("HIGH")
    arrow:ClearAllPoints()
    arrow:SetPoint("BOTTOM", PlateAnchor(plate), "TOP", 0, db.offsetY)
    ApplyLook()
    arrow:Show()

    if db.bob then
        if not bob:IsPlaying() then bob:Play() end
    else
        bob:Stop()
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")

local function SafeRegister(event)
    return pcall(ev.RegisterEvent, ev, event)
end

SafeRegister("ADDON_LOADED")
SafeRegister("PLAYER_TARGET_CHANGED")
SafeRegister("NAME_PLATE_UNIT_ADDED")
SafeRegister("NAME_PLATE_UNIT_REMOVED")
SafeRegister("PLAYER_ENTERING_WORLD")

ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        TargetArrowDB = TargetArrowDB or {}
        for k, v in pairs(defaults) do
            if TargetArrowDB[k] == nil then TargetArrowDB[k] = v end
        end
        db = TargetArrowDB
        if ns.StartVersionCheck then ns.StartVersionCheck(db, "Target Arrow") end
        ApplyLook()
        ns.BuildOptions()
        return
    end

    if event == "NAME_PLATE_UNIT_REMOVED" then
        -- the plate is going away; drop the arrow back to UIParent so it isn't recycled with it
        local plate = GetNamePlateForUnit(arg1)
        if plate and arrow:GetParent() == plate then
            bob:Stop()
            arrow:Hide()
            arrow:SetParent(UIParent)
        end
        C_Timer.After(0, Update)
        return
    end

    Update()
end)

---------------------------------------------------------------------------
-- Slash command: /tarrow
---------------------------------------------------------------------------
local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Target Arrow:|r " .. msg)
end

---------------------------------------------------------------------------
-- Settings page (Options > AddOns) and minimap addon button
---------------------------------------------------------------------------
function ns.BuildOptions()
    ns.CreateOptions({
        title = "Target Arrow",
        updateNotice = true,
        changes = {
            { "1.2.1", "This What's new list" },
            { "1.2.0", "Tells you when a newer version is out" },
            { "1.1.0", "Colour, size, height and bobbing set from this page" },
        },
        icon = "Interface\\Icons\\Ability_Hunter_SniperShot",
        about = "An arrow over your target's nameplate",
        credit = "Created by Miff, supported by Claude",
        slash = "/tarrow",
        db = db,
        onChange = function() Update() end,
        controls = {
            { type = "header", label = "Arrow" },
            { type = "choice", key = "colour", label = "Colour", values = { "red", "yellow", "green", "blue", "white" } },
            { type = "range", key = "size", label = "Size", min = 16, max = 64, step = 2 },
            { type = "range", key = "offsetY", label = "Height above health bar", min = 0, max = 120, step = 2 },
            { type = "check", key = "bob", label = "Bob up and down" },
            { type = "check", key = "enemiesOnly", label = "Only show on enemies" },
        },
    })
end

function TargetArrow_OnAddonCompartmentClick()
    if ns.OpenOptions then ns.OpenOptions() end
end

SLASH_TARGETARROW1 = "/tarrow"
SlashCmdList.TARGETARROW = function(msg)
    local cmd, val = (msg or ""):lower():match("^(%S*)%s*(.-)$")
    local n = tonumber(val)

    if cmd == "" then
        ns.OpenOptions()
        return
    elseif cmd == "size" and n then
        db.size = n; Print("size " .. n)
    elseif cmd == "offset" and n then
        db.offsetY = n; Print("height above the health bar " .. n)
    elseif cmd == "colour" or cmd == "color" then
        if COLOURS[val] then
            db.colour = val; Print("colour " .. val)
        else
            Print("colours: red, yellow, green, blue, white")
        end
    elseif cmd == "bob" then
        db.bob = not db.bob; Print("bobbing " .. (db.bob and "on" or "off"))
    elseif cmd == "enemies" then
        db.enemiesOnly = not db.enemiesOnly
        Print(db.enemiesOnly and "only on enemies" or "on any target with a nameplate")
    else
        Print("v" .. ns.version .. " commands (or just /tarrow for the settings page):")
        Print("/tarrow size <n> - arrow size (now " .. db.size .. ")")
        Print("/tarrow offset <n> - height above the health bar (now " .. db.offsetY .. ")")
        Print("/tarrow colour <red|yellow|green|blue|white> (now " .. db.colour .. ")")
        Print("/tarrow bob - bobbing on or off (now " .. (db.bob and "on" or "off") .. ")")
        Print("/tarrow enemies - only show on enemies (now " .. (db.enemiesOnly and "on" or "off") .. ")")
    end
    Update()
    if ns.RefreshOptions then ns.RefreshOptions() end
end

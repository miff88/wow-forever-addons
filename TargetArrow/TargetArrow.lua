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
    -- a second arrow, for your focus or a raid marker
    second  = "off",   -- "off", "focus" or "marker"
    secondMarker = 8,  -- 8 = skull ... 1 = star
    secondColour = "blue",
}

local COLOURS = {
    red    = { 1, 0.15, 0.15 },
    yellow = { 1, 0.85, 0.1 },
    green  = { 0.3, 1, 0.3 },
    blue   = { 0.3, 0.6, 1 },
    white  = { 1, 1, 1 },
    purple = { 0.75, 0.4, 1 },
    orange = { 1, 0.5, 0.1 },
}
local COLOUR_ORDER = { "red", "yellow", "green", "blue", "white", "purple", "orange" }

local MARKERS = { [8] = "Skull", [7] = "Cross", [6] = "Square", [5] = "Moon",
                  [4] = "Triangle", [3] = "Diamond", [2] = "Circle", [1] = "Star" }

local db
local GetNamePlateForUnit = C_NamePlate.GetNamePlateForUnit

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

---------------------------------------------------------------------------
-- Arrow frames
---------------------------------------------------------------------------
local function MakeArrow(name)
    local a = {}
    a.frame = CreateFrame("Frame", name, UIParent)
    a.frame:SetFrameStrata("HIGH")
    a.frame:Hide()
    a.tex = a.frame:CreateTexture(nil, "ARTWORK")
    a.tex:SetAllPoints()
    -- the game's tutorial down-arrow if it exists, otherwise the minimap arrow upside down
    local hasAtlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("NPE_ArrowDown")
    if hasAtlas then
        a.tex:SetAtlas("NPE_ArrowDown")
        a.tex:SetRotation(0)
    else
        a.tex:SetTexture("Interface\\Minimap\\MinimapArrow")
        a.tex:SetRotation(math.pi)
    end
    a.bob = a.frame:CreateAnimationGroup()
    a.bob:SetLooping("BOUNCE")
    local move = a.bob:CreateAnimation("Translation")
    move:SetOffset(0, 8)
    move:SetDuration(0.45)
    move:SetSmoothing("IN_OUT")
    return a
end

local main = MakeArrow("TargetArrowFrame")
local second = MakeArrow("TargetArrowSecondFrame")
ns.main, ns.second = main, second

local function ApplyLook()
    local c = COLOURS[db.colour] or COLOURS.red
    main.frame:SetSize(db.size, db.size)
    main.tex:SetVertexColor(c[1], c[2], c[3])
    -- the second arrow is a little smaller so the two are easy to tell apart
    local s2 = math.floor(db.size * 0.8 + 0.5)
    local c2 = COLOURS[db.secondColour] or COLOURS.blue
    second.frame:SetSize(s2, s2)
    second.tex:SetVertexColor(c2[1], c2[2], c2[3])
end

local function PlateAnchor(plate)
    local uf = plate.UnitFrame
    if uf and uf.healthBar then return uf.healthBar end
    if uf and uf.HealthBar then return uf.HealthBar end
    return plate
end

local function HideArrow(a)
    a.bob:Stop()
    a.frame:Hide()
    a.plate = nil
end

local function ShowArrow(a, plate)
    a.frame:SetParent(plate)
    a.frame:SetFrameStrata("HIGH")
    a.frame:ClearAllPoints()
    a.frame:SetPoint("BOTTOM", PlateAnchor(plate), "TOP", 0, db.offsetY)
    a.frame:Show()
    a.plate = plate
    if db.bob then
        if not a.bob:IsPlaying() then a.bob:Play() end
    else
        a.bob:Stop()
    end
end

local function MarkOf(unit)
    if not GetRaidTargetIndex then return nil end
    local ok, i = pcall(GetRaidTargetIndex, unit)
    if ok and not IsSecret(i) then return i end
end

-- the nameplate the second arrow belongs on
local function SecondPlate()
    if db.second == "focus" then
        if not UnitExists("focus") then return nil end
        return GetNamePlateForUnit("focus")
    elseif db.second == "marker" then
        for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
            local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
            if unit and MarkOf(unit) == db.secondMarker then return plate end
        end
    end
end

local function Update()
    if not db then return end
    ApplyLook()

    local plate = UnitExists("target") and GetNamePlateForUnit("target")
    if plate and db.enemiesOnly and not UnitCanAttack("player", "target") then
        plate = nil
    end
    if plate then ShowArrow(main, plate) else HideArrow(main) end

    -- the second arrow stays away when it would point at your target too
    local p2 = SecondPlate()
    if p2 and p2 ~= plate then ShowArrow(second, p2) else HideArrow(second) end
end
ns.Update = Update

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")

local function SafeRegister(event)
    return pcall(ev.RegisterEvent, ev, event)
end

SafeRegister("ADDON_LOADED")
SafeRegister("PLAYER_TARGET_CHANGED")
SafeRegister("PLAYER_FOCUS_CHANGED")
SafeRegister("RAID_TARGET_UPDATE")
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
        -- marks can move between mobs without an event on every client, so check now and then
        if C_Timer and C_Timer.NewTicker then
            C_Timer.NewTicker(0.5, function() if db.second == "marker" then Update() end end)
        end
        return
    end

    if event == "NAME_PLATE_UNIT_REMOVED" then
        -- the plate is going away; drop the arrows back to UIParent so they aren't recycled with it
        local plate = GetNamePlateForUnit(arg1)
        for _, a in ipairs({ main, second }) do
            if plate and a.frame:GetParent() == plate then
                HideArrow(a)
                a.frame:SetParent(UIParent)
            end
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
            { "1.3.0", "A second arrow for your focus or a raid marker (skull by default), in its own colour",
                       "Purple and orange arrows" },
            { "1.2.1", "This What's new list" },
            { "1.2.0", "Tells you when a newer version is out" },
        },
        icon = "Interface\\Icons\\Ability_Hunter_SniperShot",
        about = "An arrow over your target's nameplate",
        credit = "Created by Miff, supported by Claude",
        slash = "/tarrow",
        db = db,
        onChange = function() Update() end,
        controls = {
            { type = "header", label = "Arrow" },
            { type = "choice", key = "colour", label = "Colour", values = COLOUR_ORDER },
            { type = "range", key = "size", label = "Size", min = 16, max = 64, step = 2 },
            { type = "range", key = "offsetY", label = "Height above health bar", min = 0, max = 120, step = 2 },
            { type = "check", key = "bob", label = "Bob up and down" },
            { type = "check", key = "enemiesOnly", label = "Only show on enemies" },
            { type = "header", label = "Second arrow" },
            { type = "dropdown", key = "second", label = "A second arrow on", options = function() return {
                { value = "off", label = "Nothing (off)" },
                { value = "focus", label = "My focus" },
                { value = "marker", label = "A raid marker" },
              } end },
            { type = "dropdown", key = "secondMarker", label = "Which raid marker", options = function()
                local out = {}
                for i = 8, 1, -1 do
                    out[#out + 1] = { value = i, label = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i .. ":0|t " .. MARKERS[i] }
                end
                return out
              end },
            { type = "choice", key = "secondColour", label = "Second arrow colour", values = COLOUR_ORDER },
            { type = "info", height = 30, lines = function()
                return "|cff999999A little smaller than the main one. It hides when your target is the same mob.|r" end },
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
            Print("colours: " .. table.concat(COLOUR_ORDER, ", "))
        end
    elseif cmd == "focus" then
        db.second = db.second == "focus" and "off" or "focus"
        Print(db.second == "focus" and "second arrow on your focus" or "second arrow off")
    elseif cmd == "marker" or cmd == "mark" then
        local pick
        for i, name in pairs(MARKERS) do if name:lower() == val or tostring(i) == val then pick = i end end
        if pick then
            db.second, db.secondMarker = "marker", pick
            Print("second arrow on the " .. MARKERS[pick] .. " marker")
        elseif val == "" and db.second == "marker" then
            db.second = "off"; Print("second arrow off")
        else
            db.second = "marker"
            Print("second arrow on the " .. MARKERS[db.secondMarker] .. " marker (/tarrow marker <skull|cross|square|moon|triangle|diamond|circle|star>)")
        end
    elseif cmd == "second" then
        if val == "off" then db.second = "off"; Print("second arrow off")
        elseif COLOURS[val] then db.secondColour = val; Print("second arrow colour " .. val)
        else Print("/tarrow second off, or /tarrow second <colour>") end
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
        Print("/tarrow focus - a second arrow on your focus; /tarrow marker <skull|cross|...> - on a raid marker")
        Print("/tarrow second <colour> - its colour; /tarrow second off")
    end
    Update()
    if ns.RefreshOptions then ns.RefreshOptions() end
end

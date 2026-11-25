-- Overpower Plates (WoW Forever)
-- Puts an Overpower icon above the nameplate of the mob that dodged YOU, including mobs
-- that dodge a Whirlwind or Cleave while they aren't your target.
--
-- How it knows a dodge was against you:
--   Forever tracks Overpower as combo points on the warrior, one per dodge against you,
--   spent when you Overpower. Forever also reports dodges on every enemy nameplate, but
--   those include dodges against other players. So a nameplate dodge only counts when a
--   new combo point appears at the same moment. Anything else is ignored.
--
-- No combat log is used (Forever forbids it). Needs enemy nameplates on (V by default).

local ADDON_NAME, ns = ...

---------------------------------------------------------------------------
-- Settings (saved per account, change with /opp)
---------------------------------------------------------------------------
local defaults = {
    updateNotice = true,  -- "a newer version is out" chat notice (VersionCheck.lua)
    window  = 5,    -- seconds Overpower stays usable after a dodge
    size    = 30,   -- icon size in pixels
    offsetY = 18,   -- how far above the health bar the icon sits
    sound   = true, -- play a sound when a mob dodges you
    pop     = true, -- icon pops in with a quick scale animation
    pulse   = true, -- glow pulses around the nameplate icon while Overpower is up
    barGlow = true, -- your Overpower button on the action bars glows while it's up
    screenIcon = false, -- big Overpower icon in the middle of the screen
    screenSize = 64,
}

local MATCH_WINDOW = 0.35 -- seconds between a nameplate dodge and a new combo point to call it a match

local db

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, id)
        if ok and name and not IsSecret(name) then return name end
    end
end

local function SpellTexture(id)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, id)
        if ok and tex and not IsSecret(tex) then return tex end
    end
end

local OVERPOWER_NAME = SpellName("Overpower") or SpellName(7384) or "Overpower"
local OVERPOWER_ICON = SpellTexture("Overpower") or SpellTexture(7384) or "Interface\\Icons\\Ability_MeleeDamage"

ns.OVERPOWER_NAME = OVERPOWER_NAME
ns.OVERPOWER_ICON = OVERPOWER_ICON

local COMBO_TYPE = (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4

-- Your Overpower charges (combo points), or nil if the game won't say.
local function ReadPoints()
    local ok, v = pcall(UnitPower, "player", COMBO_TYPE)
    if ok and type(v) == "number" and not IsSecret(v) then return v end
    if GetComboPoints then
        ok, v = pcall(GetComboPoints, "player", "target")
        if ok and type(v) == "number" and not IsSecret(v) then return v end
    end
    return nil
end

local function IsNameplateUnit(unit)
    return type(unit) == "string" and unit:find("^nameplate%d+$") ~= nil
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local procs = {}        -- [nameplate unit token] = time the Overpower window closes
local recentDodges = {} -- [nameplate unit token] = time it reported a dodge (against anyone)
local unmatchedGains = {} -- times of new combo points still waiting for their nameplate dodge
local icons = {}        -- [nameplate frame] = icon frame
local lastPoints = 0
local testMode = false

local GetNamePlates = C_NamePlate.GetNamePlates
local GetNamePlateForUnit = C_NamePlate.GetNamePlateForUnit

---------------------------------------------------------------------------
-- Icon frames
---------------------------------------------------------------------------
local function PlateAnchor(plate)
    local uf = plate.UnitFrame
    if uf and uf.healthBar then return uf.healthBar end
    if uf and uf.HealthBar then return uf.HealthBar end
    return plate
end

local function GetIcon(plate)
    local f = icons[plate]
    if not f then
        f = CreateFrame("Frame", nil, plate)
        f:SetFrameStrata("HIGH")

        -- soft gold glow behind the icon, pulsing while Overpower is up
        f.glow = f:CreateTexture(nil, "BACKGROUND", nil, -1)
        f.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        f.glow:SetBlendMode("ADD")
        f.glow:SetVertexColor(1, 0.82, 0.1)
        f.glow:SetPoint("CENTER")
        f.glow:Hide()

        f.pulse = f:CreateAnimationGroup()
        f.pulse:SetLooping("BOUNCE")
        local fade = f.pulse:CreateAnimation("Alpha")
        fade:SetTarget(f.glow)
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0.2)
        fade:SetDuration(0.35)

        f.border = f:CreateTexture(nil, "BACKGROUND")
        f.border:SetPoint("TOPLEFT", -2, 2)
        f.border:SetPoint("BOTTOMRIGHT", 2, -2)
        f.border:SetColorTexture(1, 0.82, 0, 1)

        f.tex = f:CreateTexture(nil, "ARTWORK")
        f.tex:SetAllPoints()
        f.tex:SetTexture(OVERPOWER_ICON)
        f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
        f.cd:SetAllPoints()
        if f.cd.SetDrawEdge then f.cd:SetDrawEdge(false) end

        f.pop = f:CreateAnimationGroup()
        local grow = f.pop:CreateAnimation("Scale")
        if grow.SetScaleFrom then
            grow:SetScaleFrom(1.7, 1.7)
            grow:SetScaleTo(1, 1)
        else
            grow:SetScale(0.6, 0.6)
        end
        grow:SetDuration(0.18)
        grow:SetSmoothing("OUT")

        f:Hide()
        icons[plate] = f
    end

    f:SetSize(db.size, db.size)
    f.glow:SetSize(db.size * 1.9, db.size * 1.9)
    f:ClearAllPoints()
    f:SetPoint("BOTTOM", PlateAnchor(plate), "TOP", 0, db.offsetY)
    return f
end

local function PlateUnit(plate)
    return plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
end

local function SetPulse(f, on)
    if on and db.pulse then
        f.glow:Show()
        if not f.pulse:IsPlaying() then f.pulse:Play() end
    else
        f.pulse:Stop()
        f.glow:Hide()
    end
end

local function UpdatePlate(plate, unit)
    if not plate then return end
    local f = GetIcon(plate)
    unit = unit or PlateUnit(plate)

    if testMode then
        f.cd:SetCooldown(GetTime(), db.window)
        f:Show()
        SetPulse(f, true)
        return
    end

    local expires = unit and procs[unit]
    if expires and expires > GetTime() then
        f.cd:SetCooldown(expires - db.window, db.window)
        if not f:IsShown() and db.pop then f.pop:Stop(); f.pop:Play() end
        f:Show()
        SetPulse(f, true)
    else
        SetPulse(f, false)
        f:Hide()
    end
end

local function RefreshAll()
    local now = GetTime()
    for unit, expires in pairs(procs) do
        if expires <= now then procs[unit] = nil end
    end
    for _, plate in ipairs(GetNamePlates()) do
        UpdatePlate(plate)
    end

    -- the louder alerts (Alerts.lua): button glow and the big screen icon
    local latest
    for _, expires in pairs(procs) do
        if not latest or expires > latest then latest = expires end
    end
    if testMode then latest = now + db.window end
    if ns.SetButtonGlow then ns.SetButtonGlow(db.barGlow and latest ~= nil) end
    if ns.UpdateScreenIcon then ns.UpdateScreenIcon(latest, ReadPoints()) end
end

---------------------------------------------------------------------------
-- Matching dodges to your combo points
---------------------------------------------------------------------------
local function Mark(unit)
    procs[unit] = GetTime() + db.window
    recentDodges[unit] = nil
    if db.sound and PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
        PlaySound(SOUNDKIT.RAID_WARNING, "SFX")
    end
    RefreshAll()
    C_Timer.After(db.window + 0.05, RefreshAll)
end

-- Most recent nameplate dodge inside the match window, or nil.
local function TakeRecentDodge(now)
    local best, bestT
    for unit, t in pairs(recentDodges) do
        if now - t > MATCH_WINDOW then
            recentDodges[unit] = nil
        elseif not bestT or t > bestT then
            best, bestT = unit, t
        end
    end
    return best
end

local function PruneGains(now)
    for i = #unmatchedGains, 1, -1 do
        if now - unmatchedGains[i] > MATCH_WINDOW then table.remove(unmatchedGains, i) end
    end
end

-- A nameplate reported a dodge. Only counts if a new combo point turns up with it.
local function OnNameplateDodge(unit)
    local now = GetTime()
    PruneGains(now)
    if #unmatchedGains > 0 then
        table.remove(unmatchedGains, 1)
        Mark(unit)
    else
        recentDodges[unit] = now
    end
end

local function ClearTargetOrOldest()
    local plate = GetNamePlateForUnit("target")
    local unit = plate and PlateUnit(plate)
    if unit and procs[unit] then
        procs[unit] = nil
        return
    end
    local oldest, oldestT
    for u, t in pairs(procs) do
        if not oldestT or t < oldestT then oldest, oldestT = u, t end
    end
    if oldest then procs[oldest] = nil end
end

local function CheckPoints()
    local points = ReadPoints()
    if not points then return end

    if points > lastPoints then
        local now = GetTime()
        for _ = 1, points - lastPoints do
            local unit = TakeRecentDodge(now)
            if unit then
                Mark(unit)
            else
                table.insert(unmatchedGains, now) -- the nameplate dodge may arrive a moment later
            end
        end
    elseif points < lastPoints then
        if points == 0 then
            wipe(procs)
        else
            for _ = 1, lastPoints - points do ClearTargetOrOldest() end
        end
        RefreshAll()
    end

    lastPoints = points
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")

local function SafeRegister(event, unit)
    if unit then
        return pcall(ev.RegisterUnitEvent, ev, event, unit)
    end
    return pcall(ev.RegisterEvent, ev, event)
end

SafeRegister("ADDON_LOADED")
SafeRegister("PLAYER_LOGIN")

ev:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "UNIT_COMBAT" then
        -- arg1 = unit, arg2 = what happened ("WOUND", "DODGE", ...)
        if IsNameplateUnit(arg1) and not IsSecret(arg2) and arg2 == "DODGE" then
            OnNameplateDodge(arg1)
        end

    elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" then
        CheckPoints()

    elseif event == "NAME_PLATE_UNIT_ADDED" then
        UpdatePlate(GetNamePlateForUnit(arg1), arg1)

    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        -- the token gets reused for another mob, so forget anything stored against it
        procs[arg1] = nil
        recentDodges[arg1] = nil
        local plate = GetNamePlateForUnit(arg1)
        if plate and icons[plate] then icons[plate]:Hide() end

    elseif event == "ACTIONBAR_PAGE_CHANGED" or event == "UPDATE_BONUS_ACTIONBAR"
        or event == "ACTIONBAR_SLOT_CHANGED" or event == "UPDATE_SHAPESHIFT_FORM" then
        -- stance swaps page the bars, so the Overpower button may have moved
        if next(procs) or testMode then RefreshAll() end

    elseif event == "PLAYER_REGEN_ENABLED" then
        wipe(procs)
        wipe(recentDodges)
        wipe(unmatchedGains)
        RefreshAll()

    elseif event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        OverpowerPlatesDB = OverpowerPlatesDB or {}
        for k, v in pairs(defaults) do
            if OverpowerPlatesDB[k] == nil then OverpowerPlatesDB[k] = v end
        end
        db = OverpowerPlatesDB
        ns.db = db
        if ns.StartVersionCheck then ns.StartVersionCheck(db, "Overpower Plates") end
        ns.BuildOptions()

    elseif event == "PLAYER_LOGIN" then
        local _, class = UnitClass("player")
        if class ~= "WARRIOR" then return end

        SafeRegister("UNIT_COMBAT")
        SafeRegister("UNIT_POWER_UPDATE", "player")
        SafeRegister("UNIT_POWER_FREQUENT", "player")
        SafeRegister("NAME_PLATE_UNIT_ADDED")
        SafeRegister("NAME_PLATE_UNIT_REMOVED")
        SafeRegister("PLAYER_REGEN_ENABLED")
        SafeRegister("ACTIONBAR_PAGE_CHANGED")
        SafeRegister("UPDATE_BONUS_ACTIONBAR")
        SafeRegister("ACTIONBAR_SLOT_CHANGED")
        SafeRegister("UPDATE_SHAPESHIFT_FORM")

        lastPoints = ReadPoints() or 0
        if ReadPoints() == nil then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Overpower Plates:|r can't read your Overpower charges on this client, so no icons will show.")
        end
        -- backup in case a power event is missed
        C_Timer.NewTicker(0.1, CheckPoints)
    end
end)

---------------------------------------------------------------------------
-- Slash command: /opp
---------------------------------------------------------------------------
local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Overpower Plates:|r " .. msg)
end

---------------------------------------------------------------------------
-- Settings page (Options > AddOns) and minimap addon button
---------------------------------------------------------------------------
function ns.BuildOptions()
    ns.CreateOptions({
        title = "Overpower Plates",
        updateNotice = true,
        changes = {
            { "1.5.1", "Finds your Overpower button on more setups, with a gold border",
                       "/opp debug shows which buttons it found" },
            { "1.5.0", "Gold glow pulses around the nameplate icon",
                       "Your Overpower button glows on the action bars",
                       "Optional big Overpower icon in the middle of the screen" },
            { "1.4.1", "This What's new list" },
            { "1.4.0", "Tells you when a newer version is out" },
            { "1.3.0", "Icon pops in with a quick animation (can be turned off)" },
        },
        icon = OVERPOWER_ICON,
        about = "Overpower icon on the mob that dodged you",
        credit = "Created by Miff, supported by Claude",
        slash = "/opp",
        db = db,
        onChange = function() RefreshAll() end,
        controls = {
            { type = "header", label = "Icon" },
            { type = "range", key = "size", label = "Icon size", min = 16, max = 64, step = 2 },
            { type = "range", key = "offsetY", label = "Height above health bar", min = 0, max = 80, step = 2 },
            { type = "range", key = "window", label = "Seconds the icon stays up", min = 1, max = 10, step = 1, suffix = "s" },
            { type = "check", key = "pop", label = "Pop the icon in when a mob dodges you" },
            { type = "check", key = "pulse", label = "Pulse a gold glow around the icon while Overpower is up" },
            { type = "header", label = "Alerts" },
            { type = "check", key = "sound", label = "Play a sound when a mob dodges you" },
            { type = "check", key = "barGlow", label = "Make your Overpower button glow on the action bars" },
            { type = "check", key = "screenIcon", label = "Show a big Overpower icon in the middle of the screen" },
            { type = "range", key = "screenSize", label = "Screen icon size", min = 32, max = 128, step = 4 },
            { type = "button", dynamicLabel = function() return ns.screenUnlocked and "Lock screen icon" or "Move screen icon" end,
              label = "Move screen icon", func = function() ns.screenUnlocked = not ns.screenUnlocked; RefreshAll() end },
            { type = "button", label = "Reset screen icon position", func = function() ns.ResetScreenIcon(); RefreshAll() end },
            { type = "header", label = "Preview" },
            { type = "button", dynamicLabel = function() return testMode and "Stop test" or "Test on nameplates" end,
              label = "Test on nameplates", func = function() testMode = not testMode; RefreshAll() end },
        },
    })
end

function OverpowerPlates_OnAddonCompartmentClick()
    if ns.OpenOptions then ns.OpenOptions() end
end

SLASH_OVERPOWERPLATES1 = "/opp"
SlashCmdList.OVERPOWERPLATES = function(msg)
    local cmd, val = (msg or ""):lower():match("^(%S*)%s*(.-)$")
    local n = tonumber(val)

    if cmd == "" then
        ns.OpenOptions()
        return
    elseif cmd == "test" then
        testMode = not testMode
        RefreshAll()
        Print(testMode and "test mode on, every visible nameplate shows the icon. /opp test again to turn it off."
                        or "test mode off.")
    elseif cmd == "size" and n then
        db.size = n; RefreshAll(); Print("icon size " .. n)
    elseif cmd == "offset" and n then
        db.offsetY = n; RefreshAll(); Print("icon offset " .. n)
    elseif cmd == "window" and n then
        db.window = n; Print("Overpower window " .. n .. " seconds")
    elseif cmd == "sound" then
        db.sound = not db.sound
        Print("sound " .. (db.sound and "on" or "off"))
    elseif cmd == "glow" then
        db.barGlow = not db.barGlow; RefreshAll()
        Print("action bar glow " .. (db.barGlow and "on" or "off"))
    elseif cmd == "screen" then
        db.screenIcon = not db.screenIcon; RefreshAll()
        Print("screen icon " .. (db.screenIcon and "on" or "off") .. (db.screenIcon and ". /opp move to place it." or ""))
    elseif cmd == "move" then
        ns.screenUnlocked = not ns.screenUnlocked; RefreshAll()
        Print(ns.screenUnlocked and "screen icon unlocked, drag it where you want it. /opp move again to lock." or "screen icon locked.")
    elseif cmd == "debug" then
        Print("Overpower charges: " .. tostring(ReadPoints()))
        if ns.GlowDebug then
            for _, line in ipairs(ns.GlowDebug()) do Print(line) end
        end
    else
        Print("v" .. ns.version .. " commands (or just /opp for the settings page):")
        Print("/opp test - show the icon on every nameplate to check placement")
        Print("/opp size <n> - icon size (now " .. db.size .. ")")
        Print("/opp offset <n> - height above the health bar (now " .. db.offsetY .. ")")
        Print("/opp window <n> - seconds the icon stays up (now " .. db.window .. ")")
        Print("/opp sound - dodge sound (now " .. (db.sound and "on" or "off") .. ")")
        Print("/opp glow - glow on your Overpower button (now " .. (db.barGlow and "on" or "off") .. ")")
        Print("/opp screen - big icon in the middle of the screen (now " .. (db.screenIcon and "on" or "off") .. "), /opp move to place it")
        Print("/opp debug - show your Overpower charges and which action buttons hold Overpower")
    end
    if ns.RefreshOptions then ns.RefreshOptions() end
end

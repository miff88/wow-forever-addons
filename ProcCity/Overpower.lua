-- Proc City: Overpower (warriors). From Overpower Plates / Proc Plates, now part of Proc City.
--
-- When a mob dodges YOU, Overpower shows in the icon row for its 5 second window, and
-- (optionally) an Overpower icon sits above that mob's nameplate, including mobs that
-- dodge a Whirlwind or Cleave while they aren't your target.
--
-- How it knows a dodge was against you:
--   Forever tracks Overpower as combo points on the warrior, one per dodge against you,
--   spent when you Overpower. Forever also reports dodges on every enemy nameplate, but
--   those include dodges against other players. So a nameplate dodge only counts when a
--   new combo point appears at the same moment. Anything else is ignored.
-- No combat log is used (Forever forbids it). The nameplate icon needs enemy nameplates on.

local _, ns = ...

local MATCH_WINDOW = 0.35 -- seconds between a nameplate dodge and a new combo point to call it a match

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

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
ns.ReadOverpowerCharges = ReadPoints

local function IsNameplateUnit(unit)
    return type(unit) == "string" and unit:find("^nameplate%d+$") ~= nil
end

local function Entry()
    for _, p in ipairs(ns.PROCS) do if p.key == "overpower" then return p end end
end

local procs = {}          -- [nameplate unit token] = time the Overpower window closes
local recentDodges = {}   -- [nameplate unit token] = time it reported a dodge (against anyone)
local unmatchedGains = {} -- times of new combo points still waiting for their nameplate dodge
local icons = {}          -- [nameplate frame] = icon frame
local lastPoints = 0
local enabled = false     -- warriors only

local GetNamePlates = C_NamePlate.GetNamePlates
local GetNamePlateForUnit = C_NamePlate.GetNamePlateForUnit

local function Wanted()
    local p = Entry()
    return enabled and p and ns.Wanted and ns.Wanted(p)
end

---------------------------------------------------------------------------
-- Nameplate icons
---------------------------------------------------------------------------
local function PlateAnchor(plate)
    local uf = plate.UnitFrame
    if uf and uf.healthBar then return uf.healthBar end
    if uf and uf.HealthBar then return uf.HealthBar end
    return plate
end

local function PlateUnit(plate)
    return plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
end

local function GetIcon(plate)
    local db = ns.db
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
        f.tex:SetTexture((Entry() or {}).icon or "Interface\\Icons\\Ability_MeleeDamage")
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

    f:SetSize(db.oppSize, db.oppSize)
    f.glow:SetSize(db.oppSize * 1.9, db.oppSize * 1.9)
    f:ClearAllPoints()
    f:SetPoint("BOTTOM", PlateAnchor(plate), "TOP", 0, db.oppOffset)
    return f
end

local function SetPulse(f, on)
    if on and ns.db.oppPulse then
        f.glow:Show()
        if not f.pulse:IsPlaying() then f.pulse:Play() end
    else
        f.pulse:Stop()
        f.glow:Hide()
    end
end

local function UpdatePlate(plate, unit)
    if not plate then return end
    local db = ns.db
    local f = GetIcon(plate)
    unit = unit or PlateUnit(plate)
    local test = ns.IsTest and ns.IsTest()

    if enabled and db.oppPlates and test then
        f.cd:SetCooldown(GetTime(), db.oppWindow)
        f:Show()
        SetPulse(f, true)
        return
    end

    local expires = unit and procs[unit]
    if Wanted() and db.oppPlates and expires and expires > GetTime() then
        f.cd:SetCooldown(expires - db.oppWindow, db.oppWindow)
        if not f:IsShown() and db.oppPop then f.pop:Stop(); f.pop:Play() end
        f:Show()
        SetPulse(f, true)
    else
        SetPulse(f, false)
        f:Hide()
    end
end

-- the nameplate icons, and Overpower in the icon row while any window is open
local function RefreshAll()
    if not ns.db then return end
    local now = GetTime()
    for unit, expires in pairs(procs) do
        if expires <= now then procs[unit] = nil end
    end
    for _, plate in ipairs(GetNamePlates()) do
        UpdatePlate(plate)
    end
    if not enabled or (ns.IsTest and ns.IsTest()) then return end

    local latest, count = nil, 0
    for _, expires in pairs(procs) do
        count = count + 1
        if not latest or expires > latest then latest = expires end
    end
    local p = Entry()
    local a = ns.Active()[p.key]
    if latest and Wanted() then
        if not a or a.expires ~= latest or a.stacks ~= count then
            ns.Start(p, "react", { duration = ns.db.oppWindow, expires = latest, stacks = count })
        end
    elseif a and a.source == "react" then
        ns.Remove(p.key)
        ns.Layout()
    end
end
ns.RefreshOverpower = RefreshAll

---------------------------------------------------------------------------
-- Matching dodges to your combo points
---------------------------------------------------------------------------
local function Mark(unit)
    local db = ns.db
    if not Wanted() then return end
    procs[unit] = GetTime() + db.oppWindow
    recentDodges[unit] = nil
    if db.oppSound and PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
        PlaySound(SOUNDKIT.RAID_WARNING, "SFX")
    end
    RefreshAll()
    C_Timer.After(db.oppWindow + 0.05, RefreshAll)
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

    elseif event == "PLAYER_REGEN_ENABLED" then
        wipe(procs)
        wipe(recentDodges)
        wipe(unmatchedGains)
        RefreshAll()

    elseif event == "PLAYER_LOGIN" then
        local _, class = UnitClass("player")
        if class ~= "WARRIOR" then return end
        enabled = true

        SafeRegister("UNIT_COMBAT")
        SafeRegister("UNIT_POWER_UPDATE", "player")
        SafeRegister("UNIT_POWER_FREQUENT", "player")
        SafeRegister("NAME_PLATE_UNIT_ADDED")
        SafeRegister("NAME_PLATE_UNIT_REMOVED")
        SafeRegister("PLAYER_REGEN_ENABLED")

        lastPoints = ReadPoints() or 0
        -- backup in case a power event is missed
        C_Timer.NewTicker(0.1, CheckPoints)
    end
end)

-- Battle Shout Notice (WoW Forever)
-- Shows a Battle Shout icon when the buff is missing or about to run out while you're in
-- combat or have a hostile target.
--
-- Forever hides buff details from addons during combat, so the addon keeps its own timer
-- from the moment you shout, and checks the real buff whenever the game allows it (out of
-- combat). No combat log is used.

local ADDON_NAME, ns = ...

---------------------------------------------------------------------------
-- Settings (saved per account, change with /bsr)
---------------------------------------------------------------------------
local defaults = {
    updateNotice = true,  -- "a newer version is out" chat notice (VersionCheck.lua)
    threshold = 10,    -- show the icon when this many seconds or fewer are left
    duration  = 120,   -- Battle Shout length; corrected from the real buff when it can be read
    size      = 52,
    sound     = true,  -- sound when it drops off in combat
    point     = { "CENTER", "CENTER", 0, 160 },
}

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

local SHOUT_NAME = SpellName("Battle Shout") or SpellName(6673) or "Battle Shout"
local SHOUT_ICON = SpellTexture("Battle Shout") or SpellTexture(6673) or "Interface\\Icons\\Ability_Warrior_BattleShout"

-- Returns: expirationTime, duration  if the buff is up and readable
--          false                     if the buff is definitely not there
--          nil                       if the game won't say right now (in combat)
local function ReadShout()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, secret = pcall(C_Secrets.ShouldAurasBeSecret)
        if not ok or secret then return nil end
    end
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then return nil end

    local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", SHOUT_NAME, "HELPFUL")
    if not ok or IsSecret(aura) then return nil end
    if not aura then return false end

    local exp, dur = aura.expirationTime, aura.duration
    if IsSecret(exp) or IsSecret(dur) or not exp then return nil end
    return exp, dur
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------
local frame = CreateFrame("Frame", "BattleShoutReminderFrame", UIParent)
frame:SetFrameStrata("HIGH")
frame:SetClampedToScreen(true)
frame:Hide()

frame.border = frame:CreateTexture(nil, "BACKGROUND")
frame.border:SetPoint("TOPLEFT", -2, 2)
frame.border:SetPoint("BOTTOMRIGHT", 2, -2)
frame.border:SetColorTexture(1, 0.2, 0.1, 1)

frame.icon = frame:CreateTexture(nil, "ARTWORK")
frame.icon:SetAllPoints()
frame.icon:SetTexture(SHOUT_ICON)
frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
frame.text:SetPoint("TOP", frame, "BOTTOM", 0, -4)

frame.timer = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormalHuge")
frame.timer:SetPoint("CENTER")

local pulse = frame:CreateAnimationGroup()
pulse:SetLooping("BOUNCE")
local fade = pulse:CreateAnimation("Alpha")
fade:SetFromAlpha(1)
fade:SetToAlpha(0.35)
fade:SetDuration(0.5)

frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    db.point = { p, rp, x, y }
end)

local function ApplyLayout()
    frame:SetSize(db.size, db.size)
    frame:ClearAllPoints()
    local p = db.point
    frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

---------------------------------------------------------------------------
-- State and logic
---------------------------------------------------------------------------
local expiresAt = 0      -- when we believe the shout runs out (0 = not up)
local unlocked = false
local testMode = false
local wasUp = false

local function Fighting()
    if UnitAffectingCombat("player") then return true end
    return UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target")
end

local function Update()
    if not db then return end

    local exp, dur = ReadShout()
    if exp == false then
        expiresAt = 0
    elseif exp then
        expiresAt = exp
        if dur and dur > 0 then db.duration = dur end
    end

    local remaining = expiresAt - GetTime()
    local up = remaining > 0

    if wasUp and not up and UnitAffectingCombat("player") and db.sound
        and PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
        PlaySound(SOUNDKIT.RAID_WARNING, "SFX")
    end
    wasUp = up

    if unlocked or testMode then
        frame.text:SetText(unlocked and "Drag me, /bsr lock when done" or "Battle Shout!")
        frame.timer:SetText("")
        frame:Show()
        if not pulse:IsPlaying() then pulse:Play() end
        return
    end

    if UnitIsDeadOrGhost("player") or not Fighting() or remaining > db.threshold then
        pulse:Stop()
        frame:Hide()
        return
    end

    if up then
        frame.text:SetText("")
        frame.timer:SetText(math.ceil(remaining))
        pulse:Stop()
        frame:SetAlpha(1)
    else
        frame.text:SetText("Battle Shout!")
        frame.timer:SetText("")
        if not pulse:IsPlaying() then pulse:Play() end
    end
    frame:Show()
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

ev:SetScript("OnEvent", function(_, event, arg1, _, arg3)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        BattleShoutReminderDB = BattleShoutReminderDB or {}
        for k, v in pairs(defaults) do
            if BattleShoutReminderDB[k] == nil then BattleShoutReminderDB[k] = v end
        end
        db = BattleShoutReminderDB
        if ns.StartVersionCheck then ns.StartVersionCheck(db, "Battle Shout Notice") end
        ApplyLayout()
        ns.BuildOptions()

    elseif event == "PLAYER_LOGIN" then
        local _, class = UnitClass("player")
        if class ~= "WARRIOR" then return end -- nothing to do on other classes

        SafeRegister("UNIT_SPELLCAST_SUCCEEDED", "player")
        SafeRegister("UNIT_AURA", "player")
        SafeRegister("PLAYER_REGEN_ENABLED")
        SafeRegister("PLAYER_REGEN_DISABLED")
        SafeRegister("PLAYER_TARGET_CHANGED")
        SafeRegister("PLAYER_DEAD")
        C_Timer.NewTicker(0.25, Update)
        Update()

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- arg3 = spell ID
        if not IsSecret(arg3) and SpellName(arg3) == SHOUT_NAME then
            expiresAt = GetTime() + db.duration
            Update()
        end

    elseif event == "PLAYER_DEAD" then
        expiresAt = 0
        Update()

    else
        Update()
    end
end)

---------------------------------------------------------------------------
-- Slash command: /bsr
---------------------------------------------------------------------------
local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Battle Shout Notice:|r " .. msg)
end

local function SetUnlocked(v)
    unlocked = v
    frame:EnableMouse(v)
end

---------------------------------------------------------------------------
-- Settings page (Options > AddOns) and minimap addon button
---------------------------------------------------------------------------
function ns.BuildOptions()
    ns.CreateOptions({
        title = "Battle Shout Notice",
        updateNotice = true,
        changes = {
            { "1.3.1", "This What's new list" },
            { "1.3.0", "Tells you when a newer version is out" },
            { "1.2.0", "Renamed from Battle Shout Reminder", "/bsn works as well as /bsr" },
        },
        icon = SHOUT_ICON,
        about = "Reminds you when Battle Shout is missing or running out",
        credit = "Created by Miff, supported by Claude",
        slash = "/bsr",
        db = db,
        onChange = function() ApplyLayout(); Update() end,
        controls = {
            { type = "header", label = "Reminder" },
            { type = "range", key = "threshold", label = "Warn with this many seconds left", min = 0, max = 60, step = 5, suffix = "s" },
            { type = "check", key = "sound", label = "Play a sound when it drops off in combat" },
            { type = "header", label = "Icon" },
            { type = "range", key = "size", label = "Icon size", min = 24, max = 120, step = 4 },
            { type = "button", dynamicLabel = function() return unlocked and "Lock position" or "Unlock to move" end,
              label = "Unlock to move", func = function() SetUnlocked(not unlocked) end },
            { type = "button", label = "Reset position", func = function() db.point = { unpack(defaults.point) } end },
            { type = "header", label = "Preview" },
            { type = "button", dynamicLabel = function() return testMode and "Stop test" or "Show test icon" end,
              label = "Show test icon", func = function() testMode = not testMode end },
        },
    })
end

function BattleShoutReminder_OnAddonCompartmentClick()
    if ns.OpenOptions then ns.OpenOptions() end
end

SLASH_BATTLESHOUTREMINDER1 = "/bsr"
SLASH_BATTLESHOUTREMINDER2 = "/bsn"
SlashCmdList.BATTLESHOUTREMINDER = function(msg)
    local cmd, val = (msg or ""):lower():match("^(%S*)%s*(.-)$")
    local n = tonumber(val)

    if cmd == "" then
        ns.OpenOptions()
        return
    elseif cmd == "unlock" then
        SetUnlocked(true)
        Print("drag the icon where you want it, then /bsr lock")
    elseif cmd == "lock" then
        SetUnlocked(false)
        Print("locked")
    elseif cmd == "test" then
        testMode = not testMode
        Print("test mode " .. (testMode and "on" or "off"))
    elseif cmd == "time" and n then
        db.threshold = n
        Print("shows when " .. n .. " seconds or fewer are left")
    elseif cmd == "size" and n then
        db.size = n
        ApplyLayout()
        Print("icon size " .. n)
    elseif cmd == "sound" then
        db.sound = not db.sound
        Print("sound " .. (db.sound and "on" or "off"))
    elseif cmd == "reset" then
        db.point = { unpack(defaults.point) }
        ApplyLayout()
        Print("position reset")
    else
        Print("v" .. ns.version .. " commands (or just /bsr for the settings page):")
        Print("/bsr unlock, /bsr lock - move the icon")
        Print("/bsr test - show the icon to check it")
        Print("/bsr time <n> - warn when this many seconds are left (now " .. db.threshold .. ")")
        Print("/bsr size <n> - icon size (now " .. db.size .. ")")
        Print("/bsr sound - sound when it drops off in combat (now " .. (db.sound and "on" or "off") .. ")")
        Print("/bsr reset - put the icon back in the default spot")
    end
    Update()
    if ns.RefreshOptions then ns.RefreshOptions() end
end

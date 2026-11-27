-- Kill Clock (WoW Forever)
-- A countdown beside the target frame's portrait: roughly how long until your target dies at the
-- rate it's losing health, so you can time cooldowns and executes.
--
-- The estimate is the classic one: if a mob has lost (start - now) of its health in
-- t seconds, the rest takes t * now / (start - now) seconds at the same pace.
--
-- WoW Forever hides enemy health from addons in combat: they can show it but can't do
-- maths with it. So Kill Clock never reads the health. It builds a "curve" (a lookup
-- the game provides for exactly this) that turns "health left" into "time left" for
-- the seconds elapsed so far, rebuilds it twice a second, and lets the game apply it to
-- the hidden health and put the result on screen.
--
-- A second, smaller line can show how long until the target reaches execute range (20%
-- by default), and a second clock can sit beside the focus frame.

local ADDON_NAME, ns = ...

local defaults = {
    updateNotice = true,
    size      = 22,
    outline   = true,
    colour    = "white",   -- a preset name, or "custom"
    custom    = { 1, 1, 1 },
    label     = false,     -- "Dies in 1:24" instead of "1:24"
    elites    = false,     -- only elites, rares and bosses
    minTime   = 2,         -- seconds of damage before the first estimate
    pos       = nil,       -- nil = just right of the target frame's portrait
    -- execute = true/false, set on first load from your class (warriors and paladins on)
    executeAt = 20,        -- the execute line, in % health
    focus     = false,     -- a second clock beside the focus frame
    focusPos  = nil,
}

local COLOURS = {
    white  = { 1, 1, 1 },
    yellow = { 1, 0.82, 0 },
    orange = { 1, 0.5, 0 },
    red    = { 1, 0.25, 0.25 },
    green  = { 0.3, 1, 0.3 },
    blue   = { 0.35, 0.65, 1 },
    purple = { 0.75, 0.45, 1 },
    pink   = { 1, 0.45, 0.8 },
}
local COLOUR_ORDER = { "white", "yellow", "orange", "red", "green", "blue", "purple", "pink", "custom" }

local db
local unlocked, testMode, debugMode = false, false, false
local starts = {}        -- [unit token] = { t = when it started losing health, f0 = health share then }
local combatStart        -- when you entered combat, if you had your target before the pull
local inCombat = false

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8000Kill Clock:|r " .. msg)
end

local function Debug(msg)
    if debugMode then DEFAULT_CHAT_FRAME:AddMessage("|cffff8000Kill Clock debug:|r " .. msg) end
end

local function Bool(fn, ...)
    if not fn then return nil end
    local ok, v = pcall(fn, ...)
    if ok and not IsSecret(v) then return v end
    return nil
end

-- the target's health as a share (0-1) when the game lets us read it
local function ReadShare(unit)
    if not UnitHealthPercent then return nil end
    local ok, v = pcall(UnitHealthPercent, unit, true)
    if ok and not IsSecret(v) and type(v) == "number" then
        if v > 1 then v = v / 100 end
        return v
    end
end

---------------------------------------------------------------------------
-- The curves: "health left" -> minutes and seconds left
---------------------------------------------------------------------------
-- Sample times (seconds left) the curves are built from: every second for the first two
-- minutes, every 5 up to 10 minutes, then every minute up to 20. The game allows 256
-- points a curve.
local SAMPLES = {}
for T = 0, 119 do SAMPLES[#SAMPLES + 1] = T end
for T = 120, 595, 5 do SAMPLES[#SAMPLES + 1] = T end
for T = 600, 1200, 60 do SAMPLES[#SAMPLES + 1] = T end
ns.SAMPLES = SAMPLES

local function StepType(c)
    -- step: hold each value until the next point, so minutes and seconds always agree
    if c.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then
        pcall(c.SetType, c, Enum.LuaCurveType.Step)
    end
    return c
end

local function NewCurve()
    if not (C_CurveUtil and C_CurveUtil.CreateCurve) then return nil end
    local ok, c = pcall(C_CurveUtil.CreateCurve)
    if not ok or not c then return nil end
    return StepType(c)
end

local function NewColourCurve()
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
    local ok, c = pcall(C_CurveUtil.CreateColorCurve)
    if not ok or not c then return nil end
    return StepType(c)
end

local function Clear(c)
    if c.ClearPoints then c:ClearPoints() return c end
    return NewCurve()
end

---------------------------------------------------------------------------
-- A clock: one for the target, and optionally one for your focus
---------------------------------------------------------------------------
local clocks = {}

local function MakeClock(unit, frameName)
    local c = { unit = unit }
    local f = CreateFrame("Frame", frameName, UIParent)
    f:SetSize(90, 30)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:Hide()
    c.frame = f
    c.text = f:CreateFontString(nil, "OVERLAY")
    c.text:SetPoint("CENTER")
    c.exec = f:CreateFontString(nil, "OVERLAY")
    c.exec:SetPoint("TOP", c.text, "BOTTOM", 0, -1)
    c.exec:Hide()
    c.mover = f:CreateTexture(nil, "BACKGROUND")
    c.mover:SetAllPoints()
    c.mover:SetColorTexture(1, 0.5, 0, 0.35)
    c.mover:Hide()
    f:SetScript("OnMouseDown", function(self, button)
        if unlocked and button == "LeftButton" then self:StartMoving() end
    end)
    f:SetScript("OnMouseUp", function(self)
        if not unlocked then return end
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        db[c.posKey] = { point, rel, x, y }
    end)
    clocks[#clocks + 1] = c
    return c
end

local targetClock = MakeClock("target", "KillClockFrame")
targetClock.posKey, targetClock.parentName = "pos", "TargetFrame"
local focusClock = MakeClock("focus", "KillClockFocusFrame")
focusClock.posKey, focusClock.parentName = "focusPos", "FocusFrame"
ns.text = targetClock.text
ns.execText = targetClock.exec
ns.focusText = focusClock.text

-- e = seconds since the unit started losing health, f0 = its health share then
local function BuildCurves(c, e, f0)
    c.minC = c.minC or NewCurve()
    c.secC = c.secC or NewCurve()
    if not c.minC or not c.secC then return false end
    c.minC, c.secC = Clear(c.minC), Clear(c.secC)
    for _, T in ipairs(SAMPLES) do
        -- the health share at which T seconds would be left: f = f0 * T / (e + T)
        local x = f0 * T / (e + T)
        c.minC:AddPoint(x, math.floor(T / 60))
        c.secC:AddPoint(x, T % 60)
    end

    -- time until it reaches the execute line k: f = (T * f0 + k * e) / (e + T)
    c.execOK = false
    local k = (db.executeAt or 20) / 100
    if db.execute and f0 > k + 0.01 then
        c.exMin = c.exMin or NewCurve()
        c.exSec = c.exSec or NewCurve()
        if c.exMin and c.exSec then
            c.exMin, c.exSec = Clear(c.exMin), Clear(c.exSec)
            c.exMin:AddPoint(0, 0)
            c.exSec:AddPoint(0, 0)
            for _, T in ipairs(SAMPLES) do
                local x = (T * f0 + k * e) / (e + T)
                c.exMin:AddPoint(x, math.floor(T / 60))
                c.exSec:AddPoint(x, T % 60)
            end
            c.execOK = true
            -- red once it's in execute range, where the game lets addons colour by hidden health
            c.exColour = c.exColour or NewColourCurve()
            if c.exColour and c.exColour.AddPoint then
                if c.exColour.ClearPoints then c.exColour:ClearPoints() end
                local r, g, b = ns.Colour()
                pcall(c.exColour.AddPoint, c.exColour, 0, CreateColor(1, 0.2, 0.2, 1))
                pcall(c.exColour.AddPoint, c.exColour, k + 0.0005, CreateColor(r, g, b, 1))
            end
        end
    end
    c.builtFor, c.builtF0 = e, f0
    return true
end
ns.BuildCurves = function(e, f0) return BuildCurves(targetClock, e, f0) end
ns.Curves = function() return targetClock.minC, targetClock.secC, targetClock.exMin, targetClock.exSec end

-- the unit frame's portrait (the round picture), on the clients that name it
local function Portrait(frame)
    if not frame then return nil end
    local container = frame.TargetFrameContainer
    local p = (type(container) == "table" and container.Portrait) or frame.portrait
    if type(p) == "table" and p.GetObjectType then return p end
end

local function Place()
    for _, c in ipairs(clocks) do
        local f = c.frame
        f:ClearAllPoints()
        local p = db[c.posKey]
        local parent = _G[c.parentName]
        if p then
            f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
        elseif Portrait(parent) then
            -- just right of the portrait, level with it
            f:SetPoint("LEFT", Portrait(parent), "RIGHT", 2, 0)
        elseif parent then
            f:SetPoint("LEFT", parent, "RIGHT", 2, 0)
        else
            f:SetPoint("CENTER", UIParent, "CENTER", 0, c.unit == "focus" and 150 or 200)
        end
    end
end
ns.Place = Place

local function Colour()
    if db.colour == "custom" then return unpack(db.custom) end
    local col = COLOURS[db.colour] or COLOURS.white
    return col[1], col[2], col[3]
end
ns.Colour = Colour

local function Style()
    local font = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    for _, c in ipairs(clocks) do
        local ok = pcall(c.text.SetFont, c.text, font, db.size, db.outline and "OUTLINE" or "")
        if not ok or not c.text:GetFont() then c.text:SetFontObject("GameFontNormalLarge") end
        local small = math.max(9, math.floor(db.size * 0.6 + 0.5))
        local ok2 = pcall(c.exec.SetFont, c.exec, font, small, db.outline and "OUTLINE" or "")
        if not ok2 or not c.exec:GetFont() then c.exec:SetFontObject("GameFontNormalSmall") end
        c.text:SetTextColor(Colour())
        c.exec:SetTextColor(Colour())
        c.frame:SetSize(math.max(60, db.size * (db.label and 7 or 4)), db.size + 10)
        c.builtFor = nil
    end
end
ns.Style = Style

local function Fmt(main)
    if main then return db.label and "Dies in %d:%02d" or "%d:%02d" end
    return (db.executeAt or 20) .. "%% in %d:%02d"
end

local function Show(c, ...)
    if c.text.SetFormattedText then
        c.text:SetFormattedText(Fmt(true), ...)
    else
        c.text:SetText(string.format(Fmt(true), ...))
    end
    c.frame:Show()
end

local function ShowExec(c, m, s)
    if m == nil then c.exec:Hide() return end
    if c.exec.SetFormattedText then
        c.exec:SetFormattedText(Fmt(false), m, s)
    else
        c.exec:SetText(string.format(Fmt(false), m, s))
    end
    c.exec:Show()
end

local function Enabled(c)
    return c.unit == "target" or db.focus
end

local function Hide(c)
    if unlocked and Enabled(c) then
        c.text:SetText(db.label and "Dies in 1:24" or "1:24")
        if db.execute then ShowExec(c, 0, 52) else c.exec:Hide() end
        c.frame:Show()
        return
    end
    c.frame:Hide()
end

---------------------------------------------------------------------------
-- When did the unit start losing health?
---------------------------------------------------------------------------
local function PlateToken(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not ok or not plate then return nil end
    local token = plate.namePlateUnitToken or (type(plate.UnitFrame) == "table" and plate.UnitFrame.unit)
    if type(token) == "string" and not IsSecret(token) then return token end
end

local combatStarts = {}  -- [unit] = start at the pull, if you had it targeted / focused before

local function StartFor(unit)
    -- its nameplate has been watched since it appeared, so that start is the best one
    local token = PlateToken(unit)
    if token and starts[token] then return starts[token], "nameplate" end
    if starts[unit] then return starts[unit], "health" end
    if combatStarts[unit] then return combatStarts[unit], "pull" end
    if combatStart and unit == "target" then return combatStart, "pull" end
end

local function Wanted(unit)
    if not UnitExists(unit) then return false end
    if Bool(UnitCanAttack, "player", unit) == false then return false end
    if Bool(UnitIsDeadOrGhost, unit) then return false end
    if db.elites then
        local cl = Bool(UnitClassification, unit)
        if cl == "normal" or cl == "trivial" or cl == "minus" then return false end
    end
    return true
end

local lastDebug = 0
local function UpdateClock(c)
    local unit = c.unit
    if not Enabled(c) then c.frame:Hide() return end
    if testMode then
        Show(c, 1, 24)
        if db.execute then ShowExec(c, 0, 52) else c.exec:Hide() end
        return
    end
    -- the focus clock stays out of the way when your focus is also your target
    if unit == "focus" and UnitIsUnit and Bool(UnitIsUnit, "focus", "target") then Hide(c) return end
    if not inCombat or not Wanted(unit) then Hide(c) return end
    local st, source = StartFor(unit)
    if not st then Hide(c) return end
    local e = GetTime() - st.t
    if e < db.minTime then Hide(c) return end

    if not c.builtFor or math.abs(e - c.builtFor) >= 0.5 or c.builtF0 ~= st.f0 then
        if not BuildCurves(c, e, st.f0) then
            -- no curves on this client: work it out directly if the health can be read
            local f = ReadShare(unit)
            if not f or f >= st.f0 then Hide(c) return end
            local T = math.floor(e * f / (st.f0 - f))
            if T > 1200 then T = 1200 end
            Show(c, math.floor(T / 60), T % 60)
            local k = (db.executeAt or 20) / 100
            if db.execute and st.f0 > k + 0.01 then
                local TE = math.max(0, math.floor(e * (f - k) / (st.f0 - f)))
                if TE > 1200 then TE = 1200 end
                ShowExec(c, math.floor(TE / 60), TE % 60)
                if f <= k then c.exec:SetTextColor(1, 0.2, 0.2) else c.exec:SetTextColor(Colour()) end
            else
                c.exec:Hide()
            end
            return
        end
    end
    local okM, m = pcall(UnitHealthPercent, unit, true, c.minC)
    local okS, s = pcall(UnitHealthPercent, unit, true, c.secC)
    if not okM or not okS or (not IsSecret(m) and m == nil) or (not IsSecret(s) and s == nil) then Hide(c) return end
    Show(c, m, s)

    local colourWorks
    if c.execOK then
        local okEM, em = pcall(UnitHealthPercent, unit, true, c.exMin)
        local okES, es = pcall(UnitHealthPercent, unit, true, c.exSec)
        if okEM and okES and (IsSecret(em) or em ~= nil) then
            ShowExec(c, em, es)
            c.exec:SetTextColor(Colour())
            if c.exColour then
                local okC, col = pcall(UnitHealthPercent, unit, true, c.exColour)
                if okC and type(col) == "table" and col.GetRGB then
                    colourWorks = pcall(function() c.exec:SetTextColor(col:GetRGB()) end)
                end
            end
        else
            c.exec:Hide()
        end
    else
        c.exec:Hide()
    end

    if debugMode and GetTime() - lastDebug > 2 then
        lastDebug = GetTime()
        Debug(("%s: timing from %s, %.1f s of damage, start health %.0f%%, health %s, execute line %s%s"):format(
            unit, source, e, st.f0 * 100, IsSecret(m) and "hidden (curve used)" or "readable",
            c.execOK and "on" or "off", c.execOK and (colourWorks and " (turns red in range)" or " (no red in range)") or ""))
    end
end

local function Update()
    if not db then return end
    for _, c in ipairs(clocks) do UpdateClock(c) end
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

local function Begin(unit)
    if starts[unit] then return end
    starts[unit] = { t = GetTime(), f0 = 1 }
    local f = ReadShare(unit)
    if f and f > 0 and f <= 1 then starts[unit].f0 = math.min(1, f + 0.005) end
    Debug(("%s started losing health"):format(unit))
end

local function PullStart(unit)
    if UnitExists(unit) then return { t = GetTime(), f0 = ReadShare(unit) or 1 } end
end

ev:SetScript("OnEvent", function(_, event, unit)
    if event == "ADDON_LOADED" then
        if unit ~= ADDON_NAME then return end
        KillClockDB = KillClockDB or {}
        for k, v in pairs(defaults) do
            if KillClockDB[k] == nil then
                if type(v) == "table" then
                    local copy = {}
                    for i, x in ipairs(v) do copy[i] = x end
                    KillClockDB[k] = copy
                else
                    KillClockDB[k] = v
                end
            end
        end
        db = KillClockDB
        ns.db = db
        -- the execute line starts on for classes with an execute (Execute, Hammer of Wrath)
        if db.execute == nil then
            local _, class = UnitClass("player")
            db.execute = (class == "WARRIOR" or class == "PALADIN")
        end
        Style()
        Place()
        if ns.StartVersionCheck then ns.StartVersionCheck(db, "Kill Clock") end
        ns.BuildOptions()
        inCombat = (InCombatLockdown and InCombatLockdown()) or false

        SafeRegister("PLAYER_ENTERING_WORLD")
        SafeRegister("PLAYER_TARGET_CHANGED")
        SafeRegister("PLAYER_FOCUS_CHANGED")
        SafeRegister("PLAYER_REGEN_DISABLED")
        SafeRegister("PLAYER_REGEN_ENABLED")
        SafeRegister("NAME_PLATE_UNIT_REMOVED")
        SafeRegister("UNIT_HEALTH")
        SafeRegister("ENCOUNTER_START")
        if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(0.2, Update) end
        return
    end

    if event == "UNIT_HEALTH" then
        if not inCombat or type(unit) ~= "string" or IsSecret(unit) then return end
        if unit == "target" or unit == "focus" or unit:match("^nameplate%d+$") then Begin(unit) end
    elseif event == "PLAYER_TARGET_CHANGED" then
        starts.target = nil
        targetClock.builtFor = nil
        -- a target picked before the pull counts from the pull
        if not inCombat then combatStart = nil; combatStarts.target = nil end
        Update()
    elseif event == "PLAYER_FOCUS_CHANGED" then
        starts.focus = nil
        focusClock.builtFor = nil
        if not inCombat then combatStarts.focus = nil end
        Update()
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if type(unit) == "string" and not IsSecret(unit) then starts[unit] = nil end
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        combatStart = PullStart("target")
        combatStarts.target = combatStart
        combatStarts.focus = PullStart("focus")
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        wipe(starts)
        wipe(combatStarts)
        combatStart = nil
        for _, c in ipairs(clocks) do c.builtFor = nil end
        Update()
    elseif event == "ENCOUNTER_START" then
        -- a boss starts at full health when the encounter starts
        combatStart = { t = GetTime(), f0 = 1 }
        combatStarts.target = combatStart
        combatStarts.focus = { t = GetTime(), f0 = 1 }
    elseif event == "PLAYER_ENTERING_WORLD" then
        inCombat = (InCombatLockdown and InCombatLockdown()) or false
        wipe(starts)
        Place()
    end
end)

---------------------------------------------------------------------------
-- Settings page and slash command
---------------------------------------------------------------------------
local function SetUnlocked(on)
    unlocked = on
    for _, c in ipairs(clocks) do
        c.frame:EnableMouse(on)
        c.mover:SetShown(on and Enabled(c))
    end
    Update()
end

local function SetTest(on)
    testMode = on
    Update()
end
ns.SetTest = SetTest

local function PickColour()
    if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then
        Print("the colour picker isn't available here; use /kclock colour <name>.")
        return
    end
    local r, g, b = unpack(db.custom)
    ColorPickerFrame:SetupColorPickerAndShow({
        r = r, g = g, b = b, hasOpacity = false,
        swatchFunc = function()
            local nr, ng, nb = ColorPickerFrame:GetColorRGB()
            db.custom = { nr, ng, nb }
            db.colour = "custom"
            Style()
            Update()
            if ns.RefreshOptions then ns.RefreshOptions() end
        end,
        cancelFunc = function(prev)
            if prev then db.custom = { prev.r, prev.g, prev.b } end
            Style()
            if ns.RefreshOptions then ns.RefreshOptions() end
        end,
    })
end

function ns.BuildOptions()
    ns.CreateOptions({
        title = "Kill Clock",
        updateNotice = true,
        changes = {
            { "1.1.1", "Settings page: long labels no longer run into their buttons" },
            { "1.1.0", "A second line: how long until the target reaches execute range (20%, or your own)",
                       "Optional second clock beside the focus frame" },
            { "1.0.1", "Now starts just right of the target frame's portrait (drag it anywhere as before)" },
            { "1.0.0", "First version: how long until your target dies, above the target frame",
                       "Movable, with a choice of colours or your own",
                       "Works with Forever's hidden enemy health" },
        },
        icon = "Interface\\Icons\\Spell_Holy_BorrowedTime",
        about = "How long until your target dies",
        credit = "Created by Miff, supported by Claude",
        slash = "/kclock",
        db = db,
        onChange = function() Style(); SetUnlocked(unlocked); Update() end,
        controls = {
            { type = "header", label = "Look" },
            { type = "range", key = "size", label = "Text size", min = 10, max = 48, step = 1 },
            { type = "choice", key = "colour", label = "Colour", values = COLOUR_ORDER },
            { type = "button", label = "Pick a custom colour", func = PickColour },
            { type = "check", key = "outline", label = "Outline the text" },
            { type = "check", key = "label", label = "Show \"Dies in\" before the time" },
            { type = "header", label = "Position" },
            { type = "button", label = "Move",
              dynamicLabel = function() return unlocked and "Lock" or "Move" end,
              func = function() SetUnlocked(not unlocked) end },
            { type = "button", label = "Back beside the target frame", func = function() db.pos = nil; db.focusPos = nil; Place() end },
            { type = "button", label = "Test",
              dynamicLabel = function() return testMode and "Stop the test" or "Test" end,
              func = function() SetTest(not testMode) end },
            { type = "header", label = "Execute range" },
            { type = "check", key = "execute", label = "Show how long until the target reaches execute range (a smaller line underneath)" },
            { type = "range", key = "executeAt", label = "Execute range starts at", min = 5, max = 50, step = 5, suffix = "%" },
            { type = "header", label = "Focus" },
            { type = "check", key = "focus", label = "A second clock beside the focus frame" },
            { type = "header", label = "When to show it" },
            { type = "check", key = "elites", label = "Only on elites, rares and bosses" },
            { type = "range", key = "minTime", label = "Seconds of damage before the first estimate", min = 1, max = 10, step = 1 },
            { type = "header", label = "How it works on WoW Forever" },
            { type = "info", height = 96, lines = function()
                return "|cff999999The time is how long your target will take to die if it keeps losing health at the pace it has so far. "
                    .. "Forever hides enemy health from addons in combat, so Kill Clock never reads it: it hands the game a lookup "
                    .. "from \"health left\" to \"time left\" and the game shows the answer. Keep enemy nameplates on so it knows when "
                    .. "each mob started taking damage, even if you switch targets mid-fight.|r" end },
        },
    })
end

function KillClock_OnAddonCompartmentClick()
    if ns.OpenOptions then ns.OpenOptions() end
end

SLASH_KILLCLOCK1 = "/kclock"
SLASH_KILLCLOCK2 = "/killclock"
SlashCmdList.KILLCLOCK = function(msg)
    local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    rest = rest:lower()
    if cmd == "" then
        ns.OpenOptions()
    elseif cmd == "test" then
        SetTest(not testMode)
        Print(testMode and "test on. /kclock test again to stop." or "test off.")
    elseif cmd == "move" or cmd == "unlock" then
        SetUnlocked(true)
        Print("drag the orange box to move the clock. /kclock lock when done.")
    elseif cmd == "lock" then
        SetUnlocked(false)
        Print("clock locked.")
    elseif cmd == "reset" then
        db.pos = nil
        db.focusPos = nil
        Place()
        Print("clock moved back beside the target frame.")
    elseif cmd == "size" and tonumber(rest) then
        db.size = math.max(10, math.min(48, tonumber(rest)))
        Style()
        Print("text size " .. db.size .. ".")
    elseif (cmd == "colour" or cmd == "color") and (COLOURS[rest] or rest == "custom") then
        db.colour = rest
        Style()
        Print("colour " .. rest .. ".")
    elseif cmd == "colour" or cmd == "color" then
        PickColour()
    elseif cmd == "execute" then
        local n = tonumber((rest:gsub("%%", "")))
        if n then
            db.executeAt = math.max(5, math.min(50, n))
            db.execute = true
        else
            db.execute = not db.execute
        end
        Style(); Update()
        Print(db.execute and ("execute line on, at " .. db.executeAt .. "%.") or "execute line off.")
    elseif cmd == "focus" then
        db.focus = not db.focus
        SetUnlocked(unlocked); Update()
        Print(db.focus and "focus clock on." or "focus clock off.")
    elseif cmd == "debug" then
        debugMode = not debugMode
        Print(debugMode and "debug on: prints what the clock is timing from. /kclock debug again to stop." or "debug off.")
        if debugMode then
            Print(("curves %s, health readable now: %s"):format(
                (C_CurveUtil and C_CurveUtil.CreateCurve) and "available" or "missing",
                tostring(ReadShare("target") ~= nil)))
        end
    else
        Print("/kclock - settings")
        Print("/kclock test - show a sample time")
        Print("/kclock move | lock - move the clock")
        Print("/kclock reset - back beside the target frame")
        Print("/kclock size <n> - text size")
        Print("/kclock execute - the execute range line on or off; /kclock execute <n> sets it to n%")
        Print("/kclock focus - a second clock beside the focus frame")
        Print("/kclock colour <white|yellow|orange|red|green|blue|purple|pink> - or no name for the colour picker")
        Print("/kclock debug - print what it's timing from")
    end
end

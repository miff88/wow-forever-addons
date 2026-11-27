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

local minCurve, secCurve
local builtFor, builtF0

local function NewCurve()
    if not (C_CurveUtil and C_CurveUtil.CreateCurve) then return nil end
    local ok, c = pcall(C_CurveUtil.CreateCurve)
    if not ok or not c then return nil end
    -- step: hold each value until the next point, so minutes and seconds always agree
    if c.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then
        pcall(c.SetType, c, Enum.LuaCurveType.Step)
    end
    return c
end

-- e = seconds since the target started losing health, f0 = its health share then
local function BuildCurves(e, f0)
    minCurve = minCurve or NewCurve()
    secCurve = secCurve or NewCurve()
    if not minCurve or not secCurve then return false end
    if minCurve.ClearPoints then minCurve:ClearPoints() else minCurve = NewCurve() end
    if secCurve.ClearPoints then secCurve:ClearPoints() else secCurve = NewCurve() end
    for _, T in ipairs(SAMPLES) do
        -- the health share at which T seconds would be left: f = f0 * T / (e + T)
        local x = f0 * T / (e + T)
        minCurve:AddPoint(x, math.floor(T / 60))
        secCurve:AddPoint(x, T % 60)
    end
    builtFor, builtF0 = e, f0
    return true
end
ns.BuildCurves = BuildCurves
ns.Curves = function() return minCurve, secCurve end

---------------------------------------------------------------------------
-- The clock
---------------------------------------------------------------------------
local clock = CreateFrame("Frame", "KillClockFrame", UIParent)
clock:SetSize(90, 30)
clock:SetFrameStrata("MEDIUM")
clock:SetClampedToScreen(true)
clock:SetMovable(true)
clock:Hide()

local text = clock:CreateFontString(nil, "OVERLAY")
text:SetPoint("CENTER")
ns.text = text

local mover = clock:CreateTexture(nil, "BACKGROUND")
mover:SetAllPoints()
mover:SetColorTexture(1, 0.5, 0, 0.35)
mover:Hide()

clock:SetScript("OnMouseDown", function(self, button)
    if unlocked and button == "LeftButton" then self:StartMoving() end
end)
clock:SetScript("OnMouseUp", function(self)
    if not unlocked then return end
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    db.pos = { point, rel, x, y }
end)

-- the target frame's portrait (the round picture), on the clients that name it
local function TargetPortrait()
    if not TargetFrame then return nil end
    local container = TargetFrame.TargetFrameContainer
    local p = (type(container) == "table" and container.Portrait) or TargetFrame.portrait
    if type(p) == "table" and p.GetObjectType then return p end
end

local function Place()
    clock:ClearAllPoints()
    local p = db.pos
    if p then
        clock:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    elseif TargetPortrait() then
        -- just right of the portrait, level with it
        clock:SetPoint("LEFT", TargetPortrait(), "RIGHT", 2, 0)
    elseif TargetFrame then
        clock:SetPoint("LEFT", TargetFrame, "RIGHT", 2, 0)
    else
        clock:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    end
end
ns.Place = Place

local function Colour()
    if db.colour == "custom" then return unpack(db.custom) end
    local c = COLOURS[db.colour] or COLOURS.white
    return c[1], c[2], c[3]
end

local function Style()
    local font = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    local ok = pcall(text.SetFont, text, font, db.size, db.outline and "OUTLINE" or "")
    if not ok or not text:GetFont() then text:SetFontObject("GameFontNormalLarge") end
    text:SetTextColor(Colour())
    clock:SetSize(math.max(60, db.size * (db.label and 7 or 4)), db.size + 10)
end
ns.Style = Style

local function Show(fmt, ...)
    if text.SetFormattedText then
        text:SetFormattedText(fmt, ...)
    else
        text:SetText(string.format(fmt, ...))
    end
    clock:Show()
end

local function Hide()
    if unlocked then
        text:SetText(db.label and "Dies in 1:24" or "1:24")
        clock:Show()
        return
    end
    clock:Hide()
end

---------------------------------------------------------------------------
-- When did the target start losing health?
---------------------------------------------------------------------------
local function PlateToken(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not ok or not plate then return nil end
    local token = plate.namePlateUnitToken or (type(plate.UnitFrame) == "table" and plate.UnitFrame.unit)
    if type(token) == "string" and not IsSecret(token) then return token end
end

local function StartFor(unit)
    -- its nameplate has been watched since it appeared, so that start is the best one
    local token = PlateToken(unit)
    if token and starts[token] then return starts[token], "nameplate" end
    if starts[unit] then return starts[unit], "health" end
    if combatStart then return combatStart, "pull" end
end

local function Wanted(unit)
    if not UnitExists(unit) then return false end
    if Bool(UnitCanAttack, "player", unit) == false then return false end
    if Bool(UnitIsDeadOrGhost, unit) then return false end
    if db.elites then
        local c = Bool(UnitClassification, unit)
        if c == "normal" or c == "trivial" or c == "minus" then return false end
    end
    return true
end

local lastDebug = 0
local function Update()
    if not db then return end
    if testMode then
        Show(db.label and "Dies in %d:%02d" or "%d:%02d", 1, 24)
        return
    end
    local unit = "target"
    if not inCombat or not Wanted(unit) then Hide() return end
    local st, source = StartFor(unit)
    if not st then Hide() return end
    local e = GetTime() - st.t
    if e < db.minTime then Hide() return end

    if not builtFor or math.abs(e - builtFor) >= 0.5 or builtF0 ~= st.f0 then
        if not BuildCurves(e, st.f0) then
            -- no curves on this client: work it out directly if the health can be read
            local f = ReadShare(unit)
            if not f or f >= st.f0 then Hide() return end
            local T = math.floor(e * f / (st.f0 - f))
            if T > 1200 then T = 1200 end
            Show(db.label and "Dies in %d:%02d" or "%d:%02d", math.floor(T / 60), T % 60)
            return
        end
    end
    local okM, m = pcall(UnitHealthPercent, unit, true, minCurve)
    local okS, s = pcall(UnitHealthPercent, unit, true, secCurve)
    if not okM or not okS or (not IsSecret(m) and m == nil) or (not IsSecret(s) and s == nil) then Hide() return end
    Show(db.label and "Dies in %d:%02d" or "%d:%02d", m, s)

    if debugMode and GetTime() - lastDebug > 2 then
        lastDebug = GetTime()
        Debug(("timing from %s, %.1f s of damage, start health %.0f%%, health %s"):format(
            source, e, st.f0 * 100, IsSecret(m) and "hidden (curve used)" or "readable"))
    end
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
        Style()
        Place()
        if ns.StartVersionCheck then ns.StartVersionCheck(db, "Kill Clock") end
        ns.BuildOptions()
        inCombat = (InCombatLockdown and InCombatLockdown()) or false

        SafeRegister("PLAYER_ENTERING_WORLD")
        SafeRegister("PLAYER_TARGET_CHANGED")
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
        if unit == "target" or unit:match("^nameplate%d+$") then Begin(unit) end
    elseif event == "PLAYER_TARGET_CHANGED" then
        starts.target = nil
        builtFor = nil
        -- a target picked before the pull counts from the pull
        if not inCombat then combatStart = nil end
        Update()
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if type(unit) == "string" and not IsSecret(unit) then starts[unit] = nil end
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        combatStart = UnitExists("target") and { t = GetTime(), f0 = ReadShare("target") or 1 } or nil
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        wipe(starts)
        combatStart = nil
        builtFor = nil
        Update()
    elseif event == "ENCOUNTER_START" then
        -- a boss starts at full health when the encounter starts
        combatStart = { t = GetTime(), f0 = 1 }
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
    clock:EnableMouse(on)
    mover:SetShown(on)
    Update()
    if on then Hide() end
end

local function SetTest(on)
    testMode = on
    Update()
    if not on and not unlocked then clock:Hide() end
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
        onChange = function() Style(); Update() end,
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
            { type = "button", label = "Back beside the target frame", func = function() db.pos = nil; Place() end },
            { type = "button", label = "Test",
              dynamicLabel = function() return testMode and "Stop the test" or "Test" end,
              func = function() SetTest(not testMode) end },
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
        Print("/kclock colour <white|yellow|orange|red|green|blue|purple|pink> - or no name for the colour picker")
        Print("/kclock debug - print what it's timing from")
    end
end

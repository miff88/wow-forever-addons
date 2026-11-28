-- Proc City (WoW Forever)
-- The abilities that light up for a few seconds in a fight, as a movable row of icons
-- with the time left on each, and a glow on their action buttons:
--   Warrior  Overpower (also marked on the nameplate of the mob that dodged you),
--            Revenge, Victory Rush
--   Rogue    Riposte
--   Hunter   Counterattack, Mongoose Bite
--
-- Buff procs (Flurry, Crusader, Clearcasting...) are left to the game's own Cooldown
-- Manager: WoW Forever hides your buffs from addons in combat, open world included, so an
-- addon can't show them mid-fight. These abilities come from the game saying they can be
-- cast, which it still tells addons in combat.

local ADDON_NAME, ns = ...

local defaults = {
    updateNotice = true,
    grow    = "right",  -- icons grow to the right or left of the anchor
    size    = 40,
    spacing = 4,
    timer   = true,     -- seconds left on the icon
    swipe   = true,     -- clock-style sweep as it runs out
    sound   = false,
    cats    = { reactive = true },
    off     = {},       -- [key] = true for abilities you've turned off
    pins    = {},       -- keys always shown, greyed out while they're down, in this order
    pinsInCombat = true,-- ...only greyed out in combat (out of combat they hide)
    pinAlpha = 50,      -- how faint a pinned icon is while it's down
    glowButtons = true, -- light the matching action buttons
    -- Overpower on the nameplate of the mob that dodged you (Overpower.lua)
    oppPlates = true,
    oppSize   = 30,
    oppOffset = 18,     -- above the health bar
    oppWindow = 5,      -- seconds Overpower stays usable after a dodge
    oppSound  = true,   -- sound when a mob dodges you
    oppPop    = true,
    oppPulse  = true,
    pos     = nil,
}

-- settings from 1.x that tracked buffs, cleared out once
local RETIRED = { "learned", "learnedIDs", "learnedIcons", "procIcons", "glowDouble" }

local db
local unlocked, testMode, debugMode = false, false, false
local playerClass

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8000Proc City:|r " .. msg)
end

local function SpellIcon(id)
    if not id or IsSecret(id) then return nil end
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, id)
        if ok and tex and not IsSecret(tex) then return tex end
    end
end

local function KnowsAny(ids)
    if not IsPlayerSpell then return false end
    for _, id in ipairs(ids or {}) do
        local ok, known = pcall(IsPlayerSpell, id)
        if ok and not IsSecret(known) and known then return true end
    end
    return false
end

local byKey = {}
for _, p in ipairs(ns.PROCS) do byKey[p.key] = p end

local function BuildIcons()
    for _, p in ipairs(ns.PROCS) do
        local icon
        for _, id in ipairs(p.ids) do
            if KnowsAny({ id }) then icon = SpellIcon(id) break end
        end
        p.icon = icon or SpellIcon(p.ids[1]) or p.icon or 134400
    end
end

local function Wanted(p)
    if not db then return false end
    if p.class and not p.class[playerClass] then return false end
    if not db.cats[p.cat] then return false end
    return not db.off[p.key]
end

---------------------------------------------------------------------------
-- What's up right now
---------------------------------------------------------------------------
-- active[key] = { proc, icon, started, expires, duration, count, stacks, source }
local active, order = {}, {}
local Layout -- defined below

local function PlayProcSound()
    if db.sound and PlaySound and SOUNDKIT and SOUNDKIT.TELL_MESSAGE then
        pcall(PlaySound, SOUNDKIT.TELL_MESSAGE, "Master")
    end
end

local function Remove(key)
    if not active[key] then return end
    active[key] = nil
    for i, k in ipairs(order) do
        if k == key then table.remove(order, i) break end
    end
end

local function Start(p, source, opts)
    opts = opts or {}
    local now = GetTime()
    local a = active[p.key]
    local dur = opts.duration or p.dur
    if not a then
        a = { proc = p, started = now, count = 0 }
        active[p.key] = a
        order[#order + 1] = p.key
        PlayProcSound()
    end
    a.icon = opts.icon or a.icon or p.icon
    a.source = source
    a.duration = dur
    a.expires = opts.expires or (dur and now + dur or nil)
    a.count = opts.count or math.max(a.count, 1)
    a.stacks = opts.stacks
    a.started = opts.started or (a.expires and dur and a.expires - dur) or now
    Layout()
end

-- Display
---------------------------------------------------------------------------
local anchor = CreateFrame("Frame", "ProcCityAnchor", UIParent)
anchor:SetSize(40, 40)
anchor:SetMovable(true)
anchor:SetClampedToScreen(true)
anchor:SetFrameStrata("MEDIUM")

anchor.box = anchor:CreateTexture(nil, "BACKGROUND")
anchor.box:SetAllPoints()
anchor.box:SetColorTexture(1, 0.5, 0, 0.25)
anchor.label = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
anchor.label:SetPoint("BOTTOM", anchor, "TOP", 0, 4)
anchor.label:SetText("Proc City: drag to move")

anchor:SetScript("OnMouseDown", function(self, button)
    if unlocked and button == "LeftButton" then self:StartMoving() end
end)
anchor:SetScript("OnMouseUp", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    if db and point then db.pos = { point = point, rel = rel, x = x, y = y } end
end)

local function PlaceAnchor()
    anchor:ClearAllPoints()
    local p = db and db.pos
    if p and p.point then
        anchor:SetPoint(p.point, UIParent, p.rel or p.point, p.x or 0, p.y or 0)
    else
        anchor:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
    end
end

local icons = {}

local function NewIcon()
    local f = CreateFrame("Frame", nil, anchor)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    f.border = f:CreateTexture(nil, "BACKGROUND")
    f.border:SetPoint("TOPLEFT", -1, 1)
    f.border:SetPoint("BOTTOMRIGHT", 1, -1)
    f.border:SetColorTexture(0, 0, 0, 1)

    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints()
    f.cd:SetReverse(true)
    if f.cd.SetHideCountdownNumbers then f.cd:SetHideCountdownNumbers(true) end
    if f.cd.SetDrawEdge then f.cd:SetDrawEdge(false) end

    local over = CreateFrame("Frame", nil, f)
    over:SetAllPoints()
    over:SetFrameLevel((f.cd:GetFrameLevel() or 1) + 2)
    f.time = over:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    f.time:SetPoint("CENTER", 0, 0)
    f.stacks = over:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    f.stacks:SetPoint("BOTTOMRIGHT", -2, 2)

    -- glow for "up twice": a gold ring that pulses
    f.glow = over:CreateTexture(nil, "OVERLAY")
    f.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    f.glow:SetBlendMode("ADD")
    f.glow:SetVertexColor(1, 0.82, 0.1)
    f.glow:SetPoint("CENTER")
    f.edges = {}
    for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
                         { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        local t = over:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetColorTexture(1, 0.82, 0.1, 1)
        t:SetPoint(e[1]); t:SetPoint(e[2])
        if e[3] then t:SetHeight(2) else t:SetWidth(2) end
        f.edges[#f.edges + 1] = t
    end
    f.pulse = over:CreateAnimationGroup()
    f.pulse:SetLooping("BOUNCE")
    local fade = f.pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.3)
    fade:SetDuration(0.4)
    f.glowFrame = over

    f.pop = f:CreateAnimationGroup()
    local grow = f.pop:CreateAnimation("Scale")
    if grow.SetScaleFrom then grow:SetScaleFrom(1.4, 1.4); grow:SetScaleTo(1, 1) else grow:SetScale(0.7, 0.7) end
    grow:SetDuration(0.15)
    return f
end

local function SetGlow(f, on)
    f.glow:SetShown(on)
    for _, t in ipairs(f.edges) do t:SetShown(on) end
    if on then
        if not f.pulse:IsPlaying() then f.pulse:Play() end
    else
        f.pulse:Stop()
    end
end

local function FormatTime(left)
    if left >= 60 then return math.floor(left / 60) .. "m" end
    if left >= 10 then return tostring(math.floor(left)) end
    return ("%.1f"):format(left)
end


local function IsPinned(key)
    for _, k in ipairs(db.pins) do if k == key then return true end end
    return false
end

-- pinned abilities show greyed out while they're down (in combat, unless set otherwise)
local function ShowPinned(p)
    if not p or not Wanted(p) or not KnowsAny(p.ids) then return false end
    if testMode or unlocked then return true end
    if db.pinsInCombat then
        local ok, c = pcall(UnitAffectingCombat, "player")
        return ok and not IsSecret(c) and c and true or false
    end
    return true
end

Layout = function()
    if not db then return end
    local size, gap = db.size, db.spacing
    local dir = db.grow == "left" and -1 or 1
    anchor:SetSize(size, size)
    anchor.box:SetShown(unlocked)
    anchor.label:SetShown(unlocked)
    anchor:EnableMouse(unlocked)

    -- pinned first, in the order you pinned them, then everything else that's up
    local list, seen = {}, {}
    for _, key in ipairs(db.pins) do
        local p = byKey[key]
        if active[key] then
            list[#list + 1] = { key = key, a = active[key] }
            seen[key] = true
        elseif ShowPinned(p) then
            list[#list + 1] = { key = key, p = p }
        end
    end
    for _, key in ipairs(order) do
        if not seen[key] then list[#list + 1] = { key = key, a = active[key] } end
    end

    local shown = 0
    for i, e in ipairs(list) do
        local a = e.a
        local f = icons[i] or NewIcon()
        icons[i] = f
        f:SetSize(size, size)
        f.glow:SetSize(size * 1.8, size * 1.8)
        f:ClearAllPoints()
        f:SetPoint("CENTER", anchor, "CENTER", (i - 1) * (size + gap) * dir, 0)
        if a then
            f.tex:SetTexture(a.icon or 134400)
            if f.tex.SetDesaturated then f.tex:SetDesaturated(false) end
            f:SetAlpha(1)
            if a.expires and a.duration and db.swipe then
                f.cd:SetCooldown(a.expires - a.duration, a.duration)
                f.cd:Show()
            else
                f.cd:Hide()
            end
            f.stacks:SetText((a.stacks and a.stacks > 1) and a.stacks or "")
            SetGlow(f, false)
            if f.key ~= e.key then
                f.key = e.key
                if f.pop then f.pop:Stop(); f.pop:Play() end
            end
        else
            -- pinned and down: a faint grey icon holding its place
            f.tex:SetTexture(e.p.icon or 134400)
            if f.tex.SetDesaturated then f.tex:SetDesaturated(true) end
            f:SetAlpha((db.pinAlpha or 50) / 100)
            f.cd:Hide()
            f.stacks:SetText("")
            f.time:SetText("")
            SetGlow(f, false)
            f.key = "down:" .. e.key
        end
        f:Show()
        shown = i
    end
    for i = shown + 1, #icons do
        icons[i]:Hide()
        icons[i].key = nil
        SetGlow(icons[i], false)
    end
end
ns.Layout = function() Layout() end

-- seconds left on each icon, and dropping finished ones
local ticker = CreateFrame("Frame")
local since = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    since = since + elapsed
    if since < 0.1 or not db then return end
    since = 0
    local now = GetTime()
    local removed = false
    for i = #order, 1, -1 do
        local key = order[i]
        local a = active[key]
        if a.expires and a.expires <= now and not testMode then
            Remove(key)
            removed = true
        end
    end
    if removed then Layout() end
    for _, f in ipairs(icons) do
        local a = f.key and active[f.key]
        if a then
            if db.timer and a.expires then
                f.time:SetText(FormatTime(math.max(0, a.expires - now)))
            else
                f.time:SetText("")
            end
        end
    end
end)

---------------------------------------------------------------------------
-- Test mode
---------------------------------------------------------------------------
local function TestEntries()
    local list = {}
    for _, p in ipairs(ns.PROCS) do
        if p.class and p.class[playerClass] then list[#list + 1] = p end
    end
    if #list == 0 then -- a class with none of these: show the warrior ones to set the layout
        for _, p in ipairs(ns.PROCS) do
            if p.class and p.class.WARRIOR then list[#list + 1] = p end
        end
    end
    return list
end

ns.Start, ns.Remove, ns.Wanted = Start, Remove, Wanted
ns.Active = function() return active end
ns.IsTest = function() return testMode end
ns.IsUnlocked = function() return unlocked end

local function SetTest(on)
    testMode = on
    wipe(active); wipe(order)
    if on then
        local now = GetTime()
        for i, p in ipairs(TestEntries()) do
            local dur = p.dur or 5
            Start(p, "test", { duration = dur, expires = now + dur * (1 - 0.15 * (i - 1)) })
        end
    end
    Layout()
    if ns.RefreshOverpower then ns.RefreshOverpower() end
    if ns.UpdateGlows then ns.UpdateGlows(true) end
end
ns.SetTest = SetTest

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local function SafeRegister(event)
    return pcall(ev.RegisterEvent, ev, event)
end
SafeRegister("ADDON_LOADED")

-- Overpower Plates / Proc Plates is now part of Proc City: bring its settings over once
function ns.ImportProcPlates()
    local old = OverpowerPlatesDB
    if type(old) == "table" and not db.importedProcPlates then
        if type(old.window) == "number" then db.oppWindow = old.window end
        if type(old.size) == "number" then db.oppSize = old.size end
        if type(old.offsetY) == "number" then db.oppOffset = old.offsetY end
        if old.sound ~= nil then db.oppSound = old.sound and true or false end
        if old.pop ~= nil then db.oppPop = old.pop and true or false end
        if old.pulse ~= nil then db.oppPulse = old.pulse and true or false end
        if old.barGlow == false then db.glowButtons = false end
        if old.reactive == false then
            for _, k in ipairs({ "revenge", "riposte", "counterattack", "mongoose" }) do db.off[k] = true end
        end
        if type(old.reactOff) == "table" then
            for k, v in pairs(old.reactOff) do if v then db.off[k] = true end end
        end
        db.importedProcPlates = true
    end
end

ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        ProcCityDB = ProcCityDB or {}
        for k, v in pairs(defaults) do
            if ProcCityDB[k] == nil then
                if type(v) == "table" then
                    local copy = {}
                    for kk, vv in pairs(v) do copy[kk] = vv end
                    ProcCityDB[k] = copy
                else
                    ProcCityDB[k] = v
                end
            end
        end
        if type(ProcCityDB.cats) ~= "table" then ProcCityDB.cats = {} end
        if ProcCityDB.cats.reactive == nil then ProcCityDB.cats.reactive = true end
        db = ProcCityDB
        ns.db = db
        for _, k in ipairs(RETIRED) do db[k] = nil end
        -- pins for buffs Proc City no longer tracks
        if type(db.pins) ~= "table" then db.pins = {} end
        for i = #db.pins, 1, -1 do
            if not byKey[db.pins[i]] then table.remove(db.pins, i) end
        end
        ns.ImportProcPlates()
        local _, class = UnitClass("player")
        playerClass = class
        BuildIcons()
        if ns.StartVersionCheck then ns.StartVersionCheck(db, "Proc City") end
        PlaceAnchor()
        ns.BuildOptions()
        SafeRegister("PLAYER_ENTERING_WORLD")
        SafeRegister("PLAYER_REGEN_DISABLED")
        SafeRegister("PLAYER_REGEN_ENABLED")
        SafeRegister("SPELLS_CHANGED")
        Layout()
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        BuildIcons()
        Layout()
        C_Timer.After(4, ns.SeedPins)
        if not db.toldAboutCooldownManager then
            db.toldAboutCooldownManager = true
            C_Timer.After(6, function()
                Print("2.0: Proc City now shows Overpower, Revenge, Victory Rush, Riposte, Counterattack and Mongoose Bite. "
                    .. "For buff procs like Flurry or Crusader, use the game's Cooldown Manager (Options > Gameplay > Advanced): "
                    .. "Forever hides your buffs from addons in combat.")
            end)
        end
    elseif event == "SPELLS_CHANGED" then
        BuildIcons()
        Layout()
    else
        Layout() -- in or out of combat: pinned icons appear or hide
    end
end)

---------------------------------------------------------------------------
-- Settings page and slash command
---------------------------------------------------------------------------
local function Mine()
    local list = {}
    for _, p in ipairs(ns.PROCS) do
        if p.class and p.class[playerClass] then list[#list + 1] = p end
    end
    return list
end

function ns.BuildOptions()
    local controls = {
        { type = "header", label = "Layout" },
        { type = "choice", key = "grow", label = "Icons grow to the", values = { "right", "left" } },
        { type = "range", key = "size", label = "Icon size", min = 20, max = 80, step = 2 },
        { type = "range", key = "spacing", label = "Gap between icons", min = 0, max = 20, step = 1 },
        { type = "check", key = "timer", label = "Show seconds left on the icon" },
        { type = "check", key = "swipe", label = "Show a clock sweep as it runs out" },
        { type = "check", key = "sound", label = "Play a sound when one lights up" },
        { type = "button", label = "Move the icons",
          dynamicLabel = function() return unlocked and "Lock the icons" or "Move the icons" end,
          func = function() unlocked = not unlocked; Layout() end },
        { type = "button", label = "Reset position", func = function() db.pos = nil; PlaceAnchor() end },
        { type = "button", label = "Test",
          dynamicLabel = function() return testMode and "Stop the test" or "Test" end,
          func = function() SetTest(not testMode) end },
        { type = "header", label = "What to show" },
    }
    local mine = Mine()
    if #mine == 0 then
        controls[#controls + 1] = { type = "info", height = 30, lines = function()
            return "|cff999999Your class has none of these abilities. Proc City is for warriors, rogues and hunters.|r" end }
    end
    for _, p in ipairs(mine) do
        controls[#controls + 1] = { type = "check", key = "on_" .. p.key, label = p.name .. " |cff999999(" .. p.note .. ")|r" }
    end
    controls[#controls + 1] = { type = "check", key = "glowButtons", label = "Light their buttons on your action bars" }
    if playerClass == "WARRIOR" then
        controls[#controls + 1] = { type = "header", label = "Overpower on the mob that dodged you" }
        controls[#controls + 1] = { type = "check", key = "oppPlates", label = "Put an Overpower icon on that mob's nameplate too" }
        controls[#controls + 1] = { type = "range", key = "oppSize", label = "Nameplate icon size", min = 16, max = 64, step = 2 }
        controls[#controls + 1] = { type = "range", key = "oppOffset", label = "Height above the health bar", min = 0, max = 80, step = 2 }
        controls[#controls + 1] = { type = "range", key = "oppWindow", label = "Seconds Overpower stays up", min = 1, max = 10, step = 1, suffix = "s" }
        controls[#controls + 1] = { type = "check", key = "oppPop", label = "Pop the nameplate icon in" }
        controls[#controls + 1] = { type = "check", key = "oppPulse", label = "Pulse a gold glow around it" }
        controls[#controls + 1] = { type = "check", key = "oppSound", label = "Play a sound when a mob dodges you" }
        controls[#controls + 1] = { type = "info", height = 44, lines = function()
            return "|cff999999A nameplate dodge only counts when your Overpower charge goes up at the same moment, so dodges against other players are ignored. Needs enemy nameplates on (V).|r" end }
    end
    controls[#controls + 1] = { type = "header", label = "Always show (greyed out while down)" }
    controls[#controls + 1] = { type = "dropdown", key = "pinPick", label = "Pin or unpin",
        options = function()
            local out = {}
            for _, p in ipairs(ns.PinChoices()) do
                out[#out + 1] = { value = p.key, label = (IsPinned(p.key) and "|cff40ff40[pinned]|r " or "") .. p.name }
            end
            return out
        end,
        onSelect = function(key) ns.TogglePin(key) end }
    controls[#controls + 1] = { type = "info", height = 30, lines = function()
        local names = {}
        for _, k in ipairs(db.pins) do names[#names + 1] = byKey[k] and byKey[k].name or k end
        return "|cff999999" .. (#names > 0 and ("Pinned: " .. table.concat(names, ", ")) or "Nothing pinned.") .. "|r" end }
    controls[#controls + 1] = { type = "check", key = "pinsInCombat", label = "Only show pinned ones that are down while I'm in combat" }
    controls[#controls + 1] = { type = "range", key = "pinAlpha", label = "How faint a pinned one is while down", min = 20, max = 100, step = 10, suffix = "%" }
    controls[#controls + 1] = { type = "button", label = "Unpin all", func = function() wipe(db.pins); Layout() end }
    controls[#controls + 1] = { type = "header", label = "Buff procs (Flurry, Crusader, Clearcasting...)" }
    controls[#controls + 1] = { type = "info", height = 58, lines = function()
        return "|cff999999WoW Forever hides your buffs from addons in combat, so no addon can show buff procs mid-fight. "
            .. "The game's own Cooldown Manager can: turn it on under Options > Gameplay > Advanced, then add the buffs you want to its Tracked Buffs.|r" end }

    -- per-ability checkboxes are stored as db.off; categories as db.cats
    local proxy = setmetatable({}, {
        __index = function(_, k)
            local key = type(k) == "string" and k:match("^on_(.+)$")
            if key then return not db.off[key] end
            return db[k]
        end,
        __newindex = function(_, k, v)
            local key = type(k) == "string" and k:match("^on_(.+)$")
            if key then
                db.off[key] = (not v) or nil
                if not v then Remove(key) end
            else
                db[k] = v
            end
        end,
    })

    ns.CreateOptions({
        title = "Proc City",
        updateNotice = true,
        changes = {
            { "2.0.0", "Proc City is now about the abilities that light up in a fight: Overpower (on the mob's nameplate too), Revenge, Victory Rush, Riposte, Counterattack and Mongoose Bite",
                       "Victory Rush is new: it lights up after a kill",
                       "Buff procs are gone: Forever hides your buffs from addons in combat, so they could only ever show out of combat. Use the game's Cooldown Manager for those" },
            { "1.7.1", "Fixed the row going blank in combat when the game hides your buffs", "/proc debug and /proc check say whether hidden buffs can be drawn, and why not" },
            { "1.7.0", "In combat, buffs the game hides are drawn the way your buff bar draws them, so procs show mid-fight again", "A proc read before the fight drops off when its buff ends" },
            { "1.6.4", "/proc check crusader: everything the game says about one proc, right now" },
            { "1.6.3", "Fixed: since 1.6.1, Flurry, Berserker Rage and other procs could vanish in combat", "Crusader uses the same icon as your buff bar" },
            { "1.6.2", "Buffs the game hides in combat are recognised by their icon (Crusader)", "/proc debug describes each hidden buff" },
            { "1.6.1", "Crusader (and any other buff the game hides in combat) shows in combat again" },
            { "1.6.0", "Tracks the new WoW Forever procs and cooldowns for every class (Reckless Swings, Shield Wall, Heating Up, Eclipse, Infusion of Light, Maelstrom Weapon and more)",
                       "Overpower shows for every charge, including Bloodthrill procs and mobs without a nameplate",
                       "A Swiftness Potion no longer shows as a Sprinter's Sword proc (weapon procs need the weapon on)",
                       "Settings page: long labels no longer run into their buttons" },
            { "1.5.3", "Blood Craze is now tracked (warrior talent: heals you after you're crit)" },
            { "1.5.2", "Procs update in combat again: one buff the game hides in combat made it stop reading all of them",
                       "It now skips the hidden ones and reads the rest, and checks twice a second in combat" },
            { "1.5.1", "In combat, procs light up again: it asks the game about each proc directly instead of reading the hidden buff list",
                       "/proc debug lists what the game says about each proc, if any still stay grey" },
            { "1.5.0", "Starter pins: the procs your class builds around are pinned for you (if you have them)",
                       "Unpin any you don't want with /proc unpin <name> or on this page" },
            { "1.4.0", "Proc Plates is now part of Proc City: Overpower, Revenge, Riposte, Counterattack and Mongoose Bite",
                       "Overpower also marks the mob that dodged you on its nameplate",
                       "Lights the matching action buttons, including Shadow Bolt during Shadow Trance" },
            { "1.3.0", "Pin the procs you care about: they keep their place, greyed out while they're down",
                       "Pick them on this page or with /proc pin <name>" },
        },
        icon = "Interface\\Icons\\Ability_MeleeDamage",
        about = "Overpower, Revenge, Victory Rush, Riposte, Counterattack and Mongoose Bite as a row of icons",
        credit = "Created by Miff, supported by Claude",
        slash = "/proc",
        db = proxy,
        onChange = function()
            Layout()
            if ns.RefreshOverpower then ns.RefreshOverpower() end
            if ns.UpdateGlows then ns.UpdateGlows(true) end
        end,
        controls = controls,
    })
end

function ProcCity_OnAddonCompartmentClick()
    if ns.OpenOptions then ns.OpenOptions() end
end

-- what can be pinned: your class's abilities that you know (plus anything already pinned)
function ns.PinChoices()
    local out = {}
    for _, p in ipairs(ns.PROCS) do
        if (p.class and p.class[playerClass] and KnowsAny(p.ids)) or IsPinned(p.key) then out[#out + 1] = p end
    end
    return out
end

-- Starter pins: the first time each class logs in with nothing pinned, pin its main one
-- if this character knows it. Unpin it and it isn't added back.
local STARTER = { WARRIOR = "overpower", ROGUE = "riposte", HUNTER = "mongoose" }
ns.STARTER = STARTER

function ns.SeedPins()
    if not db or testMode then return end
    if type(db.seeded) ~= "table" then db.seeded = {} end
    if db.seeded[playerClass] then return end
    local p = byKey[STARTER[playerClass] or ""]
    if not p then db.seeded[playerClass] = true return end
    if not KnowsAny(p.ids) then return end -- not learned yet: try again next login
    db.seeded[playerClass] = true
    if IsPinned(p.key) then return end
    db.pins[#db.pins + 1] = p.key
    Layout()
    Print(("pinned %s for you: it keeps its place and shows greyed out in combat while down. /proc unpin %s to remove it."):format(p.name, p.key))
end

function ns.TogglePin(key)
    for i, k in ipairs(db.pins) do
        if k == key then table.remove(db.pins, i); Layout() return false end
    end
    db.pins[#db.pins + 1] = key
    Layout()
    return true
end

local function FindProc(text)
    text = (text or ""):lower():gsub("[%s'%-]", "")
    if text == "" then return nil end
    for _, p in ipairs(ns.PROCS) do
        if p.key == text or p.name:lower():gsub("[%s'%-]", "") == text then return p end
    end
end

SLASH_PROCCITY1 = "/proc"
SLASH_PROCCITY2 = "/proccity"
SlashCmdList.PROCCITY = function(msg)
    local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "" then
        ns.OpenOptions()
        return
    elseif cmd == "test" then
        SetTest(not testMode)
        Print(testMode and "test icons on. /proc test again to stop." or "test icons off.")
    elseif cmd == "move" or cmd == "unlock" or cmd == "lock" then
        unlocked = (cmd == "unlock") or (cmd == "move" and not unlocked)
        Layout()
        Print(unlocked and "drag the orange box to move the icons. /proc lock when done." or "icons locked.")
    elseif cmd == "reset" then
        db.pos = nil; PlaceAnchor(); Print("position reset.")
    elseif cmd == "grow" and (rest == "left" or rest == "right") then
        db.grow = rest; Layout(); Print("icons grow to the " .. rest .. ".")
    elseif cmd == "size" and tonumber(rest) then
        db.size = tonumber(rest); Layout(); Print("icon size " .. rest)
    elseif cmd == "off" or cmd == "on" then
        local p = FindProc(rest)
        if not p then Print("no ability called \"" .. rest .. "\". /proc list shows them.") return end
        db.off[p.key] = (cmd == "off") or nil
        if cmd == "off" then Remove(p.key); Layout() end
        Print(p.name .. (cmd == "off" and " won't be shown." or " will be shown."))
    elseif cmd == "pin" or cmd == "unpin" then
        local p = FindProc(rest)
        if not p then Print("no ability called \"" .. rest .. "\". /proc list shows them.") return end
        if (cmd == "pin") ~= IsPinned(p.key) then ns.TogglePin(p.key) end
        Print(p.name .. (cmd == "pin" and " is pinned: it keeps its place, greyed out while it's down." or " is unpinned."))
    elseif cmd == "plates" then
        db.oppPlates = not db.oppPlates
        if ns.RefreshOverpower then ns.RefreshOverpower() end
        Print("Overpower icon on the nameplate of the mob that dodged you " .. (db.oppPlates and "on" or "off"))
    elseif cmd == "glow" then
        db.glowButtons = not db.glowButtons
        if ns.UpdateGlows then ns.UpdateGlows(true) end
        Print("action button glow " .. (db.glowButtons and "on" or "off"))
    elseif cmd == "list" then
        local parts = {}
        for _, p in ipairs(Mine()) do
            parts[#parts + 1] = db.off[p.key] and ("|cff888888" .. p.name .. "|r") or p.name
        end
        Print(#parts > 0 and ("for your class (grey = off): " .. table.concat(parts, ", ")) or "nothing for your class.")
    elseif cmd == "debug" then
        debugMode = not debugMode
        Print(debugMode and "debug on." or "debug off.")
        if debugMode then
            if playerClass == "WARRIOR" and ns.ReadOverpowerCharges then
                Print("Overpower charges: " .. tostring(ns.ReadOverpowerCharges()))
            end
            if ns.ReactiveDebug then for _, line in ipairs(ns.ReactiveDebug()) do Print(line) end end
            if ns.GlowDebug then
                for _, p in ipairs(Mine()) do Print(ns.GlowDebug(p.name, p.ids)) end
            end
        end
    else
        Print("v" .. ns.version .. " commands (or just /proc for the settings page):")
        Print("/proc test - show test icons")
        Print("/proc move - move the icons (/proc lock when done), /proc reset - back to the middle")
        Print("/proc grow left|right - which way the icons grow (now " .. db.grow .. ")")
        Print("/proc size <n> - icon size (now " .. db.size .. ")")
        Print("/proc list - what's shown for your class; /proc off <name> or /proc on <name>")
        Print("/proc pin <name>, /proc unpin <name> - always show it, greyed out while it's down")
        Print("/proc glow - light the matching action buttons (now " .. (db.glowButtons and "on" or "off") .. ")")
        if playerClass == "WARRIOR" then
            Print("/proc plates - Overpower icon on the mob that dodged you (now " .. (db.oppPlates and "on" or "off") .. ")")
        end
        Print("/proc debug - what Proc City sees")
    end
    if ns.RefreshOptions then ns.RefreshOptions() end
end

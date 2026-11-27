-- Proc City: abilities that light up after a dodge, parry or block.
--   Warrior  Revenge        after you block, dodge or parry
--   Rogue    Riposte        after you parry
--   Hunter   Counterattack  after you parry
--   Hunter   Mongoose Bite  after your target dodges
-- (Overpower has its own file, since it's tied to the mob that dodged.)
--
-- No combat log: the game still reports your own dodges, parries and blocks (and your
-- target's dodges) as combat events, and its combat text says when one of these lights
-- up. Either starts a 5 second icon in the row. When the game also says whether the
-- spell can be cast right now, the icon only shows while it can, and goes away once you
-- use it. Mongoose Bite needs that check, because your target dodging your pet looks the
-- same as dodging you.
-- (From Proc Plates, formerly Overpower Plates, now part of Proc City.)

local _, ns = ...

local GRACE = 0.5      -- the game may say "usable" a moment after the dodge arrives
local mine = {}        -- the entries for your class that you know (Overpower aside)
local pending = {}     -- [key] = when its dodge / parry / block happened
local seen = { player = 0, target = 0, text = 0, secret = 0 }

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function KnownID(p)
    if not IsPlayerSpell then return nil end
    for _, id in ipairs(p.ids) do
        local ok, known = pcall(IsPlayerSpell, id)
        if ok and not IsSecret(known) and known then return id end
    end
end

-- true / false when the game says whether it can be cast now, nil when it won't say
local function Usable(p)
    local fn = (C_Spell and C_Spell.IsSpellUsable) or IsUsableSpell
    local id = KnownID(p) or p.ids[1]
    if not fn then return nil end
    local ok, usable = pcall(fn, id)
    if not ok or IsSecret(usable) or usable == nil then return nil end
    return usable and true or false
end
ns.Usable = Usable

local function Rebuild()
    wipe(mine)
    local _, class = UnitClass("player")
    for _, p in ipairs(ns.PROCS) do
        if p.react and p.key ~= "overpower" and p.class and p.class[class] and KnownID(p) then
            mine[#mine + 1] = p
        end
    end
end
ns.RebuildReactive = Rebuild

local function Trigger(p)
    if not (ns.Wanted and ns.Wanted(p)) then return end
    pending[p.key] = pending[p.key] or GetTime()
end

local function Tick()
    if not ns.db then return end
    local now = GetTime()
    local active = ns.Active()
    for _, p in ipairs(mine) do
        local t = pending[p.key]
        if t then
            local u = Usable(p)
            if u == true or (u == nil and not p.confirm) then
                pending[p.key] = nil
                ns.Start(p, "react", { duration = p.dur, expires = t + p.dur })
            elseif now - t > GRACE then
                pending[p.key] = nil -- on cooldown, or not confirmed
            end
        end
        local a = active[p.key]
        if a and a.source == "react" and now - (a.started or now) > GRACE and Usable(p) == false then
            -- used it, or it went on cooldown
            ns.Remove(p.key)
            ns.Layout()
        end
    end
end

local function OnCombat(unit, what, flags)
    if IsSecret(what) or IsSecret(flags) then seen.secret = seen.secret + 1 return end
    if unit == "player" then
        seen.player = seen.player + 1
        local kind = what
        if flags == "BLOCK_REDUCED" then kind = "BLOCK" end -- a partly blocked hit
        for _, p in ipairs(mine) do
            if p.on and p.on[kind] then Trigger(p) end
        end
    elseif unit == "target" and what == "DODGE" then
        seen.target = seen.target + 1
        for _, p in ipairs(mine) do
            if p.target then Trigger(p) end
        end
    end
    Tick()
end

-- the game's own "Revenge!" combat text
local function OnCombatText(kind)
    if IsSecret(kind) or kind ~= "SPELL_ACTIVE" then return end
    local get = (C_CombatText and C_CombatText.GetCurrentEventInfo) or GetCurrentCombatTextEventInfo
    if not get then return end
    local ok, name = pcall(get)
    if not ok or IsSecret(name) or type(name) ~= "string" then return end
    for _, p in ipairs(mine) do
        if p.name == name or (C_Spell and C_Spell.GetSpellName and KnownID(p) and C_Spell.GetSpellName(KnownID(p)) == name) then
            seen.text = seen.text + 1
            Trigger(p)
        end
    end
    Tick()
end

-- /proc debug lines
function ns.ReactiveDebug()
    local lines = {}
    for _, p in ipairs(mine) do
        local u = Usable(p)
        lines[#lines + 1] = ("%s: %s, usable now: %s"):format(p.name, ns.Wanted(p) and "on" or "off",
            u == nil and "game won't say" or tostring(u))
    end
    if #mine > 0 then
        lines[#lines + 1] = ("seen: your dodges/parries/blocks %d, your target's dodges %d, combat text %d, hidden %d"):format(
            seen.player, seen.target, seen.text, seen.secret)
    end
    return lines
end

local ev = CreateFrame("Frame")
local function SafeRegister(e) return pcall(ev.RegisterEvent, ev, e) end
SafeRegister("PLAYER_LOGIN")

ev:SetScript("OnEvent", function(_, event, a1, a2, a3)
    if event == "PLAYER_LOGIN" then
        Rebuild()
        SafeRegister("SPELLS_CHANGED")
        if not (ev.RegisterUnitEvent and pcall(ev.RegisterUnitEvent, ev, "UNIT_COMBAT", "player", "target")) then
            SafeRegister("UNIT_COMBAT")
        end
        SafeRegister("COMBAT_TEXT_UPDATE")
        SafeRegister("SPELL_UPDATE_USABLE")
        C_Timer.NewTicker(0.1, function() if next(pending) or #mine > 0 then Tick() end end)
    elseif event == "SPELLS_CHANGED" then
        Rebuild()
    elseif event == "UNIT_COMBAT" then
        if a1 == "player" or a1 == "target" then OnCombat(a1, a2, a3) end
    elseif event == "COMBAT_TEXT_UPDATE" then
        OnCombatText(a1)
    else
        Tick()
    end
end)

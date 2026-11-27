-- Payback: the other "only after a dodge, parry or block" abilities.
--   Warrior  Revenge        after you block, dodge or parry
--   Rogue    Riposte        after you parry
--   Hunter   Counterattack  after you parry
--   Hunter   Mongoose Bite  after your target dodges
--
-- No combat log: the game still reports your own dodges, parries and blocks (and your
-- target's dodges) as combat events, which is what starts the window. When the game also
-- says whether the spell can be used right now, the icon only shows while it can, so a
-- Revenge on cooldown or a Riposte without the energy stays hidden. Mongoose Bite needs
-- that check, because your target dodging your pet looks the same as dodging you.
--
-- Shown as big icons in the middle of the screen (movable) and a glow on the spell's
-- action buttons. Overpower keeps its icon on the nameplate of the mob that dodged.

local _, ns = ...

local REACTIVE = {
    { key = "revenge", class = "WARRIOR", name = "Revenge", ids = { 6572, 6574, 7379, 11600, 11601, 25288 },
      on = { BLOCK = true, DODGE = true, PARRY = true }, window = 5 },
    { key = "riposte", class = "ROGUE", name = "Riposte", ids = { 14251 },
      on = { PARRY = true }, window = 5 },
    { key = "counterattack", class = "HUNTER", name = "Counterattack", ids = { 19306, 20909, 20910 },
      on = { PARRY = true }, window = 5 },
    { key = "mongoose", class = "HUNTER", name = "Mongoose Bite", ids = { 1495, 14269, 14270, 14271 },
      target = true, confirm = true, window = 5 },
}
ns.REACTIVE = REACTIVE

local playerClass
local active = {}      -- [key] = expires
local seen = { player = 0, target = 0, secret = 0 } -- combat events seen, for /opp debug
local mine = {}        -- the entries for your class that you know

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function Known(r)
    if not IsPlayerSpell then return false end
    for _, id in ipairs(r.ids) do
        local ok, known = pcall(IsPlayerSpell, id)
        if ok and not IsSecret(known) and known then return true end
    end
    return false
end

local function KnownID(r)
    for _, id in ipairs(r.ids) do
        local ok, known = pcall(IsPlayerSpell, id)
        if ok and not IsSecret(known) and known then return id end
    end
    return r.ids[1]
end

-- true / false when the game says whether it can be cast now, nil when it won't say
local function Usable(r)
    local fn = (C_Spell and C_Spell.IsSpellUsable) or IsUsableSpell
    if not fn then return nil end
    local ok, usable = pcall(fn, KnownID(r))
    if not ok or IsSecret(usable) or usable == nil then return nil end
    return usable and true or false
end
ns.ReactiveUsable = Usable

local function Icon(r)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, KnownID(r))
        if ok and tex and not IsSecret(tex) then return tex end
    end
    return "Interface\\Icons\\Ability_Warrior_Revenge"
end

local function Wanted(r)
    local db = ns.db
    return db and db.reactive and not db.reactOff[r.key]
end

---------------------------------------------------------------------------
-- Screen icons
---------------------------------------------------------------------------
local GOLD = { 1, 0.82, 0.1 }
local holder = CreateFrame("Frame", "PaybackReactiveFrame", UIParent)
holder:SetFrameStrata("HIGH")
holder:SetClampedToScreen(true)
holder:SetMovable(true)
holder:SetSize(56, 56)
holder:Hide()
holder:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" and ns.screenUnlocked then self:StartMoving() end
end)
holder:SetScript("OnMouseUp", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint()
    if ns.db and point then ns.db.reactPos = { point = point, x = x, y = y } end
end)
holder.label = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
holder.label:SetPoint("BOTTOM", holder, "TOP", 0, 4)

local icons = {}
local function NewIcon()
    local f = CreateFrame("Frame", nil, holder)
    f.glow = f:CreateTexture(nil, "BACKGROUND")
    f.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    f.glow:SetBlendMode("ADD")
    f.glow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
    f.glow:SetPoint("CENTER")
    f.border = f:CreateTexture(nil, "BORDER")
    f.border:SetPoint("TOPLEFT", -2, 2)
    f.border:SetPoint("BOTTOMRIGHT", 2, -2)
    f.border:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints()
    if f.cd.SetDrawEdge then f.cd:SetDrawEdge(false) end
    f.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.name:SetPoint("TOP", f, "BOTTOM", 0, -3)
    f.pulse = f:CreateAnimationGroup()
    f.pulse:SetLooping("BOUNCE")
    local a = f.pulse:CreateAnimation("Alpha")
    a:SetTarget(f.glow)
    a:SetFromAlpha(1)
    a:SetToAlpha(0.2)
    a:SetDuration(0.35)
    f.pop = f:CreateAnimationGroup()
    local grow = f.pop:CreateAnimation("Scale")
    if grow.SetScaleFrom then grow:SetScaleFrom(1.5, 1.5); grow:SetScaleTo(1, 1) else grow:SetScale(0.67, 0.67) end
    grow:SetDuration(0.18)
    icons[#icons + 1] = f
    return f
end

local function Place()
    local db = ns.db
    holder:ClearAllPoints()
    local p = db.reactPos
    if p and p.point then
        holder:SetPoint(p.point, UIParent, p.point, p.x or 0, p.y or 0)
    else
        holder:SetPoint("CENTER", UIParent, "CENTER", 0, 210)
    end
end

function ns.ResetReactivePosition()
    if ns.db then ns.db.reactPos = nil end
    Place()
end

local shownKeys = {}

local function Update()
    local db = ns.db
    if not db then return end
    local now = GetTime()
    local up = {}
    for _, r in ipairs(mine) do
        local expires = active[r.key]
        if expires and expires <= now then active[r.key] = nil; expires = nil end
        if expires and Wanted(r) then
            local usable = Usable(r)
            -- shown while the game says it can be cast (or won't say), hidden on cooldown
            if usable ~= false then up[#up + 1] = { r = r, expires = expires } end
        end
    end
    if ns.reactTest then
        up = {}
        local list = #mine > 0 and mine or { REACTIVE[1] }
        for _, r in ipairs(list) do up[#up + 1] = { r = r, expires = now + r.window * 0.6 } end
    end

    for _, r in ipairs(REACTIVE) do
        local lit = false
        for _, u in ipairs(up) do if u.r == r then lit = true end end
        if ns.SetReactiveGlow then ns.SetReactiveGlow(r.key, (lit and db.reactGlow) and { name = r.name, ids = r.ids } or nil) end
    end

    local showScreen = db.reactScreen and #up > 0
    if not showScreen and not ns.screenUnlocked then
        holder:Hide()
        for _, f in ipairs(icons) do f.pulse:Stop() end
        wipe(shownKeys)
        return
    end
    Place()
    local size, gap = db.reactSize, 10
    local list = up
    if #list == 0 and ns.screenUnlocked then
        list = { { r = mine[1] or REACTIVE[1] } }
    end
    holder:SetSize(math.max(size, #list * size + (#list - 1) * gap), size)
    holder:EnableMouse(ns.screenUnlocked and true or false)
    holder.label:SetText(ns.screenUnlocked and "Payback: drag to move" or "")
    for i = 1, math.max(#list, #icons) do
        local f = icons[i] or (list[i] and NewIcon())
        local u = list[i]
        if u then
            f:SetSize(size, size)
            f.glow:SetSize(size * 1.8, size * 1.8)
            f:ClearAllPoints()
            f:SetPoint("LEFT", holder, "LEFT", (i - 1) * (size + gap), 0)
            f.tex:SetTexture(Icon(u.r))
            f.name:SetText(db.reactNames and u.r.name or "")
            if u.expires then f.cd:SetCooldown(u.expires - u.r.window, u.r.window) else f.cd:Clear() end
            if not f:IsShown() or shownKeys[i] ~= u.r.key then
                f:Show()
                if db.pop then f.pop:Stop(); f.pop:Play() end
                f.pulse:Play()
            end
            shownKeys[i] = u.r.key
        elseif f then
            f.pulse:Stop()
            f:Hide()
            shownKeys[i] = nil
        end
    end
    holder:Show()
end
ns.UpdateReactive = Update

---------------------------------------------------------------------------
-- Triggers
---------------------------------------------------------------------------
local function Start(r)
    if not Wanted(r) then return end
    local fresh = not active[r.key]
    active[r.key] = GetTime() + r.window
    if fresh and ns.db.reactSound and Usable(r) ~= false and PlaySound and SOUNDKIT then
        PlaySound(SOUNDKIT.RAID_WARNING or 8959, "SFX")
    end
    Update()
end

local function OnCombat(unit, what, flags)
    if IsSecret(what) or IsSecret(flags) then seen.secret = seen.secret + 1 return end
    if unit == "player" then
        seen.player = seen.player + 1
        local kind = what
        if flags == "BLOCK_REDUCED" then kind = "BLOCK" end -- a partly blocked hit
        for _, r in ipairs(mine) do
            if r.on and r.on[kind] then Start(r) end
        end
    elseif unit == "target" and what == "DODGE" then
        seen.target = seen.target + 1
        for _, r in ipairs(mine) do
            -- only counted when the game confirms it's usable: the dodge may have been against your pet
            if r.target and (not r.confirm or Usable(r) ~= nil) then Start(r) end
        end
    end
end

local function Rebuild()
    playerClass = select(2, UnitClass("player"))
    wipe(mine)
    for _, r in ipairs(REACTIVE) do
        if r.class == playerClass and Known(r) then mine[#mine + 1] = r end
    end
end

-- /opp debug lines
function ns.ReactiveDebug()
    local lines = {}
    if #mine == 0 then
        lines[1] = "reactive abilities: none known on this character"
        return lines
    end
    for _, r in ipairs(mine) do
        local u = Usable(r)
        lines[#lines + 1] = ("%s: %s, usable now: %s, window %s"):format(r.name, Wanted(r) and "on" or "off",
            u == nil and "game won't say" or tostring(u), active[r.key] and "open" or "closed")
    end
    lines[#lines + 1] = ("combat events seen: your dodges/parries/blocks %d, your target's dodges %d, hidden %d"):format(
        seen.player, seen.target, seen.secret)
    return lines
end

local ev = CreateFrame("Frame")
local function SafeRegister(e, unit)
    if unit then return pcall(ev.RegisterUnitEvent, ev, e, unit) end
    return pcall(ev.RegisterEvent, ev, e)
end
SafeRegister("PLAYER_LOGIN")

ev:SetScript("OnEvent", function(_, event, a1, a2, a3)
    if event == "PLAYER_LOGIN" then
        local _, class = UnitClass("player")
        playerClass = class
        Rebuild()
        SafeRegister("SPELLS_CHANGED")
        if not (ev.RegisterUnitEvent and pcall(ev.RegisterUnitEvent, ev, "UNIT_COMBAT", "player", "target")) then
            SafeRegister("UNIT_COMBAT")
        end
        SafeRegister("SPELL_UPDATE_USABLE")
        SafeRegister("SPELL_UPDATE_COOLDOWN")
        SafeRegister("PLAYER_REGEN_ENABLED")
        C_Timer.NewTicker(0.1, function() if next(active) or ns.reactTest then Update() end end)
    elseif event == "SPELLS_CHANGED" then
        Rebuild()
    elseif event == "UNIT_COMBAT" then
        if a1 == "player" or a1 == "target" then OnCombat(a1, a2, a3) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        wipe(active)
        Update()
    else
        if next(active) then Update() end
    end
end)

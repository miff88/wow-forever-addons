-- Proc Plates (formerly Overpower Plates): the louder alerts.
--   * a gold glow and border on your Overpower button (or Revenge, Riposte, Counterattack,
--     Mongoose Bite) on the action bars while it's up
--   * an optional big Overpower icon in the middle of the screen, with a countdown sweep
-- The glow is its own frame laid over the button, so the action buttons themselves are
-- never touched (they're protected in combat).

local _, ns = ...

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local GOLD = { 1, 0.82, 0.1 }

---------------------------------------------------------------------------
-- Action buttons: Blizzard bars, Bartender4, ElvUI and Dominos
---------------------------------------------------------------------------
local BUTTON_SETS = {
    { "ActionButton", 12 }, { "MultiBarBottomLeftButton", 12 }, { "MultiBarBottomRightButton", 12 },
    { "MultiBarRightButton", 12 }, { "MultiBarLeftButton", 12 }, { "MultiBar5Button", 12 },
    { "MultiBar6Button", 12 }, { "MultiBar7Button", 12 }, { "BT4Button", 180 }, { "DominosActionButton", 180 },
}

local function AllButtons()
    local list = {}
    local function add(name)
        local b = _G[name]
        if type(b) == "table" and b.IsVisible then list[#list + 1] = b end
    end
    for _, set in ipairs(BUTTON_SETS) do
        for i = 1, set[2] do add(set[1] .. i) end
    end
    for bar = 1, 15 do
        for i = 1, 12 do add("ElvUI_Bar" .. bar .. "Button" .. i) end
    end
    return list
end

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, id)
        if ok and name and not IsSecret(name) then return name end
    end
end

-- a spell's IDs: the one you know, plus every rank given
local function SpellIDs(name, ranks)
    local ids, seen = {}, {}
    local function add(id)
        if type(id) == "number" and not IsSecret(id) and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, name)
        if ok and type(info) == "table" then add(info.spellID) end
    end
    if C_Spell and C_Spell.GetSpellIDForSpellIdentifier then
        local ok, id = pcall(C_Spell.GetSpellIDForSpellIdentifier, name)
        if ok then add(id) end
    end
    for _, id in ipairs(ranks or {}) do add(id) end
    return ids, seen
end

local function OverpowerIDs()
    return SpellIDs(ns.OVERPOWER_NAME, { 7384, 7887, 11584, 11585 })
end

-- Action slots holding the spell, straight from the game (no button reading needed)
local function SpellSlots(ids)
    local slots = {}
    if C_ActionBar and C_ActionBar.FindSpellActionButtons then
        for _, id in ipairs(ids) do
            local ok, list = pcall(C_ActionBar.FindSpellActionButtons, id)
            if ok and type(list) == "table" then
                for _, slot in ipairs(list) do
                    if not IsSecret(slot) then slots[slot] = true end
                end
            end
        end
    end
    return slots
end
local OverpowerSlots = SpellSlots

-- Which action slot a button shows, tried every way the bar addons expose it
local function ButtonSlot(btn)
    local function good(v) return type(v) == "number" and not IsSecret(v) and v > 0 end
    if btn.GetAction then
        local ok, a, b = pcall(btn.GetAction, btn)
        if ok then
            if a == "action" and good(b) then return b end
            if good(a) then return a end
        end
    end
    if good(btn.action) then return btn.action end
    if btn.GetAttribute then
        local ok, a = pcall(btn.GetAttribute, btn, "action")
        if ok and good(a) then return a end
    end
    if btn.CalculateAction then
        local ok, a = pcall(btn.CalculateAction, btn)
        if ok and good(a) then return a end
    end
    if btn.GetPagedID then
        local ok, a = pcall(btn.GetPagedID, btn)
        if ok and good(a) then return a end
    end
end

local function SlotInfo(slot)
    local get = GetActionInfo or (C_ActionBar and C_ActionBar.GetActionInfo)
    if not get then return end
    local ok, kind, id = pcall(get, slot)
    if not ok or IsSecret(kind) or IsSecret(id) then return end
    if kind == "macro" and GetMacroSpell then
        local ok2, spellID = pcall(GetMacroSpell, id)
        if ok2 and spellID and not IsSecret(spellID) then return "spell", spellID end
    end
    return kind, id
end

local function IsSpellButton(btn, slots, idSet, name)
    local slot = ButtonSlot(btn)
    if not slot then return false end
    if slots[slot] then return true end
    local kind, id = SlotInfo(slot)
    if kind ~= "spell" or not id then return false end
    return idSet[id] or SpellName(id) == name
end

local function IsOverpowerButton(btn, slots, idSet)
    return IsSpellButton(btn, slots, idSet, ns.OVERPOWER_NAME)
end

local glows = {} -- [button] = glow frame

local function Edge(g, a1, a2, horizontal)
    local t = g:CreateTexture(nil, "OVERLAY", nil, 7)
    t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    t:SetPoint(a1)
    t:SetPoint(a2)
    if horizontal then t:SetHeight(3) else t:SetWidth(3) end
end

local function GetGlow(btn)
    local g = glows[btn]
    if g then return g end

    -- a child of the button, so it follows the button's scale and hides with its bar
    g = CreateFrame("Frame", nil, btn)
    g:SetAllPoints(btn)
    g:SetFrameLevel((btn:GetFrameLevel() or 1) + 10)

    -- soft glow ring around the button
    g.ring = g:CreateTexture(nil, "OVERLAY")
    g.ring:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    g.ring:SetBlendMode("ADD")
    g.ring:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
    g.ring:SetPoint("CENTER")

    g.fill = g:CreateTexture(nil, "OVERLAY")
    g.fill:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    g.fill:SetBlendMode("ADD")
    g.fill:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
    g.fill:SetAllPoints()

    -- solid gold border, which shows even if a texture file is missing on this client
    Edge(g, "TOPLEFT", "TOPRIGHT", true)
    Edge(g, "BOTTOMLEFT", "BOTTOMRIGHT", true)
    Edge(g, "TOPLEFT", "BOTTOMLEFT", false)
    Edge(g, "TOPRIGHT", "BOTTOMRIGHT", false)

    g.pulse = g:CreateAnimationGroup()
    g.pulse:SetLooping("BOUNCE")
    local a = g.pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.3)
    a:SetDuration(0.35)

    g:Hide()
    glows[btn] = g
    return g
end

-- Which spells should glow: Overpower (from the nameplate code) and any reactive
-- ability that's up (Reactive.lua). Every matching button is lit, the rest cleared.
local glowOverpower = false
local reactive = {} -- [key] = { name =, ids = } that are up

local function UpdateGlows()
    local specs = {}
    if glowOverpower then specs[#specs + 1] = { name = ns.OVERPOWER_NAME, ranks = { 7384, 7887, 11584, 11585 } } end
    for _, r in pairs(reactive) do specs[#specs + 1] = { name = r.name, ranks = r.ids } end
    local lit = {}
    if #specs > 0 then
        for _, spec in ipairs(specs) do
            spec.ids, spec.idSet = SpellIDs(spec.name, spec.ranks)
            spec.slots = SpellSlots(spec.ids)
        end
        for _, btn in ipairs(AllButtons()) do
            if btn:IsVisible() then
                for _, spec in ipairs(specs) do
                    if IsSpellButton(btn, spec.slots, spec.idSet, spec.name) then
                        lit[btn] = true
                        local g = GetGlow(btn)
                        local w = btn:GetWidth() or 36
                        g.ring:SetSize(w * 1.75, w * 1.75)
                        if not g:IsShown() then
                            g:Show()
                            g.pulse:Play()
                        end
                        break
                    end
                end
            end
        end
    end
    for btn, g in pairs(glows) do
        if not lit[btn] and g:IsShown() then
            g.pulse:Stop()
            g:Hide()
        end
    end
end

-- Light or clear every Overpower button.
function ns.SetButtonGlow(on)
    glowOverpower = on and true or false
    UpdateGlows()
end

-- key = "revenge" etc.; spec = { name, ids } while it's up, nil to clear
function ns.SetReactiveGlow(key, spec)
    if (reactive[key] ~= nil) == (spec ~= nil) then return end
    reactive[key] = spec
    UpdateGlows()
end

-- /opp debug: what the button search sees
function ns.GlowDebug()
    local ids, idSet = OverpowerIDs()
    local slots = OverpowerSlots(ids)
    local slotList = {}
    for slot in pairs(slots) do slotList[#slotList + 1] = slot end
    table.sort(slotList)
    local buttons, visible, noSlot, found = AllButtons(), 0, 0, {}
    for _, btn in ipairs(buttons) do
        if btn:IsVisible() then
            visible = visible + 1
            if not ButtonSlot(btn) then noSlot = noSlot + 1 end
            if IsOverpowerButton(btn, slots, idSet) then found[#found + 1] = btn:GetName() or "?" end
        end
    end
    local idList = {}
    for _, id in ipairs(ids) do idList[#idList + 1] = tostring(id) end
    return {
        ("spell: %s, IDs %s"):format(tostring(ns.OVERPOWER_NAME), table.concat(idList, ", ")),
        ("game says Overpower is in action slots: %s"):format(#slotList > 0 and table.concat(slotList, ", ")
            or (C_ActionBar and C_ActionBar.FindSpellActionButtons and "none" or "can't ask on this client")),
        ("action buttons: %d found, %d visible, %d with no readable slot; GetActionInfo %s"):format(
            #buttons, visible, noSlot, (GetActionInfo or (C_ActionBar and C_ActionBar.GetActionInfo)) and "works" or "missing"),
        ("Overpower buttons: %s"):format(#found > 0 and table.concat(found, ", ") or "none found"),
    }
end

---------------------------------------------------------------------------
-- Big icon in the middle of the screen
---------------------------------------------------------------------------
local screen = CreateFrame("Frame", "OverpowerPlatesScreenIcon", UIParent)
screen:SetFrameStrata("HIGH")
screen:SetClampedToScreen(true)
screen:SetMovable(true)
screen:Hide()

screen.glow = screen:CreateTexture(nil, "BACKGROUND")
screen.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
screen.glow:SetBlendMode("ADD")
screen.glow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
screen.glow:SetPoint("CENTER")

screen.border = screen:CreateTexture(nil, "BORDER")
screen.border:SetPoint("TOPLEFT", -2, 2)
screen.border:SetPoint("BOTTOMRIGHT", 2, -2)
screen.border:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)

screen.tex = screen:CreateTexture(nil, "ARTWORK")
screen.tex:SetAllPoints()
screen.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

screen.cd = CreateFrame("Cooldown", nil, screen, "CooldownFrameTemplate")
screen.cd:SetAllPoints()
if screen.cd.SetDrawEdge then screen.cd:SetDrawEdge(false) end

screen.count = screen:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
screen.count:SetPoint("BOTTOMRIGHT", -3, 3)

screen.label = screen:CreateFontString(nil, "OVERLAY", "GameFontNormal")
screen.label:SetPoint("TOP", screen, "BOTTOM", 0, -4)

screen.pulse = screen:CreateAnimationGroup()
screen.pulse:SetLooping("BOUNCE")
do
    local a = screen.pulse:CreateAnimation("Alpha")
    a:SetTarget(screen.glow)
    a:SetFromAlpha(1)
    a:SetToAlpha(0.2)
    a:SetDuration(0.35)
end

screen.pop = screen:CreateAnimationGroup()
do
    local grow = screen.pop:CreateAnimation("Scale")
    if grow.SetScaleFrom then
        grow:SetScaleFrom(1.5, 1.5)
        grow:SetScaleTo(1, 1)
    else
        grow:SetScale(0.67, 0.67)
    end
    grow:SetDuration(0.18)
    grow:SetSmoothing("OUT")
end

screen:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" and ns.screenUnlocked then self:StartMoving() end
end)
screen:SetScript("OnMouseUp", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint()
    if ns.db and point then ns.db.screenPos = { point = point, x = x, y = y } end
end)

local function Place()
    local db = ns.db
    screen:SetSize(db.screenSize, db.screenSize)
    screen.glow:SetSize(db.screenSize * 1.8, db.screenSize * 1.8)
    screen.tex:SetTexture(ns.OVERPOWER_ICON)
    screen:ClearAllPoints()
    local p = db.screenPos
    if p and p.point then
        screen:SetPoint(p.point, UIParent, p.point, p.x or 0, p.y or 0)
    else
        screen:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
    end
end

function ns.ResetScreenIcon()
    if ns.db then ns.db.screenPos = nil end
    Place()
end

-- expires: when the newest Overpower window closes (nil = nothing up)
function ns.UpdateScreenIcon(expires, charges)
    local db = ns.db
    if not db then return end
    local show = (db.screenIcon and expires ~= nil) or ns.screenUnlocked
    if not show then
        if screen:IsShown() then screen.pulse:Stop(); screen:Hide() end
        return
    end
    Place()
    screen:EnableMouse(ns.screenUnlocked and true or false)
    if expires then
        screen.cd:SetCooldown(expires - db.window, db.window)
    else
        screen.cd:Clear()
    end
    screen.count:SetText((charges and charges > 1) and charges or "")
    screen.label:SetText(ns.screenUnlocked and "Drag to move" or "")
    if not screen:IsShown() then
        screen:Show()
        if db.pop then screen.pop:Stop(); screen.pop:Play() end
        screen.pulse:Play()
    end
end

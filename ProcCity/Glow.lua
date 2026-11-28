-- Proc City: lights your action buttons for the abilities it shows: Overpower, Revenge,
-- Victory Rush, Riposte, Counterattack and Mongoose Bite while they're up. A gold glow and border laid over the button as its own frame, so the
-- action buttons themselves are never touched (they're protected in combat).
-- (From Overpower Plates / Proc Plates, now part of Proc City.)

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

-- Light every button for the procs that are up and have a glow; clear the rest.
local litFor = ""
local function UpdateGlows(force)
    local db = ns.db
    local specs, sig = {}, {}
    if db and db.glowButtons and ns.Active then
        for key, a in pairs(ns.Active()) do
            local p = a.proc
            if p and p.glow and (not a.expires or a.expires > GetTime()) then
                local g = p.glow == true and { name = p.name, ids = p.ids } or p.glow
                specs[#specs + 1] = { name = g.name, ranks = g.ids }
                sig[#sig + 1] = key
            end
        end
    end
    table.sort(sig)
    local now = table.concat(sig, ",")
    if now == litFor and not force then return end
    litFor = now
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
ns.UpdateGlows = UpdateGlows

-- /proc debug: where a spell's buttons are
function ns.GlowDebug(name, ranks)
    local ids, idSet = SpellIDs(name, ranks)
    local slots = SpellSlots(ids)
    local slotList = {}
    for slot in pairs(slots) do slotList[#slotList + 1] = slot end
    table.sort(slotList)
    local found = {}
    for _, btn in ipairs(AllButtons()) do
        if btn:IsVisible() and IsSpellButton(btn, slots, idSet, name) then found[#found + 1] = btn:GetName() or "?" end
    end
    return ("%s: action slots %s, buttons %s"):format(name,
        #slotList > 0 and table.concat(slotList, ", ") or "none",
        #found > 0 and table.concat(found, ", ") or "none found")
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "ACTIONBAR_SLOT_CHANGED", "UPDATE_SHAPESHIFT_FORM" }) do
    pcall(ev.RegisterEvent, ev, e)
end
-- stance swaps page the bars, so the button may have moved
ev:SetScript("OnEvent", function() if litFor ~= "" then UpdateGlows(true) end end)
if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(0.2, function() UpdateGlows() end) end

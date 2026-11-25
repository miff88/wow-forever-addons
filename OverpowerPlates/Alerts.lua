-- Overpower Plates: the louder alerts.
--   * a gold glow on your Overpower button on the action bars while Overpower is up
--   * an optional big Overpower icon in the middle of the screen, with a countdown sweep
-- The glow is its own frame laid over the button, so the action buttons themselves are
-- never touched (they're protected in combat).

local _, ns = ...

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local GOLD = { 1, 0.82, 0.1 }

---------------------------------------------------------------------------
-- Action buttons: Blizzard bars, plus Bartender4 and ElvUI
---------------------------------------------------------------------------
local function AllButtons()
    local list = {}
    local function add(name)
        local b = _G[name]
        if b then list[#list + 1] = b end
    end
    for _, prefix in ipairs({ "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
                              "MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button",
                              "MultiBar6Button", "MultiBar7Button" }) do
        for i = 1, 12 do add(prefix .. i) end
    end
    for i = 1, 180 do add("BT4Button" .. i) end
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

local function ButtonSpell(btn)
    local slot
    if btn.GetAction then
        local ok, kind, action = pcall(btn.GetAction, btn)
        if ok and kind == "action" then slot = action end
    end
    slot = slot or btn.action
    if not slot and btn.CalculateAction then
        local ok, a = pcall(btn.CalculateAction, btn)
        if ok then slot = a end
    end
    if not slot or IsSecret(slot) or not GetActionInfo then return end

    local ok, kind, id = pcall(GetActionInfo, slot)
    if not ok or IsSecret(kind) or IsSecret(id) then return end
    if kind == "macro" and GetMacroSpell then
        local ok2, spellID = pcall(GetMacroSpell, id)
        if ok2 and spellID and not IsSecret(spellID) then kind, id = "spell", spellID end
    end
    if kind ~= "spell" or not id then return end
    return SpellName(id)
end

local glows = {} -- [button] = glow frame

local function GetGlow(btn)
    local g = glows[btn]
    if g then return g end

    g = CreateFrame("Frame", nil, UIParent)
    g:SetFrameStrata("HIGH")
    g:SetPoint("CENTER", btn, "CENTER")

    g.ring = g:CreateTexture(nil, "OVERLAY")
    g.ring:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    g.ring:SetBlendMode("ADD")
    g.ring:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
    g.ring:SetAllPoints()

    g.fill = g:CreateTexture(nil, "OVERLAY")
    g.fill:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    g.fill:SetBlendMode("ADD")
    g.fill:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
    g.fill:SetPoint("TOPLEFT", btn, "TOPLEFT")
    g.fill:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT")

    g.pulse = g:CreateAnimationGroup()
    g.pulse:SetLooping("BOUNCE")
    local a = g.pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.25)
    a:SetDuration(0.35)

    g:Hide()
    glows[btn] = g
    return g
end

-- Light or clear every visible Overpower button.
function ns.SetButtonGlow(on)
    local lit = {}
    if on then
        for _, btn in ipairs(AllButtons()) do
            if btn:IsVisible() and ButtonSpell(btn) == ns.OVERPOWER_NAME then
                lit[btn] = true
                local g = GetGlow(btn)
                local w = btn:GetWidth() or 36
                g:SetSize(w * 1.75, w * 1.75)
                if not g:IsShown() then
                    g:Show()
                    g.pulse:Play()
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

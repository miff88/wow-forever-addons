-- Mage Services: on-screen alerts.
--   * glows the matching Portal / Conjure button on your action bars
--   * shows a short message at the top of the screen
--   * flashes the edges of the screen
-- Nothing here touches the action buttons themselves: the glow is a separate frame laid
-- over the button, so it can't interfere with casting, in or out of combat.

local ADDON_NAME, ns = ...

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, id)
        if ok and type(name) == "string" and not IsSecret(name) then return name end
    end
end

---------------------------------------------------------------------------
-- Which spells answer a request
---------------------------------------------------------------------------
local function Wants(req, name)
    local kind = req.info.kind
    if kind == "port" then
        if req.info.dest then return name == "Portal: " .. req.info.dest end
        return name:find("^Portal: ") ~= nil
    elseif kind == "water" then
        return name:find("^Conjure Water") ~= nil or name:find("^Conjure Food") ~= nil
            or name:find("^Conjure Refreshment") ~= nil
    end
    return false
end

---------------------------------------------------------------------------
-- Action buttons: Blizzard bars, plus Bartender4 and ElvUI (both use LibActionButton)
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

---------------------------------------------------------------------------
-- Button glow
---------------------------------------------------------------------------
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
    g.ring:SetVertexColor(0.41, 0.8, 0.94)
    g.ring:SetAllPoints()

    g.fill = g:CreateTexture(nil, "OVERLAY")
    g.fill:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    g.fill:SetBlendMode("ADD")
    g.fill:SetVertexColor(0.41, 0.8, 0.94)
    g.fill:SetPoint("TOPLEFT", btn, "TOPLEFT")
    g.fill:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT")

    g.pulse = g:CreateAnimationGroup()
    g.pulse:SetLooping("BOUNCE")
    local a = g.pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.25)
    a:SetDuration(0.45)

    g:Hide()
    glows[btn] = g
    return g
end

local function ShowGlow(btn)
    local g = GetGlow(btn)
    local w = btn:GetWidth() or 36
    g:SetSize(w * 1.75, w * 1.75)
    if not g:IsShown() then
        g:Show()
        g.pulse:Play()
    end
end

local function HideGlow(g)
    if g:IsShown() then
        g.pulse:Stop()
        g:Hide()
    end
end

-- Called whenever the request list refreshes.
function ns.UpdateGlows(visible)
    local db = ns.db
    if not db then return end

    local active = {}
    if db.glowBar then
        local now = GetTime()
        for _, req in ipairs(visible) do
            if (req.priority or 2) > 1 or db.alertLow then
                if now - req.time <= db.glowTime then active[#active + 1] = req end
            end
        end
    end

    local lit = {}
    if #active > 0 then
        for _, btn in ipairs(AllButtons()) do
            if btn:IsVisible() then
                local name = ButtonSpell(btn)
                if name then
                    for _, req in ipairs(active) do
                        if Wants(req, name) then
                            lit[btn] = true
                            ShowGlow(btn)
                            break
                        end
                    end
                end
            end
        end
    end

    for btn, g in pairs(glows) do
        if not lit[btn] then HideGlow(g) end
    end
end

---------------------------------------------------------------------------
-- Message at the top of the screen
---------------------------------------------------------------------------
local banner = CreateFrame("Frame", "MageServicesBanner", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
banner:SetSize(520, 60)
banner:SetPoint("TOP", UIParent, "TOP", 0, -170)
banner:SetFrameStrata("HIGH")
banner:Hide()

banner.icon = banner:CreateTexture(nil, "ARTWORK")
if banner.SetBackdrop then
    banner:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
end

banner.icon:SetSize(44, 44)
banner.icon:SetPoint("LEFT", 8, 0)
banner.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

banner.text = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
banner.text:SetPoint("BOTTOMLEFT", banner.icon, "RIGHT", 10, 3)
banner.text:SetTextColor(0.41, 0.8, 0.94)
banner.text:SetWordWrap(false)

banner.sub = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
banner.sub:SetPoint("TOPLEFT", banner.icon, "RIGHT", 10, -5)
banner.sub:SetWidth(520)
banner.sub:SetJustifyH("LEFT")
banner.sub:SetWordWrap(false)

banner.anim = banner:CreateAnimationGroup()
local bIn = banner.anim:CreateAnimation("Alpha")
bIn:SetFromAlpha(0); bIn:SetToAlpha(1); bIn:SetDuration(0.15); bIn:SetOrder(1)
local bOut = banner.anim:CreateAnimation("Alpha")
bOut:SetFromAlpha(1); bOut:SetToAlpha(0); bOut:SetDuration(0.7); bOut:SetStartDelay(3); bOut:SetOrder(2)
banner.anim:SetScript("OnFinished", function() banner:Hide() end)

function ns.ApplyBannerTheme(t)
    if banner.SetBackdropColor then
        banner:SetBackdropColor(t.bg[1], t.bg[2], t.bg[3], 0.9)
        banner:SetBackdropBorderColor(t.border[1], t.border[2], t.border[3], 1)
    end
    banner.text:SetTextColor(t.title[1], t.title[2], t.title[3])
    banner.sub:SetTextColor(t.text[1], t.text[2], t.text[3])
    local sh = t.shadow and 1 or 0
    banner.text:SetShadowOffset(sh, -sh)
    banner.sub:SetShadowOffset(sh, -sh)
end

-- Size the panel to its content so it stays centred on screen.
local function FitBanner()
    local w = math.max(banner.text:GetStringWidth() or 0, math.min(banner.sub:GetStringWidth() or 0, 520))
    banner:SetWidth(8 + 44 + 10 + w + 14)
end

---------------------------------------------------------------------------
-- Screen edge flash
---------------------------------------------------------------------------
local edge = CreateFrame("Frame", "MageServicesEdgeFlash", UIParent)
edge:SetAllPoints(UIParent)
edge:SetFrameStrata("BACKGROUND")
edge:Hide()

edge.tex = edge:CreateTexture(nil, "BACKGROUND")
edge.tex:SetAllPoints()
edge.tex:SetTexture("Interface\\FullScreenTextures\\LowHealth")
edge.tex:SetBlendMode("ADD")
edge.tex:SetVertexColor(0.3, 0.6, 1)

edge.anim = edge:CreateAnimationGroup()
for i = 1, 4 do
    local a = edge.anim:CreateAnimation("Alpha")
    local rising = (i % 2 == 1)
    a:SetFromAlpha(rising and 0 or 0.9)
    a:SetToAlpha(rising and 0.9 or 0)
    a:SetDuration(rising and 0.18 or 0.45)
    a:SetOrder(i)
end
edge.anim:SetScript("OnFinished", function() edge:Hide() end)

---------------------------------------------------------------------------
-- Called for each new request worth alerting on
---------------------------------------------------------------------------
function ns.ScreenAlert(req)
    local db = ns.db
    if not db or not req then return end

    if db.screenMsg then
        banner.icon:SetTexture(req.info.icon)
        banner.text:SetText(req.info.label .. "  -  " .. req.short)
        local reason = req.reason and ("(" .. req.reason .. ")  ") or ""
        banner.sub:SetText(reason .. req.msg)
        FitBanner()
        banner.anim:Stop()
        banner:SetAlpha(1)
        banner:Show()
        banner.anim:Play()
    end

    if db.edgeFlash then
        edge.anim:Stop()
        edge:Show()
        edge.anim:Play()
    end
end

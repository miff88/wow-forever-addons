-- Craft Services: on-screen alerts.
--   * shows a short message at the top of the screen
--   * flashes the edges of the screen

local ADDON_NAME, ns = ...

---------------------------------------------------------------------------
-- Message at the top of the screen
---------------------------------------------------------------------------
local banner = CreateFrame("Frame", "CraftServicesBanner", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
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
banner.text:SetTextColor(0.96, 0.66, 0.24)
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
local edge = CreateFrame("Frame", "CraftServicesEdgeFlash", UIParent)
edge:SetAllPoints(UIParent)
edge:SetFrameStrata("BACKGROUND")
edge:Hide()

edge.tex = edge:CreateTexture(nil, "BACKGROUND")
edge.tex:SetAllPoints()
edge.tex:SetTexture("Interface\\FullScreenTextures\\LowHealth")
edge.tex:SetBlendMode("ADD")
edge.tex:SetVertexColor(1, 0.6, 0.2)

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
        banner.icon:SetTexture((req.info.recipe and req.info.recipe.icon) or req.info.icon or ns.ICONS.craft)
        banner.text:SetText(req.info.label .. "  -  " .. req.display)
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

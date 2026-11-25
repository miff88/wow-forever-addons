-- Mage Services: the portal button and payment receipts.
--
-- Portal button: one secure spell button (the big icon at the top-left of the window)
-- that casts the portal for the selected request, or Conjure Water for a water request.
-- The top request is selected automatically; click a row to pick another. Secure buttons
-- can't be changed in combat, so it updates as soon as combat ends.
--
-- Payment receipts: when you trade with a customer, posts what happened in party chat
-- (or whispers them if they've left the group): payment received, cancelled, failed,
-- or completed with no payment.

local ADDON_NAME, ns = ...

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

---------------------------------------------------------------------------
-- Portal button
---------------------------------------------------------------------------
local cast = CreateFrame("Button", "MageServicesCastButton", UIParent, "SecureActionButtonTemplate")
cast:SetSize(40, 40)
cast:SetFrameStrata("MEDIUM")
cast:SetClampedToScreen(true)
cast:SetMovable(true)
cast:RegisterForClicks("AnyUp", "AnyDown")
cast:SetAttribute("type", "spell")
cast:Hide()

cast.icon = cast:CreateTexture(nil, "ARTWORK")
cast.icon:SetAllPoints()
cast.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

-- 1px frame in the window's border colour, so the button and window read as one piece
cast.border = cast:CreateTexture(nil, "BACKGROUND")
cast.border:SetPoint("TOPLEFT", -1, 1)
cast.border:SetPoint("BOTTOMRIGHT", 1, -1)
cast.border:SetColorTexture(0.41, 0.8, 0.94, 1)

cast.hl = cast:CreateTexture(nil, "HIGHLIGHT")
cast.hl:SetAllPoints()
cast.hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
cast.hl:SetBlendMode("ADD")

-- destination name inside the bottom of the icon, like a macro name on an action button
cast.strip = cast:CreateTexture(nil, "OVERLAY")
cast.strip:SetPoint("BOTTOMLEFT")
cast.strip:SetPoint("BOTTOMRIGHT")
cast.strip:SetHeight(12)
cast.strip:SetColorTexture(0, 0, 0, 0.6)

cast.label = cast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
cast.label:SetPoint("BOTTOMLEFT", 1, 1)
cast.label:SetPoint("BOTTOMRIGHT", -1, 1)
cast.label:SetHeight(11)
cast.label:SetWordWrap(false)
pcall(cast.label.SetFont, cast.label, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 9, "OUTLINE")

function ns.ApplyCastTheme(t)
    cast.border:SetColorTexture(t.border[1], t.border[2], t.border[3], 1)
end

cast:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.spell then
        GameTooltip:AddLine("Cast " .. self.spell, 0.41, 0.8, 0.94)
        if self.req then GameTooltip:AddLine("For " .. self.req.short .. ": " .. self.req.msg, 1, 1, 1, true) end
        GameTooltip:AddLine("Click a row in the list to pick a different request. Drag to move.", 0.7, 0.7, 0.7, true)
    else
        GameTooltip:AddLine("No request selected")
    end
    GameTooltip:Show()
end)
cast:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Dragging the icon or the window moves both (out of combat only).
local function StartMove()
    if not InCombatLockdown() then cast:StartMoving() end
end
local function StopMove()
    cast:StopMovingOrSizing()
    local p, _, rp, x, y = cast:GetPoint()
    if ns.db and p then ns.db.point = { p, rp, x, y } end
end
cast:RegisterForDrag("LeftButton")
cast:SetScript("OnDragStart", StartMove)
cast:SetScript("OnDragStop", StopMove)

function ns.PositionCast()
    local win = ns.win
    if InCombatLockdown() then return end
    cast:ClearAllPoints()
    local p = ns.db.point
    cast:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    win:ClearAllPoints()
    win:SetPoint("TOPLEFT", cast, "TOPRIGHT", 5, 1) -- tops line up, borders included
    win:SetScript("OnDragStart", StartMove)
    win:SetScript("OnDragStop", StopMove)
end

local function SpellFor(req)
    if not req then return nil end
    if req.info.kind == "port" and req.info.dest then return "Portal: " .. req.info.dest end
    if req.info.kind == "water" then return "Conjure Water" end
    return nil
end

local function IconFor(spell, req)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, spell)
        if ok and tex and not IsSecret(tex) then return tex end
    end
    return req.info.icon
end

function ns.Select(req)
    if not req then return end
    for _, r in ipairs(ns.requests) do r.selected = nil end
    req.selected = true
    ns.Refresh()
end

local pendingUpdate = false

-- Called from Refresh with the list as shown.
function ns.UpdateCastButton(visible)
    if InCombatLockdown() then
        pendingUpdate = true
        return
    end
    pendingUpdate = false

    -- the picked request, or the top one that has a spell
    local chosen
    for _, r in ipairs(visible) do
        if r.selected and SpellFor(r) then chosen = r break end
    end
    if not chosen then
        for _, r in ipairs(visible) do
            if SpellFor(r) and r.priority > 1 then chosen = r break end
        end
    end
    if not chosen then
        for _, r in ipairs(visible) do
            if SpellFor(r) then chosen = r break end
        end
    end

    local spell = SpellFor(chosen)
    cast.req, cast.spell = chosen, spell
    if spell then
        cast:SetAttribute("spell", spell)
        cast.icon:SetTexture(IconFor(spell, chosen))
        cast.icon:SetDesaturated(false)
        local short = { ["Thunder Bluff"] = "TB", Undercity = "UC", Orgrimmar = "Org",
                        Stormwind = "SW", Ironforge = "IF", Darnassus = "Darn" }
        cast.label:SetText(short[chosen.info.dest] or chosen.info.dest or "Water")
        cast.strip:Show()
    else
        cast:SetAttribute("spell", nil)
        cast.icon:SetTexture(ns.ICONS.port)
        cast.icon:SetDesaturated(true)
        cast.label:SetText("")
        cast.strip:Hide()
    end

    if #visible > 0 then cast:Show() else cast:Hide() end
end

---------------------------------------------------------------------------
-- Payment receipts
---------------------------------------------------------------------------
local trade      -- { name, money, items = {}, done }
ns.customers = {} -- [short name] = { time, kind, dest } from their latest request

local CUSTOMER_WINDOW = 30 * 60 -- a request counts for 30 minutes

local function Money(copper)
    copper = copper or 0
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end
ns.Money = Money

local function IsCustomer(name)
    if not name then return false end
    if ns.db.receiptAll then return true end
    if UnitInParty and UnitInParty(name) then return true end
    if UnitInRaid and UnitInRaid(name) then return true end
    local c = ns.customers[name]
    return c ~= nil and GetTime() - c.time < CUSTOMER_WINDOW
end

local function SendChat(text, chatType, target)
    if C_ChatInfo and C_ChatInfo.SendChatMessage then
        return pcall(C_ChatInfo.SendChatMessage, text, chatType, nil, target)
    elseif SendChatMessage then
        return pcall(SendChatMessage, text, chatType, nil, target)
    end
    return false
end

local function OpenChat(line)
    if ChatFrameUtil and ChatFrameUtil.OpenChat then
        ChatFrameUtil.OpenChat(line)
    elseif ChatFrame_OpenChat then
        ChatFrame_OpenChat(line)
    end
end

-- Party chat if they're still in the group, otherwise a whisper.
local function Post(name, text)
    local mode = ns.db.receiptMode
    if mode == "off" then return end

    local chatType, slash, target = "WHISPER", "/w " .. name .. " ", name
    if IsInRaid and IsInRaid() and UnitInRaid and UnitInRaid(name) then
        chatType, slash, target = "RAID", "/ra ", nil
    elseif UnitInParty and UnitInParty(name) then
        chatType, slash, target = "PARTY", "/p ", nil
    end

    if mode == "prefill" then
        OpenChat(slash .. text)
        return
    end
    local ok = SendChat(text, chatType, target)
    if not ok then OpenChat(slash .. text) end -- couldn't send: leave it ready to press Enter
end

local function Fill(template, name, extra)
    local out = template:gsub("{name}", name)
    for k, v in pairs(extra or {}) do out = out:gsub("{" .. k .. "}", v) end
    return out
end

local function ItemsText(items)
    if #items == 0 then return "" end
    local parts = {}
    for _, it in ipairs(items) do
        parts[#parts + 1] = (it.count and it.count > 1) and (it.count .. "x " .. it.name) or it.name
    end
    return table.concat(parts, ", ")
end

local function ReadTrade()
    if not trade then return end
    if GetTargetTradeMoney then
        local ok, m = pcall(GetTargetTradeMoney)
        if ok and type(m) == "number" and not IsSecret(m) then trade.money = m end
    end
    local items = {}
    if GetTradeTargetItemInfo then
        for i = 1, 6 do
            local ok, name, _, count = pcall(GetTradeTargetItemInfo, i)
            if ok and type(name) == "string" and not IsSecret(name) then
                items[#items + 1] = { name = name, count = count }
            end
        end
    end
    trade.items = items
end

---------------------------------------------------------------------------
-- Earnings (per character, plus this session)
---------------------------------------------------------------------------
local function NewTotals()
    return { total = 0, port = 0, water = 0, other = 0, count = { port = 0, water = 0, other = 0 }, dest = {} }
end
ns.session = NewTotals()

function ns.InitEarnings()
    MageServicesCharDB = MageServicesCharDB or {}
    MageServicesCharDB.earnings = MageServicesCharDB.earnings or NewTotals()
    local e = MageServicesCharDB.earnings
    for k, v in pairs(NewTotals()) do if e[k] == nil then e[k] = v end end
    ns.earnings = e
end

local function AddTo(t, kind, dest, copper)
    t.total = t.total + copper
    t[kind] = (t[kind] or 0) + copper
    t.count[kind] = (t.count[kind] or 0) + 1
    if kind == "port" and dest then t.dest[dest] = (t.dest[dest] or 0) + copper end
end

local function RecordEarning(name, copper)
    if not copper or copper <= 0 or not ns.earnings then return end
    local c = ns.customers[name]
    local kind = c and c.kind or "other"
    if kind ~= "port" and kind ~= "water" then kind = "other" end
    local dest = c and c.dest
    AddTo(ns.earnings, kind, dest, copper)
    AddTo(ns.session, kind, dest, copper)
end

-- One-line summary for the bottom of the window.
function ns.EarningsLine()
    local e, s = ns.earnings, ns.session
    if not e then return "" end
    local muted = ns.Theme and ns.Theme().muted or "aaaaaa"
    return ("Earned %s  |cff%s(portals %s, water %s)   this session %s|r"):format(
        Money(e.total), muted, Money(e.port), Money(e.water), Money(s.total))
end

-- Longer breakdown for chat and the settings page.
function ns.EarningsLines()
    local e, s = ns.earnings, ns.session
    if not e then return {} end
    local lines = {
        ("Total: %s   This session: %s"):format(Money(e.total), Money(s.total)),
        ("Portals: %s from %d   Water/food: %s from %d   Other: %s from %d"):format(
            Money(e.port), e.count.port or 0, Money(e.water), e.count.water or 0, Money(e.other), e.count.other or 0),
    }
    local cities = {}
    for name, copper in pairs(e.dest) do cities[#cities + 1] = { name = name, copper = copper } end
    table.sort(cities, function(a, b) return a.copper > b.copper end)
    if #cities > 0 then
        local parts = {}
        for _, c in ipairs(cities) do parts[#parts + 1] = c.name .. " " .. Money(c.copper) end
        lines[#lines + 1] = "Portals by city: " .. table.concat(parts, ", ")
    end
    return lines
end

function ns.ResetEarnings()
    MageServicesCharDB.earnings = NewTotals()
    ns.earnings = MageServicesCharDB.earnings
    ns.session = NewTotals()
end

local function MarkPaid(name, copper)
    for _, r in ipairs(ns.requests) do
        if r.short == name then r.paid = copper end
    end
    ns.Refresh()
end

local function Finish(result, reason)
    if not trade or trade.done then return end
    trade.done = true
    local name, db = trade.name, ns.db
    if not name or not IsCustomer(name) then trade = nil return end

    if result == "complete" then
        local itemsText = ItemsText(trade.items or {})
        if (trade.money or 0) > 0 or itemsText ~= "" then
            local paid = Money(trade.money)
            if (trade.money or 0) == 0 then paid = itemsText
            elseif itemsText ~= "" then paid = paid .. " + " .. itemsText end
            Post(name, Fill(db.paidMsg, name, { amount = paid }))
            if not trade.test then RecordEarning(name, trade.money or 0) end
            MarkPaid(name, trade.money or 0)
            ns.Print("payment from " .. name .. ": " .. paid)
        else
            Post(name, Fill(db.noPayMsg, name))
        end
    elseif result == "cancelled" then
        Post(name, Fill(db.cancelMsg, name))
    else
        Post(name, Fill(db.failMsg, name, { reason = (reason or "unknown reason"):gsub("%.%s*$", "") }))
    end
    trade = nil
end

-- Any of the game's ERR_TRADE_* messages counts as a failed trade.
local tradeErrors
function ns.IsTradeError(msg)
    if not tradeErrors then
        tradeErrors = {}
        for k, v in pairs(_G) do
            if type(k) == "string" and k:find("^ERR_TRADE_") and type(v) == "string"
                and k ~= "ERR_TRADE_COMPLETE" and k ~= "ERR_TRADE_CANCELLED" then
                local pattern = "^" .. v:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", ".+"):gsub("%%%%d", "%%d+") .. "$"
                tradeErrors[#tradeErrors + 1] = pattern
            end
        end
    end
    for _, pat in ipairs(tradeErrors) do
        if msg:find(pat) then return true end
    end
    return msg:lower():find("trade") ~= nil
end

local ev = CreateFrame("Frame")
local function SafeRegister(e) return pcall(ev.RegisterEvent, ev, e) end
for _, e in ipairs({ "TRADE_SHOW", "TRADE_MONEY_CHANGED", "TRADE_TARGET_ITEM_CHANGED", "TRADE_ACCEPT_UPDATE",
                     "TRADE_CLOSED", "TRADE_REQUEST_CANCEL", "UI_INFO_MESSAGE", "UI_ERROR_MESSAGE",
                     "PLAYER_REGEN_ENABLED" }) do
    SafeRegister(e)
end

ev:SetScript("OnEvent", function(_, event, arg1, arg2)
    if not ns.db then return end

    if event == "PLAYER_REGEN_ENABLED" then
        if pendingUpdate then ns.Refresh() end

    elseif event == "TRADE_SHOW" then
        local name = UnitName and UnitName("NPC")
        if IsSecret(name) then name = nil end
        trade = { name = name, money = 0, items = {} }
        ReadTrade()

    elseif event == "TRADE_MONEY_CHANGED" or event == "TRADE_TARGET_ITEM_CHANGED" or event == "TRADE_ACCEPT_UPDATE" then
        ReadTrade()

    elseif event == "UI_INFO_MESSAGE" then
        -- arg2 = message text
        if trade and arg2 == ERR_TRADE_COMPLETE then Finish("complete") end

    elseif event == "UI_ERROR_MESSAGE" then
        if trade and type(arg2) == "string" and not IsSecret(arg2) then
            if arg2 == ERR_TRADE_CANCELLED then
                Finish("cancelled")
            elseif ns.IsTradeError(arg2) then
                Finish("failed", arg2)
            end
        end

    elseif event == "TRADE_REQUEST_CANCEL" then
        if trade then Finish("cancelled") end

    elseif event == "TRADE_CLOSED" then
        -- the complete/cancel message can arrive just after the window closes
        local t = trade
        if t then
            C_Timer.After(0.6, function()
                if trade == t and not t.done then Finish("cancelled") end
            end)
        end
    end
end)

-- For /ms test-trade: run a fake trade through the same path.
function ns.TestTrade(result)
    trade = { name = "Testbuyer", money = 15000, items = { { name = "Silk Cloth", count = 5 } }, test = true }
    ns.customers.Testbuyer = { time = GetTime(), kind = "port", dest = "Undercity" }
    local mode = ns.db.receiptMode
    ns.db.receiptMode = "prefill" -- never send a real message from a test
    if result == "complete" then Finish("complete")
    elseif result == "failed" then Finish("failed", "Target is too far away.")
    else Finish("cancelled") end
    ns.db.receiptMode = mode
end

-- Craft Services: the profession button, payment receipts and earnings.
--
-- Profession button: the big icon at the top-left of the window. For the selected request
-- it opens your profession at the recipe they asked for, opens the profession when they
-- didn't name one, or casts Pick Lock for a lockbox. The top request is selected
-- automatically; click a row to pick another. It's a secure button (it casts spells),
-- so it can't be changed in combat and updates once combat ends.
--
-- Payment receipts: when you trade with a customer, posts what happened in party chat
-- (or whispers them if they've left the group): payment received, cancelled, failed,
-- or completed with no payment. Each payment is added to your earnings, by profession
-- and by recipe, and to the customer's history.

local ADDON_NAME, ns = ...

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

---------------------------------------------------------------------------
-- Profession button
---------------------------------------------------------------------------
local cast = CreateFrame("Button", "CraftServicesCastButton", UIParent, "SecureActionButtonTemplate")
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
cast.border:SetColorTexture(0.96, 0.66, 0.24, 1)

cast.hl = cast:CreateTexture(nil, "HIGHLIGHT")
cast.hl:SetAllPoints()
cast.hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
cast.hl:SetBlendMode("ADD")

-- recipe name inside the bottom of the icon, like a macro name on an action button
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
        local e = self.req and self.req.info.recipe
        if self.action == "recipe" and e then
            GameTooltip:AddLine("Open " .. e.name, 0.96, 0.66, 0.24)
        elseif self.req and self.req.info.prof == "lockpicking" then
            GameTooltip:AddLine("Cast " .. self.spell, 0.96, 0.66, 0.24)
            GameTooltip:AddLine("Then click their box in the trade window.", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Open " .. self.spell, 0.96, 0.66, 0.24)
        end
        if self.req then GameTooltip:AddLine("For " .. self.req.display .. ": " .. self.req.msg, 1, 1, 1, true) end
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

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, id)
        if ok and type(name) == "string" and not IsSecret(name) then return name end
    end
end
ns.SpellName = SpellName

-- What the button does for a request:
--   "recipe", recipe   - opens your profession at that recipe
--   "spell", spellName - casts Pick Lock, or the profession's spell (opens its window)
local function ActionFor(req)
    if not req or req.info.kind ~= "craft" then return nil end
    local prof = ns.PROF_BY_KEY[req.info.prof]
    if not prof or not ns.Book.Has(prof.key) then return nil end
    if prof.key == "lockpicking" then return "spell", SpellName(prof.spellID) or prof.spell end
    local e = req.info.recipe
    if e and type(e.id) == "number" and C_TradeSkillUI and C_TradeSkillUI.OpenRecipe then return "recipe", e end
    local mine = ns.Book.MyProfs()[prof.key]
    return "spell", (mine and mine.spellID and SpellName(mine.spellID)) or (mine and mine.spellName) or prof.name
end
ns.ActionFor = ActionFor

local function SpellFor(req)
    local kind, what = ActionFor(req)
    if kind == "spell" then return what end
    if kind == "recipe" then return what.name end
end

-- Opens your profession window at a recipe (the same call the recipe tracker uses).
function ns.PickRecipe(e)
    if not e or type(e.id) ~= "number" then return false end
    if not (C_TradeSkillUI and C_TradeSkillUI.OpenRecipe) then return false end
    if not _G.ProfessionsFrame and ProfessionsFrame_LoadUI then pcall(ProfessionsFrame_LoadUI) end
    return (pcall(C_TradeSkillUI.OpenRecipe, e.id))
end

-- Opens a profession you have, when there's no recipe to go to.
function ns.OpenProfession(key)
    local prof = ns.PROF_BY_KEY[key]
    if not (prof and prof.skill and C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill) then return false end
    if not _G.ProfessionsFrame and ProfessionsFrame_LoadUI then pcall(ProfessionsFrame_LoadUI) end
    local ok, opened = pcall(C_TradeSkillUI.OpenTradeSkill, prof.skill)
    return ok and opened ~= false
end

-- A recipe request: the secure part does nothing (no spell set), and this opens the recipe.
cast:SetScript("PostClick", function(self)
    if self.action == "recipe" and self.recipe then ns.PickRecipe(self.recipe) end
end)

local function IconFor(spell, req)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, spell)
        if ok and tex and not IsSecret(tex) then return tex end
    end
    return req.info.icon
end

local function ShortLabel(req)
    local e = req.info.recipe
    if req.info.prof == "lockpicking" then return "Lockbox" end
    if e then
        local n = e.enchant and e.effect or e.callName or e.name
        return n
    end
    local prof = ns.PROF_BY_KEY[req.info.prof]
    return prof and prof.short or ""
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
    local action, what = ActionFor(chosen)
    cast.req, cast.spell, cast.action = chosen, spell, action
    cast.recipe = action == "recipe" and what or nil
    if spell then
        if action == "recipe" then
            cast:SetAttribute("type", nil)
            cast:SetAttribute("spell", nil)
        else
            cast:SetAttribute("type", "spell")
            cast:SetAttribute("spell", spell)
        end
        cast.icon:SetTexture((chosen.info.recipe and chosen.info.recipe.icon) or IconFor(spell, chosen))
        cast.icon:SetDesaturated(false)
        cast.label:SetText(ShortLabel(chosen))
        cast.strip:Show()
    else
        cast:SetAttribute("spell", nil)
        cast.icon:SetTexture(ns.ICONS.craft)
        cast.icon:SetDesaturated(true)
        cast.label:SetText("")
        cast.strip:Hide()
    end

    if #visible > 0 then cast:Show() else cast:Hide() end
end

---------------------------------------------------------------------------
-- Payment receipts
---------------------------------------------------------------------------
local trade      -- { key, sender, first, money, items = {}, gave = {}, slot7, done }
ns.customers = {} -- [name key] = { time, kind (profession), recipe, sender } from their latest request

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

local function IsCustomer(key)
    if not key or key == "" then return false end
    if ns.db.receiptAll then return true end
    if ns.InGroupWith(key) then return true end
    local c = ns.customers[key]
    return c ~= nil and GetTime() - c.time < CUSTOMER_WINDOW
end

-- Works out who you're trading with. If the game only gives a first name, it is matched
-- to a recent customer with that first name, but only when exactly one fits.
local function TradePartner()
    local full = ns.UnitFull("NPC")
    if not full then return nil end
    local key = ns.NameKey(full)
    if ns.customers[key] then
        return key, ns.customers[key].sender
    end
    if not full:find("[%s%-]") then
        local firstKey, found, foundKey = key, 0, nil
        for k in pairs(ns.customers) do
            if k:sub(1, #firstKey) == firstKey then found, foundKey = found + 1, k end
        end
        if found == 1 then return foundKey, ns.customers[foundKey].sender end
    end
    return key, full
end

local function SendChat(text, chatType, target)
    if C_ChatInfo and C_ChatInfo.SendChatMessage then
        return pcall(C_ChatInfo.SendChatMessage, text, chatType, nil, target)
    elseif SendChatMessage then
        return pcall(SendChatMessage, text, chatType, nil, target)
    end
    return false
end

ns.SendChat = SendChat

local function OpenChat(line)
    if ChatFrameUtil and ChatFrameUtil.OpenChat then
        ChatFrameUtil.OpenChat(line)
    elseif ChatFrame_OpenChat then
        ChatFrame_OpenChat(line)
    end
end

-- Party chat if they're still in the group, otherwise a whisper to their full name.
local function Post(t, text)
    local mode = ns.db.receiptMode
    if mode == "off" then return end

    local grouped = ns.InGroupWith(t.key)
    local raid = grouped and IsInRaid and IsInRaid()

    if mode == "prefill" then
        if grouped then OpenChat((raid and "/ra " or "/p ") .. text)
        else ns.OpenWhisperTo(t.sender, text) end
        return
    end

    local ok
    if grouped then ok = SendChat(text, raid and "RAID" or "PARTY")
    else ok = SendChat(text, "WHISPER", t.sender) end
    if not ok then -- couldn't send: leave it typed, ready to press Enter
        if grouped then OpenChat((raid and "/ra " or "/p ") .. text)
        else ns.OpenWhisperTo(t.sender, text) end
    end
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
    -- what you're handing over (a crafted item means the job is done)
    local gave = {}
    if GetTradePlayerItemInfo then
        for i = 1, 6 do
            local ok, name, _, count = pcall(GetTradePlayerItemInfo, i)
            if ok and type(name) == "string" and not IsSecret(name) then
                gave[#gave + 1] = { name = name, count = count }
            end
        end
    end
    trade.gave = gave
    -- their "will not be traded" slot: the item you enchant or the box you open
    if GetTradeTargetItemInfo then
        local ok, name, _, _, _, _, enchantment = pcall(GetTradeTargetItemInfo, 7)
        if ok and type(name) == "string" and not IsSecret(name) then
            trade.slot7 = { name = name, enchantment = (type(enchantment) == "string" and not IsSecret(enchantment)) and enchantment or nil }
        else
            trade.slot7 = nil
        end
    end
end

---------------------------------------------------------------------------
-- Earnings (per character, plus this session), by profession and by recipe
---------------------------------------------------------------------------
local function NewTotals()
    return { total = 0, prof = {}, count = {}, recipe = {} }
end
ns.session = NewTotals()

local function FillTotals(t)
    for k, v in pairs(NewTotals()) do if t[k] == nil then t[k] = v end end
    return t
end

-- Saved in the addon's saved variables, so they survive logouts, reloads and restarts:
--   ns.earnings : this character, from services
--   ns.lifetime : every character on the account, from services, since the date it began
--   ns.allTrades: every character, all gold received in any completed trade
function ns.InitEarnings()
    CraftServicesCharDB = CraftServicesCharDB or {}
    CraftServicesCharDB.earnings = FillTotals(CraftServicesCharDB.earnings or NewTotals())
    ns.earnings = CraftServicesCharDB.earnings
    local db = ns.db
    db.lifetime = FillTotals(db.lifetime or NewTotals())
    ns.lifetime = db.lifetime
    db.lifetimeSince = db.lifetimeSince or (date and date("%d %b %Y")) or "install"
    db.allTrades = db.allTrades or { total = 0, count = 0 }
    ns.allTrades = db.allTrades
end

local function AddTo(t, kind, recipe, copper)
    t.total = t.total + copper
    t.prof[kind] = (t.prof[kind] or 0) + copper
    t.count[kind] = (t.count[kind] or 0) + 1
    if recipe then t.recipe[recipe] = (t.recipe[recipe] or 0) + copper end
end

local function RecordEarning(key, copper)
    if not copper or copper <= 0 or not ns.earnings then return end
    local c = ns.customers[key]
    local kind = c and c.kind or "other"
    local recipe = c and c.recipe and c.recipe.name
    AddTo(ns.earnings, kind, recipe, copper)
    AddTo(ns.lifetime, kind, recipe, copper)
    AddTo(ns.session, kind, recipe, copper)
end

-- Any completed trade that brought in gold, customer or not.
local function RecordAnyTrade(copper)
    if not copper or copper <= 0 or not ns.allTrades then return end
    ns.allTrades.total = ns.allTrades.total + copper
    ns.allTrades.count = ns.allTrades.count + 1
end

local function ProfName(kind)
    local p = ns.PROF_BY_KEY[kind]
    return p and p.name or (kind == "custom" and "Your phrases" or "Other")
end

-- One-line summary for the bottom of the window.
function ns.EarningsLine()
    local e, s, l = ns.earnings, ns.session, ns.lifetime
    if not e then return "" end
    local muted = ns.Theme and ns.Theme().muted or "aaaaaa"
    local parts = {}
    for kind, copper in pairs(l.prof) do parts[#parts + 1] = { kind = kind, copper = copper } end
    table.sort(parts, function(a, b) return a.copper > b.copper end)
    local by = {}
    for i = 1, math.min(3, #parts) do by[#by + 1] = ProfName(parts[i].kind):lower() .. " " .. Money(parts[i].copper) end
    return ("All characters %s  |cff%s%s  this character %s   session %s|r"):format(
        Money(l.total), muted, #by > 0 and ("(" .. table.concat(by, ", ") .. ")") or "", Money(e.total), Money(s.total))
end

local function Breakdown(lines, t, max)
    local parts = {}
    for kind, copper in pairs(t.prof) do parts[#parts + 1] = { kind = kind, copper = copper } end
    table.sort(parts, function(a, b) return a.copper > b.copper end)
    for i, p in ipairs(parts) do
        if max and i > max then break end
        lines[#lines + 1] = ("     %s:  %s  from %d"):format(ProfName(p.kind), Money(p.copper), t.count[p.kind] or 0)
    end
end

-- Full breakdown for chat; compact (a fixed 9 lines at most) for the settings page.
function ns.EarningsLines(compact)
    local e, s, l, a = ns.earnings, ns.session, ns.lifetime, ns.allTrades
    if not e then return {} end
    local lines = {}
    lines[#lines + 1] = ("All characters, all time (since %s):  %s"):format(ns.db.lifetimeSince or "install", Money(l.total))
    Breakdown(lines, l, compact and 4 or nil)
    lines[#lines + 1] = ("This character:  %s"):format(Money(e.total))
    if not compact then Breakdown(lines, e) end
    lines[#lines + 1] = ("This session:  %s"):format(Money(s.total))
    if not compact then Breakdown(lines, s) end
    local recipes = {}
    for name, copper in pairs(l.recipe) do recipes[#recipes + 1] = { name = name, copper = copper } end
    table.sort(recipes, function(x, y) return x.copper > y.copper end)
    if #recipes > 0 then
        local parts = {}
        for i = 1, math.min(5, #recipes) do parts[#parts + 1] = recipes[i].name .. " " .. Money(recipes[i].copper) end
        lines[#lines + 1] = "Best earners (all characters):  " .. table.concat(parts, ", ")
    end
    lines[#lines + 1] = ("Every trade while the addon was on:  %s  from %d trades"):format(Money(a.total), a.count)
    return lines
end

-- what = "character" (this character only) or "all" (everything, every character)
function ns.ResetEarnings(what)
    CraftServicesCharDB.earnings = NewTotals()
    ns.earnings = CraftServicesCharDB.earnings
    ns.session = NewTotals()
    if what == "all" then
        ns.db.lifetime = NewTotals()
        ns.lifetime = ns.db.lifetime
        ns.db.lifetimeSince = (date and date("%d %b %Y")) or "reset"
        ns.db.allTrades = { total = 0, count = 0 }
        ns.allTrades = ns.db.allTrades
    end
end

local function MarkPaid(key, copper, test)
    local c = ns.customers[key]
    if not test then ns.AddHistory(key, copper, c and c.recipe and c.recipe.name, c and c.sender) end
    ns.SetStatus(key, "paid", { paid = copper })
    if ns.JobFinished and not test then ns.JobFinished(key, c and c.sender) end
    ns.Refresh()
end

-- A trade that didn't finish the job: back to "mats received", "in your group" or
-- "invited", so they stay listed.
local function TradeEnded(key, gotMats)
    for _, r in ipairs(ns.requests) do
        if r.key == key and r.status == "trading" then
            if gotMats then r.gotMats = true end
            r.status = r.gotMats and "mats" or (ns.InGroupWith(key) and "grouped" or "invited")
            r.statusTime = GetTime()
        end
    end
    ns.Refresh()
end
ns.TradeEnded = TradeEnded

local function Finish(result, reason)
    if not trade or trade.done then return end
    trade.done = true
    local t, db = trade, ns.db
    -- the window can empty as the trade goes through: use what was there when you accepted
    if result == "complete" and t.snap then
        for k, v in pairs(t.snap) do t[k] = v end
        t.picked = t.picked or t.snap.picked
    end
    if result == "complete" and not t.test then RecordAnyTrade(t.money or 0) end
    if result ~= "complete" and t.key then TradeEnded(t.key) end
    if not t.key or not IsCustomer(t.key) then trade = nil return end
    local name = t.first

    if result == "complete" then
        local money = t.money or 0
        local itemsText = ItemsText(t.items or {})
        -- the job is done when you handed something over or enchanted / opened their item
        local jobDone = #(t.gave or {}) > 0 or (t.slot7 and t.slot7.enchantment) or t.picked
        if money > 0 then
            local paid = Money(money)
            -- the amount stays private unless you choose to share it
            if db.hideAmount then
                Post(t, Fill(db.paidMsgPrivate, name))
            else
                Post(t, Fill(db.paidMsg, name, { amount = paid }))
            end
            if not t.test then RecordEarning(t.key, money) end
            MarkPaid(t.key, money, t.test)
            ns.Print("payment from " .. ns.DisplayName(t.sender) .. ": " .. paid
                .. (itemsText ~= "" and (" (plus " .. itemsText .. ")") or ""))
        elseif jobDone then
            -- a free job, or one they'll pay for separately
            Post(t, Fill(db.noPayMsg, name))
            local c = ns.customers[t.key]
            if not t.test then ns.AddHistory(t.key, 0, c and c.recipe and c.recipe.name, t.sender) end
            ns.SetStatus(t.key, "done", { paid = 0 })
            if ns.JobFinished then ns.JobFinished(t.key, t.sender) end
        elseif itemsText ~= "" then
            -- mats handed over: still to be made, so they stay in the queue
            if db.matsReceipt then Post(t, Fill(db.matsMsg, name, { items = itemsText })) end
            TradeEnded(t.key, true)
            ns.Print("mats from " .. ns.DisplayName(t.sender) .. ": " .. itemsText)
        else
            TradeEnded(t.key) -- nothing changed hands
        end
    elseif result == "cancelled" then
        Post(t, Fill(db.cancelMsg, name))
    else
        Post(t, Fill(db.failMsg, name, { reason = (reason or "unknown reason"):gsub("%.%s*$", "") }))
    end
    trade = nil
end

-- A game format string ("%s is busy.") as a Lua pattern that matches the filled-in text.
local function FormatPattern(fmt)
    local p = fmt:gsub("([%^%$%(%)%.%[%]%*%+%-%?%%])", "%%%1")
    p = p:gsub("%%%%%%%%", "%%%%"):gsub("%%%%s", ".+"):gsub("%%%%d", "%%d+")
    return "^" .. p .. "$"
end

-- Any of the game's ERR_TRADE_* messages counts as a failed trade.
local tradeErrors
function ns.IsTradeError(msg)
    if not tradeErrors then
        tradeErrors = {}
        for k, v in pairs(_G) do
            if type(k) == "string" and k:find("^ERR_TRADE_") and type(v) == "string"
                and k ~= "ERR_TRADE_COMPLETE" and k ~= "ERR_TRADE_CANCELLED" then
                tradeErrors[#tradeErrors + 1] = FormatPattern(v)
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
for _, e in ipairs({ "TRADE_SHOW", "TRADE_MONEY_CHANGED", "TRADE_TARGET_ITEM_CHANGED", "TRADE_PLAYER_ITEM_CHANGED",
                     "TRADE_ACCEPT_UPDATE",
                     "TRADE_CLOSED", "TRADE_REQUEST_CANCEL", "UI_INFO_MESSAGE", "UI_ERROR_MESSAGE",
                     "PLAYER_REGEN_ENABLED" }) do
    SafeRegister(e)
end
pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_SUCCEEDED", "player")

-- A spell you cast while their item sits in the "will not be traded" slot (an enchant or
-- Pick Lock) means the job is done, even if the game hides the enchant text.
function ns.TradeJobCast()
    if trade and trade.slot7 then trade.picked = true end
end

ev:SetScript("OnEvent", function(_, event, arg1, arg2)
    if not ns.db then return end

    if event == "PLAYER_REGEN_ENABLED" then
        if pendingUpdate then ns.Refresh() end

    elseif event == "TRADE_SHOW" then
        local key, sender = TradePartner()
        trade = { key = key, sender = sender, first = ns.FirstName(sender), money = 0, items = {} }
        ReadTrade()
        if key then ns.SetStatus(key, "trading") end
        if ns.ShowTradePanel then ns.ShowTradePanel(key, sender) end

    elseif event == "TRADE_MONEY_CHANGED" or event == "TRADE_TARGET_ITEM_CHANGED" or event == "TRADE_ACCEPT_UPDATE"
        or event == "TRADE_PLAYER_ITEM_CHANGED" then
        ReadTrade()
        if event == "TRADE_ACCEPT_UPDATE" and trade then
            -- once you accept, nothing can change without the game clearing both accepts,
            -- so what's in the window now is what will be traded
            trade.iAccepted = (arg1 == 1 or arg1 == true)
            trade.theyAccepted = (arg2 == 1 or arg2 == true)
            trade.snap = trade.iAccepted and { money = trade.money, items = trade.items, gave = trade.gave,
                                               slot7 = trade.slot7, picked = trade.picked } or nil
        end
        if ns.UpdateTradePanel then ns.UpdateTradePanel() end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if trade then ns.TradeJobCast(); ReadTrade(); if ns.UpdateTradePanel then ns.UpdateTradePanel() end end

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
        -- the complete/cancel message can arrive just after the window closes; if both
        -- of you had accepted and no error came, the trade went through
        local t = trade
        if t then
            C_Timer.After(0.6, function()
                if trade == t and not t.done then Finish((t.iAccepted and t.theyAccepted) and "complete" or "cancelled") end
            end)
        end
    end
end)

-- The trade in progress, for the trade panel.
function ns.CurrentTrade() return trade end

-- For /cs testtrade: run a fake trade through the same path.
function ns.TestTrade(result)
    trade = { key = "testbuyerexample", sender = "Testbuyer Example", first = "Testbuyer",
              money = result == "mats" and 0 or 15000, items = { { name = "Large Brilliant Shard", count = 4 } },
              gave = {}, test = true }
    if result == "mats" then result = "complete" end
    ns.customers.testbuyerexample = { time = GetTime(), kind = "enchanting", sender = "Testbuyer Example" }
    local mode = ns.db.receiptMode
    ns.db.receiptMode = "prefill" -- never send a real message from a test
    if result == "complete" then Finish("complete")
    elseif result == "failed" then Finish("failed", "Target is too far away.")
    else Finish("cancelled") end
    ns.db.receiptMode = mode
end

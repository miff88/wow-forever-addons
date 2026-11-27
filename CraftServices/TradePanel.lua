-- Craft Services: the trade window helper.
--
-- A small panel beside the trade window while you trade with someone who asked for a
-- craft (or put an item in the "will not be traded" slot). It shows:
--   * who they are and what they asked for
--   * a mats checklist: each reagent, how many are in your bags and how many they're
--     handing over in this trade
--   * their item in the "will not be traded" slot: whether the enchant fits it, or for
--     a lockbox, whether it's locked and whether your lockpicking is high enough
--   * what they're offering against your price
-- and gives one-click buttons:
--   * Enchant their item: opens the recipe if your profession window isn't showing it,
--     otherwise starts the enchant and lands it on their item
--   * Pick Lock: casts Pick Lock on the box in their "will not be traded" slot
--   * Open recipe: opens your profession at the recipe
--   * Ask to pay / Ask for mats: a whisper (or party message) with the price or the
--     missing mats
-- The cast buttons are secure, so they're set up out of combat only.

local ADDON_NAME, ns = ...

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function Safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c, d, e, f, g
end

local function Clean(v)
    if v == nil or IsSecret(v) then return nil end
    return v
end

local READY = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t"
local NOT_READY = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12|t"
local WAITING = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:12:12|t"

-- Which item slots an enchant goes on.
local FITS = {
    ["Weapon"]    = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true,
                      INVTYPE_2HWEAPON = true },
    ["2H Weapon"] = { INVTYPE_2HWEAPON = true },
    ["Chest"]     = { INVTYPE_CHEST = true, INVTYPE_ROBE = true },
    ["Boots"]     = { INVTYPE_FEET = true },
    ["Gloves"]    = { INVTYPE_HAND = true },
    ["Bracer"]    = { INVTYPE_WRIST = true },
    ["Cloak"]     = { INVTYPE_CLOAK = true },
    ["Shield"]    = { INVTYPE_SHIELD = true },
}
ns.ENCHANT_FITS = FITS

local SLOT_WORDS = {
    INVTYPE_WEAPON = "a one-hand weapon", INVTYPE_WEAPONMAINHAND = "a main-hand weapon",
    INVTYPE_WEAPONOFFHAND = "an off-hand weapon", INVTYPE_2HWEAPON = "a two-hand weapon",
    INVTYPE_CHEST = "a chest piece", INVTYPE_ROBE = "a robe", INVTYPE_FEET = "boots", INVTYPE_HAND = "gloves",
    INVTYPE_WRIST = "bracers", INVTYPE_CLOAK = "a cloak", INVTYPE_SHIELD = "a shield", INVTYPE_HEAD = "a helm",
    INVTYPE_SHOULDER = "shoulders", INVTYPE_LEGS = "legs", INVTYPE_WAIST = "a belt", INVTYPE_FINGER = "a ring",
    INVTYPE_NECK = "a necklace", INVTYPE_TRINKET = "a trinket", INVTYPE_HOLDABLE = "an off-hand item",
    INVTYPE_RANGED = "a ranged weapon", INVTYPE_RANGEDRIGHT = "a ranged weapon", INVTYPE_THROWN = "a thrown weapon",
    INVTYPE_BODY = "a shirt", INVTYPE_TABARD = "a tabard", INVTYPE_BAG = "a bag",
}

local function EquipLoc(link)
    if type(link) ~= "string" and type(link) ~= "number" then return nil end
    local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local _, _, _, loc = Safe(fn, link)
    loc = Clean(loc)
    if loc == "" then return nil end
    return loc
end
ns.EquipLoc = EquipLoc

-- Does this enchant go on this item? true / false, plus a description of the item.
function ns.EnchantFits(e, loc)
    if not e or not e.slot or not loc then return nil end
    local fits = FITS[e.slot]
    if not fits then return nil end
    return fits[loc] == true, SLOT_WORDS[loc] or loc:gsub("^INVTYPE_", ""):lower()
end

-- Bags only: mats in the bank can't be used until you fetch them.
local function BagCount(id)
    if not id then return 0 end
    local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
    local n = Safe(fn, id, false)
    return type(n) == "number" and not IsSecret(n) and n or 0
end
ns.BagCount = BagCount

-- What they've put in the trade (slots 1-6), by item ID.
local function TheirItems()
    local out = {}
    for i = 1, 6 do
        local link = Clean(Safe(GetTradeTargetItemLink, i))
        local _, _, count = Safe(GetTradeTargetItemInfo, i)
        count = Clean(count)
        local id = ns.Book.ItemIDFromLink(link)
        if id then out[id] = (out[id] or 0) + (type(count) == "number" and count or 1) end
    end
    return out
end
ns.TheirTradeItems = TheirItems

-- Their "will not be traded" slot.
local function TheirSlot7()
    local name, texture, count, quality, usable, enchantment, itemID = Safe(GetTradeTargetItemInfo, 7)
    name = Clean(name)
    if type(name) ~= "string" then return nil end
    local link = Clean(Safe(GetTradeTargetItemLink, 7))
    itemID = Clean(itemID)
    return { name = name, icon = Clean(texture), link = link, id = type(itemID) == "number" and itemID or nil,
             enchantment = Clean(enchantment), loc = EquipLoc(link) or (type(itemID) == "number" and EquipLoc(itemID)) }
end
ns.TheirSlot7 = TheirSlot7

-- Lockbox details from the item's tooltip: locked?, skill needed.
local function TooltipLines(getter, ...)
    local lines = {}
    if C_TooltipInfo and C_TooltipInfo[getter] then
        local data = Safe(C_TooltipInfo[getter], ...)
        if type(data) == "table" and type(data.lines) == "table" then
            for _, line in ipairs(data.lines) do
                local text = Clean(line.leftText)
                if type(text) == "string" then lines[#lines + 1] = text end
            end
        end
    end
    return lines
end
ns.TooltipLines = TooltipLines

local function SkillPattern()
    -- "Requires %s (%d)" -> "^Requires (.+) %((%d+)%)$"
    local s = type(ITEM_MIN_SKILL) == "string" and ITEM_MIN_SKILL or "Requires %s (%d)"
    s = s:gsub("([%^%$%(%)%.%[%]%*%+%-%?%%])", "%%%1")
    s = s:gsub("%%%%%%%%", "%%%%"):gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
    return "^" .. s .. "$"
end
ns.SkillPattern = SkillPattern

function ns.LockboxInfo(lines, name)
    local locked, need = false, nil
    local lockedWord = LOCKED or "Locked"
    local pat = SkillPattern()
    for _, text in ipairs(lines) do
        if text == lockedWord then locked = true end
        local skill, n = text:match(pat)
        if skill and n and skill:lower():find("lockpick") then need = tonumber(n) end
    end
    local looksLikeBox = locked or (name and (name:find("[Ll]ockbox") or name:find("[Jj]unkbox")
        or name:find("[Ss]trongbox") or name:find("Box$") or name:find("Chest$")))
    if not looksLikeBox then return nil end
    return { locked = locked, need = need }
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------
local WIDTH = 250
local panel = CreateFrame("Frame", "CraftServicesTradePanel", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
panel:SetSize(WIDTH, 200)
panel:SetFrameStrata("HIGH")
panel:SetClampedToScreen(true)
panel:Hide()
if panel.SetBackdrop then
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
end
ns.tradePanel = panel

panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
panel.title:SetPoint("TOPLEFT", 8, -7)
panel.title:SetPoint("TOPRIGHT", -24, -7)
panel.title:SetJustifyH("LEFT")
panel.title:SetWordWrap(false)

panel.close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
panel.close:SetSize(20, 20)
panel.close:SetPoint("TOPRIGHT", 1, 1)
panel.close:SetScript("OnClick", function() panel:Hide(); panel.dismissed = true end)

panel.body = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
panel.body:SetPoint("TOPLEFT", 8, -26)
panel.body:SetWidth(WIDTH - 16)
panel.body:SetJustifyH("LEFT")
panel.body:SetJustifyV("TOP")
panel.body:SetSpacing(2)
panel.body:SetWordWrap(true)

-- Buttons, two rows: [Enchant their item / Pick Lock] [Open recipe]
--                    [Ask to pay] [Ask for mats]
local BW, BH = (WIDTH - 20) / 2, 20
panel.castBtn = ns.SecureFlatButton("CraftServicesTradeCast", panel, BW, BH, "Enchant their item", true)
panel.castBtn:SetAttribute("type", "macro")
panel.openBtn = ns.FlatButton(panel, BW, BH, "Open recipe")
panel.payBtn = ns.FlatButton(panel, BW, BH, "Ask to pay")
panel.matsBtn = ns.FlatButton(panel, BW, BH, "Ask for mats")

panel.castBtn:SetPoint("BOTTOMLEFT", 8, 32)
panel.openBtn:SetPoint("LEFT", panel.castBtn, "RIGHT", 4, 0)
panel.payBtn:SetPoint("BOTTOMLEFT", 8, 8)
panel.matsBtn:SetPoint("LEFT", panel.payBtn, "RIGHT", 4, 0)

local function Tip(btn, lines)
    btn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        local l = type(lines) == "function" and lines(self) or lines
        for i, text in ipairs(l) do
            if i == 1 then GameTooltip:AddLine(text, 0.96, 0.66, 0.24) else GameTooltip:AddLine(text, 1, 1, 1, true) end
        end
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

Tip(panel.castBtn, function(self)
    if self.kind == "lock" then
        return { "Pick Lock", "Casts Pick Lock on the box in their \"will not be traded\" slot." }
    end
    return { self.spellName or "Enchant",
             "First click opens the recipe in your profession window. Next click starts the enchant and puts it on their item in the \"will not be traded\" slot.",
             "If nothing happens, press Enchant in your profession window, then click their item." }
end)
Tip(panel.openBtn, function(self)
    return { "Open recipe", "Opens " .. (self.profName or "your profession") .. (self.recipe and " at this recipe." or ".") }
end)
Tip(panel.payBtn, function(self)
    return { "Ask to pay", self.preview or "" }
end)
Tip(panel.matsBtn, function(self)
    return { "Ask for mats", self.preview or "" }
end)

-- Put the panel beside the trade window without anchoring to it (anchoring secure
-- buttons to Blizzard's frame would make that frame protected in combat).
local function PlacePanel()
    local tf = _G.TradeFrame
    panel:ClearAllPoints()
    if tf and tf:IsShown() and tf:GetRight() and tf:GetTop() then
        local ratio = (tf:GetEffectiveScale() or 1) / (panel:GetEffectiveScale() or 1)
        panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", tf:GetRight() * ratio + 4, tf:GetTop() * ratio)
    else
        panel:SetPoint("CENTER", UIParent, "CENTER", 260, 80)
    end
end

function ns.ApplyTradeTheme(t)
    if panel.SetBackdropColor then
        panel:SetBackdropColor(t.bg[1], t.bg[2], t.bg[3], t.bg[4] or 0.95)
        panel:SetBackdropBorderColor(t.border[1], t.border[2], t.border[3], 1)
    end
    ns.StyleText(panel.title, t.title)
    ns.StyleText(panel.body, t.text)
end

---------------------------------------------------------------------------
-- Working out what this trade is for
---------------------------------------------------------------------------
local current -- { key, sender, first, req, info }

local function FindRequest(key)
    if not key then return nil end
    for _, r in ipairs(ns.requests or {}) do
        if r.key == key then return r end
    end
end

-- The recipe the trade is for: their request, or an enchant that fits their item when
-- they asked for "an enchanter" without naming one (only if exactly one is priced/featured).
local function TradeRecipe(info, slot7)
    if info and info.recipe then return info.recipe end
    return nil
end

local function PriceText(copper)
    return copper and ns.Money(copper) or nil
end

-- Builds the text and button states. Returns the lines (also used by tests).
function ns.TradePanelState()
    local c = current
    if not c then return nil end
    local db = ns.db
    local t = ns.Theme()
    local good, warn, muted = t.good, t.warn or "ffb347", t.muted
    local req = FindRequest(c.key)
    local info = (req and req.info) or (ns.customers[c.key] and { kind = "craft", prof = ns.customers[c.key].kind,
        recipe = ns.customers[c.key].recipe, label = ns.customers[c.key].recipe and ns.customers[c.key].recipe.name })
    local slot7 = TheirSlot7()
    local e = TradeRecipe(info, slot7)
    local prof = info and ns.PROF_BY_KEY[info.prof]
    local state = { lines = {}, cast = nil, open = nil, missing = {}, price = nil, offered = 0 }
    local L = state.lines

    -- who and what
    local who = ns.DisplayName(c.sender or c.key or "?")
    state.title = "Craft Services: " .. who
    if info and info.label then
        L[#L + 1] = ("|cff%s%s|r"):format(good, info.label)
    elseif slot7 then
        L[#L + 1] = "No request from them yet"
    end
    if req and req.msg then
        L[#L + 1] = ("|cff%s\"%s\"|r"):format(muted, req.msg)
    end
    local hist = ns.History and ns.History(c.key)
    if hist and hist.count and hist.count > 0 then
        L[#L + 1] = ("|cff%sRegular: %d job%s, %s paid in total|r"):format(muted, hist.count, hist.count == 1 and "" or "s",
            ns.Money(hist.total or 0))
    end

    -- mats checklist
    if e and e.reagents and #e.reagents > 0 then
        local theirs = TheirItems()
        L[#L + 1] = " "
        L[#L + 1] = "Mats for " .. (e.callName or e.name) .. ":"
        local allInBags, allAfter = true, true
        for _, r in ipairs(e.reagents) do
            local name = ns.Book.ItemName(r.id) or ("item " .. r.id)
            local bags, given = BagCount(r.id), theirs[r.id] or 0
            local icon
            if bags >= r.n then icon = READY
            elseif bags + given >= r.n then icon = WAITING; allInBags = false
            else icon = NOT_READY; allInBags, allAfter = false, false
                state.missing[#state.missing + 1] = { name = name, n = r.n - bags - given }
            end
            local extra = given > 0 and ("  |cff%s+%d in trade|r"):format(good, given) or ""
            L[#L + 1] = ("%s %d %s  |cff%s(bags %d)|r%s"):format(icon, r.n, name, muted, bags, extra)
        end
        state.matsReady = allInBags
        if not allInBags and allAfter then
            L[#L + 1] = ("|cff%sAccept this trade first, then make it.|r"):format(warn)
        elseif not allAfter then
            local parts = {}
            for _, m in ipairs(state.missing) do parts[#parts + 1] = m.n .. " " .. m.name end
            L[#L + 1] = ("|cff%sStill short: %s|r"):format(warn, ns.JoinList(parts))
        end
    end

    -- their item in the "will not be traded" slot
    local kind = info and info.prof
    if slot7 then
        L[#L + 1] = " "
        if kind == "lockpicking" or (not e and ns.Book.Has("lockpicking")) then
            local box = ns.LockboxInfo(TooltipLines("GetTradeTargetItem", 7), slot7.name)
            if box then
                local mine = ns.Book.Skill("lockpicking")
                local s = "Their box: " .. slot7.name
                if not box.locked then
                    s = s .. ("  |cff%snot locked|r"):format(good)
                elseif box.need and mine and mine < box.need then
                    s = s .. ("  |cff%sneeds %d lockpicking, you have %d|r"):format(warn, box.need, mine)
                    state.cantPick = true
                else
                    s = s .. ("  |cff%slocked%s|r"):format(good, box.need and (", needs " .. box.need) or "")
                end
                L[#L + 1] = s
                state.box = box
                if box.locked and not state.cantPick and ns.Book.Has("lockpicking") then
                    state.cast = { kind = "lock", spell = ns.PROF_BY_KEY.lockpicking.spell }
                end
            else
                L[#L + 1] = "Their item: " .. slot7.name
            end
        elseif e and e.enchant then
            local fits, word = ns.EnchantFits(e, slot7.loc)
            local s = "Their item: " .. slot7.name
            if fits == true then
                s = s .. ("  |cff%sfits|r"):format(good)
            elseif fits == false then
                s = s .. ("  |cff%sis %s, the enchant is for %s|r"):format(warn, word, e.slot:lower())
                state.wrongSlot = true
            end
            if slot7.enchantment then
                s = s .. ("\n|cff%sEnchanted: %s|r"):format(good, slot7.enchantment)
                state.enchanted = true
            end
            L[#L + 1] = s
            if not state.wrongSlot and state.matsReady ~= false then
                state.cast = { kind = "enchant", spell = e.name }
            end
        else
            L[#L + 1] = "Their item: " .. slot7.name
        end
    elseif e and e.enchant then
        L[#L + 1] = " "
        L[#L + 1] = ("|cff%sAsk them to put the item in the \"will not be traded\" slot.|r"):format(muted)
    elseif kind == "lockpicking" then
        L[#L + 1] = " "
        L[#L + 1] = ("|cff%sAsk them to put the box in the \"will not be traded\" slot.|r"):format(muted)
    end

    -- payment
    local offered = Clean(Safe(GetTargetTradeMoney))
    state.offered = type(offered) == "number" and offered or 0
    state.price = e and ns.Book.Price(e)
    if state.price or state.offered > 0 then
        L[#L + 1] = " "
        local s = "Offered: " .. ns.Money(state.offered)
        if state.price then
            local col = state.offered >= state.price and good or warn
            s = ("Offered: |cff%s%s|r  (your price %s)"):format(col, ns.Money(state.offered), ns.Money(state.price))
        end
        L[#L + 1] = s
    end

    -- buttons
    state.recipe = e
    if prof and prof.key ~= "lockpicking" and ns.Book.Has(prof.key) then state.open = prof.name; state.openKey = prof.key end
    return state
end

local function SetSecure(btn, attr, value)
    if InCombatLockdown() then return false end
    btn:SetAttribute(attr, value)
    return true
end

local pendingSecure = false

function ns.UpdateTradePanel()
    if not current or not panel:IsShown() then return end
    local state = ns.TradePanelState()
    if not state then return end
    local db = ns.db
    panel.title:SetText(state.title)
    panel.body:SetText(table.concat(state.lines, "\n"))
    local h = (panel.body:GetStringHeight() or 60)
    panel:SetHeight(26 + h + 10 + 52)
    panel.state = state

    -- secure buttons: out of combat only
    if InCombatLockdown() then
        pendingSecure = true
    else
        pendingSecure = false
        local cb = panel.castBtn
        if state.cast then
            cb.kind = state.cast.kind
            cb.spellName = state.cast.spell
            -- start the spell, then click their item in the trade window so it lands on it
            if state.cast.kind == "lock" then
                cb.text:SetText("Pick Lock")
                SetSecure(cb, "macrotext", "/cast " .. (ns.SpellName(1804) or state.cast.spell)
                    .. "\n/click TradeRecipientItem7ItemButton")
            else
                cb.text:SetText(ns.EnchantReady(state.recipe) and "Enchant their item" or "Open the enchant")
                SetSecure(cb, "macrotext", "/run CraftServices_StartEnchant()\n/click TradeRecipientItem7ItemButton")
            end
            cb:Show()
        else
            SetSecure(cb, "macrotext", nil)
            cb:Hide()
        end
    end
    local ob = panel.openBtn
    if state.open and not (state.cast and state.cast.kind == "enchant") then
        ob.profName, ob.recipe, ob.profKey = state.open, state.recipe, state.openKey
        ob:Show()
    else
        ob:Hide()
    end

    -- message buttons
    local first = current.first or ns.FirstName(current.sender or "")
    if state.price and state.offered < state.price then
        panel.payBtn.preview = ns.FillPayMsg(first, state.price, state.offered)
        panel.payBtn:Show()
    else
        panel.payBtn:Hide()
    end
    if #state.missing > 0 then
        panel.matsBtn.preview = ns.FillMatsAsk(first, state.missing)
        panel.matsBtn:Show()
    else
        panel.matsBtn:Hide()
    end
end

function ns.FillPayMsg(first, price, offered)
    local msg = ns.db.payAskMsg or "{name}, it's {price} when you're ready."
    msg = msg:gsub("{name}", first or ""):gsub("{price}", ns.Money(price))
    if offered and offered > 0 then msg = msg:gsub("{short}", ns.Money(price - offered)) else msg = msg:gsub("{short}", ns.Money(price)) end
    return msg
end

function ns.FillMatsAsk(first, missing)
    local parts = {}
    for _, m in ipairs(missing) do parts[#parts + 1] = m.n .. " " .. m.name end
    local msg = ns.db.matsAskMsg or "{name}, I still need {missing} for this one."
    return (msg:gsub("{name}", first or ""):gsub("{missing}", ns.JoinList(parts)))
end

-- Whisper if they're not grouped with you, otherwise party chat.
local function Say(text)
    if not current or not text or text == "" then return end
    local key = current.key
    if ns.InGroupWith(key) then
        local raid = IsInRaid and IsInRaid()
        if not ns.SendChat(text, raid and "RAID" or "PARTY") then ns.OpenWhisperTo(current.sender, text) end
    else
        if not ns.SendChat(text, "WHISPER", current.sender) then ns.OpenWhisperTo(current.sender, text) end
    end
end
ns.TradeSay = Say

panel.payBtn:SetScript("OnClick", function(self) Say(self.preview) end)
panel.matsBtn:SetScript("OnClick", function(self) Say(self.preview) end)
panel.openBtn:SetScript("OnClick", function(self)
    if self.recipe then ns.PickRecipe(self.recipe)
    elseif self.profKey then ns.OpenProfession(self.profKey) end
end)

-- Is your profession window open on the enchanting profession? (Crafting needs it open.)
function ns.EnchantReady(e)
    if not e then return false end
    local pf = _G.ProfessionsFrame
    if not (pf and pf:IsShown()) then return false end
    local open = ns.Book.OpenProfession()
    return open ~= nil and open.key == (e.prof or "enchanting")
end

-- Run by the Enchant button's macro, just before it clicks their item: starts the enchant
-- (which waits for a target), or opens the recipe first if the window isn't up.
function CraftServices_StartEnchant()
    local e = panel.state and panel.state.recipe
    if not e then return end
    if SpellIsTargeting and SpellIsTargeting() then return end -- already waiting for a target
    if not ns.EnchantReady(e) then
        ns.PickRecipe(e)
        ns.Print("opened " .. e.name .. ". Click Enchant their item again to put it on their item.")
        C_Timer.After(0.5, function() if current then ns.UpdateTradePanel() end end)
        return
    end
    local ok = C_TradeSkillUI and C_TradeSkillUI.CraftRecipe and pcall(C_TradeSkillUI.CraftRecipe, e.id, 1)
    if not ok then
        ns.Print("couldn't start the enchant. Press Enchant in your profession window, then click their item.")
    end
end

-- Whether a trade deserves the panel: they asked for something, or put an item in the
-- "will not be traded" slot while you have enchanting or lockpicking.
local function Wanted(key)
    if not ns.db or not ns.db.tradePanel then return false end
    if FindRequest(key) or ns.customers[key] then return true end
    if TheirSlot7() and (ns.Book.Has("enchanting") or ns.Book.Has("lockpicking")) then return true end
    return false
end
ns.TradePanelWanted = Wanted

local function Open()
    if InCombatLockdown() then pendingSecure = true return end -- secure buttons can't show in combat
    PlacePanel()
    panel:Show()
    ns.ApplyTradeTheme(ns.Theme())
    ns.UpdateTradePanel()
end

function ns.ShowTradePanel(key, sender)
    current = { key = key, sender = sender, first = sender and ns.FirstName(sender) }
    panel.dismissed = nil
    if Wanted(key) then Open() end
end

local function Close()
    current = nil
    if InCombatLockdown() then pendingSecure = true return end
    panel:Hide()
end
ns.HideTradePanel = Close

-- Something changed in the trade: show the panel if it's now wanted, then refresh it.
local orig = ns.UpdateTradePanel
ns.UpdateTradePanel = function()
    if current and not panel:IsShown() and not panel.dismissed and Wanted(current.key) then
        Open()
        return
    end
    orig()
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "TRADE_CLOSED", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
    if event == "TRADE_CLOSED" then
        Close()
    elseif event == "BAG_UPDATE_DELAYED" then
        if current then ns.UpdateTradePanel() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingSecure then
            pendingSecure = false
            if current then
                if not panel:IsShown() and not panel.dismissed and Wanted(current.key) then Open()
                else ns.UpdateTradePanel() end
            else
                panel:Hide()
            end
        end
    end
end)

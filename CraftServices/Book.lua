-- Craft Services: your recipe book.
--
-- Addons can only read recipes while a profession window is open, so Craft Services reads
-- each profession the first time you open it (and again whenever it changes) and keeps
-- the list per character: every recipe you've learned, what it makes, its materials and
-- its description. That's what lets it tell "you know this, and you have the mats" from
-- "you don't have this recipe".
--
-- Forever uses the modern profession window (C_TradeSkillUI), so that's what it reads.

local ADDON_NAME, ns = ...

local Book = {}
ns.Book = Book

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function Pack(...) return { n = select("#", ...), ... } end

-- Calls a game function safely; nothing comes back if it errors or returns a secret value.
local function Safe(fn, ...)
    if not fn then return nil end
    local res = Pack(pcall(fn, ...))
    if not res[1] then return nil end
    for i = 2, res.n do if IsSecret(res[i]) then return nil end end
    return unpack(res, 2, res.n)
end

local function CharDB()
    CraftServicesCharDB = CraftServicesCharDB or {}
    CraftServicesCharDB.book = CraftServicesCharDB.book or {}
    return CraftServicesCharDB
end

---------------------------------------------------------------------------
-- Item names (the game may not have them cached yet)
---------------------------------------------------------------------------
function Book.ItemName(id)
    if not id then return nil end
    local name
    if C_Item and C_Item.GetItemNameByID then name = Safe(C_Item.GetItemNameByID, id) end
    if not name and GetItemInfo then name = Safe(GetItemInfo, id) end
    if not name and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return name
end

function Book.ItemCount(id)
    if not id then return 0 end
    local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
    local n = Safe(fn, id, true) -- bags and bank
    return type(n) == "number" and n or 0
end

local function ItemIDFromLink(link)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("|Hitem:(%d+)")) or tonumber(link:match("item:(%d+)"))
end
Book.ItemIDFromLink = ItemIDFromLink

---------------------------------------------------------------------------
-- Indexes
---------------------------------------------------------------------------
local byItem, bySpell, byName, lists = {}, {}, {}, {}

local function Words(s)
    local out = {}
    for w in tostring(s or ""):lower():gsub("[^%w]", " "):gmatch("%S+") do out[#out + 1] = w end
    return out
end

-- "Enchant Boots - Minor Speed" -> slot "Boots", effect "Minor Speed"
local function EnchantParts(name)
    local slot, effect = tostring(name or ""):match("^Enchant (.-) %- (.+)$")
    return slot, effect
end
Book.EnchantParts = EnchantParts

local function Index(prof, e)
    e.prof = prof
    if e.item then byItem[e.item] = e end
    if type(e.id) == "number" then bySpell[e.id] = e end
    if e.name then byName[e.name:lower()] = e end
    if e.enchant or (e.name and e.name:find("^Enchant ")) then
        e.enchant = true
        e.slot, e.effect = EnchantParts(e.name)
    end
    -- what people call it: the item it makes, or the enchant's effect
    e.callName = (e.enchant and e.effect) or (e.item and Book.ItemName(e.item)) or e.name
    lists[prof] = lists[prof] or {}
    table.insert(lists[prof], e)
end

function Book.Rebuild()
    wipe(byItem); wipe(bySpell); wipe(byName); wipe(lists)
    for prof, data in pairs(CharDB().book) do
        for _, e in pairs(data.recipes or {}) do Index(prof, e) end
    end
end

function Book.ByItem(id) return id and byItem[id] end
function Book.BySpell(id) return id and bySpell[id] end
function Book.ByName(name) return name and byName[name:lower()] end
function Book.List(prof) return lists[prof] end
function Book.Scanned(prof) local d = CharDB().book[prof]; return d and d.scanned end
function Book.Count(prof) local l = lists[prof]; return l and #l or 0 end

---------------------------------------------------------------------------
-- Your professions
---------------------------------------------------------------------------
local myProfs, lastProfs = {}, 0

local function ProfFor(name, skillLine)
    if skillLine and ns.PROF_BY_SKILL[skillLine] then return ns.PROF_BY_SKILL[skillLine] end
    if type(name) == "string" then return ns.PROF_BY_NAME[name:lower()] end
end
Book.ProfFor = ProfFor

local function KnowsSpell(id)
    if not IsPlayerSpell then return false end
    return Safe(IsPlayerSpell, id) and true or false
end

-- The spell that opens a profession: the first spell on its card in the spellbook.
local function ProfessionSpell(offset)
    if not (offset and C_SpellBook and C_SpellBook.GetSpellBookItemInfo) then return nil end
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    local info = Safe(C_SpellBook.GetSpellBookItemInfo, offset + 1, bank)
    if type(info) == "table" and type(info.spellID) == "number" and not IsSecret(info.spellID) then
        return info.spellID, (type(info.name) == "string" and not IsSecret(info.name)) and info.name or nil
    end
    local name = Safe(C_SpellBook.GetSpellBookItemName, offset + 1, bank)
    if type(name) == "string" and not IsSecret(name) then return nil, name end
end

-- [key] = { rank, max, spellID, spellName } for each profession you have
function Book.MyProfs(force)
    if not force and GetTime() - lastProfs < 2 then return myProfs end
    lastProfs = GetTime()
    wipe(myProfs)
    if GetProfessions and GetProfessionInfo then
        local list = { Safe(GetProfessions) }
        for i = 1, 6 do
            local idx = list[i]
            if idx and not IsSecret(idx) then
                local name, _, rank, maxRank, _, offset, skillLine = Safe(GetProfessionInfo, idx)
                local p = ProfFor(name, skillLine)
                if p then
                    local spellID, spellName = ProfessionSpell(offset)
                    myProfs[p.key] = { rank = rank, max = maxRank, spellID = spellID, spellName = spellName or name }
                end
            end
        end
    end
    -- a profession you've opened counts even if the list above came back empty
    for key in pairs(CharDB().book) do
        if key ~= "lockpicking" then myProfs[key] = myProfs[key] or {} end
    end
    -- rogues open lockboxes
    if KnowsSpell(1804) then
        local lp = { spellID = 1804 }
        if C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
            local info = Safe(C_TradeSkillUI.GetProfessionInfoBySkillLineID, 633)
            if type(info) == "table" and type(info.skillLevel) == "number" and not IsSecret(info.skillLevel)
                and info.skillLevel > 0 then
                lp.rank, lp.max = info.skillLevel, info.maxSkillLevel
            end
        end
        myProfs.lockpicking = lp
    end
    return myProfs
end

function Book.Has(key) return Book.MyProfs()[key] ~= nil end

function Book.Skill(key)
    local p = Book.MyProfs()[key]
    return p and p.rank
end

---------------------------------------------------------------------------
-- Reading a profession window
---------------------------------------------------------------------------
local function Store(prof, recipes)
    local n = 0
    for _ in pairs(recipes) do n = n + 1 end
    if n == 0 then return end
    local data = CharDB().book
    local before = data[prof.key] and data[prof.key].count or 0
    data[prof.key] = { scanned = time and time() or 0, count = n, recipes = recipes }
    Book.Rebuild()
    lastProfs = 0
    if n ~= before and ns.Print then
        ns.Print(("read your %s: %d recipe%s."):format(prof.name, n, n == 1 and "" or "s"))
    end
    if ns.Refresh then ns.Refresh() end
    if ns.RefreshOptions then ns.RefreshOptions() end
end

-- Which of your professions the profession window is showing (nil if it's closed or
-- showing someone else's).
function Book.OpenProfession()
    local T = C_TradeSkillUI
    if not T then return nil end
    local base = T.GetBaseProfessionInfo and Safe(T.GetBaseProfessionInfo)
    local prof
    if type(base) == "table" then prof = ProfFor(base.professionName, base.professionID) end
    if not prof and T.GetChildProfessionInfo then
        local child = Safe(T.GetChildProfessionInfo)
        if type(child) == "table" then
            prof = ProfFor(child.parentProfessionName, child.parentProfessionID) or ProfFor(child.professionName)
        end
    end
    return prof
end

-- The profession window (C_TradeSkillUI)
local function ScanModern()
    local T = C_TradeSkillUI
    if not (T and T.GetRecipeInfo and (T.GetAllRecipeIDs or T.GetFilteredRecipeIDs)) then return false end
    -- someone else's linked profession, a guild list or an NPC: not yours
    if T.IsTradeSkillLinked and Safe(T.IsTradeSkillLinked) then return true end
    if T.IsTradeSkillGuild and Safe(T.IsTradeSkillGuild) then return true end
    if T.IsNPCCrafting and Safe(T.IsNPCCrafting) then return true end
    if T.IsTradeSkillReady and not Safe(T.IsTradeSkillReady) then return true end

    local prof = Book.OpenProfession()
    if not prof then return true end

    -- every recipe of the profession; the filtered list (what the window shows) as a fallback
    local seen, ids = {}, {}
    for _, getter in ipairs({ "GetAllRecipeIDs", "GetFilteredRecipeIDs" }) do
        local list = T[getter] and Safe(T[getter])
        if type(list) == "table" then
            for _, id in ipairs(list) do
                if type(id) == "number" and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
            end
        end
    end
    if #ids == 0 then return true end
    local recipes = {}
    for _, id in ipairs(ids) do
        local info = Safe(T.GetRecipeInfo, id)
        if type(info) == "table" and info.learned and type(info.name) == "string"
            and not info.isDummyRecipe and not info.isGatheringRecipe and not info.isRecraft then
            local e = { id = id, name = info.name, icon = info.icon, reagents = {} }
            local sch = T.GetRecipeSchematic and Safe(T.GetRecipeSchematic, id, false)
            if type(sch) == "table" then
                e.item = sch.outputItemID
                if Enum and Enum.TradeskillRecipeType and sch.recipeType == Enum.TradeskillRecipeType.Enchant then
                    e.enchant = true
                end
                for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
                    local basic = slot.required or (Enum and Enum.CraftingReagentType
                        and slot.reagentType == Enum.CraftingReagentType.Basic)
                    local r = slot.reagents and slot.reagents[1]
                    if basic and r and r.itemID then
                        e.reagents[#e.reagents + 1] = { id = r.itemID, n = slot.quantityRequired or 1 }
                    end
                end
            end
            if not e.item and T.GetRecipeOutputItemData then
                local out = Safe(T.GetRecipeOutputItemData, id)
                if type(out) == "table" then e.item = out.itemID or ItemIDFromLink(out.hyperlink) end
            end
            if T.GetRecipeDescription then
                local d = Safe(T.GetRecipeDescription, id, {})
                if type(d) == "string" then e.desc = d end
            end
            recipes[id] = e
        end
    end
    Store(prof, recipes)
    return true
end

local scanQueued = false
function Book.Scan(kind)
    if scanQueued then return end
    scanQueued = true
    C_Timer.After(0.5, function()
        scanQueued = false
        ScanModern()
    end)
end

---------------------------------------------------------------------------
-- Materials
---------------------------------------------------------------------------
-- { have = true/false (nil if the recipe has no material list), missing = { {name, need, have} },
--   text = "4 Large Brilliant Shard and 2 Righteous Orb" }
function Book.Mats(e)
    if not e or not e.reagents or #e.reagents == 0 then return { text = "" } end
    local parts, missing = {}, {}
    for _, r in ipairs(e.reagents) do
        local name = Book.ItemName(r.id) or ("item " .. r.id)
        parts[#parts + 1] = r.n .. " " .. name
        local have = Book.ItemCount(r.id)
        if have < r.n then missing[#missing + 1] = { name = name, need = r.n, have = have, id = r.id } end
    end
    local text = #parts <= 1 and (parts[1] or "") or (table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts])
    return { have = #missing == 0, missing = missing, text = text }
end

---------------------------------------------------------------------------
-- Finding a recipe from what someone typed
---------------------------------------------------------------------------
local TIERS = ns.ENCHANT_TIERS

local function TokenSet(tokens)
    local set = {}
    for _, t in ipairs(tokens) do set[t] = true end
    return set
end

-- every word of the name is in the message (long words may be one letter off)
local function NameIn(nameWords, tokens, close)
    if #nameWords == 0 then return false end
    for _, w in ipairs(nameWords) do
        local found = false
        for _, t in ipairs(tokens) do
            if close(t, w) then found = true break end
        end
        if not found then return false end
    end
    return true
end

-- Enchants by nickname: "crusader", "+15 agi 2h", "minor speed", "+7 agi gloves".
local function EnchantScore(e, tokens, set, msgSlot, msgStats, numbers, close)
    local score = 0
    local effectWords = Words(e.effect)
    local text = ((e.effect or "") .. " " .. (e.desc or "")):lower()
    for _, w in ipairs(effectWords) do
        -- a distinctive name can have a typo in it ("firey"); short and common words can't
        local hit = set[w]
        if not hit and close and #w >= 5 and not TIERS[w] and not ns.ENCHANT_STATS[w] then
            for _, t in ipairs(tokens) do
                if close(t, w) then hit = true break end
            end
        end
        if hit and not TIERS[w] and w ~= "weapon" and not ns.ENCHANT_STATS[w] and #w >= 4 then
            score = score + 10 -- a name like Crusader, Fiery, Lifestealing, Unholy
        elseif set[w] and TIERS[w] then
            score = score + 1
        end
    end
    if msgSlot then
        if e.slot == msgSlot then score = score + 3 else score = score - 5 end
    end
    local statHit = false
    for stat in pairs(msgStats) do
        if text:find(stat, 1, true) then statHit = true end
    end
    if statHit then score = score + 3 end
    for _, n in ipairs(numbers) do
        if text:find("%f[%d]" .. n .. "%f[%D]") then score = score + 3 break end
    end
    return score
end

-- Returns the best recipe and how sure it is ("sure" or "likely"), or nil.
-- prof limits the search to one profession (nil = all of yours).
function Book.FindByText(tokens, prof, close)
    if #tokens == 0 then return nil end
    local set = TokenSet(tokens)
    local msgSlot
    local msgStats, numbers = {}, {}
    for _, t in ipairs(tokens) do
        msgSlot = msgSlot or ns.ENCHANT_SLOTS[t]
        if ns.ENCHANT_STATS[t] then msgStats[ns.ENCHANT_STATS[t]] = true end
        local n = tonumber(t)
        if n and n > 0 and n < 500 then numbers[#numbers + 1] = n end
    end

    local best, bestScore, second = nil, 0, 0
    for key, list in pairs(lists) do
        if not prof or prof == key then
            for _, e in ipairs(list) do
                local score = 0
                -- the item or recipe name typed out ("arcanite reaper", "major healing potion")
                local nw = Words(e.enchant and e.effect or e.callName)
                local long = #nw >= 2 or (nw[1] and #nw[1] >= 6)
                if long and not e.enchant and NameIn(nw, tokens, close) then
                    score = 8 + #nw
                end
                if e.enchant then
                    score = math.max(score, EnchantScore(e, tokens, set, msgSlot, msgStats, numbers, close))
                end
                if score > bestScore then
                    second = bestScore
                    best, bestScore = e, score
                elseif score > second then
                    second = score
                end
            end
        end
    end
    if not best then return nil end
    if bestScore >= 6 and bestScore > second then return best, "sure" end
    -- a single clear winner on a weaker match, when they've said which profession
    if prof and bestScore >= 3 and bestScore - second >= 3 then return best, "likely" end
    return nil
end

---------------------------------------------------------------------------
-- Prices and featured recipes (shared by all your characters)
---------------------------------------------------------------------------
function Book.PriceKey(e) return e and e.name and e.name:lower() end

function Book.Price(e)
    local db = ns.db
    if not (db and e) then return nil end
    return db.prices[Book.PriceKey(e)]
end

function Book.Featured(e)
    local db = ns.db
    return db and e and db.featured[Book.PriceKey(e)] and true or false
end

-- Looks a recipe up by what you type in a command: exact name, then nickname match.
function Book.Lookup(text)
    if type(text) ~= "string" or text == "" then return nil end
    local exact = byName[text:lower()]
    if exact then return exact end
    for _, list in pairs(lists) do
        for _, e in ipairs(list) do
            if (e.callName or ""):lower() == text:lower() then return e end
        end
    end
    local tokens = Words(text)
    local e = Book.FindByText(tokens, nil, function(a, b) return a == b end)
    if e then return e end
    -- last resort: the only recipe whose name contains the text
    local hit, hits = nil, 0
    for _, list in pairs(lists) do
        for _, e2 in ipairs(list) do
            if e2.name:lower():find(text:lower(), 1, true) then hit, hits = e2, hits + 1 end
        end
    end
    if hits == 1 then return hit end
end

-- Recipes for the advert: featured ones you can make now (or all featured if none qualify).
function Book.FeaturedList(onlyWithMats)
    local out = {}
    for _, list in pairs(lists) do
        for _, e in ipairs(list) do
            if Book.Featured(e) and (not onlyWithMats or Book.Mats(e).have ~= false) then out[#out + 1] = e end
        end
    end
    table.sort(out, function(a, b) return (a.callName or a.name) < (b.callName or b.name) end)
    return out
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local function SafeRegister(e) return pcall(ev.RegisterEvent, ev, e) end
for _, e in ipairs({ "PLAYER_LOGIN", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED",
                     "NEW_RECIPE_LEARNED", "SKILL_LINES_CHANGED", "SPELLS_CHANGED", "GET_ITEM_INFO_RECEIVED" }) do
    SafeRegister(e)
end

local namesPending = false
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        Book.Rebuild()
        Book.MyProfs(true)
    elseif event == "SKILL_LINES_CHANGED" or event == "SPELLS_CHANGED" then
        lastProfs = 0
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- item names arriving: refresh names on recipes once things settle
        if not namesPending then
            namesPending = true
            C_Timer.After(1, function()
                namesPending = false
                for _, list in pairs(lists) do
                    for _, e in ipairs(list) do
                        if not e.enchant and e.item and (e.callName == e.name) then
                            e.callName = Book.ItemName(e.item) or e.callName
                        end
                    end
                end
            end)
        end
    else
        Book.Scan("trade")
    end
end)

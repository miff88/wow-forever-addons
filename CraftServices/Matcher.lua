-- Craft Services: chat matching.
-- Works out whether a chat line is someone looking for a crafter, and which recipe they
-- want when it can tell:
--   * a linked item or enchant you can make ("WTB [Arcanite Reaper] crafted")
--   * an enchant by nickname or stats ("LF enchanter crusader", "+7 agi gloves")
--   * a recipe name typed out ("anyone make major healing potions?")
--   * or just the profession ("LF BS", "need a tailor", "anyone lockpick a box?")
-- Case and punctuation are ignored, and longer words can be one letter off.

local ADDON_NAME, ns = ...

---------------------------------------------------------------------------
-- Text helpers
---------------------------------------------------------------------------
local function Levenshtein(a, b)
    local la, lb = #a, #b
    local prev, cur = {}, {}
    for j = 0, lb do prev[j] = j end
    for i = 1, la do
        cur[0] = i
        local ca = a:byte(i)
        for j = 1, lb do
            local cost = (ca == b:byte(j)) and 0 or 1
            cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
        end
        prev, cur = cur, prev
    end
    return prev[lb]
end

-- Same word, or one letter off when both are 5+ letters ("enchnter", "leatherworkr").
local function Close(a, b)
    if a == b then return true end
    if #a < 5 or #b < 5 or math.abs(#a - #b) > 1 then return false end
    return Levenshtein(a, b) <= 1
end
ns.Close = Close

function ns.Tokens(msg)
    local s = msg:lower()
    s = s:gsub("|h%[(.-)%]|h", " %1 ")      -- links: keep the name
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|h", ""):gsub("|H[^|]*", "")
    s = s:gsub("'", "")                     -- "don't" -> "dont"
    s = s:gsub("[^%w]", " ")
    local tokens = {}
    for w in s:gmatch("%S+") do tokens[#tokens + 1] = w end
    return tokens
end

local function FindWord(tokens, word)
    for i, t in ipairs(tokens) do
        if Close(t, word) then return i end
    end
end

-- Every word of the phrase appears in order, next to each other ("lock box", "your mats").
local function HasPhrase(tokens, phrase)
    local words = {}
    for w in phrase:lower():gsub("'", ""):gsub("[^%w]", " "):gmatch("%S+") do words[#words + 1] = w end
    if #words == 0 then return false end
    if #words == 1 then return FindWord(tokens, words[1]) ~= nil end
    for i = 1, #tokens - #words + 1 do
        local ok = true
        for j, w in ipairs(words) do
            if not Close(tokens[i + j - 1], w) then ok = false break end
        end
        if ok then return true end
    end
    return false
end

local function HasAny(tokens, list)
    for _, w in ipairs(list) do
        if HasPhrase(tokens, w) then return true end
    end
    return false
end
ns.HasAny = HasAny

-- Every word of the phrase appears somewhere in the message (order doesn't matter).
local function PhraseMatch(tokens, phrase)
    local any = false
    for w in phrase:lower():gsub("[^%w]", " "):gmatch("%S+") do
        any = true
        if not FindWord(tokens, w) then return false end
    end
    return any
end

function ns.TextMatches(text, phrase)
    if type(text) ~= "string" or type(phrase) ~= "string" then return false end
    return PhraseMatch(ns.Tokens(text), phrase)
end

---------------------------------------------------------------------------
-- Where they are: "in org", "from uc"
---------------------------------------------------------------------------
local ORIGIN_MARKERS = { ["in"] = true, at = true, from = true }

local function FindOrigin(tokens)
    for i, t in ipairs(tokens) do
        if ORIGIN_MARKERS[t] then
            local window = { tokens[i + 1], tokens[i + 2] }
            for _, f in ipairs({ "Horde", "Alliance" }) do
                for _, d in ipairs(ns.DESTINATIONS[f]) do
                    for _, alias in ipairs(d.aliases) do
                        local a = type(alias) == "table" and alias.word or alias
                        if #window > 0 and PhraseMatch(window, a) then return d.name end
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Links in the message
---------------------------------------------------------------------------
-- { items = { itemID, ... }, spells = { spellID, ... }, names = { "Arcanite Reaper", ... } }
local function Links(msg)
    local out = { items = {}, spells = {}, names = {} }
    for id in msg:gmatch("|Hitem:(%d+)") do out.items[#out.items + 1] = tonumber(id) end
    for id in msg:gmatch("|Henchant:(%d+)") do out.spells[#out.spells + 1] = tonumber(id) end
    for id in msg:gmatch("|Hspell:(%d+)") do out.spells[#out.spells + 1] = tonumber(id) end
    for id in msg:gmatch("|Htrade:[^:]*:(%d+)") do out.spells[#out.spells + 1] = tonumber(id) end
    for name in msg:gmatch("|h%[(.-)%]|h") do out.names[#out.names + 1] = name end
    return out
end
ns.Links = Links

---------------------------------------------------------------------------
-- Classify a chat line
-- returns nil, or {
--   kind = "craft" | "custom", prof = key, recipe = book entry or nil, sure = "sure"/"likely",
--   link = the link they posted, mats = "theirs" / "yours" / nil, origin = city or nil,
--   icon, label }
-- opts: mine = { [prof key] = true } (what you have), all = also other professions,
--       profs = { [prof key] = false } to turn one off, custom = {}, excludes = {}
---------------------------------------------------------------------------
local function WhoMats(tokens)
    if HasAny(tokens, ns.YOUR_MATS) then return "yours" end
    if HasAny(tokens, ns.THEIR_MATS) then return "theirs" end
end

local function Wanted(opts, key)
    if not key then return false end
    if opts.profs and opts.profs[key] == false then return false end
    if opts.mine[key] then return true end
    return opts.all and true or false
end

function ns.Classify(msg, opts)
    if type(msg) ~= "string" or msg == "" then return nil end
    local tokens = ns.Tokens(msg)
    if #tokens == 0 then return nil end

    for _, ex in ipairs(opts.excludes or {}) do
        if PhraseMatch(tokens, ex) then return nil end
    end
    for _, phrase in ipairs(opts.custom or {}) do
        if PhraseMatch(tokens, phrase) then
            return { kind = "custom", icon = ns.ICONS.custom, label = phrase, origin = FindOrigin(tokens) }
        end
    end

    if HasAny(tokens, ns.SELL_WORDS) then return nil end
    local links = Links(msg)
    local asking = HasAny(tokens, ns.ASK_WORDS) or msg:find("%?") ~= nil

    -- which profession they named, if any
    local named
    for _, p in ipairs(ns.PROFS) do
        if HasAny(tokens, p.words) then named = p break end
    end

    if not asking and not named then return nil end
    -- a bare profession word with nothing asking ("enchanting is fun") isn't a request
    if not asking and named and #links.items == 0 and #links.spells == 0 then return nil end

    -- 1. a link to something you can make
    local recipe, link, sure
    for i, id in ipairs(links.items) do
        local e = ns.Book.ByItem(id)
        if e then recipe, link, sure = e, links.names[i], "sure" break end
    end
    if not recipe then
        for _, id in ipairs(links.spells) do
            local e = ns.Book.BySpell(id)
            if e then recipe, sure = e, "sure" break end
        end
    end
    if not recipe and #links.names > 0 then
        for _, name in ipairs(links.names) do
            local e = ns.Book.ByName(name) or ns.Book.ByName("Enchant " .. name)
            if e then recipe, link, sure = e, name, "sure" break end
        end
    end

    -- 2. a recipe by name or nickname, within the profession they named
    if not recipe then
        recipe, sure = ns.Book.FindByText(tokens, named and named.key or nil, Close)
        -- without a profession word, only a sure match counts as a request
        if recipe and not named and sure ~= "sure" then recipe = nil end
    end

    local prof = recipe and ns.PROF_BY_KEY[recipe.prof] or named
    if not prof then return nil end
    if not Wanted(opts, prof.key) then return nil end
    -- a link on its own, with no profession word and nothing asking, is just someone showing off
    if not asking and not recipe then return nil end
    -- the linked item isn't one of yours and they didn't name a profession: not for you
    if not recipe and not named then return nil end

    local label
    if recipe then
        label = prof.name .. ": " .. (recipe.enchant and (recipe.slot and (recipe.effect .. " (" .. recipe.slot:lower() .. ")") or recipe.name)
                                       or recipe.callName or recipe.name)
    elseif link then
        label = prof.name .. ": " .. link
    elseif prof.key == "lockpicking" then
        label = "Lockbox"
    else
        label = "Wants " .. prof.who
    end

    return {
        kind = "craft", prof = prof.key, recipe = recipe, sure = sure, link = link or (links.names[1]),
        linkedItem = links.items[1], mats = WhoMats(tokens), origin = FindOrigin(tokens),
        icon = (recipe and recipe.icon) or prof.icon, label = label,
    }
end

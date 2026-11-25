-- Mage Services: chat matching.
-- Works out whether a chat line is someone asking for a portal, for water/food, or for
-- one of your own custom phrases. Matching is loose: case and punctuation are ignored,
-- and longer words can be one letter off ("portl", "watr", "orgrimar").

local ADDON_NAME, ns = ...

---------------------------------------------------------------------------
-- Word lists
---------------------------------------------------------------------------
local PORT_WORDS  = { "port", "ports", "portal", "portals", "teleport" }
local WATER_WORDS = { "water", "waters", "food", "conjured", "refreshment", "table", "bread" }
-- words that make it a request rather than a statement
local ASK_WORDS   = { "wtb", "lf", "lfm", "need", "needs", "buy", "buying", "any", "anyone", "mage",
                      "plz", "pls", "please", "can", "someone" }
-- words that mean it's another mage advertising, not a customer
local SELL_WORDS  = { "wts", "selling", "sell", "offering", "lfw" }
-- "water" used for something other than drinks
local NOT_DRINK   = { "walking", "breathing", "elemental", "elementals", "totem" }

-- Destinations. Short aliases match exactly; longer ones allow one typo.
-- strict = only counts straight after "to", "port" or "portal" (for "if", a common word).
ns.DESTINATIONS = {
    Horde = {
        { name = "Orgrimmar",     icon = "Interface\\Icons\\Spell_Arcane_PortalOrgrimmar",
          aliases = { "org", "orgri", "ogri", "orgrimmar", "ogrimmar" } },
        { name = "Undercity",     icon = "Interface\\Icons\\Spell_Arcane_PortalUnderCity",
          aliases = { "uc", "undercity", "under city" } },
        { name = "Thunder Bluff", icon = "Interface\\Icons\\Spell_Arcane_PortalThunderBluff",
          aliases = { "tb", "thunderbluff", "thunder bluff", "bluff" } },
    },
    Alliance = {
        { name = "Stormwind",     icon = "Interface\\Icons\\Spell_Arcane_PortalStormWind",
          aliases = { "sw", "stormwind", "storm wind" } },
        { name = "Ironforge",     icon = "Interface\\Icons\\Spell_Arcane_PortalIronForge",
          aliases = { "ironforge", "iron forge", { word = "if", strict = true } } },
        { name = "Darnassus",     icon = "Interface\\Icons\\Spell_Arcane_PortalDarnassus",
          aliases = { "darn", "darna", "darnassus", "darnasus" } },
    },
}

ns.ICONS = {
    port   = "Interface\\Icons\\Spell_Nature_AstralRecal",
    water  = "Interface\\Icons\\INV_Drink_18",
    custom = "Interface\\Icons\\INV_Misc_Note_01",
}

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

-- Same word, or one letter off when both are 5+ letters (so "port" won't match "post").
local function Close(a, b)
    if a == b then return true end
    if #a < 5 or #b < 5 or math.abs(#a - #b) > 1 then return false end
    return Levenshtein(a, b) <= 1
end

function ns.Tokens(msg)
    local s = msg:lower()
    s = s:gsub("|h%[(.-)%]|h", "%1")      -- item/spell links: keep the name
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|h", ""):gsub("|H[^|]*", "")
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

local function HasAny(tokens, list)
    for _, w in ipairs(list) do
        if FindWord(tokens, w) then return true end
    end
    return false
end

-- Every word of the phrase appears somewhere in the message (order doesn't matter).
local function PhraseMatch(tokens, phrase)
    local any = false
    for w in phrase:lower():gsub("[^%w]", " "):gmatch("%S+") do
        any = true
        if not FindWord(tokens, w) then return false end
    end
    return any
end

local function AliasMatch(tokens, alias)
    if type(alias) == "table" then
        for i, t in ipairs(tokens) do
            if t == alias.word then
                local before = tokens[i - 1]
                if not alias.strict or before == "to" or before == "port" or before == "portal" then
                    return true
                end
            end
        end
        return false
    end
    return PhraseMatch(tokens, alias)
end

-- Words that introduce where the person is now: "from org", "in tb", "at uc".
local ORIGIN_MARKERS = { from = true, frm = true, ["in"] = true, at = true }

-- Finds where the person says they are. Returns the city (if it's one we know), the raw
-- words after "from" (for non-city zones like "crossroads"), and the token positions used.
local function FindOrigin(tokens)
    for i, t in ipairs(tokens) do
        if ORIGIN_MARKERS[t] then
            local window = { tokens[i + 1], tokens[i + 2] }
            for _, f in ipairs({ "Horde", "Alliance" }) do
                for _, d in ipairs(ns.DESTINATIONS[f]) do
                    for _, alias in ipairs(d.aliases) do
                        local a = type(alias) == "table" and alias.word or alias
                        if #window > 0 and PhraseMatch(window, a) then
                            return d, nil, { [i] = true, [i + 1] = true, [i + 2] = true }
                        end
                    end
                end
            end
            if t == "from" or t == "frm" then
                local words = {}
                for j = i + 1, math.min(i + 3, #tokens) do
                    if tokens[j] == "to" then break end
                    words[#words + 1] = tokens[j]
                end
                if #words > 0 then
                    local used = {}
                    for j = i, i + #words do used[j] = true end
                    return nil, table.concat(words, " "), used
                end
            end
        end
    end
end

-- True when every word of `phrase` appears in `text` (loosely). Used for zone names.
function ns.TextMatches(text, phrase)
    if type(text) ~= "string" or type(phrase) ~= "string" then return false end
    return PhraseMatch(ns.Tokens(text), phrase)
end

local function FindDestination(tokens, faction, allFactions)
    local sets = allFactions and { "Horde", "Alliance" } or { faction }
    for _, f in ipairs(sets) do
        for _, d in ipairs(ns.DESTINATIONS[f] or {}) do
            for _, alias in ipairs(d.aliases) do
                if AliasMatch(tokens, alias) then return d end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Classify a chat line
-- returns nil, or { kind = "port"|"water"|"custom", dest = name|nil, icon = path, label = text }
---------------------------------------------------------------------------
function ns.Classify(msg, opts)
    if type(msg) ~= "string" or msg == "" then return nil end
    local tokens = ns.Tokens(msg)
    if #tokens == 0 then return nil end

    -- your own excluded words beat everything
    for _, ex in ipairs(opts.excludes or {}) do
        if PhraseMatch(tokens, ex) then return nil end
    end

    -- custom phrases are matched first, exactly as you wrote them (loosely)
    for _, phrase in ipairs(opts.custom or {}) do
        if PhraseMatch(tokens, phrase) then
            return { kind = "custom", icon = ns.ICONS.custom, label = phrase }
        end
    end

    if HasAny(tokens, SELL_WORDS) then return nil end

    local asking = HasAny(tokens, ASK_WORDS) or msg:find("%?") ~= nil

    if opts.ports and asking and HasAny(tokens, PORT_WORDS) then
        -- work out where they are first, then look for the destination in the other words
        local origin, originText, used = FindOrigin(tokens)
        local rest = tokens
        if used then
            rest = {}
            for i, t in ipairs(tokens) do
                if not used[i] then rest[#rest + 1] = t end
            end
        end
        local d = FindDestination(rest, opts.faction, opts.allFactions)
        return {
            kind = "port",
            dest = d and d.name or nil,
            icon = d and d.icon or ns.ICONS.port,
            label = d and ("Port: " .. d.name) or "Port",
            origin = origin and origin.name or nil,
            originText = originText,
        }
    end

    if opts.water and asking and HasAny(tokens, WATER_WORDS) and not HasAny(tokens, NOT_DRINK) then
        return { kind = "water", icon = ns.ICONS.water, label = "Water / food" }
    end

    return nil
end

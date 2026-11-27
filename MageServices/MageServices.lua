-- Mage Services (WoW Forever)
-- Watches chat for people asking for a portal or for water/food (or your own custom
-- phrases) and lists them in a small window with Invite and Whisper buttons.
--
-- Whisper doesn't send anything by itself: it opens your chat box with a reply already
-- typed, and you press Enter. Auto-invite is optional and off by default.
--
-- Requests are ranked by where the person is compared with you (your current zone, or a
-- city you pick): people near you go to the top, people who say they're elsewhere, or who
-- want a port to the city you're already in, are dimmed at the bottom.
--
-- Forever hides chat text from addons inside dungeons, raids, M+ and PvP, so it only
-- works out in the world, which is where people ask for ports and water anyway.

local ADDON_NAME, ns = ...

-- Key Bindings > AddOns > Mage Services
BINDING_HEADER_MAGESERVICES = "Mage Services"
_G["BINDING_NAME_CLICK MageServicesCastButton:LeftButton"] = "Cast the requested portal"
BINDING_NAME_MAGESERVICES_TOGGLEPAUSE = "Pause or resume the service"
BINDING_NAME_MAGESERVICES_ADVERTISE = "Post your advert"

local defaults = {
    updateNotice = true,  -- "a newer version is out" chat notice (VersionCheck.lua)
    ports       = true,
    water       = true,
    allFactions = false,  -- also match the other faction's cities
    -- channels to watch
    chTrade = true,       -- Trade, General, LookingForGroup and other numbered channels
    chSay   = true,       -- say and yell
    chWhisper = true,
    chGuild = true,
    -- alerts
    sound  = true,
    soundKey = "TELL_MESSAGE", -- which game sound plays (see /ms sounds)
    flash  = true,        -- flash the WoW icon on the taskbar
    autoInvite = false,
    expire = 120,         -- seconds a request stays in the list
    -- location
    zone = "auto",        -- "auto" = the zone you're in, or a city name you pick
    scope = "nearby",     -- which requests show: "here" (your city only), "nearby" (your city +
                          -- unknown), "all" (everything, the rest dimmed)
    alertLow = false,     -- sound/flash/glow for low-priority requests too
    -- on-screen alerts
    glowBar = true,       -- glow the matching Portal / Conjure button on your action bars
    screenMsg = true,     -- short message at the top of the screen
    edgeFlash = true,     -- flash the edges of the screen
    glowTime = 20,        -- seconds a button keeps glowing
    -- payments
    receiptMode = "auto", -- "auto" posts by itself, "prefill" types it for you, "off"
    receiptAll  = false,  -- post for every trade, not just people who asked or are in your group
    paidMsg   = "Payment received from {name}: {amount}. Thanks, safe travels!",
    hideAmount = true,    -- keep the gold amount out of payment messages
    paidMsgPrivate = "Payment received, thanks {name}! Safe travels.",
    noPayMsg  = "Trade with {name} completed, but no payment was included.",
    cancelMsg = "Trade with {name} was cancelled. No payment received.",
    failMsg   = "Trade with {name} failed ({reason}). No payment received.",
    maxRows = 6,
    custom = {},          -- your own phrases, e.g. "lf summon"
    excludes = {},        -- phrases that should never match
    portMsg  = "Hi {name}, I can port you to {dest}. Sending you an invite now.",
    waterMsg = "Hi {name}, I've got water and food for you. Sending you an invite now.",
    customMsg = "Hi {name}, sending you an invite now.",
    -- automatic replies to whispers (off until you turn them on)
    autoReply = false,
    autoReplyCant = true, -- also answer when you can't help
    autoReplyGap = 5,     -- minutes before the same player gets another automatic reply
    cantMsg = "Sorry {name}, I can't help with that one right now.",
    point = { "CENTER", "CENTER", 300, 100 },
    theme = "dark",       -- "dark" or "light"
    -- runes and your group (Group.lua)
    runeCount = true,     -- rune counts at the bottom right of the window
    runeLow = 5,          -- warn when Runes of Portals fall below this
    kickAfterPort = false,-- remove customers from the group once they've gone through your portal
    -- your own advert (the Advertise button, /ms ad or a key binding)
    adMsg     = "Mage in {zone} selling {services}. Whisper me!",
    adChannel = "trade",  -- trade, general, say or yell
    adGap     = 3,        -- minutes between adverts
    idleBar   = false,    -- keep a slim bar (with Advertise) when there are no requests
}

ns.defaults = defaults
local db
local requests = {}   -- newest first: { sender, short, msg, info, time }
ns.requests = requests
local testMode = false

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0Mage Services:|r " .. msg)
end
ns.Print = Print

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

---------------------------------------------------------------------------
-- Player names
--
-- Forever characters have a first AND last name ("John Blizzard"), and the full name is
-- what identifies them. So names are never cut down to the first word except for
-- friendly greetings. The game hands names over as "John Blizzard" or "John-Blizzard"
-- depending on where they come from, so comparisons use a key that ignores spaces,
-- hyphens and case.
---------------------------------------------------------------------------
local function Clean(name)
    if type(name) ~= "string" or IsSecret(name) then return nil end
    return name
end

-- "John Blizzard", "John-Blizzard", "john blizzard" -> "johnblizzard"
function ns.NameKey(name)
    name = Clean(name)
    if not name then return "" end
    return (name:lower():gsub("[%s%-]", ""))
end

-- For showing in the list: "John-Blizzard" -> "John Blizzard"
function ns.DisplayName(name)
    name = Clean(name)
    return name and (name:gsub("%-", " ")) or "?"
end

-- For greetings in messages: "John Blizzard" -> "John"
function ns.FirstName(name)
    name = Clean(name)
    return name and (name:match("^[^%s%-]+") or name) or "there"
end

-- A unit's full name, joining whatever parts the game gives.
function ns.UnitFull(unit)
    if GetUnitName then
        local ok, full = pcall(GetUnitName, unit, true)
        if ok and Clean(full) and full ~= "" then
            if UnitFullName then
                local ok2, first, last = pcall(UnitFullName, unit)
                -- some clients give only the first name here; add the surname if it's separate
                if ok2 and Clean(last) and last ~= "" and not full:find(last, 1, true) then
                    return full .. " " .. last
                end
            end
            return full
        end
    end
    if UnitFullName then
        local ok, first, last = pcall(UnitFullName, unit)
        if ok and Clean(first) then
            return (Clean(last) and last ~= "") and (first .. " " .. last) or first
        end
    end
    local n = UnitName and UnitName(unit)
    return Clean(n)
end

-- Is someone with this name key in your party or raid?
function ns.InGroupWith(key)
    if key == "" then return false end
    local prefix, count = "party", 4
    if IsInRaid and IsInRaid() then prefix, count = "raid", 40 end
    for i = 1, count do
        local unit = prefix .. i
        if UnitExists and UnitExists(unit) and ns.NameKey(ns.UnitFull(unit)) == key then return true end
    end
    return false
end

-- Opens the chat box in whisper mode aimed at this exact name, with the text typed in.
-- This skips "/w Name text" parsing, which splits two-part names at the space.
function ns.OpenWhisperTo(name, text)
    local sendTell = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
    if sendTell then
        local ok = pcall(sendTell, name)
        if ok then
            local box = (ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow())
                or (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow())
                or (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox)
            if box and box.Insert then
                box:Insert(text)
                return
            end
        end
    end
    -- older clients: fall back to the typed command
    local line = "/w " .. name .. " " .. text
    if ChatFrameUtil and ChatFrameUtil.OpenChat then
        ChatFrameUtil.OpenChat(line)
    elseif ChatFrame_OpenChat then
        ChatFrame_OpenChat(line)
    end
end

local function Faction()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    return (f == "Alliance") and "Alliance" or "Horde"
end

local function MatchOptions()
    return {
        ports = db.ports, water = db.water,
        faction = Faction(), allFactions = db.allFactions,
        custom = db.custom, excludes = db.excludes,
    }
end

---------------------------------------------------------------------------
-- Location and priority
---------------------------------------------------------------------------
local HIGH, NORMAL, LOW = 3, 2, 1

-- The zone the game says you're in right now ("" while a loading screen is up).
function ns.RealZone()
    local z = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
    if IsSecret(z) then return "" end
    return z
end

-- The zone used for ranking: the one you picked, or the real one.
function ns.MyZone()
    if db.zone and db.zone ~= "auto" then return db.zone end
    return ns.RealZone()
end

local function SameZone(a, b)
    if not a or not b or a == "" or b == "" then return false end
    if a:lower() == b:lower() then return true end
    return ns.TextMatches(a, b) or ns.TextMatches(b, a)
end

-- Can you cast what this request needs? Portals you haven't learned (or the other
-- faction's cities) and water before you can conjure it count as "can't help".
-- Answers are cached and cleared when your spells change.
local PORTAL_IDS = {
    ["Portal: Orgrimmar"] = 11417, ["Portal: Undercity"] = 11418, ["Portal: Thunder Bluff"] = 11420,
    ["Portal: Stormwind"] = 10059, ["Portal: Ironforge"] = 11416, ["Portal: Darnassus"] = 11419,
}
local WATER_SPELLS = { "Conjure Water", "Conjure Food", "Conjure Refreshment" }
local knownCache = {}

local function Truthy(ok, v) return ok and v ~= nil and v ~= false and not IsSecret(v) end

-- true = known, false = not known, nil = the game gave no way to tell
local function KnowsSpell(name)
    if knownCache[name] ~= nil then return knownCache[name] end
    local asked, known = false, false
    local id = PORTAL_IDS[name]
    if id and IsPlayerSpell then
        asked = true
        if Truthy(pcall(IsPlayerSpell, id)) then known = true end
    end
    if not known and C_SpellBook and C_SpellBook.FindSpellBookSlotForSpell then
        -- portals sit in a flyout on this client, so include flyouts
        asked = true
        if Truthy(pcall(C_SpellBook.FindSpellBookSlotForSpell, name, false, true, false, false)) then known = true end
        if not known and id and Truthy(pcall(C_SpellBook.FindSpellBookSlotForSpell, id, false, true, false, false)) then known = true end
    end
    if not asked then return nil end
    knownCache[name] = known
    return known
end

function ns.SpellsChanged() wipe(knownCache) end

-- Returns nil if you can help, or the reason you can't.
local function CantCast(info)
    if not UnitClass then return nil end
    local _, class = UnitClass("player")
    if class ~= "MAGE" then return nil end -- the check only makes sense on a mage
    if info.kind == "port" and info.dest then
        local spell = "Portal: " .. info.dest
        if KnowsSpell(spell) == false then return "you don't have " .. spell end
    elseif info.kind == "water" then
        local anyAnswer, anyKnown = false, false
        for _, name in ipairs(WATER_SPELLS) do
            local k = KnowsSpell(name)
            if k ~= nil then anyAnswer = true end
            if k then anyKnown = true break end
        end
        if anyAnswer and not anyKnown then return "you can't conjure water yet" end
    end
    return nil
end

ns.CantCast = CantCast

-- Where guildmates and friends are, read from the guild and friends lists (no /who needed).
local rosterZones = {} -- [name key] = { zone = , how = "guild" or "friend" }
local lastRoster = 0

local function AddRoster(name, zone, how)
    if type(name) ~= "string" or type(zone) ~= "string" or IsSecret(name) or IsSecret(zone) or zone == "" then return end
    local entry = { zone = zone, how = how }
    rosterZones[ns.NameKey(name)] = entry
    if Ambiguate then
        local ok, short = pcall(Ambiguate, name, "short")
        if ok and type(short) == "string" and not IsSecret(short) then rosterZones[ns.NameKey(short)] = entry end
    end
end

function ns.RebuildRoster(force)
    local now = GetTime()
    if not force and now - lastRoster < 5 then return end
    lastRoster = now
    wipe(rosterZones)
    if IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
        local ok, n = pcall(GetNumGuildMembers)
        if ok and type(n) == "number" and not IsSecret(n) then
            for i = 1, n do
                local ok2, name, _, _, _, _, zone, _, _, online = pcall(GetGuildRosterInfo, i)
                if ok2 and online and not IsSecret(online) then AddRoster(name, zone, "guild") end
            end
        end
    end
    if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
        local ok, n = pcall(C_FriendList.GetNumFriends)
        if ok and type(n) == "number" and not IsSecret(n) then
            for i = 1, n do
                local ok2, f = pcall(C_FriendList.GetFriendInfoByIndex, i)
                if ok2 and type(f) == "table" and f.connected and not IsSecret(f.connected) then
                    AddRoster(f.name, f.area, "friend")
                end
            end
        end
    end
end

-- Returns priority and a short reason shown on the row.
local function Rank(req)
    local info, here = req.info, ns.MyZone()

    local cant = CantCast(info)
    if cant then return LOW, cant end

    if info.kind == "port" and info.dest and SameZone(info.dest, here) then
        return LOW, "wants " .. info.dest .. ", you're already there"
    end

    if req.whoZone then
        if SameZone(req.whoZone, here) then return HIGH, "in your zone (/who)" end
        return LOW, "they're in " .. req.whoZone .. " (/who)"
    end
    local roster = rosterZones[req.key]
    if roster then
        if SameZone(roster.zone, here) then return HIGH, "in your zone (" .. roster.how .. ")" end
        return LOW, "they're in " .. roster.zone .. " (" .. roster.how .. ")"
    end
    if req.whoPending then return NORMAL, "looking up..." end
    if req.whoFailed then return NORMAL, "no /who reply, click ? again" end

    local origin = info.origin or info.originText
    if origin then
        if SameZone(origin, here) then return HIGH, "in your zone" end
        return LOW, "they're in " .. origin
    end

    -- say/yell and General/LocalDefense come from where you actually are (or the channel's
    -- zone), which isn't always the zone you picked
    if req.source == "say" then
        if req.heardIn and req.heardIn ~= "" and not SameZone(req.heardIn, here) then
            return LOW, "they're in " .. req.heardIn
        end
        return HIGH, "near you"
    end
    if req.source == "local" then
        local zone = req.heardIn or req.zoneAtReceive
        if SameZone(zone, here) then return HIGH, "in your zone" end
        return LOW, "they're in " .. (zone or "another zone")
    end

    return NORMAL, nil
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
ns.invited = {} -- [name key] = when you invited them from Mage Services

local function Invite(name)
    ns.invited[ns.NameKey(name)] = GetTime()
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(name)
    elseif InviteUnit then
        InviteUnit(name)
    end
end
ns.Invite = Invite

-- everyone in the list going to the same city as this request, not yet in your group
local function SameTrip(req, list)
    local out = {}
    if not (req.info and req.info.kind == "port" and req.info.dest) then return out end
    for _, r in ipairs(list or requests) do
        if r.info and r.info.kind == "port" and r.info.dest == req.info.dest
            and not ns.InGroupWith(ns.NameKey(r.sender)) then
            out[#out + 1] = r
        end
    end
    return out
end
ns.SameTrip = SameTrip

---------------------------------------------------------------------------
-- Advertise: post your own line ("Mage in Orgrimmar: portals to UC and TB, food and water.")
-- Posting to a chat channel needs a click or key press, so it only goes out from the
-- Advertise button, /ms ad or the key binding, and at most once every few minutes.
---------------------------------------------------------------------------
local CITY_SHORT = { Orgrimmar = "Org", Undercity = "UC", ["Thunder Bluff"] = "TB",
                     Stormwind = "SW", Ironforge = "IF", Darnassus = "Darn" }
local FACTION_CITIES = { Horde = { "Orgrimmar", "Undercity", "Thunder Bluff" },
                         Alliance = { "Stormwind", "Ironforge", "Darnassus" } }
local AD_CHANNELS = { trade = "Trade", general = "General", say = "Say", yell = "Yell" }
local lastAd = -1e9

local function JoinList(list)
    if #list <= 1 then return list[1] or "" end
    return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end

-- "UC, Org and TB", and "portals to UC, Org and TB, food and water"
function ns.AdParts()
    local cities = {}
    for _, c in ipairs(FACTION_CITIES[Faction()]) do
        if KnowsSpell("Portal: " .. c) ~= false then cities[#cities + 1] = CITY_SHORT[c] end
    end
    local water = KnowsSpell("Conjure Water") ~= false or KnowsSpell("Conjure Food") ~= false
    local services = ""
    if #cities > 0 and water then
        services = "portals to " .. JoinList(cities) .. ", plus food and water"
    elseif #cities > 0 then
        services = "portals to " .. JoinList(cities)
    elseif water then
        services = "food and water"
    end
    return JoinList(cities), services
end

function ns.FillAd(template)
    local portals, services = ns.AdParts()
    local zone = ns.MyZone()
    if zone == "" then zone = "town" end
    local values = { services = services, portals = portals, zone = zone }
    return ((template or ""):gsub("{(%a+)}", function(k) return values[k] end))
end

local function FindChannel(prefix)
    if not GetChannelList then return nil end
    local list = { GetChannelList() }
    for i = 1, #list, 3 do
        local id, name = list[i], list[i + 1]
        if type(name) == "string" and not IsSecret(name) and name:lower():find("^" .. prefix) then return id end
    end
end

-- seconds until the next advert is allowed (0 = now)
function ns.AdWait()
    return math.max(0, (db.adGap or 3) * 60 - (GetTime() - lastAd))
end

function ns.Advertise()
    if not db then return end
    if ns.IsPaused() then Print("paused: resume first (the Resume button or /ms resume).") return end
    local wait = ns.AdWait()
    if wait > 0 then
        Print(("you can advertise again in %d:%02d (every %d min, set on the settings page)."):format(
            math.floor(wait / 60), math.ceil(wait) % 60, db.adGap))
        return
    end
    local _, services = ns.AdParts()
    if services == "" and db.adMsg:find("{services}") then
        Print("nothing to advertise: no portals or Conjure Water on this character.")
        return
    end
    local text = ns.FillAd(db.adMsg)
    local ch = db.adChannel or "trade"
    local ok
    if ch == "say" or ch == "yell" then
        ok = ns.SendChat(text, ch:upper())
    else
        local id = FindChannel(ch)
        if not id then
            Print(("you're not in %s chat here. Try it in a city, or pick another channel on the settings page."):format(AD_CHANNELS[ch] or ch))
            return
        end
        ok = ns.SendChat(text, "CHANNEL", id)
    end
    if ok then
        lastAd = GetTime()
        if ns.Refresh then ns.Refresh() end
    else
        Print("the game didn't let that go out.")
    end
end

function MageServices_Advertise()
    if ns.Advertise then ns.Advertise() end
end

local function InviteTrip(req, list)
    local trip = SameTrip(req, list)
    for _, r in ipairs(trip) do Invite(r.sender) end
    if #trip > 0 then
        Print(("invited %d going to %s: %s"):format(#trip, req.info.dest,
            table.concat((function() local n = {} for _, r in ipairs(trip) do n[#n + 1] = r.display or r.sender end return n end)(), ", ")))
    end
end

-- {name} = their first name, {dest} = the city they asked for, {zone} = where you are
local function FillTemplate(template, req)
    local dest = (req.info and req.info.dest) or "your city"
    local zone = ns.MyZone()
    if zone == "" then zone = "town" end
    local out = tostring(template or "")
    out = out:gsub("{name}", function() return req.first or "" end)
    out = out:gsub("{dest}", function() return dest end)
    out = out:gsub("{zone}", function() return zone end)
    return out:sub(1, 255) -- the game's chat limit
end

local function ReplyTemplate(req)
    if req.info.kind == "port" then return db.portMsg end
    if req.info.kind == "water" then return db.waterMsg end
    return db.customMsg
end

local function OpenWhisper(req)
    ns.OpenWhisperTo(req.sender, FillTemplate(ReplyTemplate(req), req))
end

-- Example for the settings page.
function ns.SampleReply(template, kind)
    local info = { kind = kind, dest = kind == "port" and "Undercity" or nil }
    return FillTemplate(template, { first = "Lil", info = info })
end

-- Shown under the auto-reply settings when the wording promises an invite that won't come.
function ns.ReplyWarning()
    if not (db and db.autoReply) or db.autoInvite then return "" end
    for _, k in ipairs({ "portMsg", "waterMsg", "customMsg" }) do
        if tostring(db[k] or ""):lower():find("invite") then
            return "|cffff8040Your replies mention an invite, but \"Invite them automatically\" is off.|r"
        end
    end
    return ""
end

-- Automatic reply to someone who whispered you a request. Only whispers (never
-- Trade or General posts), at most once per player per few minutes, never in test mode.
local lastAutoReply = {}
local function AutoReply(req)
    if not db.autoReply or testMode then return end
    local now = GetTime()
    local last = lastAutoReply[req.key]
    if last and now - last < (db.autoReplyGap or 5) * 60 then return end

    local template
    if req.priority == LOW then
        if not db.autoReplyCant then return end
        template = db.cantMsg
    else
        template = ReplyTemplate(req)
    end
    lastAutoReply[req.key] = now
    local ok = ns.SendChat and ns.SendChat(FillTemplate(template, req), "WHISPER", req.sender)
    if ok then
        req.replied = true
    else
        Print("couldn't send the automatic reply to " .. req.display .. ". Use the Whisper button instead.")
    end
end

---------------------------------------------------------------------------
-- Themes
---------------------------------------------------------------------------
local WHITE = "Interface\\Buttons\\WHITE8x8"

-- Colours are {r, g, b[, a]}; hex strings are used inside text.
local THEMES = {
    dark = {
        bg = { 0.07, 0.07, 0.09, 0.95 }, header = { 0.12, 0.12, 0.16, 1 }, border = { 0.41, 0.8, 0.94, 0.9 },
        title = { 0.41, 0.8, 0.94 }, label = { 1, 0.82, 0 }, text = { 0.88, 0.88, 0.88 }, footer = { 0.72, 0.72, 0.72 },
        high = { 1, 0.82, 0, 0.12 }, sel = { 0.41, 0.8, 0.94, 0.2 }, divider = { 1, 1, 1, 0.07 },
        btn = { 0.16, 0.16, 0.2, 1 }, btnHover = { 0.25, 0.25, 0.31, 1 }, btnBorder = { 0.32, 0.32, 0.38, 1 },
        btnText = { 0.92, 0.92, 0.92 },
        accent = { 0.16, 0.42, 0.56, 1 }, accentHover = { 0.22, 0.52, 0.68, 1 }, accentText = { 1, 1, 1 },
        good = "4cd964", muted = "a0a0a0", dim = "8a8a8a", shadow = true,
    },
    light = {
        bg = { 0.96, 0.96, 0.94, 0.97 }, header = { 0.87, 0.9, 0.93, 1 }, border = { 0.25, 0.5, 0.65, 1 },
        title = { 0.1, 0.33, 0.5 }, label = { 0.12, 0.12, 0.12 }, text = { 0.3, 0.3, 0.3 }, footer = { 0.33, 0.33, 0.33 },
        high = { 1, 0.78, 0.1, 0.22 }, sel = { 0.25, 0.55, 0.85, 0.18 }, divider = { 0, 0, 0, 0.09 },
        btn = { 0.9, 0.9, 0.9, 1 }, btnHover = { 0.8, 0.85, 0.9, 1 }, btnBorder = { 0.68, 0.68, 0.7, 1 },
        btnText = { 0.12, 0.12, 0.12 },
        accent = { 0.2, 0.47, 0.66, 1 }, accentHover = { 0.27, 0.56, 0.77, 1 }, accentText = { 1, 1, 1 },
        good = "1d8a3a", muted = "666666", dim = "8c8c8c", shadow = false,
    },
}
ns.THEMES = THEMES

function ns.Theme()
    return THEMES[(db and db.theme) or "dark"] or THEMES.dark
end

local function Color(obj, method, c) obj[method](obj, c[1], c[2], c[3], c[4] or 1) end

local function StyleText(fs, c)
    local t = ns.Theme()
    fs:SetTextColor(c[1], c[2], c[3])
    if t.shadow then fs:SetShadowOffset(1, -1) else fs:SetShadowOffset(0, 0) end
end

-- Flat buttons drawn in the theme's colours.
local buttons = {}

local function PaintButton(b)
    local t = ns.Theme()
    local base = b.primary and t.accent or t.btn
    local hover = b.primary and t.accentHover or t.btnHover
    Color(b, "SetBackdropColor", b.hovered and hover or base)
    Color(b, "SetBackdropBorderColor", b.primary and base or t.btnBorder)
    StyleText(b.text, b.primary and t.accentText or t.btnText)
end

local function FlatButton(parent, w, h, label, primary)
    local b = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    b:SetSize(w, h)
    if b.SetBackdrop then b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 }) end
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("CENTER", 0, 0)
    b.text:SetText(label)
    b.primary = primary
    b:HookScript("OnEnter", function(self) self.hovered = true; PaintButton(self) end)
    b:HookScript("OnLeave", function(self) self.hovered = false; PaintButton(self) end)
    buttons[#buttons + 1] = b
    PaintButton(b)
    return b
end

---------------------------------------------------------------------------
-- Request window
--
--   +-----------------------------------------------------------+
--   | Mage Services  Orgrimmar                     [Clear] [x]  |  header 24
--   +-----------------------------------------------------------+
--   | [icon] Port: Undercity  in your zone  Bob, 4s  [?][Invite][Whisper][x] |  rows 30
--   |        LF port to UC pls                                  |
--   +-----------------------------------------------------------+
--   | Earned 12g (portals 10g, water 2g)  this session 1g 50s   |  footer 20
--   +-----------------------------------------------------------+
---------------------------------------------------------------------------
local WIDTH, HEADER_H, ROW_H, FOOTER_H, PAD = 460, 24, 30, 20, 6

local win = CreateFrame("Frame", "MageServicesFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
win:SetSize(WIDTH, 60)
win:SetFrameStrata("MEDIUM")
win:SetClampedToScreen(true)
win:SetMovable(true)
win:EnableMouse(true)
win:RegisterForDrag("LeftButton")
win:SetScript("OnDragStart", win.StartMoving)
win:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    db.point = { p, rp, x, y }
end)
if win.SetBackdrop then win:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 }) end
win:Hide()
ns.win = win

win.header = win:CreateTexture(nil, "BORDER")
win.header:SetPoint("TOPLEFT", 1, -1)
win.header:SetPoint("TOPRIGHT", -1, -1)
win.header:SetHeight(HEADER_H)

win.close = FlatButton(win, 18, 18, "x")
win.close:SetPoint("RIGHT", win.header, "RIGHT", -4, 0)

win.clear = FlatButton(win, 46, 18, "Clear")
win.clear:SetPoint("RIGHT", win.close, "LEFT", -4, 0)

win.pause = FlatButton(win, 58, 18, "Pause")
win.pause:SetPoint("RIGHT", win.clear, "LEFT", -4, 0)

win.ad = FlatButton(win, 70, 18, "Advertise")
win.ad:SetPoint("RIGHT", win.pause, "LEFT", -4, 0)
win.ad:SetScript("OnClick", function() MageServices_Advertise() end)
win.ad:HookScript("OnEnter", function(self)
    if not db then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Post your advert in " .. (({ trade = "Trade", general = "General", say = "Say", yell = "Yell" })[db.adChannel] or db.adChannel))
    GameTooltip:AddLine(ns.FillAd(db.adMsg), 1, 1, 1, true)
    local wait = ns.AdWait()
    if wait > 0 then GameTooltip:AddLine(("Again in %d:%02d"):format(math.floor(wait / 60), math.ceil(wait) % 60), 0.7, 0.7, 0.7) end
    GameTooltip:AddLine("Edit it on the settings page. Also /ms ad or a key binding.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end)
win.ad:HookScript("OnLeave", function() GameTooltip:Hide() end)

win.title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
win.title:SetPoint("LEFT", win.header, "LEFT", 8, 0)
win.title:SetPoint("RIGHT", win.ad, "LEFT", -8, 0)
win.title:SetJustifyH("LEFT")
win.title:SetWordWrap(false)

win.footerLine = win:CreateTexture(nil, "BORDER")
win.footerLine:SetPoint("BOTTOMLEFT", 1, FOOTER_H)
win.footerLine:SetPoint("BOTTOMRIGHT", -1, FOOTER_H)
win.footerLine:SetHeight(1)

win.footer = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
win.footer:SetPoint("BOTTOMLEFT", 8, 0)
win.footer:SetPoint("BOTTOMRIGHT", -8, 0)
win.footer:SetHeight(FOOTER_H)
win.footer:SetJustifyH("LEFT")
win.footer:SetWordWrap(false)

local rows = {}
local Refresh -- forward

local function Remove(req)
    for i, r in ipairs(requests) do
        if r == req then table.remove(requests, i) break end
    end
    Refresh()
end

local function Tooltip(btn, title, body)
    btn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(title)
        if body then GameTooltip:AddLine(body, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function MakeRow(i)
    local row = CreateFrame("Frame", nil, win)
    row:SetSize(WIDTH - 2, ROW_H)
    row:SetPoint("TOPLEFT", 1, -(1 + HEADER_H + (i - 1) * ROW_H))

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()

    row.sel = row:CreateTexture(nil, "BORDER")
    row.sel:SetAllPoints()
    row.sel:Hide()

    row.line = row:CreateTexture(nil, "BORDER")
    row.line:SetPoint("BOTTOMLEFT", PAD, 0)
    row.line:SetPoint("BOTTOMRIGHT", -PAD, 0)
    row.line:SetHeight(1)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(24, 24)
    row.icon:SetPoint("LEFT", PAD + 1, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- buttons, right to left, all 20 high and centred in the row
    row.dismiss = FlatButton(row, 20, 20, "x")
    row.dismiss:SetPoint("RIGHT", -PAD, 0)
    row.whisper = FlatButton(row, 58, 20, "Whisper")
    row.whisper:SetPoint("RIGHT", row.dismiss, "LEFT", -3, 0)
    row.invite = FlatButton(row, 52, 20, "Invite", true)
    row.invite:SetPoint("RIGHT", row.whisper, "LEFT", -3, 0)
    row.all = FlatButton(row, 38, 20, "All 2")
    row.all:SetPoint("RIGHT", row.invite, "LEFT", -3, 0)
    row.all:Hide()
    row.all:HookScript("OnEnter", function(self)
        if not row.req then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Invite everyone going to " .. (row.req.info.dest or "the same city"))
        local names = {}
        for _, r in ipairs(row.trip or {}) do names[#names + 1] = r.display or r.sender end
        GameTooltip:AddLine(table.concat(names, ", "), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row.all:HookScript("OnLeave", function() GameTooltip:Hide() end)
    row.where = FlatButton(row, 20, 20, "?")
    row.where:SetPoint("RIGHT", row.invite, "LEFT", -3, 0)
    Tooltip(row.where, "Where are they?", "Runs a /who on this player and re-ranks the request by their zone.")
    Tooltip(row.dismiss, "Dismiss")

    -- two lines of text between the icon and the buttons, centred on the icon
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.label:SetPoint("BOTTOMLEFT", row.icon, "RIGHT", 8, 1)
    row.label:SetPoint("RIGHT", row.where, "LEFT", -8, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("TOPLEFT", row.icon, "RIGHT", 8, -1)
    row.text:SetPoint("RIGHT", row.where, "LEFT", -8, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if not self.req then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(self.req.sender, 0.41, 0.8, 0.94)
        GameTooltip:AddLine(self.req.msg, 1, 1, 1, true)
        GameTooltip:AddLine("Click to put this request on the portal button.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnMouseUp", function(self) if self.req and ns.Select then ns.Select(self.req) end end)

    row.invite:SetScript("OnClick", function() if row.req then Invite(row.req.sender) end end)
    row.all:SetScript("OnClick", function() if row.req then InviteTrip(row.req, row.visible) end end)
    row.where:SetScript("OnClick", function() if row.req then ns.LookupZone(row.req) end end)
    row.whisper:SetScript("OnClick", function() if row.req then OpenWhisper(row.req) end end)
    row.dismiss:SetScript("OnClick", function() if row.req then Remove(row.req) end end)

    rows[i] = row
    ns.ApplyTheme()
    return row
end

-- Repaint everything in the current theme.
function ns.ApplyTheme()
    local t = ns.Theme()
    if win.SetBackdropColor then
        Color(win, "SetBackdropColor", t.bg)
        Color(win, "SetBackdropBorderColor", t.border)
    end
    Color(win.header, "SetColorTexture", t.header)
    Color(win.footerLine, "SetColorTexture", t.divider)
    StyleText(win.title, t.title)
    StyleText(win.footer, t.footer)
    for _, row in ipairs(rows) do
        Color(row.bg, "SetColorTexture", t.high)
        Color(row.sel, "SetColorTexture", t.sel)
        Color(row.line, "SetColorTexture", t.divider)
        StyleText(row.label, t.label)
        StyleText(row.text, t.text)
    end
    for _, b in ipairs(buttons) do PaintButton(b) end
    if ns.ApplyCastTheme then ns.ApplyCastTheme(t) end
    if ns.ApplyBannerTheme then ns.ApplyBannerTheme(t) end
end

-- Paused is saved per character (MageServicesCharDB, set up in Service.lua).
function ns.IsPaused()
    return MageServicesCharDB and MageServicesCharDB.paused and true or false
end

local pausedClosed = false -- closed the paused bar with x: stay hidden until resume or /ms show
local idleClosed = false   -- closed the idle bar with x: stay hidden until a request comes in

local function UpdatePauseButton()
    local p = ns.IsPaused()
    win.pause.text:SetText(p and "Resume" or "Pause")
    win.pause.primary = p
    PaintButton(win.pause)
    win.clear:SetShown(not p)
    win.ad:SetShown(not p)
    if db then
        local wait = ns.AdWait()
        win.ad.text:SetText(wait > 0 and ("Ad %d:%02d"):format(math.floor(wait / 60), math.ceil(wait) % 60) or "Advertise")
    end
    win.pause:ClearAllPoints()
    win.pause:SetPoint("RIGHT", p and win.close or win.clear, "LEFT", -4, 0)
end

Refresh = function()
    if not db then return end
    local t = ns.Theme()
    UpdatePauseButton()

    if ns.IsPaused() then
        -- a slim bar with Resume, so there's always a way back
        for _, row in ipairs(rows) do row.req = nil; row:Hide() end
        win.title:SetText("Mage Services  |cff" .. t.muted .. "paused, not watching chat|r")
        win.footer:SetText(ns.EarningsLine and ns.EarningsLine() or "")
        if ns.UpdateGlows then ns.UpdateGlows({}) end
        if ns.UpdateCastButton then ns.UpdateCastButton({}) end
        win:SetHeight(2 + HEADER_H + FOOTER_H + 1)
        if pausedClosed then win:Hide() else win:Show() end
        return
    end
    local now = GetTime()
    for i = #requests, 1, -1 do
        if now - requests[i].time > db.expire then table.remove(requests, i) end
    end

    for _, r in ipairs(requests) do r.priority, r.reason = Rank(r) end
    table.sort(requests, function(a, b)
        if a.priority ~= b.priority then return a.priority > b.priority end
        return a.time > b.time
    end)

    local visible = requests
    if db.scope ~= "all" then
        visible = {}
        for _, r in ipairs(requests) do
            if not ns.IsHidden(r) then visible[#visible + 1] = r end
        end
    end
    local hiddenCount = #requests - #visible

    local shown = math.min(#visible, db.maxRows)
    for i = 1, math.max(shown, #rows) do
        local row = rows[i] or (i <= shown and MakeRow(i))
        if row then
            local req = visible[i]
            if i <= shown and req then
                row.req = req
                row.icon:SetTexture(req.info.icon)
                local ago = math.floor(now - req.time)
                local tag = ""
                if req.paid then
                    tag = "  |cff" .. t.good .. "paid " .. ns.Money(req.paid) .. "|r"
                elseif req.priority == HIGH then
                    tag = "  |cff" .. t.good .. (req.reason or "near you") .. "|r"
                elseif req.reason then
                    tag = "  |cff" .. t.dim .. req.reason .. "|r"
                end
                if req.replied then tag = tag .. "  |cff" .. t.muted .. "replied|r" end
                row.label:SetText(req.info.label .. tag .. "  |cff" .. t.muted .. req.display .. ", " .. ago .. "s|r")
                row.text:SetText(req.msg)
                row.bg:SetShown(req.priority == HIGH)
                row.sel:SetShown(req.selected and true or false)
                row.line:SetShown(i < shown)
                row:SetAlpha(req.priority == LOW and 0.5 or 1)
                -- two or more going to the same city: one button invites them all
                row.visible = visible
                row.trip = SameTrip(req, visible)
                local together = #row.trip >= 2
                row.all:SetShown(together)
                if together then row.all.text:SetText("All " .. #row.trip) end
                row.where:ClearAllPoints()
                row.where:SetPoint("RIGHT", together and row.all or row.invite, "LEFT", -3, 0)
                row:Show()
            else
                row.req = nil
                row:Hide()
            end
        end
    end

    local extra = #visible - shown
    local where, real = ns.MyZone(), ns.RealZone()
    local note = ""
    if db.zone ~= "auto" then
        -- a picked zone stays put when you travel, so show where you really are if it differs
        note = (real ~= "" and real ~= where) and (" (picked, you're in " .. real .. ")") or " (picked)"
    end
    win.title:SetText("Mage Services"
        .. (where ~= "" and ("  |cff" .. t.muted .. where .. note .. "|r") or "")
        .. (extra > 0 and ("  |cff" .. t.muted .. "+" .. extra .. " more|r") or "")
        .. (hiddenCount > 0 and ("  |cff" .. t.muted .. hiddenCount .. " hidden|r") or ""))
    if ns.UpdateGlows then ns.UpdateGlows(visible) end
    if ns.UpdateCastButton then ns.UpdateCastButton(visible) end
    win.footer:SetText(ns.EarningsLine and ns.EarningsLine() or "")
    win:SetHeight(2 + HEADER_H + shown * ROW_H + FOOTER_H + 1)
    if shown > 0 then
        idleClosed = false
        win:Show()
    elseif db.idleBar and not idleClosed then
        win:Show() -- a slim bar with Advertise while you wait
    else
        win:Hide()
    end
end

ns.Refresh = Refresh
win.clear:SetScript("OnClick", function() wipe(requests); Refresh() end)
win.close:SetScript("OnClick", function()
    if ns.IsPaused() then pausedClosed = true end
    if #requests == 0 then idleClosed = true end
    win:Hide()
end)

function ns.SetPaused(on)
    if not MageServicesCharDB then return end
    MageServicesCharDB.paused = on and true or nil
    pausedClosed = false
    if on then
        wipe(requests) -- drops their glows, alerts and the portal button too
        Print("paused. Not watching chat until you resume (the Resume button, /ms resume or a key binding).")
    else
        Print("resumed, watching chat for requests again.")
    end
    Refresh()
    if ns.RefreshOptions then ns.RefreshOptions() end
end

function MageServices_TogglePause()
    ns.SetPaused(not ns.IsPaused())
end

win.pause:SetScript("OnClick", MageServices_TogglePause)

local function ApplyPosition()
    if ns.PositionCast then
        ns.PositionCast() -- the window hangs off the portal button
        return
    end
    win:ClearAllPoints()
    local p = db.point
    win:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

---------------------------------------------------------------------------
-- Incoming chat
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Alert sounds: the game's own sounds. Any the client doesn't have are left out.
---------------------------------------------------------------------------
local SOUND_LIST = {
    { "TELL_MESSAGE", "Whisper" },
    { "RAID_WARNING", "Raid warning" },
    { "READY_CHECK", "Ready check" },
    { "UI_RAID_BOSS_WHISPER_WARNING", "Boss emote warning" },
    { "IG_PLAYER_INVITE", "Group invite" },
    { "LFG_ROLE_CHECK", "Role check" },
    { "PVP_THROUGH_QUEUE", "Queue ready" },
    { "UI_BNET_TOAST", "Battle.net toast" },
    { "ALARM_CLOCK_WARNING_2", "Alarm clock (short)" },
    { "ALARM_CLOCK_WARNING_3", "Alarm clock" },
    { "MAP_PING", "Map ping" },
    { "LOOT_WINDOW_COIN_SOUND", "Coins" },
    { "IG_QUEST_LIST_COMPLETE", "Quest complete" },
    { "AUCTION_WINDOW_OPEN", "Auction house" },
    { "UI_EPICLOOT_TOAST", "Epic loot" },
    { "UI_LEGENDARY_LOOT_TOAST", "Legendary loot" },
    { "UI_GARRISON_TOAST_MISSION_COMPLETE", "Mission complete" },
    { "UI_WORLDQUEST_COMPLETE", "World quest complete" },
}

function ns.SoundOptions()
    local opts = { { value = "NONE", label = "None" } }
    for _, s in ipairs(SOUND_LIST) do
        if SOUNDKIT and SOUNDKIT[s[1]] then opts[#opts + 1] = { value = s[1], label = s[2] } end
    end
    return opts
end

function ns.PlayAlertSound(key)
    key = key or db.soundKey
    if key == "NONE" or not (PlaySound and SOUNDKIT) then return end
    local id = SOUNDKIT[key] or SOUNDKIT.TELL_MESSAGE or SOUNDKIT.RAID_WARNING
    if id then PlaySound(id, "Master") end
end

-- Hidden by your settings: can't help (another zone, already there, no spell),
-- or, with hideUnknown, no idea where they are and no /who lookup running.
function ns.IsHidden(r)
    if r.paid then return false end
    if db.scope == "here" then return r.priority ~= HIGH and not r.whoPending end
    if db.scope == "nearby" then return r.priority == LOW end
    return false
end

local function Alert(req)
    if db.sound then ns.PlayAlertSound() end
    if db.flash and FlashClientIcon then FlashClientIcon() end
    if ns.ScreenAlert then ns.ScreenAlert(req) end
end

local function AddRequest(sender, msg, info, source, whispered, heardIn)
    -- same person again: refresh their entry instead of adding a second one
    for i, r in ipairs(requests) do
        if r.key == ns.NameKey(sender) then
            table.remove(requests, i)
            break
        end
    end
    local req = { sender = sender, key = ns.NameKey(sender), display = ns.DisplayName(sender),
                  first = ns.FirstName(sender), msg = msg, info = info, time = GetTime(),
                  source = source, zoneAtReceive = ns.MyZone(), heardIn = heardIn }
    req.priority, req.reason = Rank(req)
    ns.customers[req.key] = { time = GetTime(), kind = info.kind, dest = info.dest, sender = sender }
    table.insert(requests, 1, req)
    -- nothing for requests your settings hide
    if not ns.IsHidden(req) and (req.priority > LOW or db.alertLow) then
        Alert(req)
        if db.autoInvite and not testMode and req.priority > LOW then Invite(sender) end
    end
    if whispered then AutoReply(req) end
    Refresh()
end

-- source: "say" (say/yell, so they're close), "local" (your zone's General or
-- LocalDefense channel), or "other" (trade, whispers, guild: could be anywhere)
function ns.HandleChat(msg, sender, source, whispered, heardIn)
    if not db then return end
    if ns.IsPaused() and not testMode then return end -- paused: not taking requests
    if IsSecret(msg) or IsSecret(sender) then return end -- inside instances: unreadable
    if type(msg) ~= "string" or type(sender) ~= "string" or sender == "" then return end

    local key = ns.NameKey(sender)
    if key == ns.NameKey(ns.UnitFull("player")) then return end -- yourself
    if ns.InGroupWith(key) then return end                       -- already grouped

    local info = ns.Classify(msg, MatchOptions())
    if info then AddRequest(sender, msg, info, source or "other", whispered, heardIn) end
end

local SOURCE = {
    CHAT_MSG_SAY = "say", CHAT_MSG_YELL = "say",
    CHAT_MSG_WHISPER = "other", CHAT_MSG_GUILD = "other",
}

-- General and LocalDefense are per-zone, so the sender is in the zone you're in.
local function ChannelSource(channelName, channelBase)
    local name = (type(channelBase) == "string" and not IsSecret(channelBase) and channelBase ~= "" and channelBase)
              or (type(channelName) == "string" and not IsSecret(channelName) and channelName) or ""
    name = name:lower():gsub("^%d+%.%s*", "")
    if name:find("^general") or name:find("^localdefense") or name:find("^local defense") then
        -- "2. General - Durotar": the zone is in the channel's name
        local zone
        if type(channelName) == "string" and not IsSecret(channelName) then
            zone = channelName:gsub("^%d+%.%s*", ""):match("%s%-%s(.+)$")
        end
        return "local", zone
    end
    return "other"
end

---------------------------------------------------------------------------
-- /who lookups (only from a click: the game requires a click or key press for /who)
---------------------------------------------------------------------------
local pendingWho -- { req = request, name = short name, time = sent at }

local function FinishWho(area)
    if not pendingWho then return end
    local req = pendingWho.req
    req.whoPending = nil
    if area and area ~= "" then
        req.whoZone = area
        req.whoFailed = nil
    else
        req.whoFailed = true
    end
    pendingWho = nil
    Refresh()
end

function ns.LookupZone(req)
    if not (C_FriendList and C_FriendList.SendWho) then
        Print("/who isn't available on this client.")
        return
    end
    if C_FriendList.SetWhoToUi then pcall(C_FriendList.SetWhoToUi, false) end
    pendingWho = { req = req, key = req.key, time = GetTime() }
    ns.lastWhoKey, ns.lastWhoTime = req.key, GetTime()
    req.whoPending, req.whoFailed = true, nil
    -- search by first name; results are matched on the full name below
    local ok = pcall(C_FriendList.SendWho, 'n-"' .. req.first .. '"')
    if not ok then
        pendingWho = nil
        req.whoPending, req.whoFailed = nil, true
    end
    Refresh()
    -- the server has a /who cooldown and may not answer
    local sent = pendingWho and pendingWho.time
    C_Timer.After(5, function()
        if pendingWho and pendingWho.time == sent then FinishWho(nil) end
    end)
end

-- Results come back as a WHO_LIST_UPDATE (4+ results) or as system chat lines (1-3).
local function OnWhoList()
    if not pendingWho then return end
    local n = C_FriendList.GetNumWhoResults and C_FriendList.GetNumWhoResults() or 0
    for i = 1, n do
        local ok, info = pcall(C_FriendList.GetWhoInfo, i)
        if ok and info and ns.NameKey(info.fullName) == pendingWho.key then
            FinishWho(info.area)
            return
        end
    end
    FinishWho(nil)
end

-- "[Name]: Level 40 Orc Warrior <Guild> - Orgrimmar"
local function ParseWhoLine(msg)
    if type(msg) ~= "string" or IsSecret(msg) then return end
    local name = msg:match("|Hplayer:([^:|]+)")
    if not name then return end
    local area = msg:match("^.*%s%-%s(.-)%s*$")
    return ns.NameKey(name), area
end

-- Hide our own lookup lines from chat so the lookup is quiet.
local function WhoChatFilter(_, _, msg)
    if not pendingWho and not ns.lastWhoTime then return false end
    if type(msg) ~= "string" or IsSecret(msg) then return false end
    local name = ParseWhoLine(msg)
    local recent = ns.lastWhoTime and GetTime() - ns.lastWhoTime < 6
    if (pendingWho and name == pendingWho.key) or (recent and name == ns.lastWhoKey) then return true end
    if recent and msg:find("%d+ [Pp]layers? total") then return true end
    return false
end

local function OnSystemMessage(msg)
    if not pendingWho then return end
    local name, area = ParseWhoLine(msg)
    if name and name == pendingWho.key then
        FinishWho(area)
    end
end

local CHANNEL_EVENTS = {
    CHAT_MSG_CHANNEL = "chTrade",
    CHAT_MSG_SAY = "chSay",
    CHAT_MSG_YELL = "chSay",
    CHAT_MSG_WHISPER = "chWhisper",
    CHAT_MSG_GUILD = "chGuild",
}

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")

local function SafeRegister(event)
    return pcall(ev.RegisterEvent, ev, event)
end

SafeRegister("ADDON_LOADED")
SafeRegister("PLAYER_LOGIN")

ev:SetScript("OnEvent", function(_, event, arg1, arg2, _, arg4, _, _, _, _, arg9)
    local setting = CHANNEL_EVENTS[event]
    if setting then
        local whispered = event == "CHAT_MSG_WHISPER"
        if db and (db[setting] or (whispered and db.autoReply)) then
            local source, heardIn = SOURCE[event], nil
            if not source then source, heardIn = ChannelSource(arg4, arg9) end
            if source == "say" or (source == "local" and not heardIn) then heardIn = ns.RealZone() end
            ns.HandleChat(arg1, arg2, source, whispered, heardIn)
        end

    elseif event == "WHO_LIST_UPDATE" then
        OnWhoList()

    elseif event == "CHAT_MSG_SYSTEM" then
        OnSystemMessage(arg1)

    elseif event == "GUILD_ROSTER_UPDATE" or event == "FRIENDLIST_UPDATE" then
        ns.RebuildRoster()
        Refresh()

    elseif event == "SPELLS_CHANGED" then
        -- learned a portal, levelled up, changed spec: check the spells again
        ns.SpellsChanged()
        Refresh()

    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
        -- after a loading screen the zone can be blank for a moment, so check again shortly
        Refresh()
        C_Timer.After(1, Refresh)

    elseif event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        MageServicesDB = MageServicesDB or {}
        -- 1.9.0: the two hide checkboxes became one "Show requests from" setting
        if MageServicesDB.scope == nil and (MageServicesDB.hideLow ~= nil or MageServicesDB.hideUnknown ~= nil) then
            -- neither ticked was just the old default, so that gets the new default
            MageServicesDB.scope = MageServicesDB.hideUnknown and "here" or "nearby"
        end
        MageServicesDB.hideLow, MageServicesDB.hideUnknown = nil, nil
        for k, v in pairs(defaults) do
            if MageServicesDB[k] == nil then
                MageServicesDB[k] = type(v) == "table" and { unpack(v) } or v
            end
        end
        db = MageServicesDB
        if ns.StartVersionCheck then ns.StartVersionCheck(db, "Mage Services") end
        ns.db = db
        ns.InitEarnings()
        ns.ApplyTheme()
        ApplyPosition()
        ns.BuildOptions()

    elseif event == "PLAYER_LOGIN" then
        for e in pairs(CHANNEL_EVENTS) do SafeRegister(e) end
        SafeRegister("ZONE_CHANGED_NEW_AREA")
        SafeRegister("SPELLS_CHANGED")
        SafeRegister("GUILD_ROSTER_UPDATE")
        SafeRegister("FRIENDLIST_UPDATE")
        -- keep the guild and friends lists fresh so their zones are current
        local function AskRoster()
            if ns.IsPaused() then return end
            if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster)
            elseif GuildRoster then pcall(GuildRoster) end
            if C_FriendList and C_FriendList.ShowFriends then pcall(C_FriendList.ShowFriends) end
        end
        C_Timer.After(5, AskRoster)
        C_Timer.NewTicker(60, AskRoster)
        C_Timer.After(8, function()
            if ns.IsPaused() then Print("paused on this character. Click Resume on the window, or type /ms resume.") end
        end)
        SafeRegister("PLAYER_ENTERING_WORLD")
        SafeRegister("WHO_LIST_UPDATE")
        SafeRegister("CHAT_MSG_SYSTEM")
        if ChatFrame_AddMessageEventFilter then
            ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", WhoChatFilter)
        elseif ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter then
            ChatFrameUtil.AddMessageEventFilter("CHAT_MSG_SYSTEM", WhoChatFilter)
        end
        C_Timer.NewTicker(1, Refresh) -- ages the "s ago" and drops old requests
    end
end)

---------------------------------------------------------------------------
-- Test: run sample chat lines through the same path
---------------------------------------------------------------------------
local SAMPLES = {
    { "Gruntor-Realm", "LF port to UC pls", "local" },              -- your zone's General: high
    { "Lilthrall-Realm", "WTB mage water x40", "say" },             -- said near you: high
    { "Tauzan-Realm", "anyone port tb?", "other" },                 -- trade: normal
    { "Farseer-Realm", "LF port from Thunder Bluff to Org", "other" }, -- elsewhere: low (unless you're in TB)
    { "Otherlock-Realm", "WTS portals to all cities 5s", "other" }, -- another mage's ad: ignored
    { "Shamy-Realm", "water walking anyone?", "other" },            -- not a drink: ignored
}

local function RunTest()
    if ns.IsPaused() then
        Print("paused. Resume first (/ms resume) to try the test.")
        return
    end
    testMode = true
    local before = #requests
    for _, s in ipairs(SAMPLES) do ns.HandleChat(s[2], s[1], s[3]) end
    testMode = false
    Print(("test: %d sample lines, %d matched (2 are meant to be ignored). Your location: %s"):format(
        #SAMPLES, #requests - before, ns.MyZone() ~= "" and ns.MyZone() or "unknown"))
end

---------------------------------------------------------------------------
-- Settings page (Options > AddOns) and minimap addon button
---------------------------------------------------------------------------
function ns.ZoneChoices()
    local list = { "auto" }
    for _, f in ipairs(db.allFactions and { "Horde", "Alliance" } or { Faction() }) do
        for _, d in ipairs(ns.DESTINATIONS[f]) do list[#list + 1] = d.name end
    end
    -- keep a zone typed with /ms zone selectable too
    if db.zone and db.zone ~= "auto" then
        local found = false
        for _, v in ipairs(list) do if v == db.zone then found = true end end
        if not found then list[#list + 1] = db.zone end
    end
    return list
end

function ns.BuildOptions()
    ns.CreateOptions({
        title = "Mage Services",
        updateNotice = true,
        changes = {
            { "2.1.0", "Advertise button: posts your own advert in Trade (or General, say, yell), at most every few minutes",
                       "It lists the portals you have; edit it on this page. Also /ms ad or a key binding",
                       "Optional slim bar with the button when there are no requests" },
            { "2.0.0", "\"All\" button invites everyone going to the same city at once",
                       "Rune counts on the window, with a warning when Runes of Portals run low",
                       "Optional: remove customers from the group once they've gone through your portal" },
            { "1.9.0", "Pause / Resume button on the window",
                       "\"Show requests from\": your city only, your city + unknown, or everywhere",
                       "Better at telling where people are: channel zones, guildmates, friends" },
        },
        icon = "Interface\\Icons\\Spell_Arcane_PortalOrgrimmar",
        about = "Spots portal and water requests in chat",
        credit = "Created by Miff, supported by Claude",
        slash = "/ms",
        db = db,
        onChange = function() ns.ApplyTheme(); Refresh() end,
        controls = {
            { type = "header", label = "Service" },
            { type = "button", label = "Pause the service",
              dynamicLabel = function() return ns.IsPaused() and "Resume the service" or "Pause the service" end,
              func = function() ns.SetPaused(not ns.IsPaused()) end },
            { type = "info", height = 22, lines = function()
                return "|cff999999" .. (ns.IsPaused() and "Paused on this character: not watching chat." or "Pausing stops watching chat on this character until you resume.") .. "|r" end },
            { type = "header", label = "Look for" },
            { type = "check", key = "ports", label = "Portal requests" },
            { type = "check", key = "water", label = "Water and food requests" },
            { type = "check", key = "allFactions", label = "Other faction's cities too" },
            { type = "header", label = "Channels" },
            { type = "check", key = "chTrade", label = "Trade, General and other numbered channels" },
            { type = "check", key = "chSay", label = "Say and yell" },
            { type = "check", key = "chWhisper", label = "Whispers" },
            { type = "check", key = "chGuild", label = "Guild" },
            { type = "header", label = "Look" },
            { type = "choice", key = "theme", label = "Window theme", values = { "dark", "light" } },
            { type = "header", label = "Your location" },
            { type = "choice", key = "zone", label = "Where you are (Auto = current zone)", values = ns.ZoneChoices() },
            { type = "dropdown", key = "scope", label = "Show requests from", options = function() return {
                { value = "here", label = "Your city only" },
                { value = "nearby", label = "Your city + unknown" },
                { value = "all", label = "Everywhere (rest dimmed)" },
              } end },
            { type = "info", height = 44, lines = function()
                return "|cff999999Trade chat reaches every city, so a Trade request only counts as your city if it says so, they're a guildmate or friend, or you click ? on it. \"Your city only\" hides the rest; \"Your city + unknown\" keeps them so you can check.|r" end },
            { type = "check", key = "alertLow", label = "Alert for low-priority requests too" },
            { type = "header", label = "On screen" },
            { type = "check", key = "glowBar", label = "Glow the matching Portal / Conjure button" },
            { type = "range", key = "glowTime", label = "Glow for", min = 5, max = 60, step = 5, suffix = "s" },
            { type = "check", key = "screenMsg", label = "Show a message at the top of the screen" },
            { type = "check", key = "edgeFlash", label = "Flash the edges of the screen" },
            { type = "header", label = "Earnings (saved, kept through logouts)" },
            { type = "info", lines = function() return ns.EarningsLines() end, height = 190 },
            { type = "header", label = "Replies (the Whisper button, and automatic replies)" },
            { type = "text", key = "portMsg", label = "Portal reply", default = defaults.portMsg,
              preview = function(t) return ns.SampleReply(t, "port") end },
            { type = "text", key = "waterMsg", label = "Food and water reply", default = defaults.waterMsg,
              preview = function(t) return ns.SampleReply(t, "water") end },
            { type = "text", key = "customMsg", label = "Reply for your own phrases (/ms add)", default = defaults.customMsg,
              preview = function(t) return ns.SampleReply(t, "custom") end },
            { type = "info", height = 24, lines = function()
                return "|cff999999{name} is their first name, {dest} the city they want, {zone} where you are. Press Enter to save.|r" end },
            { type = "check", key = "autoReply", label = "Reply automatically when someone whispers you for a port or food" },
            { type = "check", key = "autoReplyCant", label = "Also reply when you can't help (a portal you don't have, or they're elsewhere)" },
            { type = "text", key = "cantMsg", label = "Can't-help reply", default = defaults.cantMsg,
              preview = function(t) return ns.SampleReply(t, "port") end },
            { type = "range", key = "autoReplyGap", label = "Don't auto-reply to them again for", min = 1, max = 30, step = 1, suffix = " min" },
            { type = "info", height = 22, lines = function() return ns.ReplyWarning() end },
            { type = "header", label = "Payments" },
            { type = "choice", key = "receiptMode", label = "Payment messages (Auto / Prefill / Off)", values = { "auto", "prefill", "off" } },
            { type = "check", key = "receiptAll", label = "Post for every trade, not just customers" },
            { type = "check", key = "hideAmount", label = "Keep the gold amount out of payment messages" },
            { type = "button", label = "Test a payment message", func = function() ns.TestTrade("complete") end },
            { type = "header", label = "When someone asks" },
            { type = "check", key = "sound", label = "Play a sound" },
            { type = "dropdown", key = "soundKey", label = "Sound", options = ns.SoundOptions,
              onSelect = function(v) ns.PlayAlertSound(v) end, preview = function(v) ns.PlayAlertSound(v) end },
            { type = "check", key = "flash", label = "Flash the WoW icon on the taskbar" },
            { type = "check", key = "autoInvite", label = "Invite them automatically" },
            { type = "header", label = "Advertise" },
            { type = "text", key = "adMsg", label = "Your advert", default = defaults.adMsg,
              preview = function(t) return ns.FillAd(t) end },
            { type = "info", height = 44, lines = function()
                return "|cff999999{services} is the portals you have and food and water, {portals} just the cities, {zone} where you are. Keep \"selling\" or \"WTS\" in it, so other mages' Mage Services don't list it as a request. Press Enter to save.|r" end },
            { type = "dropdown", key = "adChannel", label = "Post it in", options = function() return {
                { value = "trade", label = "Trade" }, { value = "general", label = "General" },
                { value = "say", label = "Say" }, { value = "yell", label = "Yell" },
              } end },
            { type = "range", key = "adGap", label = "At most once every", min = 1, max = 15, step = 1, suffix = " min" },
            { type = "check", key = "idleBar", label = "Keep a slim bar with the Advertise button when there are no requests" },
            { type = "button", label = "Advertise now", func = function() MageServices_Advertise() end },
            { type = "info", height = 30, lines = function()
                return "|cff999999The game only lets an addon post in a channel from a click or key press: the Advertise button, /ms ad, or a key binding (Key Bindings > AddOns).|r" end },
            { type = "header", label = "Runes and your group" },
            { type = "check", key = "runeCount", label = "Show your rune counts at the bottom of the window" },
            { type = "range", key = "runeLow", label = "Warn when Runes of Portals fall below", min = 0, max = 20, step = 1 },
            { type = "check", key = "kickAfterPort", label = "After a portal, remove customers from the group once they've gone through" },
            { type = "info", height = 32, lines = function()
                return "|cff999999Only people you invited from Mage Services or who asked you in chat, and only once they've vanished from beside you after your portal. You need to be the group leader.|r" end },
            { type = "range", key = "expire", label = "Keep requests for", min = 30, max = 600, step = 30, suffix = "s" },
            { type = "range", key = "maxRows", label = "Rows shown", min = 2, max = 12, step = 1 },
            { type = "header", label = "Preview" },
            { type = "button", label = "Add test requests", func = RunTest },
            { type = "button", label = "Reset window position", func = function()
                db.point = { unpack(defaults.point) }; ApplyPosition() end },
        },
    })
end

function MageServices_OnAddonCompartmentClick()
    if ns.OpenOptions then ns.OpenOptions() end
end

---------------------------------------------------------------------------
-- Slash command: /ms
---------------------------------------------------------------------------
local function ListPhrases(list, what)
    if #list == 0 then Print("no " .. what .. " yet.") return end
    for i, p in ipairs(list) do Print(i .. ". " .. p) end
end

SLASH_MAGESERVICES1 = "/ms"
SLASH_MAGESERVICES2 = "/mageservices"
SlashCmdList.MAGESERVICES = function(msg)
    msg = msg or ""
    local cmd, rest = msg:match("^(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    local n = tonumber(rest)

    if cmd == "" then
        ns.OpenOptions()
    elseif cmd == "zone" then
        if rest == "" then
            Print("you're in: " .. (ns.MyZone() ~= "" and ns.MyZone() or "unknown")
                .. (db.zone == "auto" and " (detected)" or " (picked; /ms zone auto to detect)"))
        elseif rest:lower() == "auto" then
            db.zone = "auto"; Print("location: detect automatically (now " .. ns.MyZone() .. ")")
        else
            -- accept city shorthand like "uc" or "tb", or any zone name
            local picked = rest
            for _, f in ipairs({ "Horde", "Alliance" }) do
                for _, d in ipairs(ns.DESTINATIONS[f]) do
                    for _, alias in ipairs(d.aliases) do
                        local a = type(alias) == "table" and alias.word or alias
                        if a == rest:lower() or d.name:lower() == rest:lower() then picked = d.name end
                    end
                end
            end
            db.zone = picked; Print("location set to " .. picked)
        end
        Refresh()
    elseif cmd == "paidmsg" and rest ~= "" then
        db.paidMsg = rest; Print("payment message: " .. rest)
    elseif cmd == "amount" then
        db.hideAmount = not db.hideAmount
        Print(db.hideAmount and "payment messages won't mention the amount" or "payment messages will include the amount")
    elseif cmd == "privatemsg" and rest ~= "" then
        db.paidMsgPrivate = rest; Print("payment message without amount: " .. rest)
    elseif cmd == "nopaymsg" and rest ~= "" then
        db.noPayMsg = rest; Print("no-payment message: " .. rest)
    elseif cmd == "cancelmsg" and rest ~= "" then
        db.cancelMsg = rest; Print("cancelled message: " .. rest)
    elseif cmd == "failmsg" and rest ~= "" then
        db.failMsg = rest; Print("failed message: " .. rest)
    elseif cmd == "receipts" then
        local m = rest:lower()
        if m == "auto" or m == "prefill" or m == "off" then db.receiptMode = m end
        Print("payment messages: " .. db.receiptMode .. " (auto, prefill or off)")
    elseif cmd == "theme" then
        local v = rest:lower()
        if THEMES[v] then db.theme = v else db.theme = (db.theme == "dark") and "light" or "dark" end
        ns.ApplyTheme(); Refresh()
        Print("theme: " .. db.theme)
    elseif cmd == "sounds" then
        for i, o in ipairs(ns.SoundOptions()) do
            Print(i .. ". " .. o.label .. (o.value == db.soundKey and "  |cff33ff33(current)|r" or ""))
        end
        Print("pick one with /ms sound <number>")
    elseif cmd == "sound" and n then
        local o = ns.SoundOptions()[n]
        if o then db.soundKey = o.value; ns.PlayAlertSound(); Print("sound: " .. o.label) end
    elseif cmd == "earnings" or cmd == "gold" then
        local r = rest:lower()
        if r == "reset yes" then
            ns.ResetEarnings("character"); Print("this character's earnings reset. The all-characters total is kept.")
        elseif r == "reset all yes" then
            ns.ResetEarnings("all"); Print("all earnings reset, on every character.")
        elseif r == "reset" or r == "reset all" then
            Print("/ms earnings reset yes - clears this character's earnings (the all-characters total is kept)")
            Print("/ms earnings reset all yes - clears everything, every character, for good")
        else
            for _, line in ipairs(ns.EarningsLines()) do Print(line) end
        end
        Refresh()
    elseif cmd == "testtrade" then
        ns.TestTrade(rest ~= "" and rest:lower() or "complete")
    elseif cmd == "show" then
        pausedClosed = false
        win:Show()
    elseif cmd == "ad" or cmd == "advertise" then
        ns.Advertise()
    elseif cmd == "pause" then
        ns.SetPaused(true)
    elseif cmd == "resume" then
        ns.SetPaused(false)
    elseif cmd == "filter" and (rest == "here" or rest == "nearby" or rest == "all") then
        db.scope = rest
        Print(({ here = "showing requests from your city only",
                 nearby = "showing requests from your city, plus ones that don't say where they are",
                 all = "showing every request, others dimmed" })[rest])
        Refresh()
    elseif cmd == "test" then
        RunTest()
    elseif cmd == "add" and rest ~= "" then
        table.insert(db.custom, rest:lower()); Print("now watching for: " .. rest:lower())
    elseif cmd == "remove" and n and db.custom[n] then
        Print("removed: " .. table.remove(db.custom, n))
    elseif cmd == "list" then
        ListPhrases(db.custom, "custom phrases")
    elseif cmd == "exclude" and rest ~= "" then
        table.insert(db.excludes, rest:lower()); Print("will ignore lines with: " .. rest:lower())
    elseif cmd == "unexclude" and n and db.excludes[n] then
        Print("no longer ignoring: " .. table.remove(db.excludes, n))
    elseif cmd == "excludes" then
        ListPhrases(db.excludes, "excluded phrases")
    elseif cmd == "portmsg" and rest ~= "" then
        db.portMsg = rest; Print("portal reply: " .. rest)
    elseif cmd == "watermsg" and rest ~= "" then
        db.waterMsg = rest; Print("water reply: " .. rest)
    elseif cmd == "cantmsg" and rest ~= "" then
        db.cantMsg = rest; Print("can't-help reply: " .. rest)
    elseif cmd == "autoreply" then
        db.autoReply = not db.autoReply
        Print(db.autoReply and "automatic replies to whispers are on" or "automatic replies are off")
        if db.autoReply and ns.ReplyWarning() ~= "" then Print("your replies mention an invite, but auto-invite is off (type /ms for settings)") end
    elseif cmd == "custommsg" and rest ~= "" then
        db.customMsg = rest; Print("custom reply: " .. rest)
    else
        Print("v" .. ns.version .. " commands (or just /ms for the settings page):")
        Print("/ms pause, /ms resume - stop or start taking requests on this character (now " .. (ns.IsPaused() and "paused" or "on") .. ")")
        Print("/ms ad - post your advert (edit it on the settings page)")
        Print("/ms filter here|nearby|all - show requests from your city only, your city + unknown, or everywhere (now " .. db.scope .. ")")
        Print("/ms add <phrase> - also watch for your own phrase, e.g. /ms add lf summon")
        Print("/ms list, /ms remove <number> - see or remove your phrases")
        Print("/ms exclude <phrase> - never match lines with this, e.g. /ms exclude ratchet")
        Print("/ms excludes, /ms unexclude <number>")
        Print("/ms portmsg <text>, /ms watermsg <text>, /ms custommsg <text>, /ms cantmsg <text> - reply text; {name}, {dest} and {zone} get filled in")
        Print("/ms autoreply - reply automatically when someone whispers you for a port or food (now " .. (db.autoReply and "on" or "off") .. ")")
        Print("/ms zone [auto|city|zone name] - show or set where you are, e.g. /ms zone uc")
        Print("/ms theme [dark|light] - window theme")
        Print("/ms sounds, /ms sound <number> - list the alert sounds and pick one")
        Print("/ms earnings - gold earned, all characters and this one; /ms earnings reset for options")
        Print("/ms receipts [auto|prefill|off] - payment messages: send them, type them for you, or off")
        Print("/ms amount - include or leave out the gold amount in payment messages (now " .. (db.hideAmount and "left out" or "included") .. ")")
        Print("/ms paidmsg, /ms privatemsg, /ms nopaymsg, /ms cancelmsg, /ms failmsg <text> - {name}, {amount}, {reason} get filled in")
        Print("/ms testtrade [complete|cancelled|failed] - try a payment message (only typed, never sent)")
        Print("/ms test - add sample requests, /ms show - show the window")
    end
    if ns.RefreshOptions then ns.RefreshOptions() end
end

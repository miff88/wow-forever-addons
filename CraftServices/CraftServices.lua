-- Craft Services (WoW Forever)
-- Watches chat for people looking for a crafter (enchanting, blacksmithing, leatherworking,
-- tailoring, alchemy, engineering, cooking, first aid, and rogues for lockboxes) and lists
-- them in a small window with Invite and Whisper buttons, just like Mage Services does
-- for portals.
--
-- It knows your recipes (read from each profession window the first time you open it),
-- so it can tell what they want ("LF enchanter crusader", a linked item, "+7 agi gloves"),
-- whether you can make it, and whether you have the materials. Replies fill in the
-- recipe, your price, the materials and their place in the queue. Each request follows
-- the customer through: replied, invited, in your group, trading, paid.
--
-- Whisper doesn't send anything by itself: it opens your chat box with a reply already
-- typed, and you press Enter. Automatic replies and invites are optional and off.
--
-- Forever hides chat text from addons inside dungeons, raids, M+ and PvP, so it works out
-- in the world, which is where people look for crafters anyway.

local ADDON_NAME, ns = ...

-- Key Bindings > AddOns > Craft Services
BINDING_HEADER_CRAFTSERVICES = "Craft Services"
_G["BINDING_NAME_CLICK CraftServicesCastButton:LeftButton"] = "Open the profession for the selected request"
BINDING_NAME_CRAFTSERVICES_TOGGLEPAUSE = "Pause or resume the service"
BINDING_NAME_CRAFTSERVICES_ADVERTISE = "Post your advert"

local defaults = {
    updateNotice = true,  -- "a newer version is out" chat notice (VersionCheck.lua)
    profs = {},           -- [profession key] = false to stop watching for it
    allProfs = false,     -- also list requests for professions you don't have
    -- channels to watch
    chTrade = true,       -- Trade, General, LookingForGroup and other numbered channels
    chSay   = true,       -- say and yell
    chWhisper = true,
    chGuild = true,
    -- alerts
    sound  = true,
    soundKey = "TELL_MESSAGE",
    flash  = true,        -- flash the WoW icon on the taskbar
    screenMsg = true,     -- short message at the top of the screen
    edgeFlash = false,    -- flash the edges of the screen
    autoInvite = false,   -- invite when you can make it (or it's a lockbox and you're a rogue)
    expire = 180,         -- seconds a new request stays in the list
    keepActive = 15,      -- minutes a customer you're dealing with (invited, grouped) stays listed
    -- location
    zone = "auto",
    scope = "nearby",     -- "here", "nearby" or "all"
    alertLow = false,
    -- payments
    receiptMode = "auto", -- "auto" posts by itself, "prefill" types it for you, "off"
    receiptAll  = false,
    paidMsg   = "Payment received from {name}: {amount}. Thanks, enjoy!",
    hideAmount = true,
    paidMsgPrivate = "Payment received, thanks {name}! Enjoy.",
    noPayMsg  = "Trade with {name} completed, but no payment was included.",
    matsMsg   = "Got your mats, {name} ({items}). Working on it now.",
    matsReceipt = true,
    kickAfterJob = false, -- remove customers from the group once they've paid
    kickDelay = 20,
    payAskMsg  = "{name}, it's {price} when you're ready.",
    matsAskMsg = "{name}, I still need {missing} for this one.",   -- post matsMsg when someone hands over mats without paying yet
    cancelMsg = "Trade with {name} was cancelled. No payment received.",
    failMsg   = "Trade with {name} failed ({reason}). No payment received.",
    maxRows = 6,
    custom = {},          -- your own phrases, e.g. "lf summon"
    excludes = {},        -- phrases that should never match
    -- replies: {name} {item} {who} {price} {mats} {matsline} {missing} {queue} {zone}
    craftMsg   = "Hi {name}, I can do {item} for you{price}.{matsline}{queue} Sending you an invite.",
    missingMsg = "Hi {name}, I can do {item}{price}, but I'm short on {missing}. Can you bring those?{queue}",
    genericMsg = "Hi {name}, I'm {who}. What would you like made? Link it if you can.",
    lockMsg    = "Hi {name}, I can open that box for you.{queue} Sending you an invite.",
    customMsg  = "Hi {name}, sending you an invite now.",
    cantMsg    = "Sorry {name}, I don't have that recipe.",
    -- automatic replies to whispers (off until you turn them on)
    autoReply = false,
    autoReplyCant = true,
    autoReplyGap = 5,
    -- prices and featured recipes, by recipe name (shared by all your characters)
    prices = {},
    featured = {},
    noPriceText = "",     -- what {price} says when there's no price set, e.g. " (tips welcome)"
    -- your own advert
    adMsg     = "LFW {professions} in {zone}{featured}. Whisper me!",
    adChannel = "trade",
    adGap     = 3,
    adOnlyMats = true,    -- only list featured recipes you have the materials for
    idleBar   = false,
    -- the panel beside the trade window
    tradePanel = true,
    point = { "CENTER", "CENTER", 300, 100 },
    theme = "dark",
    history = {},         -- [name key] = { count, total, last, item } past customers
}

ns.defaults = defaults
local db
local requests = {}   -- newest first
ns.requests = requests
local testMode = false
ns.IsTestMode = function() return testMode end

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffb347Craft Services:|r " .. msg)
end
ns.Print = Print

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

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

-- "5g", "2g 50s", "75s", "1.5g" -> copper
function ns.ParseMoney(text)
    if type(text) ~= "string" then return nil end
    text = text:lower():gsub("%s+", "")
    if text == "" then return nil end
    local total, any = 0, false
    for n, unit in text:gmatch("([%d%.]+)([gsc]?)") do
        local v = tonumber(n)
        if v then
            any = true
            if unit == "s" then total = total + v * 100
            elseif unit == "c" then total = total + v
            else total = total + v * 10000 end
        end
    end
    return any and math.floor(total + 0.5) or nil
end

local function JoinList(list)
    if #list <= 1 then return list[1] or "" end
    return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end
ns.JoinList = JoinList

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
    local mine = {}
    for key in pairs(ns.Book.MyProfs()) do mine[key] = true end
    return { mine = mine, all = db.allProfs, profs = db.profs, custom = db.custom, excludes = db.excludes }
end

---------------------------------------------------------------------------
-- Location and priority
---------------------------------------------------------------------------
local HIGH, NORMAL, LOW = 3, 2, 1
ns.HIGH, ns.NORMAL, ns.LOW = HIGH, NORMAL, LOW

-- Statuses a request moves through. Anything from "invited" on is a customer you're
-- dealing with: it stays at the top and isn't dropped after a few minutes.
local ACTIVE = { invited = true, grouped = true, mats = true, trading = true }
local STATUS_TEXT = { replied = "replied", invited = "invited", grouped = "in your group",
                      mats = "mats received", trading = "trading", paid = "paid", done = "done" }
ns.STATUS_TEXT = STATUS_TEXT
ns.ACTIVE = ACTIVE

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

-- Can you make it? Returns a reason when you can't (or can't yet), and whether that
-- should drop it to the bottom (a recipe you don't have) or just be noted (missing mats).
local function CraftCheck(info)
    if info.kind ~= "craft" then return nil end
    local prof = ns.PROF_BY_KEY[info.prof]
    if not ns.Book.Has(info.prof) then return "not your profession", true end
    if info.recipe then
        if info.mats == "theirs" then return "they bring the mats", false, true end
        local m = ns.Book.Mats(info.recipe)
        if m.have == false then
            local names = {}
            for _, x in ipairs(m.missing) do names[#names + 1] = (x.need - x.have) .. " " .. x.name end
            return "short on " .. JoinList(names), false
        end
        return nil
    end
    -- they linked something you can't make (and your recipe list is up to date)
    if info.linkedItem and ns.Book.Scanned(info.prof) then return "you don't have this recipe", true end
    if prof and prof.key ~= "lockpicking" and not ns.Book.Scanned(info.prof) then
        return "open your " .. prof.name .. " once so I know your recipes", false
    end
    return nil
end
ns.CraftCheck = CraftCheck

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

    if ACTIVE[req.status] or req.status == "paid" then return HIGH, nil end

    local cant, hard, good = CraftCheck(info)
    if cant and hard then return LOW, cant end

    local prio, where = NORMAL, nil
    if req.whoZone then
        if SameZone(req.whoZone, here) then prio, where = HIGH, "in your zone (/who)"
        else prio, where = LOW, "they're in " .. req.whoZone .. " (/who)" end
    elseif rosterZones[req.key] then
        local roster = rosterZones[req.key]
        if SameZone(roster.zone, here) then prio, where = HIGH, "in your zone (" .. roster.how .. ")"
        else prio, where = LOW, "they're in " .. roster.zone .. " (" .. roster.how .. ")" end
    elseif req.whoPending then
        where = "looking up..."
    elseif req.whoFailed then
        where = "no /who reply, click ? again"
    elseif info.origin then
        if SameZone(info.origin, here) then prio, where = HIGH, "in your zone"
        else prio, where = LOW, "they're in " .. info.origin end
    elseif req.source == "say" then
        if req.heardIn and req.heardIn ~= "" and not SameZone(req.heardIn, here) then
            prio, where = LOW, "they're in " .. req.heardIn
        else
            prio, where = HIGH, "near you"
        end
    elseif req.source == "local" then
        local zone = req.heardIn or req.zoneAtReceive
        if SameZone(zone, here) then prio, where = HIGH, "in your zone"
        else prio, where = LOW, "they're in " .. (zone or "another zone") end
    end

    -- a note about mats goes with the location, it doesn't change the order
    if cant then where = where and (where .. ", " .. cant) or cant end
    return prio, where, good
end

---------------------------------------------------------------------------
-- Customers you've served before (all characters)
---------------------------------------------------------------------------
function ns.History(key)
    return db and db.history[key]
end

function ns.AddHistory(key, copper, item, name)
    if not db or not key or key == "" then return end
    local h = db.history[key] or { count = 0, total = 0 }
    if name then h.name = ns.DisplayName(name) end
    h.count = h.count + 1
    h.total = h.total + (copper or 0)
    h.last = time and time() or 0
    h.item = item or h.item
    db.history[key] = h
end

---------------------------------------------------------------------------
-- Statuses
---------------------------------------------------------------------------
local Refresh -- forward

function ns.SetStatus(key, status, extra)
    local changed = false
    for _, r in ipairs(requests) do
        if r.key == key then
            -- never step backwards (a whisper after the invite doesn't undo it)
            local order = { replied = 1, invited = 2, grouped = 3, mats = 3.5, trading = 4, paid = 5, done = 5 }
            if not r.status or (order[status] or 0) >= (order[r.status] or 0) then
                r.status = status
                r.statusTime = GetTime()
                if extra then for k, v in pairs(extra) do r[k] = v end end
                changed = true
            end
        end
    end
    if changed and Refresh then Refresh() end
    return changed
end

-- Customers waiting ahead of this one: those you've invited, grouped or are trading with.
function ns.QueueAhead(req)
    local n = 0
    for _, r in ipairs(requests) do
        if r ~= req and ACTIVE[r.status] then n = n + 1 end
    end
    return n
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
ns.invited = {} -- [name key] = when you invited them

local function Invite(name)
    local key = ns.NameKey(name)
    ns.invited[key] = GetTime()
    if not testMode then
        if C_PartyInfo and C_PartyInfo.InviteUnit then
            C_PartyInfo.InviteUnit(name)
        elseif InviteUnit then
            InviteUnit(name)
        end
    end
    ns.SetStatus(key, "invited")
end
ns.Invite = Invite

---------------------------------------------------------------------------
-- Advertise: "LFW Enchanter and Tailor in Orgrimmar: Crusader, Fiery Weapon. Whisper me!"
-- Posting to a chat channel needs a click or key press, so it only goes out from the
-- Advertise button, /cs ad or the key binding, and at most once every few minutes.
---------------------------------------------------------------------------
local AD_CHANNELS = { trade = "Trade", general = "General", say = "Say", yell = "Yell" }
local lastAd = -1e9

-- "Enchanter and Tailor", and ": Crusader, Fiery Weapon and Runecloth Bag"
function ns.AdParts()
    local mine = ns.Book.MyProfs()
    local profs = {}
    for _, p in ipairs(ns.PROFS) do
        if mine[p.key] and db.profs[p.key] ~= false and p.key ~= "cooking" and p.key ~= "firstaid" then
            profs[#profs + 1] = p.short
        end
    end
    local names = {}
    for _, e in ipairs(ns.Book.FeaturedList(db.adOnlyMats)) do
        local n = e.enchant and e.effect or e.callName or e.name
        if e.enchant and e.slot and not n:lower():find(e.slot:lower(), 1, true) and not ns.UniqueEffect(e) then
            n = n .. " " .. e.slot:lower()
        end
        names[#names + 1] = n
    end
    return JoinList(profs), (#names > 0 and (": " .. JoinList(names)) or "")
end

-- Is this enchant's effect name unique among your enchants? ("Crusader" is; "Greater Agility" isn't)
function ns.UniqueEffect(e)
    local n = 0
    for _, x in ipairs(ns.Book.List("enchanting") or {}) do
        if x.effect == e.effect then n = n + 1 end
    end
    return n <= 1
end

function ns.FillAd(template)
    local profs, featured = ns.AdParts()
    local zone = ns.MyZone()
    if zone == "" then zone = "town" end
    local values = { professions = profs ~= "" and profs or "crafter", featured = featured, zone = zone }
    return ((template or ""):gsub("{(%a+)}", function(k) return values[k] end)):sub(1, 255)
end

local function FindChannel(prefix)
    if not GetChannelList then return nil end
    local list = { GetChannelList() }
    for i = 1, #list, 3 do
        local id, name = list[i], list[i + 1]
        if type(name) == "string" and not IsSecret(name) and name:lower():find("^" .. prefix) then return id end
    end
end

function ns.AdWait()
    return math.max(0, (db.adGap or 3) * 60 - (GetTime() - lastAd))
end

function ns.Advertise()
    if not db then return end
    if ns.IsPaused() then Print("paused: resume first (the Resume button or /cs resume).") return end
    local wait = ns.AdWait()
    if wait > 0 then
        Print(("you can advertise again in %d:%02d (every %d min, set on the settings page)."):format(
            math.floor(wait / 60), math.ceil(wait) % 60, db.adGap))
        return
    end
    local profs = ns.AdParts()
    if profs == "" and db.adMsg:find("{professions}") then
        Print("nothing to advertise: no crafting professions on this character (or they're all turned off).")
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

function CraftServices_Advertise()
    if ns.Advertise then ns.Advertise() end
end

---------------------------------------------------------------------------
-- Replies
-- {name} first name, {item} what they want, {who} "an enchanter", {price} " for 5g",
-- {mats} the material list, {matsline} " It takes 4 Large Brilliant Shard.", {missing}
-- what you're short of, {queue} " You're #2 in line.", {zone} where you are
---------------------------------------------------------------------------
local function ItemText(req)
    local info = req.info
    if info.recipe then
        local e = info.recipe
        if e.enchant then return e.name end
        return e.callName or e.name
    end
    return info.link or "that"
end

local function FillTemplate(template, req)
    local info = req.info
    local prof = ns.PROF_BY_KEY[info.prof or ""]
    local e = info.recipe
    local mats = e and ns.Book.Mats(e) or { text = "" }
    local price = e and ns.Book.Price(e)
    local missing = {}
    for _, x in ipairs(mats.missing or {}) do missing[#missing + 1] = (x.need - x.have) .. " " .. x.name end
    local ahead = ns.QueueAhead(req)
    local zone = ns.MyZone()
    if zone == "" then zone = "town" end
    local values = {
        name = req.first or "",
        item = ItemText(req),
        who = prof and prof.who or "a crafter",
        price = price and (" for " .. Money(price)) or (db.noPriceText or ""),
        mats = mats.text ~= "" and mats.text or "the usual mats",
        matsline = (mats.text ~= "" and info.mats ~= "theirs") and (" It takes " .. mats.text .. ".") or "",
        missing = #missing > 0 and JoinList(missing) or "nothing",
        queue = ahead > 0 and (" You're #" .. (ahead + 1) .. " in line.") or "",
        zone = zone,
    }
    local out = tostring(template or ""):gsub("{(%a+)}", function(k) return values[k] end)
    return out:sub(1, 255) -- the game's chat limit
end

local function ReplyTemplate(req)
    local info = req.info
    if info.kind == "custom" then return db.customMsg end
    if info.prof == "lockpicking" then return db.lockMsg end
    if info.recipe then
        local m = ns.Book.Mats(info.recipe)
        if m.have == false and info.mats ~= "theirs" then return db.missingMsg end
        return db.craftMsg
    end
    return db.genericMsg
end

local function OpenWhisper(req)
    ns.OpenWhisperTo(req.sender, FillTemplate(ReplyTemplate(req), req))
    ns.SetStatus(req.key, "replied")
end
ns.OpenWhisper = OpenWhisper

-- Example for the settings page: a made-up customer wanting your first featured recipe
-- (or any recipe you have).
function ns.SampleReply(template, kind)
    local e
    for _, x in ipairs(ns.Book.FeaturedList(false)) do e = x break end
    if not e then
        for _, list in pairs({ ns.Book.List("enchanting"), ns.Book.List("blacksmithing"), ns.Book.List("tailoring"),
                               ns.Book.List("leatherworking"), ns.Book.List("alchemy"), ns.Book.List("engineering") }) do
            if list and list[1] then e = list[1] break end
        end
    end
    local info = { kind = "craft", prof = e and e.prof or "enchanting", recipe = (kind ~= "generic" and kind ~= "lock") and e or nil }
    if kind == "lock" then info.prof = "lockpicking" end
    if kind == "custom" then info.kind = "custom" end
    return FillTemplate(template, { first = "Lil", info = info })
end

function ns.ReplyWarning()
    if not (db and db.autoReply) or db.autoInvite then return "" end
    for _, k in ipairs({ "craftMsg", "lockMsg", "customMsg" }) do
        if tostring(db[k] or ""):lower():find("invite") then
            return "|cffff8040Your replies mention an invite, but \"Invite them automatically\" is off.|r"
        end
    end
    return ""
end

-- Automatic reply to someone who whispered you a request. Only whispers (never Trade or
-- General posts), at most once per player per few minutes, never in test mode.
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
        ns.SetStatus(req.key, "replied")
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
        bg = { 0.07, 0.07, 0.09, 0.95 }, header = { 0.12, 0.12, 0.16, 1 }, border = { 0.96, 0.66, 0.24, 0.9 },
        title = { 0.98, 0.7, 0.28 }, label = { 1, 0.82, 0 }, text = { 0.88, 0.88, 0.88 }, footer = { 0.72, 0.72, 0.72 },
        high = { 1, 0.82, 0, 0.12 }, sel = { 0.96, 0.66, 0.24, 0.2 }, divider = { 1, 1, 1, 0.07 },
        btn = { 0.16, 0.16, 0.2, 1 }, btnHover = { 0.25, 0.25, 0.31, 1 }, btnBorder = { 0.32, 0.32, 0.38, 1 },
        btnText = { 0.92, 0.92, 0.92 },
        accent = { 0.55, 0.33, 0.08, 1 }, accentHover = { 0.68, 0.42, 0.12, 1 }, accentText = { 1, 1, 1 },
        good = "4cd964", muted = "a0a0a0", dim = "8a8a8a", warn = "ffb347", shadow = true,
    },
    light = {
        bg = { 0.96, 0.96, 0.94, 0.97 }, header = { 0.93, 0.89, 0.83, 1 }, border = { 0.6, 0.38, 0.1, 1 },
        title = { 0.5, 0.3, 0.05 }, label = { 0.12, 0.12, 0.12 }, text = { 0.3, 0.3, 0.3 }, footer = { 0.33, 0.33, 0.33 },
        high = { 1, 0.78, 0.1, 0.22 }, sel = { 0.85, 0.55, 0.15, 0.18 }, divider = { 0, 0, 0, 0.09 },
        btn = { 0.9, 0.9, 0.9, 1 }, btnHover = { 0.8, 0.85, 0.9, 1 }, btnBorder = { 0.68, 0.68, 0.7, 1 },
        btnText = { 0.12, 0.12, 0.12 },
        accent = { 0.62, 0.4, 0.12, 1 }, accentHover = { 0.72, 0.48, 0.16, 1 }, accentText = { 1, 1, 1 },
        good = "1d8a3a", muted = "666666", dim = "8c8c8c", warn = "b35900", shadow = false,
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

-- The same look on a secure action button (casts a spell or runs a macro on click).
local function SecureFlatButton(name, parent, w, h, label, primary)
    local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate" .. (BackdropTemplateMixin and ",BackdropTemplate" or ""))
    b:SetSize(w, h)
    b:RegisterForClicks("AnyUp", "AnyDown")
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

ns.Color, ns.StyleText, ns.PaintButton = Color, StyleText, PaintButton
ns.FlatButton, ns.SecureFlatButton = FlatButton, SecureFlatButton


---------------------------------------------------------------------------
-- Request window
--
--   +---------------------------------------------------------------------+
--   | Craft Services  Orgrimmar          [Advertise] [Pause] [Clear] [x]  |  header 24
--   +---------------------------------------------------------------------+
--   | [icon] Enchanting: Crusader (weapon)  near you  Bob, 4s  [?][Invite][Whisper][x] |
--   |        LF enchanter crusader, have mats                             |  rows 30
--   +---------------------------------------------------------------------+
--   | Earned 12g (enchanting 10g, tailoring 2g)  this session 1g 50s      |  footer 20
--   +---------------------------------------------------------------------+
---------------------------------------------------------------------------
local WIDTH, HEADER_H, ROW_H, FOOTER_H, PAD = 480, 24, 30, 20, 6

local win = CreateFrame("Frame", "CraftServicesFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
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
win.ad:SetScript("OnClick", function() CraftServices_Advertise() end)
win.ad:HookScript("OnEnter", function(self)
    if not db then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Post your advert in " .. (AD_CHANNELS[db.adChannel] or db.adChannel))
    GameTooltip:AddLine(ns.FillAd(db.adMsg), 1, 1, 1, true)
    local wait = ns.AdWait()
    if wait > 0 then GameTooltip:AddLine(("Again in %d:%02d"):format(math.floor(wait / 60), math.ceil(wait) % 60), 0.7, 0.7, 0.7) end
    GameTooltip:AddLine("Edit it on the settings page, and feature recipes with /cs feature <name>. Also /cs ad or a key binding.", 0.7, 0.7, 0.7, true)
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

local function Remove(req)
    for i, r in ipairs(requests) do
        if r == req then table.remove(requests, i) break end
    end
    Refresh()
end
ns.RemoveRequest = Remove

local function Tooltip(btn, title, body)
    btn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(title)
        if body then GameTooltip:AddLine(body, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Everything known about a request, for the row's tooltip.
local function RequestTooltip(self)
    local req = self.req
    if not req then return end
    local t = ns.Theme()
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(req.display, t.title[1], t.title[2], t.title[3])
    GameTooltip:AddLine(req.msg, 1, 1, 1, true)
    local info = req.info
    local e = info.recipe
    if e then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(e.name .. (info.sure == "likely" and "  (best guess)" or ""), 1, 0.82, 0)
        local m = ns.Book.Mats(e)
        if m.text ~= "" then
            GameTooltip:AddLine("Mats: " .. m.text, 0.9, 0.9, 0.9, true)
            if info.mats == "theirs" then
                GameTooltip:AddLine("They say they have the mats.", 0.3, 0.85, 0.4, true)
            elseif m.have then
                GameTooltip:AddLine("You have everything.", 0.3, 0.85, 0.4)
            else
                for _, x in ipairs(m.missing) do
                    GameTooltip:AddLine(("  %s: you have %d of %d"):format(x.name, x.have, x.need), 1, 0.45, 0.3)
                end
            end
        end
        local price = ns.Book.Price(e)
        GameTooltip:AddLine(price and ("Your price: " .. Money(price)) or "No price set (/cs price " .. (e.callName or e.name) .. " 5g)", 0.7, 0.7, 0.7, true)
    elseif info.mats == "theirs" then
        GameTooltip:AddLine("They say they have the mats.", 0.3, 0.85, 0.4, true)
    end
    local h = ns.History(req.key)
    if h then
        GameTooltip:AddLine(("Bought from you %d time%s before, %s in total%s."):format(h.count, h.count == 1 and "" or "s",
            Money(h.total), h.item and (", last: " .. h.item) or ""), 0.6, 0.8, 1, true)
    end
    GameTooltip:AddLine("Click to put this request on the profession button (top left).", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
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
    row.where = FlatButton(row, 20, 20, "?")
    row.where:SetPoint("RIGHT", row.invite, "LEFT", -3, 0)
    Tooltip(row.where, "Where are they?", "Runs a /who on this player and re-ranks the request by their zone.")
    Tooltip(row.dismiss, "Dismiss", "Done with this one (also clears it from your queue).")
    Tooltip(row.whisper, "Whisper", "Opens a whisper with your reply typed in, with the recipe, your price, the mats and their place in line filled in. Press Enter to send.")

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
    row:SetScript("OnEnter", RequestTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnMouseUp", function(self) if self.req and ns.Select then ns.Select(self.req) end end)

    row.invite:SetScript("OnClick", function() if row.req then Invite(row.req.sender) end end)
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
    if ns.ApplyTradeTheme then ns.ApplyTradeTheme(t) end
end

-- Paused is saved per character (CraftServicesCharDB).
function ns.IsPaused()
    return CraftServicesCharDB and CraftServicesCharDB.paused and true or false
end

local pausedClosed = false -- closed the paused bar with x: stay hidden until resume or /cs show
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

-- How long a request stays: new ones a few minutes, customers you're dealing with longer,
-- paid ones a minute after paying.
local function Expired(r, now)
    if r.status == "paid" or r.status == "done" then return now - (r.statusTime or r.time) > 60 end
    if ACTIVE[r.status] then return now - (r.statusTime or r.time) > (db.keepActive or 15) * 60 end
    return now - r.time > db.expire
end

local function StatusOrder(r)
    if r.status == "trading" then return 6 end
    if r.status == "mats" then return 5 end
    if r.status == "grouped" then return 4 end
    if r.status == "invited" then return 3 end
    if r.status == "paid" then return 2 end
    return 0
end

Refresh = function()
    if not db then return end
    local t = ns.Theme()
    UpdatePauseButton()

    if ns.IsPaused() then
        for _, row in ipairs(rows) do row.req = nil; row:Hide() end
        win.title:SetText("Craft Services  |cff" .. t.muted .. "paused, not watching chat|r")
        win.footer:SetText(ns.EarningsLine and ns.EarningsLine() or "")
        if ns.UpdateCastButton then ns.UpdateCastButton({}) end
        win:SetHeight(2 + HEADER_H + FOOTER_H + 1)
        if pausedClosed then win:Hide() else win:Show() end
        return
    end
    local now = GetTime()
    for i = #requests, 1, -1 do
        if Expired(requests[i], now) then table.remove(requests, i) end
    end

    for _, r in ipairs(requests) do r.priority, r.reason, r.good = Rank(r) end
    table.sort(requests, function(a, b)
        local sa, sb = StatusOrder(a), StatusOrder(b)
        if sa ~= sb then return sa > sb end
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
                local ageText = ago < 60 and (ago .. "s") or (math.floor(ago / 60) .. "m")
                local tag = ""
                if req.status == "paid" then
                    tag = "  |cff" .. t.good .. "paid " .. Money(req.paid or 0) .. "|r"
                elseif STATUS_TEXT[req.status] and req.status ~= "replied" then
                    tag = "  |cff" .. t.good .. STATUS_TEXT[req.status] .. "|r"
                elseif req.priority == HIGH then
                    tag = "  |cff" .. (req.good == false and t.warn or t.good) .. (req.reason or "near you") .. "|r"
                elseif req.reason then
                    tag = "  |cff" .. (req.priority == LOW and t.dim or t.warn) .. req.reason .. "|r"
                end
                if req.status == "replied" or req.replied then tag = tag .. "  |cff" .. t.muted .. "replied|r" end
                local h = ns.History(req.key)
                if h then tag = tag .. "  |cff" .. t.muted .. "regular x" .. h.count .. "|r" end
                row.label:SetText(req.info.label .. tag .. "  |cff" .. t.muted .. req.display .. ", " .. ageText .. "|r")
                row.text:SetText(req.msg)
                row.bg:SetShown(req.priority == HIGH)
                row.sel:SetShown(req.selected and true or false)
                row.line:SetShown(i < shown)
                row:SetAlpha(req.priority == LOW and 0.5 or 1)
                row.invite:SetShown(not (req.status == "grouped" or req.status == "mats" or req.status == "trading"
                    or req.status == "paid" or req.status == "done"))
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
        note = (real ~= "" and real ~= where) and (" (picked, you're in " .. real .. ")") or " (picked)"
    end
    local queue = 0
    for _, r in ipairs(requests) do if ACTIVE[r.status] then queue = queue + 1 end end
    win.title:SetText("Craft Services"
        .. (where ~= "" and ("  |cff" .. t.muted .. where .. note .. "|r") or "")
        .. (queue > 0 and ("  |cff" .. t.good .. queue .. " in queue|r") or "")
        .. (extra > 0 and ("  |cff" .. t.muted .. "+" .. extra .. " more|r") or "")
        .. (hiddenCount > 0 and ("  |cff" .. t.muted .. hiddenCount .. " hidden|r") or ""))
    if ns.UpdateCastButton then ns.UpdateCastButton(visible) end
    win.footer:SetText(ns.EarningsLine and ns.EarningsLine() or "")
    win:SetHeight(2 + HEADER_H + shown * ROW_H + FOOTER_H + 1)
    if shown > 0 then
        idleClosed = false
        win:Show()
    elseif db.idleBar and not idleClosed then
        win:Show()
    else
        win:Hide()
    end
end

ns.Refresh = Refresh
win.clear:SetScript("OnClick", function()
    -- keep customers you're dealing with; clear the rest
    for i = #requests, 1, -1 do
        if not ACTIVE[requests[i].status] then table.remove(requests, i) end
    end
    Refresh()
end)
win.close:SetScript("OnClick", function()
    if ns.IsPaused() then pausedClosed = true end
    if #requests == 0 then idleClosed = true end
    win:Hide()
end)

function ns.SetPaused(on)
    if not CraftServicesCharDB then return end
    CraftServicesCharDB.paused = on and true or nil
    pausedClosed = false
    if on then
        wipe(requests)
        Print("paused. Not watching chat until you resume (the Resume button, /cs resume or a key binding).")
    else
        Print("resumed, watching chat for requests again.")
    end
    Refresh()
    if ns.RefreshOptions then ns.RefreshOptions() end
end

function CraftServices_TogglePause()
    ns.SetPaused(not ns.IsPaused())
end

win.pause:SetScript("OnClick", CraftServices_TogglePause)

local function ApplyPosition()
    if ns.PositionCast then
        ns.PositionCast() -- the window hangs off the profession button
        return
    end
    win:ClearAllPoints()
    local p = db.point
    win:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

function ns.ShowWindow()
    pausedClosed, idleClosed = false, false
    win:Show()
    Refresh()
end

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


-- Hidden by your settings: can't help (another zone, not your recipe), or with "here",
-- no idea where they are. Customers you're already dealing with are never hidden.
function ns.IsHidden(r)
    if r.status and r.status ~= "replied" then return false end
    if db.scope == "here" then return r.priority ~= HIGH and not r.whoPending end
    if db.scope == "nearby" then return r.priority == LOW end
    return false
end

local function Alert(req)
    if db.sound then ns.PlayAlertSound() end
    if db.flash and FlashClientIcon then FlashClientIcon() end
    if ns.ScreenAlert then ns.ScreenAlert(req) end
end

-- Should an automatic invite go out? Only when you can actually do it.
local function CanDoIt(req)
    if req.priority <= LOW then return false end
    local info = req.info
    if info.kind == "custom" then return true end
    if info.prof == "lockpicking" then return ns.Book.Has("lockpicking") end
    if not info.recipe then return false end -- "LF enchanter": ask what they want first
    local cant, hard = CraftCheck(info)
    return not hard and (not cant or info.mats == "theirs" or cant:find("^they bring"))
end
ns.CanDoIt = CanDoIt

local function AddRequest(sender, msg, info, source, whispered, heardIn)
    -- same person again: refresh their entry, keeping where you'd got to with them
    local key = ns.NameKey(sender)
    local old
    for i, r in ipairs(requests) do
        if r.key == key then
            old = table.remove(requests, i)
            break
        end
    end
    -- a vaguer follow-up ("hello?") keeps the recipe they asked for before
    if old and old.info.recipe and not info.recipe and info.prof == old.info.prof then
        info.recipe, info.label, info.icon, info.sure = old.info.recipe, old.info.label, old.info.icon, old.info.sure
    end
    local req = { sender = sender, key = key, display = ns.DisplayName(sender),
                  first = ns.FirstName(sender), msg = msg, info = info, time = GetTime(),
                  source = source, zoneAtReceive = ns.MyZone(), heardIn = heardIn }
    if old then
        req.status, req.statusTime, req.replied, req.whoZone = old.status, old.statusTime, old.replied, old.whoZone
        req.selected = old.selected
    end
    req.priority, req.reason, req.good = Rank(req)
    ns.customers[req.key] = { time = GetTime(), kind = info.prof or info.kind, recipe = info.recipe, sender = sender }
    table.insert(requests, 1, req)
    -- nothing for requests your settings hide, or for repeats from someone you're already helping
    if not old and not ns.IsHidden(req) and (req.priority > LOW or db.alertLow) then
        Alert(req)
        if db.autoInvite and not testMode and CanDoIt(req) then Invite(sender) end
    end
    if whispered then AutoReply(req) end
    Refresh()
end

-- source: "say" (say/yell, so they're close), "local" (your zone's General or
-- LocalDefense channel), or "other" (trade, whispers, guild: could be anywhere)
function ns.HandleChat(msg, sender, source, whispered, heardIn)
    if not db then return end
    if ns.IsPaused() and not testMode then return end
    if IsSecret(msg) or IsSecret(sender) then return end -- inside instances: unreadable
    if type(msg) ~= "string" or type(sender) ~= "string" or sender == "" then return end

    local key = ns.NameKey(sender)
    if key == ns.NameKey(ns.UnitFull("player")) then return end -- yourself

    local info = ns.Classify(msg, MatchOptions())
    if not info then return end
    -- already in your group: only a new request from them counts (a whisper saying what they want)
    if ns.InGroupWith(key) and not whispered then return end
    AddRequest(sender, msg, info, source or "other", whispered, heardIn)
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

-- Customers who've joined your group (or left it) since the last check.
local function CheckGroup()
    local changed = false
    for _, r in ipairs(requests) do
        local inGroup = ns.InGroupWith(r.key)
        if inGroup and (r.status == nil or r.status == "replied" or r.status == "invited") then
            r.status, r.statusTime, changed = "grouped", GetTime(), true
        elseif not inGroup and (r.status == "grouped" or r.status == "mats") then
            -- they left without trading: back to invited, so they stay listed a while
            r.status, r.statusTime, changed = "invited", GetTime(), true
        end
    end
    if changed then Refresh() end
end
ns.CheckGroup = CheckGroup

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

    elseif event == "GROUP_ROSTER_UPDATE" then
        CheckGroup()

    elseif event == "BAG_UPDATE_DELAYED" then
        -- mats came or went: the "short on" notes may have changed
        Refresh()

    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
        Refresh()
        C_Timer.After(1, Refresh)

    elseif event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        CraftServicesDB = CraftServicesDB or {}
        for k, v in pairs(defaults) do
            if CraftServicesDB[k] == nil then
                if type(v) == "table" then
                    local copy = {}
                    for kk, vv in pairs(v) do copy[kk] = vv end
                    CraftServicesDB[k] = copy
                else
                    CraftServicesDB[k] = v
                end
            end
        end
        db = CraftServicesDB
        ns.db = db
        if ns.StartVersionCheck then ns.StartVersionCheck(db, "Craft Services") end
        ns.InitEarnings()
        ns.ApplyTheme()
        ApplyPosition()
        ns.BuildOptions()

    elseif event == "PLAYER_LOGIN" then
        for e in pairs(CHANNEL_EVENTS) do SafeRegister(e) end
        SafeRegister("ZONE_CHANGED_NEW_AREA")
        SafeRegister("GUILD_ROSTER_UPDATE")
        SafeRegister("FRIENDLIST_UPDATE")
        SafeRegister("GROUP_ROSTER_UPDATE")
        SafeRegister("BAG_UPDATE_DELAYED")
        local function AskRoster()
            if ns.IsPaused() then return end
            if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster)
            elseif GuildRoster then pcall(GuildRoster) end
            if C_FriendList and C_FriendList.ShowFriends then pcall(C_FriendList.ShowFriends) end
        end
        C_Timer.After(5, AskRoster)
        C_Timer.NewTicker(60, AskRoster)
        C_Timer.After(3, function() ns.Book.MyProfs(true); ns.AddProfessionChecks() end)
        C_Timer.After(8, function()
            if ns.IsPaused() then Print("paused on this character. Click Resume on the window, or type /cs resume.") return end
            -- professions you have but haven't opened yet
            local unread = {}
            for _, p in ipairs(ns.PROFS) do
                if ns.Book.Has(p.key) and p.key ~= "lockpicking" and not ns.Book.Scanned(p.key) and db.profs[p.key] ~= false then
                    unread[#unread + 1] = p.name
                end
            end
            if #unread > 0 then
                Print("open your " .. JoinList(unread) .. " window once so I can read your recipes (I can still spot requests without it).")
            end
        end)
        SafeRegister("PLAYER_ENTERING_WORLD")
        SafeRegister("WHO_LIST_UPDATE")
        SafeRegister("CHAT_MSG_SYSTEM")
        if ChatFrame_AddMessageEventFilter then
            ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", WhoChatFilter)
        elseif ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter then
            ChatFrameUtil.AddMessageEventFilter("CHAT_MSG_SYSTEM", WhoChatFilter)
        end
        C_Timer.NewTicker(1, Refresh) -- ages the times and drops old requests
    end
end)

---------------------------------------------------------------------------
-- Test: run sample chat lines through the same path
---------------------------------------------------------------------------
local function TestSamples()
    local list = {}
    local mine = ns.Book.MyProfs()
    -- one for each profession you have, using a recipe you know when there is one
    for _, p in ipairs(ns.PROFS) do
        if mine[p.key] and p.key ~= "cooking" and p.key ~= "firstaid" then
            local recipes = {}
            for _, x in ipairs(ns.Book.List(p.key) or {}) do recipes[#recipes + 1] = x end
            table.sort(recipes, function(a, b) return a.name < b.name end)
            local e = recipes[math.min(#recipes, 3)]
            if p.key == "lockpicking" then
                list[#list + 1] = { "Boxholder-Test", "anyone lockpick a box for me? in org", "other" }
            elseif e and e.enchant and e.effect then
                local slot = e.slot and (" on my " .. e.slot:lower()) or ""
                list[#list + 1] = { "Gruntor-Test", "LF " .. p.short:lower() .. " " .. e.effect:lower() .. slot .. " pls, have mats", "local" }
            elseif e then
                list[#list + 1] = { "Lilthrall-Test", "WTB " .. (e.callName or e.name) .. " crafted", "say" }
            else
                list[#list + 1] = { "Tauzan-Test", "LF " .. p.short:lower() .. " ?", "other" }
            end
        end
    end
    if #list == 0 then
        list[#list + 1] = { "Tauzan-Test", "LF enchanter crusader", "other" }
    end
    list[#list + 1] = { "Otherchanter-Test", "LFW Enchanter, all enchants, your mats", "other" } -- an advert: ignored
    return list
end

local function RunTest()
    if ns.IsPaused() then
        Print("paused. Resume first (/cs resume) to try the test.")
        return
    end
    testMode = true
    local samples = TestSamples()
    local wasAll = db.allProfs
    if not next(ns.Book.MyProfs()) then db.allProfs = true end -- no professions: show them anyway
    local matched = 0
    for _, s in ipairs(samples) do
        ns.HandleChat(s[2], s[1], s[3])
        local key = ns.NameKey(s[1])
        for _, r in ipairs(requests) do
            if r.key == key and r.msg == s[2] then matched = matched + 1 break end
        end
    end
    db.allProfs = wasAll
    testMode = false
    Print(("test: %d sample lines, %d matched (the last is another crafter's advert, meant to be ignored)."):format(
        #samples, matched))
end

---------------------------------------------------------------------------
-- Prices and featured recipes, from the settings page or /cs
---------------------------------------------------------------------------
-- "crusader 5g", "arcanite reaper 12g 50s", "crusader clear"
function ns.SetPriceFromText(text)
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return end
    local name, amount = text:match("^(.-)%s+([%d%.]+[gsc]?[%d%.gsc%s]*)$")
    local clear = text:match("^(.-)%s+clear$") or text:match("^(.-)%s+none$")
    local e = ns.Book.Lookup(clear or name or text)
    if not e then Print("no recipe of yours matches \"" .. (clear or name or text) .. "\" (open its profession window first).") return end
    local key = ns.Book.PriceKey(e)
    if clear then
        db.prices[key] = nil
        Print("price cleared for " .. e.name .. ".")
        return
    end
    local copper = ns.ParseMoney(amount)
    if not copper then
        local p = db.prices[key]
        Print(e.name .. ": " .. (p and Money(p) or "no price set") .. ". Set one with /cs price " .. (e.callName or e.name) .. " 5g")
        return
    end
    db.prices[key] = copper
    Print(("price for %s: %s."):format(e.name, Money(copper)))
end

function ns.ToggleFeature(text)
    local e = ns.Book.Lookup(text)
    if not e then Print("no recipe of yours matches \"" .. tostring(text) .. "\" (open its profession window first).") return end
    local key = ns.Book.PriceKey(e)
    db.featured[key] = not db.featured[key] or nil
    Print(e.name .. (db.featured[key] and " is featured in your advert." or " is no longer featured."))
end

local function PriceLines()
    local list = {}
    for key, copper in pairs(db.prices) do
        local e = ns.Book.ByName(key)
        list[#list + 1] = ((e and (e.callName or e.name)) or key) .. "  " .. Money(copper)
    end
    table.sort(list)
    return list
end

local function FeaturedLines()
    local list = {}
    for key in pairs(db.featured) do
        local e = ns.Book.ByName(key)
        list[#list + 1] = (e and (e.callName or e.name)) or key
    end
    table.sort(list)
    return list
end

---------------------------------------------------------------------------
-- Settings page (Options > AddOns) and minimap addon button
---------------------------------------------------------------------------
function ns.ZoneChoices()
    local list = { "auto" }
    for _, d in ipairs(ns.DESTINATIONS[Faction()]) do list[#list + 1] = d.name end
    if db.zone and db.zone ~= "auto" then
        local found = false
        for _, v in ipairs(list) do if v == db.zone then found = true end end
        if not found then list[#list + 1] = db.zone end
    end
    return list
end

local function RecipeLines()
    local lines = {}
    local mine = ns.Book.MyProfs()
    for _, p in ipairs(ns.PROFS) do
        if mine[p.key] then
            local skill = mine[p.key].rank and (" (" .. mine[p.key].rank .. ")") or ""
            if p.key == "lockpicking" then
                lines[#lines + 1] = p.name .. skill .. ": lockbox requests, and the Pick Lock button"
            elseif ns.Book.Scanned(p.key) then
                lines[#lines + 1] = ("%s%s: %d recipes known"):format(p.name, skill, ns.Book.Count(p.key))
            else
                lines[#lines + 1] = ("%s%s: |cffffb347not read yet, open your %s window once|r"):format(p.name, skill, p.name)
            end
        end
    end
    if #lines == 0 then lines[1] = "No crafting professions on this character." end
    return lines
end

function ns.BuildOptions()
    local controls = {
        { type = "header", label = "Service" },
        { type = "button", label = "Pause the service",
          dynamicLabel = function() return ns.IsPaused() and "Resume the service" or "Pause the service" end,
          func = function() ns.SetPaused(not ns.IsPaused()) end },
        { type = "info", height = 22, lines = function()
            return "|cff999999" .. (ns.IsPaused() and "Paused on this character: not watching chat." or "Pausing stops watching chat on this character until you resume.") .. "|r" end },
        { type = "header", label = "Your professions" },
        { type = "info", height = 96, lines = RecipeLines },
    }
    local function add(c) controls[#controls + 1] = c end
    -- a checkbox per profession you have goes in here once your professions are known
    ns.profChecksAt, ns.optionControls = #controls + 1, controls
    add({ type = "check", key = "allProfs", label = "Also list requests for professions you don't have (dimmed)" })

    add({ type = "header", label = "Prices" })
    add({ type = "text", key = "priceEntry", label = "Set a price: the recipe, then the amount (e.g. crusader 5g)", default = "" })
    add({ type = "info", height = 70, lines = function()
        local l = PriceLines()
        return "|cff999999" .. (#l > 0 and table.concat(l, ",  ") or "No prices set. Replies fill {price} in from these: \"I can do Crusader for you for 5g\".") .. "|r" end })
    add({ type = "text", key = "noPriceText", label = "{price} when there's no price set (e.g. \" (tips welcome)\")", default = "" })

    add({ type = "header", label = "Advertise" })
    add({ type = "text", key = "adMsg", label = "Your advert", default = defaults.adMsg,
          preview = function(t) return ns.FillAd(t) end })
    add({ type = "info", height = 44, lines = function()
        return "|cff999999{professions} is what you do (\"Enchanter and Tailor\"), {featured} your featured recipes, {zone} where you are. Keep \"LFW\" or \"WTS\" in it, so other crafters' Craft Services don't list it as a request.|r" end })
    add({ type = "text", key = "featureEntry", label = "Feature a recipe in your advert (type its name; again to remove)", default = "" })
    add({ type = "info", height = 40, lines = function()
        local l = FeaturedLines()
        return "|cff999999" .. (#l > 0 and ("Featured: " .. table.concat(l, ", ")) or "Nothing featured yet.") .. "|r" end })
    add({ type = "check", key = "adOnlyMats", label = "Only list featured recipes you have the mats for" })
    add({ type = "dropdown", key = "adChannel", label = "Post it in", options = function() return {
        { value = "trade", label = "Trade" }, { value = "general", label = "General" },
        { value = "say", label = "Say" }, { value = "yell", label = "Yell" },
      } end })
    add({ type = "range", key = "adGap", label = "At most once every", min = 1, max = 15, step = 1, suffix = " min" })
    add({ type = "check", key = "idleBar", label = "Keep a slim bar with the Advertise button when there are no requests" })
    add({ type = "button", label = "Advertise now", func = function() CraftServices_Advertise() end })
    add({ type = "info", height = 30, lines = function()
        return "|cff999999The game only lets an addon post in a channel from a click or key press: the Advertise button, /cs ad, or a key binding (Key Bindings > AddOns).|r" end })

    add({ type = "header", label = "Replies (the Whisper button, and automatic replies)" })
    add({ type = "text", key = "craftMsg", label = "When you can do it", default = defaults.craftMsg,
          preview = function(t) return ns.SampleReply(t, "craft") end })
    add({ type = "text", key = "missingMsg", label = "When you're short on mats", default = defaults.missingMsg,
          preview = function(t) return ns.SampleReply(t, "craft") end })
    add({ type = "text", key = "genericMsg", label = "When they didn't say what they want", default = defaults.genericMsg,
          preview = function(t) return ns.SampleReply(t, "generic") end })
    add({ type = "text", key = "lockMsg", label = "Lockboxes", default = defaults.lockMsg,
          preview = function(t) return ns.SampleReply(t, "lock") end })
    add({ type = "text", key = "customMsg", label = "Your own phrases (/cs add)", default = defaults.customMsg,
          preview = function(t) return ns.SampleReply(t, "custom") end })
    add({ type = "info", height = 58, lines = function()
        return "|cff999999{name} their first name, {item} the recipe, {who} \"an enchanter\", {price} \" for 5g\" from your prices, {mats} the materials, {matsline} \" It takes 4 Large Brilliant Shard.\" (left out when they bring mats), {missing} what you're short of, {queue} \" You're #2 in line.\" when others are ahead, {zone} where you are.|r" end })
    add({ type = "check", key = "autoReply", label = "Reply automatically when someone whispers you a request" })
    add({ type = "check", key = "autoReplyCant", label = "Also reply when you can't help (a recipe you don't have, or they're elsewhere)" })
    add({ type = "text", key = "cantMsg", label = "Can't-help reply", default = defaults.cantMsg,
          preview = function(t) return ns.SampleReply(t, "craft") end })
    add({ type = "range", key = "autoReplyGap", label = "Don't auto-reply to them again for", min = 1, max = 30, step = 1, suffix = " min" })
    add({ type = "info", height = 22, lines = function() return ns.ReplyWarning() end })

    add({ type = "header", label = "When someone asks" })
    add({ type = "check", key = "sound", label = "Play a sound" })
    add({ type = "dropdown", key = "soundKey", label = "Sound", options = ns.SoundOptions,
          onSelect = function(v) ns.PlayAlertSound(v) end, preview = function(v) ns.PlayAlertSound(v) end })
    add({ type = "check", key = "flash", label = "Flash the WoW icon on the taskbar" })
    add({ type = "check", key = "screenMsg", label = "Show a message at the top of the screen" })
    add({ type = "check", key = "edgeFlash", label = "Flash the edges of the screen" })
    add({ type = "check", key = "autoInvite", label = "Invite them automatically when you can do it (you know the recipe and have or they bring the mats)" })

    add({ type = "header", label = "Trading" })
    add({ type = "check", key = "tradePanel", label = "Show the helper beside the trade window (mats, payment, slot check, enchant and Pick Lock buttons)" })
    add({ type = "choice", key = "receiptMode", label = "Payment messages (Auto / Prefill / Off)", values = { "auto", "prefill", "off" } })
    add({ type = "check", key = "receiptAll", label = "Post for every trade, not just customers" })
    add({ type = "check", key = "hideAmount", label = "Keep the gold amount out of payment messages" })
    add({ type = "text", key = "paidMsg", label = "Payment received", default = defaults.paidMsg,
          preview = function(t) return (t:gsub("{name}", "Testbuyer"):gsub("{amount}", "1g 50s")) end })
    add({ type = "check", key = "matsReceipt", label = "Say thanks when someone hands over mats (before paying)" })
    add({ type = "text", key = "matsMsg", label = "Mats received", default = defaults.matsMsg,
          preview = function(t) return (t:gsub("{name}", "Testbuyer"):gsub("{items}", "4x Large Brilliant Shard")) end })
    add({ type = "text", key = "payAskMsg", label = "Ask to pay button", default = defaults.payAskMsg,
          preview = function(t) return (t:gsub("{name}", "Testbuyer"):gsub("{price}", "5g"):gsub("{short}", "1g 50s")) end })
    add({ type = "text", key = "matsAskMsg", label = "Ask for mats button", default = defaults.matsAskMsg,
          preview = function(t) return (t:gsub("{name}", "Testbuyer"):gsub("{missing}", "2 Large Brilliant Shard")) end })
    add({ type = "check", key = "kickAfterJob", label = "Remove customers from the group once they've paid (only people you invited, while you lead)" })
    add({ type = "range", key = "kickDelay", label = "Wait before removing them", min = 5, max = 120, step = 5, suffix = "s" })
    add({ type = "button", label = "Test a payment message", func = function() ns.TestTrade("complete") end })

    add({ type = "header", label = "Earnings (saved, kept through logouts)" })
    add({ type = "info", lines = function() return ns.EarningsLines() end, height = 190 })

    add({ type = "header", label = "Channels" })
    add({ type = "check", key = "chTrade", label = "Trade, General and other numbered channels" })
    add({ type = "check", key = "chSay", label = "Say and yell" })
    add({ type = "check", key = "chWhisper", label = "Whispers" })
    add({ type = "check", key = "chGuild", label = "Guild" })

    add({ type = "header", label = "Your location" })
    add({ type = "choice", key = "zone", label = "Where you are (Auto = current zone)", values = ns.ZoneChoices() })
    add({ type = "dropdown", key = "scope", label = "Show requests from", options = function() return {
        { value = "here", label = "Your city only" },
        { value = "nearby", label = "Your city + unknown" },
        { value = "all", label = "Everywhere (rest dimmed)" },
      } end })
    add({ type = "check", key = "alertLow", label = "Alert for low-priority requests too" })

    add({ type = "header", label = "Window" })
    add({ type = "choice", key = "theme", label = "Window theme", values = { "dark", "light" } })
    add({ type = "range", key = "expire", label = "Keep new requests for", min = 30, max = 600, step = 30, suffix = "s" })
    add({ type = "range", key = "keepActive", label = "Keep customers you've invited for", min = 5, max = 60, step = 5, suffix = " min" })
    add({ type = "range", key = "maxRows", label = "Rows shown", min = 2, max = 12, step = 1 })
    add({ type = "button", label = "Add test requests", func = RunTest })
    add({ type = "button", label = "Reset window position", func = function()
        db.point = { unpack(defaults.point) }; ApplyPosition() end })

    -- per-profession checkboxes and the price / feature boxes aren't plain settings
    local proxy = setmetatable({}, {
        __index = function(_, k)
            local key = type(k) == "string" and k:match("^prof_(.+)$")
            if key then return db.profs[key] ~= false end
            if k == "priceEntry" or k == "featureEntry" then return "" end
            return db[k]
        end,
        __newindex = function(_, k, v)
            local key = type(k) == "string" and k:match("^prof_(.+)$")
            if key then
                db.profs[key] = (not v) and false or nil
            elseif k == "priceEntry" then
                if v ~= "" then ns.SetPriceFromText(v) end
            elseif k == "featureEntry" then
                if v ~= "" then ns.ToggleFeature(v) end
            else
                db[k] = v
            end
        end,
    })

    ns.CreateOptions({
        title = "Craft Services",
        updateNotice = true,
        changes = {
            { "1.0.0", "Spots requests for every profession: links, nicknames like \"crusader\" or \"+7 agi gloves\", recipe names",
                       "Knows your recipes and mats; replies fill in the recipe, your price, the mats and their place in line",
                       "Follows each customer from invite to paid, with a helper beside the trade window" },
        },
        icon = "Interface\\Icons\\Trade_BlackSmithing",
        about = "Spots crafting, enchanting and lockbox requests in chat",
        credit = "Created by Miff, supported by Claude",
        slash = "/cs",
        db = proxy,
        onChange = function() ns.ApplyTheme(); Refresh() end,
        controls = controls,
    })
end

-- Called shortly after login, when your professions are known (the page is built the
-- first time you open it, so this is in time).
function ns.AddProfessionChecks()
    local controls = ns.optionControls
    if not controls or ns.profChecksAdded then return end
    local at = ns.profChecksAt
    for _, p in ipairs(ns.PROFS) do
        if ns.Book.Has(p.key) then
            table.insert(controls, at, { type = "check", key = "prof_" .. p.key,
                label = "Watch for " .. (p.key == "lockpicking" and "lockbox" or p.name:lower()) .. " requests" })
            at = at + 1
            ns.profChecksAdded = true
        end
    end
end

function CraftServices_OnAddonCompartmentClick()
    if ns.OpenOptions then ns.OpenOptions() end
end

---------------------------------------------------------------------------
-- Slash command: /cs
---------------------------------------------------------------------------
local function ListPhrases(list, what)
    if #list == 0 then Print("no " .. what .. " yet.") return end
    for i, p in ipairs(list) do Print(i .. ". " .. p) end
end

-- /cs can <text>: do you know it, and do you have the mats?
local function CanCommand(text)
    local e = ns.Book.Lookup(text)
    if not e then Print("no recipe of yours matches \"" .. text .. "\".") return end
    local m = ns.Book.Mats(e)
    local price = ns.Book.Price(e)
    Print(("%s (%s)%s"):format(e.name, ns.PROF_BY_KEY[e.prof].name, price and (", your price " .. Money(price)) or ""))
    if m.text ~= "" then
        Print("mats: " .. m.text .. (m.have and "  |cff4cd964you have them|r" or ""))
        for _, x in ipairs(m.missing or {}) do Print(("  short: %s (have %d of %d)"):format(x.name, x.have, x.need)) end
    end
end

-- /cs shopping: everything you're short of for the requests in the list
local function ShoppingList()
    local need = {}
    for _, r in ipairs(requests) do
        local e = r.info.recipe
        if e and r.info.mats ~= "theirs" then
            for _, x in ipairs(ns.Book.Mats(e).missing or {}) do
                need[x.name] = (need[x.name] or 0) + (x.need - x.have)
            end
        end
    end
    local lines = {}
    for name, n in pairs(need) do lines[#lines + 1] = n .. " " .. name end
    table.sort(lines)
    if #lines == 0 then Print("you have the mats for every request in the list.") return end
    Print("short of, for the requests in the list: " .. table.concat(lines, ", "))
end

SLASH_CRAFTSERVICES1 = "/cs"
SLASH_CRAFTSERVICES2 = "/craftservices"
SlashCmdList.CRAFTSERVICES = function(msg)
    msg = msg or ""
    local cmd, rest = msg:match("^(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    local n = tonumber(rest)

    if cmd == "" then
        ns.OpenOptions()
    elseif cmd == "price" then
        if rest == "" then
            local l = PriceLines()
            Print(#l > 0 and ("prices: " .. table.concat(l, ", ")) or "no prices set. /cs price <recipe> <amount>, e.g. /cs price crusader 5g")
        else
            ns.SetPriceFromText(rest)
        end
    elseif cmd == "prices" then
        local l = PriceLines()
        Print(#l > 0 and ("prices: " .. table.concat(l, ", ")) or "no prices set.")
    elseif cmd == "feature" and rest ~= "" then
        ns.ToggleFeature(rest)
    elseif cmd == "featured" or (cmd == "feature" and rest == "") then
        local l = FeaturedLines()
        Print(#l > 0 and ("featured: " .. table.concat(l, ", ")) or "nothing featured. /cs feature <recipe>")
    elseif cmd == "can" and rest ~= "" then
        CanCommand(rest)
    elseif cmd == "shopping" or cmd == "mats" then
        ShoppingList()
    elseif cmd == "recipes" then
        for _, line in ipairs(RecipeLines()) do Print(line) end
    elseif cmd == "zone" then
        if rest == "" then
            Print("you're in: " .. (ns.MyZone() ~= "" and ns.MyZone() or "unknown")
                .. (db.zone == "auto" and " (detected)" or " (picked; /cs zone auto to detect)"))
        elseif rest:lower() == "auto" then
            db.zone = "auto"; Print("location: detect automatically (now " .. ns.MyZone() .. ")")
        else
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
        Print("pick one with /cs sound <number>")
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
            Print("/cs earnings reset yes - clears this character's earnings (the all-characters total is kept)")
            Print("/cs earnings reset all yes - clears everything, every character, for good")
        else
            for _, line in ipairs(ns.EarningsLines()) do Print(line) end
        end
        Refresh()
    elseif cmd == "customers" then
        if rest:lower() == "forget yes" then wipe(db.history); Print("customer history cleared.") return end
        local list = {}
        for key, h in pairs(db.history) do list[#list + 1] = { key = key, h = h } end
        table.sort(list, function(a, b) return a.h.total > b.h.total end)
        if #list == 0 then Print("no customers yet.") end
        for i = 1, math.min(10, #list) do
            local x = list[i]
            Print(("%s: %d time%s, %s%s"):format(x.h.name or x.key, x.h.count, x.h.count == 1 and "" or "s", Money(x.h.total),
                x.h.item and (", last " .. x.h.item) or ""))
        end
        if #list > 0 then Print("/cs customers forget yes clears this list.") end
    elseif cmd == "testtrade" then
        ns.TestTrade(rest ~= "" and rest:lower() or "complete")
    elseif cmd == "show" then
        ns.ShowWindow()
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
    elseif cmd == "autoreply" then
        db.autoReply = not db.autoReply
        Print(db.autoReply and "automatic replies to whispers are on" or "automatic replies are off")
    elseif cmd == "autoinvite" then
        db.autoInvite = not db.autoInvite
        Print(db.autoInvite and "automatic invites are on (only when you can do it)" or "automatic invites are off")
    else
        Print("v" .. ns.version .. " commands (or just /cs for the settings page):")
        Print("/cs pause, /cs resume - stop or start taking requests on this character (now " .. (ns.IsPaused() and "paused" or "on") .. ")")
        Print("/cs recipes - what it knows of your professions (open a profession window to update)")
        Print("/cs can <recipe> - do you know it, and do you have the mats? e.g. /cs can crusader")
        Print("/cs price <recipe> <amount> - your price, e.g. /cs price crusader 5g; /cs prices to list them")
        Print("/cs feature <recipe> - list it in your advert; /cs featured to see them")
        Print("/cs ad - post your advert; /cs shopping - mats you're short of for the current requests")
        Print("/cs customers - your best customers; /cs autoreply, /cs autoinvite - turn those on or off")
        Print("/cs filter here|nearby|all - which requests show (now " .. db.scope .. ")")
        Print("/cs add <phrase>, /cs list, /cs remove <n> - your own phrases; /cs exclude <phrase> to ignore lines")
        Print("/cs zone [auto|city], /cs theme, /cs sounds, /cs earnings, /cs receipts [auto|prefill|off]")
        Print("/cs test - add sample requests, /cs show - show the window, /cs testtrade [complete|mats|cancelled|failed] - try a payment message")
    end
    if ns.RefreshOptions then ns.RefreshOptions() end
end

-- Kick Tally (WoW Forever)
-- Announces your successful interrupts in chat and keeps a small window with how many
-- kicks each person in your party or raid has landed, this fight and in total.
--
-- WoW Forever runs on a client where addons can't read the combat log, and in combat
-- the game hides which spells other players cast. So Kick Tally works from what it can
-- still see:
--   * your own casts (readable): you cast Pummel, and a moment later an enemy's cast is
--     interrupted, so your kick landed. No interrupt means it missed or had nothing to stop.
--   * the enemy's "cast interrupted" event, and who interrupted it when the game says.
--   * a party or raid member's cast landing at the same moment an enemy's cast is
--     interrupted, when the game hides which spell it was.
-- Chat messages from addons are blocked during boss encounters, so there your kicks go
-- to your own chat window instead. /kicks debug prints what it sees.

local ADDON_NAME, ns = ...
local KICKS = ns.KICKS

local defaults = {
    updateNotice = true,
    announce   = true,       -- post your successful kicks in chat
    channel    = "auto",     -- auto, party, raid, instance, say, yell, self
    message    = "Interrupted {target}'s {spell}!",
    stuns      = true,       -- stuns and fears that stop a cast count as kicks
    printLocal = true,       -- show your kick in your own chat window when it isn't posted
    missed     = true,       -- tell me when my kick didn't interrupt anything
    sound      = false,
    trackGroup = true,       -- count party and raid members' kicks too
    show       = "group",    -- tracker window: group, always, never
    rows       = 8,
    locked     = false,
    reportAfterBoss = false, -- post the fight's kicks to the group after a boss
    total      = {},         -- [name] = kicks in total
    classes    = {},         -- [name] = class token, for colours
    pos        = nil,
}

-- how close (seconds) a cast and an enemy's interrupted cast must be to belong together
local BEFORE, AFTER = 0.4, 0.2  -- a known kick: cast up to 0.4s before, or 0.2s after
local TIGHT = 0.1               -- a hidden spell: must land at the same moment
local WAIT = 0.25               -- wait this long before deciding who kicked
local MISS_WAIT = 0.8           -- no interrupt this long after your kick: it missed

local db
local debugMode, testMode = false, false
local playerName, playerGUID, petGUID
local fight = {}        -- [name] = kicks this fight
local roster = {}       -- [unit] = name, refreshed whenever the group changes
local guidName = {}     -- [guid] = name (pets map to their owner)
local casts = {}        -- recent casts that could be kicks
local lastEvent         -- the latest enemy interrupt, to merge the same one seen on two units
local lastLine          -- "Mitch > Defias Pillager (Fireball)" for the window
local sentTarget        -- target name of your last cast, from UNIT_SPELLCAST_SENT
local inEncounter = false

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

-- the value if the game lets us read it, otherwise nil
local function Readable(v)
    if IsSecret(v) then return nil end
    return v
end

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8000Kick Tally:|r " .. msg)
end

local function Debug(msg)
    if debugMode then DEFAULT_CHAT_FRAME:AddMessage("|cffff8000Kick Tally debug:|r " .. msg) end
end

local function SpellName(id)
    id = Readable(id)
    if not id then return nil end
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, id)
        if ok and not IsSecret(name) and name then return name end
    end
    local k = KICKS[id]
    return k and k.name
end

local function NameOf(unit)
    local ok, name = pcall(UnitName, unit)
    if ok and not IsSecret(name) and name then return name end
end

local function GUIDOf(unit)
    local ok, guid = pcall(UnitGUID, unit)
    if ok and not IsSecret(guid) and guid then return guid end
end

-- the group member a unit belongs to ("partypet2" -> "party2"), or nil for anyone else
local function OwnerUnit(unit)
    if type(unit) ~= "string" or IsSecret(unit) then return nil end
    if unit == "player" or unit == "pet" or unit == "vehicle" then return "player" end
    local n = unit:match("^partypet(%d)$")
    if n then return "party" .. n end
    n = unit:match("^raidpet(%d+)$")
    if n then return "raid" .. n end
    if unit:match("^party%d$") or unit:match("^raid%d+$") then return unit end
end

local function IsEnemy(unit)
    local ok, v = pcall(UnitCanAttack, "player", unit)
    if ok and not IsSecret(v) then return v and true or false end
    return true -- can't tell; group units were already left out
end

local function InGroup()
    return IsInGroup and IsInGroup() or false
end

local function ClassColor(name)
    local class = db and db.classes[name]
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255) end
    return "|cffffffff"
end

---------------------------------------------------------------------------
-- Group
---------------------------------------------------------------------------
local function AddMember(unit)
    local name = NameOf(unit)
    if not name then return end
    roster[unit] = name
    local ok, _, class = pcall(UnitClass, unit)
    if ok and not IsSecret(class) and class then db.classes[name] = class end
    local guid = GUIDOf(unit)
    if guid then guidName[guid] = name end
end

local function UpdateRoster()
    wipe(roster)
    playerName = NameOf("player") or playerName
    playerGUID = GUIDOf("player") or playerGUID
    petGUID = GUIDOf("pet")
    if playerName then
        roster.player = playerName
        local _, class = UnitClass("player")
        if not IsSecret(class) and class then db.classes[playerName] = class end
        if playerGUID then guidName[playerGUID] = playerName end
        if petGUID then guidName[petGUID] = playerName end
    end
    if IsInRaid and IsInRaid() then
        for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
            local u = "raid" .. i
            if UnitExists(u) then
                AddMember(u)
                local pg = GUIDOf("raidpet" .. i)
                if pg and roster[u] then guidName[pg] = roster[u] end
            end
        end
    elseif InGroup() then
        for i = 1, 4 do
            local u = "party" .. i
            if UnitExists(u) then
                AddMember(u)
                local pg = GUIDOf("partypet" .. i)
                if pg and roster[u] then guidName[pg] = roster[u] end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Chat
---------------------------------------------------------------------------
local function ChatLocked()
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok, v = pcall(C_ChatInfo.InChatMessagingLockdown)
        if ok and not IsSecret(v) and v then return true end
    end
    return false
end

local function InInstance()
    if not IsInInstance then return false end
    local inside = IsInInstance()
    if IsSecret(inside) then return false end
    return inside and true or false
end

-- the chat to post in, or nil when there's nowhere suitable
local function ChatType(channel)
    channel = channel or db.channel
    local instanceGroup = IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE or 2)
    local raid = IsInRaid and IsInRaid()
    if channel == "self" then return nil end
    if channel == "auto" then
        if instanceGroup then return "INSTANCE_CHAT" end
        if raid then return "RAID" end
        if InGroup() then return "PARTY" end
        return nil
    elseif channel == "party" then
        return InGroup() and "PARTY" or nil
    elseif channel == "raid" then
        if raid then return "RAID" end
        return InGroup() and "PARTY" or nil
    elseif channel == "instance" then
        if instanceGroup then return "INSTANCE_CHAT" end
        return InGroup() and "PARTY" or nil
    elseif channel == "say" or channel == "yell" then
        -- outside instances the game only lets these out on a key press
        return InInstance() and channel:upper() or nil
    end
end

local function Send(msg, chatType)
    local f = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not f or not chatType then return false end
    return (pcall(f, msg, chatType))
end

-- post a line; returns true if it went out
local function Post(msg, channel)
    local ct = ChatType(channel)
    if not ct then return false, "nowhere to post" end
    if ChatLocked() then return false, "chat is locked during boss fights" end
    if Send(msg, ct) then return true end
    return false, "the game refused it"
end

-- fill the message template; any part the game hid is left out
local function Fill(template, v)
    local s = template or ""
    if not v.spell then
        s = s:gsub("'s {spell}", ""):gsub("{spell}", "")
    end
    if not v.target then
        s = s:gsub("{target}'s ", ""):gsub("{target}", "")
    end
    s = s:gsub("{target}", function() return v.target end)
    s = s:gsub("{spell}", function() return v.spell end)
    s = s:gsub("{ability}", function() return v.ability or "" end)
    s = s:gsub("{count}", function() return tostring(v.count or "") end)
    s = s:gsub("%(%s*%)", ""):gsub("%s+([!%.,%?])", "%1"):gsub("%s%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return s
end
ns.Fill = Fill

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local win = CreateFrame("Frame", "KickTallyFrame", UIParent)
win:SetSize(190, 60)
win:SetFrameStrata("MEDIUM")
win:SetClampedToScreen(true)
win:SetMovable(true)
win:Hide()
local bg = win:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.55)

local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
title:SetPoint("TOPLEFT", 6, -5)
title:SetText("|cffff8000Kick|r Tally")
local cols = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
cols:SetPoint("TOPRIGHT", -6, -5)
cols:SetText("fight (all)")

local rowsL, rowsR = {}, {}
local function Row(i)
    if not rowsL[i] then
        local l = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        l:SetPoint("TOPLEFT", 8, -8 - i * 13)
        l:SetJustifyH("LEFT")
        local r = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r:SetPoint("TOPRIGHT", -8, -8 - i * 13)
        r:SetJustifyH("RIGHT")
        rowsL[i], rowsR[i] = l, r
    end
    return rowsL[i], rowsR[i]
end
local last = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
last:SetJustifyH("LEFT")
last:SetWidth(178)

win:SetScript("OnDragStart", function(self) if not db.locked then self:StartMoving() end end)
win:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    db.pos = { point, rel, x, y }
end)

local function PlaceWindow()
    win:ClearAllPoints()
    local p = db.pos
    if p then
        win:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        win:SetPoint("RIGHT", UIParent, "RIGHT", -240, 60)
    end
end

local sample = { { "Miff", 3, 41, "WARRIOR" }, { "Grunk", 2, 17, "ROGUE" }, { "Sally", 1, 9, "SHAMAN" }, { "Zaxx", 0, 4, "MAGE" } }

local function Layout()
    if not db then return end
    local show = testMode or db.show == "always" or (db.show == "group" and InGroup())
    win:EnableMouse(not db.locked)
    if win.RegisterForDrag then win:RegisterForDrag("LeftButton") end
    if not show then win:Hide() return end

    local list = {}
    if testMode then
        for _, s in ipairs(sample) do list[#list + 1] = { name = s[1], f = s[2], t = s[3], class = s[4] } end
    else
        local seen = {}
        local function add(name)
            if name and not seen[name] then
                seen[name] = true
                list[#list + 1] = { name = name, f = fight[name] or 0, t = db.total[name] or 0 }
            end
        end
        for _, name in pairs(roster) do add(name) end
        for name in pairs(fight) do add(name) end
        table.sort(list, function(a, b)
            if a.f ~= b.f then return a.f > b.f end
            if a.t ~= b.t then return a.t > b.t end
            return a.name < b.name
        end)
    end

    local n = math.min(#list, db.rows)
    for i = 1, math.max(n, #rowsL) do
        local l, r = Row(i)
        local e = list[i]
        if e and i <= n then
            local color = e.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class]
            local hex = color and ("|cff%02x%02x%02x"):format(color.r * 255, color.g * 255, color.b * 255) or ClassColor(e.name)
            l:SetText(hex .. e.name .. "|r")
            r:SetText((e.f > 0 and "|cffffd100" .. e.f .. "|r" or "|cff8080800|r") .. "  |cff999999(" .. e.t .. ")|r")
            l:Show(); r:Show()
        else
            l:Hide(); r:Hide()
        end
    end
    local text = testMode and "Last: Miff > Defias Pillager (Fireball)" or (lastLine and ("Last: " .. lastLine)) or nil
    last:ClearAllPoints()
    last:SetPoint("TOPLEFT", 8, -10 - (n + 1) * 13)
    last:SetText(text or "")
    last:SetShown(text ~= nil)
    win:SetHeight(18 + n * 13 + (text and 18 or 6) + (n == 0 and 13 or 0))
    if n == 0 then
        local l, r = Row(1)
        l:SetText("|cff999999No kicks yet|r"); l:Show(); r:Hide()
    end
    win:Show()
end
ns.Layout = Layout

---------------------------------------------------------------------------
-- Kicks
---------------------------------------------------------------------------
local function Prune(now)
    local keep = {}
    for _, c in ipairs(casts) do
        if now - c.t < 3 then keep[#keep + 1] = c end
    end
    casts = keep
end

-- the unused cast closest in time to t that passes test, within the window
local function Best(t, test, before, after)
    local best, gap
    for _, c in ipairs(casts) do
        if not c.used and test(c) and c.t >= t - before and c.t <= t + after then
            local d = math.abs(c.t - t)
            if not gap or d < gap then best, gap = c, d end
        end
    end
    return best
end

local function Missed(c)
    if c.used or not db.missed then return end
    Print(("your %s didn't interrupt anything."):format(SpellName(c.id) or "kick"))
    if db.sound and PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_QUEST_FAILED or 847) end
end

local function OwnKick(e, cast)
    local values = {
        target = e.target or (cast and cast.target),
        spell = e.spell,
        ability = cast and SpellName(cast.id),
        count = fight[playerName],
    }
    if db.sound and PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.RAID_WARNING or 8959) end
    local msg = Fill(db.message, values)
    local sent, why = false, "announcing is off"
    if db.announce and msg ~= "" then sent, why = Post(msg) end
    if not sent and db.printLocal then
        Print(msg ~= "" and msg or "you interrupted a cast.")
    end
    Debug("own kick: " .. msg .. (sent and " (posted)" or (" (not posted: " .. tostring(why) .. ")")))
end

local function Credit(who, e, cast)
    fight[who] = (fight[who] or 0) + 1
    db.total[who] = (db.total[who] or 0) + 1
    local what = e.target or "?"
    if e.spell then what = what .. " (" .. e.spell .. ")" end
    lastLine = who .. " > " .. what
    Debug(("kick credited to %s%s"):format(who, cast and cast.id and (" with " .. tostring(SpellName(cast.id))) or " (spell hidden)"))
    if who == playerName then OwnKick(e, cast) end
    Layout()
end

local function Resolve(e)
    local who, cast
    if e.by then
        who = guidName[e.by]
        if not who then Debug("interrupted by someone outside your group") return end
        cast = Best(e.t, function(c) return c.name == who end, BEFORE, AFTER)
    else
        cast = Best(e.t, function(c) return c.own and c.known end, BEFORE, AFTER)
            or Best(e.t, function(c) return not c.own and c.known end, BEFORE, AFTER)
            or (not e.channel and Best(e.t, function(c) return not c.known end, TIGHT, TIGHT))
        if not cast then
            Debug(e.channel and "a channel ended with no kick nearby (finished on its own)"
                or "an enemy's cast was interrupted, but no kick was seen at that moment")
            return
        end
        who = cast.name
    end
    if cast then cast.used = true end
    if who ~= playerName and not db.trackGroup then return end
    Credit(who, e, cast)
end

local function OnCast(unit, spellID)
    local owner = OwnerUnit(unit)
    if not owner then return end
    local own = owner == "player"
    if not own and not db.trackGroup then return end
    local id = Readable(spellID)
    local info = id and KICKS[id]
    if id and not info then return end -- a spell we can read and it isn't a kick
    if info and info.kind == "stun" and not db.stuns then return end
    local name = own and playerName or roster[owner] or NameOf(owner)
    if not name then return end
    local now = GetTime()
    Prune(now)
    local c = { t = now, name = name, id = id, known = info ~= nil, own = own }
    if own and sentTarget and now - sentTarget.t < 2 then c.target = sentTarget.name end
    casts[#casts + 1] = c
    Debug(("cast by %s: %s"):format(name, id and tostring(SpellName(id)) or "(hidden spell)"))
    if own and info and info.kind == "kick" then
        C_Timer.After(MISS_WAIT, function() Missed(c) end)
    end
end

local function OnInterrupted(event, unit, spellID, interruptedBy)
    if type(unit) ~= "string" or IsSecret(unit) or OwnerUnit(unit) then return end
    if not IsEnemy(unit) then return end
    -- a caster that died mid-cast wasn't kicked
    local okDead, dead = pcall(UnitIsDead, unit)
    if okDead and not IsSecret(dead) and dead then return end
    local channel = event == "UNIT_SPELLCAST_CHANNEL_STOP"
    local by = Readable(interruptedBy)
    local now = GetTime()
    local spell = SpellName(spellID)
    local target = NameOf(unit)
    if by == "" then by = nil end

    -- the same interrupt seen on two units (your target and its nameplate)
    if lastEvent and now - lastEvent.t < 0.08 and lastEvent.by == by then
        lastEvent.spell = lastEvent.spell or spell
        lastEvent.target = lastEvent.target or target
        if not channel then lastEvent.channel = false end
        return
    end
    local e = { t = now, spell = spell, target = target, by = by, channel = channel }
    lastEvent = e
    Debug(("%s on %s%s"):format(channel and "channel stopped" or "cast interrupted", tostring(target or unit),
        by and (" by " .. tostring(guidName[by] or by)) or ""))
    C_Timer.After(WAIT, function() Resolve(e) end)
end

---------------------------------------------------------------------------
-- Reports
---------------------------------------------------------------------------
local function Summary(counts)
    local list = {}
    for name, n in pairs(counts) do if n > 0 then list[#list + 1] = { name, n } end end
    if #list == 0 then return nil end
    table.sort(list, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
    local parts = {}
    for i, v in ipairs(list) do
        if i > 10 then break end
        parts[#parts + 1] = v[1] .. " " .. v[2]
    end
    return table.concat(parts, ", ")
end

local function Report(which, quiet)
    local counts = (which == "total") and db.total or fight
    local s = Summary(counts)
    if not s then
        if not quiet then Print("no kicks to report yet.") end
        return true
    end
    local line = (which == "total" and "Kicks in total: " or "Kicks this fight: ") .. s
    local sent, why = Post(line, "auto")
    if not sent and not quiet then Print(line .. "  |cff999999(" .. tostring(why) .. ")|r") end
    return sent
end

local function ReportAfterBoss(tries)
    if not db.reportAfterBoss then return end
    if ChatLocked() and tries < 6 then
        C_Timer.After(2, function() ReportAfterBoss(tries + 1) end)
        return
    end
    Report("fight", true)
end

---------------------------------------------------------------------------
-- Test
---------------------------------------------------------------------------
local function SetTest(on)
    testMode = on
    if on then
        Print("test: " .. Fill(db.message, { target = "Defias Pillager", spell = "Fireball", ability = "Pummel", count = 3 })
            .. "  |cff999999(sample only, nothing was posted)|r")
    end
    Layout()
end
ns.SetTest = SetTest

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local function SafeRegister(event, unit)
    if unit then return pcall(ev.RegisterUnitEvent, ev, event, unit) end
    return pcall(ev.RegisterEvent, ev, event)
end
SafeRegister("ADDON_LOADED")

ev:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON_NAME then return end
        KickTallyDB = KickTallyDB or {}
        for k, v in pairs(defaults) do
            if KickTallyDB[k] == nil then
                KickTallyDB[k] = type(v) == "table" and {} or v
            end
        end
        db = KickTallyDB
        ns.db = db
        UpdateRoster()
        PlaceWindow()
        if ns.StartVersionCheck then ns.StartVersionCheck(db, "Kick Tally") end
        ns.BuildOptions()

        SafeRegister("PLAYER_ENTERING_WORLD")
        SafeRegister("GROUP_ROSTER_UPDATE")
        SafeRegister("UNIT_PET")
        SafeRegister("PLAYER_REGEN_DISABLED")
        SafeRegister("ENCOUNTER_START")
        SafeRegister("ENCOUNTER_END")
        SafeRegister("UNIT_SPELLCAST_SENT", "player")
        SafeRegister("UNIT_SPELLCAST_SUCCEEDED")
        SafeRegister("UNIT_SPELLCAST_INTERRUPTED")
        SafeRegister("UNIT_SPELLCAST_CHANNEL_STOP")
        Layout()
        return
    end

    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnCast(a1, a3)
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        OnInterrupted(event, a1, a3, a4)
    elseif event == "UNIT_SPELLCAST_SENT" then
        local target = Readable(a2)
        if target and target ~= "" then sentTarget = { t = GetTime(), name = target } end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- a new fight (a boss fight keeps counting from its start)
        if not inEncounter then wipe(fight); lastLine = nil end
        UpdateRoster()
        Layout()
    elseif event == "ENCOUNTER_START" then
        inEncounter = true
        wipe(fight); lastLine = nil
        Layout()
    elseif event == "ENCOUNTER_END" then
        inEncounter = false
        C_Timer.After(2, function() ReportAfterBoss(0) end)
    elseif event == "UNIT_PET" then
        if a1 == "player" then petGUID = GUIDOf("pet"); if petGUID and playerName then guidName[petGUID] = playerName end
        else UpdateRoster() end
    else -- PLAYER_ENTERING_WORLD, GROUP_ROSTER_UPDATE
        UpdateRoster()
        Layout()
    end
end)

---------------------------------------------------------------------------
-- Settings page and slash command
---------------------------------------------------------------------------
local CHANNEL_HELP = {
    auto = "Auto: your instance group, raid or party chat. Nothing is posted when you're on your own.",
    party = "Party chat (when you're in a group).",
    raid = "Raid chat, or party chat in a party.",
    instance = "Instance chat (dungeon finder groups), or party chat.",
    say = "Say. Only works inside dungeons and raids: the game blocks addons from using say outdoors.",
    yell = "Yell. Only works inside dungeons and raids: the game blocks addons from using yell outdoors.",
    self = "Only you: a line in your own chat window.",
}

function ns.BuildOptions()
    ns.CreateOptions({
        title = "Kick Tally",
        updateNotice = true,
        changes = {
            { "1.0.0", "First version: announces your successful kicks",
                       "Counts your party and raid's kicks, this fight and in total",
                       "Tells you when a kick didn't interrupt anything" },
        },
        icon = "Interface\\Icons\\Ability_Kick",
        about = "Announces your kicks and tallies the group's",
        credit = "Created by Miff, supported by Claude",
        slash = "/kicks",
        db = db,
        onChange = function() Layout() end,
        controls = {
            { type = "header", label = "Your kicks" },
            { type = "check", key = "announce", label = "Announce your successful kicks in chat" },
            { type = "choice", key = "channel", label = "Where to announce",
              values = { "auto", "party", "raid", "instance", "say", "yell", "self" } },
            { type = "info", height = 30, lines = function()
                return "|cff999999" .. (CHANNEL_HELP[db.channel] or "") .. "|r" end },
            { type = "text", key = "message", label = "Message ({target}, {spell}, {ability}, {count})",
              default = defaults.message,
              preview = function(text) return Fill(text, { target = "Defias Pillager", spell = "Fireball", ability = "Pummel", count = 3 }) end },
            { type = "check", key = "stuns", label = "Count stuns and fears that stop a cast (Hammer of Justice, Kidney Shot...)" },
            { type = "check", key = "printLocal", label = "Show your kick in your own chat window when it isn't posted" },
            { type = "check", key = "missed", label = "Tell me when my kick didn't interrupt anything" },
            { type = "check", key = "sound", label = "Play a sound on a kick" },
            { type = "header", label = "Tally window" },
            { type = "choice", key = "show", label = "Show the window", values = { "group", "always", "never" } },
            { type = "check", key = "trackGroup", label = "Count party and raid members' kicks too" },
            { type = "range", key = "rows", label = "Players shown", min = 3, max = 20, step = 1 },
            { type = "check", key = "locked", label = "Lock the window (otherwise drag it to move)" },
            { type = "button", label = "Reset position", func = function() db.pos = nil; PlaceWindow() end },
            { type = "button", label = "Reset the counts", func = function() wipe(fight); wipe(db.total); lastLine = nil; Layout() end },
            { type = "button", label = "Test",
              dynamicLabel = function() return testMode and "Stop the test" or "Test" end,
              func = function() SetTest(not testMode) end },
            { type = "check", key = "reportAfterBoss", label = "After a boss fight, post that fight's kicks to the group" },
            { type = "header", label = "How it works on WoW Forever" },
            { type = "info", height = 96, lines = function()
                return "|cff999999Your own kicks are exact: Kick Tally sees you cast Pummel and the enemy's cast being interrupted. "
                    .. "In combat the game hides which spells other players cast, so a party member's kick is counted when their cast "
                    .. "and an enemy's interrupted cast happen at the same moment. Keep enemy nameplates on so it sees every enemy. "
                    .. "Addons can't post in chat during boss fights, so there your kicks show in your own chat window.|r" end },
        },
    })
end

function KickTally_OnAddonCompartmentClick()
    if ns.OpenOptions then ns.OpenOptions() end
end

SLASH_KICKTALLY1 = "/kicks"
SLASH_KICKTALLY2 = "/kicktally"
SlashCmdList.KICKTALLY = function(msg)
    local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "" then
        ns.OpenOptions()
    elseif cmd == "test" then
        SetTest(not testMode)
        if not testMode then Print("test off.") end
    elseif cmd == "lock" or cmd == "unlock" then
        db.locked = cmd == "lock"
        Layout()
        Print(db.locked and "window locked." or "window unlocked: drag it to move.")
    elseif cmd == "show" or cmd == "hide" then
        db.show = cmd == "show" and "always" or "never"
        Layout()
        Print(cmd == "show" and "window shown." or "window hidden. /kicks show to bring it back.")
    elseif cmd == "reset" then
        if rest == "position" then
            db.pos = nil; PlaceWindow(); Print("window position reset.")
        else
            wipe(fight); wipe(db.total); lastLine = nil; Layout(); Print("counts reset.")
        end
    elseif cmd == "report" then
        Report(rest == "total" and "total" or "fight")
    elseif cmd == "debug" then
        debugMode = not debugMode
        Print(debugMode and "debug on: casts and interrupts are printed. /kicks debug again to stop." or "debug off.")
        if debugMode then
            Print(("now: in a group %s, chat locked %s, announcing to %s"):format(tostring(InGroup()),
                tostring(ChatLocked()), tostring(ChatType() or "your chat window only")))
        end
    else
        Print("/kicks - settings")
        Print("/kicks test - sample window and message")
        Print("/kicks report [total] - post this fight's (or all) kicks to the group")
        Print("/kicks lock | unlock - lock or move the window")
        Print("/kicks show | hide - window always on or off")
        Print("/kicks reset [position] - reset the counts (or the window position)")
        Print("/kicks debug - print what it sees, to check it on Forever")
    end
end

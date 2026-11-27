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
-- to your own chat window instead. /ktally debug prints what it sees.

local ADDON_NAME, ns = ...
local KICKS = ns.KICKS

local defaults = {
    updateNotice = true,
    announce   = true,       -- post your successful kicks in chat
    channel    = "auto",     -- auto, party, raid, instance, say, yell, self
    message    = "{ability} interrupted {target}'s {spell}!",
    announceVague = false,   -- post even when the game hides both the enemy and its spell
    stuns      = true,       -- stuns and fears that stop a cast count as kicks
    printLocal = true,       -- show your kick in your own chat window when it isn't posted
    missed     = true,       -- tell me when my kick didn't interrupt anything
    sound      = false,
    trackGroup = true,       -- count party and raid members' kicks too
    showWindow = true,       -- the tally window
    groupOnly  = true,       -- ...only while in a party or raid
    mode       = "fight",    -- the window shows this fight ("fight") or overall ("total")
    collapsed  = false,      -- minimised to just its title bar
    width      = 250,
    height     = 140,        -- drag the bottom-right corner to resize
    barHeight  = 20,
    bgOpacity  = 60,         -- the window's background, like the meter's
    opacity    = 100,
    locked     = false,
    reportAfterBoss = false, -- post the fight's kicks to the group after a boss
    sync       = true,       -- swap kicks with other Kick Tally users in the group
    cooldowns  = true,       -- show interrupt cooldowns on the rows
    cds        = {},         -- [spellID] = cooldown read from the game
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
local sentTarget        -- target name of your last cast, from UNIT_SPELLCAST_SENT
local inEncounter = false
local cooldowns = {}    -- [name] = { id, start, dur } the interrupt they last used
local synced = {}       -- [name] = when they last told us they run Kick Tally

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

-- the raid marker on a unit (1 star ... 8 skull), when the game shows it
local function MarkOf(unit)
    if not GetRaidTargetIndex then return nil end
    local ok, i = pcall(GetRaidTargetIndex, unit)
    if ok and not IsSecret(i) and type(i) == "number" and i >= 1 and i <= 8 then return i end
end

-- enemies' names, read while the game still shows them: in a dungeon the game hides an
-- enemy's name once the fight starts, but it shows it when its nameplate appears or you
-- target it before the pull
local unitNames = {}
local function RememberName(unit)
    unitNames[unit] = NameOf(unit) or unitNames[unit]
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
    if not v.spell and not v.target then
        s = s:gsub("{target}'s {spell}", "a cast")
    end
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
-- The window: built to look like the game's own damage meter, using its art
---------------------------------------------------------------------------
local BAR_SPACING, HEADER = 4, 32
local sizing = false    -- the corner is being dragged
local scroll = 0        -- rows scrolled past, when there are more players than fit
local recent = {}       -- [name] = { "Defias Pillager (Fireball)", ... } this fight, newest last

-- the game's art; on a client without it, a plain colour stands in
local function Atlas(tex, atlas, r, g, b, a)
    if tex.SetAtlas then
        local ok, res = pcall(tex.SetAtlas, tex, atlas)
        if ok and res ~= false then return true end
    end
    tex:SetColorTexture(r or 0, g or 0, b or 0, a or 0.6)
    return false
end

local win = CreateFrame("Frame", "KickTallyFrame", UIParent)
win:SetSize(250, 120)
win:SetFrameStrata("MEDIUM")
win:SetClampedToScreen(true)
win:SetMovable(true)
win:EnableMouse(true)
win:Hide()

local body = win:CreateTexture(nil, "BACKGROUND", nil, -1)
body:SetPoint("TOPLEFT", 0, -HEADER + 6)
body:SetPoint("BOTTOMRIGHT")
Atlas(body, "damagemeters-background", 0.08, 0.05, 0.03, 0.8)

local header = win:CreateTexture(nil, "BACKGROUND")
header:SetPoint("TOPLEFT")
header:SetPoint("TOPRIGHT")
header:SetHeight(HEADER)
Atlas(header, "ui-damagemeters-header-bar", 0.12, 0.08, 0.02, 0.95)

-- the header is the drag handle
local drag = CreateFrame("Frame", nil, win)
drag:SetPoint("TOPLEFT")
drag:SetPoint("TOPRIGHT", -80, 0)
drag:SetHeight(HEADER)
drag:EnableMouse(true)
if drag.RegisterForDrag then drag:RegisterForDrag("LeftButton") end
drag:SetScript("OnDragStart", function() if not db.locked then win:StartMoving() end end)
drag:SetScript("OnDragStop", function()
    win:StopMovingOrSizing()
    local point, _, rel, x, y = win:GetPoint()
    db.pos = { point, rel, x, y }
end)

-- a small menu from a button; uses the game's menus when it has them
local function OpenMenu(owner, build)
    if MenuUtil and MenuUtil.CreateContextMenu then
        pcall(MenuUtil.CreateContextMenu, owner, function(_, root) build(root) end)
        return true
    end
    return false
end

-- title: the arrow dropdown, like the meter's "Damage Done"
local title
local okType, typeDD = pcall(CreateFrame, "DropdownButton", nil, win, "WowStyle1ArrowDropdownTemplate")
if okType and typeDD then
    typeDD:SetPoint("TOPLEFT", 4, -3)
    title = typeDD:CreateFontString(nil, "OVERLAY", "GameFontNormalMed1")
    if type(typeDD.Arrow) == "table" then
        title:SetPoint("LEFT", typeDD.Arrow, "RIGHT", 0, 3)
    else
        title:SetPoint("LEFT", typeDD, "LEFT", 22, 0)
    end
    if typeDD.SetupMenu then
        typeDD:SetupMenu(function(_, root)
            root:CreateTitle("Kick Tally")
            root:CreateButton("Post to the group", function() if ns.Report then ns.Report(db.mode) end end)
            root:CreateButton("Reset all data", function() if ns.AskReset then ns.AskReset() end end)
            root:CreateButton("Test", function() if ns.SetTest then ns.SetTest(not testMode) end end)
        end)
    end
else
    title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -9)
end
title:SetText("Kicks")

-- minimise, like the meter's red button
local mini = CreateFrame("Button", nil, win)
mini:SetSize(18, 19)
mini:SetPoint("TOPRIGHT", -3, -5)
local function MiniArt()
    local n = mini:GetNormalTexture() or mini:CreateTexture(nil, "ARTWORK")
    local p = mini:GetPushedTexture() or mini:CreateTexture(nil, "ARTWORK")
    local collapsed = db and db.collapsed
    if not Atlas(n, collapsed and "ui-questtrackerbutton-expand-all" or "ui-questtrackerbutton-collapse-all", 0.6, 0.1, 0.1, 1) then
        n:SetAllPoints()
    end
    Atlas(p, collapsed and "ui-questtrackerbutton-expand-all-pressed" or "ui-questtrackerbutton-collapse-all-pressed", 0.4, 0.05, 0.05, 1)
    mini:SetNormalTexture(n)
    mini:SetPushedTexture(p)
end
do
    local h = mini:CreateTexture(nil, "HIGHLIGHT")
    h:SetAllPoints()
    Atlas(h, "ui-questtrackerbutton-red-highlight", 1, 1, 1, 0.2)
    if h.SetBlendMode then h:SetBlendMode("ADD") end
end

-- settings, like the meter's gear
local gear = CreateFrame("Button", nil, win)
gear:SetSize(27, 27)
gear:SetPoint("RIGHT", mini, "LEFT", -2, -2)
do
    local n, p, h = gear:CreateTexture(nil, "ARTWORK"), gear:CreateTexture(nil, "ARTWORK"), gear:CreateTexture(nil, "HIGHLIGHT")
    n:SetAllPoints(); p:SetAllPoints(); h:SetAllPoints()
    Atlas(n, "common-dropdown-a-button-settings-shadowless", 0.5, 0.4, 0.1, 1)
    Atlas(p, "common-dropdown-a-button-settings-pressed-shadowless", 0.4, 0.3, 0.1, 1)
    Atlas(h, "common-dropdown-a-button-settings-hover-shadowless", 1, 1, 1, 0.15)
    gear:SetNormalTexture(n); gear:SetPushedTexture(p)
end

-- current fight or overall, like the meter's C / O button
local session = CreateFrame("Button", nil, win)
session:SetSize(24, 20)
session:SetPoint("RIGHT", gear, "LEFT", -2, 3)
do
    local okS, dd = pcall(CreateFrame, "DropdownButton", nil, win, "WowStyle2DropdownTemplate")
    if okS and dd then
        session:Hide()
        session = dd
        session:SetSize(24, 18)
        session:SetPoint("RIGHT", gear, "LEFT", -2, 3)
        if type(session.Text) == "table" then session.Text:Hide() end
    else
        local bg = session:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.5)
    end
    session.label = session:CreateFontString(nil, "OVERLAY", "GameFontNormalMed1")
    session.label:SetAllPoints()
    session.label:SetJustifyH("CENTER")
end

local rows = {}
local function Row(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Button", nil, win)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetPoint("LEFT")
    -- the interrupt on cooldown, over the class icon, with seconds left
    r.cd = r:CreateTexture(nil, "OVERLAY")
    r.cd:SetAllPoints(r.icon)
    r.cd:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.cd:Hide()
    r.cdShade = r:CreateTexture(nil, "OVERLAY", nil, 1)
    r.cdShade:SetAllPoints(r.icon)
    r.cdShade:SetColorTexture(0, 0, 0, 0.55)
    r.cdShade:Hide()
    r.cdText = r:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    r.cdText:SetPoint("CENTER", r.icon, "CENTER", 0, 0)
    r.cdText:Hide()
    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetPoint("LEFT", r.icon, "RIGHT", 0, 0)
    r.bar:SetPoint("TOP", 0, -1)
    r.bar:SetPoint("BOTTOMRIGHT", -4, 1)
    local tex = r.bar:CreateTexture(nil, "ARTWORK")
    if not Atlas(tex, "UI-HUD-CoolDownManager-Bar", 1, 1, 1, 1) then tex:SetColorTexture(1, 1, 1, 1) end
    r.bar:SetStatusBarTexture(tex)
    r.bar.tex = tex
    local bg = r.bar:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", -2, 2)
    bg:SetPoint("BOTTOMRIGHT", 2, -2)
    Atlas(bg, "ui-damagemeters-bar-shadowbg", 0, 0, 0, 0.5)
    local edge = r.bar:CreateTexture(nil, "OVERLAY")
    edge:SetPoint("TOPLEFT", -2, 2)
    edge:SetPoint("BOTTOMRIGHT", 2, -2)
    if not Atlas(edge, "ui-damagemeters-bar-shadowedge", 0, 0, 0, 0) then edge:Hide() end
    r.value = r.bar:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    r.value:SetPoint("RIGHT", -3, 0)
    r.value:SetJustifyH("RIGHT")
    r.name = r.bar:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    r.name:SetPoint("LEFT", 2, 0)
    r.name:SetPoint("RIGHT", r.value, "LEFT", -25, 0)
    r.name:SetJustifyH("LEFT")
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end
    r:SetScript("OnEnter", function(self)
        if ns.GripFade then ns.GripFade() end
        if not self.who or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(self.who)
        GameTooltip:AddLine(("%d this fight, %d in total"):format(fight[self.who] or 0, db.total[self.who] or 0), 1, 1, 1)
        local cd = cooldowns[self.who]
        if cd and cd.dur > 0 then
            local left = cd.start + cd.dur - GetTime()
            GameTooltip:AddLine(((SpellName(cd.id) or "Interrupt") .. (left > 0 and (" ready in %ds"):format(math.ceil(left)) or " ready")),
                left > 0 and 1 or 0.4, left > 0 and 0.6 or 1, 0.4)
        end
        if synced[self.who] then GameTooltip:AddLine("Runs Kick Tally: their kicks are sent to you", 0.6, 0.6, 0.6) end
        local list = recent[self.who]
        if list and #list > 0 then
            GameTooltip:AddLine(" ")
            for k = #list, math.max(1, #list - 5), -1 do GameTooltip:AddLine(list[k], 0.8, 0.8, 0.8) end
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    rows[i] = r
    return r
end

local empty = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
empty:SetPoint("TOP", 0, -HEADER - 6)
empty:SetText("No kicks yet")

local function PlaceWindow()
    win:ClearAllPoints()
    local p = db.pos
    if p then
        win:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        win:SetPoint("RIGHT", UIParent, "RIGHT", -240, 60)
    end
end

local function ClassIcon(tex, class)
    if class and GetClassAtlas then
        local ok, atlas = pcall(GetClassAtlas, class)
        if ok and atlas and tex.SetAtlas then
            local ok2, res = pcall(tex.SetAtlas, tex, atlas)
            if ok2 and res ~= false then tex:SetTexCoord(0, 1, 0, 1) return end
        end
    end
    local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if coords then
        tex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        tex:SetTexCoord(unpack(coords))
    else
        tex:SetTexture("Interface\\Icons\\Ability_Kick")
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

local sample = { { "Miff", 3, 41, "WARRIOR" }, { "Grunk", 2, 17, "ROGUE" }, { "Sally", 1, 9, "SHAMAN" }, { "Zaxx", 0, 4, "MAGE" } }

local function WindowWanted()
    if testMode then return true end
    if not db.showWindow then return false end
    return not db.groupOnly or InGroup()
end

local function SpellIcon(id)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, id)
        if ok and not IsSecret(tex) and tex then return tex end
    end
    return "Interface\\Icons\\Ability_Kick"
end

local function UpdateCooldowns()
    local now = GetTime()
    for _, r in ipairs(rows) do
        local cd = r.who and db.cooldowns and cooldowns[r.who]
        local left = cd and cd.dur > 0 and (cd.start + cd.dur - now) or 0
        if testMode and r.who == "Grunk" then left, cd = 6, { id = 1766 } end
        if left > 0 then
            r.cd:SetTexture(SpellIcon(cd.id))
            r.cdText:SetText(math.ceil(left))
            r.cd:Show(); r.cdShade:Show(); r.cdText:Show()
        else
            r.cd:Hide(); r.cdShade:Hide(); r.cdText:Hide()
        end
    end
end
ns.UpdateCooldowns = UpdateCooldowns

local function Layout()
    if not db then return end
    if not WindowWanted() then win:Hide() return end
    if not sizing then
        win:SetWidth(db.width)
        win:SetHeight(db.collapsed and HEADER or db.height)
    end
    MiniArt()
    session.label:SetText(db.mode == "total" and "O" or "C")
    title:SetText(db.mode == "total" and "Kicks (overall)" or "Kicks")

    local list = {}
    if testMode then
        for _, s in ipairs(sample) do
            list[#list + 1] = { name = s[1], n = db.mode == "total" and s[3] or s[2], class = s[4] }
        end
    else
        local counts = db.mode == "total" and db.total or fight
        local seen = {}
        local function add(name)
            if name and not seen[name] then
                seen[name] = true
                list[#list + 1] = { name = name, n = counts[name] or 0, class = db.classes[name] }
            end
        end
        for _, name in pairs(roster) do add(name) end
        for name in pairs(counts) do add(name) end
    end
    table.sort(list, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.name < b.name
    end)
    local sum, top = 0, 0
    for _, e in ipairs(list) do sum = sum + e.n; if e.n > top then top = e.n end end

    -- as many rows as fit the window; the mouse wheel scrolls the rest
    local bh = db.barHeight
    local fit = math.max(1, math.floor((db.height - HEADER - 2) / (bh + BAR_SPACING)))
    scroll = math.max(0, math.min(scroll, #list - fit))
    local n = db.collapsed and 0 or math.min(#list - scroll, fit)
    for i = 1, math.max(n, #rows) do
        local r = Row(i)
        local index = i + scroll
        local e = list[index]
        r:ClearAllPoints()
        r:SetHeight(bh)
        r:SetPoint("TOPLEFT", 5, -HEADER + 2 - (i - 1) * (bh + BAR_SPACING))
        r:SetPoint("RIGHT", -1, 0)
        r.icon:SetSize(bh, bh)
        if e and i <= n then
            local c = e.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class]
            r.bar.tex:SetVertexColor(c and c.r or 0.6, c and c.g or 0.6, c and c.b or 0.6)
            r.bar:SetMinMaxValues(0, math.max(top, 1))
            r.bar:SetValue(e.n)
            r.name:SetText(index .. ". " .. e.name)
            r.value:SetText(sum > 0 and ("%d (%d%%)"):format(e.n, math.floor(e.n / sum * 100 + 0.5)) or "0")
            ClassIcon(r.icon, e.class)
            r.who = e.name
            r:Show()
        else
            r.who = nil
            r:Hide()
        end
    end
    win.listSize, win.fit = #list, fit
    body:SetShown(not db.collapsed)
    body:SetAlpha((db.bgOpacity or 60) / 100)
    empty:SetShown(not db.collapsed and n == 0)
    if win.grip then win.grip:SetShown(not db.locked and not db.collapsed) end
    win:SetAlpha((db.opacity or 100) / 100)
    UpdateCooldowns()
    win:Show()
end
ns.Layout = Layout

local function ResetCounts()
    wipe(fight); wipe(db.total); wipe(recent)
    scroll = 0
    Layout()
end
ns.ResetCounts = ResetCounts

-- clearing everything asks first, like the damage meter
local function AskReset()
    if StaticPopupDialogs and StaticPopup_Show then
        StaticPopupDialogs.KICKTALLY_RESET = StaticPopupDialogs.KICKTALLY_RESET or {
            text = "Clear all Kick Tally data?\nThis fight's and the overall kick counts are deleted.",
            button1 = YES or "Yes",
            button2 = NO or "No",
            OnAccept = function() ResetCounts(); Print("all kick data cleared.") end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("KICKTALLY_RESET")
    else
        ResetCounts()
        Print("all kick data cleared.")
    end
end
ns.AskReset = AskReset

mini:SetScript("OnClick", function() db.collapsed = not db.collapsed; Layout() end)

-- resizing: the meter's corner handle, shown while the mouse is over the window
if win.SetResizable then win:SetResizable(true) end
if win.SetResizeBounds then
    pcall(win.SetResizeBounds, win, 160, HEADER + 30, 600, 800)
elseif win.SetMinResize then
    win:SetMinResize(160, HEADER + 30); win:SetMaxResize(600, 800)
end
local grip = CreateFrame("Button", nil, win)
grip:SetFrameLevel((win:GetFrameLevel() or 1) + 10)
do
    local n, h, p = grip:CreateTexture(nil, "OVERLAY"), grip:CreateTexture(nil, "HIGHLIGHT"), grip:CreateTexture(nil, "OVERLAY")
    n:SetAllPoints(); h:SetAllPoints(); p:SetAllPoints()
    if Atlas(n, "damagemeters-scalehandle", 0.8, 0.6, 0.2, 0.6) then
        grip:SetSize(60, 60)               -- the meter's own size and spot
        grip:SetPoint("BOTTOMRIGHT", 9, -8)
    else
        grip:SetSize(16, 16)
        grip:SetPoint("BOTTOMRIGHT", -2, 2)
        n:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    end
    if not Atlas(h, "damagemeters-scalehandle-hover", 1, 1, 1, 0.2) then h:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight") end
    if not Atlas(p, "damagemeters-scalehandle-pressed", 0.6, 0.4, 0.1, 0.6) then p:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down") end
    grip:SetNormalTexture(n); grip:SetHighlightTexture(h); grip:SetPushedTexture(p)
end
grip:SetAlpha(0)
win.grip = grip

local function SavePos()
    local point, _, rel, x, y = win:GetPoint()
    if point then db.pos = { point, rel, x, y } end
end
grip:SetScript("OnMouseDown", function(_, button)
    if button ~= "LeftButton" or db.locked or db.collapsed then return end
    sizing = true
    win:StartSizing("BOTTOMRIGHT")
end)
grip:SetScript("OnMouseUp", function()
    if not sizing then return end
    win:StopMovingOrSizing()
    sizing = false
    db.width = math.floor(win:GetWidth() + 0.5)
    db.height = math.floor(win:GetHeight() + 0.5)
    SavePos()
    Layout()
    if ns.RefreshOptions then ns.RefreshOptions() end
end)
win:SetScript("OnSizeChanged", function()
    if sizing then
        db.width, db.height = win:GetWidth(), win:GetHeight()
        Layout()
    end
end)

-- show the corner handle while the mouse is over the window, like the meter
local function GripFade()
    if sizing then return end
    local over = win:IsMouseOver()
    grip:SetAlpha(over and 1 or 0)
    if over then C_Timer.After(0.3, GripFade) end
end
win:SetScript("OnEnter", GripFade)
ns.GripFade = GripFade

win:EnableMouseWheel(true)
win:SetScript("OnMouseWheel", function(_, delta)
    if not win.listSize or not win.fit or win.listSize <= win.fit then return end
    scroll = math.max(0, math.min(scroll - delta, win.listSize - win.fit))
    Layout()
end)

local function SetMode(mode) db.mode = mode; Layout() end
if session.SetupMenu then
    session:SetupMenu(function(_, root)
        root:CreateRadio("Current fight", function() return db.mode ~= "total" end, function() SetMode("fight") end)
        root:CreateRadio("Overall", function() return db.mode == "total" end, function() SetMode("total") end)
        if root.CreateDivider then root:CreateDivider() end
        root:CreateButton("Reset all data", AskReset)
    end)
    if session.SetSelectionText then pcall(session.SetSelectionText, session, function() return "" end) end
else
    session:SetScript("OnClick", function() SetMode(db.mode == "total" and "fight" or "total") end)
end

gear:SetScript("OnClick", function(self)
    local opened = OpenMenu(self, function(root)
        root:CreateTitle("Kick Tally")
        root:CreateCheckbox("Lock window", function() return db.locked end, function() db.locked = not db.locked end)
        root:CreateCheckbox("Only in a party or raid", function() return db.groupOnly end,
            function() db.groupOnly = not db.groupOnly; Layout() end)
        root:CreateButton("Hide window", function()
            db.showWindow = false; Layout()
            Print("window hidden. /ktally show, or the settings page, brings it back.")
        end)
        root:CreateButton("Reset all data", AskReset)
        root:CreateButton("Settings", function() if ns.OpenOptions then ns.OpenOptions() end end)
    end)
    if not opened and ns.OpenOptions then ns.OpenOptions() end
end)

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

-- {rt8} shows as a skull in chat; in our own chat lines it needs the texture itself
local function Icons(msg)
    return (msg:gsub("{rt(%d)}", "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%1:0|t"))
end

local function OwnKick(e, cast)
    local target = e.target or (cast and cast.target)
    local values = {
        target = target or (e.mark and ("{rt" .. e.mark .. "}")),
        spell = e.spell,
        ability = cast and SpellName(cast.id) or "Kick",
        count = fight[playerName],
    }
    if db.sound and PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.RAID_WARNING or 8959) end
    local msg = Fill(db.message, values)
    local sent, why = false, "announcing is off"
    local vague = not values.target and not values.spell
    if db.announce and msg ~= "" then
        if vague and not db.announceVague then
            why = "the game hid the enemy and its spell"
        else
            sent, why = Post(msg)
        end
    end
    if not sent and db.printLocal then
        Print(Icons(msg ~= "" and msg or "you interrupted a cast."))
    end
    Debug("own kick: " .. msg .. (sent and " (posted)" or (" (not posted: " .. tostring(why) .. ")")))
end

local SendSyncRef, CleanRef -- set once the sync code below exists
local function Credit(who, e, cast)
    fight[who] = (fight[who] or 0) + 1
    db.total[who] = (db.total[who] or 0) + 1
    local what = e.target or "an enemy"
    if e.spell then what = what .. " (" .. e.spell .. ")" end
    recent[who] = recent[who] or {}
    table.insert(recent[who], what)
    if #recent[who] > 10 then table.remove(recent[who], 1) end
    Debug(("kick credited to %s%s"):format(who, cast and cast.id and (" with " .. tostring(SpellName(cast.id))) or " (spell hidden)"))
    if who == playerName then
        OwnKick(e, cast)
        if SendSyncRef then SendSyncRef(("K:%d:%s:%s"):format(cast and cast.id or 0, CleanRef(e.target or ""), CleanRef(e.spell or ""))) end
    end
    Layout()
end

---------------------------------------------------------------------------
-- Cooldowns and syncing with other Kick Tally users
---------------------------------------------------------------------------
-- Other players' spells are hidden in combat, so a party member's kick is normally
-- matched by timing. When they run Kick Tally too, their copy sends each kick it is sure
-- of (their own) and yours trusts that instead. The game blocks addon messages during
-- boss fights, M+ and PvP, so there everyone falls back to timing.
local PREFIX = "KickTally"
local lastHello = 0

local function SyncChannel()
    if not InGroup() then return nil end
    if IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE or 2) then return "INSTANCE_CHAT" end
    if IsInRaid and IsInRaid() then return "RAID" end
    return "PARTY"
end

local function SyncOn()
    return db.sync and InGroup() and not ChatLocked()
end

local function SendSync(msg)
    if not SyncOn() then return end
    local ch = SyncChannel()
    local f = C_ChatInfo and C_ChatInfo.SendAddonMessage
    if ch and f then pcall(f, PREFIX, msg, ch) end
end

local function Hello(force)
    if not force and GetTime() - lastHello < 10 then return end
    lastHello = GetTime()
    SendSync("H")
end

-- "Name-Realm" from the message -> the name in your group list
local function RosterName(sender)
    if type(sender) ~= "string" then return nil end
    local short = Ambiguate and Ambiguate(sender, "none") or sender:match("^[^%-]+")
    for _, n in pairs(roster) do
        if n == sender or n == short then return n end
    end
    for _, n in pairs(roster) do
        if short:find(n, 1, true) == 1 or n:find(short, 1, true) == 1 then return n end
    end
end

local function IsSynced(name)
    return name and synced[name] and db.sync and not ChatLocked()
end

local function StartCooldown(name, id, dur)
    if not name or not id then return end
    local info = KICKS[id]
    if not info or info.kind ~= "kick" then return end
    cooldowns[name] = { id = id, start = GetTime(), dur = dur or db.cds[id] or info.cd or 0 }
end

-- after your own kick, read its real cooldown when the game shares it
local function ReadOwnCooldown(id)
    if not (C_Spell and C_Spell.GetSpellCooldown) then return end
    local ok, cd = pcall(C_Spell.GetSpellCooldown, id)
    if not ok or type(cd) ~= "table" or IsSecret(cd.duration) or IsSecret(cd.startTime) then return end
    if type(cd.duration) == "number" and cd.duration > 1.6 then
        db.cds[id] = cd.duration
        local mine = cooldowns[playerName]
        if mine and mine.id == id then mine.start, mine.dur = cd.startTime, cd.duration end
    end
end

local function Clean(s)
    return (tostring(s or ""):gsub("[:\n]", " "))
end

local function OnSync(text, sender)
    local who = RosterName(sender)
    if not who or who == playerName then return end
    local first = synced[who] == nil
    synced[who] = GetTime()
    local parts = {}
    for piece in (text .. ":"):gmatch("([^:]*):") do parts[#parts + 1] = piece end
    local kind, a, b, c, d = parts[1], parts[2], parts[3], parts[4], parts[5]
    if kind == "H" then
        if first then Hello(true) end
    elseif kind == "C" then
        -- their kick went out: show its cooldown on their row
        StartCooldown(who, tonumber(a), tonumber(b))
        Layout()
    elseif kind == "K" then
        if who ~= playerName and not db.trackGroup then return end
        local e = { t = GetTime(), target = (c ~= "" and c or nil), spell = (d ~= "" and d or nil) }
        Credit(who, e, { id = tonumber(a) })
    end
end
ns.OnSync = OnSync
SendSyncRef, CleanRef = SendSync, Clean
ns.Synced = function() return synced end
ns.Cooldowns = function() return cooldowns end

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
    -- they run Kick Tally too: their own copy sends this kick, so don't count it twice
    if who ~= playerName and IsSynced(who) then
        Debug(who .. " runs Kick Tally; waiting for their copy to send it")
        return
    end
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
    if info and info.kind == "kick" then
        StartCooldown(name, id)
        if own then
            C_Timer.After(0.1, function() ReadOwnCooldown(id); Layout() end)
            SendSync(("C:%d:%s"):format(id, tostring(cooldowns[name] and cooldowns[name].dur or 0)))
        end
        Layout()
    end
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
    local target = NameOf(unit) or unitNames[unit]
    local mark = MarkOf(unit)
    if by == "" then by = nil end

    -- the same interrupt seen on two units (your target and its nameplate)
    if lastEvent and now - lastEvent.t < 0.08 and lastEvent.by == by then
        lastEvent.spell = lastEvent.spell or spell
        lastEvent.target = lastEvent.target or target
        lastEvent.mark = lastEvent.mark or mark
        if not channel then lastEvent.channel = false end
        return
    end
    local e = { t = now, spell = spell, target = target, mark = mark, by = by, channel = channel }
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

ns.Report = Report

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
        if db.message == "Interrupted {target}'s {spell}!" then db.message = defaults.message end
        if db.show ~= nil then -- 1.0.0 test builds: show = group / always / never
            db.showWindow = db.show ~= "never"
            db.groupOnly = db.show == "group"
            db.show = nil
        end
        UpdateRoster()
        PlaceWindow()
        if ns.StartVersionCheck then ns.StartVersionCheck(db, "Kick Tally") end
        ns.BuildOptions()

        SafeRegister("PLAYER_ENTERING_WORLD")
        SafeRegister("GROUP_ROSTER_UPDATE")
        SafeRegister("UNIT_PET")
        SafeRegister("PLAYER_TARGET_CHANGED")
        SafeRegister("PLAYER_FOCUS_CHANGED")
        SafeRegister("NAME_PLATE_UNIT_ADDED")
        SafeRegister("NAME_PLATE_UNIT_REMOVED")
        SafeRegister("PLAYER_REGEN_DISABLED")
        SafeRegister("ENCOUNTER_START")
        SafeRegister("ENCOUNTER_END")
        SafeRegister("UNIT_SPELLCAST_SENT", "player")
        SafeRegister("UNIT_SPELLCAST_SUCCEEDED")
        SafeRegister("UNIT_SPELLCAST_INTERRUPTED")
        SafeRegister("UNIT_SPELLCAST_CHANNEL_STOP")
        SafeRegister("CHAT_MSG_ADDON")
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
        end
        -- count down the interrupt cooldowns on the rows
        if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(0.25, UpdateCooldowns) end
        Layout()
        return
    end

    if event == "CHAT_MSG_ADDON" then
        if a1 == PREFIX and type(a2) == "string" and not IsSecret(a2) then OnSync(a2, a4) end
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
        if not inEncounter then wipe(fight); wipe(recent) end
        UpdateRoster()
        Layout()
    elseif event == "ENCOUNTER_START" then
        inEncounter = true
        wipe(fight); wipe(recent)
        Layout()
    elseif event == "ENCOUNTER_END" then
        inEncounter = false
        C_Timer.After(3, function() Hello(true) end)
        C_Timer.After(2, function() ReportAfterBoss(0) end)
    elseif event == "PLAYER_TARGET_CHANGED" then
        unitNames.target = NameOf("target")
    elseif event == "PLAYER_FOCUS_CHANGED" then
        unitNames.focus = NameOf("focus")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if type(a1) == "string" and not IsSecret(a1) then unitNames[a1] = NameOf(a1) end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if type(a1) == "string" and not IsSecret(a1) then unitNames[a1] = nil end
    elseif event == "UNIT_PET" then
        if a1 == "player" then petGUID = GUIDOf("pet"); if petGUID and playerName then guidName[petGUID] = playerName end
        else UpdateRoster() end
    else -- PLAYER_ENTERING_WORLD, GROUP_ROSTER_UPDATE
        UpdateRoster()
        -- forget Kick Tally users who have left the group
        local here = {}
        for _, n in pairs(roster) do here[n] = true end
        for n in pairs(synced) do if not here[n] then synced[n] = nil end end
        if InGroup() and C_Timer then C_Timer.After(2, function() Hello() end) end
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
            { "1.4.0", "Group members who run Kick Tally send you their kicks, so their counts are exact",
                       "Interrupt cooldowns over the class icons: yours, and theirs when they run it" },
            { "1.3.2", "The chat command is now /ktally (/kicks and /kicktally still work). /kick is the game's own" },
            { "1.3.1", "Reset all data: in the C / O menu and the gear menu on the window, asks first" },
            { "1.3.0", "Kick posts name the enemy more often: names read before the pull, raid markers",
                       "When the game hides everything it says which ability, or isn't posted at all",
                       "New message: \"Pummel interrupted Scorching Elemental's Fireball!\"" },
            { "1.2.0", "Resize the window by dragging its bottom-right corner",
                       "Scroll with the mouse wheel when more players than fit",
                       "Thinner bars and a see-through background, like the meter; both adjustable" },
            { "1.1.0", "The window now looks like the game's damage meter",
                       "Current fight or overall (C / O), settings and minimise buttons on its title bar",
                       "Show or hide the window, or only show it in a party or raid" },
            { "1.0.0", "First version: announces your successful kicks",
                       "Counts your party and raid's kicks, this fight and in total",
                       "Tells you when a kick didn't interrupt anything" },
        },
        icon = "Interface\\Icons\\Ability_Kick",
        about = "Announces your kicks and tallies the group's",
        credit = "Created by Miff, supported by Claude",
        slash = "/ktally",
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
              preview = function(text) return Fill(text, { target = "Defias Pillager", spell = "Fireball", ability = "Pummel", count = 3 })
                  .. "  |cff999999or, with the name hidden in a dungeon:|r " .. Icons(Fill(text, { target = "{rt8}", ability = "Pummel", count = 3 })) end },
            { type = "check", key = "announceVague", label = "Post even when the game hides the enemy and its spell (\"Pummel interrupted a cast!\")" },
            { type = "check", key = "stuns", label = "Count stuns and fears that stop a cast (Hammer of Justice, Kidney Shot...)" },
            { type = "check", key = "printLocal", label = "Show your kick in your own chat window when it isn't posted" },
            { type = "check", key = "missed", label = "Tell me when my kick didn't interrupt anything" },
            { type = "check", key = "sound", label = "Play a sound on a kick" },
            { type = "header", label = "Tally window" },
            { type = "check", key = "showWindow", label = "Show the tally window" },
            { type = "check", key = "groupOnly", label = "Only while I'm in a party or raid" },
            { type = "check", key = "trackGroup", label = "Count party and raid members' kicks too" },
            { type = "check", key = "sync", label = "Swap kicks with group members who run Kick Tally (more accurate counts)" },
            { type = "check", key = "cooldowns", label = "Show interrupt cooldowns over the class icons" },
            { type = "range", key = "width", label = "Width (or drag the bottom-right corner)", min = 160, max = 600, step = 10 },
            { type = "range", key = "height", label = "Height", min = 60, max = 800, step = 10 },
            { type = "range", key = "barHeight", label = "Bar height", min = 12, max = 32, step = 1 },
            { type = "range", key = "bgOpacity", label = "Background opacity", min = 0, max = 100, step = 10, suffix = "%" },
            { type = "range", key = "opacity", label = "Window opacity", min = 30, max = 100, step = 10, suffix = "%" },
            { type = "check", key = "locked", label = "Lock the window (otherwise drag its title bar to move it)" },
            { type = "button", label = "Reset position and size", func = function()
                db.pos = nil; db.width, db.height = defaults.width, defaults.height; PlaceWindow(); Layout() end },
            { type = "button", label = "Reset all data", func = function() AskReset() end },
            { type = "button", label = "Test",
              dynamicLabel = function() return testMode and "Stop the test" or "Test" end,
              func = function() SetTest(not testMode) end },
            { type = "check", key = "reportAfterBoss", label = "After a boss fight, post that fight's kicks to the group" },
            { type = "header", label = "How it works on WoW Forever" },
            { type = "info", height = 124, lines = function()
                return "|cff999999Your own kicks are exact: Kick Tally sees you cast Pummel and the enemy's cast being interrupted. "
                    .. "In combat the game hides which spells other players cast, so a party member's kick is counted when their cast "
                    .. "and an enemy's interrupted cast happen at the same moment. Keep enemy nameplates on so it sees every enemy. "
                    .. "Group members who run Kick Tally send their own kicks to you instead, which is exact. "
                    .. "Addons can't post in chat or send to each other during boss fights, so there it goes back to timing and your kicks show in your own chat window.|r" end },
        },
    })
end

function KickTally_OnAddonCompartmentClick()
    if ns.OpenOptions then ns.OpenOptions() end
end

-- /ktally, not /kick: /kick is the game's own command for removing someone from your group
SLASH_KICKTALLY1 = "/ktally"
SLASH_KICKTALLY2 = "/kicktally"
SLASH_KICKTALLY3 = "/kicks"
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
        db.showWindow = cmd == "show"
        Layout()
        if cmd == "show" then
            Print(db.groupOnly and not InGroup() and "window on. It shows when you're in a party or raid (turn that off in /ktally)."
                or "window shown.")
        else
            Print("window hidden. /ktally show to bring it back.")
        end
    elseif cmd == "reset" then
        if rest == "position" then
            db.pos = nil; db.width, db.height = defaults.width, defaults.height; PlaceWindow(); Layout()
            Print("window position and size reset.")
        else
            ResetCounts(); Print("all kick data cleared.")
        end
    elseif cmd == "report" then
        Report(rest == "total" and "total" or "fight")
    elseif cmd == "debug" then
        debugMode = not debugMode
        Print(debugMode and "debug on: casts and interrupts are printed. /ktally debug again to stop." or "debug off.")
        if debugMode then
            Print(("now: in a group %s, chat locked %s, announcing to %s"):format(tostring(InGroup()),
                tostring(ChatLocked()), tostring(ChatType() or "your chat window only")))
        end
    else
        Print("/ktally - settings")
        Print("/ktally test - sample window and message")
        Print("/ktally report [total] - post this fight's (or all) kicks to the group")
        Print("/ktally lock | unlock - lock or move the window")
        Print("/ktally show | hide - show or hide the window")
        Print("/ktally reset - clear all kick data (/ktally reset position for the window's position and size)")
        Print("/ktally debug - print what it sees, to check it on Forever")
    end
end

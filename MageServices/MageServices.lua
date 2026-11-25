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

local defaults = {
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
    hideLow = false,      -- hide requests you can't help with instead of dimming them
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
    noPayMsg  = "Trade with {name} completed, but no payment was included.",
    cancelMsg = "Trade with {name} was cancelled. No payment received.",
    failMsg   = "Trade with {name} failed ({reason}). No payment received.",
    maxRows = 6,
    custom = {},          -- your own phrases, e.g. "lf summon"
    excludes = {},        -- phrases that should never match
    portMsg  = "Hi {name}, I can port you to {dest}. Sending you an invite now.",
    waterMsg = "Hi {name}, I've got water and food for you. Sending you an invite now.",
    customMsg = "Hi {name}, sending you an invite now.",
    point = { "CENTER", "CENTER", 300, 100 },
}

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

local function ShortName(full)
    if Ambiguate then
        local ok, n = pcall(Ambiguate, full, "none")
        if ok and n then return n end
    end
    return (full:match("^[^%-]+")) or full
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

function ns.MyZone()
    if db.zone and db.zone ~= "auto" then return db.zone end
    local z = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
    if IsSecret(z) then return "" end
    return z
end

local function SameZone(a, b)
    if not a or not b or a == "" or b == "" then return false end
    if a:lower() == b:lower() then return true end
    return ns.TextMatches(a, b) or ns.TextMatches(b, a)
end

-- Returns priority and a short reason shown on the row.
local function Rank(req)
    local info, here = req.info, ns.MyZone()

    if info.kind == "port" and info.dest and SameZone(info.dest, here) then
        return LOW, "wants " .. info.dest .. ", you're already there"
    end

    if req.whoZone then
        if SameZone(req.whoZone, here) then return HIGH, "in your zone (/who)" end
        return LOW, "they're in " .. req.whoZone .. " (/who)"
    end
    if req.whoPending then return NORMAL, "looking up..." end
    if req.whoFailed then return NORMAL, "no /who reply, click ? again" end

    local origin = info.origin or info.originText
    if origin then
        if SameZone(origin, here) then return HIGH, "in your zone" end
        return LOW, "they're in " .. origin
    end

    if req.source == "say" then return HIGH, "near you" end
    if req.source == "local" then
        if SameZone(req.zoneAtReceive, here) then return HIGH, "in your zone" end
        return LOW, "they're in " .. (req.zoneAtReceive or "another zone")
    end

    return NORMAL, nil
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
local function Invite(name)
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(name)
    elseif InviteUnit then
        InviteUnit(name)
    end
end

local function FillTemplate(template, req)
    local dest = (req.info and req.info.dest) or "your city"
    return (template:gsub("{name}", req.short):gsub("{dest}", dest))
end

local function OpenWhisper(req)
    local template = db.customMsg
    if req.info.kind == "port" then template = db.portMsg
    elseif req.info.kind == "water" then template = db.waterMsg end
    local line = "/w " .. req.sender .. " " .. FillTemplate(template, req)
    if ChatFrameUtil and ChatFrameUtil.OpenChat then
        ChatFrameUtil.OpenChat(line)
    elseif ChatFrame_OpenChat then
        ChatFrame_OpenChat(line)
    end
end

---------------------------------------------------------------------------
-- Request window
---------------------------------------------------------------------------
local ROW_H, WIDTH = 28, 440

local win = CreateFrame("Frame", "MageServicesFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
win:SetSize(WIDTH, 40)
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
if win.SetBackdrop then
    win:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    win:SetBackdropColor(0.05, 0.05, 0.1, 0.92)
    win:SetBackdropBorderColor(0.41, 0.8, 0.94, 1)
end
win:Hide()
ns.win = win

win.title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
win.title:SetPoint("TOPLEFT", 10, -8)
win.title:SetTextColor(0.41, 0.8, 0.94)

win.footer = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
win.footer:SetPoint("BOTTOMLEFT", 10, 7)
win.footer:SetJustifyH("LEFT")

win.close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
win.close:SetSize(24, 24)
win.close:SetPoint("TOPRIGHT", 0, 0)

win.clear = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
win.clear:SetSize(56, 18)
win.clear:SetPoint("RIGHT", win.close, "LEFT", -2, 0)
win.clear:SetText("Clear")

local rows = {}
local Refresh -- forward

local function Remove(req)
    for i, r in ipairs(requests) do
        if r == req then table.remove(requests, i) break end
    end
    Refresh()
end

local function MakeRow(i)
    local row = CreateFrame("Frame", nil, win)
    row:SetSize(WIDTH - 16, ROW_H)
    row:SetPoint("TOPLEFT", 8, -28 - (i - 1) * ROW_H)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 0.82, 0, 0.14)

    row.sel = row:CreateTexture(nil, "BORDER")
    row.sel:SetAllPoints()
    row.sel:SetColorTexture(0.41, 0.8, 0.94, 0.22)
    row.sel:Hide()

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("LEFT", 0, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.dismiss = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.dismiss:SetSize(22, 20)
    row.dismiss:SetPoint("RIGHT", 0, 0)
    row.dismiss:SetText("x")

    row.whisper = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.whisper:SetSize(62, 20)
    row.whisper:SetPoint("RIGHT", row.dismiss, "LEFT", -2, 0)
    row.whisper:SetText("Whisper")

    row.invite = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.invite:SetSize(56, 20)
    row.invite:SetPoint("RIGHT", row.whisper, "LEFT", -2, 0)
    row.invite:SetText("Invite")

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.label:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, 0)
    row.where = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.where:SetSize(22, 20)
    row.where:SetPoint("RIGHT", row.invite, "LEFT", -2, 0)
    row.where:SetText("?")
    row.where:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Where are they?")
        GameTooltip:AddLine("Runs a /who on this player and re-ranks the request by their zone.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row.where:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row.label:SetPoint("RIGHT", row.where, "LEFT", -6, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 0)
    row.text:SetPoint("RIGHT", row.where, "LEFT", -6, 0)
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
    row.where:SetScript("OnClick", function() if row.req then ns.LookupZone(row.req) end end)
    row.whisper:SetScript("OnClick", function() if row.req then OpenWhisper(row.req) end end)
    row.dismiss:SetScript("OnClick", function() if row.req then Remove(row.req) end end)

    rows[i] = row
    return row
end

Refresh = function()
    if not db then return end
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
    if db.hideLow then
        visible = {}
        for _, r in ipairs(requests) do
            if r.priority > LOW then visible[#visible + 1] = r end
        end
    end

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
                    tag = "  |cff33ff33paid " .. ns.Money(req.paid) .. "|r"
                elseif req.priority == HIGH then
                    tag = "  |cff33ff33" .. (req.reason or "near you") .. "|r"
                elseif req.reason then
                    tag = "  |cff999999" .. req.reason .. "|r"
                end
                row.label:SetText(req.info.label .. tag .. "  |cffaaaaaa" .. req.short .. ", " .. ago .. "s|r")
                row.text:SetText(req.msg)
                row.bg:SetShown(req.priority == HIGH)
                row.sel:SetShown(req.selected and true or false)
                row:SetAlpha(req.priority == LOW and 0.45 or 1)
                row:Show()
            else
                row.req = nil
                row:Hide()
            end
        end
    end

    local extra = #visible - shown
    local where = ns.MyZone()
    win.title:SetText("Mage Services" .. (where ~= "" and ("  |cffaaaaaa" .. where .. (db.zone == "auto" and "" or " (picked)") .. "|r") or "")
        .. (extra > 0 and ("  (+" .. extra .. " more)") or ""))
    if ns.UpdateGlows then ns.UpdateGlows(visible) end
    if ns.UpdateCastButton then ns.UpdateCastButton(visible) end
    win.footer:SetText(ns.EarningsLine and ns.EarningsLine() or "")
    win:SetHeight(50 + shown * ROW_H)
    if shown == 0 then win:Hide() else win:Show() end
end

ns.Refresh = Refresh
win.clear:SetScript("OnClick", function() wipe(requests); Refresh() end)
win.close:SetScript("OnClick", function() win:Hide() end)

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

local function Alert(req)
    if db.sound then ns.PlayAlertSound() end
    if db.flash and FlashClientIcon then FlashClientIcon() end
    if ns.ScreenAlert then ns.ScreenAlert(req) end
end

local function AddRequest(sender, msg, info, source)
    -- same person again: refresh their entry instead of adding a second one
    for i, r in ipairs(requests) do
        if r.sender == sender then
            table.remove(requests, i)
            break
        end
    end
    local req = { sender = sender, short = ShortName(sender), msg = msg, info = info, time = GetTime(),
                  source = source, zoneAtReceive = ns.MyZone() }
    req.priority, req.reason = Rank(req)
    ns.customers[req.short] = { time = GetTime(), kind = info.kind, dest = info.dest }
    table.insert(requests, 1, req)
    if req.priority > LOW or db.alertLow then
        Alert(req)
        if db.autoInvite and not testMode and req.priority > LOW then Invite(sender) end
    end
    Refresh()
end

-- source: "say" (say/yell, so they're close), "local" (your zone's General or
-- LocalDefense channel), or "other" (trade, whispers, guild: could be anywhere)
function ns.HandleChat(msg, sender, source)
    if not db then return end
    if IsSecret(msg) or IsSecret(sender) then return end -- inside instances: unreadable
    if type(msg) ~= "string" or type(sender) ~= "string" or sender == "" then return end

    local me = UnitName("player")
    if ShortName(sender) == me then return end
    if UnitInParty and UnitInParty(ShortName(sender)) then return end

    local info = ns.Classify(msg, MatchOptions())
    if info then AddRequest(sender, msg, info, source or "other") end
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
        return "local"
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
    pendingWho = { req = req, name = req.short, time = GetTime() }
    ns.lastWhoName, ns.lastWhoTime = req.short, GetTime()
    req.whoPending, req.whoFailed = true, nil
    local ok = pcall(C_FriendList.SendWho, 'n-"' .. req.short .. '"')
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
        if ok and info and info.fullName and ShortName(info.fullName) == pendingWho.name then
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
    return ShortName(name), area
end

-- Hide our own lookup lines from chat so the lookup is quiet.
local function WhoChatFilter(_, _, msg)
    if not pendingWho and not ns.lastWhoTime then return false end
    if type(msg) ~= "string" or IsSecret(msg) then return false end
    local name = ParseWhoLine(msg)
    local recent = ns.lastWhoTime and GetTime() - ns.lastWhoTime < 6
    if (pendingWho and name == pendingWho.name) or (recent and name == ns.lastWhoName) then return true end
    if recent and msg:find("%d+ [Pp]layers? total") then return true end
    return false
end

local function OnSystemMessage(msg)
    if not pendingWho then return end
    local name, area = ParseWhoLine(msg)
    if name and name == pendingWho.name then
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
        if db and db[setting] then
            local source = SOURCE[event] or ChannelSource(arg4, arg9)
            ns.HandleChat(arg1, arg2, source)
        end

    elseif event == "WHO_LIST_UPDATE" then
        OnWhoList()

    elseif event == "CHAT_MSG_SYSTEM" then
        OnSystemMessage(arg1)

    elseif event == "ZONE_CHANGED_NEW_AREA" then
        Refresh()

    elseif event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        MageServicesDB = MageServicesDB or {}
        for k, v in pairs(defaults) do
            if MageServicesDB[k] == nil then
                MageServicesDB[k] = type(v) == "table" and { unpack(v) } or v
            end
        end
        db = MageServicesDB
        ns.db = db
        ns.InitEarnings()
        ApplyPosition()
        ns.BuildOptions()

    elseif event == "PLAYER_LOGIN" then
        for e in pairs(CHANNEL_EVENTS) do SafeRegister(e) end
        SafeRegister("ZONE_CHANGED_NEW_AREA")
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
        icon = "Interface\\Icons\\Spell_Arcane_PortalOrgrimmar",
        about = "Spots portal and water requests in chat",
        slash = "/ms",
        db = db,
        onChange = function() Refresh() end,
        controls = {
            { type = "header", label = "Look for" },
            { type = "check", key = "ports", label = "Portal requests" },
            { type = "check", key = "water", label = "Water and food requests" },
            { type = "check", key = "allFactions", label = "Other faction's cities too" },
            { type = "header", label = "Channels" },
            { type = "check", key = "chTrade", label = "Trade, General and other numbered channels" },
            { type = "check", key = "chSay", label = "Say and yell" },
            { type = "check", key = "chWhisper", label = "Whispers" },
            { type = "check", key = "chGuild", label = "Guild" },
            { type = "header", label = "Your location" },
            { type = "choice", key = "zone", label = "Where you are (Auto = current zone)", values = ns.ZoneChoices() },
            { type = "check", key = "hideLow", label = "Hide requests you can't help with (instead of dimming)" },
            { type = "check", key = "alertLow", label = "Alert for low-priority requests too" },
            { type = "header", label = "On screen" },
            { type = "check", key = "glowBar", label = "Glow the matching Portal / Conjure button" },
            { type = "range", key = "glowTime", label = "Glow for", min = 5, max = 60, step = 5, suffix = "s" },
            { type = "check", key = "screenMsg", label = "Show a message at the top of the screen" },
            { type = "check", key = "edgeFlash", label = "Flash the edges of the screen" },
            { type = "header", label = "Earnings (this character)" },
            { type = "info", lines = function() return ns.EarningsLines() end, height = 58 },
            { type = "header", label = "Payments" },
            { type = "choice", key = "receiptMode", label = "Payment messages (Auto / Prefill / Off)", values = { "auto", "prefill", "off" } },
            { type = "check", key = "receiptAll", label = "Post for every trade, not just customers" },
            { type = "button", label = "Test a payment message", func = function() ns.TestTrade("complete") end },
            { type = "header", label = "When someone asks" },
            { type = "check", key = "sound", label = "Play a sound" },
            { type = "dropdown", key = "soundKey", label = "Sound", options = ns.SoundOptions,
              onSelect = function(v) ns.PlayAlertSound(v) end, preview = function(v) ns.PlayAlertSound(v) end },
            { type = "check", key = "flash", label = "Flash the WoW icon on the taskbar" },
            { type = "check", key = "autoInvite", label = "Invite them automatically" },
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
    elseif cmd == "sounds" then
        for i, o in ipairs(ns.SoundOptions()) do
            Print(i .. ". " .. o.label .. (o.value == db.soundKey and "  |cff33ff33(current)|r" or ""))
        end
        Print("pick one with /ms sound <number>")
    elseif cmd == "sound" and n then
        local o = ns.SoundOptions()[n]
        if o then db.soundKey = o.value; ns.PlayAlertSound(); Print("sound: " .. o.label) end
    elseif cmd == "earnings" or cmd == "gold" then
        if rest:lower() == "reset yes" then
            ns.ResetEarnings(); Print("earnings reset.")
        elseif rest:lower() == "reset" then
            Print("this clears this character's earnings for good. Type /ms earnings reset yes to confirm.")
        else
            for _, line in ipairs(ns.EarningsLines()) do Print(line) end
        end
        Refresh()
    elseif cmd == "testtrade" then
        ns.TestTrade(rest ~= "" and rest:lower() or "complete")
    elseif cmd == "show" then
        win:Show()
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
    elseif cmd == "custommsg" and rest ~= "" then
        db.customMsg = rest; Print("custom reply: " .. rest)
    else
        Print("v" .. ns.version .. " commands (or just /ms for the settings page):")
        Print("/ms add <phrase> - also watch for your own phrase, e.g. /ms add lf summon")
        Print("/ms list, /ms remove <number> - see or remove your phrases")
        Print("/ms exclude <phrase> - never match lines with this, e.g. /ms exclude ratchet")
        Print("/ms excludes, /ms unexclude <number>")
        Print("/ms portmsg <text>, /ms watermsg <text>, /ms custommsg <text> - reply text; {name} and {dest} get filled in")
        Print("/ms zone [auto|city|zone name] - show or set where you are, e.g. /ms zone uc")
        Print("/ms sounds, /ms sound <number> - list the alert sounds and pick one")
        Print("/ms earnings - gold earned from portals and water; /ms earnings reset to clear")
        Print("/ms receipts [auto|prefill|off] - payment messages: send them, type them for you, or off")
        Print("/ms paidmsg, /ms nopaymsg, /ms cancelmsg, /ms failmsg <text> - {name}, {amount}, {reason} get filled in")
        Print("/ms testtrade [complete|cancelled|failed] - try a payment message (only typed, never sent)")
        Print("/ms test - add sample requests, /ms show - show the window")
    end
    if ns.RefreshOptions then ns.RefreshOptions() end
end

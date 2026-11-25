-- Mage Services (WoW Forever)
-- Watches chat for people asking for a portal or for water/food (or your own custom
-- phrases) and lists them in a small window with Invite and Whisper buttons.
--
-- Whisper doesn't send anything by itself: it opens your chat box with a reply already
-- typed, and you press Enter. Auto-invite is optional and off by default.
--
-- Forever hides chat text from addons inside dungeons, raids, M+ and PvP, so it only
-- works out in the world, which is where people ask for ports and water anyway.

local ADDON_NAME, ns = ...

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
    flash  = true,        -- flash the WoW icon on the taskbar
    autoInvite = false,
    expire = 120,         -- seconds a request stays in the list
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
local testMode = false

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0Mage Services:|r " .. msg)
end

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

win.title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
win.title:SetPoint("TOPLEFT", 10, -8)
win.title:SetTextColor(0.41, 0.8, 0.94)

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
    row.label:SetPoint("RIGHT", row.invite, "LEFT", -6, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 0)
    row.text:SetPoint("RIGHT", row.invite, "LEFT", -6, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if not self.req then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(self.req.sender, 0.41, 0.8, 0.94)
        GameTooltip:AddLine(self.req.msg, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row.invite:SetScript("OnClick", function() if row.req then Invite(row.req.sender) end end)
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

    local shown = math.min(#requests, db.maxRows)
    for i = 1, math.max(shown, #rows) do
        local row = rows[i] or (i <= shown and MakeRow(i))
        if row then
            local req = requests[i]
            if i <= shown and req then
                row.req = req
                row.icon:SetTexture(req.info.icon)
                local ago = math.floor(now - req.time)
                row.label:SetText(req.info.label .. "  |cffaaaaaa" .. req.short .. ", " .. ago .. "s ago|r")
                row.text:SetText(req.msg)
                row:Show()
            else
                row.req = nil
                row:Hide()
            end
        end
    end

    local extra = #requests - shown
    win.title:SetText("Mage Services" .. (extra > 0 and ("  (+" .. extra .. " more)") or ""))
    win:SetHeight(34 + shown * ROW_H)
    if shown == 0 then win:Hide() else win:Show() end
end

win.clear:SetScript("OnClick", function() wipe(requests); Refresh() end)
win.close:SetScript("OnClick", function() win:Hide() end)

local function ApplyPosition()
    win:ClearAllPoints()
    local p = db.point
    win:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

---------------------------------------------------------------------------
-- Incoming chat
---------------------------------------------------------------------------
local function Alert()
    if db.sound and PlaySound and SOUNDKIT then
        PlaySound(SOUNDKIT.TELL_MESSAGE or SOUNDKIT.RAID_WARNING, "Master")
    end
    if db.flash and FlashClientIcon then FlashClientIcon() end
end

local function AddRequest(sender, msg, info)
    -- same person again: refresh their entry instead of adding a second one
    for i, r in ipairs(requests) do
        if r.sender == sender then
            table.remove(requests, i)
            break
        end
    end
    local req = { sender = sender, short = ShortName(sender), msg = msg, info = info, time = GetTime() }
    table.insert(requests, 1, req)
    Alert()
    if db.autoInvite and not testMode then Invite(sender) end
    Refresh()
end

function ns.HandleChat(msg, sender)
    if not db then return end
    if IsSecret(msg) or IsSecret(sender) then return end -- inside instances: unreadable
    if type(msg) ~= "string" or type(sender) ~= "string" or sender == "" then return end

    local me = UnitName("player")
    if ShortName(sender) == me then return end
    if UnitInParty and UnitInParty(ShortName(sender)) then return end

    local info = ns.Classify(msg, MatchOptions())
    if info then AddRequest(sender, msg, info) end
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

ev:SetScript("OnEvent", function(_, event, arg1, arg2)
    local setting = CHANNEL_EVENTS[event]
    if setting then
        if db and db[setting] then ns.HandleChat(arg1, arg2) end

    elseif event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        MageServicesDB = MageServicesDB or {}
        for k, v in pairs(defaults) do
            if MageServicesDB[k] == nil then
                MageServicesDB[k] = type(v) == "table" and { unpack(v) } or v
            end
        end
        db = MageServicesDB
        ApplyPosition()
        ns.BuildOptions()

    elseif event == "PLAYER_LOGIN" then
        for e in pairs(CHANNEL_EVENTS) do SafeRegister(e) end
        C_Timer.NewTicker(1, Refresh) -- ages the "s ago" and drops old requests
    end
end)

---------------------------------------------------------------------------
-- Test: run sample chat lines through the same path
---------------------------------------------------------------------------
local SAMPLES = {
    { "Gruntor-Realm", "LF port to UC pls" },
    { "Lilthrall-Realm", "WTB mage water x40" },
    { "Tauzan-Realm", "anyone port tb?" },
    { "Otherlock-Realm", "WTS portals to all cities 5s" },       -- another mage's ad: ignored
    { "Shamy-Realm", "water walking anyone?" },                   -- not a drink: ignored
}

local function RunTest()
    testMode = true
    local before = #requests
    for _, s in ipairs(SAMPLES) do ns.HandleChat(s[2], s[1]) end
    testMode = false
    Print(("test: %d sample lines, %d matched (2 are meant to be ignored)."):format(#SAMPLES, #requests - before))
end

---------------------------------------------------------------------------
-- Settings page (Options > AddOns) and minimap addon button
---------------------------------------------------------------------------
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
            { type = "header", label = "When someone asks" },
            { type = "check", key = "sound", label = "Play a sound" },
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
        Print("/ms test - add sample requests, /ms show - show the window")
    end
    if ns.RefreshOptions then ns.RefreshOptions() end
end

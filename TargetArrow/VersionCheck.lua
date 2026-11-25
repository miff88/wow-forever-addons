-- Shared "a newer version is out" notice. Each addon ships its own copy.
-- Addons can't go online, so copies of the addon tell each other which version they
-- are on, over the game's hidden addon channel (your guild and your group). When
-- someone has a newer one you get one chat line, and the reminder comes back at each
-- login until you update. Turned off with the "Tell me when a newer version is out"
-- setting, which also stops this copy sending anything.

local ADDON_NAME, ns = ...
local PREFIX = "MiffVer" -- shared by all of Miff's addons; each message names its addon

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function Parse(v)
    local t = {}
    for n in tostring(v or ""):gmatch("%d+") do t[#t + 1] = tonumber(n) end
    return t
end

-- true if version a is newer than version b ("1.10.0" is newer than "1.9.2")
local function Newer(a, b)
    local x, y = Parse(a), Parse(b)
    if #x == 0 then return false end
    for i = 1, math.max(#x, #y) do
        local p, q = x[i] or 0, y[i] or 0
        if p ~= q then return p > q end
    end
    return false
end
ns.VersionNewer = Newer

local store, title, mine
local told = false
local lastSent = {}

local function On() return store and store.updateNotice ~= false end

local function Tell()
    if told or not On() or not store.newestVersion then return end
    if not Newer(store.newestVersion, mine) then return end
    told = true
    DEFAULT_CHAT_FRAME:AddMessage(("|cffffd100%s:|r version %s is out (you have %s). Update it in the CurseForge app, or download it from CurseForge."):format(
        title, store.newestVersion, mine))
end

local function Send(channel, target)
    if not On() or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local key = channel .. (target or "")
    local now = GetTime()
    if lastSent[key] and now - lastSent[key] < 60 then return end -- at most once a minute per channel
    lastSent[key] = now
    pcall(C_ChatInfo.SendAddonMessage, PREFIX, ADDON_NAME .. ":" .. mine, channel, target)
end

local function Announce()
    if IsInGuild and IsInGuild() then Send("GUILD") end
    if IsInRaid and IsInRaid() then Send("RAID")
    elseif IsInGroup and IsInGroup() then Send("PARTY") end
end

local function OnMessage(prefix, text, channel, sender)
    if prefix ~= PREFIX or not store then return end
    if IsSecret(text) or IsSecret(sender) or type(text) ~= "string" then return end
    local name, ver = text:match("^([^:]+):(.+)$")
    if name ~= ADDON_NAME or not ver then return end
    if Newer(ver, mine) then
        if not store.newestVersion or Newer(ver, store.newestVersion) then store.newestVersion = ver end
        Tell()
    elseif Newer(mine, ver) and type(sender) == "string" and sender ~= "" then
        Send("WHISPER", sender) -- they're behind: let their copy know
    end
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        OnMessage(...)
    elseif event == "GROUP_ROSTER_UPDATE" then
        Announce()
    end
end)

-- Called by the addon once its saved settings are loaded.
function ns.StartVersionCheck(db, addonTitle)
    store, title = db, addonTitle
    mine = ns.version
    if not mine or mine == "?" then
        local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
        mine = get and get(ADDON_NAME, "Version") or "0"
    end
    -- updated since the last notice: forget it
    if store.newestVersion and not Newer(store.newestVersion, mine) then store.newestVersion = nil end

    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    end
    pcall(ev.RegisterEvent, ev, "CHAT_MSG_ADDON")
    pcall(ev.RegisterEvent, ev, "GROUP_ROSTER_UPDATE")
    -- give the login a moment to settle, then remind and say hello
    if C_Timer and C_Timer.After then
        C_Timer.After(15, function() Tell(); Announce() end)
    end
end

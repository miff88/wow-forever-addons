-- Mage Services: rune counts and tidying up your group after a portal.
--
-- Runes: the window's footer shows how many Runes of Teleportation and Runes of Portals
-- you carry, and warns when Runes of Portals run low. The warning only starts once the
-- addon has seen a portal use one, in case a server doesn't need them.
--
-- After a portal (optional): customers who were standing with you when the portal went
-- up are removed from the group once they vanish from beside you, so your next customers
-- have room. Only people you invited from Mage Services or who asked you in chat, and only
-- while you lead the group.

local _, ns = ...

local RUNE_TELEPORT, RUNE_PORTAL = 17031, 17032
local TELEPORT_IDS = { 3561, 3562, 3563, 3565, 3566, 3567 }
local PORTAL_IDS = { 10059, 11416, 11417, 11418, 11419, 11420 }
local WATCH_FOR = 120          -- seconds after a portal to keep watching who went through
local CUSTOMER_WINDOW = 30 * 60

local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0Mage Services:|r " .. msg)
end

local function Count(id)
    local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not fn then return nil end
    local ok, n = pcall(fn, id)
    if ok and not IsSecret(n) and type(n) == "number" then return n end
end

local function KnowsAny(ids)
    if not IsPlayerSpell then return false end
    for _, id in ipairs(ids) do
        local ok, known = pcall(IsPlayerSpell, id)
        if ok and not IsSecret(known) and known then return true end
    end
    return false
end

local function SpellName(id)
    if not (C_Spell and C_Spell.GetSpellName) or IsSecret(id) then return nil end
    local ok, name = pcall(C_Spell.GetSpellName, id)
    if ok and not IsSecret(name) then return name end
end

---------------------------------------------------------------------------
-- Rune counts on the window
---------------------------------------------------------------------------
local win = ns.win
local runes = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
runes:SetPoint("BOTTOMRIGHT", -8, 0)
runes:SetHeight(20)
runes:SetJustifyH("RIGHT")
runes:SetWordWrap(false)
win.runes = runes
win.footer:SetPoint("BOTTOMRIGHT", runes, "BOTTOMLEFT", -10, 0)

local lastPortal, lastTeleport          -- counts as of the last check
local castKind, castAt                  -- "portal" / "teleport" cast just finished
local warnedAt                          -- the count you were last warned at

function ns.RuneLine()
    local db = ns.db
    if not db or not db.runeCount then return "" end
    local portal, teleport = Count(RUNE_PORTAL), Count(RUNE_TELEPORT)
    local parts = {}
    local t = ns.Theme()
    if teleport and (teleport > 0 or KnowsAny(TELEPORT_IDS)) then
        parts[#parts + 1] = teleport .. " teleport"
    end
    if portal and (portal > 0 or KnowsAny(PORTAL_IDS)) then
        local low = db.portalRunes and portal < (db.runeLow or 0)
        parts[#parts + 1] = (low and "|cffff4040" or "") .. portal .. " portal" .. (low and "|r" or "")
    end
    if #parts == 0 then return "" end
    return "|cff" .. t.muted .. "Runes:|r " .. table.concat(parts, ", ")
end

local function UpdateRunes()
    local line = ns.RuneLine()
    runes:SetText(line)
    runes:SetShown(line ~= "")
    if ns.Theme then
        local c = ns.Theme().footer
        runes:SetTextColor(c[1], c[2], c[3])
    end
end
ns.UpdateRunes = UpdateRunes

local function CheckRunes()
    local db = ns.db
    if not db then return end
    local portal, teleport = Count(RUNE_PORTAL), Count(RUNE_TELEPORT)
    -- a portal or teleport just finished and the matching rune went down: they're used here
    if castAt and GetTime() - castAt < 5 then
        if castKind == "portal" and portal and lastPortal and portal < lastPortal then
            db.portalRunes = true; castAt = nil
        elseif castKind == "teleport" and teleport and lastTeleport and teleport < lastTeleport then
            db.teleportRunes = true; castAt = nil
        end
    end
    if portal and db.portalRunes and db.runeLow and db.runeLow > 0 then
        if portal < db.runeLow and (lastPortal == nil or lastPortal >= db.runeLow or warnedAt == nil) and warnedAt ~= portal then
            warnedAt = portal
            Print(portal == 0 and "you're out of Runes of Portals." or
                ("only %d Rune%s of Portals left."):format(portal, portal == 1 and "" or "s"))
        elseif portal >= db.runeLow then
            warnedAt = nil
        end
    end
    lastPortal, lastTeleport = portal, teleport
    UpdateRunes()
end
ns.CheckRunes = CheckRunes

---------------------------------------------------------------------------
-- After a portal: remove customers who went through
---------------------------------------------------------------------------
local watch -- { untilT, people = { [key] = true } }

local function GroupUnits()
    local out = {}
    local prefix, n = "party", 4
    if IsInRaid and IsInRaid() then prefix, n = "raid", 40 end
    for i = 1, n do
        local u = prefix .. i
        if UnitExists(u) and not (UnitIsUnit and UnitIsUnit(u, "player")) then out[#out + 1] = u end
    end
    return out
end

local function IsCustomer(key)
    local now = GetTime()
    local inv = ns.invited and ns.invited[key]
    if inv and now - inv < CUSTOMER_WINDOW then return true end
    local c = ns.customers and ns.customers[key]
    return c ~= nil and now - c.time < CUSTOMER_WINDOW
end

local function Visible(u)
    if not UnitIsVisible then return true end
    local ok, v = pcall(UnitIsVisible, u)
    if not ok or IsSecret(v) then return true end
    return v and true or false
end

local function Leader()
    if not UnitIsGroupLeader then return false end
    local ok, v = pcall(UnitIsGroupLeader, "player")
    return ok and not IsSecret(v) and v
end

local function Uninvite(name)
    if C_PartyInfo and C_PartyInfo.UninviteUnit then
        return pcall(C_PartyInfo.UninviteUnit, name)
    elseif UninviteUnit then
        return pcall(UninviteUnit, name)
    end
    return false
end

local function OnPortal()
    if not (ns.db and ns.db.kickAfterPort) then return end
    local people = {}
    local any = false
    for _, u in ipairs(GroupUnits()) do
        local key = ns.NameKey(ns.UnitFull(u))
        if key ~= "" and IsCustomer(key) and Visible(u) then people[key] = true; any = true end
    end
    watch = any and { untilT = GetTime() + WATCH_FOR, people = people } or nil
end
ns.OnPortal = OnPortal

local function CheckGroup()
    if not watch then return end
    if GetTime() > watch.untilT or not (ns.db and ns.db.kickAfterPort) then watch = nil return end
    if not Leader() then return end
    local left = false
    for _, u in ipairs(GroupUnits()) do
        local name = ns.UnitFull(u)
        local key = ns.NameKey(name)
        if watch.people[key] then
            left = true
            if not Visible(u) then
                watch.people[key] = nil
                if Uninvite(name) then
                    if ns.invited then ns.invited[key] = nil end
                    Print(("removed %s from the group (went through your portal)."):format(ns.DisplayName(name) or name))
                end
            end
        end
    end
    if not left then watch = nil end
end
ns.CheckGroup = CheckGroup

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local function SafeRegister(e, unit)
    if unit then return pcall(ev.RegisterUnitEvent, ev, e, unit) end
    return pcall(ev.RegisterEvent, ev, e)
end
SafeRegister("PLAYER_LOGIN")

ev:SetScript("OnEvent", function(_, event, a1, _, a3)
    if event == "PLAYER_LOGIN" then
        SafeRegister("BAG_UPDATE_DELAYED")
        SafeRegister("UNIT_SPELLCAST_SUCCEEDED", "player")
        C_Timer.After(3, CheckRunes)
        C_Timer.NewTicker(1, function() CheckGroup(); UpdateRunes() end)
    elseif event == "BAG_UPDATE_DELAYED" then
        CheckRunes()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local name = SpellName(a3)
        if type(name) ~= "string" then return end
        if name:find("^Portal:") then
            castKind, castAt = "portal", GetTime()
            OnPortal()
        elseif name:find("^Teleport:") then
            castKind, castAt = "teleport", GetTime()
        end
    end
end)

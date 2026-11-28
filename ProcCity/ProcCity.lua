-- Proc City (WoW Forever)
-- A movable row of icons for your procs and short buffs: Flurry, Crusader, Clearcasting,
-- trinkets and the like. Each icon shows how long is left, and a Crusader that has
-- procced on both weapons at once glows.
--
-- WoW Forever hides buff details from addons during combat, so Proc City reads your
-- buffs directly when it can (out of combat) and, in combat, works from what the game
-- still shows: your own casts (trinkets, cooldowns), your Strength going up and down
-- (Crusader and other Strength procs) and the game's combat text "you gain" messages.
-- When combat ends it checks the real buffs again and corrects itself.
-- /proc debug prints what it sees, to tune it for Forever.

local ADDON_NAME, ns = ...

local defaults = {
    updateNotice = true,
    grow    = "right",  -- icons grow to the right or left of the anchor
    size    = 40,
    spacing = 4,
    timer   = true,     -- seconds left on the icon
    swipe   = true,     -- clock-style sweep as it runs out
    glowDouble = true,  -- glow when a proc is up twice (Crusader on both weapons)
    sound   = false,
    cats    = { proc = true, cooldown = true, enchant = true, item = true, trinket = true, racial = true,
                reactive = true },
    off     = {},       -- [key] = true for procs you've turned off
    learned = {},       -- [key] = real duration seen out of combat
    learnedIDs = {},    -- [spellID] = key, for buffs matched by name (new Forever enchants)
    learnedIcons = {},  -- [icon] = key, seen out of combat: names a buff the game hides in combat
    procIcons = {},     -- [key] = the icon Forever shows on the buff itself (can differ from the spell's)
    pins    = {},       -- keys always shown, greyed out while they're down, in this order
    pinsInCombat = true,-- ...only greyed out in combat (out of combat they hide)
    pinAlpha = 50,      -- how faint a pinned icon is while it's down
    glowButtons = true, -- light the matching action buttons (Overpower, Revenge, Shadow Bolt...)
    -- Overpower on the nameplate of the mob that dodged you (Overpower.lua)
    oppPlates = true,
    oppSize   = 30,
    oppOffset = 18,     -- above the health bar
    oppWindow = 5,      -- seconds Overpower stays usable after a dodge
    oppSound  = true,   -- sound when a mob dodges you
    oppPop    = true,
    oppPulse  = true,
    pos     = nil,
}

local db
local unlocked, testMode, debugMode = false, false, false

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8000Proc City:|r " .. msg)
end

local function Debug(msg)
    if debugMode then DEFAULT_CHAT_FRAME:AddMessage("|cffff8000Proc City debug:|r " .. msg) end
end

local function SpellName(id)
    if not id or IsSecret(id) then return nil end
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, id)
        if ok and name and not IsSecret(name) then return name end
    end
end

local function SpellIcon(id)
    if not id or IsSecret(id) then return nil end
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, id)
        if ok and tex and not IsSecret(tex) then return tex end
    end
end

---------------------------------------------------------------------------
-- Lookups
---------------------------------------------------------------------------
local byID, byName = {}, {}   -- byName[name] = list of entries with that buff name
local playerClass
local equipped = {}           -- item IDs in your weapon slots

local function AddName(n, p)
    local list = byName[n]
    if not list then byName[n] = { p } return end
    for _, q in ipairs(list) do if q == p then return end end
    list[#list + 1] = p
end

-- Icons that belong to exactly one tracked proc: in combat the game can hide a buff's name
-- and spell ID but still show its icon, which is then enough to say which proc it is.
local byIcon = {}
local function AddIcon(icon, p)
    if not icon or icon == 134400 or IsSecret(icon) then return end
    local cur = byIcon[icon]
    if cur == nil then byIcon[icon] = p
    elseif cur ~= p then byIcon[icon] = false end -- shared by two procs: can't tell them apart
end

local function BuildLookups()
    wipe(byID); wipe(byName); wipe(byIcon)
    for _, p in ipairs(ns.PROCS) do
        p.icon = p.icon or SpellIcon(p.ids[1]) or 134400
        for _, id in ipairs(p.react and {} or p.ids) do
            byID[id] = p
            -- the client's own name for the ID (other languages, or a renamed spell)
            local n = SpellName(id)
            if n then AddName(n, p) end
        end
        if not p.react then AddName(p.name, p) end
    end
    for _, p in ipairs(ns.PROCS) do
        if not p.react then
            for _, id in ipairs(p.ids) do AddIcon(SpellIcon(id), p) end
        end
    end
    -- IDs learned from your own buffs, for entries whose ID isn't published yet
    if db and db.learnedIDs then
        local byKey = {}
        for _, p in ipairs(ns.PROCS) do byKey[p.key] = p end
        for id, key in pairs(db.learnedIDs) do
            local p = byKey[key]
            if p and not byID[id] then
                byID[id] = p
                local n = SpellName(id)
                if n then AddName(n, p) end
                if p.icon == 134400 then p.icon = SpellIcon(id) or p.icon end
            end
        end
    end
    if db and db.procIcons then
        for _, p in ipairs(ns.PROCS) do
            local icon = db.procIcons[p.key]
            if icon then p.icon = icon end
        end
    end
    if db and db.learnedIcons then
        local byKey = {}
        for _, p in ipairs(ns.PROCS) do byKey[p.key] = p end
        for icon, key in pairs(db.learnedIcons) do
            if byKey[key] then AddIcon(icon, byKey[key]) end
        end
    end
end

local function Wanted(p)
    if not db then return false end
    if p.class and not p.class[playerClass] then return false end
    if not db.cats[p.cat] then return false end
    return not db.off[p.key]
end

local function HasItem(p)
    if not p.items then return false end
    for _, id in ipairs(p.items) do if equipped[id] then return true end end
    return false
end

-- A weapon proc matched by anything other than its own published ID only counts while
-- that weapon is on: a Swiftness Potion's "Speed" isn't Sprinter's Sword, and a druid's
-- Enrage isn't Ragehammer's.
local function OwnID(p, id)
    if not id then return false end
    for _, x in ipairs(p.ids) do if x == id then return true end end
    return false
end
local function ItemOK(p, id)
    return not p.items or HasItem(p) or OwnID(p, id)
end
ns.ItemOK = ItemOK

-- Several buffs share a name (Haste, Enrage, Holy Shield): prefer the one from a
-- weapon you have on, then one that isn't from a weapon, then anything you track.
local function FindByName(name)
    local list = name and byName[name]
    if not list then return nil end
    local best, bestScore
    for _, p in ipairs(list) do
        if ItemOK(p) then
            local score = (Wanted(p) and 10 or 0) + (HasItem(p) and 2 or (not p.items and 1 or 0))
            if not bestScore or score > bestScore then best, bestScore = p, score end
        end
    end
    return best
end

-- The tracked proc for a buff or cast, by spell ID first, then by name.
local function Match(id, name)
    local p = id and byID[id]
    if p and not ItemOK(p, id) then p = nil end
    return p or FindByName(name)
end

---------------------------------------------------------------------------
-- Active procs
---------------------------------------------------------------------------
-- active[key] = { proc, icon, started, expires (nil = no timer), duration, count, stacks, source }
local active, order = {}, {}
local Layout -- defined below

local function Duration(p)
    return (db and db.learned[p.key]) or p.dur
end

local function PlayProcSound()
    if db.sound and PlaySound and SOUNDKIT and SOUNDKIT.TELL_MESSAGE then
        pcall(PlaySound, SOUNDKIT.TELL_MESSAGE, "Master")
    end
end

local function Remove(key)
    if not active[key] then return end
    active[key] = nil
    for i, k in ipairs(order) do
        if k == key then table.remove(order, i) break end
    end
end

-- A proc started (or refreshed). count is how many are up at once (Crusader per weapon).
local function Start(p, source, opts)
    opts = opts or {}
    local now = GetTime()
    local a = active[p.key]
    local dur = opts.duration or Duration(p)
    if not a then
        a = { proc = p, started = now, count = 0 }
        active[p.key] = a
        order[#order + 1] = p.key
        PlayProcSound()
    end
    a.icon = opts.icon or a.icon or p.icon
    a.source = source
    a.seenAt = now
    a.duration = dur
    if opts.noTimer then
        a.expires = nil
    else
        a.expires = opts.expires or (dur and now + dur or nil)
    end
    a.count = opts.count or math.max(a.count, 1)
    a.stacks = opts.stacks
    a.started = opts.started or (a.expires and dur and a.expires - dur) or now
    a.lastAt = now
    Layout()
end

local useSpells = {} -- [spellID] = { slot, icon, name } for equipped trinkets with a Use
local generic = {}   -- made-up entries for trinkets that aren't in the list

local function GenericFor(spellID, use, name)
    local key = "use" .. spellID
    local g = generic[key]
    if not g then
        g = { key = key, name = use.name or name or "Trinket", ids = { spellID }, cat = "trinket",
              generic = true, icon = use.icon }
        generic[key] = g
    end
    return g
end

-- a buff on you that belongs to one of your trinkets' Use effects
local function GenericForAura(spellID, name)
    for id, use in pairs(useSpells) do
        if id == spellID or (name and use.name == name) then return GenericFor(id, use, name) end
    end
end

---------------------------------------------------------------------------
-- Reading your buffs (exact, when the game allows it)
---------------------------------------------------------------------------
local function AurasReadable()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, secret = pcall(C_Secrets.ShouldAurasBeSecret)
        if ok and secret then return false end
    end
    return C_UnitAuras and C_UnitAuras.GetAuraDataByIndex and true or false
end

-- Returns true if it could read your buffs (and updated the list from them).
local ScanOne, ApplyFound
local lastHidden = 0
local hiddenShown = {} -- debug: each hidden buff slot described once per fight
local function ScanAuras()
    if testMode or not AurasReadable() then return false end
    local found, readable, hidden = {}, 0, 0
    for i = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok then return false end
        -- in combat the game can hide some buffs and not others: skip the hidden ones
        -- and read the rest (it used to give up on the whole list for one hidden buff)
        if IsSecret(aura) then
            hidden = hidden + 1
        elseif aura == nil then
            break
        elseif IsSecret(aura.name) or IsSecret(aura.spellId) then
            hidden = hidden + 1
            -- the name and ID are hidden: the icon may still say which proc it is
            local icon = aura.icon
            local p = icon and not IsSecret(icon) and byIcon[icon]
            if p and Wanted(p) and (not p.items or HasItem(p)) then
                ScanOne({ name = p.name, spellId = p.ids[1], icon = icon,
                          expirationTime = aura.expirationTime, duration = aura.duration,
                          applications = aura.applications }, found)
                readable = readable + 1
            end
            if debugMode and not hiddenShown[i] then
                hiddenShown[i] = true
                local function f(v) if v == nil then return "nil" end return IsSecret(v) and "hidden" or tostring(v) end
                Debug(("hidden buff %d: icon %s (%s), time left %s, stacks %s"):format(i, f(icon),
                    p and p.name or "not tracked", f(aura.expirationTime), f(aura.applications)))
            end
        else
            readable = readable + 1
            ScanOne(aura, found)
        end
    end
    if hidden > 0 and readable == 0 then return false end -- nothing to go on
    if hidden ~= lastHidden then
        Debug(("buffs: %d readable, %d hidden"):format(readable, hidden))
        lastHidden = hidden
    end
    return ApplyFound(found, hidden)
end

-- One readable buff: is it a proc you track?
ScanOne = function(aura, found)
    local p = Match(aura.spellId, aura.name) or GenericForAura(aura.spellId, aura.name)
    if p and not p.generic and aura.spellId and not byID[aura.spellId] then
        -- matched by name only: remember the real ID for next time
        byID[aura.spellId] = p
        db.learnedIDs[aura.spellId] = p.key
        if p.icon == 134400 and aura.icon and not IsSecret(aura.icon) then p.icon = aura.icon end
        Debug(("learned %s = spell %d"):format(p.name, aura.spellId))
    end
    if p and not p.generic and aura.icon and not IsSecret(aura.icon) and db.learnedIcons[aura.icon] ~= p.key
        and not InCombatLockdown() then
        db.learnedIcons[aura.icon] = p.key
        AddIcon(aura.icon, p)
    end
    if p and not p.generic and aura.icon and not IsSecret(aura.icon) and not InCombatLockdown()
        and db.procIcons[p.key] ~= aura.icon then
        db.procIcons[p.key] = aura.icon -- show the same icon as your buff bar
        p.icon = aura.icon
    end
    if p and Wanted(p) then
        local f = found[p.key]
        if not f then
            f = { p = p, count = 0, icon = p.generic and p.icon or aura.icon }
            found[p.key] = f
        end
        f.count = f.count + 1
        local exp, dur = aura.expirationTime, aura.duration
        if not IsSecret(exp) and exp and exp > 0 and (not f.expires or exp > f.expires) then
            f.expires, f.duration = exp, dur
        end
        if not IsSecret(aura.applications) and aura.applications and aura.applications > 1 then
            f.stacks = aura.applications
        end
    end
end

ApplyFound = function(found, hidden)

    -- oldest first, so the row keeps the order the procs happened in
    local keys = {}
    for key in pairs(found) do keys[#keys + 1] = key end
    table.sort(keys, function(x, y)
        local fx, fy = found[x], found[y]
        local sx = fx.expires and fx.duration and (fx.expires - fx.duration) or 0
        local sy = fy.expires and fy.duration and (fy.expires - fy.duration) or 0
        if sx ~= sy then return sx < sy end
        return x < y
    end)
    for _, key in ipairs(keys) do
        local f = found[key]
        local p = f.p
        if f.duration and f.duration > 0 and not IsSecret(f.duration) then
            db.learned[key] = math.floor(f.duration + 0.5) -- Forever's real duration
        end
        local a = active[key]
        local changed = not a or a.count ~= f.count or a.expires ~= f.expires or a.stacks ~= f.stacks
        if changed then
            Start(p, "aura", { duration = f.duration, count = f.count, stacks = f.stacks, icon = f.icon,
                               expires = f.expires, noTimer = not f.expires })
        end
        active[key].readable = true
    end
    -- anything we were showing that isn't really there any more (abilities aren't buffs).
    -- With some buffs hidden, only a proc we could read before is known to be gone.
    for key, a in pairs(active) do
        if not found[key] and a.source ~= "react" and (hidden == 0 or a.readable) then Remove(key) end
    end
    Layout()
    return true
end

---------------------------------------------------------------------------
-- In combat: asking for each proc by spell ID
--
-- In combat the game hides the buff list from addons, but it still answers "is this
-- buff on you?" for a given spell. Some buffs come back in full (exact timer and
-- stacks); for the rest it may only say that the buff is there, and then the timer runs
-- from when it was first seen, using the duration learned out of combat.
---------------------------------------------------------------------------
-- Looks one spell up: "absent", "present" (and the aura when it's readable), or nil
-- when the game won't say.
local function ProbeAura(id)
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return nil end
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
    if not ok then return nil end
    if IsSecret(aura) then return "present" end      -- there, but nothing readable
    if aura == nil then return "absent" end
    if type(aura) ~= "table" then return nil end
    return "present", aura
end
ns.ProbeAura = ProbeAura

-- The IDs to ask about for a proc: its own, plus any learned from your buffs.
local function IDsFor(p)
    local ids = {}
    for _, id in ipairs(p.ids or {}) do ids[#ids + 1] = id end
    if db and db.learnedIDs then
        for id, key in pairs(db.learnedIDs) do
            if key == p.key then ids[#ids + 1] = id end
        end
    end
    return ids
end

local function Readable(v) return v ~= nil and not IsSecret(v) end

-- Does the game hide this buff in combat? (nil answer counts as hidden)
local function SpellAuraSecret(id)
    if not (C_Secrets and C_Secrets.ShouldSpellAuraBeSecret) then return true end
    local ok, v = pcall(C_Secrets.ShouldSpellAuraBeSecret, id)
    if not ok or IsSecret(v) then return true end
    return v and true or false
end

-- Returns true if it could tell anything at all.
-- addOnly: the buff list was read too, so it decides what has ended. The game's answer
-- for one spell in combat can be "not there" for a buff that is (Forever 1.60.1), so only
-- trust it to add a proc the list couldn't see, never to remove one.
local function CombatScan(addOnly)
    if testMode then return false end
    local decided, changed = false, false
    local now = GetTime()
    for _, p in ipairs(ns.PROCS) do
        if not p.react and Wanted(p) and (not p.items or HasItem(p)) then
            local state, best
            for _, id in ipairs(IDsFor(p)) do
                local st, aura = ProbeAura(id)
                if st == "present" then
                    state = "present"
                    if aura then best = best or aura end
                elseif st == "absent" and state == nil and not SpellAuraSecret(id) then
                    -- only a buff the game shows in combat can be trusted to be really gone
                    state = "absent"
                end
            end
            if state then decided = true end
            local a = active[p.key]
            if state == "present" then
                local exp = best and Readable(best.expirationTime) and best.expirationTime or nil
                local dur = best and Readable(best.duration) and best.duration or nil
                local stacks = best and Readable(best.applications) and best.applications > 1 and best.applications or nil
                if exp and exp > 0 then
                    -- exact
                    if not a or a.expires ~= exp or a.stacks ~= stacks then
                        Start(p, "aura", { duration = dur, expires = exp, stacks = stacks, count = a and a.count or 1 })
                        changed = true
                    end
                elseif not a or a.source == "react" then
                    Start(p, "seen") -- timer from now, with the duration learned out of combat
                    changed = true
                elseif a.expires and now > a.expires then
                    Start(p, "seen", { count = a.count }) -- refreshed: still there after its time ran out
                    changed = true
                end
            elseif state == "absent" and a and a.source ~= "react" and not addOnly then
                Remove(p.key)
                changed = true
            end
        end
    end
    if changed then Layout() end
    return decided
end
ns.CombatScan = CombatScan

-- For /proc debug: what the game will say about each proc you track, right now.
function ns.AuraProbeLines()
    local lines = {}
    for _, p in ipairs(ns.PROCS) do
        if not p.react and Wanted(p) then
            local parts = {}
            for _, id in ipairs(IDsFor(p)) do
                local secret = "?"
                if C_Secrets and C_Secrets.ShouldSpellAuraBeSecret then
                    local ok, v = pcall(C_Secrets.ShouldSpellAuraBeSecret, id)
                    if ok and not IsSecret(v) then secret = v and "hidden in combat" or "readable" end
                end
                local st, aura = ProbeAura(id)
                local detail = st or "no answer"
                if aura then detail = detail .. (Readable(aura.expirationTime) and ", timer readable" or ", timer hidden") end
                parts[#parts + 1] = ("%d %s (%s)"):format(id, detail, secret)
            end
            if #parts == 0 then parts[1] = "new in Forever, matched by name (not seen yet)" end
            lines[#lines + 1] = p.name .. ": " .. table.concat(parts, "; ")
        end
    end
    return lines
end

---------------------------------------------------------------------------
-- In combat: your casts
---------------------------------------------------------------------------
local function ScanTrinkets()
    wipe(useSpells)
    local getSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if not getSpell then return end
    for _, slot in ipairs({ 13, 14 }) do
        local itemID = GetInventoryItemID and GetInventoryItemID("player", slot)
        if itemID and not IsSecret(itemID) then
            local ok, name, spellID = pcall(getSpell, itemID)
            if ok and spellID and not IsSecret(spellID) then
                useSpells[spellID] = { slot = slot, name = name, icon = GetInventoryItemTexture("player", slot) }
            end
        end
    end
end

-- Crusader on how many of your weapons (enchant 1900 in the item link)
local crusaderWeapons = 0
local function ScanWeapons()
    crusaderWeapons = 0
    wipe(equipped)
    for _, slot in ipairs({ 16, 17, 18 }) do
        local id = GetInventoryItemID and GetInventoryItemID("player", slot)
        if id and not IsSecret(id) then equipped[id] = true end
    end
    for _, slot in ipairs({ 16, 17 }) do
        local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
        if link and not IsSecret(link) then
            local enchant = tonumber(link:match("item:%d+:(%d+)"))
            if enchant == 1900 then crusaderWeapons = crusaderWeapons + 1 end
        end
    end
end

-- One proc can show up as both a cast and a Strength change a moment apart: only a
-- signal more than this long after the last one counts as a second proc.
local SAME_PROC = 0.75

local function OnCast(spellID)
    if IsSecret(spellID) then Debug("cast: (hidden)") return end
    local name = SpellName(spellID)
    local p = Match(spellID, name)
    local use = useSpells[spellID]
    Debug(("cast: %s %s%s"):format(tostring(spellID), tostring(name),
        p and (" -> " .. p.name) or (use and " -> trinket" or "")))

    -- buffs used up by your next spell (Revelation)
    local now, removed = GetTime(), false
    for key, a in pairs(active) do
        if a.proc.consume and a.proc ~= p and now - (a.seenAt or now) > 0.2 then
            Remove(key)
            removed = true
        end
    end
    if removed then Layout() end

    if p and Wanted(p) then
        local a = active[p.key]
        if p.double and a and a.source ~= "aura" then
            -- a second proc while one is up: count it as the other weapon if both have it
            local limit = math.max(crusaderWeapons, 1)
            local count = a.count
            if GetTime() - (a.lastAt or 0) > SAME_PROC then count = math.min(a.count + 1, limit) end
            Start(p, "cast", { count = count })
        else
            Start(p, "cast")
        end
        return
    end

    if use and db.cats.trinket then
        local g = GenericFor(spellID, use, name)
        if not db.off[g.key] then Start(g, "cast", { icon = use.icon }) end
    end
end

---------------------------------------------------------------------------
-- In combat: your Strength (Crusader and other Strength procs)
---------------------------------------------------------------------------
local lastStr
local statProcs = {} -- procs that move a stat, biggest first

local function ReadStr()
    if not UnitStat then return nil end
    local ok, _, stat = pcall(UnitStat, "player", 1)
    if not ok or stat == nil or IsSecret(stat) then return nil end
    return stat
end

local function OnStats()
    local str = ReadStr()
    if not str then
        if lastStr then Debug("strength: hidden") end
        lastStr = nil
        return
    end
    if lastStr and str ~= lastStr then
        local delta = str - lastStr
        Debug(("strength %d -> %d (%+d)"):format(lastStr, str, delta))
        -- only infer while the buffs themselves can't be read
        if not AurasReadable() then
            for _, p in ipairs(statProcs) do
                if Wanted(p) and (p.key ~= "holystrength" or crusaderWeapons > 0)
                    and (not p.items or HasItem(p)) then
                    local amount = db.learned[p.key .. "Amount"] or p.stat[2]
                    -- allow for Strength multipliers (Kings, talents): 90% to 130%
                    for n = p.double and 2 or 1, 1, -1 do
                        local lo, hi = amount * n * 0.9, amount * n * 1.3
                        if delta >= lo and delta <= hi then
                            local a = active[p.key]
                            local count = n
                            if a and a.count then
                                -- the same proc already announced by its cast a moment ago
                                local fresh = GetTime() - (a.lastAt or 0) <= SAME_PROC and a.source == "cast"
                                count = fresh and math.max(a.count, n) or (a.count + n)
                            end
                            if p.double then count = math.min(count, math.max(crusaderWeapons, 1)) else count = 1 end
                            Start(p, "stat", { count = count })
                            lastStr = str
                            return
                        elseif -delta >= lo and -delta <= hi then
                            local a = active[p.key]
                            if a then
                                a.count = a.count - n
                                if a.count <= 0 then Remove(p.key) end
                                Layout()
                            end
                            lastStr = str
                            return
                        end
                    end
                end
            end
        end
    end
    lastStr = str
end

---------------------------------------------------------------------------
-- In combat: the game's combat text ("+Flurry")
---------------------------------------------------------------------------
local function OnCombatText(kind)
    if IsSecret(kind) then Debug("combat text: (hidden)") return end
    if kind ~= "SPELL_AURA_START" and kind ~= "SPELL_AURA_END" then return end
    local get = (C_CombatText and C_CombatText.GetCurrentEventInfo) or GetCurrentCombatTextEventInfo
    if not get then return end
    local ok, name = pcall(get)
    if not ok or IsSecret(name) or type(name) ~= "string" then Debug("combat text " .. kind .. ": (hidden)") return end
    local p = FindByName(name)
    Debug(("combat text %s %s%s"):format(kind, name, p and " -> tracked" or ""))
    if not p or not Wanted(p) then return end
    if kind == "SPELL_AURA_START" then
        Start(p, "text")
    elseif active[p.key] and not p.double then
        Remove(p.key)
        Layout()
    end
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------
local anchor = CreateFrame("Frame", "ProcCityAnchor", UIParent)
anchor:SetSize(40, 40)
anchor:SetMovable(true)
anchor:SetClampedToScreen(true)
anchor:SetFrameStrata("MEDIUM")

anchor.box = anchor:CreateTexture(nil, "BACKGROUND")
anchor.box:SetAllPoints()
anchor.box:SetColorTexture(1, 0.5, 0, 0.25)
anchor.label = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
anchor.label:SetPoint("BOTTOM", anchor, "TOP", 0, 4)
anchor.label:SetText("Proc City: drag to move")

anchor:SetScript("OnMouseDown", function(self, button)
    if unlocked and button == "LeftButton" then self:StartMoving() end
end)
anchor:SetScript("OnMouseUp", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    if db and point then db.pos = { point = point, rel = rel, x = x, y = y } end
end)

local function PlaceAnchor()
    anchor:ClearAllPoints()
    local p = db and db.pos
    if p and p.point then
        anchor:SetPoint(p.point, UIParent, p.rel or p.point, p.x or 0, p.y or 0)
    else
        anchor:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
    end
end

local icons = {}

local function NewIcon()
    local f = CreateFrame("Frame", nil, anchor)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    f.border = f:CreateTexture(nil, "BACKGROUND")
    f.border:SetPoint("TOPLEFT", -1, 1)
    f.border:SetPoint("BOTTOMRIGHT", 1, -1)
    f.border:SetColorTexture(0, 0, 0, 1)

    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints()
    f.cd:SetReverse(true)
    if f.cd.SetHideCountdownNumbers then f.cd:SetHideCountdownNumbers(true) end
    if f.cd.SetDrawEdge then f.cd:SetDrawEdge(false) end

    local over = CreateFrame("Frame", nil, f)
    over:SetAllPoints()
    over:SetFrameLevel((f.cd:GetFrameLevel() or 1) + 2)
    f.time = over:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    f.time:SetPoint("CENTER", 0, 0)
    f.stacks = over:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    f.stacks:SetPoint("BOTTOMRIGHT", -2, 2)

    -- glow for "up twice": a gold ring that pulses
    f.glow = over:CreateTexture(nil, "OVERLAY")
    f.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    f.glow:SetBlendMode("ADD")
    f.glow:SetVertexColor(1, 0.82, 0.1)
    f.glow:SetPoint("CENTER")
    f.edges = {}
    for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
                         { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        local t = over:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetColorTexture(1, 0.82, 0.1, 1)
        t:SetPoint(e[1]); t:SetPoint(e[2])
        if e[3] then t:SetHeight(2) else t:SetWidth(2) end
        f.edges[#f.edges + 1] = t
    end
    f.pulse = over:CreateAnimationGroup()
    f.pulse:SetLooping("BOUNCE")
    local fade = f.pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.3)
    fade:SetDuration(0.4)
    f.glowFrame = over

    f.pop = f:CreateAnimationGroup()
    local grow = f.pop:CreateAnimation("Scale")
    if grow.SetScaleFrom then grow:SetScaleFrom(1.4, 1.4); grow:SetScaleTo(1, 1) else grow:SetScale(0.7, 0.7) end
    grow:SetDuration(0.15)
    return f
end

local function SetGlow(f, on)
    f.glow:SetShown(on)
    for _, t in ipairs(f.edges) do t:SetShown(on) end
    if on then
        if not f.pulse:IsPlaying() then f.pulse:Play() end
    else
        f.pulse:Stop()
    end
end

local function FormatTime(left)
    if left >= 60 then return math.floor(left / 60) .. "m" end
    if left >= 10 then return tostring(math.floor(left)) end
    return ("%.1f"):format(left)
end

local byKey = {}
for _, p in ipairs(ns.PROCS) do byKey[p.key] = p end

local function IsPinned(key)
    for _, k in ipairs(db.pins) do if k == key then return true end end
    return false
end

-- pinned procs show greyed out while they're down (in combat, unless set otherwise)
local function ShowPinned(p)
    if not p or not Wanted(p) then return false end
    if p.items and not HasItem(p) then return false end
    if p.key == "holystrength" and crusaderWeapons == 0 then return false end -- no Crusader on
    if testMode or unlocked then return true end
    if db.pinsInCombat then
        local ok, c = pcall(UnitAffectingCombat, "player")
        return ok and not IsSecret(c) and c and true or false
    end
    return true
end

local function PinIcon(p)
    if p.icon then return p.icon end
    for _, id in ipairs(p.ids or {}) do
        local tex = SpellIcon(id)
        if tex then return tex end
    end
    return 134400
end

Layout = function()
    if not db then return end
    local size, gap = db.size, db.spacing
    local dir = db.grow == "left" and -1 or 1
    anchor:SetSize(size, size)
    anchor.box:SetShown(unlocked)
    anchor.label:SetShown(unlocked)
    anchor:EnableMouse(unlocked)

    -- pinned procs first, in the order you pinned them, then everything else that's up
    local list, seen = {}, {}
    for _, key in ipairs(db.pins) do
        local p = byKey[key]
        if active[key] then
            list[#list + 1] = { key = key, a = active[key] }
            seen[key] = true
        elseif ShowPinned(p) then
            list[#list + 1] = { key = key, p = p }
        end
    end
    for _, key in ipairs(order) do
        if not seen[key] then list[#list + 1] = { key = key, a = active[key] } end
    end

    local shown = 0
    for i, e in ipairs(list) do
        local a = e.a
        local f = icons[i] or NewIcon()
        icons[i] = f
        f:SetSize(size, size)
        f.glow:SetSize(size * 1.8, size * 1.8)
        f:ClearAllPoints()
        f:SetPoint("CENTER", anchor, "CENTER", (i - 1) * (size + gap) * dir, 0)
        if a then
            f.tex:SetTexture(a.icon or 134400)
            if f.tex.SetDesaturated then f.tex:SetDesaturated(false) end
            f:SetAlpha(1)
            if a.expires and a.duration and db.swipe then
                f.cd:SetCooldown(a.expires - a.duration, a.duration)
                f.cd:Show()
            else
                f.cd:Hide()
            end
            f.stacks:SetText((a.stacks and a.stacks > 1) and a.stacks or "")
            SetGlow(f, db.glowDouble and (a.count or 1) >= 2)
            if f.key ~= e.key then
                f.key = e.key
                if f.pop then f.pop:Stop(); f.pop:Play() end
            end
        else
            -- pinned and down: a faint grey icon holding its place
            f.tex:SetTexture(PinIcon(e.p))
            if f.tex.SetDesaturated then f.tex:SetDesaturated(true) end
            f:SetAlpha((db.pinAlpha or 50) / 100)
            f.cd:Hide()
            f.stacks:SetText("")
            f.time:SetText("")
            SetGlow(f, false)
            f.key = "down:" .. e.key
        end
        f:Show()
        shown = i
    end
    for i = shown + 1, #icons do
        icons[i]:Hide()
        icons[i].key = nil
        SetGlow(icons[i], false)
    end
end
ns.Layout = function() Layout() end

-- seconds left on each icon, and dropping finished procs
local ticker = CreateFrame("Frame")
local since, probeSince = 0, 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    since = since + elapsed
    probeSince = probeSince + elapsed
    if since < 0.1 or not db then return end
    since = 0
    -- in combat, ask about each proc twice a second (buff changes don't always say which)
    if probeSince >= 0.5 then
        probeSince = 0
        -- (buff changes don't always come with an event in combat, so look anyway)
        if not testMode and InCombatLockdown() then
            -- a buff the game hides in combat (Crusader, for one) is skipped by the list read,
            -- so ask about each tracked proc by spell as well whenever anything is hidden
            if not ScanAuras() then CombatScan()
            elseif lastHidden > 0 then CombatScan(true) end
        elseif not testMode and not AurasReadable() then
            CombatScan()
        end
    end
    local now = GetTime()
    local removed = false
    for i = #order, 1, -1 do
        local key = order[i]
        local a = active[key]
        if a.expires and a.expires <= now and not testMode then
            if a.source == "stat" and not AurasReadable() then
                -- your Strength hasn't dropped, so it was refreshed: keep it, without a
                -- timer, until the Strength drop (or the end of combat) clears it
                a.expires = nil
                removed = true
            else
                Remove(key)
                removed = true
            end
        elseif not a.expires and not testMode and a.source ~= "aura" and a.source ~= "stat"
            and now - a.started > 30 then
            -- "until used" buffs we can't see: give up after 30 seconds
            Remove(key)
            removed = true
        end
    end
    if removed then Layout() end
    for _, f in ipairs(icons) do
        local a = f.key and active[f.key]
        if a then
            if db.timer and a.expires then
                f.time:SetText(FormatTime(math.max(0, a.expires - now)))
            else
                f.time:SetText("")
            end
        end
    end
end)

---------------------------------------------------------------------------
-- Test mode
---------------------------------------------------------------------------
local function TestEntries()
    local list = {}
    local function add(key) for _, p in ipairs(ns.PROCS) do if p.key == key then list[#list + 1] = p end end end
    add("holystrength")
    if playerClass == "WARRIOR" then add("flurry"); add("deathwish")
    elseif playerClass == "MAGE" then add("clearcasting"); add("arcanepower")
    elseif playerClass == "WARLOCK" then add("shadowtrance")
    elseif playerClass == "PALADIN" then add("vengeance")
    elseif playerClass == "ROGUE" then add("adrenalinerush"); add("bladeflurry")
    elseif playerClass == "HUNTER" then add("quickshots"); add("rapidfire")
    elseif playerClass == "DRUID" then add("clearcasting"); add("naturesgrace")
    elseif playerClass == "SHAMAN" then add("flurry"); add("clearcasting")
    elseif playerClass == "PRIEST" then add("innerfocus"); add("spirittap") end
    if playerClass == "WARRIOR" then add("overpower")
    elseif playerClass == "ROGUE" then add("riposte")
    elseif playerClass == "HUNTER" then add("counterattack") end
    add("kissspider")
    return list
end

ns.Start, ns.Remove, ns.Wanted = Start, Remove, Wanted
ns.Active = function() return active end
ns.IsTest = function() return testMode end
ns.IsUnlocked = function() return unlocked end

local function SetTest(on)
    testMode = on
    wipe(active); wipe(order)
    if on then
        local now = GetTime()
        for i, p in ipairs(TestEntries()) do
            local dur = Duration(p) or 15
            Start(p, "test", { duration = dur, expires = now + dur * (1 - 0.15 * (i - 1)),
                               count = p.double and 2 or 1, stacks = p.key == "vengeance" and 3 or nil })
        end
    else
        ScanAuras()
    end
    Layout()
    if ns.RefreshOverpower then ns.RefreshOverpower() end
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

local function Refresh()
    ScanWeapons()
    ScanTrinkets()
    lastStr = ReadStr()
    ScanAuras()
    Layout()
end

-- Overpower Plates / Proc Plates is now part of Proc City: bring its settings over once
function ns.ImportProcPlates()
    local old = OverpowerPlatesDB
    if type(old) == "table" and not db.importedProcPlates then
        if type(old.window) == "number" then db.oppWindow = old.window end
        if type(old.size) == "number" then db.oppSize = old.size end
        if type(old.offsetY) == "number" then db.oppOffset = old.offsetY end
        if old.sound ~= nil then db.oppSound = old.sound and true or false end
        if old.pop ~= nil then db.oppPop = old.pop and true or false end
        if old.pulse ~= nil then db.oppPulse = old.pulse and true or false end
        if old.barGlow == false then db.glowButtons = false end
        if old.reactive == false then
            for _, k in ipairs({ "revenge", "riposte", "counterattack", "mongoose" }) do db.off[k] = true end
        end
        if type(old.reactOff) == "table" then
            for k, v in pairs(old.reactOff) do if v then db.off[k] = true end end
        end
        db.importedProcPlates = true
    end
end

ev:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        ProcCityDB = ProcCityDB or {}
        for k, v in pairs(defaults) do
            if ProcCityDB[k] == nil then
                if type(v) == "table" then
                    local copy = {}
                    for kk, vv in pairs(v) do copy[kk] = vv end
                    ProcCityDB[k] = copy
                else
                    ProcCityDB[k] = v
                end
            end
        end
        for k, v in pairs(defaults.cats) do
            if ProcCityDB.cats[k] == nil then ProcCityDB.cats[k] = v end
        end
        db = ProcCityDB
        ns.db = db
        if type(db.pins) ~= "table" then db.pins = {} end
        ns.ImportProcPlates()
        local _, class = UnitClass("player")
        playerClass = class
        BuildLookups()
        wipe(statProcs)
        for _, p in ipairs(ns.PROCS) do if p.stat then statProcs[#statProcs + 1] = p end end
        table.sort(statProcs, function(a, b) return a.stat[2] > b.stat[2] end)
        if ns.StartVersionCheck then ns.StartVersionCheck(db, "Proc City") end
        PlaceAnchor()
        ns.BuildOptions()

        SafeRegister("PLAYER_ENTERING_WORLD")
        SafeRegister("PLAYER_REGEN_DISABLED")
        SafeRegister("PLAYER_REGEN_ENABLED")
        SafeRegister("PLAYER_EQUIPMENT_CHANGED")
        SafeRegister("UNIT_AURA", "player")
        SafeRegister("UNIT_SPELLCAST_SUCCEEDED", "player")
        SafeRegister("UNIT_STATS", "player")
        SafeRegister("COMBAT_TEXT_UPDATE")
        Layout()
        return
    end

    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_EQUIPMENT_CHANGED" then
        BuildLookups()
        Refresh()
        if event == "PLAYER_ENTERING_WORLD" and ns.SeedPins then C_Timer.After(4, ns.SeedPins) end
    elseif event == "PLAYER_REGEN_DISABLED" then
        Layout() -- pinned procs appear greyed out
        wipe(hiddenShown)
        Debug("combat started; buffs readable: " .. tostring(AurasReadable()) .. ", strength readable: " .. tostring(ReadStr() ~= nil))
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- out of combat: trust the real buffs again
        C_Timer.After(0.2, function() ScanAuras(); lastStr = ReadStr(); Layout() end)
    elseif event == "UNIT_AURA" then
        if not ScanAuras() and not CombatScan() then OnStats() end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnCast(arg3)
    elseif event == "UNIT_STATS" then
        OnStats()
    elseif event == "COMBAT_TEXT_UPDATE" then
        OnCombatText(arg1)
    end
end)

---------------------------------------------------------------------------
-- Settings page and slash command
---------------------------------------------------------------------------
local function ProcsForSettings()
    local list = {}
    for _, p in ipairs(ns.PROCS) do
        if not p.class or p.class[playerClass] then list[#list + 1] = p end
    end
    return list
end

function ns.BuildOptions()
    local controls = {
        { type = "header", label = "Layout" },
        { type = "choice", key = "grow", label = "Icons grow to the", values = { "right", "left" } },
        { type = "range", key = "size", label = "Icon size", min = 20, max = 80, step = 2 },
        { type = "range", key = "spacing", label = "Gap between icons", min = 0, max = 20, step = 1 },
        { type = "check", key = "timer", label = "Show seconds left on the icon" },
        { type = "check", key = "swipe", label = "Show a clock sweep as it runs out" },
        { type = "check", key = "glowDouble", label = "Glow when a proc is up twice (Crusader on both weapons)" },
        { type = "check", key = "sound", label = "Play a sound when a proc starts" },
        { type = "button", label = "Move the icons",
          dynamicLabel = function() return unlocked and "Lock the icons" or "Move the icons" end,
          func = function() unlocked = not unlocked; Layout() end },
        { type = "button", label = "Reset position", func = function() db.pos = nil; PlaceAnchor() end },
        { type = "button", label = "Test",
          dynamicLabel = function() return testMode and "Stop the test" or "Test" end,
          func = function() SetTest(not testMode) end },
        { type = "header", label = "What to show" },
    }
    for _, c in ipairs(ns.CATEGORIES) do
        controls[#controls + 1] = { type = "check", key = "cat_" .. c.key, label = c.label }
    end
    controls[#controls + 1] = { type = "check", key = "glowButtons", label = "Light the matching action buttons (Overpower, Revenge, Riposte, Shadow Bolt during Shadow Trance...)" }
    if playerClass == "WARRIOR" then
        controls[#controls + 1] = { type = "header", label = "Overpower on the mob that dodged you" }
        controls[#controls + 1] = { type = "check", key = "oppPlates", label = "Put an Overpower icon on that mob's nameplate too" }
        controls[#controls + 1] = { type = "range", key = "oppSize", label = "Nameplate icon size", min = 16, max = 64, step = 2 }
        controls[#controls + 1] = { type = "range", key = "oppOffset", label = "Height above the health bar", min = 0, max = 80, step = 2 }
        controls[#controls + 1] = { type = "range", key = "oppWindow", label = "Seconds Overpower stays up", min = 1, max = 10, step = 1, suffix = "s" }
        controls[#controls + 1] = { type = "check", key = "oppPop", label = "Pop the nameplate icon in" }
        controls[#controls + 1] = { type = "check", key = "oppPulse", label = "Pulse a gold glow around it" }
        controls[#controls + 1] = { type = "check", key = "oppSound", label = "Play a sound when a mob dodges you" }
        controls[#controls + 1] = { type = "info", height = 44, lines = function()
            return "|cff999999A nameplate dodge only counts when your Overpower charge goes up at the same moment, so dodges against other players are ignored. Needs enemy nameplates on (V).|r" end }
    end
    controls[#controls + 1] = { type = "header", label = "Always show (greyed out while down)" }
    controls[#controls + 1] = { type = "dropdown", key = "pinPick", label = "Pin or unpin a proc",
        options = function()
            local out = {}
            for _, p in ipairs(ns.PinChoices()) do
                out[#out + 1] = { value = p.key, label = (IsPinned(p.key) and "|cff40ff40[pinned]|r " or "") .. p.name }
            end
            return out
        end,
        onSelect = function(key) ns.TogglePin(key) end }
    controls[#controls + 1] = { type = "info", height = 30, lines = function()
        local names = {}
        for _, k in ipairs(db.pins) do names[#names + 1] = byKey[k] and byKey[k].name or k end
        return "|cff999999" .. (#names > 0 and ("Pinned: " .. table.concat(names, ", ")) or "Nothing pinned. Pin the procs you build around, like Flurry or Crusader, to see at a glance when they're down.") .. "|r" end }
    controls[#controls + 1] = { type = "check", key = "pinsInCombat", label = "Only show pinned procs that are down while I'm in combat" }
    controls[#controls + 1] = { type = "range", key = "pinAlpha", label = "How faint a pinned proc is while down", min = 20, max = 100, step = 10, suffix = "%" }
    controls[#controls + 1] = { type = "button", label = "Unpin all", func = function() wipe(db.pins); Layout() end }
    controls[#controls + 1] = { type = "info", height = 40, lines = function()
        return "|cff999999Turn single procs off with /proc off <name>, e.g. /proc off bloodrage. /proc list shows them all.|r" end }
    controls[#controls + 1] = { type = "header", label = "How it works on WoW Forever" }
    controls[#controls + 1] = { type = "info", height = 70, lines = function()
        return "|cff999999Forever hides buff details from addons in combat. Out of combat Proc City reads your buffs exactly. In combat it works from your own casts (trinkets and cooldowns), your Strength (Crusader) and the game's combat text, then corrects itself when combat ends. /proc debug shows what it sees.|r" end }

    -- category checkboxes live in db.cats; mirror them as flat keys for the settings page
    local proxy = setmetatable({}, {
        __index = function(_, k)
            local cat = type(k) == "string" and k:match("^cat_(.+)$")
            if cat then return db.cats[cat] end
            return db[k]
        end,
        __newindex = function(_, k, v)
            local cat = type(k) == "string" and k:match("^cat_(.+)$")
            if cat then db.cats[cat] = v else db[k] = v end
        end,
    })

    ns.CreateOptions({
        title = "Proc City",
        updateNotice = true,
        changes = {
            { "1.6.4", "/proc check crusader: everything the game says about one proc, right now" },
            { "1.6.3", "Fixed: since 1.6.1, Flurry, Berserker Rage and other procs could vanish in combat", "Crusader uses the same icon as your buff bar" },
            { "1.6.2", "Buffs the game hides in combat are recognised by their icon (Crusader)", "/proc debug describes each hidden buff" },
            { "1.6.1", "Crusader (and any other buff the game hides in combat) shows in combat again" },
            { "1.6.0", "Tracks the new WoW Forever procs and cooldowns for every class (Reckless Swings, Shield Wall, Heating Up, Eclipse, Infusion of Light, Maelstrom Weapon and more)",
                       "Overpower shows for every charge, including Bloodthrill procs and mobs without a nameplate",
                       "A Swiftness Potion no longer shows as a Sprinter's Sword proc (weapon procs need the weapon on)",
                       "Settings page: long labels no longer run into their buttons" },
            { "1.5.3", "Blood Craze is now tracked (warrior talent: heals you after you're crit)" },
            { "1.5.2", "Procs update in combat again: one buff the game hides in combat made it stop reading all of them",
                       "It now skips the hidden ones and reads the rest, and checks twice a second in combat" },
            { "1.5.1", "In combat, procs light up again: it asks the game about each proc directly instead of reading the hidden buff list",
                       "/proc debug lists what the game says about each proc, if any still stay grey" },
            { "1.5.0", "Starter pins: the procs your class builds around are pinned for you (if you have them)",
                       "Unpin any you don't want with /proc unpin <name> or on this page" },
            { "1.4.0", "Proc Plates is now part of Proc City: Overpower, Revenge, Riposte, Counterattack and Mongoose Bite",
                       "Overpower also marks the mob that dodged you on its nameplate",
                       "Lights the matching action buttons, including Shadow Bolt during Shadow Trance" },
            { "1.3.0", "Pin the procs you care about: they keep their place, greyed out while they're down",
                       "Pick them on this page or with /proc pin <name>" },

        },
        icon = "Interface\\Icons\\Spell_Holy_BlessingOfStrength",
        about = "Your procs and short buffs as a row of icons",
        credit = "Created by Miff, supported by Claude",
        slash = "/proc",
        db = proxy,
        onChange = function()
            if not testMode then ScanAuras() end
            Layout()
            if ns.RefreshOverpower then ns.RefreshOverpower() end
            if ns.UpdateGlows then ns.UpdateGlows(true) end
        end,
        controls = controls,
    })
end

function ProcCity_OnAddonCompartmentClick()
    if ns.OpenOptions then ns.OpenOptions() end
end

local function KnowsAny(ids)
    if not IsPlayerSpell then return false end
    for _, id in ipairs(ids or {}) do
        local ok, known = pcall(IsPlayerSpell, id)
        if ok and not IsSecret(known) and known then return true end
    end
    return false
end

-- what can be pinned: your class's procs and cooldowns, weapon enchants, racials you
-- have, and procs from weapons you have on (plus anything already pinned)
function ns.PinChoices()
    local out = {}
    for _, p in ipairs(ns.PROCS) do
        local fits = (p.class and p.class[playerClass]) or p.cat == "enchant"
            or (p.items and HasItem(p)) or (p.cat == "racial" and KnowsAny(p.ids))
        if fits or IsPinned(p.key) then out[#out + 1] = p end
    end
    return out
end

-- Starter pins: the first time each class logs in with nothing pinned, pin the procs that
-- class usually builds around, if this character has them (the talent or the ability, or
-- Crusader on a weapon right now). Unpin any you don't want; they aren't added back.
local STARTER = {
    WARRIOR = { { key = "overpower" }, { key = "flurry", talent = { 12319, 12971, 12972, 12973, 12974 } },
                { key = "holystrength", crusader = true } },
    ROGUE   = { { key = "riposte" }, { key = "remorseless", talent = { 14144, 14148 } },
                { key = "holystrength", crusader = true } },
    HUNTER  = { { key = "quickshots", talent = { 19552, 19553, 19554, 19555, 19556 } }, { key = "mongoose" } },
    MAGE    = { { key = "clearcasting", talent = { 11213, 12574, 12575, 12576, 12577 } } },
    PRIEST  = { { key = "spirittap", talent = { 15270, 15335, 15336, 15337, 15338 } } },
    WARLOCK = { { key = "shadowtrance", talent = { 18094, 18095 } } },
    PALADIN = { { key = "vengeance", talent = { 20049, 20056, 20057, 20058, 20059 } },
                { key = "holystrength", crusader = true } },
    SHAMAN  = { { key = "flurry", talent = { 16256, 16281, 16282, 16283, 16284 } },
                { key = "clearcasting", talent = { 16164 } } },
    DRUID   = { { key = "clearcasting", talent = { 16864 } }, { key = "naturesgrace", talent = { 16880 } } },
}
ns.STARTER = STARTER

function ns.SeedPins()
    if not db or testMode then return end
    if type(db.seeded) ~= "table" then db.seeded = {} end
    if db.seeded[playerClass] then return end
    -- you've already pinned something for this class yourself
    for _, k in ipairs(db.pins) do
        local p = byKey[k]
        if p and p.class and p.class[playerClass] then db.seeded[playerClass] = true return end
    end
    local picks, classPicks = {}, 0
    for _, st in ipairs(STARTER[playerClass] or {}) do
        local p = byKey[st.key]
        local has
        if not p then has = false
        elseif st.crusader then has = crusaderWeapons > 0
        elseif st.talent then has = KnowsAny(st.talent)
        else has = KnowsAny(p.ids) end
        if has and not IsPinned(st.key) then
            picks[#picks + 1] = p
            if not st.crusader then classPicks = classPicks + 1 end
        end
    end
    -- nothing for your class yet (low level, or talents not picked): try again next login
    if classPicks == 0 then return end
    local added = {}
    for _, p in ipairs(picks) do
        db.pins[#db.pins + 1] = p.key
        added[#added + 1] = p.name
    end
    db.seeded[playerClass] = true
    Layout()
    local list = #added == 1 and added[1] or (table.concat(added, ", ", 1, #added - 1) .. " and " .. added[#added])
    local verb = #added == 1 and "it keeps its place and shows" or "they keep their place and show"
    Print(("pinned %s for you: %s greyed out in combat while down. /proc unpin <name> to remove one."):format(list, verb))
end

function ns.TogglePin(key)
    for i, k in ipairs(db.pins) do
        if k == key then table.remove(db.pins, i); Layout() return false end
    end
    db.pins[#db.pins + 1] = key
    Layout()
    return true
end

local function FindProc(text)
    text = (text or ""):lower():gsub("[%s'%-]", "")
    if text == "" then return nil end
    for _, p in ipairs(ns.PROCS) do
        if p.key == text or p.alias == text or p.name:lower():gsub("[%s'%-]", "") == text then return p end
    end
end

SLASH_PROCCITY1 = "/proc"
SLASH_PROCCITY2 = "/proccity"
SlashCmdList.PROCCITY = function(msg)
    local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "" then
        ns.OpenOptions()
        return
    elseif cmd == "test" then
        SetTest(not testMode)
        Print(testMode and "test icons on. /proc test again to stop." or "test icons off.")
    elseif cmd == "move" or cmd == "unlock" or cmd == "lock" then
        unlocked = (cmd == "unlock") or (cmd == "move" and not unlocked)
        Layout()
        Print(unlocked and "drag the orange box to move the icons. /proc lock when done." or "icons locked.")
    elseif cmd == "reset" then
        db.pos = nil; PlaceAnchor(); Print("position reset.")
    elseif cmd == "grow" and (rest == "left" or rest == "right") then
        db.grow = rest; Layout(); Print("icons grow to the " .. rest .. ".")
    elseif cmd == "size" and tonumber(rest) then
        db.size = tonumber(rest); Layout(); Print("icon size " .. rest)
    elseif cmd == "off" or cmd == "on" then
        local p = FindProc(rest)
        if not p then Print("no proc called \"" .. rest .. "\". /proc list shows them.") return end
        db.off[p.key] = (cmd == "off") or nil
        if cmd == "off" then Remove(p.key); Layout() end
        Print(p.name .. (cmd == "off" and " won't be shown." or " will be shown."))
    elseif cmd == "pin" or cmd == "unpin" then
        local p = FindProc(rest)
        if not p then Print("no proc called \"" .. rest .. "\". /proc list shows them.") return end
        local pinned = IsPinned(p.key)
        if (cmd == "pin") ~= pinned then ns.TogglePin(p.key) end
        Print(p.name .. (cmd == "pin" and " is pinned: it keeps its place, greyed out while it's down." or " is unpinned."))
    elseif cmd == "plates" then
        db.oppPlates = not db.oppPlates
        if ns.RefreshOverpower then ns.RefreshOverpower() end
        Print("Overpower icon on the nameplate of the mob that dodged you " .. (db.oppPlates and "on" or "off"))
    elseif cmd == "glow" then
        db.glowButtons = not db.glowButtons
        if ns.UpdateGlows then ns.UpdateGlows(true) end
        Print("action button glow " .. (db.glowButtons and "on" or "off"))
    elseif cmd == "list" then
        local parts = {}
        for _, p in ipairs(ProcsForSettings()) do
            parts[#parts + 1] = (db.off[p.key] or not db.cats[p.cat]) and ("|cff888888" .. p.name .. "|r") or p.name
        end
        Print("tracked for your class (grey = off): " .. table.concat(parts, ", "))
    elseif cmd == "check" then
        -- one proc, everything the game will say about it right now (short enough for one screenshot)
        local want = (rest and rest ~= "" and rest or "crusader"):lower()
        local p
        for _, q in ipairs(ns.PROCS) do
            if not q.react and (q.key == want or q.name:lower() == want or (q.alias and q.alias == want)) then p = q break end
        end
        if not p then Print("check: no proc called " .. want) return end
        local function f(v) if v == nil then return "nil" end return IsSecret(v) and "hidden" or tostring(v) end
        local now = GetTime()
        local a = active[p.key]
        Print(("check %s: in combat %s, tracked %s%s, showing %s"):format(p.name, tostring(InCombatLockdown()),
            tostring(Wanted(p)), p.key == "holystrength" and (", Crusader on " .. crusaderWeapons .. " weapon(s)") or "",
            a and (a.source .. (a.expires and (" " .. math.floor(a.expires - now + 0.5) .. "s") or "") .. " x" .. (a.count or 1)) or "no"))
        local total, hiddenN, lines = 0, 0, {}
        for i = 1, 40 do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok then lines[#lines + 1] = "list read failed at " .. i break end
            if aura == nil then break end
            total = total + 1
            if IsSecret(aura) then
                hiddenN = hiddenN + 1
                lines[#lines + 1] = ("[%d] whole buff hidden"):format(i)
            else
                local name, id, icon = aura.name, aura.spellId, aura.icon
                local hid = IsSecret(name) or IsSecret(id)
                if hid then hiddenN = hiddenN + 1 end
                local mine = (not IsSecret(id) and id and byID[id] == p) or (not IsSecret(name) and name == p.name)
                    or (not IsSecret(icon) and icon and (icon == p.icon or db.procIcons[p.key] == icon))
                if hid or mine then
                    lines[#lines + 1] = ("[%d] %s id %s icon %s left %s"):format(i, f(name), f(id), f(icon),
                        IsSecret(aura.expirationTime) and "hidden" or (aura.expirationTime and math.floor(aura.expirationTime - now + 0.5) or "nil"))
                end
            end
        end
        Print(("buff list: %d buffs, %d hidden; this proc or hidden:"):format(total, hiddenN))
        for _, l in ipairs(lines) do Print("  " .. l) end
        local parts = {}
        for _, id in ipairs(IDsFor(p)) do
            local st = ProbeAura(id)
            parts[#parts + 1] = ("%d %s%s"):format(id, st or "?", SpellAuraSecret(id) and " (secret)" or "")
        end
        Print("by spell: " .. (#parts > 0 and table.concat(parts, "; ") or "no IDs known"))
        Print(("icons: buff %s, spell %s"):format(tostring(db.procIcons[p.key]), tostring(SpellIcon(p.ids[1]))))
    elseif cmd == "debug" then
        debugMode = not debugMode
        Print(debugMode and "debug on: casts, Strength changes and combat text are printed. /proc debug again to stop." or "debug off.")
        if debugMode then
            Print(("now: buffs readable %s, Strength readable %s, Crusader on %d weapon(s), trinkets with a Use %d"):format(
                tostring(AurasReadable()), tostring(ReadStr() ~= nil), crusaderWeapons,
                (function() local n = 0 for _ in pairs(useSpells) do n = n + 1 end return n end)()))
            if playerClass == "WARRIOR" and ns.ReadOverpowerCharges then
                Print("Overpower charges: " .. tostring(ns.ReadOverpowerCharges()))
            end
            if ns.ReactiveDebug then for _, line in ipairs(ns.ReactiveDebug()) do Print(line) end end
            Print("per proc (try this in combat with a proc up):")
            for _, line in ipairs(ns.AuraProbeLines()) do Print("  " .. line) end
            if ns.GlowDebug then
                for _, p in ipairs(ns.PROCS) do
                    if p.glow and p.class and p.class[playerClass] then
                        local g = p.glow == true and { name = p.name, ids = p.ids } or p.glow
                        Print(ns.GlowDebug(g.name, g.ids))
                    end
                end
            end
        end
    else
        Print("v" .. ns.version .. " commands (or just /proc for the settings page):")
        Print("/proc test - show test icons")
        Print("/proc move - move the icons (/proc lock when done), /proc reset - back to the middle")
        Print("/proc grow left|right - which way the icons grow (now " .. db.grow .. ")")
        Print("/proc size <n> - icon size (now " .. db.size .. ")")
        Print("/proc list - what's tracked for your class; /proc off <name> or /proc on <name>")
        Print("/proc pin <name>, /proc unpin <name> - always show it, greyed out while it's down")
        Print("/proc glow - light the matching action buttons (now " .. (db.glowButtons and "on" or "off") .. ")")
        if playerClass == "WARRIOR" then
            Print("/proc plates - Overpower icon on the mob that dodged you (now " .. (db.oppPlates and "on" or "off") .. ")")
        end
        Print("/proc debug - print what Proc City sees in combat")
    end
    if ns.RefreshOptions then ns.RefreshOptions() end
end

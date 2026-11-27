-- Buff Notice (WoW Forever), formerly Battle Shout Notice
-- Reminds you when a buff your class keeps up is missing or about to run out: Battle
-- Shout, Arcane Intellect, Fortitude, Mark of the Wild, Blessings, armors, Inner Fire,
-- Aspects, Lightning Shield, poisons and weapon imbues. For group buffs it also counts the
-- party and raid members who are missing yours, and in dungeons and raids it can check
-- your food and flask or elixir.
--
-- Forever hides buff details from addons during combat, so Buff Notice reads the real
-- buffs whenever the game allows it (out of combat), keeps its own timers in between, and
-- restarts a timer the moment you cast the buff. No combat log is used.

local ADDON_NAME, ns = ...

---------------------------------------------------------------------------
-- Settings (saved per account, change with /bsn)
---------------------------------------------------------------------------
local defaults = {
    updateNotice = true,  -- "a newer version is out" chat notice (VersionCheck.lua)
    threshold = 10,    -- short buffs (under 10 minutes): warn with this many seconds left
    longThreshold = 60,-- long buffs: warn with this many seconds left
    size      = 52,
    sound     = true,  -- sound when a buff drops off in combat
    party     = true,  -- count party and raid members missing your group buffs
    consumables = false, -- food and flask/elixir in dungeons and raids
    quietRested = true,  -- no reminders in cities and inns
    point     = { "CENTER", "CENTER", 0, 160 },
    on        = {},    -- [key] = true/false to override a buff's default
    durations = {},    -- [key] = real length seen out of combat
}

local db
local playerClass
local buffs = {}         -- the entries for your class that you know, plus consumables
local state = {}         -- [key] = { expires = time or 0 or math.huge, missing = n party }
local unlocked, testMode = false, false

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Buff Notice:|r " .. msg)
end

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, id)
        if ok and not IsSecret(name) and name then return name end
    end
end

local function SpellTexture(id)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, id)
        if ok and not IsSecret(tex) and tex then return tex end
    end
end

local function Knows(id)
    if IsPlayerSpell then
        local ok, known = pcall(IsPlayerSpell, id)
        if ok and not IsSecret(known) and known then return true end
    end
    if IsSpellKnown then
        local ok, known = pcall(IsSpellKnown, id)
        if ok and not IsSecret(known) and known then return true end
    end
    return false
end

local function AurasReadable()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, secret = pcall(C_Secrets.ShouldAurasBeSecret)
        if not ok or secret then return false end
    end
    return C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName and true or false
end

-- Returns expirationTime (math.huge for buffs without a timer), duration  if up and readable
--         false   if definitely not there
--         nil     if the game won't say right now (in combat)
local function ReadBuff(unit, names)
    if not AurasReadable() then return nil end
    local unknown = false
    for _, name in ipairs(names) do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, name, "HELPFUL")
        if not ok or IsSecret(aura) then
            unknown = true -- this one's hidden: keep checking the other names
        elseif aura then
            local exp, dur = aura.expirationTime, aura.duration
            if IsSecret(exp) or IsSecret(dur) then return nil end -- there, but its timer is hidden: keep the last known
            if not exp or exp == 0 then return math.huge, 0 end
            return exp, dur
        end
    end
    if unknown then return nil end
    return false
end

-- food / flask: any buff whose name contains one of the words
local function ReadMatch(words)
    if not AurasReadable() or not C_UnitAuras.GetAuraDataByIndex then return nil end
    -- the game can hide some buffs and not others: skip the hidden ones and read the rest
    local hidden = false
    for i = 1, 60 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok then return nil end
        if IsSecret(aura) then
            hidden = true
        elseif aura == nil then
            break
        end
        local name = not IsSecret(aura) and aura and aura.name
        if IsSecret(name) then hidden = true end
        if name and not IsSecret(name) and type(name) == "string" then
            for _, w in ipairs(words) do
                if name:find(w, 1, true) then
                    local exp = aura.expirationTime
                    if IsSecret(exp) or not exp or exp == 0 then return math.huge end
                    return exp
                end
            end
        end
    end
    if hidden then return nil end -- it might be one of the hidden ones
    return false
end

-- temporary weapon enchants (poisons, imbues): expiration time, or false
local function ReadWeapon(hand)
    if not GetWeaponEnchantInfo then return nil end
    local ok, hasMain, mainMs, _, _, hasOff, offMs = pcall(GetWeaponEnchantInfo)
    if not ok then return nil end
    local has, ms = hasMain, mainMs
    if hand == "off" then has, ms = hasOff, offMs end
    if IsSecret(has) or IsSecret(ms) then return nil end
    if not has then return false end
    return GetTime() + (ms or 0) / 1000
end

local function OffHandWeapon()
    local id = GetInventoryItemID and GetInventoryItemID("player", 17)
    if not id or IsSecret(id) then return false end
    if C_Item and C_Item.GetItemInfoInstant then
        local ok, _, _, _, _, _, classID = pcall(C_Item.GetItemInfoInstant, id)
        if ok and classID then return classID == 2 end -- 2 = weapon
    end
    return true
end

local function InInstance()
    if not IsInInstance then return false end
    local ok, inside, kind = pcall(IsInInstance)
    if not ok or IsSecret(inside) then return false end
    return inside and (kind == "party" or kind == "raid")
end

---------------------------------------------------------------------------
-- Which buffs to watch
---------------------------------------------------------------------------
local function Enabled(b)
    local v = db.on[b.key]
    if v == nil then return not b.off end
    return v
end

local function Resolve(b)
    b.realNames = {}
    for i, id in ipairs(b.ids or {}) do
        b.realNames[#b.realNames + 1] = SpellName(id) or b.names[i]
    end
    for _, n in ipairs(b.names or {}) do b.realNames[#b.realNames + 1] = n end
    if not b.icon then
        for _, id in ipairs(b.ids or {}) do
            if Knows(id) then b.icon = SpellTexture(id); break end
        end
        b.icon = b.icon or SpellTexture(b.ids and b.ids[1] or 0) or "Interface\\Icons\\INV_Misc_QuestionMark"
    end
end

local function Rebuild()
    playerClass = select(2, UnitClass("player"))
    wipe(buffs)
    for _, b in ipairs(ns.CLASS_BUFFS[playerClass] or {}) do
        local known = false
        for _, id in ipairs(b.ids) do if Knows(id) then known = true; break end end
        if known then
            Resolve(b)
            buffs[#buffs + 1] = b
        end
    end
    for _, c in ipairs(ns.CONSUMABLES) do
        c.consumable = true
        buffs[#buffs + 1] = c
    end
    for _, b in ipairs(buffs) do state[b.key] = state[b.key] or { expires = 0, missing = 0 } end
end
ns.Rebuild = Rebuild
ns.Buffs = function() return buffs end
ns.State = function() return state end

---------------------------------------------------------------------------
-- Display: a row of icons, one per buff that needs you
---------------------------------------------------------------------------
local frame = CreateFrame("Frame", "BattleShoutReminderFrame", UIParent)
frame:SetFrameStrata("HIGH")
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:SetSize(52, 52)
frame:Hide()
if frame.RegisterForDrag then frame:RegisterForDrag("LeftButton") end
frame:SetScript("OnDragStart", function(self) if unlocked then self:StartMoving() end end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    db.point = { p, rp, x, y }
end)

local mover = frame:CreateTexture(nil, "BACKGROUND")
mover:SetAllPoints()
mover:SetColorTexture(1, 0.82, 0, 0.3)
mover:Hide()

local icons = {}
local function Icon(i)
    if icons[i] then return icons[i] end
    local f = CreateFrame("Frame", nil, frame)
    f.border = f:CreateTexture(nil, "BACKGROUND")
    f.border:SetPoint("TOPLEFT", -2, 2)
    f.border:SetPoint("BOTTOMRIGHT", 2, -2)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.timer = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalHuge")
    f.timer:SetPoint("CENTER")
    f.count = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    f.count:SetPoint("BOTTOMRIGHT", -2, 2)
    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.label:SetPoint("TOP", f, "BOTTOM", 0, -4)
    f.pulse = f:CreateAnimationGroup()
    f.pulse:SetLooping("BOUNCE")
    local fade = f.pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.35)
    fade:SetDuration(0.5)
    icons[i] = f
    return f
end

local function ApplyLayout()
    frame:ClearAllPoints()
    local p = db.point
    frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

-- shows: list of { b = entry, kind = "missing" | "expiring" | "party", remaining, count }
local function Draw(shows)
    ns.lastShows = shows
    local size, gap = db.size, math.max(8, math.floor(db.size / 4))
    local n = #shows
    frame:SetSize(math.max(size, n * size + (n - 1) * gap), size)
    for i = 1, math.max(n, #icons) do
        local f = Icon(i)
        local s = shows[i]
        if s then
            f:SetSize(size, size)
            f:ClearAllPoints()
            f:SetPoint("LEFT", frame, "LEFT", (i - 1) * (size + gap), 0)
            f.icon:SetTexture(s.b.icon)
            f.icon:SetDesaturated(s.kind == "missing")
            f.timer:SetText(s.kind == "expiring" and tostring(math.ceil(s.remaining)) or "")
            f.count:SetText(s.kind == "party" and tostring(s.count) or "")
            if s.kind == "missing" then
                f.border:SetColorTexture(1, 0.2, 0.1, 1)
                f.label:SetText(s.b.label)
                if not f.pulse:IsPlaying() then f.pulse:Play() end
            elseif s.kind == "party" then
                f.border:SetColorTexture(0.3, 0.6, 1, 1)
                f.label:SetText(s.count == 1 and "1 missing it" or (s.count .. " missing it"))
                f.pulse:Stop(); f:SetAlpha(1)
            else
                f.border:SetColorTexture(1, 0.82, 0, 1)
                f.label:SetText("")
                f.pulse:Stop(); f:SetAlpha(1)
            end
            f:Show()
        else
            f.pulse:Stop()
            f:Hide()
        end
    end
    frame:SetShown(n > 0)
end

---------------------------------------------------------------------------
-- State and logic
---------------------------------------------------------------------------
local function Fighting()
    if UnitAffectingCombat("player") then return true end
    if not UnitExists("target") then return false end
    local ok, can = pcall(UnitCanAttack, "player", "target")
    if not ok or IsSecret(can) or not can then return false end
    local ok2, dead = pcall(UnitIsDead, "target")
    return not (ok2 and not IsSecret(dead) and dead)
end

local function OutAndAbout()
    if UnitOnTaxi and UnitOnTaxi("player") then return false end
    if db.quietRested and IsResting and IsResting() then return false end
    return true
end

-- how many party / raid members are missing a group buff (only read out of combat)
local NO_MANA = { WARRIOR = true, ROGUE = true, DEATHKNIGHT = true }
local function CountMissing(b)
    if not (IsInGroup and IsInGroup()) then return 0 end
    local raid = IsInRaid and IsInRaid()
    local total = raid and (GetNumGroupMembers and GetNumGroupMembers() or 0) or 4
    local n = 0
    for i = 1, total do
        local u = raid and ("raid" .. i) or ("party" .. i)
        if UnitExists(u) and not (UnitIsUnit and UnitIsUnit(u, "player")) then
            local okC, connected = pcall(UnitIsConnected, u)
            local okD, dead = pcall(UnitIsDeadOrGhost, u)
            local alive = not (okD and not IsSecret(dead) and dead)
            local online = not (okC and not IsSecret(connected) and connected == false)
            local near = true
            if UnitInRange then
                local okR, inRange, checked = pcall(UnitInRange, u)
                if okR and not IsSecret(inRange) and not IsSecret(checked) and checked and not inRange then near = false end
            end
            local needs = true
            if b.manaOnly then
                local okK, _, class = pcall(UnitClass, u)
                if okK and not IsSecret(class) and NO_MANA[class] then needs = false end
            end
            if needs and alive and online and near and ReadBuff(u, b.realNames) == false then n = n + 1 end
        end
    end
    return n
end

local wasUp = {}

local function Refresh(b)
    local st = state[b.key]
    local now = GetTime()
    local exp
    if b.consumable then
        exp = ReadMatch(b.match)
    elseif b.weapon then
        if b.weapon == "off" and not OffHandWeapon() then
            st.expires, st.skip = 0, true
            return
        end
        st.skip = false
        exp = ReadWeapon(b.weapon)
    else
        local e, dur = ReadBuff("player", b.realNames)
        exp = e
        if e == math.huge then
            db.durations[b.key] = 0  -- no timer (Aspects, auras)
        elseif e and dur and dur > 0 then
            db.durations[b.key] = dur
        end
    end
    if exp == false then
        st.expires = 0
    elseif exp then
        st.expires = exp
    end
    -- party members missing it (out of combat, every couple of seconds)
    if b.group and db.party and AurasReadable() then
        if now - (st.partyAt or 0) > 2 then
            st.partyAt = now
            st.missing = CountMissing(b)
        end
    elseif not AurasReadable() then
        -- in combat the count can't be checked; keep the last one
    else
        st.missing = 0
    end
end

local SAMPLE_KINDS = { "missing", "expiring", "party" }

local function Update()
    if not db then return end
    local shows = {}

    if unlocked or testMode then
        local list = {}
        for _, b in ipairs(buffs) do if not b.consumable then list[#list + 1] = b end end
        if #list == 0 then list = { buffs[1] } end
        for i, b in ipairs(list) do
            if b then
                local kind = SAMPLE_KINDS[(i - 1) % 3 + 1]
                shows[#shows + 1] = { b = b, kind = kind, remaining = 8, count = 2 }
            end
        end
        mover:SetShown(unlocked)
        frame:EnableMouse(unlocked)
        Draw(shows)
        return
    end
    mover:Hide()
    frame:EnableMouse(false)

    local dead = UnitIsDeadOrGhost("player")
    local fighting = Fighting()
    local about = OutAndAbout()
    local inCombat = UnitAffectingCombat("player")
    local now = GetTime()

    for _, b in ipairs(buffs) do
        local wanted
        if b.consumable then
            wanted = db.consumables and InInstance() and not inCombat
        else
            wanted = Enabled(b)
        end
        if wanted then
            Refresh(b)
            local st = state[b.key]
            local remaining = st.expires - now
            local up = remaining > 0
            if wasUp[b.key] and not up and inCombat and db.sound
                and PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
                PlaySound(SOUNDKIT.RAID_WARNING, "SFX")
            end
            wasUp[b.key] = up

            local when
            if b.when == "fight" then when = fighting else when = about or fighting end
            if not dead and not st.skip and when then
                local dur = db.durations[b.key] or 0
                local limit = (dur > 0 and dur < 600) and db.threshold or db.longThreshold
                if not up then
                    shows[#shows + 1] = { b = b, kind = "missing" }
                elseif remaining <= limit then
                    shows[#shows + 1] = { b = b, kind = "expiring", remaining = remaining }
                elseif b.group and db.party and (st.missing or 0) > 0 and not inCombat then
                    shows[#shows + 1] = { b = b, kind = "party", count = st.missing }
                end
            end
        end
    end
    Draw(shows)
end
ns.Update = Update

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")

local function SafeRegister(event, unit)
    if unit then
        return pcall(ev.RegisterUnitEvent, ev, event, unit)
    end
    return pcall(ev.RegisterEvent, ev, event)
end

SafeRegister("ADDON_LOADED")
SafeRegister("PLAYER_LOGIN")

-- casting one of your buffs restarts its timer, even in combat when buffs can't be read
local function OnCast(spellID)
    if IsSecret(spellID) then return end
    local name = SpellName(spellID)
    if not name then return end
    for _, b in ipairs(buffs) do
        if not b.consumable and not b.weapon then
            for _, n in ipairs(b.realNames) do
                if n == name then
                    local dur = db.durations[b.key] or (b.key == "shout" and 120) or 1800
                    state[b.key].expires = (dur == 0) and math.huge or (GetTime() + dur)
                    Update()
                    return
                end
            end
        end
    end
end

ev:SetScript("OnEvent", function(_, event, arg1, _, arg3)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        BattleShoutReminderDB = BattleShoutReminderDB or {}
        for k, v in pairs(defaults) do
            if BattleShoutReminderDB[k] == nil then
                if type(v) == "table" then
                    local copy = {}
                    for kk, vv in pairs(v) do copy[kk] = vv end
                    BattleShoutReminderDB[k] = copy
                else
                    BattleShoutReminderDB[k] = v
                end
            end
        end
        db = BattleShoutReminderDB
        -- 1.3.x kept Battle Shout's length in db.duration
        if db.duration and not db.durations.shout then db.durations.shout = db.duration end
        db.duration = nil
        if ns.StartVersionCheck then ns.StartVersionCheck(db, "Buff Notice") end
        ApplyLayout()

    elseif event == "PLAYER_LOGIN" then
        local _, class = UnitClass("player")
        playerClass = class
        Rebuild()
        ns.BuildOptions()
        SafeRegister("UNIT_SPELLCAST_SUCCEEDED", "player")
        SafeRegister("UNIT_AURA", "player")
        SafeRegister("UNIT_INVENTORY_CHANGED", "player")
        SafeRegister("PLAYER_REGEN_ENABLED")
        SafeRegister("PLAYER_REGEN_DISABLED")
        SafeRegister("PLAYER_TARGET_CHANGED")
        SafeRegister("PLAYER_DEAD")
        SafeRegister("SPELLS_CHANGED")
        SafeRegister("GROUP_ROSTER_UPDATE")
        SafeRegister("PLAYER_UPDATE_RESTING")
        C_Timer.NewTicker(0.5, Update)
        Update()

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnCast(arg3)

    elseif event == "SPELLS_CHANGED" then
        if playerClass then Rebuild() end
        Update()

    elseif event == "PLAYER_DEAD" then
        for _, st in pairs(state) do st.expires = 0 end
        Update()

    else
        Update()
    end
end)

---------------------------------------------------------------------------
-- Settings page (Options > AddOns) and slash command
---------------------------------------------------------------------------
local function SetUnlocked(v)
    unlocked = v
    Update()
end

local function SetTest(v)
    testMode = v
    Update()
end
ns.SetTest = SetTest

function ns.BuildOptions()
    local controls = {
        { type = "header", label = "Which buffs" },
    }
    local mine = ns.CLASS_BUFFS[playerClass] or {}
    if #mine == 0 then
        controls[#controls + 1] = { type = "info", height = 24, lines = function() return "|cff999999No class buffs for your class.|r" end }
    end
    for _, b in ipairs(mine) do
        controls[#controls + 1] = { type = "check", key = "on_" .. b.key,
            label = b.label:gsub("!$", "") .. (b.off and "  |cff999999(off unless you turn it on)|r" or "") }
    end
    controls[#controls + 1] = { type = "check", key = "party", label = "Show how many party and raid members are missing your group buffs" }
    controls[#controls + 1] = { type = "check", key = "consumables", label = "In dungeons and raids, remind me about food and a flask or elixir" }
    controls[#controls + 1] = { type = "header", label = "When" }
    controls[#controls + 1] = { type = "range", key = "threshold", label = "Short buffs: warn with this many seconds left", min = 0, max = 60, step = 5, suffix = "s" }
    controls[#controls + 1] = { type = "range", key = "longThreshold", label = "Long buffs: warn with this many seconds left", min = 0, max = 300, step = 30, suffix = "s" }
    controls[#controls + 1] = { type = "check", key = "quietRested", label = "No reminders in cities and inns" }
    controls[#controls + 1] = { type = "check", key = "sound", label = "Play a sound when a buff drops off in combat" }
    controls[#controls + 1] = { type = "header", label = "Icons" }
    controls[#controls + 1] = { type = "range", key = "size", label = "Icon size", min = 24, max = 120, step = 4 }
    controls[#controls + 1] = { type = "button", dynamicLabel = function() return unlocked and "Lock position" or "Unlock to move" end,
        label = "Unlock to move", func = function() SetUnlocked(not unlocked) end }
    controls[#controls + 1] = { type = "button", label = "Reset position", func = function() db.point = { unpack(defaults.point) }; ApplyLayout() end }
    controls[#controls + 1] = { type = "button", dynamicLabel = function() return testMode and "Stop test" or "Show test icons" end,
        label = "Show test icons", func = function() SetTest(not testMode) end }
    controls[#controls + 1] = { type = "info", height = 56, lines = function()
        return "|cff999999Red and pulsing: missing. Gold with seconds: running out. Blue with a number: that many party or raid members are missing your buff. "
            .. "Forever hides buffs in combat, so Buff Notice checks them out of combat and times them from your casts in between.|r" end }

    -- per-buff checkboxes live in db.on; mirror them as flat keys for the settings page
    local proxy = setmetatable({}, {
        __index = function(_, k)
            local key = type(k) == "string" and k:match("^on_(.+)$")
            if key then
                for _, b in ipairs(mine) do if b.key == key then return Enabled(b) end end
                return false
            end
            return db[k]
        end,
        __newindex = function(_, k, v)
            local key = type(k) == "string" and k:match("^on_(.+)$")
            if key then db.on[key] = v else db[k] = v end
        end,
    })

    ns.CreateOptions({
        title = "Buff Notice",
        updateNotice = true,
        changes = {
            { "2.0.1", "Food and flask checks no longer give up when the game hides one of your other buffs in combat" },
            { "2.0.0", "Now for every class: Arcane Intellect, Fortitude, Mark of the Wild, Blessings, armors, Aspects, poisons and more",
                       "Counts party and raid members missing your group buffs",
                       "Optional food and flask check in dungeons and raids. Renamed from Battle Shout Notice" },
            { "1.3.1", "This What's new list" },
            { "1.3.0", "Tells you when a newer version is out" },
        },
        icon = "Interface\\Icons\\Spell_Holy_WordFortitude",
        about = "Reminds you when your buffs are missing or running out",
        credit = "Created by Miff, supported by Claude",
        slash = "/bsn",
        db = proxy,
        onChange = function() ApplyLayout(); Update() end,
        controls = controls,
    })
end

function BattleShoutReminder_OnAddonCompartmentClick()
    if ns.OpenOptions then ns.OpenOptions() end
end

SLASH_BATTLESHOUTREMINDER1 = "/bsn"
SLASH_BATTLESHOUTREMINDER2 = "/bsr"
SLASH_BATTLESHOUTREMINDER3 = "/buffnotice"
SlashCmdList.BATTLESHOUTREMINDER = function(msg)
    local cmd, val = (msg or ""):lower():match("^(%S*)%s*(.-)$")
    local n = tonumber(val)

    if cmd == "" then
        ns.OpenOptions()
        return
    elseif cmd == "unlock" or cmd == "move" then
        SetUnlocked(true)
        Print("drag the icons where you want them, then /bsn lock")
    elseif cmd == "lock" then
        SetUnlocked(false)
        Print("locked")
    elseif cmd == "test" then
        SetTest(not testMode)
        Print("test icons " .. (testMode and "on" or "off"))
    elseif cmd == "time" and n then
        db.threshold = n
        Print("short buffs show when " .. n .. " seconds or fewer are left")
    elseif cmd == "size" and n then
        db.size = n
        Print("icon size " .. n)
    elseif cmd == "sound" then
        db.sound = not db.sound
        Print("sound " .. (db.sound and "on" or "off"))
    elseif cmd == "reset" then
        db.point = { unpack(defaults.point) }
        ApplyLayout()
        Print("position reset")
    elseif cmd == "list" then
        local names = {}
        for _, b in ipairs(buffs) do
            if not b.consumable then names[#names + 1] = b.label:gsub("!$", "") .. (Enabled(b) and "" or " (off)") end
        end
        Print(#names > 0 and ("watching: " .. table.concat(names, ", ")) or "no class buffs to watch on this character.")
    else
        Print("v" .. ns.version .. " commands (or just /bsn for the settings page):")
        Print("/bsn unlock, /bsn lock - move the icons")
        Print("/bsn test - show test icons")
        Print("/bsn list - the buffs it watches for you")
        Print("/bsn time <n> - short buffs: warn with this many seconds left (now " .. db.threshold .. ")")
        Print("/bsn size <n> - icon size (now " .. db.size .. ")")
        Print("/bsn sound - sound when a buff drops off in combat (now " .. (db.sound and "on" or "off") .. ")")
        Print("/bsn reset - put the icons back in the default spot")
    end
    Update()
    if ns.RefreshOptions then ns.RefreshOptions() end
end

-- Kick Tally: the abilities that stop an enemy's cast, by spell ID.
-- IDs come from WoW Forever's spell data (spells Forever didn't change keep their
-- Classic IDs). kind "kick" is a true interrupt; kind "stun" is a stun or fear that also
-- stops the cast, counted only when "Count stuns and fears too" is on.
-- The name is only a fallback: the game's own spell name is used when it can be read.

local _, ns = ...

-- Cooldowns (seconds) are the usual ones, shown on your row until Kick Tally has read the
-- real one from the game; 0 = not known until then.
local COOLDOWN = {
    Pummel = 10, ["Shield Bash"] = 12, Kick = 10, Counterspell = 24, ["Earth Shock"] = 6,
    ["Spell Lock"] = 24, ["Feral Charge"] = 15, Silence = 45, ["Skull Bash"] = 0, Rebuke = 0,
}

local list = {
    -- true interrupts
    { "kick", "Pummel",          6552, 6554 },
    { "kick", "Shield Bash",     72, 1671, 1672 },
    { "kick", "Kick",            1766, 1767, 1768, 1769 },
    { "kick", "Counterspell",    2139 },
    { "kick", "Earth Shock",     8042, 8044, 8045, 8046, 10412, 10413, 10414 },
    { "kick", "Spell Lock",      19244, 19647 },
    { "kick", "Feral Charge",    16979, 1238122 },
    { "kick", "Silence",         15487 },
    { "kick", "Skull Bash",      410176 },
    { "kick", "Rebuke",          425609 },
    -- stuns and fears that also stop a cast
    { "stun", "Hammer of Justice", 853, 5588, 5589, 10308 },
    { "stun", "Bash",            5211, 6798, 8983 },
    { "stun", "Concussion Blow", 12809 },
    { "stun", "Kidney Shot",     408, 8643 },
    { "stun", "Gouge",           1776, 1777, 8629, 11285, 11286 },
    { "stun", "Cheap Shot",      1833 },
    { "stun", "War Stomp",       20549 },
    { "stun", "Intimidation",    19577 },
    { "stun", "Scatter Shot",    19503 },
    { "stun", "Charge",          100, 6178, 11578 },
    { "stun", "Intercept",       20252, 20616, 20617 },
    { "stun", "Death Coil",      6789, 17925, 17926 },
    { "stun", "Intimidating Shout", 5246 },
    { "stun", "Psychic Scream",  8122, 8124, 10888, 10890 },
    { "stun", "Howl of Terror",  5484, 17928 },
}

ns.KICKS = {}
for _, row in ipairs(list) do
    for i = 3, #row do
        ns.KICKS[row[i]] = { kind = row[1], name = row[2], cd = COOLDOWN[row[2]] }
    end
end

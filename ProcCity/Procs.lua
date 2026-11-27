-- Proc City: what to watch for.
-- Each entry is a buff on you. Matching is by spell ID and by name, so a spell that
-- WoW Forever gave a new ID is still caught by its name. IDs are the ones Forever's
-- database lists (unchanged spells keep their Classic IDs).
--
--   key    unique id for settings
--   name   buff name in English (also matched against the game's own name for the ID)
--   ids    spell IDs of the buff (all ranks)
--   dur    seconds it lasts (nil = until used; the real duration is learned out of combat)
--   class  only for this class (nil = everyone)
--   cat    proc (talent procs), cooldown (buffs you cast), enchant (weapon enchants),
--          item (item procs), trinket (on-use items), racial
--   double can be up twice at once (one per weapon); the icon glows when it is
--   consume gone once you cast your next spell (Revelation)
--   items  item IDs of the weapon that gives it (Strength procs are only read from your
--          stats in combat while one of these is equipped)
--   stat    { stat index, amount } for Strength-style procs, read in combat from your stats
--   react   an ability that lights up after a dodge, parry or block (Reactive.lua), with
--           on = which of your own dodge / parry / block starts it, target = after your
--           target dodges, confirm = only when the game confirms it can be cast
--   glow    light this spell's buttons on your action bars while it's up (true = the entry's
--           own spell, or { name, ids } for another spell: Shadow Trance lights Shadow Bolt)

local _, ns = ...

ns.CATEGORIES = {
    { key = "proc",     label = "Class procs (Flurry, Clearcasting, Vengeance...)" },
    { key = "cooldown", label = "Class cooldowns you cast (Death Wish, Arcane Power...)" },
    { key = "enchant",  label = "Weapon enchants (Crusader, Insight, Revelation)" },
    { key = "item",     label = "Weapon and item procs" },
    { key = "trinket",  label = "On-use trinkets (any equipped trinket with a Use)" },
    { key = "racial",   label = "Racials (Blood Fury, Berserking...)" },
    { key = "reactive", label = "After a dodge, parry or block (Overpower, Revenge, Riposte, Counterattack, Mongoose Bite)" },
}

ns.PROCS = {
    ---------------------------------------------------------------- enchants
    { key = "holystrength", name = "Holy Strength", ids = { 20007 }, dur = 15, cat = "enchant",
      double = true, stat = { 1, 100 }, enchantID = 1900, note = "Crusader: +100 Strength", alias = "crusader" },
    -- New in WoW Forever. Their buff IDs aren't published yet, so these match by name
    -- and Proc City learns the real ID and duration the first time it sees them out of combat.
    { key = "insight", name = "Insight", ids = {}, dur = 10, cat = "enchant",
      icon = "Interface\\Icons\\Spell_Holy_MindVision", note = "Enchant Weapon - Insight: +100% Spirit" },
    { key = "revelation", name = "Revelation", ids = {}, dur = 15, cat = "enchant",
      icon = "Interface\\Icons\\Spell_Holy_SearingLight", consume = true, note = "Enchant Weapon - Revelation: next spell +100% crit" },

    ---------------------------------------------------------------- weapon procs
    -- Every WoW Forever weapon whose chance on hit (or Use) puts a buff on you, from
    -- Forever's item database. items = the weapons, so a Strength change in combat is
    -- only read as that proc while you have the weapon on.
    -- Strength
    { key = "destiny", name = "Destiny", ids = { 17152 }, dur = 12, cat = "item", items = { 647 },
      stat = { 1, 200 }, note = "Destiny: +200 Strength" },
    { key = "championstr", name = "Strength of the Champion", ids = { 16916 }, dur = 30, cat = "item",
      items = { 12790 }, stat = { 1, 120 }, note = "Arcanite Champion: +120 Strength" },
    { key = "malown", name = "Malown's Slam", ids = { 17500 }, dur = 20, cat = "item", items = { 13393 },
      stat = { 1, 53 }, note = "Malown's Slam: +53 Strength" },
    { key = "wane", name = "Wane", ids = {}, dur = 10, cat = "item", items = { 280080 },
      stat = { 1, 40 }, icon = "Interface\\Icons\\Spell_Nature_Strength", note = "Claymore of Two Moons: +40 Strength" },
    { key = "untamedfury", name = "Untamed Fury", ids = { 23719 }, dur = 8, cat = "item", items = { 19334 },
      stat = { 1, 300 }, note = "Untamed Blade: +300 Strength" },
    -- attack power and speed
    { key = "mcphaste", name = "Haste", ids = { 13494 }, dur = 30, cat = "item", items = { 9449 },
      note = "Manual Crowd Pummeler (Use): +50% attack speed" },
    { key = "haste", name = "Haste", ids = { 13533, 21165 }, dur = 10, cat = "item", items = { 9423, 17112 },
      note = "The Jackhammer: +15% attack speed" },
    { key = "ragehammer", name = "Enrage", ids = { 12686 }, dur = 15, cat = "item", items = { 10626 },
      note = "Ragehammer: +102 attack power, +6% attack speed" },
    { key = "lordgeneral", name = "Lord General's Sword", ids = { 15602 }, dur = 10, cat = "item", items = { 11817 },
      note = "+84 attack power" },
    { key = "argentavenger", name = "Argent Avenger", ids = { 17352 }, dur = 10, cat = "item", items = { 13246 },
      note = "+100 attack power (+100 more against Undead)" },
    { key = "zeal", name = "Zeal", ids = { 8191 }, dur = 15, cat = "item", items = { 6622 },
      note = "Sword of Zeal: +10 damage, +150 armor" },
    { key = "felstriker", name = "Felstriker", ids = { 16551 }, dur = 3, cat = "item", items = { 12590 },
      note = "Felstriker: 100% crit and hit" },
    { key = "ancestorsvengeance", name = "Ancestor's Vengeance", ids = { 16939 }, dur = 20, cat = "item", items = { 12802 },
      note = "Darkspear: +4% crit for the party" },
    { key = "spicy", name = "Spicy!", ids = { 434488 }, dur = 30, cat = "item", items = { 213105 },
      note = "Shawarmageddon (Use): melee hits add Fire damage" },
    { key = "bladestorm", name = "Bladestorm", ids = { 9632 }, dur = 9, cat = "item", items = { 7717 },
      note = "Ravager: spinning attack" },
    -- defensive
    { key = "sanctuary", name = "Sanctuary", ids = { 22850 }, dur = 10, cat = "item", items = { 18348 },
      note = "Quel'Serrar: +13 Defense, +300 armor, +30 attack power" },
    { key = "guardiansdurability", name = "Guardian's Durability", ids = { 1293345 }, dur = 12, cat = "item", items = { 273046 },
      note = "Guardian's Dualblade: +1080 armor" },
    { key = "jangthraze", name = "Jang'thraze", ids = { 11657 }, dur = 20, cat = "item", items = { 9380, 11086 },
      note = "Jang'thraze the Protector: physical damage shield" },
    { key = "deflecting", name = "Deflecting", ids = { 1294243 }, dur = 9, cat = "item", items = { 9379 },
      note = "Sang'thraze the Deflector: +2% parry" },
    { key = "basiliskskin", name = "Basilisk Skin", ids = { 10351 }, dur = 5, cat = "item", items = { 8223 },
      note = "Blade of the Basilisk: +48 Defense" },
    { key = "truesilver", name = "Holy Shield", ids = { 9800 }, dur = 60, cat = "item", items = { 7960 },
      note = "Truesilver Champion: damage shield" },
    { key = "flamewrath", name = "Flame Wrath", ids = { 16560 }, dur = 15, cat = "item", items = { 11809 },
      note = "Flame Wrath: fire shield" },
    { key = "giftofstone", name = "Gift of Stone", ids = { 16470 }, dur = 10, cat = "item", items = { 12532 },
      note = "Spire of the Stoneshaper (Use): +4000 armor" },
    { key = "reforgedspear", name = "Reforged Spear", ids = { 1297357 }, dur = 14, cat = "item", items = { 275645 },
      note = "heal over time" },
    { key = "julie", name = "Julie's Blessing", ids = { 8348 }, dur = 12, cat = "item", items = { 6660 },
      note = "Julie's Dagger: heal over time" },
    -- casters
    { key = "focus", name = "Focus", ids = { 18803 }, dur = 4, cat = "item", items = { 2243 }, consume = true,
      note = "Hand of Edward the Odd: next spell is instant" },
    { key = "witsend", name = "Wit's End", ids = { 1300140 }, dur = 15, cat = "item", items = { 276632 }, consume = true,
      note = "Wit's Edge: next damage spell costs no mana" },
    { key = "whiteobsidian", name = "White Obsidian", ids = { 1294058 }, dur = 10, cat = "item", items = { 274425 }, consume = true,
      note = "White Obsidian Wand: next spell costs less" },
    { key = "speed", name = "Speed", ids = { 22863 }, dur = 10, cat = "item", items = { 18410 },
      note = "Sprinter's Sword: +35% run speed" },

    ---------------------------------------------------------------- on-use trinkets
    -- Any equipped trinket with a Use is also picked up automatically; these just
    -- carry known durations so the first use already has a timer.
    { key = "kissspider", name = "Kiss of the Spider", ids = { 28866 }, dur = 15, cat = "trinket" },
    { key = "earthstrike", name = "Earthstrike", ids = { 25891 }, dur = 20, cat = "trinket" },
    { key = "diamondflask", name = "Diamond Flask", ids = { 24427 }, dur = 60, cat = "trinket" },
    { key = "jomgabbar", name = "Jom Gabbar", ids = { 29602 }, dur = 20, cat = "trinket" },
    { key = "swarmguard", name = "Badge of the Swarmguard", ids = { 26480 }, dur = 30, cat = "trinket" },
    { key = "slayerscrest", name = "Slayer's Crest", ids = { 28777 }, dur = 20, cat = "trinket" },
    { key = "restlessstrength", name = "Restless Strength", ids = { 24662 }, dur = 20, cat = "trinket" },
    { key = "unstablepower", name = "Unstable Power", ids = { 24658 }, dur = 20, cat = "trinket" },
    { key = "ephemeralpower", name = "Ephemeral Power", ids = { 23271 }, dur = 15, cat = "trinket" },
    { key = "mindquickening", name = "Mind Quickening", ids = { 23723 }, dur = 20, cat = "trinket" },
    { key = "burstofknowledge", name = "Burst of Knowledge", ids = { 15646 }, dur = 10, cat = "trinket" },
    { key = "secondwind", name = "Second Wind", ids = { 15604 }, dur = 10, cat = "trinket" },
    { key = "giftoflife", name = "Gift of Life", ids = { 23725 }, dur = 20, cat = "trinket" },
    { key = "devilsaurfury", name = "Devilsaur Fury", ids = { 24352 }, dur = 20, cat = "trinket" },
    { key = "massivedestruction", name = "Massive Destruction", ids = { 24543 }, dur = 20, cat = "trinket" },
    { key = "essencesapphiron", name = "Essence of Sapphiron", ids = { 28779 }, dur = 20, cat = "trinket" },

    ---------------------------------------------------------------- warrior
    { key = "flurry", name = "Flurry", ids = { 12966, 12967, 12968, 12969, 12970, 16257, 16277, 16278, 16279, 16280 },
      dur = 15, class = { WARRIOR = true, SHAMAN = true }, cat = "proc", note = "next 3 swings faster" },
    { key = "enrage", name = "Enrage", ids = { 12880, 14201, 14202, 14203, 14204 }, dur = 12,
      class = { WARRIOR = true }, cat = "proc" },
    { key = "deathwish", name = "Death Wish", ids = { 12328 }, dur = 30, class = { WARRIOR = true }, cat = "cooldown" },
    { key = "recklessness", name = "Recklessness", ids = { 1719 }, dur = 15, class = { WARRIOR = true }, cat = "cooldown" },
    { key = "sweeping", name = "Sweeping Strikes", ids = { 12292 }, dur = 20, class = { WARRIOR = true }, cat = "cooldown" },
    { key = "bloodrage", name = "Bloodrage", ids = { 29131 }, dur = 10, class = { WARRIOR = true }, cat = "cooldown" },
    { key = "berserkerrage", name = "Berserker Rage", ids = { 18499 }, dur = 10, class = { WARRIOR = true }, cat = "cooldown" },
    { key = "retaliation", name = "Retaliation", ids = { 20230 }, dur = 15, class = { WARRIOR = true }, cat = "cooldown" },
    { key = "laststand", name = "Last Stand", ids = { 12976 }, dur = 20, class = { WARRIOR = true }, cat = "cooldown" },
    { key = "shieldblock", name = "Shield Block", ids = { 2565 }, dur = 5, class = { WARRIOR = true }, cat = "cooldown" },

    ---------------------------------------------------------------- rogue
    { key = "adrenalinerush", name = "Adrenaline Rush", ids = { 13750 }, dur = 15, class = { ROGUE = true }, cat = "cooldown" },
    { key = "bladeflurry", name = "Blade Flurry", ids = { 13877 }, dur = 15, class = { ROGUE = true }, cat = "cooldown" },
    { key = "coldblood", name = "Cold Blood", ids = { 14177 }, class = { ROGUE = true }, cat = "cooldown" },
    { key = "remorseless", name = "Remorseless Attacks", ids = { 14143, 14149 }, dur = 20, class = { ROGUE = true }, cat = "proc" },

    ---------------------------------------------------------------- hunter
    { key = "quickshots", name = "Quick Shots", ids = { 6150 }, dur = 12, class = { HUNTER = true }, cat = "proc",
      note = "Improved Aspect of the Hawk" },
    { key = "rapidfire", name = "Rapid Fire", ids = { 3045 }, dur = 15, class = { HUNTER = true }, cat = "cooldown" },

    ---------------------------------------------------------------- mage
    { key = "clearcasting", name = "Clearcasting", ids = { 12536, 16246, 16870 }, dur = 15,
      class = { MAGE = true, SHAMAN = true, DRUID = true }, cat = "proc" },
    { key = "arcanepower", name = "Arcane Power", ids = { 12042 }, dur = 15, class = { MAGE = true }, cat = "cooldown" },
    { key = "combustion", name = "Combustion", ids = { 11129 }, class = { MAGE = true }, cat = "cooldown" },
    { key = "presenceofmind", name = "Presence of Mind", ids = { 12043 }, class = { MAGE = true }, cat = "cooldown" },

    ---------------------------------------------------------------- priest
    { key = "innerfocus", name = "Inner Focus", ids = { 14751 }, class = { PRIEST = true }, cat = "cooldown" },
    { key = "powerinfusion", name = "Power Infusion", ids = { 10060 }, dur = 15, cat = "cooldown" },
    { key = "spirittap", name = "Spirit Tap", ids = { 15271 }, dur = 15, class = { PRIEST = true }, cat = "proc" },

    ---------------------------------------------------------------- shaman
    { key = "elementalmastery", name = "Elemental Mastery", ids = { 16166 }, class = { SHAMAN = true }, cat = "cooldown" },
    { key = "naturesswiftness", name = "Nature's Swiftness", ids = { 16188, 17116 },
      class = { SHAMAN = true, DRUID = true }, cat = "cooldown" },

    ---------------------------------------------------------------- paladin
    { key = "vengeance", name = "Vengeance", ids = { 20050, 20052, 20053, 20054, 20055 }, dur = 30,
      class = { PALADIN = true }, cat = "proc", note = "up to 3 stacks on Forever" },
    { key = "redoubt", name = "Redoubt", ids = { 20128, 20131, 20132, 20133, 20134 }, dur = 10,
      class = { PALADIN = true }, cat = "proc" },
    { key = "divinefavor", name = "Divine Favor", ids = { 20216 }, class = { PALADIN = true }, cat = "cooldown" },
    { key = "holyshield", name = "Holy Shield", ids = { 20925, 20927, 20928 }, dur = 10, class = { PALADIN = true }, cat = "cooldown" },

    ---------------------------------------------------------------- druid
    { key = "naturesgrace", name = "Nature's Grace", ids = { 16886 }, dur = 15, class = { DRUID = true }, cat = "proc" },
    { key = "tigersfury", name = "Tiger's Fury", ids = { 5217, 6793, 9845, 9846 }, dur = 6, class = { DRUID = true }, cat = "cooldown" },
    { key = "innervate", name = "Innervate", ids = { 29166 }, dur = 20, cat = "cooldown" },

    ---------------------------------------------------------------- warlock
    { key = "shadowtrance", name = "Shadow Trance", ids = { 17941 }, dur = 10, class = { WARLOCK = true }, cat = "proc",
      note = "Nightfall: instant Shadow Bolt",
      glow = { name = "Shadow Bolt", ids = { 686, 695, 705, 1088, 1106, 7641, 11659, 11660, 11661, 25307 } } },
    { key = "amplifycurse", name = "Amplify Curse", ids = { 18288 }, dur = 30, class = { WARLOCK = true }, cat = "cooldown" },

    ---------------------------------------------------------------- after a dodge, parry or block
    -- These are abilities, not buffs: Reactive.lua (and Overpower.lua for Overpower) starts
    -- them, so they're left out of the buff lookups.
    { key = "overpower", name = "Overpower", ids = { 7384, 7887, 11584, 11585 }, dur = 5,
      class = { WARRIOR = true }, cat = "reactive", react = true, glow = true,
      note = "after a mob dodges you; also marked on that mob's nameplate" },
    { key = "revenge", name = "Revenge", ids = { 6572, 6574, 7379, 11600, 11601, 25288 }, dur = 5,
      class = { WARRIOR = true }, cat = "reactive", react = true, glow = true,
      on = { BLOCK = true, DODGE = true, PARRY = true }, note = "after you block, dodge or parry" },
    { key = "riposte", name = "Riposte", ids = { 14251 }, dur = 5,
      class = { ROGUE = true }, cat = "reactive", react = true, glow = true,
      on = { PARRY = true }, note = "after you parry" },
    { key = "counterattack", name = "Counterattack", ids = { 19306, 20909, 20910 }, dur = 5,
      class = { HUNTER = true }, cat = "reactive", react = true, glow = true,
      on = { PARRY = true }, note = "after you parry" },
    { key = "mongoose", name = "Mongoose Bite", ids = { 1495, 14269, 14270, 14271 }, dur = 5,
      class = { HUNTER = true }, cat = "reactive", react = true, glow = true,
      target = true, confirm = true, note = "after your target dodges" },

    ---------------------------------------------------------------- racials
    { key = "bloodfury", name = "Blood Fury", ids = { 20572 }, dur = 15, cat = "racial" },
    { key = "berserking", name = "Berserking", ids = { 26296, 26297, 20554 }, dur = 10, cat = "racial" },
    { key = "perception", name = "Perception", ids = { 20600 }, dur = 20, cat = "racial" },
    { key = "stoneform", name = "Stoneform", ids = { 20594 }, dur = 8, cat = "racial" },
}

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
--   stat    { stat index, amount } for Strength-style procs, read in combat from your stats

local _, ns = ...

ns.CATEGORIES = {
    { key = "proc",     label = "Class procs (Flurry, Clearcasting, Vengeance...)" },
    { key = "cooldown", label = "Class cooldowns you cast (Death Wish, Arcane Power...)" },
    { key = "enchant",  label = "Weapon enchants (Crusader)" },
    { key = "item",     label = "Weapon and item procs" },
    { key = "trinket",  label = "On-use trinkets (any equipped trinket with a Use)" },
    { key = "racial",   label = "Racials (Blood Fury, Berserking...)" },
}

ns.PROCS = {
    ---------------------------------------------------------------- enchants
    { key = "holystrength", name = "Holy Strength", ids = { 20007 }, dur = 15, cat = "enchant",
      double = true, stat = { 1, 100 }, enchantID = 1900, note = "Crusader: +100 Strength" },

    ---------------------------------------------------------------- item procs
    { key = "untamedfury", name = "Untamed Fury", ids = { 23719 }, dur = 8, cat = "item",
      stat = { 1, 300 }, note = "Untamed Blade: +300 Strength" },
    { key = "felstriker", name = "Felstriker", ids = { 16551 }, dur = 3, cat = "item",
      note = "Felstriker: 100% crit and hit" },
    { key = "haste", name = "Haste", ids = { 21165, 13494 }, dur = 10, cat = "item",
      note = "Empyrean Demolisher / Manual Crowd Pummeler" },

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
      note = "Nightfall: instant Shadow Bolt" },
    { key = "amplifycurse", name = "Amplify Curse", ids = { 18288 }, dur = 30, class = { WARLOCK = true }, cat = "cooldown" },

    ---------------------------------------------------------------- racials
    { key = "bloodfury", name = "Blood Fury", ids = { 20572 }, dur = 15, cat = "racial" },
    { key = "berserking", name = "Berserking", ids = { 26296, 26297, 20554 }, dur = 10, cat = "racial" },
    { key = "perception", name = "Perception", ids = { 20600 }, dur = 20, cat = "racial" },
    { key = "stoneform", name = "Stoneform", ids = { 20594 }, dur = 8, cat = "racial" },
}

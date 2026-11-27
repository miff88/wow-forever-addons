-- Craft Services: word lists and profession data.

local ADDON_NAME, ns = ...

---------------------------------------------------------------------------
-- Professions
--   key      saved settings and recipe book use this
--   name     the profession's name in game (also the spell that opens its window)
--   who      what you call someone with it, with "a"/"an"
--   words    what people type when they want one ("LF enchanter", "need a BS")
--   skill    the game's skill line ID
---------------------------------------------------------------------------
ns.PROFS = {
    { key = "enchanting", name = "Enchanting", who = "an enchanter", short = "Enchanter",
      icon = "Interface\\Icons\\Trade_Engraving", skill = 333,
      words = { "enchanter", "enchanters", "enchanting", "enchant", "enchants", "chanter", "ench", "enchy" } },
    { key = "blacksmithing", name = "Blacksmithing", who = "a blacksmith", short = "Blacksmith",
      icon = "Interface\\Icons\\Trade_BlackSmithing", skill = 164,
      words = { "blacksmith", "blacksmiths", "blacksmithing", "bs", "smith", "smithing", "armorsmith", "weaponsmith" } },
    { key = "leatherworking", name = "Leatherworking", who = "a leatherworker", short = "Leatherworker",
      icon = "Interface\\Icons\\Trade_LeatherWorking", skill = 165,
      words = { "leatherworker", "leatherworkers", "leatherworking", "lw", "leatherwork" } },
    { key = "tailoring", name = "Tailoring", who = "a tailor", short = "Tailor",
      icon = "Interface\\Icons\\Trade_Tailoring", skill = 197,
      words = { "tailor", "tailors", "tailoring" } },
    { key = "alchemy", name = "Alchemy", who = "an alchemist", short = "Alchemist",
      icon = "Interface\\Icons\\Trade_Alchemy", skill = 171,
      words = { "alchemist", "alchemists", "alchemy", "alch", "alchy", "transmute", "transmutes", "xmute", "transmuter" } },
    { key = "engineering", name = "Engineering", who = "an engineer", short = "Engineer",
      icon = "Interface\\Icons\\Trade_Engineering", skill = 202,
      words = { "engineer", "engineers", "engineering", "engi", "engy", "engie" } },
    { key = "jewelcrafting", name = "Jewelcrafting", who = "a jewelcrafter", short = "Jewelcrafter",
      icon = "Interface\\Icons\\INV_Misc_Gem_01", skill = 755,
      words = { "jewelcrafter", "jewelcrafting", "jc", "jeweler" } },
    { key = "inscription", name = "Inscription", who = "a scribe", short = "Scribe",
      icon = "Interface\\Icons\\INV_Inscription_Tradeskill01", skill = 773,
      words = { "scribe", "inscription", "inscriptionist" } },
    { key = "cooking", name = "Cooking", who = "a cook", short = "Cook",
      icon = "Interface\\Icons\\INV_Misc_Food_15", skill = 185,
      words = { "cook", "cooking", "chef" } },
    { key = "firstaid", name = "First Aid", who = "someone with First Aid", short = "First Aid",
      icon = "Interface\\Icons\\Spell_Holy_SealOfSacrifice", skill = 129,
      words = { "first aid", "bandage", "bandages" } },
    -- not a profession, but the same kind of service: rogues open lockboxes
    { key = "lockpicking", name = "Lockpicking", who = "a rogue", short = "Lockpicker",
      icon = "Interface\\Icons\\Spell_Nature_MoonKey", skill = 633, spell = "Pick Lock", spellID = 1804,
      words = { "lockpick", "lockpicking", "lockpicker", "lockbox", "lockboxes", "lock box", "pick lock",
                "picklock", "junkbox", "junk box", "open box", "open my box", "lockpic" } },
}

ns.PROF_BY_KEY = {}
ns.PROF_BY_NAME = {}
ns.PROF_BY_SKILL = {}
for _, p in ipairs(ns.PROFS) do
    ns.PROF_BY_KEY[p.key] = p
    ns.PROF_BY_NAME[p.name:lower()] = p
    ns.PROF_BY_SKILL[p.skill] = p
end

---------------------------------------------------------------------------
-- Request words
---------------------------------------------------------------------------
-- words that make it a request rather than a statement
ns.ASK_WORDS = { "lf", "lfm", "wtb", "need", "needs", "needed", "buy", "buying", "any", "anyone", "anybody",
                 "someone", "somebody", "plz", "pls", "please", "can", "who", "looking", "lookin", "want", "wanting" }
-- words that mean it's another crafter advertising, not a customer
ns.SELL_WORDS = { "wts", "selling", "sell", "offering", "lfw", "customers", "taking orders", "your mats",
                  "ur mats", "free enchants", "tips appreciated", "can craft", "can make", "i can do", "i craft" }

-- who brings the materials
ns.THEIR_MATS = { "have mats", "got mats", "my mats", "own mats", "w mats", "with mats", "i have the mats",
                  "have the mats", "have all mats", "mats ready", "i have mats", "bring mats", "providing mats" }
ns.YOUR_MATS  = { "no mats", "need mats", "without mats", "w o mats", "dont have mats", "don't have mats",
                  "your mats", "ur mats", "you have mats", "u have mats", "with your mats", "with ur mats",
                  "you supply mats", "you provide mats", "and mats" }

---------------------------------------------------------------------------
-- Enchanting: slots and stats people type, matched against your enchant recipes
---------------------------------------------------------------------------
-- slot words -> the slot part of the recipe name ("Enchant Boots - Minor Speed")
ns.ENCHANT_SLOTS = {
    weapon = "Weapon", wep = "Weapon", weap = "Weapon", wpn = "Weapon", ["1h"] = "Weapon", mh = "Weapon",
    oh = "Weapon", dagger = "Weapon", sword = "Weapon", mace = "Weapon", axe = "Weapon",
    ["2h"] = "2H Weapon", ["2hand"] = "2H Weapon", ["2hander"] = "2H Weapon", twohand = "2H Weapon",
    twohander = "2H Weapon", staff = "2H Weapon",
    chest = "Chest", robe = "Chest",
    boots = "Boots", boot = "Boots", feet = "Boots",
    gloves = "Gloves", glove = "Gloves", hands = "Gloves", gauntlets = "Gloves",
    bracer = "Bracer", bracers = "Bracer", wrist = "Bracer", wrists = "Bracer", bracelet = "Bracer",
    cloak = "Cloak", back = "Cloak", cape = "Cloak",
    shield = "Shield", sheild = "Shield", offhand = "Shield",
}

-- stat words -> words found in recipe names or descriptions
ns.ENCHANT_STATS = {
    agi = "agility", agil = "agility", agility = "agility",
    str = "strength", strength = "strength",
    sta = "stamina", stam = "stamina", stamina = "stamina",
    int = "intellect", intel = "intellect", intellect = "intellect",
    spi = "spirit", spirit = "spirit",
    stats = "stats", stat = "stats",
    hp = "health", health = "health",
    mana = "mana",
    dmg = "damage", damage = "damage", striking = "striking", impact = "impact",
    def = "defense", defense = "defense", armor = "armor", armour = "armor",
    resist = "resistance", res = "resistance", resistance = "resistance",
    heal = "healing", healing = "healing", heals = "healing",
    sp = "spell", spellpower = "spell", spelldmg = "spell",
    speed = "speed", run = "speed", runspeed = "speed",
    haste = "haste", mp5 = "regeneration", regen = "regeneration",
    riding = "riding", mount = "riding",
    fr = "fire", fire = "fire", frost = "frost", shadow = "shadow", nature = "nature", arcane = "arcane",
    skinning = "skinning", mining = "mining", herbalism = "herbalism", fishing = "fishing",
    block = "block", parry = "parry", dodge = "dodge",
}

-- words that only tell tiers apart; the number someone types does that better
ns.ENCHANT_TIERS = { minor = true, lesser = true, greater = true, superior = true, major = true, mighty = true }

---------------------------------------------------------------------------
-- Cities, for "where are you" (same as Mage Services)
---------------------------------------------------------------------------
ns.DESTINATIONS = {
    Horde = {
        { name = "Orgrimmar", aliases = { "org", "orgri", "ogri", "orgrimmar", "ogrimmar" } },
        { name = "Undercity", aliases = { "uc", "undercity", "under city" } },
        { name = "Thunder Bluff", aliases = { "tb", "thunderbluff", "thunder bluff", "bluff" } },
    },
    Alliance = {
        { name = "Stormwind", aliases = { "sw", "stormwind", "storm wind" } },
        { name = "Ironforge", aliases = { "ironforge", "iron forge", { word = "if", strict = true } } },
        { name = "Darnassus", aliases = { "darn", "darna", "darnassus", "darnasus" } },
    },
}

ns.ICONS = {
    custom = "Interface\\Icons\\INV_Misc_Note_01",
    craft  = "Interface\\Icons\\Trade_BlackSmithing",
}

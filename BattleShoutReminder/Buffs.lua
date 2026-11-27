-- Buff Notice: the buffs each class keeps up, by spell ID (spells WoW Forever didn't change
-- keep their Classic IDs). The names are fallbacks; the game's own names are used when it
-- has them, so any rank of a spell matches.
--
-- Fields:
--   key      saved settings key
--   ids      spell IDs: knowing any of them means you can cast it; any of their buffs counts
--   names    fallback buff names, same order as ids
--   label    what the icon says when it's missing
--   when     "fight": only while fighting (Battle Shout); default: whenever you're out and about
--   group    also count party and raid members who are missing it
--   manaOnly when counting the group, skip warriors and rogues (Intellect, Spirit)
--   weapon   "main" / "off": a temporary weapon enchant (poisons, imbues) instead of a buff
--   off      not reminded unless turned on (situational buffs)

local _, ns = ...

ns.CLASS_BUFFS = {
    WARRIOR = {
        { key = "shout", ids = { 6673 }, names = { "Battle Shout" }, label = "Battle Shout!", when = "fight" },
    },
    MAGE = {
        { key = "intellect", ids = { 1459, 23028 }, names = { "Arcane Intellect", "Arcane Brilliance" },
          label = "Arcane Intellect", group = true, manaOnly = true },
        { key = "armor", ids = { 168, 7302, 6117 }, names = { "Frost Armor", "Ice Armor", "Mage Armor" },
          label = "Armor" },
    },
    PRIEST = {
        { key = "fortitude", ids = { 1243, 21562 }, names = { "Power Word: Fortitude", "Prayer of Fortitude" },
          label = "Fortitude", group = true },
        { key = "innerfire", ids = { 588 }, names = { "Inner Fire" }, label = "Inner Fire" },
        { key = "spirit", ids = { 14752, 27681 }, names = { "Divine Spirit", "Prayer of Spirit" },
          label = "Divine Spirit", group = true, manaOnly = true },
    },
    DRUID = {
        { key = "wild", ids = { 1126, 21849 }, names = { "Mark of the Wild", "Gift of the Wild" },
          label = "Mark of the Wild", group = true },
        { key = "omen", ids = { 16864 }, names = { "Omen of Clarity" }, label = "Omen of Clarity" },
        { key = "thorns", ids = { 467 }, names = { "Thorns" }, label = "Thorns", off = true },
    },
    PALADIN = {
        { key = "blessing",
          ids = { 19740, 19742, 20217, 1038, 19977, 20911, 25782, 25894, 25898, 25895, 25890, 25899 },
          names = { "Blessing of Might", "Blessing of Wisdom", "Blessing of Kings", "Blessing of Salvation",
                    "Blessing of Light", "Blessing of Sanctuary", "Greater Blessing of Might",
                    "Greater Blessing of Wisdom", "Greater Blessing of Kings", "Greater Blessing of Salvation",
                    "Greater Blessing of Light", "Greater Blessing of Sanctuary" },
          label = "Blessing" },
        { key = "fury", ids = { 25780 }, names = { "Righteous Fury" }, label = "Righteous Fury", off = true },
    },
    WARLOCK = {
        { key = "armor", ids = { 687, 706 }, names = { "Demon Skin", "Demon Armor" }, label = "Demon Armor" },
    },
    SHAMAN = {
        { key = "shield", ids = { 324 }, names = { "Lightning Shield" }, label = "Lightning Shield" },
        { key = "imbue", ids = { 8017, 8024, 8033, 8232 },
          names = { "Rockbiter Weapon", "Flametongue Weapon", "Frostbrand Weapon", "Windfury Weapon" },
          label = "Weapon imbue", weapon = "main" },
    },
    HUNTER = {
        { key = "aspect", ids = { 13165, 13163, 5118, 13159, 20043, 13161 },
          names = { "Aspect of the Hawk", "Aspect of the Monkey", "Aspect of the Cheetah", "Aspect of the Pack",
                    "Aspect of the Wild", "Aspect of the Beast" },
          label = "Aspect" },
        { key = "trueshot", ids = { 19506 }, names = { "Trueshot Aura" }, label = "Trueshot Aura" },
    },
    ROGUE = {
        { key = "poisonMain", ids = { 2842 }, names = { "Poisons" }, label = "Main-hand poison", weapon = "main",
          icon = "Interface\\Icons\\Ability_Poisons" },
        { key = "poisonOff", ids = { 2842 }, names = { "Poisons" }, label = "Off-hand poison", weapon = "off",
          icon = "Interface\\Icons\\Ability_Poisons" },
    },
}

-- dungeons and raids: food and a flask or elixir (off unless turned on)
ns.CONSUMABLES = {
    { key = "food", label = "Well Fed", match = { "Well Fed" }, icon = "Interface\\Icons\\INV_Misc_Food_14" },
    { key = "flask", label = "Flask / elixir", match = { "Flask", "Elixir" }, icon = "Interface\\Icons\\INV_Potion_97" },
}

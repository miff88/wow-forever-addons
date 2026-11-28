-- Proc City: the abilities it watches for.
-- These are abilities that light up for a few seconds after something happens in a fight
-- (a dodge, a parry, a block, a kill). The game still tells addons about these in combat,
-- unlike your buffs, which WoW Forever hides from addons in combat. For buff procs
-- (Flurry, Enrage, Clearcasting...) use the game's own Cooldown Manager.
--
--   key     unique id for settings
--   name    the ability's name in English
--   ids     spell IDs (all ranks)
--   dur     seconds it stays usable
--   class   only for this class
--   on      which of your own dodge / parry / block starts it (Reactive.lua)
--   target  after your target dodges
--   confirm only show it when the game confirms it can be cast
--   poll    starts when the game says it has become castable (Victory Rush after a kill)
--   glow    light this ability's buttons on your action bars while it's up
--   note    shown in the settings list

local _, ns = ...

ns.CATEGORIES = {
    { key = "reactive", label = "Abilities after a dodge, parry, block or kill" },
}

ns.PROCS = {
    { key = "overpower", name = "Overpower", ids = { 7384, 7887, 11584, 11585 }, dur = 5,
      class = { WARRIOR = true }, cat = "reactive", react = true, glow = true,
      note = "after a mob dodges you; also marked on that mob's nameplate" },
    { key = "revenge", name = "Revenge", ids = { 6572, 6574, 7379, 11600, 11601, 25288 }, dur = 5,
      class = { WARRIOR = true }, cat = "reactive", react = true, glow = true,
      on = { BLOCK = true, DODGE = true, PARRY = true }, note = "after you block, dodge or parry" },
    { key = "victoryrush", name = "Victory Rush", ids = { 402927, 34428 }, dur = 20,
      class = { WARRIOR = true }, cat = "reactive", react = true, glow = true, poll = true,
      note = "after you kill something" },
    { key = "riposte", name = "Riposte", ids = { 14251 }, dur = 5,
      class = { ROGUE = true }, cat = "reactive", react = true, glow = true,
      on = { PARRY = true }, note = "after you parry" },
    { key = "counterattack", name = "Counterattack", ids = { 19306, 20909, 20910 }, dur = 5,
      class = { HUNTER = true }, cat = "reactive", react = true, glow = true,
      on = { PARRY = true }, note = "after you parry" },
    { key = "mongoose", name = "Mongoose Bite", ids = { 1495, 14269, 14270, 14271 }, dur = 5,
      class = { HUNTER = true }, cat = "reactive", react = true, glow = true,
      target = true, confirm = true, note = "after your target dodges" },
}

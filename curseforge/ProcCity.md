# Proc City

**See your procs the moment they happen.** Proc City shows your procs and short buffs as a movable row of icons with the time left on each: Flurry, Crusader, Clearcasting, Vengeance, Shadow Trance, trinkets, and now Overpower, Revenge and Riposte too.

Made for **World of Warcraft: Forever**. Every class.

## Features

### Every class
- Talent procs: Flurry, Enrage, Clearcasting, Vengeance, Nature's Grace, Shadow Trance, Quick Shots, Spirit Tap, Remorseless Attacks, Redoubt.
- Class cooldowns you cast: Death Wish, Recklessness, Arcane Power, Adrenaline Rush, Rapid Fire, Inner Focus, Elemental Mastery, Divine Favor, Tiger's Fury and more.
- Crusader (Holy Strength), the new Forever enchants Insight and Revelation, and every Forever weapon that buffs you on hit or on use (Destiny, Arcanite Champion, Claymore of Two Moons, Ragehammer, Quel'Serrar, Hand of Edward the Odd and more), and racials (Blood Fury, Berserking, Perception, Stoneform).
- **Any equipped trinket with a Use** is picked up automatically, including Forever's new trinkets.

### After a dodge, parry or block (formerly Proc Plates)
- **Warriors:** Overpower when a mob dodges you, and Revenge after you block, dodge or parry.
- **Rogues:** Riposte after you parry. **Hunters:** Counterattack after you parry, and Mongoose Bite after your target dodges.
- They join the row for their 5 second window, and their buttons glow on your action bars (Blizzard bars, Bartender4, ElvUI and Dominos).
- **Overpower on the right mob:** an Overpower icon also sits above the nameplate of the mob that dodged you, including Whirlwind and Cleave dodges on mobs you aren't targeting. Dodges against other players are ignored.
- Revenge, Riposte and the hunter ones only show while the game says you can cast them, and go away once you use them.
- Coming from Proc Plates or Overpower Plates? Proc City brings your settings over, and Proc Plates steps aside once Proc City is installed.

### Clear at a glance
- Icons grow to the right or left as procs happen, with the seconds left and an optional clock sweep.
- **Crusader on both weapons:** when both proc at once, the icon glows.
- **Pinned procs:** pin the procs you build around and they keep their place, shown as a faint grey icon while they're down. Spot a missing Flurry or Crusader as easily as a running one. By default the grey icons only show in combat.
- **Starter pins:** the first time each class logs in, the procs it usually builds around are pinned for you, if you have them (warriors get Overpower, Flurry and Crusader). Unpin any you don't want.
- **Button glow:** your Overpower, Revenge, Riposte, Counterattack and Mongoose Bite buttons light up while they're usable, and Shadow Bolt lights up during Shadow Trance.
- Stack counts, an optional sound, and adjustable icon size and gap.

### Easy to set up
- Drag it anywhere, and test mode shows sample icons.
- Turn whole groups or single procs off.
- Settings page under Options > AddOns, with an entry on the minimap's addon button.

## Commands

| Command | What it does |
|---|---|
| `/proc` | Open settings |
| `/proc test` | Show test icons |
| `/proc move` / `/proc lock` | Move the icons |
| `/proc grow left` or `right` | Which way the icons grow |
| `/proc list` | What's tracked for your class |
| `/proc off <name>` / `/proc on <name>` | Hide or show one proc |
| `/proc pin <name>` / `/proc unpin <name>` | Keep a proc on screen, greyed out while it's down |
| `/proc glow` | Turn the action button glow on or off |
| `/proc plates` | Turn the Overpower nameplate icon on or off (warriors) |
| `/proc debug` | Print what Proc City sees in combat |

## Good to know
- WoW Forever hides buff details from addons during combat. Out of combat Proc City reads your buffs exactly and learns their real durations. In combat it works from your own casts, your Strength and the game's combat text, then corrects itself when combat ends.

Created by Miff, supported by Claude. Source and changelog: [github.com/miff88/wow-forever-addons](https://github.com/miff88/wow-forever-addons)

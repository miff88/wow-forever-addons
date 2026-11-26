# Proc City

**See your procs the moment they happen.** Proc City shows your procs and short buffs as a movable row of icons with the time left on each: Flurry, Crusader, Clearcasting, Vengeance, Shadow Trance, trinkets and more.

Made for **World of Warcraft: Forever**. Every class.

## Features

### Every class
- Talent procs: Flurry, Enrage, Clearcasting, Vengeance, Nature's Grace, Shadow Trance, Quick Shots, Spirit Tap, Remorseless Attacks, Redoubt.
- Class cooldowns you cast: Death Wish, Recklessness, Arcane Power, Adrenaline Rush, Rapid Fire, Inner Focus, Elemental Mastery, Divine Favor, Tiger's Fury and more.
- Crusader (Holy Strength), weapon procs and racials (Blood Fury, Berserking, Perception, Stoneform).
- **Any equipped trinket with a Use** is picked up automatically, including Forever's new trinkets.

### Clear at a glance
- Icons grow to the right or left as procs happen, with the seconds left and an optional clock sweep.
- **Crusader on both weapons:** when both proc at once, the icon glows.
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
| `/proc debug` | Print what Proc City sees in combat |

## Good to know
- WoW Forever hides buff details from addons during combat. Out of combat Proc City reads your buffs exactly and learns their real durations. In combat it works from your own casts, your Strength and the game's combat text, then corrects itself when combat ends.

Created by Miff, supported by Claude. Source and changelog: [github.com/miff88/wow-forever-addons](https://github.com/miff88/wow-forever-addons)

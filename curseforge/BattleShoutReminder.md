# Buff Notice

**Never pull without your buffs again.** Buff Notice (formerly Battle Shout Notice) shows an icon when a buff your class keeps up is missing or about to run out, and tells you how many of your group are missing the buffs you hand out.

Made for **World of Warcraft: Forever**. Every class.

## Features

### Your class's buffs
- **Warrior:** Battle Shout, while you're fighting, exactly as before.
- **Mage:** Arcane Intellect, and Frost, Ice or Mage Armor.
- **Priest:** Power Word: Fortitude, Inner Fire, Divine Spirit.
- **Druid:** Mark of the Wild, Omen of Clarity, Thorns (off unless you turn it on).
- **Paladin:** a Blessing, Righteous Fury (off unless you turn it on).
- **Warlock:** Demon Skin or Demon Armor.
- **Shaman:** Lightning Shield and a weapon imbue.
- **Hunter:** an Aspect, Trueshot Aura.
- **Rogue:** poison on your main hand and off hand.
- Only buffs you've learned are watched, and each one can be turned off.

### Your group
- For group buffs (Intellect, Fortitude, Spirit, Mark of the Wild) the icon shows how many nearby party or raid members are missing yours.
- Intellect and Spirit skip warriors and rogues, who don't use mana.

### Food and flasks
- Optional: in dungeons and raids, a reminder when you're not Well Fed or have no flask or elixir.

### Shows up when it matters
- Red and pulsing when a buff is missing, gold with a countdown when it's running out.
- Short buffs warn at 10 seconds, long ones at 60. Both are adjustable.
- A sound when a buff drops off in combat.
- Quiet in cities and inns, on flight paths and while you're dead.

### Easy to set up
- Full settings page under Options > AddOns, with an entry on the minimap's addon button.
- Drag the icons anywhere on screen and change their size. Test mode shows sample icons so you can place them.
- Tells you when a newer version is out.

## Commands

| Command | What it does |
|---|---|
| `/bsn` | Open settings (`/bsr` and `/buffnotice` work too) |
| `/bsn unlock` / `/bsn lock` | Move the icons |
| `/bsn test` | Show sample icons |
| `/bsn list` | The buffs it's watching on this character |
| `/bsn time <n>` | Short buffs: warn when this many seconds are left |
| `/bsn size <n>` | Icon size |
| `/bsn sound` | Turn the sound on or off |
| `/bsn reset` | Put the icons back in their default spot |
| `/bsn help` | All commands |

## Good to know
- WoW Forever hides buff details from addons during combat. Buff Notice checks your real buffs whenever you're out of combat, and times them from your own casts in between.
- Because of that, a buff someone else puts on you during a fight is only picked up once combat ends, and the group count is only updated out of combat.
- Upgrading from Battle Shout Notice keeps your settings and icon position.

## More WoW Forever addons
- **[Proc City](https://www.curseforge.com/wow/addons/proc-city)**: Overpower on the mob that dodged you, plus Revenge, Victory Rush, Riposte, Counterattack and Mongoose Bite, with their buttons lit.
- **[Mage Services](https://www.curseforge.com/wow/addons/mage-services)**: catches portal, food and water requests in chat, with one-click invite, whisper and portal.
- **[Kick Tally](https://www.curseforge.com/wow/addons/kick-tally)**: announces your successful interrupts and counts your group's kicks.
- **[Kill Clock](https://www.curseforge.com/wow/addons/kill-clock)**: how long until your target dies, and until it reaches execute range.
- **[Plate Threat](https://www.curseforge.com/wow/addons/plate-threat)**: your threat on every enemy nameplate, with a warning before you pull aggro.
- **[Target Arrow](https://www.curseforge.com/wow/addons/target-arrow)**: an arrow over your target so you can find it in any crowd.

Created by Miff, supported by Claude. Source and changelog: [github.com/miff88/wow-forever-addons](https://github.com/miff88/wow-forever-addons)

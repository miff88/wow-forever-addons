# Battle Shout Notice

**Never fight without Battle Shout again.** Battle Shout Notice shows a Battle Shout icon when the buff is missing or about to run out while you're fighting, with a countdown and a sound when it drops off.

Made for **World of Warcraft: Forever**. Warrior only.

## Features

### Shows up when it matters
- Appears while you're in combat or targeting an enemy, once Battle Shout has 10 seconds or less left. The warning time is adjustable.
- Counts down the last seconds on the icon.
- When the buff runs out, the icon flashes with "Battle Shout!" underneath and plays a sound if you're in combat.
- Disappears as soon as you shout, and stays out of the way the rest of the time.

### Your layout
- Drag the icon anywhere on screen, and change its size.
- Sound on or off.
- Does nothing on your other classes.

### Easy to set up
- Full settings page under Options > AddOns, with an entry on the minimap's addon button.
- Test mode shows the icon so you can place it.

## Commands

| Command | What it does |
|---|---|
| `/bsr` | Open settings |
| `/bsr unlock` / `/bsr lock` | Move the icon |
| `/bsr test` | Show the icon |
| `/bsr time <n>` | Warn when this many seconds are left |
| `/bsr size <n>` | Icon size |
| `/bsr sound` | Turn the sound on or off |
| `/bsr reset` | Put the icon back in its default spot |
| `/bsr help` | All commands |

## Good to know
- WoW Forever hides buff details from addons during combat. Battle Shout Notice times your own shouts, then checks the real buff (and its real length) whenever you're out of combat.
- Because of that, a Battle Shout from another warrior during a fight is only picked up once combat ends, so in a group you may get an early reminder.

Created by Miff, supported by Claude. Source and changelog: [github.com/miff88/wow-forever-addons](https://github.com/miff88/wow-forever-addons)

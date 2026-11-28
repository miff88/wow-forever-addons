# Plate Threat

**See how close you are to pulling aggro on every enemy, before it happens.** Plate Threat shows your threat percentage beside each enemy nameplate during combat, a retail-style threat box on your target frame, and a warning when aggro is about to change hands.

Made for **World of Warcraft: Forever**. Works on every class: damage dealers watching their threat, healers, and tanks checking they've got everything.

## Features

### Threat on every nameplate
- Your threat percentage next to each enemy's health bar while you're in combat. 100% means you have aggro.
- Sits on the left of the health bar, clear of the level box and of other nameplate icons above the bar.
- Coloured by threat level (green, yellow, orange, red) when the game lets addons read it.
- Only shows on mobs you're actually on the threat table for.

### Threat on your target frame
- A small threat box on top of the default target frame, coloured by your threat level, like retail's.
- Can be turned off or nudged left, right, up or down if it doesn't line up with your setup.

### Aggro warning in groups
- In a party or raid, a big flashing message and a sound when aggro is about to change hands.
- Not tanking: "About to pull aggro" when you're above the tank, and "You have aggro!" when a mob turns to you.
- Tanking: "Losing aggro" when someone is close to taking a mob, and "Lost aggro!" once they have. Counts how many mobs, e.g. "Lost aggro on 2!".
- Works out whether you're the tank from your group role, or Defensive Stance and Bear Form. You can also set it yourself.
- The early warnings and the sound can each be turned off, and the message can be moved and resized.

### Easy to set up
- Full settings page under Options > AddOns, with an entry on the minimap's addon button.
- Choose the side of the health bar, font size and gap.
- Test mode shows sample numbers on every nameplate so you can check placement without fighting.

## Commands

| Command | What it does |
|---|---|
| `/pth` | Open settings |
| `/pth test` | Show sample numbers on every nameplate |
| `/pth left` / `/pth right` | Which side of the health bar |
| `/pth size <n>` | Font size |
| `/pth gap <n>` | Gap from the health bar |
| `/pth portrait` | Turn the target frame box on or off |
| `/pth warn` | Turn the aggro warning on or off |
| `/pth tank` / `/pth dps` / `/pth auto` | Who the warning treats you as |
| `/pth move` | Move the warning |
| `/pth help` | All commands |

## Good to know
- WoW Forever hides exact threat values from addons. Plate Threat displays the percentage the game provides, so it can't show how far ahead of the next player you are, and once you have aggro it reads 100%.
- Colours depend on the game allowing the threat level to be read; if it doesn't, the number shows in white.
- Inside dungeons and raids, Forever may hide threat on nameplates, so the numbers can drop out there. The aggro warning uses the game's threat status, which it usually still shares.
- The nameplate numbers need enemy nameplates switched on (V by default). The target frame box needs the default target frame.

## More WoW Forever addons
- **[Proc City](https://www.curseforge.com/wow/addons/proc-city)**: Overpower on the mob that dodged you, plus Revenge, Victory Rush, Riposte, Counterattack and Mongoose Bite, with their buttons lit.
- **[Mage Services](https://www.curseforge.com/wow/addons/mage-services)**: catches portal, food and water requests in chat, with one-click invite, whisper and portal.
- **[Buff Notice](https://www.curseforge.com/wow/addons/battle-shout-notice)**: an icon when a buff your class keeps up is missing or about to run out.
- **[Kick Tally](https://www.curseforge.com/wow/addons/kick-tally)**: announces your successful interrupts and counts your group's kicks.
- **[Kill Clock](https://www.curseforge.com/wow/addons/kill-clock)**: how long until your target dies, and until it reaches execute range.
- **[Target Arrow](https://www.curseforge.com/wow/addons/target-arrow)**: an arrow over your target so you can find it in any crowd.

Created by Miff, supported by Claude. Source and changelog: [github.com/miff88/wow-forever-addons](https://github.com/miff88/wow-forever-addons)

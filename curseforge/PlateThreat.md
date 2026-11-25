# Plate Threat

**See how close you are to pulling aggro on every enemy, before it happens.** Plate Threat shows your threat percentage beside each enemy nameplate during combat, plus a retail-style threat box on your target frame.

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
| `/pth help` | All commands |

## Good to know
- WoW Forever hides exact threat values from addons. Plate Threat displays the percentage the game provides, so it can't show how far ahead of the next player you are, and once you have aggro it reads 100%.
- Colours depend on the game allowing the threat level to be read; if it doesn't, the number shows in white.
- Inside dungeons and raids, Forever may hide threat on nameplates, so the numbers can drop out there.
- The nameplate numbers need enemy nameplates switched on (V by default). The target frame box needs the default target frame.

Created by Miff, supported by Claude. Source and changelog: [github.com/miff88/wow-forever-addons](https://github.com/miff88/wow-forever-addons)

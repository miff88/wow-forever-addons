# WoW Forever Addons

Small addons for World of Warcraft: Forever (Interface 16001). Some work on any class, some are for warriors only. None of them use the combat log, which Forever blocks for addons.

## Install

Copy whichever addon folders you want into `World of Warcraft\_forever_\Interface\AddOns` and `/reload`. Each addon works on its own. Enemy nameplates need to be on (V) for everything except Battle Shout Reminder.

## Settings

Every addon has a settings page under **Options > AddOns**, and an entry on the minimap's addon button. Typing the slash command on its own (for example `/opp`) opens the page, and adding `help` (`/opp help`) lists the chat commands.

## Any class

### Target Arrow (`/tarrow`)
A bobbing arrow above your target's nameplate so you can pick it out of a crowd. It sits high enough to clear the Overpower Plates icon if you use both.

- `/tarrow colour <red|yellow|green|blue|white>`
- `/tarrow size <n>`, `/tarrow offset <n>`, `/tarrow bob`, `/tarrow enemies`

### Plate Threat (`/pth`)
Shows your threat percentage on the left of each enemy nameplate in combat (100% = you have aggro), clear of the level box. Forever returns threat as secret values, so the number is displayed directly and is only coloured when the game allows the value to be read. May not show in instances.

Also adds a retail-style threat box on top of the target frame, coloured by your threat level. It can be moved or turned off on the settings page.

- `/pth test`, `/pth left`, `/pth right`, `/pth size <n>`, `/pth gap <n>`, `/pth portrait`

## Warrior only

These do nothing on other classes.

### Overpower Plates (`/opp`)
Puts an Overpower icon with a 5 second countdown above the nameplate of the mob that dodged you, including off-target dodges from Whirlwind and Cleave. A nameplate dodge only counts when your Overpower charge (combo point) goes up at the same moment, so dodges against other players are ignored.

- `/opp test` show the icon on every nameplate
- `/opp size <n>`, `/opp offset <n>`, `/opp window <n>`
- `/opp sound` toggle the dodge sound
- `/opp debug` print your current Overpower charge count

### Battle Shout Reminder (`/bsr`)
Shows a Battle Shout icon when the buff is missing or under 10 seconds while you're in combat or targeting an enemy. Forever hides buffs from addons in combat, so it times your own casts and checks the real buff out of combat.

- `/bsr unlock`, `/bsr lock` move the icon
- `/bsr test`, `/bsr time <n>`, `/bsr size <n>`, `/bsr sound`, `/bsr reset`

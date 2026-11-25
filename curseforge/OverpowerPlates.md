# Overpower Plates

**Know exactly which enemy just dodged you.** Overpower Plates puts an Overpower icon with a countdown above the nameplate of the mob that dodged you, so you can Overpower the right target even in a big pull.

Made for **World of Warcraft: Forever**. Warrior only.

## Features

### The right mob, every time
- When a mob dodges one of your attacks, an Overpower icon appears above its nameplate with a 5 second countdown.
- Catches dodges on mobs you aren't targeting, such as Whirlwind and Cleave hits on the rest of the pack.
- Only marks dodges against you. Dodges against other players and their pets are ignored, even in groups.

### Clears itself
- The icon goes away when you use Overpower, when the window runs out, when the mob dies or when you leave combat.

### Hard to miss
- The icon pops in and a gold glow pulses around it for as long as Overpower is up.
- Your Overpower button glows on the action bars at the same time (Blizzard bars, Bartender4 and ElvUI), and follows it when you swap stance.
- Optional big Overpower icon in the middle of the screen, with a countdown. Move it and size it to suit.
- Optional sound when a mob dodges you.
- Size, height above the health bar and how long it stays up are all adjustable.

### Easy to set up
- Full settings page under Options > AddOns, with an entry on the minimap's addon button.
- Test mode puts the icon on every nameplate so you can check placement without fighting.

## Commands

| Command | What it does |
|---|---|
| `/opp` | Open settings |
| `/opp test` | Show the icon on every nameplate, plus the glow and screen icon |
| `/opp size <n>` | Icon size |
| `/opp offset <n>` | Height above the health bar |
| `/opp window <n>` | Seconds the icon stays up |
| `/opp sound` | Turn the dodge sound on or off |
| `/opp glow` | Turn the action bar glow on or off |
| `/opp screen` / `/opp move` | Turn the screen icon on or off / move it |
| `/opp debug` | Show your current Overpower charge count |
| `/opp help` | All commands |

## Good to know
- WoW Forever doesn't let addons read the combat log. Overpower Plates works it out from the game's own Overpower charges and dodge reports instead.
- Needs enemy nameplates switched on (V by default).
- If you use a nameplate addon, the icon still attaches to the nameplate; adjust the height if it overlaps.
- Pairs with Target Arrow, which sits above the Overpower icon.

Created by Miff, supported by Claude. Source and changelog: [github.com/miff88/wow-forever-addons](https://github.com/miff88/wow-forever-addons)

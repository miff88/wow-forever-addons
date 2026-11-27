# Payback

**Hit back the moment you can.** Payback (formerly Overpower Plates) lights up the abilities you can only use right after a dodge, parry or block: Overpower on the exact mob that dodged you, and Revenge, Riposte, Counterattack and Mongoose Bite as a big icon in the middle of your screen.

Made for **World of Warcraft: Forever**. Warriors, rogues and hunters.

## Features

### Overpower on the right mob (warriors)
- When a mob dodges one of your attacks, an Overpower icon appears above its nameplate with a 5 second countdown.
- Catches dodges on mobs you aren't targeting, such as Whirlwind and Cleave hits on the rest of the pack.
- Only marks dodges against you. Dodges against other players and their pets are ignored, even in groups.
- Clears itself when you use Overpower, when the window runs out, when the mob dies or when you leave combat.

### Revenge, Riposte, Counterattack and Mongoose Bite
- **Warriors:** Revenge after you block, dodge or parry.
- **Rogues:** Riposte after you parry.
- **Hunters:** Counterattack after you parry, and Mongoose Bite after your target dodges.
- A big icon in the middle of the screen with a 5 second sweep and the spell's name, and a glow on its action buttons.
- Only shows while the game says you can cast it, so one on cooldown stays out of the way.
- Each one can be turned off, and the icon moved, resized or swapped for just the button glow.

### Hard to miss
- The Overpower icon pops in and a gold glow pulses around it while it's up.
- Your buttons glow on the action bars (Blizzard bars, Bartender4, ElvUI and Dominos), and follow them when you swap stance.
- Optional big Overpower icon in the middle of the screen too, and optional sounds.

### Easy to set up
- Full settings page under Options > AddOns, with an entry on the minimap's addon button. It only shows the parts for your class.
- Test mode shows every icon so you can check placement without fighting.

## Commands

| Command | What it does |
|---|---|
| `/payback` or `/opp` | Open settings |
| `/opp test` | Show the icons, plus the glow |
| `/opp size <n>` | Overpower icon size |
| `/opp offset <n>` | Overpower icon height above the health bar |
| `/opp window <n>` | Seconds the Overpower icon stays up |
| `/opp sound` | Turn the dodge sound on or off |
| `/opp glow` | Turn the action bar glow on or off |
| `/opp screen` / `/opp move` | Turn the Overpower screen icon on or off / move the screen icons |
| `/opp reactive` | Revenge, Riposte, Counterattack and Mongoose Bite on or off |
| `/opp debug` | What Payback can see: Overpower charges, action buttons, dodges and parries |
| `/opp help` | All commands |

## Good to know
- WoW Forever doesn't let addons read the combat log. Payback works from the game's own Overpower charges, its dodge, parry and block reports, and whether it says a spell can be cast.
- Mongoose Bite only shows when the game confirms it's usable, since your target dodging your pet looks the same as dodging you.
- Overpower needs enemy nameplates switched on (V by default).
- Upgrading from Overpower Plates keeps your settings, and `/opp` still works.
- Pairs with Target Arrow, which sits above the Overpower icon.

Created by Miff, supported by Claude. Source and changelog: [github.com/miff88/wow-forever-addons](https://github.com/miff88/wow-forever-addons)

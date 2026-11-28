# Kill Clock

**Know when it's going to die.** Kill Clock shows a countdown right beside the target frame with roughly how long until your target dies, so you can time cooldowns, executes and potions.

Made for **World of Warcraft: Forever**. Every class.

## Features
- Minutes and seconds (`1:24`), worked out from how fast your target has lost health so far.
- Sits just right of the target frame's portrait. Drag it anywhere you like.
- Standard game font with your choice of size, outline and colour: white, yellow, orange, red, green, blue, purple, pink, or any colour from the colour picker.
- Optional "Dies in" label.
- Can be limited to elites, rares and bosses.
- **Execute range:** a smaller line underneath shows how long until the target reaches 20% (`20% in 0:12`), so you know when Execute or Hammer of Wrath comes up. On by default for warriors and paladins, and the percentage can be changed for any class. Where the game allows it, the line turns red once the target is in range.
- **Focus clock:** an optional second clock beside the focus frame, for keeping an eye on a second mob or a boss while you kill adds.

## Commands

| Command | What it does |
|---|---|
| `/kclock` | Open settings |
| `/kclock test` | Show a sample time |
| `/kclock move` / `/kclock lock` | Move the clock |
| `/kclock reset` | Back beside the target frame |
| `/kclock size <n>` | Text size |
| `/kclock colour <name>` | white, yellow, orange, red, green, blue, purple or pink; no name opens the colour picker |
| `/kclock execute` | Execute range line on or off |
| `/kclock execute <n>` | Execute range at n% |
| `/kclock focus` | Focus clock on or off |
| `/kclock debug` | Print what it's timing from |

## Good to know
- It's an estimate: how long the target takes if it keeps losing health at the pace it has so far.
- WoW Forever hides enemy health from addons in combat. Kill Clock never reads it: it gives the game a lookup from health left to time left, and the game shows the answer.
- Keep enemy nameplates on (V) so it knows when each mob started taking damage, even after you switch targets.

## More WoW Forever addons
- **[Proc City](https://www.curseforge.com/wow/addons/proc-city)**: your procs and short buffs as a row of icons, including the new Forever talents, plus Overpower on the nameplate of the mob that dodged.
- **[Mage Services](https://www.curseforge.com/wow/addons/mage-services)**: catches portal, food and water requests in chat, with one-click invite, whisper and portal.
- **[Buff Notice](https://www.curseforge.com/wow/addons/battle-shout-notice)**: an icon when a buff your class keeps up is missing or about to run out.
- **[Kick Tally](https://www.curseforge.com/wow/addons/kick-tally)**: announces your successful interrupts and counts your group's kicks.
- **[Plate Threat](https://www.curseforge.com/wow/addons/plate-threat)**: your threat on every enemy nameplate, with a warning before you pull aggro.
- **[Target Arrow](https://www.curseforge.com/wow/addons/target-arrow)**: an arrow over your target so you can find it in any crowd.

Created by Miff, supported by Claude. Source and changelog: [github.com/miff88/wow-forever-addons](https://github.com/miff88/wow-forever-addons)

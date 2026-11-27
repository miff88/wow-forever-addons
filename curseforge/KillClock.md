# Kill Clock

**Know when it's going to die.** Kill Clock shows a countdown just above the target frame with roughly how long until your target dies, so you can time cooldowns, executes and potions.

Made for **World of Warcraft: Forever**. Every class.

## Features
- Minutes and seconds (`1:24`), worked out from how fast your target has lost health so far.
- Sits just above the target frame, and above Plate Threat's threat box if you use that. Drag it anywhere you like.
- Standard game font with your choice of size, outline and colour: white, yellow, orange, red, green, blue, purple, pink, or any colour from the colour picker.
- Optional "Dies in" label.
- Can be limited to elites, rares and bosses.

## Commands

| Command | What it does |
|---|---|
| `/kclock` | Open settings |
| `/kclock test` | Show a sample time |
| `/kclock move` / `/kclock lock` | Move the clock |
| `/kclock reset` | Back above the target frame |
| `/kclock size <n>` | Text size |
| `/kclock colour <name>` | white, yellow, orange, red, green, blue, purple or pink; no name opens the colour picker |
| `/kclock debug` | Print what it's timing from |

## Good to know
- It's an estimate: how long the target takes if it keeps losing health at the pace it has so far.
- WoW Forever hides enemy health from addons in combat. Kill Clock never reads it: it gives the game a lookup from health left to time left, and the game shows the answer.
- Keep enemy nameplates on (V) so it knows when each mob started taking damage, even after you switch targets.

Created by Miff, supported by Claude. Source and changelog: [github.com/miff88/wow-forever-addons](https://github.com/miff88/wow-forever-addons)

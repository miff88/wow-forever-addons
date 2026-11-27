# Kick Tally

**Know when your kick landed, and who's pulling their weight.** Kick Tally announces your successful interrupts in chat and keeps a small window with how many kicks each person in your party or raid has landed.

Made for **World of Warcraft: Forever**. Every class.

## Features

### Your kicks
- Announces each successful interrupt: "Pummel interrupted Defias Pillager's Fireball!"
- Post to auto (instance, raid or party chat), party, raid, instance, say or yell, or just your own chat window.
- Edit the message with `{target}`, `{spell}`, `{ability}` and `{count}`.
- Tells you (only you) when your kick didn't interrupt anything.
- Optional sound.

### The group's kicks
- A window styled like the game's own damage meter: class-coloured bars, C / O for this fight or overall, and a minimise button. Hover a row to see what that player kicked.
- Resize it by dragging the corner, and scroll with the mouse wheel when there are more players than fit.
- Show or hide it, or only show it in a party or raid. Bar height and background opacity are adjustable.
- `/kicks report` posts the tally to your group, and it can post a boss fight's tally automatically when the boss dies.

### What counts
- Pummel, Shield Bash, Kick, Counterspell, Earth Shock, Spell Lock, Feral Charge and Silence.
- Optionally, stuns and fears that stop a cast: Hammer of Justice, Bash, Concussion Blow, Kidney Shot, Gouge, War Stomp, Intimidation and more.

## Commands

| Command | What it does |
|---|---|
| `/kicks` | Open settings |
| `/kicks test` | Sample window and message |
| `/kicks report` / `/kicks report total` | Post this fight's (or all) kicks to the group |
| `/kicks lock` / `/kicks unlock` | Lock or move the window |
| `/kicks show` / `/kicks hide` | Show or hide the window |
| `/kicks reset` / `/kicks reset position` | Clear all kick data (also in the window's C / O and gear menus) or reset the window position |
| `/kicks debug` | Print the casts and interrupts it sees |

## Good to know
- WoW Forever doesn't let addons read the combat log. Your own kicks are exact: Kick Tally sees your interrupt and the enemy's cast stopping. In combat the game hides which spells other players cast, so their kicks are counted when their cast lands at the same moment an enemy's cast is interrupted.
- Keep enemy nameplates on (V) so it sees every enemy, not just your target.
- The game blocks addon chat messages during boss fights. There your kicks show in your own chat window instead.
- In dungeon fights the game hides enemies' names and spells from addons. Kick Tally remembers names it saw before the pull and uses raid markers; a kick it can't name stays in your own chat window unless you turn on posting it anyway.
- Say and yell only work inside dungeons and raids; outdoors the game blocks addons from using them.

Created by Miff, supported by Claude. Source and changelog: [github.com/miff88/wow-forever-addons](https://github.com/miff88/wow-forever-addons)

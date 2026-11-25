# WoW Forever Addons

Small addons for World of Warcraft: Forever (Interface 16001). Some work on any class, some are for warriors only. None of them use the combat log, which Forever blocks for addons.

## Install

Copy whichever addon folders you want into `World of Warcraft\_forever_\Interface\AddOns` and `/reload`. Each addon works on its own. Enemy nameplates need to be on (V) for everything except Battle Shout Reminder.

## Settings

Every addon has a settings page under **Options > AddOns**, and an entry on the minimap's addon button. Typing the slash command on its own (for example `/opp`) opens the page, and adding `help` (`/opp help`) lists the chat commands.

## Any class

### Target Arrow (`/tarrow`)
<img src="logos/TargetArrow.png" alt="TargetArrow logo" width="96">

A bobbing arrow above your target's nameplate so you can pick it out of a crowd. It sits high enough to clear the Overpower Plates icon if you use both.

- `/tarrow colour <red|yellow|green|blue|white>`
- `/tarrow size <n>`, `/tarrow offset <n>`, `/tarrow bob`, `/tarrow enemies`

### Plate Threat (`/pth`)
<img src="logos/PlateThreat.png" alt="PlateThreat logo" width="96">

Shows your threat percentage on the left of each enemy nameplate in combat (100% = you have aggro), clear of the level box. Forever returns threat as secret values, so the number is displayed directly and is only coloured when the game allows the value to be read. May not show in instances.

Also adds a retail-style threat box on top of the target frame, coloured by your threat level. It can be moved or turned off on the settings page.

- `/pth test`, `/pth left`, `/pth right`, `/pth size <n>`, `/pth gap <n>`, `/pth portrait`

## Mage

### Mage Services (`/ms`)
<img src="logos/MageServices.png" alt="MageServices logo" width="96">

Spots people asking for portals or water in chat and lists them in a small window, each with **Invite** and **Whisper** buttons. Whisper opens your chat box with a reply already typed (`{name}` and `{dest}` filled in), so you just press Enter. Matching is loose: it ignores case and punctuation, allows small typos, understands city shorthand (UC, TB, Org, SW, IF, Darn), and ignores other mages' adverts ("WTS portals"). Auto-invite is available but off by default. Works on any class, but it's made for mages.

**Location priority.** Requests are ranked against where you are (detected automatically, or pick a city with `/ms zone`):
- **Top, highlighted:** asked in your zone's General channel or in say/yell, said "from <your zone>", or a /who shows them in your zone.
- **Middle:** location unknown (Trade, whispers, guild). Click **?** on the row to run a /who and re-rank it. The game only allows /who from a click, so this can't run automatically.
- **Bottom, dimmed:** they're somewhere else, or they want a port to the city you're already in. Can be hidden instead.

**On-screen alerts.** The matching Portal or Conjure button on your action bars glows (Blizzard bars, Bartender4 and ElvUI), a message shows at the top of the screen, and the screen edges flash. Each can be turned off.

**Portal button.** A big icon at the top-left of the window casts the portal for the selected request (or Conjure Water for a water request). The top request is picked automatically; click a row to pick another. It can be bound to a key under Key Bindings > AddOns. It updates as soon as combat ends, since the game doesn't allow spell buttons to change during combat.

**Payment messages.** After a trade with someone who asked (or is in your group), it posts the result: payment received (gold and any items), completed with no payment, cancelled, or failed with the reason. It uses party chat if they're still in your group, otherwise it whispers them. Choose whether it sends automatically, only types it into your chat box for you to send, or stays off.

**Earnings.** Gold received is totalled per character, split into portals (with a per-city breakdown), water/food and other, plus a total for the current session. It's shown at the bottom of the window, on the settings page and with `/ms earnings`.

Forever hides chat text from addons inside dungeons, raids, M+ and PvP, so it only works out in the world.

- `/ms theme [dark|light]` window theme (also on the settings page)
- `/ms sounds`, `/ms sound <number>` list and pick the alert sound (also a dropdown on the settings page)
- `/ms earnings` totals; `/ms earnings reset` to clear
- `/ms receipts [auto|prefill|off]` how payment messages are posted
- `/ms paidmsg`, `/ms nopaymsg`, `/ms cancelmsg`, `/ms failmsg <text>` change them (`{name}`, `{amount}`, `{reason}` are filled in)
- `/ms testtrade [complete|cancelled|failed]` preview a payment message (typed only, never sent)
- `/ms zone [auto|city|zone]` show or set your location, e.g. `/ms zone uc`
- `/ms add <phrase>` watch for your own phrase too, e.g. `/ms add lf summon`; `/ms list`, `/ms remove <n>`
- `/ms exclude <phrase>` never match lines containing it; `/ms excludes`, `/ms unexclude <n>`
- `/ms portmsg <text>`, `/ms watermsg <text>`, `/ms custommsg <text>` change the reply
- `/ms test` add sample requests, `/ms show` show the window

## Warrior only

These do nothing on other classes.

### Overpower Plates (`/opp`)
<img src="logos/OverpowerPlates.png" alt="OverpowerPlates logo" width="96">

Puts an Overpower icon with a 5 second countdown above the nameplate of the mob that dodged you, including off-target dodges from Whirlwind and Cleave. A nameplate dodge only counts when your Overpower charge (combo point) goes up at the same moment, so dodges against other players are ignored.

- `/opp test` show the icon on every nameplate
- `/opp size <n>`, `/opp offset <n>`, `/opp window <n>`
- `/opp sound` toggle the dodge sound
- `/opp debug` print your current Overpower charge count

### Battle Shout Reminder (`/bsr`)
<img src="logos/BattleShoutReminder.png" alt="BattleShoutReminder logo" width="96">

Shows a Battle Shout icon when the buff is missing or under 10 seconds while you're in combat or targeting an enemy. Forever hides buffs from addons in combat, so it times your own casts and checks the real buff out of combat.

- `/bsr unlock`, `/bsr lock` move the icon
- `/bsr test`, `/bsr time <n>`, `/bsr size <n>`, `/bsr sound`, `/bsr reset`

## Releasing

Pushing a tag named `<AddonFolder>-v<version>` (for example `MageServices-v1.4.4`) builds that addon's zip, attaches it to a GitHub release and, for addons listed in `curseforge.json`, uploads it to CurseForge as a WoW Forever (1.60.1) file. The tag must match the version in the addon's .toc. CurseForge uploads need the `CF_API_TOKEN` repository secret.

# Mage Services

**Never miss a portal or water request again.** Mage Services watches chat for people asking for a portal or for food and water, and lists them in a small window with **Invite**, **Whisper** and a one-click **Portal** button, so you can serve customers fast and keep track of what you earn.

Made for **World of Warcraft: Forever**. Works on any class, built for mages.

## Features

### Spots requests in chat
- Picks up portal requests ("LF port to UC", "anyone port tb?", "need a portal to orgrimar") and food and water requests ("WTB mage water", "any mage for table?"), including linked Conjured items.
- Loose matching: ignores case and punctuation, allows small typos, and knows city shorthand (Org, UC, TB, SW, IF, Darn).
- Ignores other mages' adverts ("WTS portals"), "water walking" and other false alarms.
- Add your own phrases (`/ms add lf summon`) and words to ignore (`/ms exclude ratchet`).

### Only the requests you can serve
- Knows where you are, automatically or from a city you pick.
- **Your city:** people who asked in your zone's General channel, nearby in say/yell, said "from <your zone>", or are guildmates and friends standing in your city.
- **Unknown:** Trade chat reaches every city, so Trade requests that don't say where they are are marked unknown. Click **?** to run a /who and place them.
- **Show requests from:** your city only, your city + unknown, or everywhere with the rest dimmed.
- Requests for a city you're already in, or a portal you don't have yet, are counted as ones you can't help with.

### Pause when you're busy
- **Pause** on the window stops taking requests on that character, with no alerts or replies, until you press **Resume**. No need to turn the addon off.

### One-click service
- **Portal button:** casts the requested portal (or Conjure Water) for the selected request. Click a row to pick another. Bindable to a key.
- **Invite** and **Whisper** on every request. Whisper opens a ready-made reply aimed at the player's full two-part Forever name ("Hi Lil, I can port you to Undercity..."), so you just press Enter.
- Edit the replies on the settings page, with a live example. `{name}`, `{dest}` and `{zone}` are filled in.
- **Optional automatic reply** for people who whisper you directly. Never for Trade or General posts, at most once per player every few minutes, and a separate polite reply when you can't help (a portal you don't have, or they're somewhere else).
- **Invite everyone going to the same city** with one click: rows that share a destination get an "All 3" button, so one portal serves the whole group.
- **Optional group tidy-up:** after your portal, customers who went through are removed from the group so there's room for the next lot. Only people you invited from Mage Services or who asked you in chat, and only while you lead.
- Optional auto-invite.

### Advertise
- One click on **Advertise** posts your own line in Trade (or General, say, yell): "Mage in Orgrimmar selling portals to UC and TB, plus food and water. Whisper me!", listing the portals this character has.
- At most once every 3 minutes (adjustable), with a countdown on the button, so you never spam.
- Edit the text on the settings page. Also `/ms ad` or a key binding, and an optional slim bar keeps the button handy while you wait for customers.

### Runes
- Your Runes of Teleportation and Runes of Portals counts at the bottom of the window.
- A chat warning when Runes of Portals run low (below 5 by default, adjustable), so you restock before you run dry mid-service.

### Hard to miss
- The matching Portal or Conjure button on your action bars glows (Blizzard bars, Bartender4, ElvUI).
- Message at the top of the screen, screen-edge flash and a sound of your choice from the game's own sounds.

### Payments and earnings
- After a trade with a customer, posts the result in party chat, or whispers them if they've left: payment received, no payment, cancelled or failed with the reason. The gold amount is left out by default so your prices stay private. Send automatically, have it typed for you, or turn it off.
- Earnings saved through logouts and split into **portals** and **food & water**: all characters all time, this character, this session, and portals by city. Plus a total of all gold from every trade while the addon is on.

### Looks the part
- Dark and light themes.
- Full settings page under Options > AddOns, with an entry on the minimap's addon button.

## Commands

| Command | What it does |
|---|---|
| `/ms` | Open settings |
| `/ms ad` | Post your advert |
| `/ms test` | Add sample requests to try the window |
| `/ms zone [auto, city or zone]` | Show or set your location |
| `/ms pause` / `/ms resume` | Stop or start taking requests on this character |
| `/ms filter here, nearby or all` | Which requests to show |
| `/ms earnings` | Show your earnings |
| `/ms add <phrase>` / `/ms exclude <phrase>` | Watch for or ignore your own phrases |
| `/ms portmsg`, `/ms watermsg`, `/ms cantmsg` `<text>` | Change the replies (`{name}`, `{dest}` and `{zone}` are filled in) |
| `/ms autoreply` | Turn automatic replies to whispers on or off |
| `/ms receipts [auto, prefill, off]` | How payment messages are posted |
| `/ms theme [dark, light]` | Window theme |
| `/ms help` | All commands |

## Good to know
- WoW Forever hides chat text from addons inside dungeons, raids, Mythic+ and PvP, so requests are only picked up out in the world, which is where people ask anyway.
- The game only allows /who from a click, so the **?** lookup can't run automatically.

## More WoW Forever addons
- **[Proc City](https://www.curseforge.com/wow/addons/proc-city)**: Overpower on the mob that dodged you, plus Revenge, Victory Rush, Riposte, Counterattack and Mongoose Bite, with their buttons lit.
- **[Buff Notice](https://www.curseforge.com/wow/addons/battle-shout-notice)**: an icon when a buff your class keeps up is missing or about to run out.
- **[Kick Tally](https://www.curseforge.com/wow/addons/kick-tally)**: announces your successful interrupts and counts your group's kicks.
- **[Kill Clock](https://www.curseforge.com/wow/addons/kill-clock)**: how long until your target dies, and until it reaches execute range.
- **[Plate Threat](https://www.curseforge.com/wow/addons/plate-threat)**: your threat on every enemy nameplate, with a warning before you pull aggro.
- **[Target Arrow](https://www.curseforge.com/wow/addons/target-arrow)**: an arrow over your target so you can find it in any crowd.

Created by Miff, supported by Claude. Source and changelog: [github.com/miff88/wow-forever-addons](https://github.com/miff88/wow-forever-addons)

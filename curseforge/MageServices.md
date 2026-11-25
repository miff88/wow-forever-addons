# Mage Services

**Never miss a portal or water request again.** Mage Services watches chat for people asking for a portal or for food and water, and lists them in a small window with **Invite**, **Whisper** and a one-click **Portal** button, so you can serve customers fast and keep track of what you earn.

Made for **World of Warcraft: Forever**. Works on any class, built for mages.

## Features

### Spots requests in chat
- Picks up portal requests ("LF port to UC", "anyone port tb?", "need a portal to orgrimar") and food and water requests ("WTB mage water", "any mage for table?"), including linked Conjured items.
- Loose matching: ignores case and punctuation, allows small typos, and knows city shorthand (Org, UC, TB, SW, IF, Darn).
- Ignores other mages' adverts ("WTS portals"), "water walking" and other false alarms.
- Add your own phrases (`/ms add lf summon`) and words to ignore (`/ms exclude ratchet`).

### Puts the best requests first
- Knows where you are, automatically or from a city you pick.
- **Top:** people near you, who asked in your zone's General channel or in say/yell, or said "from <your zone>".
- **Middle:** Trade and whispers, where the location is unknown. Click **?** to run a /who and re-rank the request by their real zone.
- **Bottom, dimmed:** people elsewhere, asking for a port to the city you're already in, or asking for a portal you don't have yet. Can be hidden instead, and there's a separate option to hide requests that don't say where the player is.

### One-click service
- **Portal button:** casts the requested portal (or Conjure Water) for the selected request. Click a row to pick another. Bindable to a key.
- **Invite** and **Whisper** on every request. Whisper opens a ready-made reply aimed at the player's full two-part Forever name ("Hi Lil, I can port you to Undercity..."), so you just press Enter.
- Edit the replies on the settings page, with a live example. `{name}`, `{dest}` and `{zone}` are filled in.
- **Optional automatic reply** for people who whisper you directly. Never for Trade or General posts, at most once per player every few minutes, and a separate polite reply when you can't help (a portal you don't have, or they're somewhere else).
- Optional auto-invite.

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
| `/ms test` | Add sample requests to try the window |
| `/ms zone [auto, city or zone]` | Show or set your location |
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

Created by Miff, supported by Claude. Source and changelog: [github.com/miff88/wow-forever-addons](https://github.com/miff88/wow-forever-addons)

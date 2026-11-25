# Changelog

## 2026-11-25

Mage Services 1.4.1
- Re-checks your zone straight after loading screens (hearth, portals, instances), not just on zone changes.
- With a picked zone, the title also shows where you really are when they differ, e.g. "Thunder Bluff (picked, you're in Orgrimmar)".

Mage Services 1.4.0
- Dark and light themes for the window, portal button and on-screen message (settings page or /ms theme).
- Window rebuilt on a fixed grid with flat themed buttons: header buttons centred, row buttons share one right edge, two-line text centred on the icon, long titles and footer text cut off cleanly instead of running into buttons.
- Portal button's border matches the window and its top lines up with the window; the city name now sits inside the button (UC, TB, Org...) instead of spilling into the window.
- On-screen message has a panel, is sized to its text so it stays centred, and the two lines no longer overlap.
- Action button glow sized closer to the game's own.

Mage Services 1.3.0
- Choose the alert sound from a dropdown of the game's own sounds (or None), with a Play button to preview. Also /ms sounds and /ms sound <number>.

Mage Services 1.2.0
- Portal button that casts the selected request's portal (or Conjure Water), with a key binding.
- Payment messages after trades: received (gold and items), no payment, cancelled or failed, in party chat or by whisper if they've left the group. Auto, prefill or off.
- Earnings per character: portals by city, water/food, other, and this session. Shown in the window, settings page and /ms earnings.

Mage Services 1.1.0
- Location priority: requests ranked by where the person is compared with your zone (auto-detected or picked with /ms zone). Near you at the top, elsewhere or "port to where you already are" dimmed at the bottom, with an option to hide them.
- Understands "from X" / "in X" in requests, so "LF port from Org to UC" gets the right destination.
- "?" button on each request runs a /who to find their zone and re-rank it.
- On-screen alerts: glowing Portal/Conjure action button, message at the top of the screen, screen edge flash.

Mage Services 1.0.0
- New addon: spots portal and water requests in chat with Invite and Whisper buttons, custom phrases, exclusions and optional auto-invite.

## 2026-11-24 (later)

Plate Threat 1.3.0
- Retail-style threat box on top of the target frame, coloured by threat level. Can be moved or turned off.

## 2026-11-24

All addons
- Settings page for each addon under Options > AddOns.
- Entry on the minimap's addon button that opens the settings page.
- Icon and coloured name in the AddOns list, plus category and website.
- Slash command on its own opens settings; `help` lists chat commands with the version.

Overpower Plates 1.3.0
- Icon pops in with a quick scale animation (can be turned off).

Battle Shout Reminder 1.1.0
- Unlock, reset position and test from the settings page.

Plate Threat 1.2.0
- Side, font size and gap adjustable from the settings page.

Target Arrow 1.1.0
- Colour, size, height, bobbing and enemies-only adjustable from the settings page.

## Earlier

- Overpower Plates 1.2.0: only marks dodges against you, by matching nameplate dodges to your Overpower charges.
- Overpower Plates 1.1.0: rebuilt without the combat log, which Forever blocks for addons.
- Plate Threat 1.1.0: moved to the left of the health bar so it doesn't cover the level box.
- First versions of all four addons.

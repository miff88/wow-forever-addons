# Changelog

## 2026-11-27

Craft Services 1.1.1
- Mats always show by name. Right after logging in the game may not have loaded an item's name yet, which showed as "short on 1 item 2836"; it now uses the name saved when it read your recipes, and fills it in as soon as the game has it.

Craft Services 1.1.0
- Choose which professions it watches: the settings page has a tick-box for every profession. The ones you've trained start ticked, and you can tick others (one an alt has, say). Nothing else is picked up. This replaces "Also list requests for professions you don't have".
- Never picks up mage requests. "looking for mage port uc to tb" was being read as a cooking request, because "looking" counted as a typo of "cooking". Typos now have to keep the first letter of the word, and lines about ports, portals, water or a mage are skipped unless a profession or recipe is named.
- Typos in enchant names are understood: "anyone do firey?" finds Fiery Weapon.
- A request that just names your profession ("LF cook") no longer says "open your Cooking window" next to it.
- Settings page: no more big gaps under your professions, prices and featured recipes; the "Payment messages" label isn't cut off; and the payment message used when the gold amount is kept private can now be edited (it's the one that's on by default).

Mage Services 2.1.2
- Settings page: the "Payment messages" label is no longer cut off.

Craft Services 1.0.0
- New addon: Mage Services for every profession. Spots people asking for enchants, crafts and lockboxes in chat (Enchanting, Blacksmithing, Leatherworking, Tailoring, Alchemy, Engineering, Jewelcrafting, Inscription, Cooking, First Aid, and Lockpicking for rogues) and lists them with Invite and Whisper buttons.
- Reads your recipes when you open a profession window, so it knows what you can make and whether you have the mats. Understands links, recipe names and enchant nicknames like "crusader" or "+7 agi gloves".
- Replies fill in the recipe, your price, the mats and their place in the queue. Optional automatic replies to whispers and automatic invites (only when you can do it).
- Follows each customer from invite to paid. A helper beside the trade window checks mats, their item and the payment, and has buttons to enchant their item, pick their lockbox, open the recipe, and ask for payment or missing mats.
- Prices, a featured-recipe advert, payment messages, earnings by profession and recipe, and customer history.

Mage Services 2.1.1
- Payment messages are more reliable: a trade both of you accepted now counts as completed even if the game doesn't send its "Trade complete" message (before, it could be reported as cancelled). The amount is taken from when you accepted, in case the window empties first.
- Trade errors that include a player's name are now recognised as failed trades.

Proc City 1.5.0
- Starter pins: the first time each class logs in with nothing pinned, the procs it usually builds around are pinned for you, if the character has them. Warriors get Overpower, Flurry and Crusader; rogues Riposte and Remorseless Attacks; hunters Quick Shots and Mongoose Bite; mages Clearcasting; priests Spirit Tap; warlocks Shadow Trance; paladins Vengeance and Crusader; shamans Flurry and Clearcasting; druids Clearcasting and Nature's Grace. A chat line says what was pinned. Unpin any you don't want and they stay unpinned.

Mage Services 2.1.0
- Advertise: a button on the window (also `/ms ad` and a key binding) posts your own advert in Trade, General, say or yell. By default it reads "Mage in Orgrimmar selling portals to UC and TB, plus food and water. Whisper me!", listing the portals this character has. At most once every 3 minutes (adjustable), and the button counts down to the next one. Edit the text on the settings page.
- Optional slim bar that keeps the window (and the Advertise button) on screen when there are no requests.

Proc City 1.4.0
- Proc Plates (formerly Overpower Plates) is now part of Proc City. Warriors get Overpower when a mob dodges you and Revenge after a block, dodge or parry; rogues get Riposte; hunters get Counterattack and Mongoose Bite. They join the icon row for their 5 second window, can be pinned, and only show while the game says you can cast them.
- Overpower also puts an icon on the nameplate of the mob that dodged you, as Proc Plates did (on by default, `/proc plates` to turn it off).
- Your action buttons glow while one of these is up, and Shadow Bolt lights up during Shadow Trance (`/proc glow` to turn it off).
- Proc Plates settings come across automatically the first time you log in with both installed.

Proc Plates 2.1.0
- The last Proc Plates update: it's now part of Proc City. With Proc City 1.4.0 or later installed, Proc City takes over with your settings and Proc Plates goes quiet (and `/opp` opens Proc City's settings), so you can delete it. Without Proc City it keeps working and reminds you at login.

Proc Plates 2.0.2
- Now called Proc Plates. `/procplates` opens the settings, and `/opp` still works. Nothing else changed.

Payback Time 2.0.1
- Named Payback Time (the name "Payback" was already taken on CurseForge), so the addon list, settings page and CurseForge page all match. Nothing else changed; `/payback` and `/opp` both still work.

Payback 2.0.0 (was Overpower Plates)
- Renamed, because it now covers rogues and hunters too, with a new logo.
- Revenge (warriors), Riposte (rogues), Counterattack and Mongoose Bite (hunters): a big icon in the middle of the screen with a 5 second sweep, and a glow on the spell's action buttons, after you block, dodge or parry (Mongoose Bite: after your target dodges). It only shows while the game says the spell can be cast, so one on cooldown stays hidden. Each can be turned off, and the icon moved, resized or turned off in favour of just the button glow.
- Overpower works exactly as before. Your settings carry over, and `/opp` still works alongside the new `/payback`.
- `/opp debug` now also shows the dodges and parries it has seen, to help if something doesn't light up.

Target Arrow 1.3.0
- An optional second arrow for your focus or a raid marker (skull by default), a little smaller and in its own colour (blue by default). It hides when it would point at your target. Set it up on the settings page, or with `/tarrow focus` and `/tarrow marker skull`.
- Purple and orange arrows.

Proc City 1.3.0
- Pinned procs: pin the procs you build around (Flurry, Crusader, Enrage, Clearcasting...) on the settings page or with `/proc pin <name>`. They come first, always in the same place, and show as a faint grey icon while they're down, so you can see at a glance when one's missing. By default the grey icons only show in combat; how faint they are is adjustable.
- `/proc pin crusader` works as well as `/proc pin holy strength`.

Kick Tally 1.4.0
- Group members who also run Kick Tally send you their own kicks, so their counts are exact instead of matched by timing. Addons can't message each other during boss fights, M+ or PvP, so there it goes back to timing as before. Can be turned off on the settings page.
- Interrupt cooldowns count down over the class icons on the window: yours, and those of group members who run Kick Tally (or whose kick the game shows). The tooltip says when it's ready. Can be turned off.

Mage Services 2.0.0
- When two or more people want the same city, their rows get an **All** button ("All 3") that invites everyone going there at once.
- Rune counts at the bottom right of the window (Runes of Teleportation and Runes of Portals), and a chat warning when Runes of Portals drop below 5. The threshold is on the settings page; the warning starts once it has seen a portal use a rune.
- Optional (off by default): after your portal, customers who were standing with you are removed from the group once they've gone through. Only people you invited from Mage Services or who asked you in chat, and only while you lead the group.

Kill Clock 1.1.0
- A smaller second line shows how long until your target reaches execute range, e.g. `20% in 0:12`. On by default for warriors and paladins (Execute, Hammer of Wrath); turn it on for any class and set the percentage on the settings page or with `/kclock execute <n>`. Where the game allows it, it turns red once the target is in range.
- An optional second clock beside the focus frame (`/kclock focus`). It hides while your focus is also your target.

Plate Threat 1.5.0
- Aggro warning in a party or raid: a big flashing message and a sound. Not tanking, "About to pull aggro" when you're above the tank and "You have aggro!" when a mob turns to you. Tanking, "Losing aggro" when someone is close to taking a mob and "Lost aggro!" when they have it, with a count when it's more than one mob.
- Works out whether you're the tank from your group role, or Defensive Stance and Bear Form. Set it yourself on the settings page or with `/pth tank`, `/pth dps` and `/pth auto`.
- The early warning and the sound can each be turned off. Move the message with `/pth move` or from the settings page, and change its size.

Buff Notice 2.0.0 (was Battle Shout Notice)
- New logo.
- Now for every class. Reminds you about the buffs your class keeps up: Battle Shout, Arcane Intellect and mage armors, Fortitude, Inner Fire and Divine Spirit, Mark of the Wild, Omen of Clarity and Thorns, Blessings and Righteous Fury, Demon Skin/Armor, Lightning Shield and weapon imbues, Aspects and Trueshot Aura, and rogue poisons on each weapon. Only buffs you know are watched, and each can be turned off on the settings page.
- Group buffs show how many nearby party or raid members are missing yours (Intellect and Spirit skip warriors and rogues).
- Optional food and flask/elixir reminder in dungeons and raids.
- Short buffs warn at 10 seconds and long ones at 60, both adjustable. Quiet in cities and inns.
- Warriors: Battle Shout works as before, and your settings and icon position carry over. `/bsn list` shows what it's watching; `/buffnotice` also opens the settings.

Kick Tally 1.3.2
- The chat command is now `/ktally`, because `/kick` (one letter off `/kicks`) is the game's own command for removing someone from your group. `/kicks` and `/kicktally` still work.

Kick Tally 1.3.1
- "Reset all data" on the window itself: in the C / O menu (like the damage meter) and the gear menu, as well as the arrow menu and the settings page. It asks before clearing this fight's and the overall counts. `/kicks reset` still clears them straight away.

Kill Clock 1.0.1
- The clock now starts just right of the target frame's portrait, level with it, instead of above the frame. If you've already moved it, it stays where you put it; `/kclock reset` brings it to the new spot.

Kill Clock 1.0.0 (new)
- A countdown just above the target frame showing roughly how long until your target dies, from how fast it has lost health so far. Shown as minutes and seconds (`1:24`), up to 20 minutes.
- Movable. Text size, outline, an optional "Dies in" label, and a colour: white, yellow, orange, red, green, blue, purple, pink or any colour from the colour picker.
- Can be limited to elites, rares and bosses, and waits a couple of seconds of damage before its first estimate.
- Works with WoW Forever's hidden enemy health: it never reads the health, it hands the game a lookup from health left to time left and the game shows the result. Times each mob from when its nameplate started losing health, so switching targets mid-fight keeps a good estimate.
- Sits above Plate Threat's threat box when that's on.

Kick Tally 1.3.0
- Fixed kick posts that only said "Interrupted!". In a dungeon fight the game hides the enemy's name and spell from addons, and won't let them post hidden text. Kick Tally now reads each enemy's name while it still can (when its nameplate appears or you target it before the pull) and uses that, falls back to the enemy's raid marker ({rt8} shows as a skull), and always names your ability.
- New default message: "{ability} interrupted {target}'s {spell}!", e.g. "Pummel interrupted Scorching Elemental's Fireball!". If you kept the old default it's switched over; a message you wrote yourself is left alone.
- When the game hides both the enemy and its spell, the kick goes only to your own chat window ("Pummel interrupted a cast!") instead of the group. Turn on "Post even when the game hides the enemy and its spell" to post it anyway.

Kick Tally 1.2.0
- Resize the window by dragging its bottom-right corner, with the damage meter's own corner handle (it shows while your mouse is over the window). The window lists as many players as fit; scroll with the mouse wheel to see the rest.
- Thinner bars (20, was 25) and a see-through background, closer to how the meter looks. Bar height, background opacity and window height are new settings, next to width and window opacity.
- "Reset position" also resets the size.

Kick Tally 1.1.0
- The tally window now looks like the game's own damage meter, using its art: the gold title bar, class-coloured bars with class icons, "1. Name" and the count with each player's share of the group's kicks.
- Title bar buttons like the meter's: C / O for this fight or overall, a gear menu (lock, only in a group, hide, settings) and a minimise button. The arrow by the title posts the tally, resets the counts or runs the test.
- Hover a row to see what that player kicked this fight.
- New settings: show the window (on/off), only while in a party or raid, width and opacity.

Kick Tally 1.0.0 (new)
- Announces your successful interrupts in chat. The message is editable, with `{target}`, `{spell}`, `{ability}` and `{count}`, and any part the game hides is left out cleanly.
- Choose where it goes: auto (instance, raid or party chat), party, raid, instance, say, yell (inside instances only) or just your own chat window.
- A movable window with each party or raid member's kicks this fight and in total. `/kicks report` posts it to the group, and it can post a boss fight's tally when the boss dies.
- Tells you when your kick didn't interrupt anything.
- Counts Pummel, Shield Bash, Kick, Counterspell, Earth Shock, Spell Lock, Feral Charge and Silence, and optionally stuns and fears that stop a cast.
- Works without the combat log: your kicks are matched to the enemy's interrupted cast; other players' kicks are matched by timing because Forever hides their spells in combat. During boss fights, when addons can't post in chat, your kicks show in your own chat window.

Proc City 1.2.0
- Tracks every WoW Forever weapon whose chance on hit or Use puts a buff on you (28 weapons, taken from Forever's item database):
  - Strength: Destiny, Arcanite Champion, Malown's Slam, Claymore of Two Moons (Wane).
  - Attack power and speed: The Jackhammer, Manual Crowd Pummeler, Ragehammer, Lord General's Sword, Argent Avenger, Sword of Zeal, Felstriker, Darkspear, Shawarmageddon, Ravager.
  - Defensive: Quel'Serrar, Guardian's Dualblade, Jang'thraze, Sang'thraze, Blade of the Basilisk, Truesilver Champion, Flame Wrath, Spire of the Stoneshaper, Reforged Spear, Julie's Dagger.
  - Casters: Hand of Edward the Odd, Wit's Edge, White Obsidian Wand. These clear when your next spell uses them.
  - Sprinter's Sword.
- In combat, a Strength jump only counts as a weapon's proc while that weapon is equipped, so Destiny can't be mistaken for two Crusaders.
- Buffs that share a name (Haste, Enrage, Holy Shield) are matched to the weapon you have on.

## 2026-11-26

Proc City 1.1.0
- Tracks the new WoW Forever weapon enchants Insight (+100% Spirit for 10 sec) and Revelation (next spell +100% crit). Their buff IDs aren't published yet, so they're matched by name, and Proc City learns the real ID and duration the first time it sees them out of combat.
- Revelation's icon goes away when you cast your next spell, since that spell uses it up.
- Recovery isn't shown: it's an instant heal with no buff to time.

Proc City 1.0.0 (new)
- A movable row of icons for your procs and short buffs, growing left or right, with the seconds left on each and an optional clock sweep.
- Every class: talent procs (Flurry, Enrage, Clearcasting, Vengeance, Nature's Grace, Shadow Trance, Quick Shots, Spirit Tap, Remorseless Attacks, Redoubt), class cooldowns, racials, Crusader, item procs and on-use trinkets. Any equipped trinket with a Use is picked up automatically.
- Crusader up on both weapons at once makes its icon glow.
- Reads your buffs exactly out of combat and learns their real durations; in combat it works from your casts, your Strength and the game's combat text, and corrects itself after combat. /proc debug prints what it sees.

Mage Services 1.9.0
- Pause / Resume button on the window. Pausing stops taking requests on that character (no list, alerts, glows or replies) until you resume, without turning the addon off. While paused the window shrinks to a slim bar with Resume. Also /ms pause, /ms resume and a key binding. Saved per character.
- Zone filter fixes: with your zone set to a city you're not standing in, people in your local General channel or using say/yell were counted as being in the picked city. They're now placed in the zone they're actually in.
- Guildmates and friends are placed automatically from the guild and friends lists, no /who needed.
- The two hide checkboxes are now one "Show requests from" setting: your city only, your city + unknown, or everywhere (rest dimmed). If neither box was ticked before, you get "your city + unknown". The window title shows how many requests were hidden. Also /ms filter here|nearby|all.

## 2026-11-25

Overpower Plates 1.5.1
- The action bar glow now finds your Overpower button more ways: it asks the game which bar slots hold Overpower, reads each button's slot several ways, and matches any rank of Overpower or a macro that casts it. Dominos bars are covered too.
- The glow is now part of the button, so it follows the bar's scale, and has a solid gold border that shows even if the glow texture is missing.
- /opp debug lists which action buttons it found Overpower on, to help track down setups where the glow still doesn't show.

Overpower Plates 1.5.0
- A gold glow now pulses around the nameplate icon for as long as Overpower is up (can be turned off).
- Your Overpower button on the action bars glows at the same time: Blizzard bars, Bartender4 and ElvUI. It follows the button when a stance swap pages your bars. On by default; /opp glow toggles it.
- Optional big Overpower icon in the middle of the screen, with a countdown sweep and your charge count. Off by default; turn it on in settings or with /opp screen, and place it with "Move screen icon" or /opp move.
- Test mode shows all of these.

Mage Services 1.8.1, Plate Threat 1.4.1, Overpower Plates 1.4.1, Target Arrow 1.2.1, Battle Shout Notice 1.3.1
- A short "What's new" list at the top of the settings page, covering the last few versions.

Mage Services 1.8.0
- The replies are now edited on the settings page, with a live example under each one. {zone} (where you are) can be used alongside {name} and {dest}. Emptying a box puts the original reply back.
- New, off by default: reply automatically when someone whispers you for a port or food. It only answers whispers, never Trade or General posts, and answers the same player at most once every 5 minutes (adjustable). When you can't help, such as a portal you don't have, it sends a separate "can't help" reply, which can be turned off. Rows you've auto-replied to are marked "replied".
- A warning shows if your replies promise an invite while "Invite them automatically" is off.
- New commands: /ms autoreply and /ms cantmsg.
- Update notice: addons can't go online, so Mage Services tells guild and group members running it which version it's on. If someone has a newer one, you get a chat message saying it's out and to update through the CurseForge app. Turn it off under "Updates" on the settings page.

Plate Threat 1.4.0, Overpower Plates 1.4.0, Target Arrow 1.2.0, Battle Shout Notice 1.3.0
- Update notice: addons can't go online, so each addon tells guild and group members running it which version it's on. If someone has a newer one, you get a chat message saying it's out and to update through the CurseForge app, with a reminder at each login until you do. Turn it off under "Updates" on the settings page.

Mage Services 1.7.0
- "Hide requests you can't help with" now also covers portals you don't have: ones you haven't learned yet, and the other faction's cities. Water requests count too until you can conjure water. The check reruns when you learn a spell.
- Before, it only hid people known to be in another zone and ports to the city you're already in. Requests that don't say where the player is (most Trade chat) stayed, because the addon can't tell. A new option hides those as well; leave it off if you want to use the ? lookup on them.
- Hidden requests no longer play a sound, flash or glow, and the portal button no longer offers a portal you don't have.

Battle Shout Notice 1.2.0
- Renamed from Battle Shout Reminder to Battle Shout Notice, to match its CurseForge page. The addon folder and your saved settings are unchanged.
- /bsn now works as well as /bsr.

Mage Services 1.6.0
- New setting, on by default: keep the gold amount out of payment messages, so what you charge isn't shared in party chat or whispers. Your earnings totals still record the real amounts. Turn it off on the settings page or with /ms amount; change the wording with /ms privatemsg.

Mage Services 1.5.0
- Whispers now work with WoW Forever's two-part names: Whisper opens a whisper aimed at the player's full name instead of typing "/w First Last", which went to the wrong player.
- Players are matched on their full name everywhere: requests, trades, payment messages and /who lookups, so two players with the same first name can't be mixed up. Greetings still use the first name.
- Earnings now include an all-characters, all-time total and a total of gold from every trade, all saved through logouts. Every total is split into portals and food & water.
- /ms earnings reset now clears this character only; /ms earnings reset all clears everything.

Overpower Plates 1.3.3, Battle Shout Reminder 1.1.3, Plate Threat 1.3.3, Target Arrow 1.1.3
- Credit line on the settings page: "Created by Miff, supported by Claude".

Mage Services 1.4.4
- Credit line on the settings page: "Created by Miff, supported by Claude".

All addons (Mage Services 1.4.3, Overpower Plates 1.3.2, Battle Shout Reminder 1.1.2, Plate Threat 1.3.2, Target Arrow 1.1.2)
- Settings page scrolling rebuilt from plain frames with its own scroll bar, instead of the game's scroll template, which didn't clip or show a bar in Forever. The page also clips anything past its edge.

All addons (Mage Services 1.4.2, Overpower Plates 1.3.1, Battle Shout Reminder 1.1.1, Plate Threat 1.3.1, Target Arrow 1.1.1)
- Settings pages now scroll, with a scroll bar and mouse wheel, so long pages no longer spill out of the options window.

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

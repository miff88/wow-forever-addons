# Craft Services

**Every enchant, craft and lockbox request, in one list.** Craft Services watches chat for people asking for your professions, knows which recipes you have and whether you have the mats, and follows each customer from the first whisper to the payment. It's Mage Services for every profession.

Made for **World of Warcraft: Forever**. Works on any class, for anyone with a profession (and rogues, for lockboxes).

## Features

### Every profession
- Enchanting, Blacksmithing, Leatherworking, Tailoring, Alchemy, Engineering, Jewelcrafting, Inscription, Cooking and First Aid, plus **Lockpicking** for rogues.
- Only lists the professions you have, or all of them dimmed if you prefer. Turn each one on or off.

### Knows your recipes
- Open each profession window once and it reads every recipe you've learned, with its materials and description. It updates when you learn something new.
- So it can tell "you know this and have the mats" from "you're short 2 Illusion Dust" or "you don't have this recipe".
- `/cs can crusader` tells you on the spot. `/cs shopping` lists the mats you're short of for everyone waiting.

### Understands what people ask for
- Links to recipes, items or enchants, and recipe names: "LF tailor runecloth bag".
- Enchant nicknames: "crusader", "+7 agi gloves", "minor speed boots", "2h int". When it could be two enchants, it asks them which rather than guessing.
- Notices who brings the mats ("have mats", "your mats").
- Ignores other crafters' adverts ("WTS", "LFW") and chatter like "crusader is the best enchant".
- Add your own phrases (`/cs add`) and words to ignore (`/cs exclude`).

### Replies that do the work
- **Whisper** opens a ready-made reply: "Hi Ana, I can do Enchant Weapon - Crusader for you for 5g. You're #2 in line. Sending you an invite." Edit them on the settings page.
- Different replies when you're short on mats, when they didn't say what they want, and for lockboxes.
- **Optional automatic reply** to whispers (never Trade or General), at most once per player every few minutes.
- **Optional automatic invite**, only when you know the recipe and have the mats (or they bring them).

### From request to paid
- Each customer moves through *replied*, *invited*, *in your group*, *mats received*, *trading* and *paid*. The window shows who's next and how many are in your queue.
- Repeat customers are tagged "regular", with their history in `/cs customers`.
- **Profession button:** the big icon on the window opens your profession straight to the recipe they want, or casts Pick Lock for a lockbox. Bindable to a key.

### Trade helper
A panel beside the trade window:
- **Mats checklist:** each reagent, how many are in your bags and how many they're handing over.
- **Their item:** whether the enchant fits what they put in the "will not be traded" slot, or for a lockbox, whether it's locked and your lockpicking is high enough.
- **Payment:** what they're offering against your price.
- **Enchant their item** (first click opens the recipe, the next puts the enchant on their item), **Pick Lock**, **Open recipe**, **Ask to pay** and **Ask for mats** buttons.

### Prices and advert
- Set prices with `/cs price crusader 5g` or on the settings page; they go into replies and the trade panel.
- Feature your best recipes and the **Advertise** button posts "LFW Enchanter and Tailor in Orgrimmar: Crusader, Minor Speed. Whisper me!". At most once every 3 minutes (adjustable), with a countdown on the button.

### Payments and earnings
- After a trade it posts the result in party chat, or a whisper if they've left: payment received, mats received, cancelled or failed. The gold amount is left out by default.
- Earnings saved through logouts, split by profession and by recipe: all characters, this character and this session.
- **Optional group tidy-up:** customers who've paid are removed from your group after a short wait. Only people you invited, only while you lead, never in combat.

### Hard to miss
- Message at the top of the screen, screen-edge flash and a sound of your choice.
- Dark and light themes, a full settings page under Options > AddOns, and an entry on the minimap's addon button.

## Commands

| Command | What it does |
|---|---|
| `/cs` | Open settings |
| `/cs recipes` | What it knows of your professions |
| `/cs can <recipe>` | Do you know it, and do you have the mats? |
| `/cs price <recipe> <amount>` / `/cs prices` | Set or list your prices |
| `/cs feature <recipe>` / `/cs featured` | Choose what your advert lists |
| `/cs ad` | Post your advert |
| `/cs shopping` | Mats you're short of for the current requests |
| `/cs customers` | Your best customers |
| `/cs autoreply` / `/cs autoinvite` | Turn those on or off |
| `/cs pause` / `/cs resume` | Stop or start taking requests on this character |
| `/cs filter here, nearby or all` | Which requests to show |
| `/cs earnings` | Your earnings |
| `/cs test` | Add sample requests to try the window |
| `/cs help` | All commands |

## Good to know
- Open each profession window once after installing so it can read your recipes. It still spots requests before that, it just can't check recipes and mats yet.
- WoW Forever hides chat text from addons inside dungeons, raids, Mythic+ and PvP, so requests are only picked up out in the world.
- The game only lets addons post in Trade from a click or key press, so the advert never posts by itself.

Created by Miff, supported by Claude. Source and changelog: [github.com/miff88/wow-forever-addons](https://github.com/miff88/wow-forever-addons)

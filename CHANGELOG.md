# Changelog

## Unreleased
- **Profession stop: no white outline.** Its map pin and minimap dot lose the light ring; a small centre stays.
- **Worn gear: an early warning.** When anything you wear drops under 20% durability an anvil shows above Flow's key
  (hover: which item, the nearest repair vendor Flow knows) and the route gets a Repair stop. Options: "Warn early when
  gear wears out".
- **Repair after selling.** At a vendor Flow now sells first and repairs after, so the sale helps pay; it says once when
  you still can't afford it, and with auto-repair off it says the cost and leaves the button to you.
- **Hearthstone estimate.** Asking for a service that's far away (or the repair warning) says when hearthstone-then-run
  looks clearly quicker than going straight: at least 2 minutes and a quarter of the trip, counting its cooldown, the
  cast and the loading screen. It's an estimate, only for inns Flow knows, and Flow never uses the hearthstone for you.
- **Camp objects: placed is per campfire.** No more hour-long silence after placing one; your group's objects are listed
  as near you, elsewhere or unknown, and members who leave drop off the list.
- **One recovery order, always.** Out of a fight every heal goes through your order (bandage, food, heal spell by default):
  a heal spell no longer jumps ahead when your health is shown or the low-health warning is on, and "Cast heals" off
  means no heal spell. Fight healing is unchanged: healthstone, potion, then heal spells.
- **Well Fed food heals too.** Food that restores health and also makes you Well Fed is eaten to heal when you carry no
  plain food (right-click the Flow key to keep it for the buff).
- **Alt + easy key: healthstone or potion.** Set before the fight, so it works in one even when the item is on none of
  your bars. It can't switch mid-fight (WoW's rule).
- **Profession marker and path.** The faint profession arrow's stop now has its own pin on the world map and a dot on the
  minimap, in the arrow's smoked-glass colour with a light ring, plus a dotted path through your next profession stops.
- **Farm it here, not at the bank.** A profession plan only sends you to the bank when the banker is close or the material
  can't be had on this map. Wolves around you beat 2 meat from a bank across the zone.
- **Dungeon runs (needs Questie).** Flow plans one dungeon run at a time: the quests you can do
  on this trip, at your level, in one wing. Later parts of a chain, quests above you and other
  wings wait for the next run. Lead-in quests are traced back to the first one you can take now
  (up to 3; "Include long lead-ins" per dungeon for more), and quests you can't get say why once
  (class, race, reputation, profession, other faction). The arrow menu's new **Dungeons** section
  lists the runs at your level with how they compare to your questing XP per hour (measured, or
  estimated until Flow has 15 minutes of your questing): **Prepare this run** puts the pickups and
  lead-ins on the route, then the entrance; **Straight to the entrance**; **Share quests** in a
  group for the run quests party members lack. Inside, the route shows only that dungeon's
  quests. Flow times your runs and uses your own run time from then on. "Suggest dungeons" turns
  the suggestion off. A quest Questie files under its giver's zone counts for the dungeon when
  all its objectives are in there. Scarlet Monastery, Blackrock Spire (Lower / Upper) and
  Stratholme (Live / Undead) are split by their bosses: a quest that targets a boss, or an item
  a boss drops, is that boss's wing; other creatures go by the bosses' levels. A breadcrumb to a
  run quest goes on the route when its giver is within 150 yd of a stop you make anyway. It's
  optional: dropped if it's a detour, and it never holds back the real quest or the entrance.
- **Your weapon stone goes on with one press, and food that makes you Well Fed too.** When
  you're about to kill a lot (at a kill or loot stop, or right after a fight) and your main hand
  has no sharpening stone, weightstone or oil on it, the Flow key (out of combat, not in inns or
  cities) puts the one in your bags on it, no more opening bags and clicking the weapon. Stones
  and weapon oils are now found by name too, not only when the game files them as an item
  enhancement. Never oil on a fishing pole. It shows on Flow's icon ahead of the out-of-combat
  buff the rotation suggests (a paladin's seal, say), except when an enemy is targeted or you're
  under half health. Same moment, if you aren't Well Fed and carry food that says it makes you
  Well Fed, the Flow key eats it, after elixirs and the stone (you sit for ten seconds). Plain
  food is left alone.
- **Campfire buffs.** Near a lit campfire (yours or another player's, "Campfire Nearby") without
  its camp buffs, Flow's key sits you down; it shows "Stay sitting" while the minute runs (a
  press does nothing, so it never stands you up), then goes once the buffs are on. Not in combat,
  mounted or fishing. The camp objects you carry or know (a tent, a mana well, a lute...) are
  placed first, then you sit again so the buffs include them. In a group, party members running
  Flow tell each other which objects they could add: a camp status icon above the key shows how
  many, and hovering it lists who has what. Flow can't see the bags of players without it.
- **Buff timer on the Flow icon.** When Flow suggests re-casting a buff that's still on (a
  blessing, a seal, Mark of the Wild on a party member...), the icon shows the seconds it has left
  once it's under 30, in light blue. Cooldown numbers still take the middle when there is one.
- **Healthstone, then potion, at low health in a fight.** When the game's low-health warning is
  on (or you're at a third of your health, where it's shown), Flow's icon shows your healthstone,
  else your best healing potion, ahead of any heal spell, for every class. The key is locked in a
  fight, so press it on your bar: it glows there.
- **After a fight: bandage, then food, then a heal spell.** Hurt out of combat, the Flow key uses
  your best bandage (not while Recently Bandaged), then food that heals (when you're quite hurt and
  no enemy is targeted), then your heal spell. **Right-click the Flow key** for the options: the
  order of the three steps, turning any of them off, best or lowest bandage first, the in-fight
  healthstone/potion, and placing camp objects. Right-click never casts.
- **Status icons above the Flow key** (between fights, no chat spam): a small row for things to
  sort out (so far: what your group can add to the camp). Hover one for what it means; the key's
  own tooltip lists them too. Turn the row off from the key's right-click menu.
- **Auto-repair**: opening a vendor who repairs fixes everything if you have the gold, and says
  what it cost (Options: "Auto-repair at vendors", on by default).
- **The route on the world map is a faint dotted trail**, like a treasure map, instead of a solid
  line with crawling chevrons: it shows the way without covering the map. The stretch from you
  to your next stop (and that stop's dot) wears the arrow's colour, so with the distance colours
  it turns from red to green as you close in; the rest of the route is fainter. Your waypoint's
  trail is dotted too. Nothing moves every frame any more (the dots are redrawn only when you
  move or the colour changes); /flow perf shows them as "route dots".

## 0.35.106
- **New quests are accepted for you.** Talk to a quest giver and Flow turns in your finished
  quests first, then opens their new quest and accepts it. A quest started by an item is
  accepted too. Before, Flow only accepted quests your party shared with you. Grey (low level)
  and repeatable quests are left to you, and nothing is accepted when your quest log is full.
  Hold Shift at the NPC to do it yourself; there's a box in Flow Settings, or `/flow accept off`.

## 0.35.105
- **The Flow Arrow's drawer has a pin button**, top right, where Flow's other views have their
  close button (a red square like it). A gold pin standing straight means pinned: the drawer stays
  open as the arrow moves on to the next stop, and after a /reload. A grey, tilted pin means it
  folds when the mouse leaves. Click the pin to switch.
- A drawer opened by hovering the arrow now waits a moment before folding, so you can move the
  mouse onto it (to pin it) without it folding away. The distance moved to the drawer's lower
  right to make room for the pin.

## 0.35.104
- **Fixed: the Flow key could turn your auto attack off.** When Flow had nothing new to suggest,
  the key was often still set to the Attack spell, and Attack switches your swing off if you're
  already swinging. Now the key uses the game's own "Start Attack" command, which only ever turns
  auto attack on. On a game without that command, the key holds nothing for the fight instead of
  Attack.
- **The key no longer does anything you can't see.** Out of a fight, a hidden button means the
  key does nothing. In a fight (where the key can't change), if Flow has nothing new to suggest,
  the button shows what the key still does, greyed out, instead of disappearing. `/flow key test`
  also says whether your game has Start Attack.
- Fixed a self-test for looting that passed for the wrong reason.

## 0.35.103
- **Fixed: the Flow key stopped working in 0.35.102, with "blocked" errors on every press.**
  The loot step's self-test stood in for some of the game's own functions (UnitExists and
  others) for a moment at login. That marks them as touched by an add-on, and the game then
  blocked every cast and Interact Flow's key made. The test no longer touches them; Flow's own
  checks (lint and an in-game test) now catch this.
- **Class training is back in its normal place on the route.** 0.35.98 sent you to the trainer
  first whenever it was close, even in the middle of killing mobs for a quest. Now you finish
  the quests where you are and the trainer fits in where it costs least, as before.
- **/ai and /si open Flow Chat** (short for /claude).
- **Long messages aren't cut off any more.** The game's chat box stops at 255 letters, so a
  long /ai message now opens in the Flow Chat window to finish (it takes 1000) instead of
  sending the cut-off part.
- Two self-tests fixed (the drawer can be Shift-dragged since 0.35.101; a saved position can
  come back as 99.99999).

## 0.35.102
- **After a kill, the Flow key loots the corpse.** With the dead mob still targeted, out of
  combat, the key shows "Loot <name>": walk up and press it. With Auto Loot on (Flow Setup) you
  get everything without the loot window. WoW doesn't let an add-on loot with no key press at
  all, so this is the closest it can be. Shift + key still heals. Turn it off with
  /flow action loot off.

## 0.35.101
- **The Flow Arrow's drawer opens beside the arrow again, on the side with room.** It opens below
  by default, above when the arrow is near the bottom of the screen, and to the right or left
  when the arrow is at a screen edge. (0.35.95 had moved it to the tooltip spot, away from the
  arrow.)
- **Shift-drag the drawer to give it a place of its own.** It opens there from then on, and the
  arrow's right-click menu has "Drawer next to the arrow (again)" to put it back.
- **A pinned drawer stays pinned:** click the arrow to pin it open. It follows your current stop
  as you go, and opens again after a /reload until you fold it (the ^ tab, a click on it, or the
  arrow). Shift-clicking the drawer no longer folds it.

## 0.35.100
- **Every new character starts with "Next stop only"**, so the map and the Flow Tracker look
  simple. How many stops you show is now each character's own setting; before, one character's
  choice carried over to all of them, new ones too. Your characters start back at "Next stop
  only" once; change it any time from the arrow's right-click menu or Flow Settings.

## 0.35.99
- **Death reports.** When you die, Flow says in chat what happened. For example: "died after 40 s
  fighting Bristleback Interloper (level 9, you 6); low-health warning 8 s before; heals:
  suggested 0 times, cast 0; Shift + key 0". It then lists up to 3 things that could have saved
  you:
  - the low-health warning came on but no heal was cast (Shift + your easy key heals you, even
    in a fight);
  - Flow suggested no heal, or only with the warning;
  - you were out of mana;
  - the enemy was elite or 3+ levels above you.

  Each report is saved, with what Flow suggested and what you cast. If you use Ask Claude, the
  bridge passes each death to the watching Claude session as a `DEATH` line. Claude does a
  post-mortem on how the easy button could have prevented it, makes that improvement, and tells
  you in a note (docs/ASK-CLAUDE.md).

## 0.35.98
- **Class training comes first when your trainer is close.** If spells are waiting, your class
  trainer is within about 300 yards, and you can pay for some of them, the arrow takes you there
  before anything else: new spells make every fight after it easier. Before, Flow Improvements
  said to train while the arrow went to the next fight (a new paladin in Deathknell). If the
  trainer is far away, training is still fitted into the route where it costs the least. Once
  you've been to the trainer at your level, it doesn't push to the front again.
- Fixed a self-test that still expected your own buffs to cast without `[@player]`.

## 0.35.97
- **Flow is on CurseForge:** [Flow (unfettered)](https://www.curseforge.com/wow/addons/flow-unfettered).
  From now on every release goes there automatically, the same day it's on GitHub, so the
  CurseForge app always offers the newest Flow. (The first upload there was 0.35.66; this
  brings CurseForge up to date.)

## 0.35.96
- **Flow Seller: Auto-cleanup.** After the Flow Seller sells something (auto-sell, or your
  click), your bags are tidied with the game's Clean Up Bags (the broom on your bags). It's an
  "Auto-cleanup" checkbox next to Auto-sell in the Flow Seller's header (on), and also in Flow
  Settings. If this client has no Clean Up Bags, the checkbox is greyed out and says so.
- **Every view is named "Flow ...":**
  - Ask Claude -> **Flow Chat**; New spell -> **Flow Spells**;
  - Professions / Your professions -> **Flow Professions**;
  - Key binding mode -> **Flow Key Bindings**;
  - the settings and setup pages -> **Flow Settings** and **Flow Setup**;
  - the "!" button's tooltip -> **Flow Improvements**;
  - chat messages name the **Flow Seller** (it was "vendor drawer").
  New views will follow the same rule.

## 0.35.95
- **Flow's tooltips open where WoW shows its own:** the spot you set in Edit Mode or the
  interface options, or at the cursor. Before, each opened next to whatever you hovered. That
  covers every Flow tooltip: the easy button, the arrow, the Flow Tracker and Router, map pins,
  the Improvements list, settings and the Seller.
- **The stop card and the arrow's drawer open there too.** A stop card you dragged somewhere
  stays where you put it. If your tooltips follow the cursor, the card and drawer keep their old
  places. Setting: "Tooltips where WoW shows them" (on).
- **Herbalism stops in Kalimdor.** The herbs there (Peacebloom, Silverleaf, Earthroot, Mageroyal,
  Briarthorn, Bruiseweed) have their own game object numbers, which Flow didn't have. So
  Mulgore had "no known Herbalism spot" and your "Camping 101: Herbalism" stop was stuck. The
  Flow Tracker's "herbs nearby" line sees them now too, and each herb is checked by name.
- **Heals keep coming until you're really topped up.** In your logs, after a 2-minute fight one
  Rejuvenation and one Healing Touch made Flow think you were nearly full, yet you went on
  healing. Each heal now makes up for less of the damage.

## 0.35.94
- **New spell ranks replace the old ones on your bars.** When you learn a higher rank, every
  action bar slot with an older rank of that spell gets the new one. It happens right away, or
  just after the fight if you're in one, and chat says how many slots changed. It only happens
  when you learn the rank, so a lower rank you put back on purpose (to save mana) stays.
  Setting: "Upgrade spell ranks on your bars" (on).
- **The next stops' NPCs get a smaller (o) too.** Walking into a camp, everyone you need there
  is marked. Pyall Silentstride, the cooking trainer for "Camping 101: Cooking", was stop 2 and
  had no mark. Mobs to kill keep their skull or diamond.
- **WoW: Forever's own trainers are found:**
  - from Questie by their title ("Cooking Trainer", "Druid Trainer");
  - from any trainer you've learned from, who counts as one for that profession from then on.
  Profession trainer stops and the (o) include them.

## 0.35.93
- **`/claude` opens a chat window** instead of only reloading (which looked like it did
  nothing). It shows what you asked and Claude's answers, with a box to type in, Send, and Check
  now. Sending and checking still reload for a moment: that's when WoW saves and reads the files.
  `/claude <message>` still sends straight away; `/claude check` looks for answers.
- **The new-spell card shows again.** It waited for a game event this client doesn't have (on
  newer clients it has another name), so it never appeared. Flow now compares your spellbook
  after every change, so a spell you learn gets its card. That happens even when the game
  already put it on a bar: the card says where, and offers to bind a key. New ranks of spells
  you have still don't ask. The route and the Flow key's actions now notice new spells too.
- **Your buffs go on you, even with a friend targeted.** A self-buff on the easy button (Mark
  of the Wild, Thorns...) used to land on your target. Now it's always on you.
- **Ctrl + easy key casts the shown heal or buff on your target instead.** (Shift + key is still
  your heal on yourself.) Setting: "Ctrl + easy key: on your target" (on).

## 0.35.92
- **Flow Improvements (the "!" list): click a row to hide it.** It goes under "+ Hidden (N)" at
  the bottom, collapsed. Click that to see what you hid, and click one there to bring it back.
  Hidden advice is kept per character. The count on the "!" button and the chat summary leave
  hidden ones out. A line stays hidden when only its numbers change ("Train 2 spells" ->
  "Train 3 spells").
- **A link button on each row opens what it's about:**
  - the stop on your route (its card, where you can go there next);
  - the spell (the card to put it on a bar or bind a key);
  - the item (its tooltip);
  - the profession picker, or the talent plan.
  The panel is now titled "Flow Improvements".
- **Short key names on the easy button:** "Mouse Button 5" shows as MB5 ("` / MB5"), with
  modifiers as S-, C- and A-, and Num Pad 3 as N3. The tooltip keeps the full names.
- **Quests Flow can't place are listed in `/flow nav why`** (and the diagnostics), with the
  reason: a quest Questie doesn't know, an objective with no location or of a kind Flow can't
  place, or no place to hand it in. They used to drop off the route without a word ("Dirt-stained
  Map").

## 0.35.91
Performance pass: fewer stutters while the route is planned, less work for the arrow.
- Planning the route is several times faster with exactly the same result: the nearest spot
  of each stop from each place is worked out once per plan (the polish asked it thousands of
  times), and trying a different order no longer copies the whole trip each time. Plans took
  20-50 ms each, enough to feel as a stutter every few seconds.
- Gathering the stops turns spawn spots into world positions with plain arithmetic on a flat
  zone map (checked against the game per map) instead of asking the game for each of
  thousands of spots.
- The arrow no longer sorts every stop by distance 10 times a second; that list is only made
  when there's no plan or you pinned a stop.
- Minimap areas ask the minimap's zoom, size and rotation once per drawing instead of once
  per spawn spot, and redraw when you've moved a pixel's worth (at least 2 yards).
- /flow perf: each line counts its own time only (planning inside the arrow update was
  counted twice), and stop gathering ("gather: questie", ...) and minimap areas have their
  own lines.

## 0.35.90
**Restart WoW once** for this version: it adds a file (Learned\Places.lua). Everything else works
after a /reload.
- **Share what your Flow has learned with every Flow player** (opt in). `/flow places share`, then
  `/reload`, then send it with a pull request; your Claude session can do that part if you ask it
  to "share my Flow places". Guide: [docs/SHARE-PLACES.md](docs/SHARE-PLACES.md).
  - What's shared: NPC names, NPC IDs, where they stand, what they do, and which faction used
    them, plus mailboxes. Nothing about you.
  - `/flow places share off` stops it.
  - `tools\share-places.ps1` merges a player's list into `Learned\Places.lua`, which ships with
    Flow. It checks every field and keeps the file sorted.
- **Flow uses spots other players shared** for NPCs you haven't talked to yourself, and only ones
  your faction can use. This covers your route's trainers and quest givers and "Nearest ...",
  which says when another Flow player found it. `/flow places` shows how many came with Flow.
- Each NPC Flow learns now also notes which faction used them.
- **Fixed: the riding trainer was taken for your class trainer.** Kar Stormsinger (the tauren
  kodo trainer) counted as a druid's class trainer: every trainer that wasn't a profession
  trainer did, and his riding lessons replaced your class spell list. Now a trainer counts only
  if it's one of your class's trainers, or teaches your class's spells. One saved wrongly is
  forgotten at login.

## 0.35.89
- **Flow learns who does what as you play**, for all your characters. Every NPC you talk to is
  remembered: where you stood, their NPC ID, and what they do for you. That covers vendors (and
  whether they repair), trainers, flight masters, innkeepers, bankers, auctioneers and quest
  givers. Mailboxes you open are remembered too. `/flow places` shows what it has learned (also
  in the diagnostics).
- **Fixed: Flow forgot merchants.** Talking to a merchant through their chat window overwrote
  them as a plain NPC, so Flow forgot they sell and repair. Now each visit only adds to what it
  knows.
- **Nearest flight master, innkeeper, banker, auctioneer and mailbox**, besides repair and
  vendor: in the arrow's right-click menu, or `/flow way flight | inn | bank | auction | mail`.
  It uses the ones you've used yourself plus Questie's data, and says when it's one you've been
  to.
- **Fixed: "Nearest" could pick the other faction's NPC.** A tauren could be sent to an Alliance
  vendor; now only NPCs friendly to you count.

## 0.35.88
- **The arrow is the same purple as the (o)** over the NPC you're heading to. Both always took
  the route colour (purple for "Most XP first"), but the 3D arrow shaded every edge and darkened
  its sides, so it read as a muddier purple. Its top is now the exact route colour, flat; the
  sides are only a little darker, and the white ridge along the middle is fainter. Other route
  colours (blue for Shortest path, orange for a Custom route, green for your waypoint) match
  their (o) the same way.

## 0.35.87
- **Heals come early now, long before your health is a problem.** Forever hides your health
  from add-ons all the time (Flow reads "0/0" even standing still), and its combat log is off,
  so Flow can't see damage either. It used to wait for the game's red low-health warning
  (about a third left), which was far too late. Now it keeps an estimate of how hurt you are,
  counted in seconds of being hit:
  - it goes up while an enemy is on you;
  - it goes down with your heals, with natural regen out of combat, and faster while you eat
    or drink;
  - levelling up resets it.
- **When Flow heals on that estimate:**
  - Out of a fight, a little hurt: your HoT (Rejuvenation) or a quick heal, even with an
    enemy targeted, so you top up before the pull.
  - Out of a fight, hurt more: the big heal (Healing Touch, Holy Light).
  - In a fight, after about 8 s of being hit: Rejuvenation if it isn't on you. After about
    20 s: your fastest heal. These show on the icon with a green "Shift+key", since Shift +
    key casts them mid-fight.
  - A HoT you just cast counts as on you for its duration, so it's never suggested twice.
- **Heal debug lines in the log** (`[heal]`, in the diagnostics):
  - each fight: how long an enemy was on you, and the estimate before and after;
  - each heal suggested and each heal cast, with the estimate;
  - each Shift + key press;
  - once a session, whether any real health or damage numbers are readable;
  - `/flow rot why` also shows the estimate.
- Replaces the old "15 s after a long fight" heal prompt.
- **Release zips:** `Flow.toc` no longer starts with an invisible byte-order mark, which WoW can
  misread as an out-of-date add-on (`tools\package.ps1`). Releases now also go on
  [GitHub Releases](https://github.com/Perpetuator-LLC/flow-wow/releases).

## 0.35.86
- **Profession trainers are stops on your route, not a waypoint.** The reminder card no longer
  has "Show me the way" (which set one waypoint, for the first profession only). It now says
  where each trainer is on your optimal route, however many there are. For example: "Learn
  Herbalism: stop 4 on your route (Komin Winterhoof, Thunder Bluff, 1240 yd)". To go to one
  next, click its ^ in the Flow Router, as with any stop.
  - If your route leaves trainers out (Quests only, or Optimal without professions), the card
    shows "Add to my route", which switches to Optimal with professions.
  - If Flow can't place a trainer yet, the card says so.
- **Druid out of mana:** in caster form with no mana for Wrath, the easy button now says to hit
  it with your weapon. Before, it showed nothing (52 of 131 checks in one fight).

## 0.35.85
- **Shift + your easy key heals you, even in a fight.** WoW doesn't let the easy key change
  what it casts during a fight, so a heal Flow showed mid-fight couldn't be cast until your
  enemy died. Shift + key now always casts your fastest heal on you (Rejuvenation, Flash of
  Light...). It's set before each fight. When the icon shows a heal in a fight, the key label
  turns green: "Shift+`". Clicking or shift-dragging the icon is unchanged. Setting: "Shift +
  easy key heals you" (on).
- **Curses, poisons and diseases.** Out of combat, the easy button removes them from you first,
  then your group's tank, healers and everyone else, alive and in range.
  - Druid: Remove Curse, Abolish Poison or Cure Poison.
  - Paladin: Cleanse or Purify.
  - In a fight, only a healer is shown them, and only for someone else, so a poison on you
    never pushes your attacks off the icon.
- **Breaking free:** a druid shown how to escape roots by changing form (never into the form
  you're already in). This joins the racials and Blessing of Freedom.
- **No hard quests offered:** quests to pick up stop at 2 levels above you (orange and red ones,
  3+ up, come back as you level). Quests already in your log that are 3+ levels up are planned
  after the easier ones, with a note saying why.
- **L (quest log) moves the Flow Router aside** so you see the quest log. It's back the next
  time you open the map.

## 0.35.84
**Restart WoW once** for this version: it adds a file (Bonus.lua). Everything else works after
a /reload.
- **The easy button buffs your party and raid**, the right buff for each person. Out of combat,
  with nothing else to press, it casts on whoever is missing one (alive and in range), and the
  icon says who it's for ("on Zed").
  - Druid: Mark of the Wild for everyone; Thorns for tanks and warriors.
  - Paladin: one blessing each. Kings for a tank (once you have it), Might for melee, Wisdom for
    casters, healers and hunters (Might doesn't help them).
  - Roles come from the group finder, else the class (a druid by its form).
  - Setting: "Easy button buffs your group" (on).
- **Profession reminders.** A small card says what to learn or train next and which trainer,
  with "Show me the way" to point the arrow there. It opens for 8 s (it waits while your mouse
  is on it) after you log in, when you level up, when a skill reaches its cap, and in a town
  where a trainer you need stands. Buttons: "Not now" (until your next level) and "stop
  reminding". From level 5. Setting: "Profession reminders"; `/flow prof remind` shows it now.
- **Druids level with Herbalism + Skinning** (was Herbalism + Alchemy). Two gathering skills
  earn the most gold with no time spent crafting; tauren get +15 Herbalism. At max level, swap
  Skinning for Alchemy.
- **Bonus mode** (off by default): extras just for fun, in /flow settings or `/flow bonus on`.
  The first is **Spoken**: NPCs read their words aloud with the game's text-to-speech, in a
  man's or a woman's voice to match them. `/flow bonus say` tests it.
- **Quests missing from the route:**
  - The next part of a chain now waits only for an earlier part you can actually do (in your
    log, or on offer). Optional lead-in quests you'd never get were hiding real quests.
  - A failed scan for quests to pick up is logged and tried again 30 s later; before, it stayed
    empty until your next turn-in.
  - `/flow nav why` says what the scan found and why it left quests out.
- **Horde city trainers** (Thunder Bluff, Orgrimmar, Undercity) are looked up by NPC ID too.
  `/flow nav why` explains where the lookup stops for any it still can't place.
- "Follow current quests" is now called **"Quests only"** (route menu and map panel).
- Diagnostics: the rotation check saved at logout is the last one taken while playing. At
  logout the game reports nothing as castable, which looked like a missing-buff bug.

## 0.35.83
- **/claude without installing anything.** The bridge no longer runs the `claude` command line.
  It prints each in-game message as an `ASK` line for a Claude session you already have open
  (Claude desktop or Claude Code: tell it "watch Flow's in-game chat"). That session makes the
  change and answers with `tools\claude-bridge.ps1 -Reply <id> -Text "..."`. CLAUDE.md tells any
  Claude session how. The old automatic mode is still there as `-Cli`.
- **Quest drops: one hint instead of a "!" everywhere.** Questie marks every spawn of every mob
  that drops a quest-starting item with a "!", which fills the map and minimap. Flow now:
  - shows one line in the Flow Tracker when those mobs are near you, "quest drop: Bloodstained
    Note (Bristleback Quilboar)" (hover for details);
  - puts a yellow "!" on those mobs' nameplates only;
  - offers, in its setup suggestions, to turn off Questie's "Available Quests from Items"
    markers (the same switch as in Questie's own settings).

## 0.35.82
- **Ask Claude from inside the game.** `/claude make the arrow green` (or `/flow ask ...`) saves
  your message and reloads. A small script on your PC, `tools\claude-bridge.ps1`, hands it to
  Claude Code in your Flow folder, which can answer and change Flow itself. `/claude` on its own
  reloads to show the answer ("Claude: ...") along with any change. The script is woken by
  Windows when WoW saves (no polling) and keeps one conversation going.
- **Updates by themselves.** The same script checks GitHub each time WoW saves. A clean clone on
  `main` moves to the newest Flow, and you're told in game "Flow updated: 0.35.81 -> 0.35.82.
  Type /reload to load it" (or to restart WoW when files were added). Clones with changes of
  their own, or on another branch, are never touched.
- Setup for everyone: [docs/ASK-CLAUDE.md](docs/ASK-CLAUDE.md). It covers Claude Code, starting
  the bridge, starting it with Windows, and the options (`-NoClaude` for updates only).

## 0.35.81
- **Two keys for the easy button.** /flow settings has a "Second key" row under "Your key",
  with its own Set and Clear buttons. Both keys cast Flow's suggestion, and the icon shows
  both ("` / F").
- **The arrow points straight at your stop.** It used to follow trails you'd walked whenever
  one was up to 4 times longer than the straight line, and pointed at the next trail point
  even after you'd passed it, so it wandered. Now:
  - outdoors it points straight at the stop;
  - into caves and buildings it still follows the way you walked in, or heads for the
    entrance;
  - "Arrow follows paths you've walked" (/flow settings, off by default) uses outdoor trails
    again, but only ones at most 1.5 times the straight line, and it leads to the furthest
    trail point ahead of you instead of one behind.

## 0.35.80
- **A gentle start for new players.** The first time anyone uses Flow, nothing is on screen at
  login (no intro, no arrow, no Tracker). Flow's pieces fade in one at a time as you play, each
  with one line saying what it is:
  - the **arrow** (and the minimap marks), once you walk a few steps;
  - the **Flow Tracker**, 20 s later or when you accept a quest;
  - the **easy button's icon**, when you target an enemy or get into a fight (the key works
    before that too);
  - the **"!" advice button** and the setup suggestions, at your first level up or after
    10 minutes.

  Anyone already using Flow sees everything as before. `/flow reveal all` shows it all now;
  `/flow reveal reset` replays the tour.

## 0.35.79
- Nameplates: the unit you're heading to (the mob to kill or loot for your current stop, or
  its NPC) now shows **only Flow's (o)**, with the objective's count beside it, instead of the
  (o) plus a diamond or skull. Every other unit keeps its skull, diamond or star.

## 0.35.78
- **New spell card.** When you learn a spell, a small card shows it for 10 s. It waits while
  your mouse is on it, while you drag, and while you choose a key. You can:
  - drag its icon onto any bar slot;
  - **Put it on my bar** (the first empty slot, main bar first; it says where);
  - **Bind a key...**: press the key you want. Flow shows what that key does now, warns if it
    moves you, and changes nothing until you click "Yes, bind it". The key casts the spell
    directly, no bar slot needed;
  - **Not on my bars**: Flow stops asking you to put that spell on your bars.

  New ranks of spells you already have, passive spells, and spells learned mid-fight (they
  wait until it ends) don't ask. Setting: "New spells: offer to place or bind them".
- **Hover-to-bind is easier to find.** It's in the arrow's right-click menu ("Key bindings:
  hover a button, press a key..."), on Flow's settings page under your cast key, and on the
  new spell card. Nothing changes until you click Save, as before.
- **Heals land on you with no target.** The game's Auto Self Cast is now one of Flow's setup
  suggestions. Flow's settings show the key that forces a heal onto yourself even with
  someone else targeted ("Heal yourself: hold": Alt, Ctrl, Shift or None).
- The "Put X on your action bars" advice skips spells you said no to and spells a key casts
  directly.

## 0.35.77
- **Flow's (o) over the NPC you're heading to.** The turn-in, quest giver or trainer of your
  current stop wears Flow's target marker above their nameplate, in the route colour (purple
  on Most XP), on top of any quest marks. The party member you follow gets a green one.
  Friendly nameplates need to be on (Shift+V, or /flow quest plates). This replaces the
  orange raid circle, which only showed when nothing else was marked.
- **Following a party member works from the waypoint menu.**
  - "Follow Zed" and "Waypoint at Zed" are now in the route menu's **Your waypoint** section.
  - You can also type a party member's name into "Set a waypoint...", or `/way Zed`.
  - "Clear your waypoint" also stops following.
  - Party members are found by name more reliably, and Flow players who shared progress
    count even if the game hides their name. Following no longer stops at the first roster
    update.
  - `/flow party` and the diagnostics say where the position comes from: the game, sent by
    their Flow, or unknown.

## 0.35.76
- Fixed a Lua error that broke "Stops on the map". Two Flow functions had the same name, and
  the one that opens a stop's card replaced the one that decides which stops the map and the
  Flow Tracker draw, so every redraw failed ("attempt to index local 'goal'").
- Horde characters are no longer sent to Alliance trainers. Profession trainers now include
  Thunder Bluff, Orgrimmar and Undercity, and an NPC of the other faction is never used as a
  stop.
- Quests to pick up: none 4+ levels above you (a new level-1 tauren was sent 700 yd for a
  level-8 quest; they come back as you level). The next part of a quest chain no longer
  shows before you've done the part before it.
- The menu's full-screen "click outside to close" layer can never stay up without the menu
  (if it ever did, the game couldn't be clicked). If that's ever caught, it's logged.
- Self-tests that assumed a Paladin, or the old "all stops" default, now work on any class.

## 0.35.75
- **Finish a zone before leaving it.** The route does this zone's quests before heading to
  another zone. Exceptions:
  - Quests too low (less XP) or 3+ levels above you don't hold you here.
  - A stop just over the border, or your class trainer, can come any time.
  - A turn-in here that needs the next zone first doesn't hold you either.

  Waiting stops say "(Westfall, after this zone)". The Flow Router and the Flow Tracker say
  "Finishing Elwynn Forest first". It's on by default; switch it off in /flow settings.
- **Join the party route.** The Party section of the route menu (and the line under the
  arrow) now offers Your own route, **Join the party route**, or Just Bob's quests.
  - Everyone who joins gets one route for all their quests: objectives, quest items and
    turn-ins.
  - It's **the same route and the same next stop for all of you**. One of you plans it (the
    group leader if they've joined, otherwise the first name) and sends the next 8 stops in
    one short message whenever they change. If that planner goes quiet for 90 s, everyone
    plans for themselves.
  - Flow asks when a Flow player in your group first shares progress, and again when someone
    joins the party route.
  - `/flow party join` and `/flow party leave`.
- Less party traffic: quest progress is now sent as **only what changed** (usually one short
  message after a kill), with the full list only when someone joins or asks.
- The party route is quests only, so everyone plans from the same kind of stops. A
  hand-made route shared with `/flow party share` still works and shows as "Shared stops".

## 0.35.74
- **Hover the easy button** to see the spell's (or item's) own tooltip, why Flow suggests it,
  what the key is locked to in a fight (when that's different), and the next three
  suggestions, each with its reason. Each **on deck** icon has its own tooltip too.
- **Buff items on the Flow key.** At a kill or loot stop (quest mobs, farming meat or cloth),
  or right after a fight, the key offers an elixir, flask or scroll you carry whose buff isn't
  on. If your weapon has nothing on it, it offers a sharpening stone (edged weapons),
  weightstone (blunt) or oil instead. It's out of combat only, never in inns or cities, and
  one press uses it.
- **Batch crafting bar.** Making several at once (Create All, or a count) shows a second bar
  under your cast bar for the whole batch, "Making Charred Wolf Meat 3/10". It fills as each
  one finishes and says "Stopped" if you move.
- **Auction house prices and a watch list.**
  - Opening an auction house looks up the cheapest buyout of what you'd sell there and of
    your watch list, and records anything you browse.
  - Item tooltips show "Auction house: 1g 20s each, 3 h ago". The Flow Seller uses these
    prices to choose between the auction house and a vendor.
  - `/flow ah watch <item> [gold]` tells you (with a sound) when an item is listed at or under
    your price. `/flow ah` lists the watch list; `/flow ah unwatch <item>` removes one.
- The Flow Tracker and world map now show **just the next stop** by default. Choose 3, 5, 10 or
  All in /flow settings or the route menu.

## 0.35.73
- **Whose quests your route covers**, in a group with other Flow players:
  - **Mine:** your own quests.
  - **Combined:** yours and every Flow party member's, planned as one optimal route. Each
    spot is visited once and says who it's for.
  - **Just Bob's:** only what Bob still needs, where he hands in, and your own stops only
    where you need the same thing.

  Choose it from the "Quests: ... (click: change)" line under the arrow, the route menu
  (right-click the arrow, or the Flow Router's Route menu), or
  `/flow party quests mine|combined|<name>`. When someone's progress first comes in, Flow
  asks once: Combined, Just Bob's, or Not now.
- A party member's stop that you've already done yourself (that objective, or the whole
  quest) now says **(done for you)**, so it's clear it's only for them.
- **Follow a party member:** the arrow points at them in green and keeps following as they
  move. "Following Bob (click: stop)" shows under the arrow; the route carries on underneath.
  **Waypoint at Bob** drops your waypoint where Bob is right now. Both are in the route menu's
  "Party members" section, or use `/flow follow <name>|off`. Where the game hides a party
  member's position, Flow players send it to whoever follows them.
- Paladin: a seal is suggested whenever you have none, not only once you target an enemy, so
  it's already up when a fight starts. (A fight that started without one locked the key to
  Judgement, which can't work without a seal.) Not in inns and cities.
- New, off by default: **Leave junk behind when looting** (/flow settings). Grey items stay in
  the corpse and everything else is looted for you. The game's Auto Loot can't skip junk, so
  Flow does the looting while this is on and gives Auto Loot back when you turn it off. Hold
  Shift to loot by hand.

## 0.35.72
- Quest sharing in a party. A quest you pick up is shared when a party member doesn't have
  it. When a Flow player joins (or their quest list comes in), the quests you have and they
  don't are shared one every few seconds, skipping ones they're too low a level for. Each
  quest is offered to each person once per group.
- Quests a party member shares with you are accepted for you, and so are escort quests they
  start, unless your quest log is full.
- On by default: "Share quests with your party" in /flow settings, or /flow share on|off.

## 0.35.71
- Fixed: in a group, Flow asked "Help <you>?" about yourself. The game echoes your own party
  messages back, and this client adds your realm to your name ("Name-Realm"), so Flow didn't
  recognise them as yours. Your own messages (quest progress, party route) are now always
  ignored, while someone with your name from another realm still counts as someone else.

## 0.35.70
- Profession nodes near you: soft clouds on the minimap where ore (tan) and herbs (green) your
  professions can gather spawn, so you can mine Iron while you're in a quest's area without
  it becoming a stop of its own.
- The Flow Tracker gets a line under its stops: "Nearby: Iron Deposit x3 +skill, Kingsblood
  x2", counting spawn spots within 120 yd of you and your next stop. +skill means the node
  still raises your skill; hover the line for the details.
- Only professions you've learned and nodes your skill can gather are shown (Copper to
  Rich Thorium, Peacebloom to Black Lotus). These are spots where a node can appear; the
  game's Find Minerals / Find Herbs shows which ones are up right now.
- On by default: "Profession nodes near you" in /flow settings.

## 0.35.69
- Party quest progress: Flow players in a group now share how far they are on every quest
  (each objective's count, like 3/10, and whether it's ready to hand in). It updates a couple
  of seconds after anyone's quest log changes.
- When a party member's progress arrives, Flow asks once: "Put Bob's priority list first on
  your route?" Click **Help Bob** and the objectives Bob still needs come first on your route
  (kill credit is shared in a party), plus where Bob hands in, then your own stops. Bob's
  stops say "Bob: ...". Anything your own quests already cover isn't doubled up.
- "Helping Bob (click: stop)" shows under the arrow. `/flow party help Bob` starts it,
  `/flow party help off` stops it, and it stops by itself when either of you leaves the group.
  `/flow party` lists who has shared progress.

## 0.35.68
- Each character has its own Flow data now. "Ways to improve" (and the route) showed the last
  character you played, because everything was saved once for the whole account. Fights,
  learned heals, your class trainer, recipes, reagents, profession plan, role, hidden stops,
  bought-back items and the like are now saved per character. Settings, learned trails, cave
  entrances and NPC places stay shared, since they're the same for everyone.
- Your old data is sorted out the first time each character logs in: fights and learned heals
  go to the class whose spells they used, the class trainer list to its class, and recipes to
  the characters with that profession. Plain-Attack fights can't be told apart, so they're
  dropped, and short-lived things (quests an NPC didn't offer, money-blocked stops) start fresh.
- The diagnostics snapshot says which character it's from.

## 0.35.67
- The route looks further ahead: up to 30 stops instead of 14. The nearest stops are still
  ordered carefully, and the rest follow on nearest-next, so re-planning costs no more than
  before.
- New: **Stops on the map**. Choose how many of your next stops the world map and the Flow
  Tracker show: just the next one, the next 3, 5 or 10, or all of them. It's in /flow settings,
  in the arrow's (and Tracker's) right-click menu, and `/flow nav stops 1|3|5|10|all`. The
  Flow Router still lists the whole route, and a stop you point at there always shows on the map.

## 0.35.66
- Finished quests are turned in for you: talk to the NPC and Flow opens the finished quest,
  presses Complete and takes the reward. With several rewards to choose from, you pick (the
  green arrow is Flow's pick for you). Quests that take gold are left to you, and holding
  Shift at the NPC lets you do it yourself. On by default; there's a box for it in
  /flow settings, or use /flow turnin on|off.

## 0.35.65
- Group invites from your friends (WoW friends list and Battle.net friends) are accepted for
  you. Anyone else still gets the usual popup. Turn it off in /flow settings or with
  /flow invites off.
- Quest rewards: a big green arrow (the same one as "equip this" in your bags) marks the best
  pick for your character, the biggest upgrade for the spec you're levelling. It shows when
  you're offered the quest and again when you turn it in.
- Gear advice never suggests something your class can't wear or wield, even for a class Flow
  has no class data for yet (a new Druid was told to equip mail, shields and swords).
- When you press a Flow Action such as "Equip X", what the game says back goes in the
  diagnostics ("You can't use that item"...), so a failing equip shows why.

## 0.35.64
- Druids are supported. Flow suggests Mark of the Wild and Thorns, then Moonfire and Wrath as
  a caster. In Bear Form it suggests Demoralizing Roar and Maul (Swipe on several enemies); in
  Cat Form, Rake, Claw and Ferocious Bite at 4+ combo points. The cast key stays on your form's
  main attack for the fight (Wrath, Maul or Claw). You get heal prompts (Rejuvenation, Healing
  Touch, Regrowth) in caster form, Druid gear stats (Feral, Restoration), trainer spells and
  class trainers (night elf and tauren), and Herbalism + Alchemy as the suggested professions.
- A brand-new character now gets an arrow to their first quest. Quests to pick up used to
  come only from zones where you'd already finished a quest, so with none finished there
  were none. Now the zone you're standing in counts too, as do the zones of quests in your log.
- When the game hides your target's debuffs, Flow remembers your Moonfire, Rake and
  Demoralizing Roar on that mob, so it doesn't keep suggesting them.
- Most XP: quests 3+ levels above you always wait, even at level 1 (a level-4 quest's
  bigger XP used to put it first at level 1).

## 0.35.63
- The world map costs far less while it's open. It used to draw your whole route again
  twice a second; now it does that only when something on it changes (the route, the map,
  the zoom, the stop you point at, the colours or your waypoint). In between, only the lines
  that start at you follow you.
- Mob areas on the map keep their worked-out shape, instead of grouping every spawn again on
  each redraw (that made most of the map's garbage). The moving chevrons only change what moved.
- /flow perf splits the map into "full redraw", "keeping up with you" and "moving chevrons"
  (the chevrons weren't counted before).

## 0.35.62: first public release
Flow's first release on CurseForge, for World of Warcraft: Forever. What's in it:
- **Rotation helper** (paladin): shows the spell to press next and lights up its action bar
  button; click the icon or press your Flow key to cast it. Keeps your seal, blessing and aura
  up, and still heals in time although Forever hides your health from add-ons.
- **Route planner and 3D arrow**: plans your quests and town errands by most XP, shortest path
  or your own pick, on the world map, the minimap and the Flow Tracker. Shows the quests you
  missed and which quests a mob is part of. Best with Questie + QuestieDB installed.
- **Gear and bags**: gear scores for your role, badges on quest rewards, bag icons that say why
  to keep or sell, and the Flow Seller to sell the junk in one go.
- **Professions**: skill plans that become stops on your route, and "make exactly enough" on
  the profession window.
- **Advice list**: training, talents, skill books and other things worth doing now.
- Colour-blind palette, lite mode, Shift-drag to move anything, `/flow help` for every command.
- Paladin only for now. Flow is built so other classes can be added: see CONTRIBUTING.md.
- Flow is free software under the GNU GPL v3 (see LICENSE). You can use it, change it and
  share it, as long as what you share stays under the same licence and keeps the credits.

## 0.35.61
- Your own waypoint is green now (arrow, map line and (o), and its line in the Flow Router),
  so it never looks like a Custom route. Orange means Custom route only. (Colour-blind
  palette: a bluish green.)
- The Custom route button in the Flow Router is greyed out while you're on Most XP or
  Shortest: it comes on by itself when you pick a stop's ^. Same in the right-click menus.

## 0.35.60
- Finished quests are on the route again. Flow looked for each quest's turn-in NPC under a
  name Questie no longer uses ("Finishes"; today's Questie says "Finisher"), so no turn-in
  ever had a place on the map and none made the route. Turn-ins near you now come first, with
  the quest pickups there, before heading out.
- Custom route is back, in the clear orange: pick your next stop with its ^ in the Flow Router
  (or right-click a stop: Go here next). The route goes there first and stays orange, not
  optimised, until you choose Most XP (purple) or Shortest (blue) again. The colour always
  says which you're on, and the Router and menus have all three.

## 0.35.59
- The map: the stop you're heading to has a white ring; every other stop a black one.
- Choosing stops is simpler. Click a stop: open it. Its ^ in the Flow Router: it moves to the
  top, the rest of the route is re-planned after it, and it gets the (o). The (o) is always the
  top row, and nothing else is marked: no more red "selected" stop, and no "From selected"
  order (the route keeps its colour). Click the (o) of a stop you moved, or "Usual order" in
  the menus, to go back.
- Your own waypoint (Ctrl/Alt-click the map, /way, "Point the arrow here") is no longer pushed
  into the route as stop 1. The arrow turns orange and points at it along an orange line on
  the map; the Flow Router shows it as an orange line above the route, with an X to clear it.
  The route waits underneath and the arrow goes back to it when you arrive or clear it.

## 0.35.58
- The dark oval behind FLOW in the login intro is softer: about half dark in the middle,
  fading out to nothing at its edges, so the pillars show through around the word.
- Flow Seller has the same title bar as the Flow Tracker and Flow Router (dark bar, orange
  accent, an icon, gold title). All three now come from one place, so they stay matched.
- Right-click menus: "Move on (hide this for now)" is now "Hide this stop".

## 0.35.57
- Quests could go missing from the route while you stood right where they're done (Red Linen
  Goods among the Defias). Flow keeps up to 80 spots per objective, and it took the first 80
  Questie lists: one mob with lots of spawns filled them from one corner of the zone, and the
  other eight mobs that drop the bandana got none. Spots are now spread over every spawn of
  every mob, your current zone first. Professions' gathering and vendor spots too.
- `/flow nav why` (and the diagnostics) list quest objectives that aren't on the current plan,
  with how far their nearest known spot is.
- Two self-tests failed on completionist routes (they assumed the default route): fixed.

## 0.35.56
- Flow's code is now checked before you ever /reload: a Lua checker (luacheck) reads every
  file for the kind of slip that used to reach you as a Lua error or a dead button (a name
  typo, a missing "local", using something before it's set up). The whole add-on passes with
  no warnings. No change in game: the tidy-up removed unused leftovers only.

## 0.35.55
- The Flow Router's Route dropdown didn't open: the same waypoint error as the arrow menu
  (fixed in 0.35.54). Menus now fail safely: if building a list ever errors, it's logged and
  said in chat, and the menu still opens.
- The arrow turns with your character, only. The map-style and minimap modes are gone (neither
  turned the way you look). It can't follow the camera as you swing it around: the game
  doesn't give add-ons the camera's direction.
- Catching breakage sooner: Flow runs its self-tests 8 seconds after every login and /reload,
  and if any fail you get one red line in chat naming it. New "click" tests press Flow's own
  buttons (the arrow's right-click, the Router dropdown, Tracker rows) and check a menu opens.

## 0.35.54
- Fixed: the arrow's right-click menu broke once a waypoint was set (Nearest repair / vendor,
  Point the arrow here): Forever gives the game's map pin position as a plain table, and Flow
  called a vector method on it ("Waypoint.lua:20: attempt to call a nil value").
- The arrow turns with your character again by default (everyone is switched back once). Map
  style (up = north) is still in the arrow menu, now labelled for what it does: it doesn't
  turn with you or the camera. No mode can follow the camera: the game doesn't tell add-ons
  where the camera points.

## 0.35.53
- The camera stays where you put it: the game's "Camera Following Style" swung it back behind
  you whenever you moved. Flow switches it to Never once (you asked); it's a suggested setting
  in Options > AddOns > Flow if you want it back.
- The arrow can turn three ways (right-click it, "Arrow turns"): north-up (the default, fixed
  to the screen: it only turns as the direction to the stop changes), with my character, or
  like my minimap (turns with you if your minimap rotates, north-up if it's locked).
- Flow Router: one "Route:" dropdown (current quests, optimal with or without professions,
  completionist, and the order) instead of two checkboxes and a sub-box that couldn't reach
  Completionist. The route list moved up into the space.
- Flow Seller: an "Auto-sell" switch on the drawer's header, and both auto-sell switches (all,
  and grey junk) in Options > AddOns > Flow.
- README brought up to date with everything since 0.35.

## 0.35.52
- Auto-sell: opening a vendor now also sells everything else Flow marks "sell" (gear you've
  outgrown, outgrown food and drink, unused materials...), not just grey junk. Up to 12 a visit,
  the size of the vendor's buyback tab, so anything sold by mistake can be bought back from
  Flow's vendor drawer; buying it back tells Flow never to sell that item again. More than 12:
  the rest go on the next visit. On by default; Options > AddOns > Flow: "Auto-sell everything
  Flow marks to sell".

## 0.35.51
- Fixed: a finished quest's turn-in right next to you waited behind every quest pickup in the
  hub. A hub's business now includes ready turn-ins with the pickups (like a walkthrough: hand
  in, pick up, head out), and each turn-in frees a quest log slot for the pickups.
- North-up arrow (the default): the arrow points the way on the screen like a map, up = north.
  Right-click the arrow ("North-up arrow"), Options > AddOns > Flow, or /flow nav northup to
  switch back to turning with your character. (Add-ons can't read the camera's direction.)
- "Point the arrow here (your waypoint)" on every stop's right-click menu (world map, Flow
  Router, Flow Tracker): the arrow goes there first; the planned route stays as it is. Any spot
  on the map: Alt-click it.
- Selling: food and drink you've outgrown is marked to sell once you carry 10+ of a better tier
  of the same kind for your level.
- Lite mode in dungeons, raids and boss fights: route planning pauses, the arrow and minimap
  update twice a second, the map and tracker refresh every 2 s, the minimap areas pause. The
  rotation, the Flow key and bags run as normal.
- Flow Tracker: a faint line down the left of the stops with a small down chevron at the end:
  the order runs top to bottom.

## 0.35.50
- Minimap areas are one smooth shape per group of spawns, like the world map's areas, instead
  of the outline of many circles. Only your current stop's area shows (and the one you hover
  in the Flow Tracker).
- The better / worse arrows above the spec icons are always full strength (they faded with
  the spec icons for specs you aren't levelling).
- Learning from your bags: anything you can learn right now (a recipe, a scroll or book that
  teaches you something, not already known) is offered on the Flow key: "Learn: X". When your
  bags are full it comes first: learning frees the slot.
- Nearest repair and nearest vendor: right-click the arrow ("Nearest repair", "Nearest vendor
  (sell)") or /flow way repair | vendor. Flow sets your waypoint on the closest one it knows:
  merchants you've visited (it now remembers which ones repair) and every vendor and repairer
  in Questie's data. When it's far, it reminds you where your hearthstone goes.

## 0.35.49
- Fixed a blocked action: the world map's own pins were blocked in combat ("taint from Flow:
  Button:SetPassThroughButtons()"). Flow was opening the game's quest log panel itself to make
  room for the Flow Router, which ran the map from Flow's code. It never touches the game's
  map or quest panels now: with the quest log open the Router covers it, otherwise it docks
  beside the map. The stop card's link is now "Select in quest log" (press L or M to read it),
  and "Show on map" highlights the stop on Flow's map layer.
- Map: a route on/off button sits right above Flow's drawer button.
- Map labels push each other apart: each one tries eight spots around its point and takes one
  that doesn't cover another label; with no room it drops the [level] and keeps the number.
- Bags full: the "sell at a merchant" stop is planned even with a detour (it was only planned
  when a merchant was on your way).
- Flow button: the next three spells are "on deck" to its right, shrinking, with their cooldown
  timers, moving up and down as things change. Auto attack moved to the left (the "active"
  side).

## 0.35.48
- The Flow button shows a small crossed-swords badge (top-left, gently pulsing) while auto
  attack is on.
- Heals: your health is hidden from add-ons on WoW: Forever, so Flow's heal timing never fired.
  It now uses the game's own low-health warning (the red screen flash, about a third of your
  health): when it's on, Flow suggests your fastest heal. In combat that's on the Flow icon and
  glowing on your bar (the key itself is locked for the fight). New suggested setting:
  "Low-health screen warning" (needed for this).
- Stunned, feared or rooted: Flow suggests the spell that breaks you free when you have one
  (Will to Survive or Every Man for Himself, Will of the Forsaken, Escape Artist, Blessing of
  Freedom for roots).
- `/flow api` reports whether the low-health warning and loss-of-control can be read here.

## 0.35.47
- The Flow button shows a cooldown timer: seconds left, big in the middle of the icon (tenths
  under 10 s, minutes when long). Not for the 1.5 s global cooldown. Items too (a lure...).
- In a quest's area the arrow is the ring again. Pointing at the nearest spawn spot (0.35.45)
  sent you back and forth: those are where things CAN spawn, not where they are. Standing on
  one still makes the pillars wave.

## 0.35.46
- The Flow button's "drag to move" label (hold Shift) now sits above the button, on a dark tab,
  instead of covering the action's text below it. Hovering the handle lights it up, shows the
  move cursor and a tooltip, so it's clear you can grab it.
- Right on the spot (on a spawn spot, or at the stop itself), the arrow's pillars run a sine
  wave around the ring.
- Minimap clouds: redrawn only when something changed (you moved, turned, zoomed, or the stop
  changed), without the memory churn (it was 1.3 MB a second).

## 0.35.45
- Weapons: Flow now checks the weapon skills you've actually trained, not only what your class
  may use. A sword before you've learned Swords isn't offered as an upgrade (no more "you do
  not have the required proficiency"); it's kept, its tooltip says so, and if it would be an
  upgrade the route gets a weapon master stop (Woo Ping in Stormwind, Buliwyf Stonehand in
  Ironforge...) to learn it. Guns stay "your class can't use this": paladins never can.
- In a quest's area the arrow now points at the nearest spot where the thing you need spawns
  ("Nearest Bundle of Wood: 23 yd"), from Questie's spawn data, and moves on to the next spot
  after you loot one. The ring shows only when you're right on a spot.

## 0.35.44
- Fixed: with the Fishing Pole on and no note of your weapons, "put your weapon back" picked by
  item level and chose the Rust-covered Blunderbuss (a gun paladins can't use). It now uses
  Flow's gear check: your best usable weapon for your levelling spec.
- New: upgrades on the Flow key. Out of combat with nothing to cast, the key offers "Equip X
  (upgrade +N)" for gear in your bags that's better for your levelling spec (or fills an empty
  slot). Target an enemy and it comes first: "Before the fight: equip X". Weapons wait while
  you're fishing.
- Minimap areas are one soft cloud like the game's own quest areas, instead of a pile of
  overlapping circles.

## 0.35.43
- Fixed: talking to a quest giver could hide quests they DO offer (7 at once in one talk), so
  "Accept:" stops vanished for quests you hadn't taken. Flow now only judges from a real list
  of quests on screen, never in the seconds after you accept or turn in, needs two visits a
  minute apart, and skips for a day instead of a week. The ones it wrongly hid are back.
- Fixed: a quest you just accepted stayed on the route as "Accept:" until a background scan
  finished. It now leaves at once (checked against your quest log), and the route refreshes
  when the scan ends.
- Clicking anything in Flow that opens a window (arrow drawer, stop card, menus, advice) hides
  the hover tooltip, and the arrow shows no tooltip while its drawer is open.
- Intro: FLOW is bigger and bold, on top of the spinning pillars (it was drawn under them).
- The Flow key no longer offers "Cast your line" just because the pole is on: away from a
  fishing stop or where you last fished, it offers to put your weapons back.

## 0.35.42
- Cooking: Flow plans cooking where you stand only if you can make a campfire (you need Simple
  Wood AND Flint and Tinder). Otherwise it plans it at a real fire: by the cooking trainer
  (Goldshire's inn), where the Flow key opens Cooking and makes them. No known fire: the stop
  waits, saying why.
- Bags: the old green "equip now" arrow in the top-left corner is gone. The per-spec marks say
  it (green up = better for that spec, your levelling spec brightest).
- The arrow's panel is a drawer: it slides down out of the arrow, joined to it, with a ^ tab at
  the bottom to fold it back up (or click the arrow). It no longer moves. The stop card from the
  Flow Tracker and Router is still its own window with an X.

## 0.35.41
- The arrow's pillars stay small when you arrive (only a little taller than while pointing),
  and bounce up quickly as the change happens.
- The Flow Router has a header like the Flow Tracker's (dark bar, orange accent, its own
  spyglass icon), with the "?" help on the right.
- The item your current stop wants you to use (a recipe to learn...) gets Flow's (o) marker
  in the route colour on its bag slot, top-left.
- The Flow Action border is no longer route purple (it read as "epic"): spell steps use the
  spell colour (light blue), item steps the item's own quality colour.

## 0.35.40
- Fixed: at "Learn Brilliant Smallfish: use the recipe in your bags" the Flow key offered to
  equip your Fishing Pole (the word "fish" made Flow think it was fishing). Only quest
  objectives like "catch 5 fish" are guessed from their text now.
- "Make 32 x Brilliant Smallfish" with the recipe already in your bags now says "use the recipe
  in your bags first", not "buy" it.
- Diagnostics: blocked actions carry the Flow version; `/flow api` reads UnitHealthPercent (it
  may let Flow see how hurt you are).

## 0.35.39
- Crafting where you stand ("Make 4 x Roasted Boar Meat" when you carry the meat and no fire is
  known nearby): the Flow key now does all of it: makes a campfire (Basic Campfire), opens
  Cooking, then makes exactly the right number. First Aid skips the fire. A recipe in your
  bags: the key uses it.
- No Simple Wood for the campfire: a "Buy Simple Wood" stop goes on the route.
- When you're at a stop like that, the arrow's ring shows its icon bouncing in place of the
  ball: the cooking (or other profession) icon for crafting, a bag for something to use from
  your bags.

## 0.35.38
- The 3D arrow's ring has height: its dots are now little pillars with lit caps (short while
  it points the way, tall and glowing in the route colour when you've arrived). The dot in the
  middle is now a shaded sphere floating over its shadow.
- New login intro: the pillars stand tall and spin fast around a deep gold FLOW, slowing to a
  stop, with "Flow (unfettered)", the version and status underneath; then the arrow appears
  over the still pillars.
- What the route optimises is now pluggable (for contributors): a `routeObjective` registry.
  Most XP and Shortest are the built-in ones; others (fishing only, a profession race) are a
  registration away. `/flow nav sort` lists them.

## 0.35.37
- Fixed a "blocked" error: dragging the Flow cast icon when a fight started tried to finish the
  move in combat, which the game forbids for that button. A drag still going when combat
  starts is now finished just before the fight.
- Fixed: Flow counted 0 of every item, because WoW: Forever moved GetItemCount into C_Item.
  Crafting counts, lures and "put your weapon back" all read your bags correctly now.

## 0.35.36
- The arrow's panel (click the arrow) can be dragged by its title band too, like the stop
  card; it then opens where you left it (right-click the title to put it back under the arrow).
- Gear marks are one style everywhere: the game's green bag arrow pointing up = better for
  that spec, the same arrow red and pointing down = worse, a short grey dash = about the same.
- After-fight heal: offered after any fight of 6 seconds or more, for 15 seconds (it was only
  after 15-second fights, for 10). Your health is hidden from add-ons on WoW: Forever, so Flow
  can't tell how hurt you are; `/flow api` now also checks whether the damage meter or the
  health bar could tell it.

## 0.35.35
- Fixed: after a fight away from the water, the Flow key kept offering "Cast your line" and
  the game said "didn't land in fishable water" over and over. Now that message tells Flow
  there's no water there: away from a fishing stop it offers to put your weapons back
  instead; at one, it says "Face the water, then cast".

## 0.35.34
- Target an enemy with your Fishing Pole still on, and the Flow key puts your weapon back on
  first (then your shield), before your pull, even at the fishing spot. If Flow didn't note
  what you had on, it picks the best weapon in your bags. It won't offer the pole again while
  the enemy is targeted.

## 0.35.33
- The login intro starts straight away with the spin and "Flow (unfettered)" (it used to show
  your quest first and then take the arrow over, which flashed), and lasts about a second
  longer. The status line fills in as quest data and your route load.

## 0.35.32
- The login title card is gone. Instead the arrow plays a short intro: it spins up, settles
  into its ring with FLOW in the middle, and underneath says "Flow (unfettered)", the version,
  and what Flow is working with (spells, Questie, stops planned). Then it points the way as
  usual. `/flow splash` replays it; Options > AddOns > Flow turns it off.
- "ways to improve" in chat now shows Flow's version.

## 0.35.31
- The stop you choose ("Go here first") stays marked: on the map it's red inside with a bold
  dark red ring and its area stays red (like when you hover it); in the Flow Router its row is
  tinted red with a red bar, and its marker turns red. The route itself stays in the "From
  selected" orange.
- The stop card (Flow's quest view) can be dragged by its title band. It then opens where you
  left it; right-click the title to put it back beside what you click.

## 0.35.30
- Flow key with an NPC selected (Lee Brown): Fishing and Find Minerals now cast on you, never
  on your target, so they don't fail. Reeling in and gathering use the game's Interact, which
  goes to your target when you have one, so with a friendly target selected the key first
  clears it (one press). Enemy targets are left alone (that's your pull).
- Flow Router: the title stands alone; a "?" on the right shows a small legend with the same
  ^ handle and (o) marker the rows use. The background is darker.
- Flow Router and the quest log: with the Router open, the game's quest-log button now just
  closes the Router and shows the quest log (it used to close and spring back open). Flow's
  button still opens the Router over the quest log, and closes both.

## 0.35.29
- `/flow perf` also shows how much memory each part churns through (KB/s), and how much Flow
  really keeps after a clean-up, to track down a memory reading of 96 MB.
- Fixed a self-test that still used the old fishing check.

## 0.35.28
- Smoother: Flow no longer re-plans the route every 8 seconds while you stand still (only after
  you move 30 yards, or when something changes), and the background refresh of the stop list
  runs every 30 seconds instead of 10. Each one took 20-40 ms, a small stutter you could feel.

## 0.35.27
- Crafting: Flow makes exactly what reaches your target. The profession window gets a small
  Flow panel: "make 11 x Heavy Linen Bandage", First Aid 47 -> 58, and a **Make 11** button that
  crafts exactly that many. Hover it for why that number and what's next. When the skill gets
  there, Flow says "that's enough, stop crafting" and names your next stop.
- Fixed: a crafting plan vanished once you were within 10 points of its target (halfway
  through), so nothing told you when to stop. It now holds until the target is reached.
- Route stops highlight the count in "Make 11 x ...".
- Fishing keeps up with the water you'll fish in (about 25 by level 10, 75 by 20, 150 by 30)
  instead of the crafting curve, which asked for 58 at level 8.

## 0.35.26
- Fixed: the Flow key stopped fishing after the first fishing quest. The next Fishing stop
  (the "skill behind your level" one) didn't say it was for Fishing, so the key didn't
  know. Now any fishing stop counts, including quest objectives like "catch 5 fish". Fishing
  also continues wherever you have the pole on and are casting, until you walk away (then the
  key puts your weapons back).
- New: a "Buy a Shiny Bauble (lure)" stop with the Fishing Pole, when you carry no lure
  (optional, planned when the vendor is on the way).
- Options > AddOns > Flow: turn off the login title card, and turn the key's fishing and
  gathering steps on or off.
- The title card now sits lower, below the game's zone name.

## 0.35.25
- `/flow perf`: how much CPU and memory Flow uses, per part (arrow, rotation, route planning,
  world map, tracker), and any single update slow enough to feel as a hitch. Saved with the
  diagnostics so slow spots get noticed.
- The Flow Tracker shows a spinner and "updating route..." while the route is being redone.

## 0.35.24
- Professions chain: when Fishing is on your route, the fish you'll catch count toward
  Cooking (Brilliant Smallfish levels it like wolf or boar meat), so there's less meat to
  farm. The recipe (about 40 copper) goes on the route as a stop. The farm stop says how many
  fewer kills fishing saved you.

## 0.35.23
- Progress reads as a path everywhere Flow writes it: "Loot Stringy Wolf Meat 9 -> 66",
  "Slimy Menace: 0 -> 7 Murloc slain".

## 0.35.22
- Fixed: the Flow key and the icon did nothing out of combat (Devotion Aura, blessings, seals).
  Once the button had nothing to cast it hid itself and never came back until a fight started.
- New: Flow Actions on the same key, out of combat, at your route stop. Fishing: equip your
  pole, put on your best lure, cast, then press again when the bobber splashes. Mining and
  herbs: turn on Find Minerals or Find Herbs, then gather. Leaving: your weapons go back on.
  `/flow action` says what it would do and why.
- New suggested setting: "Interact key reaches objects" (needed to reel in and gather with the key).

## 0.35.21
- Fixed a self-test that dropped the oldest diagnostics line when the log was full.

## 0.35.20
- Fixed: "Flow has been blocked from an action only available to the Blizzard UI" when using
  the game menu. Flow replaced the game's popup table (0.35.17), which taints every popup,
  including Log Out and Exit. Flow also no longer closes the Options window from its own code.
- Blocked actions are now logged (what was blocked, which add-on was blamed, what was open)
  and tools/read-diag.ps1 shows them in their own section. Developer installs turn on the
  game's taint log so the cause can be found. A self-test checks the game's global tables are
  untainted.
- Flow's settings now live in the game: Game Menu > Options > AddOns > Flow. The page has your
  cast key, Flow's options (colour-blind colours, 3D arrow, minimap areas, route on the map) and
  every **Suggested WoW setting** (auto loot, nameplates, target of target, instant quest text,
  camera zoom, timestamps, ...) with what Flow suggests, plus "Use Flow's suggestions".
  /flow settings and /flow setup open it.
- Flow's target marker (o) everywhere: a ring in the route colour (epic purple in Most XP
  order) around a dot, for the stop the arrow points at on the world map, on the minimap and in
  the Flow Router, matching the arrow's ring when you arrive.

## 0.35.19
- 3D arrow (the new default): a thick chevron lying on the ground ahead of you, tilted towards
  the horizon with perspective, a lit top, darker sides, a soft shadow and a slight float. Its
  ring lies flat on the ground too. It turns left and right like before; it can't point up or
  down (WoW: Forever gives no heights). Right-click the arrow and untick "3D arrow", or
  `/flow nav arrow flat`, for the flat line arrow.

## 0.35.18
- Fishing needs a Fishing Pole: without one, "Buy a Fishing Pole" comes first and the fishing
  stop shows "needs a Fishing Pole". Fishing stops also suggest a Shiny Bauble lure.
- Minimap areas: the stop the arrow points at shows its area on the minimap (discs and a
  border, like the world map). Hover a row in the Flow Tracker and that stop's area lights up
  in the hover colour too, so you can see whether you stand in this stop's area, the next one's,
  or both.

## 0.35.17
- Waypoints from pasted coordinates. `/way` now works too (unless TomTom has it), and so does
  a whole pasted line: `45.2 63.1`, `(45.2, 63.1)`, `/way 45.2 63.1 Hogger`,
  `/way Elwynn Forest 45.2 63.1 Hogger`, `/way #1429 45 63`.
- Arrow menu (right-click): "Set a waypoint (paste coordinates)..." opens a box to paste into,
  and "Clear your waypoint".

## 0.35.16
- Mount milestone. Five levels before riding level the advice list tells you to start saving
  (how much, and what you have). At riding level "Learn riding" goes on the route as a
  milestone, then the mount itself; each waits, with its price, until you can pay. Paladins
  and warlocks get their mount from a class quest, so they only save for riding.
- The riding level (40) and prices (about 20g riding, 80g mount) are the classic ones, shown
  as estimates until WoW: Forever confirms them; they are one line to change in
  Modules/Nav/Mounts.lua.

## 0.35.15
- Fixed: "Learn Heavy Linen Bandage" (and other recipe stops) stayed after you learned it at
  the trainer. Flow now notices the "You have learned..." line at once.
- New route: **Completionist** (arrow menu, or `/flow nav complete`): every quest you can still
  do in the zones you are questing in, grey ones included, in the shortest order. XP does not
  reorder it.
- Class training is a milestone: it always makes the route (never dropped as too far) and
  counts as half the distance of a quest stop, so you train as soon as it fits around the
  quests on the way, instead of whenever you happen to pass the trainer.
- Quests that come into range as you level are folded into the route by themselves (the
  route re-plans on level up).

## 0.35.14
- For contributors: CLAUDE.md (how to work on Flow with an AI assistant), CONTRIBUTING.md,
  and GitHub issue and pull request templates.
- Tools find your WoW: Forever folder and account by themselves (set FLOW_WOW_DIR /
  FLOW_WOW_ACCOUNT to override); combat reports go to reports/ by default.

## 0.35.13
- Flow Router: the active stop (where the arrow points now) shows a selected radio dot, a
  white ring around a dot in the route colour, instead of the ^ (replaces the 0.35.12 star).
  Hover says the arrow points here; if you chose it, a click clears your choice.
- Optional profession farming (meat for Cooking when no quest needs it) is never a stop of
  its own any more, so Flow no longer sends you off to kill wolves. It is listed under "Along
  the way" in the arrow panel: loot those mobs when your quests bring you to them.
- Fixed three icon paths with single backslashes (money-blocked stops, lock icon, quest
  reward coin).

## 0.35.12
- Flow Router: your selected stop shows a filled star instead of the ^. Hover it to see that
  the route starts there; click it to clear the selection and go back to your usual order.

## 0.35.11
- Clicking a stop (Flow Router row or point, Flow Tracker row, map area) opens Flow's own
  card for it beside what you clicked, and the Flow Router stays open. The card has links:
  "Open in quest log" (the old behaviour), "Show on map" and "Go here first". Click the stop
  again, the X, or Esc to close it.
- World map areas: only the patch the route actually goes to is drawn for each stop; point at
  a stop to see every place its mobs live.
- Fixed: the arrow panel's fallback icon path (single backslashes).

## 0.35.10
- Farm stops count like quest objectives: "Loot Stringy Wolf Meat or Chunk of Boar Meat 9/66
  (~150 kills)". The count is what you carry out of what the plan uses.
- World map: every area stop gets its own patch with a border around it (the next stop
  stronger, the one you point at in the hover colour). Hover a patch to see the stop number
  and what you need there; click opens it, right-click for the menu.

## 0.35.9
- World map: a stop that is a whole area (mobs to kill, things to loot, meat to farm) shows
  where its mobs live as soft discs in the route colour, for the next stop and the one you point
  at, instead of a single dot. Farm stops also get the ring on the arrow when you are there.
- Farming is realistic now: "Loot 66 Stringy Wolf Meat or Chunk of Boar Meat (~170 kills)".
  Each material has a rough drop rate, and Flow learns yours as you loot those mobs.
- Either meat will do: wolves and boars both count, and meat already in your bags is cooked
  first.
- Optional professions (not needed for a quest) are "loot as you quest": their farm stops only
  come up when the mobs are on your way, instead of pulling you off to grind.

## 0.35.8
- Setup: new "Target of target" row, suggested on. On clients that keep it in Edit Mode the
  row says where to find it (Target Frame > Target of Target).
- Setup: when an update adds a suggestion you have not seen and that is off, the setup table
  opens once more, 30 seconds after login, with a line in chat naming what is new.
- README: feature list brought up to date (route orders and colours, Flow Router, Flow Tracker,
  quest areas, corpse arrow, blocked stops, professions, Flow Seller, self-tests); banner uses
  the current route colours.

## 0.35.7
- Arrow: in a quest area (the ring is showing), hovering the arrow or its text opens the full
  panel and moving away closes it; click to keep it open. Elsewhere hover shows a tooltip and a
  click opens the panel, as before.

## 0.35.6
- Fixed: "Buy a Mining Pick" (and "needs a Mining Pick") stayed after you bought one: Flow only
  looked for the classic item ID. Tools now count by ID or name, in your bags or equipped.

## 0.35.5
- Flow Seller (the vendor drawer) stays on screen at every vendor. With nothing to sell it's
  collapsed to its header, "Flow Seller  0 items to sell"; click the header to open or close it.
  With items to sell it opens as before.

## 0.35.4
- Flow Seller never suggests selling a profession tool (Mining Pick, Blacksmith Hammer, Skinning
  Knife, fishing poles, Arclight Spanner) while you have or plan that profession; bags show the
  profession icon with "tool for Mining".

## 0.35.3
- Cast key check: each press of your Flow key is logged in the fight record (what it was bound
  to at that moment, whether a text box had the keyboard, and whether the button then got the
  click), to find why the key sometimes does nothing.

## 0.35.2
- Party: forming a group as leader no longer builds a party route from everyone's quests and
  switches you onto it (it flooded the tracker and map). You get a one-line hint instead; others
  still get the join prompt when someone shares one.
- Right-click menu, in a group: Your own route / Party route, Share a party route, Leave it.

## 0.35.1
- Forever blocks measuring nameplates on screen, so the arrow no longer tries to point at visible
  quest mobs (it logged an error each time); the ring stays.
- `/flow talents` reads the modern talent system (C_ClassTalents), which Forever uses.
- Checked: this client gives addons no height (always 0), so no up/down hints; caves are learned
  from your trails instead.

## 0.35.0
- Caves: Flow marks trail points you walk indoors and learns entrances (where you go from
  outdoors to indoors). A stop inside is no longer pointed at in a straight line (that led on top
  of the cave, e.g. Book Return): the arrow follows your trail in, or heads for the entrance
  ("it's inside: entrance first"). Needs one walk in to learn the cave.
- Map points work like rows in the Flow Router list: hover = details (highlighted in place),
  click = open it, right-click = menu. Only the ^ handle in the list previews or changes the route.
- Cast key: Attack uses the spell button too, so pressing the key on an enemy starts auto attack.
- Diagnostics: whether this client gives addons heights (for up/down hints).

## 0.34.1
- Gear: while you wear a two-hander, a one-hander or shield is valued as a pair with the best
  partner in your bags (a shield for a one-hander, a one-hander for a shield), shown as "as a
  pair with ...". Retribution, which uses no off-hand, keeps comparing the one-hander alone.
- `/flow talents` (and the diagnostics) list this client's talent trees, for writing the
  talent plan.

## 0.34.0
- Crafting materials no profession of yours uses (learned or planned) are offered for sale (plain)
  or the auction house (better quality). Materials for planned professions are kept, e.g. Linen
  Cloth for First Aid before you've learned it.
- Weapon speed now counts a little in the gear score (up to one point either way), per spec
  preference (Retribution: slow).
- Tests: quest availability (level, holiday events, quests a giver didn't offer), sell decisions,
  weapon speed (25 in all).

## 0.33.1
- Items kept for several reasons list them all (e.g. Linen Cloth: the Redemption class quest; for
  First Aid: Linen Bandage). Profession materials name every profession of yours that uses them,
  including from Flow's levelling guides.
- Flow Router (the map drawer, renamed): "Show route on map" switch (off = the list only).
- Route lines on the map are fully opaque and a touch thicker, so they show the exact route colour
  (epic purple for Most XP first).

## 0.33.0
- After-fight heal prompt: only after fights of 15 s or more, for 10 s, and never once you target
  an enemy (you're pulling: attacks first). It was offering Holy Light before attacks at nearly
  full health. Now tested rule by rule.
- Dead: the arrow turns red and points back to your corpse ("Release your spirit" before that),
  with the minimap dot on the corpse.
- Quest stops show a quest icon in the tracker and route list: "!" to accept, "?" to turn in, a
  grey "?" for objectives of quests you're on.
- Hovering the ring lists every quest stop you're in the area for ("Also here").
- Tests: 22.

## 0.32.2
- Moving the spell icon: hold Shift (out of combat) and a "drag to move" handle appears over it;
  drag that. Dragging the secure button itself didn't work (it takes the press as a click).

## 0.32.1
- Cast key: a fight that starts while the after-fight heal is offered no longer locks the key
  to Holy Light for the whole fight (seen in the fight records); it locks to Judgement.

## 0.32.0
- Arrow: anywhere in a quest's area counts as arrived (within 45 yd of any spawn of its mobs or
  objects, not just the point the route picked), so it shows the ring there instead of pointing
  you back to one dot. In the area, when one of the quest's mobs or NPCs has a nameplate on
  screen, the arrow points straight at it ("There: Kobold Vermin").
- Hover the arrow, ring or its text for the stop's details (quest progress...).
- Heals from the cast key always land on you, whatever you have targeted. Presses and the
  game's errors in the 15 s after a fight are recorded too.
- "Choose your professions" no longer shows once you've learned two main professions.
- Tests: quest area, professions advice (19 in all).

## 0.31.1
- Cast key: never locked to nothing for a fight. The fight records showed pulls with no
  suggestion, so the key did nothing all fight; now the class picks (Paladin: Judgement, or a
  seal if you have none).
- Order modes coloured in menus and the map list: Most XP purple, Shortest blue, From selected
  orange.
- Clickable things look clickable: hand cursor on route rows, map points and the ^ handle; tracker
  rows also show "open".
- Arrived: the arrow turns into a pulsing ring with a dot in the middle.
- Route chevrons are white on every leg.
- Fixed: the advice list's go-arrow icon path (single backslashes).

## 0.31.0
- Cast key and icon: Forever ignores macro-type secure buttons (fight records showed every press
  arriving with the right spell, and nothing cast). The button now uses the "spell" type; only
  Attack still uses /startattack. Fight records also log the game's own errors and casts.
- After a fight of 6 s or more, the icon offers Holy Light for up to 12 s (Flow can't see your
  health in Forever, so it's a prompt; it goes when you heal or fight again).
- No buff reminders while resting (inns, cities); everywhere else they keep coming.
- One spec badge everywhere items are marked (bags, quest reward choices, vendor drawer): an icon
  per spec with an arrow drawn right above it (up better, down worse, flat about the same). Quest
  rewards used to show plain coloured squares.
- Tests: spec badge, after-fight heal (15 in all).

## 0.30.1
- Route: a quest's turn-in now comes along with its objectives (it used to fall off the end of
  the 14 nearest stops, so the route stopped at the last objective).
- Quests that aren't on offer stay off the route: event quests only while Questie says the event
  is on (e.g. An Apple Treat after Hallow's End), and when you talk to a quest giver, quests Flow
  expected but they don't offer are skipped for a week.
- The text under the arrow clicks like the arrow (left: panel, right: menu).
- Vendor drawer: the button says what it sells ("Sell 16 items for 1s 20c"), and the junk line
  reads "No junk left (4 grey items sold this visit)".

## 0.30.0
- Bags: gear shows a small icon per spec along the bottom with an arrow above each: up = better
  than that spec's gear, down = worse, flat bar = about the same (your levelling spec brighter).
  The sell coin and keep icons moved to the top right.
- "From selected stop" survives /reload: the chosen stop is saved, the radio and route colour
  come back as they were.
- Cast diagnostics: each fight logs what was suggested at the pull, what the key was set to,
  whether the button received your clicks or key presses, and what Flow suggested during the
  fight ("[cast]" lines), to find why the key doesn't cast.

## 0.29.1
- Splash: 2 s.
- "Hide this stop" in the menus is now "Move on (hide this for now)".
- "From selected" is greyed as "Select a waypoint" until you pick a stop, then it reads "From
  selected" and is ticked.
- From selected stop is legendary orange (route, arrow). Hovering a stop now shows only the route
  you'd follow, all in that orange, instead of two routes in different colours.
- Route lines and points sit one layer (frame strata) above the map, so map objects can't cover them.
- "Ways to improve" no longer lists quests to accept (they're on the route, tracker and map
  list); it sticks to spells, training, gear, talents and professions.

## 0.29.0
- Fixed: the spell suggestion (icon and cast key) stopped. Forever hides your buffs from addons
  (often in combat) and reading them threw an error that stopped every suggestion. Now Flow
  remembers the seals, blessings and auras you cast and uses that when buffs are hidden, and one
  failing check only skips its own rule.
- Fixed: vendor drawer icons (wrong icon call).
- Map list rows: an up-arrow handle on the left routes from that stop (hover it to preview).
  Clicking the row opens it (quest details; the drawer folds away so they show). Hovering shows
  the details right there. Right-click for a menu.
- One readable tooltip for every stop (map pins, map list, tracker): title and level, the task
  in white, objectives with progress, a short quest text, details, XP, then a hint.
- Arrow panel: the task now has a band of its own in the route colour (icon, type, the task in
  large text, distance), then the rest.
- Self-tests: `/flow test` (12 tests: registry, skill objectives and planning, XP, route colour,
  planner order and dependencies, blocked labels, buff memory, gear rule, menu, tooltip). They
  also run on every /reload into the diagnostics.

## 0.28.1
- Flow Tracker: Shift-drag its header to move it, even when docked (dragging undocks it). Drop
  it just under Questie's tracker to dock it again.

## 0.28.0
- Route and arrow share one colour, and it shows the order mode: purple (epic) = Most XP first,
  blue (rare) = Shortest path, gold (artifact) = From selected stop. Previewed route yellow,
  yours grey meanwhile, hovered stop red. Colour-blind palette keeps the same roles.
- Map drawer: the "Flow route" bar at the top is gone (the square map button does it); hidden
  stops are always listed (greyed, click to bring back).
- Profession stops (skill plan, tools to buy) follow "Include professions": off means none.
- Buying stops carry a price (guide estimate until you've seen it at a vendor, then the real
  one) and are listed as blocked until you can pay.
- Flow Tracker docks under Questie's tracker and opens downward.
- Splash: 1 s.

## 0.27.0
- Route order has three modes (map list, arrow menu): Most XP first (default), Shortest path,
  From selected stop. Clicking a stop on the world map selects it; picking one of the other two
  clears it. When the selected stop is done, the route goes back to your usual mode.
- Flow Tracker: clicking a stop opens it (quest in the quest log, anything else on the world map,
  highlighted) instead of changing the route. Right-click for a menu. The route is changed on
  the world map only.
- Flow Tracker docks on top of Questie's tracker: one column, Flow opens upward from its
  header, Questie downward from its own, one open at a time or neither. `/flow tracker undock`.
- Right-click menu (arrow and tracker rows), in Flow's style: open or hide the stop; route
  (Follow current quests / Optimal with professions / Optimal without professions); order;
  Unhide all stops.
- Minimap: a dot in the route colour for your current stop (at the edge when it's further).
- Nameplates: the NPC your current stop is about (vendor, trainer, quest giver, turn-in) gets a
  circle mark.
- Map pins and route lines sit above the map's own art (lake, towns).

## 0.26.0
- Map: a square Flow button above the game's quest log button opens and closes the route list.
  The quest log and Flow's list share the slot: one or the other, or neither.
- Map: a line from you to your first stop, and small chevrons crawling along the route to show
  which way it runs (and when a leg goes out and back). The stop you hover (on the map or in the
  list) is drawn bigger, in the hover colour with a white ring, on top of everything.
- Map list: blocked and hidden stops always get rows (up to half the list), so a full route no
  longer pushes them out of sight. Rows show a tooltip with the stop's details.
- Most XP first (new default; "Most XP first" on the map list, `/flow nav xp on|off`): still the
  shortest path, but quest stops are weighed by XP and level. Quests 3+ levels above you wait;
  more XP is worth a longer walk; quests about to go grey come a little sooner. Quest tooltips
  show XP (real from your log where the game gives it, else an estimate) and a note.
- Splash: 0.618 s.
- Flow Tracker hangs from its top-left corner, so collapsing folds it up into the header.

## 0.25.0
- Blocked stops are shown, not hidden: a lock (or coin) and the reason, e.g. "needs 1s (you have
  40c)", "needs Mining", "needs a Blacksmith Hammer". In the map route list, the Flow Tracker
  (header counts them) and `/flow nav why`. They join the route by themselves once sorted.
- Profession skill planner. "Raise your Blacksmithing skill to 20" no longer sends you to the
  trainer: Flow works out what to make (most skill per material at your skill), what that
  needs minus what's in your bags, and how to get the rest (smelt ore you carry, mine the
  veins on this map, kill the mobs that drop it, buy it). Those become route stops mixed with
  your quests by distance, re-planned as your bags and skills change. Planned crafting
  professions behind your level get optional stops the same way.
- Data: Blacksmithing, Mining, First Aid, Cooking brackets and material sources (Guides.lua,
  from public levelling guides; approximate). Opening a profession window records your real
  recipes, colours and reagents, which win over the guide data.
- `/flow prof plan` explains the plan (also in diagnostics).

## 0.24.0
- Route colours back to green (your route) and yellow (a route you preview); your route turns blue
  while previewing and the stop under the mouse is red. "Colour-blind route colours" in
  /flow settings and /flow setup switches to orange / purple / sky blue.
- Splash is gone in about half a second.
- `/flow nav unhide` brings back every stop you hid; `/flow nav hidden` lists them.
- Stops that cost money you don't have (class training) are skipped and remembered. They
  come back on the route by themselves once you can pay, planned by distance like any other
  stop, so the trainer goes to the top when you're near it (e.g. after a hearth).
  `/flow nav why` lists what was skipped. If you can afford only some spells, the stop says so.

## 0.23.0
- Fixed: the vendor drawer didn't appear (it checked the vendor window before the game showed it).
- Auto-sell junk when you open a vendor, no confirmation (on by default; /flow setup).
- First-run setup now opens 30 seconds after login, well after the splash.
- Fixed: a shield could show as a DPS upgrade with a lower score ("better in every stat" compared
  it with a two-hander). That rule now only compares like with like, and Retribution never treats
  shields or off-hands as DPS upgrades.
- Armor counts more for DPS and Heal while levelling.
- Fixed: Kobold Candles and Gold Dust Exchange were marked [Elite]; an objective is elite only if
  every mob that drops the item is elite.
- `/flow gear why` (and the diagnostics) show each bag item's stats, scores and comparisons.

## 0.22.3
- Removed the Questie button from the Flow Tracker header; the two trackers still work as an
  accordion through their own headers. Splash fades out in 300 ms.

## 0.22.2
- Load splash: the two gold bars count down how long it stays (top empties left to right, bottom
  right to left); when they're empty the splash is gone.

## 0.22.1
- Map: thin, unbroken route lines through small round points; your route is orange (like the
  arrow), a previewed route purple. Each point shows its stop-type icon.
- New HUD-style arrow: a glowing line-drawn chevron with a ring that marks the direction.

## 0.22.0
- Stops are colour-coded by type, each with an icon too: accept (yellow !), turn in (yellow ?),
  daily (blue), kill (red skull), collect (orange diamond), use (tan), talk (green), profession
  trainer (purple), class trainer (teal), merchant (gold), hearthstone (white), skill-up (green),
  waypoint and party (sky blue). The stop the arrow points at has an orange number.
- Flow Tracker on screen, working as an accordion with Questie's tracker (blue Questie button).
- Map: the Flow route header sits just above the quest log; open it covers the quest log, rolled up
  the quest log is back.
- Merchant stop when there is enough to sell (or bags nearly full) and a merchant is on the way.
- Profession picker: offered in the advice list from level 3, `/flow professions`, setup row.
- "Accept" instead of "Pick up".
- Fixed: hovering checkpoints no longer re-plans every time (previews are cached).
- Fixed: professions are read through the newer API, so learned ones clear their trainer stops.

## 0.21.0
- Route planner: Flow checks quest availability itself (earlier quests in the chain done, race,
  class, level). It no longer sends you to pick up quests you can't take yet.
- Picks up the quests in the hub you're in before heading out (within ~250 yd), and never plans
  more pickups than your quest log has room for.
- Elite objectives are marked [Elite] and planned later.
- Hearthstone stop recognises the inn name as well as the town.
- `/flow nav why` (and the saved diagnostics) list the full planned route.

## 0.20.0
- Hearthstone: no more pop-up. While levelling, the route gets a "Set hearthstone" stop at the
  local inn when yours is set elsewhere (`/flow hearth off` to stop).
- Hide any stop: right-click it on the map or in the route list. "Show hidden stops" lists them
  greyed out; click one to bring it back.
- Setup table: tick boxes show each setting's current state; Apply turns things on or off to
  match. Quick picks: All, None, Flow suggests, WoW default, Reset. The Set button has its own column.

## 0.19.1
- Spec icons (Retribution, Holy, Protection) replace DPS / Heal / Tank words, dots and letters in
  tooltips, bag icons and quest reward badges.
- Fixed: an item at least as good in every stat (e.g. a belt with only more armor) is now an upgrade
  for every role; armor also weighs more for DPS and Heal.

## 0.19.0
- Vendor drawer: "Sell all junk" (every grey item, on by default) plus up to 12 proposed items with
  their own Sell buttons; Sell All sells junk first so the proposed ones stay in the buyback tab;
  "Sold this visit" with Buy back; buttons grey out and the drawer folds away when done.
- Hearthstone reminder when you rest at an inn that isn't your home (once per inn; stronger when
  most of your route is in that zone). `/flow hearth on|off`.
- Nicer "Flow route" bar on the map panel.

## 0.18.0
- First-run setup table (`/flow setup`): auto loot, nameplates, instant quest text, auto-placing new
  spells, max zoom, chat timestamps, combat log file, cast key, Questie. Tick and Apply.
- Key binding mode (`/flow bind`): hover a button and press a key; changes are listed and only
  saved on Save. Ctrl+Z undo, Esc cancel (asks first with more than 3 changes; Esc again returns).
- Auto-placed spells: Flow says when the game puts a new spell on your bars and marks those bars
  (hover the book icon); `/flow autoplace` lists them.

## 0.17.6
- Diagnostics Claude can read from disk: Flow logs its errors and takes a snapshot of its checks on
  every `/reload` and logout (saved with Flow's data). `/flow dump` captures one on demand;
  `toolsead-diag.ps1` prints it.

## 0.17.5
- Profession and class trainers are found by NPC ID (with a name check) as well as by name, and
  Questie zones fall back to matching the game's own map names, so trainer stops show up.
- "Include professions" on the map panel (and `/flow nav professions on|off`).
- `/flow nav why`: what the route is made of and which places Flow couldn't find.

## 0.17.4
- Seal of Righteousness is suggested again a few seconds before it runs out (Forever's Judgement no
  longer uses it up), and Blessing of Might when it has under 30s left out of combat.
- `/flow rot guide`: your rotation in plain words, using the spells you have.

## 0.17.3
- Map route panel: "Click a stop to follow that route" hint, and a choice between **Follow current
  quests** (only quests in your log) and **Follow optimal path** (also pickups, trainers, skill-ups).
  Also `/flow nav quests|optimal`.

## 0.17.2
- The advice button is now a round minimap-style spyglass with an orange count bubble, and it pulses
  briefly when something important appears.

## 0.17.1
- The map route list no longer covers the map: it takes over the quest log area (or sits just
  right of the map) as a routed quest list, with an orange "Hide / Show Flow route" bar to roll
  it up and get the game's own map and quest log back.

## 0.17.0
- Joining a group asks automatically: follow the party route or keep yours. Party and personal
  routes are separate; switch any time with the toggle under the arrow.
- Forming a group as leader makes a party route by itself: quests members share come first
  (members exchange quest lists), otherwise your current route.

## 0.16.0
- Name: Flow (unfettered).
- Shared party routes: `/flow party share`; party members join with one click and anyone can
  edit (choose stops, add waypoints, reach stops). The latest edit wins for everyone; nobody owns it.

## 0.15.1
- Max camera zoom on by default; untick it in `/flow settings` (or `/flow zoom off`) for the game default.

## 0.15.0
- Fixed: the cast key did nothing on some clients. `/flow key test` shows what your key does.
- Route adds a class-trainer stop by itself when you level into new spells.
- Trip plan is colour-coded (orange = next stop, blue = quest pickups, sky blue = your waypoint)
  and listed beside the world map; hover a row to preview, click to choose.
- README banner.

## 0.14.0
- Choose your route: click a place in the advice list or a checkpoint on the world map. Picking a
  quest pickup (`!N`) routes you through all the pickups first.
- World map route with numbered checkpoints and quest levels; hover to preview another route.
  Colour-blind safe colours.
- Your own waypoint: Ctrl- or Alt-click the map, or `/flow way`.

## 0.13.0
- Keep icons in bags: a quest "!" for items your quests need, and profession icons for crafting
  materials. Tooltips explain every decision.

## 0.12.0
- Bag icons (equip, sell, AH, DE). The vendor panel sells 12 at a time with one-click buy back
  and learns what not to sell.

## 0.11.0
- Cast button and key, with conflict-aware key binding in a new settings window.

## 0.10.0
- Whole-trip route planner, stance-bar auras, chat timestamps.

## 0.9.0 and earlier
- Rotation helper, smart self-heals, fight profiler, combat log reports, advisor, gear scores
  per role and gear sets, quest markers, missed quests, navigation arrow with learned trails,
  load splash, help.

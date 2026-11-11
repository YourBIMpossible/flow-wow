<p align="center"><img src="docs/flow-banner.svg" alt="Flow: World of Warcraft levelling companion" width="720"></p>

# Flow (unfettered) WoW Mod

A levelling companion addon for **World of Warcraft: Forever**. It suggests what to press, plans
your route, judges your gear, sorts your bags, plans your professions and learns from how you
play. It started with the paladin and is built so other classes can be added without changing
existing code.

Flow for WoW is a separate project from Flow Engine.

## Features

### Combat
- **Rotation helper**: an icon shows the spell to press next, and the matching action bar or
  stance bar button glows. The border colour says why: green attack, light blue buff, gold heal,
  fast gold pulse heal now. A big cooldown timer sits on the icon (and, when it suggests
  re-casting a buff, the buff's last 30 seconds in light blue); the next three spells are
  **on deck** to its right (shrinking, with their timers, reordering as the fight changes), and
  a crossed-swords badge on its left shows auto attack is on.
- **Cast button and key**: click the icon or press your Flow key to cast the suggestion. Set the
  key in `/flow settings`; it warns you about conflicts and never changes your own key bindings.
  In combat WoW freezes what a key casts, so at the pull Flow locks it to a real attack (a seal
  if none is up, then Judgement or Crusader Strike), never a heal. Shift + key heals you, Alt +
  key uses your healthstone (or best healing potion), in fights too. Ctrl-drag to move the
  button; Ctrl + mouse wheel over it resizes it.
- **Buff button** (off by default: `/flow buffbutton on`): buffs and weapon stones, oils and buff
  items move to their own blue button left of the icon, so the Flow key is only your fight
  (seals, shouts, shields and Hunter's Mark stay with it). Give it a key with `/flow buffkey Q`.
- **Craft the right amount**: on the profession window, Flow says how many to make to reach your
  target, with a Make N button for exactly that many, and tells you when to stop.
- **Flow Actions** (same key, out of combat, at your route stop): at a fishing spot it equips
  your Fishing Pole, puts on your best lure, casts, then reels in when the bobber splashes; at a
  mining or herb stop it turns on Find Minerals / Find Herbs and gathers; when you leave it puts
  your weapons back. Upgrades in your bags: it equips them (first, when you target an enemy).
  Crafting: campfire, open the profession, make exactly enough; by an anvil, forge or cooking
  fire with something to make, it opens Blacksmithing, Smelting or Cooking. Things to learn in your bags
  (recipes, scrolls): it learns them. About to fight (a kill stop, or just
  after a fight): elixirs and scrolls, a stone or oil on your weapon, then food that makes you Well
  Fed. By a WoW: Forever campfire: place the camp objects you carry (a tent, a lute...), then sit
  for the camp buffs (the key sits you down; stay a minute); party members running Flow say which
  objects they could add. One press per step.
  `/flow action` shows what it would do.
- **Healing items**: low in a fight, Flow's icon shows your healthstone, then your best healing
  potion, when it's on one of your action bars (press it there: it glows). After a fight the key
  recovers you: bandage (the smallest that fills you), then food, then a heal spell by default,
  and drinks when you're at half mana or less (also while you eat). With fights ahead and no
  Well Fed, Well Fed food comes first. Right-click the Flow key to change that order, turn steps
  off, or use your lowest bandages first.
- **Status icons** above the Flow key, between fights only, instead of chat lines: by a campfire,
  what your group can add to the camp. Hover for details.
- **Auto-repair** at vendors who repair (Options, on by default), after Flow sells your junk.
- **Worn gear**: under 20% durability an anvil shows above the Flow key (hover: the item and the
  nearest repair vendor Flow knows) and the route gets a Repair stop. When a service is far away,
  Flow says if your hearthstone then a run looks clearly quicker (an estimate; it never uses it
  for you).
- **Buffs while questing**: keeps your seal, blessing and aura up; quiet in cities and inns.
  Remembers what you cast when the game hides your auras.
- **Heals when your health is hidden** (WoW: Forever hides it from add-ons): the game's own
  red low-health warning triggers your fastest heal; after any fight of 6 s or more a heal is
  offered for 15 s. Where health is readable, heals are timed so none of it is wasted, with an
  emergency heal when you'd die before you could react.
- **Break free**: stunned, feared or rooted, Flow suggests the spell that gets you out (Will to
  Survive / Every Man for Himself, Will of the Forsaken, Escape Artist, Blessing of Freedom).
- **Stop a cast**: your target starts casting within 8 yards, Flow suggests War Stomp (tauren).
  Classes add their own interrupts to `ns.rotation.INTERRUPTS`.
- **Druid: Entangling Roots** opens on a melee mob (the key casts it before the pull), and shows
  again when the mob comes for you mid-fight.
- **Fight types**: boss, several enemies, elite or normal mob, each with its own priorities.
- **Fight profiler**: records every fight and compares your best with your worst per fight
  type. It leans the rotation towards what worked (`/flow fights`).
- **Combat log reports**: `/flow log auto` writes the game's combat log file.
  `tools/analyze-combatlog.ps1` turns it into DPS, healing and tanking reports with
  recommendations, and feeds what it learned back into Flow.

### Questing and navigation
- **Route planner and arrow**: plans the whole trip (quest objectives, turn-ins after their
  objectives, quests to pick up, trainers you can afford, and profession stops) and points you
  along it. It learns trails as you walk, follows them around hills and rivers, and learns cave
  entrances so it sends you in through the door, not over the top. A quest stop says when it's
  an escort (its giver may be away walking another player out, for a few minutes) or when the
  giver is deep in a cave (The Longwalkers). Distances come with a travel time (by air when a
  flight is quicker; Flow learns flight masters as you fly). Optional, off by default: a faint
  profession arrow (profession stops on a route of their own, behind the main arrow), and
  "Finish the area you're in first". Profession plans use what's in your bags and bank and smelt
  ore into bars. A stop that needs something first goes after the
  stop that provides it ("after Bear Form"), or waits with the reason: training Demoralizing
  Roar and Maul comes after the class quest that teaches Bear Form.
- **The route's colour tells you its state** (arrow, route and waypoints): **Most XP first**
  (epic purple, the default) and **Shortest path** (rare blue) are optimised; **Custom route**
  (legendary orange) means you picked the next stop yourself with its ^ in the Flow Router (or
  "Go here next"). It goes there first and stays orange until you choose Most XP or Shortest
  again. The top row's (o) is where you're heading (a white ring on the map). Tooltips show
  each stop's XP.
- **Dungeon runs** (with Questie): the arrow menu's Dungeons section lists the dungeon runs at
  your level (one wing, the quests you can do this trip; later parts wait for the next run) and
  how each compares to your questing XP per hour. Prepare a run and the pickups and short
  lead-in quests go on the route (plus any breadcrumb whose giver is next to one of those
  stops), then the entrance; inside, the route shows only that dungeon's quests. Wings are
  told apart by their bosses. In a group, "Share quests" shares the run quests party members
  lack.
- **Your own waypoint** (Ctrl or Alt-click the map, `/way 45.2 63.1`, or "Point the arrow
  here") isn't a stop on the route: the arrow turns green and points there along a green line
  on the map, then goes back to the route when you arrive or clear it.
- **Near first**: the route finishes the stops around you before it sends you far; far stops
  and item drops whose mobs are spread out wait (`/flow nearfirst on|off`).
- **Hub business first**: in a quest hub the route turns in every finished quest there and
  picks up the quests on offer before heading out, like a walkthrough.
- **Quest areas**: in an objective area the arrow shows a glowing ring, a beam of light and
  ripples (they speed up when you're right on the spot); hover it to see every quest there. A
  "do it here" stop (crafting, a recipe to learn) shows its own icon bouncing in the ring.
- **Arrow**: a glossy metal chevron that glides as it turns and floats over its own shadow. Its
  colour says how close you are: grey while the stop is in another zone, then orange (far) through
  yellow to green (close), and blue once you're in its area (`/flow nav arrowcolor route` gives
  it the route's colour instead). Right-click it to pick Modern, 3D (pillars) or Flat lines
  (`/flow nav arrow modern|3d|flat`). It turns with your character. (The game doesn't tell
  add-ons where the camera points, so it can't follow the camera.) The login intro spins the
  arrow around a gold FLOW with the version underneath (`/flow splash`).
- **Corpse arrow**: when you die the arrow turns red and points to your corpse.
- **Milestones**: class training and your mount always make the route and fit around the
  quests on the way. Flow tells you to start saving for your mount 5 levels early.
- **Completionist route**: every quest in the zones you are questing in, any level.
- **Along the way**: optional farming (meat for Cooking) is never a detour; loot it as you go.
- **Blocked stops**: stops you can't do yet stay listed, greyed, with the reason ("needs
  1g 20s", "needs a Mining Pick"), and come back by themselves when you can.
- **Flow Router** (the square button above the world map's quest log button): the route list
  with a "Route:" dropdown (current quests, optimal,
  completionist; professions on or off) and the order. Hover a stop for details, click it for its stop card, use the
  `^` handle to route from that stop (it stays marked red), right-click to hide it or "Point
  the arrow here". A button above it shows or hides the route on the map.
- **World map and minimap**: the route as a faint dotted trail, like a treasure map (the stretch
  to your next stop, and that stop's dot, in the arrow's colour); numbered waypoints with quest levels (`3 [9]`) and pickups
  (`!2`); labels push each other apart so they don't overlap. Quest areas are drawn as clouds
  with borders; the minimap shows your current stop's area the same way, and the (o) marker.
- **Stop card**: Flow's view of a stop (drag it by its title). The arrow's own panel is a drawer
  beside the arrow: click the arrow to open it, click again or its X to close it.
- **Flow Tracker**: the route under Questie's tracker, opening downward (a faint rail shows the
  order). Click a row for its stop card; hover it to see its area on the minimap; Ctrl-drag
  the header to move it.
- **Stops on the map**: the route plans up to 30 stops ahead. Choose how many the world map and
  the Flow Tracker show: just the next stop, the next 3, 5 or 10, or all of them (/flow settings,
  the arrow's right-click menu, or `/flow nav stops 1|3|5|10|all`). The Flow Router always lists
  the whole route.
- **Lite mode**: in dungeons, raids and boss fights Flow eases off route planning and map
  updates so it never adds lag; the rotation and the Flow key run as normal.
- **Arrow menu**: right-click the arrow for route (quests only, optimal with or without
  professions), order, unhide all, and party options.
- **Party routes**: share your quests as a party route if you want one; your own route stays
  separate. Anyone following it can edit it; nobody owns it.
- **Your own waypoint**: `/flow way repair` or `vendor` (or right-click the arrow) for the nearest one; Ctrl- or Alt-click the world map, paste coordinates (`/way Elwynn Forest
  45.2 63.1`, or right-click the arrow: Set a waypoint), or `/flow way x y`; it clears when you
  arrive.
- **Only quests you can get**: holiday quests drop out when the event ends, and quests an NPC
  doesn't offer are skipped.
- **Quest markers on nameplates**: skull with your kill count, diamond with the count of an item
  a mob drops, star for NPCs to talk to; several per mob.
- **Missed quests**: quests you skipped in zones you've quested in (`/flow missed`).

### Professions
- **Skill plans**: for each profession, the cheapest path to the next skill cap: buy, learn,
  smelt, craft, gather or farm, with prices from vendors you've visited. These go into the route
  (`/flow prof plan`).
- **Guides** for Blacksmithing, Mining, First Aid, Cooking, Fishing and Herbalism, plus the
  recipes Flow has seen in your profession windows.
- **Tools**: reminds you to buy the Mining Pick, Blacksmith Hammer or Fishing Pole (and a lure),
  and knows when you have one.
- **Chained professions**: fish you'll catch levelling Fishing count toward Cooking, so there's
  less meat to farm. Cooking goes to a real fire unless you can make a campfire.
- **Exactly enough**: the profession window gets a Flow panel with a Make N button for exactly
  what reaches your target, and a "that's enough" notice when you get there.

### Gear and items
- **Gear scores per role** in every tooltip, shown with your spec icons (Retribution, Holy,
  Protection) and a mark above each (green arrow up better, red arrow down worse, grey dash
  about the same), compared with what the item would
  replace (two one-handers are judged as a pair against a two-hander), or with your gear set
  for that role (Equipment Manager or `/flow gear save`). Weapon speed counts for each spec.
- **Quest reward badges**: the same spec icons and arrows on quest rewards, or a gold coin on
  the best one to sell.
- **Bag icons**: spec marks per role, the (o) marker on an item your current stop wants you to
  use, gold coin to sell, AH, DE, a quest "!" for items your quests need, and profession icons
  for materials and tools. The tooltip lists every reason to keep an item (e.g. "Linen for
  First Aid").
- **Weapon skills**: Flow knows which weapon skills you've trained; an upgrade that needs one
  puts a weapon master stop on the route. Weapons your class can never use are marked to sell.
- **Flow Seller**: at a vendor Flow auto-sells grey junk and everything else it marks "sell"
  (outgrown gear, food and drink you've outgrown...), 12 a visit, the size of the buyback tab.
  It never sells profession tools or materials you need. Buy any item back with one click, and
  Flow then never sells it again. Auto-sell has its own switch on the drawer and in Options.
  With full bags a "sell at a merchant" stop goes on the route.
- **Skill books**: tells you to hold "+N skill" items until the last points before a cap.

### Progress advice
- **Advice list** (the round spyglass button with a count): spells to train (with cost), items
  to equip, professions behind your level, talents and habits from your best fights. Rows that
  are places route you there.
- **Training and talents**: trainer reminders, profession targets for your level, and spec
  advice (`/flow spec`, `/flow talents`).

### Quality of life
- **Each character keeps its own**: fights, trainer, recipes, profession plan, role, hidden
  stops and the like are saved per character, so "Ways to improve" and the route are about the
  character you're on. Settings, learned trails and NPC places are shared by all of them.
- **Options > AddOns > Flow**: your cast key, Flow's own options, and Flow's suggested WoW
  settings (auto loot, nameplates, target of target, camera zoom, the camera staying where you
  put it, the low-health warning, the Interact key reaching objects, timestamps...) with a "Use
  Flow's suggestions" button. When an update adds a suggestion, the page shows once more.
- **Quests accepted and turned in for you**: talk to a quest giver and Flow turns in your
  finished quests (you pick when there's a choice of rewards), then accepts their new ones (not
  grey or repeatable ones). Hold Shift to do it yourself; `/flow turnin` and `/flow accept` turn
  them off.
- **Nearest repair, vendor, flight master, innkeeper, banker, auctioneer or mailbox**: right-click
  the arrow, or `/flow way repair` / `vendor` / `flight` / `inn` / `bank` / `auction` / `mail`.
- **Learns where things are as you play** (every NPC you talk to and what they do, for all your
  characters; `/flow places`), and you can **share** that with every Flow player: opt in, NPCs
  only, nothing about you ([docs/SHARE-PLACES.md](docs/SHARE-PLACES.md)).
- **Performance**: `/flow perf` shows Flow's CPU and memory per part; it's saved with the
  diagnostics so slow spots get noticed.
- **Key binding mode** with save/undo/cancel (`/flow bind`). Spells you learn go into one
  **Flow Spells** list: drag each to a bar, or Bar / Key / Skip per row, or **Place all on
  bar**. `/flow keys` lists the keys that cast a spell directly, not from a bar (the game's Key
  Bindings window doesn't show those).
- **Colour-blind palette** for the route (in `/flow settings`).
- A short intro on the arrow at login (version and status), `/flow help`, `/flow settings`, chat timestamps, and Ctrl-drag to move
  any Flow element.
- **Self-tests**: `/flow test` runs Flow's built-in checks; they also run on every `/reload`.
- **Ask Claude from the game** (optional): `/claude make the arrow green`. A Claude session on
  your PC (Claude desktop or Claude Code, told to "watch Flow's in-game chat") picks it up through
  a small script, can answer and change Flow itself, and the answer shows in chat after
  `/claude`. The same script keeps a GitHub clone of Flow up to date by itself. Setup:
  [docs/ASK-CLAUDE.md](docs/ASK-CLAUDE.md).

## Requirements and companions
- World of Warcraft: Forever (interface 16001).
- Recommended: **Questie** + **QuestieDB**. Flow reads their quest and NPC data at runtime for
  the arrow, map route, missed quests and quest-item keeping. Nothing is copied from them.
- Optional: **Auctionator**, for auction house prices in sell decisions.

## Commands
`/flow help` lists everything. The main ones: `/flow settings`, `/flow rot why`,
`/flow action`, `/flow advice`, `/flow way` (`repair`, `vendor`, `clear`), `/flow map`,
`/flow nav xp|distance|northup|unhide|sort|stops`, `/flow prof plan`, `/flow gear sets`, `/flow sell`,
`/flow bind`, `/flow fights`, `/flow talents`, `/flow splash`, `/flow perf`, `/flow log auto`,
`/flow test`, `/flow api`, `/flow copy` (what Flow said lately, ready to copy), `/flow nearfirst`.

## For developers
Start with [CONTRIBUTING.md](CONTRIBUTING.md). Using Claude or another AI assistant? Point it
at this folder: [CLAUDE.md](CLAUDE.md) tells it how Flow is built and how to test in game. To
talk to Claude from inside the game and get updates by themselves:
[docs/ASK-CLAUDE.md](docs/ASK-CLAUDE.md).

- `Flow.toc` sets the load order. `Core.lua` holds the event bus and the registries
  (`ns:Register` / `ns:Get` / `ns:Each`).
- `Modules/` holds the features. `Classes/<Class>/` holds class data, trainer spells and the
  rotation.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) lists every extension point and how to add a
  class; [docs/GEAR_PLAN.md](docs/GEAR_PLAN.md) covers gear scoring.
- **Tests:** `Modules/Tests.lua` registers self-tests (`ns:Register("test", name, fn)`). There's
  no Lua interpreter here, so they run in game: `/flow test`, and in the diagnostics on every
  `/reload` (`tools/read-diag.ps1` prints them).
- **Lint:** `tools/lint.ps1` checks the Lua before you `/reload` (luacheck with
  `.luacheckrc`, plus texture paths): missing `local`s, typos, values never used.
- **Debugging:** `/console scriptErrors 1`, `/flow rot why` and `/flow api`.
- **Dev install:** the game's `Interface\AddOns\Flow` is a junction to this repo, so `/reload`
  picks up changes.
- **Packaging:** `tools/package.ps1` builds a release zip; see [docs/PUBLISHING.md](docs/PUBLISHING.md).

## Licence
Copyright (C) 2026 Sooth. Flow is free software: you can redistribute it and/or modify it
under the terms of the [GNU General Public License, version 3](LICENSE). It comes with no
warranty.

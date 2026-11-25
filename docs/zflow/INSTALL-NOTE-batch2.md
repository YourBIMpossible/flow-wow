# Z-Flow batch 2: install note

Draft by Twin, DISPATCH §579 item 1. Sources: the READY posts and reviews in §570–§578, at the SHAs below.

- **Candidate build (zflow SHA):** `2722c664`
- **Rollback build (the installed ZFlow kept as a copy):** `aa3dd5a8`, kept as `Interface\ZFlow.prev-aa3dd5a8`
- **Your saved settings:** not touched by the install.
- **Seen in game:** none of the rows below yet. Each one says "not seen in game" until your test.

## Two buttons you will use below

- **The minimap button**: the small round Z-Flow button on the edge of the minimap.
  - Left-click it: the settings page opens. It does nothing else.
  - Right-click it: the route menu opens.
- **The Flow button**: the big rotation button on your screen. A click on it casts its spell. It does not open settings.
- **To turn something off:** left-click the minimap button, find the setting by its words (the page has a search), then untick it.

## What changes, item by item

| # | What you see | Where you find it, no typing | How to turn it off | In game |
|---|---|---|---|---|
| R1 | Both buttons are always on screen. With nothing to cast, the self buff button stays as a dark face with the word "Buffs" under it. Point at it and its tooltip says why it is empty. By default it sits under the Flow button. (Twin 08790906) | On screen after login. | Combat and Class: "Show the self buff button". To move it out from under the Flow button: "Keep the self button under the Flow button". | not seen in game |
| R2 | If you know Mining or Herbalism and no tracking is on, the self button offers Find Minerals (or Find Herbs). Your click or key casts it. Nothing casts by itself. It is not offered in a fight, while mounted, on a flight or while eating. (Twin 81a41d67) | Look at the self button out of a fight. | Professions and Crafting: "Offer gathering tracking". | not seen in game |
| R3 | Gear advice follows the role you chose. A buff such as Righteous Fury never changes it. The bag arrow and the item tooltip give the same verdict, so equipping a suggested item never makes the old one the next suggestion. With no role chosen, it follows Flow's rule (damage). (MyBuddy fd40b430) | Combat and Class, Next spell: "Your role". | Gear and Loot: "Advise upgrades in your bags", "Badge gear in your bags", "Gear verdict on item tooltips". | not seen in game |
| R4 | Bag marks and gear badge letters now show in Bagnon or BagBrother bags as well as in the normal bags. Another character's bags, viewed in Bagnon, get no marks. (Lazy bdcb3ed5) | Open your bags. There is nothing to switch on. | Gear and Loot: "Marks on your bag slots". | not seen in game |
| R5 | A profession step names where to go: a trainer, a vendor, or a zone with nodes you have gathered before. The arrow points there. With Questie installed, the arrow can take a few seconds to appear; if the step first shows in a fight, it appears after the fight. With no known place, the step says so plainly. Nothing is made up. (Plexy 37f08964) | Comes with the profession step, when one shows. | Travel and Questing, The arrow: "Profession trainer arrow". | not seen in game |
| R6 | With quests in your log, the quest route plans itself and is drawn on the world map. It updates when you take a quest, finish a step, or a quest leaves the log. It is still there after a restart. (Zen a6d49a67) | Press M (the world map) with quests in your log. | Travel and Questing, The way there: "Show the route beside the quest log and on the map". Or right-click the minimap button, then Off in the route menu. | not seen in game |
| R7 | The arrow, its purple echo and the map route agree on colour. A map pin or waypoint arrow is green at any distance. If you turned "Arrow colour by distance" off, the arrow and every leg of the map route wear your one colour, pins and waypoints too. (Zen eba50815; map lines Muse 2722c664) | Set a map pin, or follow a quest. | Travel and Questing, The arrow: "Arrow colours", "Arrow colour by distance". | not seen in game |
| R8 | "Your buffs" and "Advice" each say in one line what they are, every time they show. "Your buffs" has a close button. Closing it turns the strip off, and a chat line tells you how to bring it back. (Zen f02a5f16) | Both panels show by themselves. | The close button, or Combat and Class: "Show your class buffs and their time left". | not seen in game |
| R9 | The inventory list and the dungeon "Get ready" stops open from menus, with no typing. (Lazy 9e07b6c3) | Inventory: right-click the quest arrow (or the world map button), then Show, Flow windows, Inventory. Dungeons: right-click the arrow, Dungeon quests, pick a dungeon, Plan the run. | Close the window. | not seen in game |

## Known limits, in plain words

- R1: the empty self button is darkened, not greyed as in Flow. A click on it while empty does nothing.
- R2: if you know both, Mining comes first. Spell names are the English ones.
- R4: the Bagnon button names are a reading of Bagnon's source, not seen in game. If a Bagnon release names them differently, no marks show (and no error).
- R5: no trainer or node table ships. Node zones come only from nodes this account gathered before.
- R6: the arrow does not walk the planned route; it keeps its own pick. The cost of planning is not measured in game.
- R9: the inventory and dungeon rows need the quest arrow or the world map button on screen.
- Typed-only words (facts, sound, choices, rollhint, sets, auctionlog and similar checks) are not claimed here.

## Rollback

If something is wrong: close the game, put back the kept copy of the ZFlow folder (`Interface\ZFlow.prev-aa3dd5a8`, into `Interface\AddOns\ZFlow`), and start the game. Your saved settings are untouched by either step.

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
  re-casting a buff, the buff's last 30 seconds in light blue), and a crossed-swords badge on
  its right shows auto attack is on. A line by the icon always names the spell the press casts
  ("Wrath", "Regrowth on Beryl"), and changes to a held modifier's spell.
- **Auto attack at the pull**: with a new enemy targeted and no fight yet, the first press of
  your key turns auto attack on (the game's own Start Attack: on, never off), and your opener
  comes with the next press. WoW: Forever doesn't start it when you cast, and the key can't
  change once the fight is on. A switch in the settings; one enemy can be left out
  (`noAutoAttack`).
- **The queue: four things on one key.** Left of the icon, each a little smaller, sit the
  three things your key casts with a modifier held, the modifier written above each: **CTRL**
  your second attack (Moonfire beside Wrath; between fights the next way to heal up, or the
  shown heal or buff on your friendly target), **SHIFT** your quickest heal on you, **ALT** your
  healthstone or healing potion (without one, the spell that holds or stops your target), and
  **C+S** (Ctrl and Shift together) another spell Flow may ask for in the fight, so its
  advice is on a key and not only on your bar. Hold
  a modifier and the big icon becomes that spell. In a fight they are all set at the pull;
  the one Flow advises pulses gold. A class says what its fights use (`fightKeys`). Each small
  icon shows its cooldown (the game's own sweep and countdown, so it works in a fight), goes
  grey when it can't be cast and red when out of range.
- **Cast button and key**: click the icon or press your Flow key to cast the suggestion. Set the
  key in `/flow settings`; it warns you about conflicts and never changes your own key bindings.
  In combat WoW freezes what a key casts, so at the pull Flow locks it to a real attack (a seal
  if none is up, then Judgement or Crusader Strike), never a heal. Ctrl, Shift and Alt + key cast the queue's three (above), in fights too.
  Ctrl-drag to move the button; Ctrl + mouse wheel over it resizes it. While a swing spell
  waits for your next swing (a druid's Maul), the button blinks red, as the action bar does.
- **The auto-attack badge** beside the target button shows the game's own Attack picture for
  your form, edged in your weapon's quality colour, and glows inside while you're swinging.
  Click it to turn auto attack off: it stays off until your next attack.
- **Flow Meters** also count damage taken, interrupts and deaths (right-click the meters). **Flow
  Deaths** shows who died and, for each, the game's own record of the death as a table (what hit
  them, who, how much, the health left) and a health graph; hovering one lights up the other
  (`/flow deaths`).
- **From stealth** (druid, Cat Form): out of a fight with an enemy targeted, Flow suggests
  Prowl; in stealth the target button opens with your best opener (Ravage, Pounce, Shred or
  Rake), then goes on to your usual attacks.
- **Combo points on the nameplate**: a five-part bar under your target's health bar, in the
  game's own combo colour (`/flow combo`).
- **Which spells take you out of a form** (druid): Flow watches your casts and learns, for each
  spell, whether it kept you in Bear or Cat Form or took you out. The spell's tooltip says so
  ("Flow: takes you out of Bear Form", "Flow: keeps you in Bear Form and Cat Form", or not seen
  yet); a form's own abilities say so from the start. `/flow forms` lists them.
- **Target button and self button**: Flow's icon is the target button (attacks on an enemy;
  heals, buffs and cures on a friendly target and your group). The self button
  (`/flow selfbutton on`, a key with `/flow selfkey Q`) is a second, blue button for you: your
  heals, food, bandage, cures, buffs, weapon stones and oils. By default it's docked under the
  target button as one block, with Shift, Ctrl, Alt and C+S written once between the two rows;
  Ctrl + mouse wheel over it gives it a size of its own, and Ctrl-dragging either one moves the
  pair. Both have the same edge and size, and a cast bar along the bottom.
- **Buffs for your group**: out of a fight, with nothing else to press, the target button casts
  your buffs straight on whoever in your party lacks one (Mark of the Wild for everyone, Thorns
  for the tank). When the game refuses one as weaker than what they have, Flow moves on to the
  next buff or person.
- **Craft the right amount**: on the profession window, Flow says how many to make to reach your
  target, with a Make N button for exactly that many, and tells you when to stop.
- **Flow Actions** (same key, out of combat, at your route step): at a fishing spot it equips
  your Fishing Pole, puts on your best lure, casts, then reels in when the bobber splashes; at a
  mining or herb step it turns on Find Minerals / Find Herbs and gathers; when you leave it puts
  your weapons back. Upgrades in your bags: it equips them (first, when you target an enemy).
  A kill you have targeted: it loots it, then skins it when the game says it's skinnable and
  you have Skinning (or gathers from it, where Herbalism, Mining or Engineering can). A dead
  friend targeted: it casts your resurrection. A quest's item at its step: it uses it.
  A living friendly player targeted (in your group or not): your buffs for others, then a
  heal when they're hurt or in a fight, with mana to spare.
  Crafting: campfire, open the profession, make exactly enough; by an anvil, forge or cooking
  fire with something to make, it opens Blacksmithing, Smelting or Cooking. Things to learn in your bags
  (recipes, scrolls): it learns them. About to fight (a kill step, or just
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
  nearest repair vendor Flow knows) and the route gets a Repair step. When a service is far away,
  Flow says if your hearthstone then a run looks clearly quicker (an estimate; it never uses it
  for you).
- **Buffs while questing**: keeps your seal, blessing and aura up; quiet in cities and inns.
  Remembers what you cast when the game hides your auras.
- **Heals when your health is hidden** (WoW: Forever hides it from add-ons): the game's own
  red low-health warning triggers your fastest heal; after any fight of 6 s or more a heal is
  offered for 15 s. Where health is readable, heals are timed so none of it is wasted, with an
  emergency heal when you'd die before you could react.
  Out of a fight the prompt clears as soon as your health is full: the game still says when
  your health changes, and six seconds without a change mean a full bar.
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
  objectives, quests to pick up, trainers you can afford, and profession steps) and points you
  along it. It learns trails as you walk, follows them around hills and rivers, and learns cave
  entrances so it sends you in through the door, not over the top. A quest step says when it's
  an escort (its giver may be away walking another player out, for a few minutes) or when the
  giver is deep in a cave (The Longwalkers). A quest in your log is always on the route: where
  the quest data has no place for an objective, the step goes to the game's own marker for the
  quest, or is listed with a lock and the reason. A class quest that teaches a spell (Bear Form)
  is always a step, whatever zone it starts in. Profession trainers are read when you open
  them, so the next tier is only on the route once that trainer says you can learn it. Distances come with a travel time (by air when a
  flight is quicker; Flow learns flight masters as you fly). Optional, off by default: a faint
  profession arrow (profession steps on a route of their own, behind the main arrow), and
  "Finish the area you're in first". Profession plans use what's in your bags and bank and smelt
  ore into bars. A step that needs something first goes after the
  step that provides it ("after Bear Form"), or waits with the reason: training Demoralizing
  Roar and Maul comes after the class quest that teaches Bear Form. A quest that needs you to
  bring something (a bauble from a lake, half a pendant) gets a "get it first" step where it's
  found; when that's on another continent, the steps that need it wait and say where it is and
  how to cross. Each trail stretch remembers the quickest you've covered it, so of two known
  ways the arrow takes the faster; a nearly full trail network thins its straight runs.
- **Ways between maps**: Flow learns where you cross from one map into another on foot or by
  lift (up Thunder Bluff, through a pass into the next zone). A step in another part of the
  map goes by the way you've used: the arrow leads to the lift, the route counts the ride (so
  steps on the bluff are done together), and the map's dotted path bends through it. Capital
  cities are walled: where Flow knows no way in yet, it says so. `/flow gates`. Flight paths
  count as ways too (`/flow gates` lists them): with no way known on foot, the arrow leads to
  the flight master and says where to fly. A druid's
  Teleport: Moonglade counts as travel too: a step in Moonglade is one cast away.
  And the way back is a person: in Moonglade a druid's arrow leads to Bunthen Plainswind
  (Horde) or Silva Fil'naveth (Alliance), who fly druids home for free, and says who to talk
  to. `/flow rides`.
  On any flight the arrow says where you're flying, when you land and what comes after.
  On the flight map, the flight master that lands you nearest your next step has a ring of
  dots in the route's colour and the step's name under it.
  With your next step on another map, the world map's dotted line still leaves from you,
  through the gate, to the map's edge; "Show on map" for a step elsewhere says which zone it's in.
- **Hearthstone**: in a town with an inn, when your stone is set somewhere else, the route
  gets a "Set hearthstone" step (Horde and Alliance towns and cities). A city beats a
  village (in Thunder Bluff with your home in Bloodhoof Village, you're told to set it
  there), a village near your city home isn't offered back, and a step that's a teleport
  away waits until you've set your home. `/flow hearth on|off`.
- **The route's colour tells you its state** (arrow, route and waypoints): **Shortest path**
  (rare blue, the default) and **Most XP first** (epic purple) are optimised; **Custom route**
  (legendary orange) means you picked the next step yourself with its ^ in the Flow Router (or
  "Go here next"). It goes there first and stays orange until you choose Most XP or Shortest
  again. The top row's (o) is where you're heading (a white ring on the map). Tooltips show
  each step's XP.
- **Dungeon runs** (with Questie): the arrow menu's Dungeons section lists the dungeon runs at
  your level (one wing, the quests you can do this trip; later parts wait for the next run) and
  how each compares to your questing XP per hour. Prepare a run and the pickups and short
  lead-in quests go on the route (plus any breadcrumb whose giver is next to one of those
  steps), then the entrance; inside, the route shows only that dungeon's quests. Wings are
  told apart by their bosses. In a group, "Share quests" shares the run quests party members
  lack. `/flow dungeons` lists the runs with each quest and what you still have to pick up
  ("Quests: 2/5", and what you've done before); `/flow dungeons <name>` puts you on that run's
  dungeon route, `leave` and `back` step off and on it, `off` cancels it. While a run is
  prepared a line under the arrow says so ("Dungeon route: Ragefire Chasm · Quests: 2/5"): click
  it for the run's quests. The dungeon route keeps your errands on the way (training that's
  waiting, selling and repairs, your bank), and "Ask my group in chat who has its quests" says
  one line in party chat.
- **Your questing zones**: you pick them, Flow doesn't. The Flow Router's Zones section (Route)
  lists your zones and every zone with quests for your level, each with its levels and how many
  steps or quests to pick up ("Ashenvale: levels 18-24, 22 to pick up - suggested"). Hover one
  for what it holds: your steps there, quests to pick up and their XP, where the quest givers
  stand (all in one place, or spread over several), how far apart the quests' mobs are, mob
  levels, elite quests, class quests and what you could gather. A few are marked "suggested"
  (good XP for your level, quests in one place, mobs close together). Tick a zone to quest there:
  the route only takes quests in your zones (per character; a trainer or vendor is wherever it
  is). Under a line: Quest in the zone you're in, Select all zones, Select no zones and Current
  zone only. With "Finish the selected zones first" (Order) on, an unticked zone isn't left out:
  its quests come after your zones'. `/flow zones` (`all`, `none`, `here`, `on <zone>`,
  `off <zone>`, `first`).
- **A note when you're in a zone you haven't picked**: a bar at the top of the screen, its edge
  pulsing orange, says so and what the zone holds, with **Quest here** (it becomes one of your
  zones) and **No thanks** (Flow never asks about that zone again). It waits until you have been in the zone half a minute. Not on a flight, in a dungeon or in a
  fight; Ctrl-drag moves it. Off in Flow Settings (Finding your way).
- **Alignment lines**: Ctrl + drag a Flow button and a line shows when it is level with the middle
  of the screen or with Flow's other button or the arrow; let go and it settles on the line.
- **Combo points on the nameplate**: a five-section bar under your target's health bar for a rogue or a
  druid in Cat Form, in the game's combo point colour (`/flow combo`).
- **From group to group**: in a kill or collect step's area the arrow doesn't stop at the ring.
  When you leave a group of spots, or stand in one with nothing to do, it points to the nearest
  group you haven't just worked, of any such step near the front of your route (`/flow hop`).
- **A quest's materials from the auction house**: when a quest asks you to collect something Flow
  has seen for sale there (5 Earthroot), buying it is an optional step at an auctioneer, with
  what it should cost, while one is close to your way and you can pay.
- **The arrow's words stack** above it, the longest line on top (below it in the lower half of
  your screen), and a button's small icons run toward the side of the screen it's on. Moving a
  Flow button shows alignment lines to what's on screen and snaps to them on release.
- **Above or below you**: the game gives add-ons no height. Flow logs what the game's own
  world marker answers while you play (`/flow height`), to find out whether an up or down
  arrow can be built; nothing is shown yet.
- **Trips Flow learns**: each trip from one step to the next is timed, your quickest is kept, and
  the route is ordered by those times instead of the straight line (`/flow legs`).
- **Zone info on the world map**: hover a zone on a continent map for its name, level range (coloured
  against your level) and the fishing skill its waters need; hold Shift for the fish and how often.
- **Hard and elite quests wait while you're solo**: a quest 3 or more levels above you, or an elite
  one, is held off the route (listed, locked) until you can do it or you're in a group.
- **Quest levels beside steps** follow the game's own map filter (Show quest levels, Quest difficulty
  color): red and orange above you, yellow full XP, green easy, olive when the XP drops, grey for none.
- **Crossing to another continent**: while steps of yours wait across the sea, the route gets a step
  at the zeppelin tower or dock that gets you there by the shortest trip (`/flow crossings`).
- **Errands on a custom route**: a custom route is your quest lines in place of the quest kinds, plus the
  errands ticked under Route includes: class trainer, weapon skills and riding; repair, selling and
  hearthstone; the bank; flight paths to learn; crossings. Professions start off. These ticks are the
  custom route's own, so your usual route's come back when you clear it.
- **Custom route by quest line**: "Go here next" on a step, or a line's link in Flow Improvements,
  picks that step's whole quest line (to the spell, for a class quest), and your route shows only
  the lines you picked, planned together. Right-click a step to remove it or its line; the bar
  under the Flow Tracker says what you're on and clears it with a click (`/flow focus`).
- **Battlegrounds in Route includes**: battleground quests (in your log and to pick up) are a tick
  of their own, off until you want them. Hover any quest step for the XP it gives at your level.
- **Where next**: `/flow where` lists the same zones in chat, the most XP first.
- **Your own waypoint** (Ctrl or Alt-click the map, `/way 45.2 63.1`, or "Point the arrow
  here") isn't a step on the route: the arrow turns green and points there along a green line
  on the map, then goes back to the route when you arrive or clear it.
- **Near first**: the route finishes the steps around you before it sends you far; far steps
  and item drops whose mobs are spread out wait (`/flow nearfirst on|off`).
- **Hub business first**: in a quest hub the route turns in every finished quest there and
  picks up the quests on offer before heading out, like a walkthrough.
- **Quest areas**: in an objective area the arrow shows a glowing ring, a beam of light and
  ripples (they speed up when you're right on the spot); hover it to see every quest there. A
  "do it here" step (crafting, a recipe to learn) shows its own icon bouncing in the ring.
- **Arrow**: a glossy metal chevron that glides as it turns and floats over its own shadow. Its
  colour says how close you are: grey while the step is in another zone, then orange (far) through
  yellow to green (close), and blue once you're in its area (`/flow nav arrowcolor route` gives
  it the route's colour instead). Right-click it to pick Modern, 3D (pillars) or Flat lines
  (`/flow nav arrow modern|3d|flat`). It turns with your character. (The game doesn't tell
  add-ons where the camera points, so it can't follow the camera.) The login intro spins the
  arrow around a gold FLOW with the version underneath (`/flow splash`).
- **Corpse arrow**: when you die the arrow turns red and points to your corpse.
- **Milestones**: class training and your mount always make the route and fit around the
  quests on the way. Flow tells you to start saving for your mount 5 levels early.
- **Route includes**: one tick per kind of step, in the route menu (the Flow Router's "Route:"
  dropdown, or right-click the arrow): current quests, new quests, low-level quests (every
  quest in the zones you're questing in, any level), class trainer / weapon skills / riding,
  professions (on the route, or on their own faint arrow), and repair / selling / hearthstone
  steps. "Select all" and "Clear all" set them in one click; the ticks stay open while you
  choose. Right under them: send the arrow to the nearest repairer, vendor, flight master,
  innkeeper, mailbox or banker.
- **Along the way**: optional farming (meat for Cooking) is never a detour; loot it as you go.
- **Blocked steps**: steps you can't do yet stay listed, greyed, with the reason ("needs
  1g 20s", "needs a Mining Pick"), and come back by themselves when you can.
- **Flow Router** (the square button above the world map's quest log button, a little route
  list with an arrow that points the way the quest log button's does): the route list,
  just right of the map (and so of the quest log; either or both can be open),
  with a "Route:" dropdown (what the route includes, and the order). Hover a step for details, click it for its step card, use the
  `^` handle to route from that step (it stays marked red), right-click to hide it or "Point
  the arrow here". A button above it shows or hides the route on the map, and one above that
  shows the **flight masters**: green rings for the flight paths you have, light blue for the
  ones you don't have yet (free: talk to them once), and the flight your next step is quicker by
  in the route's colour, joined by a line. Hover one for who and what. Click one for where you
  can fly from it (green lines) and can't yet (red); point at a line, or near it, for that
  flight's time; click again to clear. Right-click one to point the arrow there, and again to
  take the waypoint off.
- **World map and minimap**: the route as a faint dotted trail, like a treasure map (the stretch
  to your next step, and that step's dot, in the arrow's colour). The dots drift slowly toward
  the next step, so you see which way the route goes, and "Path opacity" in the settings makes
  the trail stronger or fainter. The stretch from you follows the way the arrow takes (a
  trail you've walked, a gate, a cave's entrance), not a straight line; numbered waypoints with quest levels (`3 [9]`) and pickups
  (`!2`); labels push each other apart so they don't overlap. Quest areas are drawn as clouds
  with borders; the minimap shows your current step's area the same way. On the minimap the
  step in view is ringed with small dots, the middle left clear for the game's own icon and its
  above/below arrow. Hover a step in the Flow Router and the map shows that step alone.
- **Step card**: Flow's view of a step (drag it by its title). Its "Show on map" and "Select in
  quest log" links open the map when it's closed (the game opens its own window: Flow passes
  your click to the game's own button, so its code never runs the map). The arrow's own panel is a drawer
  beside the arrow: click the arrow to open it, click again or its X to close it.
- **Flow Tracker**: the route under Questie's tracker, opening downward (a faint rail shows the
  order). It and Questie's tracker open and fold on their own: either or both. Click a row for
  its step card; hover it to see its area on the minimap; Ctrl-drag the header to move it.
  A quest that gives you an item to use shows it at the right end of its row: click the icon
  to use it (it's placed out of a fight; `/flow questitems`). Standing at that quest's step,
  your Flow key uses the item too.
  Its right-click menu (and Flow Settings) shows or hides the other two quest lists: Questie's
  tracker and WoW's own (which comes back at a /reload once Questie's is off).
- **Steps**: the route plans up to 30 steps ahead. Choose how many the world map and
  the Flow Tracker show: just the next step, the next 3, 5 or 10, or all of them (/flow settings,
  the arrow's right-click menu, or `/flow nav steps 1|3|5|10|all`). The Flow Router always lists
  the whole route.
- **Lite mode**: in dungeons, raids and boss fights Flow eases off route planning and map
  updates so it never adds lag; the rotation and the Flow key run as normal.
- **The Flow menu**: right-click the arrow, the Flow Tracker or a step. The thing you clicked
  is shown open; under it the same sections everywhere, in one order, each a row that pops
  out when you point at it or click it ("Order  Shortest path"): Order, Route includes, Go to
  the nearest..., Your waypoint, Dungeons, Party, Zones, Steps, Buttons (the self
  button on or off, docked or not), Flow windows. The arrow's look and the key bindings are in
  Flow Settings.
- **Party routes**: share your quests as a party route if you want one; your own route stays
  separate. Anyone following it can edit it; nobody owns it.
- **Your own waypoint**: `/flow way repair` or `vendor` (or right-click the arrow) for the nearest one; Ctrl- or Alt-click the world map, paste coordinates (`/way Elwynn Forest
  45.2 63.1`, or right-click the arrow: Set a waypoint), or `/flow way x y`; it clears when you
  arrive.
- **Only quests you can get**: holiday quests drop out when the event ends, and quests an NPC
  doesn't offer are skipped.
- **Quest markers on nameplates**: skull with your kill count, diamond with the count of an item
  a mob drops, star for NPCs to talk to; several per mob. A mob that drops what one of your
  professions wants (Kodo Meat for Cooking) gets that profession's icon with your count, and a
  line in its tooltip: "Flow: loot Kodo Meat for Cooking, 0 -> 8".
- **Missed quests**: quests you skipped in zones you've quested in (`/flow missed`).

### Professions
- **Skill plans**: for each profession, the cheapest path to the next skill cap: buy, learn,
  smelt, craft, gather or farm, with prices from vendors you've visited. These go into the route
  (`/flow prof plan`).
- **Guides** for Blacksmithing, Mining, First Aid, Cooking, Fishing and Herbalism, plus the
  recipes Flow has seen in your profession windows.
- **Gathering keeps up with the zone**: when a herb grows where you are that your skill can't
  pick, the route gets a step that names what to gather ("Pick Earthroot, Peacebloom or
  Silverleaf: Herbalism 35 -> 50 (Mageroyal here needs 50)"), taken in on the way behind your
  quests and shown as an area on the map; an empty spot is passed over after a few seconds.
  When your route is about to take you to a zone whose herbs are beyond you, that step comes
  before you leave.
- **Materials from the auction house**: a material nothing drops or sells becomes a step at an
  auctioneer, on a price Flow has seen ("Buy 57 Wool Cloth at the auction house (about 58s)").
- **Tools**: reminds you to buy the Mining Pick, Blacksmith Hammer or Fishing Pole (and a lure),
  and knows when you have one.
- **Chained professions**: fish you'll catch levelling Fishing count toward Cooking, so there's
  less meat to farm. Cooking goes to a real fire unless you can make a campfire.
- **Exactly enough**: the profession window gets a Flow panel with a Make N button for exactly
  what reaches your target, and a "that's enough" notice when you get there.
- **The professions card** pops up only for a main profession you've still to learn (with fewer
  than two) or when Flow's suggestion changes, never to train a tier: that's on your route and
  in Flow Improvements.

### Gear and items
- **Gear scores per role** in every tooltip, shown with your spec icons (Retribution, Holy,
  Protection) and a mark above each (green arrow up better, red arrow down worse, grey dash
  about the same), compared with what the item would
  replace (two one-handers are judged as a pair against a two-hander), or with your gear set
  for that role (Equipment Manager or `/flow gear save`). Weapon speed counts for each spec.
- **Quest reward badges**: the same spec icons and arrows on quest rewards: the big green arrow
  on the best upgrade for the spec you're levelling, or, when none is one, a gold coin on the
  one that sells for most (wearable or not).
- **Upgrades at vendors**: the same badge on gear a vendor sells, and one line in chat when
  something for sale is better for the spec you level as, with its price.
- **Bag icons**: top left, what Flow will do with it: the (o) marker on an item your current
  step wants you to use, a bank icon on what Flow Banker will put in your bank at your next
  visit, the gold coin to sell, the auctioneer's mark for the auction house, DE to disenchant.
  Top right, what it is: a quest "!" for items your quests need, a profession's icon for its
  materials and tools. Along the bottom, spec marks per role. The tooltip lists every reason to keep an item (e.g. "Linen for
  First Aid"). A material your skill has moved past is let go ("your First Aid is past it"), a
  spare bag no bigger than the ones you wear is marked to sell, and something only another
  class can use ("Classes: Mage") goes to the auction house or a vendor.
- **Leftover quest items**: a quest item no quest in your log uses is looked up in the quest
  data: kept, with the quest named, when one you haven't done uses it; sold or "destroy it"
  only when its quest is done. The bags and Flow Improvements say the same thing.
- **Loot rolls**: the item on the roll window gets the same marks as your bags: the big green
  arrow and its figure for an upgrade, or what Flow would do with it (the gold coin to vendor,
  the auctioneer's mark, DE), and the spec marks along the bottom; with "Flow: upgrade +2.1:
  Need" or "Flow: not an upgrade: Greed, then vendor it" above it. Flow never rolls for you.
- **Weapon skills**: Flow knows which weapon skills you've trained; an upgrade that needs one
  puts a weapon master step on the route. Weapons your class can never use are marked to sell.
- **Inventory** (`/flow inventory`): every item in your bags with what Flow would do (sell,
  auction house, keep), why and which rule said so, the vendor price and the last auction
  price. Saved with the diagnostics.
- **A second key for heals and potions**: turn on the self button and give it a key
  (`/flow selfbutton on`, `/flow selfkey <key>`). In a fight that key is your quickest heal;
  Shift, Ctrl, Alt and Ctrl + Shift with it cast your heal over time, your other heal, your
  healthstone or potion, and your bandage (`/flow carekeys`). Out of a fight the two keys
  split the same way: the self button's key is for **you** (heal up, eat, drink, bandage, a
  cure for yourself, your buffs, fishing), Flow's key is for **your target** (attacks on an
  enemy; heals, buffs and cures on a friendly player you target) and for **your group** (their
  buffs, cast straight on whoever is missing one).
- **Flow Meters**: two small lists, threat on your target (pets too) and damage, from the
  game's own counts. Right-click them to choose when they show (in combat, in a group, always),
  2, 5 or 10 players (the group's row on top), what they count (damage per second, total
  damage, healing per second, total healing), and this fight or all fights since a reset.
- **Your threat on enemy nameplates**: in a group, in a fight, a small number at the right of
  each enemy's nameplate: your threat as a share of whoever it's attacking, coloured by where
  you stand (tanking: green yours, orange losing it, red lost; otherwise green, yellow from
  50%, red above 90%, flashing at 100%). `/flow threat on|off`.
- **How many you have**: every item's tooltip says how many you have, split between your bags
  and your bank.
- **Your buffs on a player's tooltip**: hover a friendly player and see, for each buff you give
  others, whether they have it (from anyone, a group or stronger version too) or it's missing.
- **A form's new spells on that form's bar**: a spell the game drops on your bars that needs
  Bear Form, Cat Form or a stance is moved to that form's bar.
- **Flow Improvements in colour**: white for worth doing, yellow for close to a limit or important,
  red when you're losing something until it's done (a profession at its cap, full bags).
- **Quest items in your bags** (`/flow questbags`): what clears each one. With nearly full bags a
  finished quest's hand-in always stays on the route, comes early and says how many slots it frees;
  Flow Banker puts away what waits for another continent or another quest, and offers it back when
  a quest here needs it.
- **Gear set icons on your bags**: an icon for each of the game's equipment sets beside the Flow Banker
  tab: hover for its name, click to put it on. The one you're wearing has a gold edge.
- **Sets Flow builds**: a spec's set gets its spec's icon, and Flow can build a Fishing set (your
  pole): one click on its icon and you're fishing. Right-click a set's icon for its picture, the
  icons' size and the sets Flow can build. Every set has a default picture (its spec's, or Fishing's):
  "Reset to the default" puts it back, in the game's Equipment Manager too, and "Make this the
  default" makes the picture you chose the default for sets of that name on all your characters.
- **Keep set for**: a tick for each of your specs under your bags (below the money line). Unticked, gear that's
  only good for that spec is sold like any other you don't need. Build sets makes the game's own
  equipment sets for the ticked ones (`/flow keepsets`).
- **Flow Banker, To sell**: what the Flow Seller takes at the next vendor or auction house, and
  what's in your bank that Flow would now sell (a material your skill has moved past): Take out
  at a bank brings those to your bags. Hover a thing in To bank for why Flow keeps it; Alt-click
  one you once bought back to let Flow sell it again.
  Your own choice: Shift-click a thing there to sell it, click a To sell line to flip it between
  sell and keep, right-click for Flow's own choice; "Reset to Flow's" drops all your choices.
  A step that has you fetch something ("Get from your bank: 5 Mild Spices") is in the Take out
  list too, and the window opens on it at the bank. Flow never moves a thing one way and then
  back: what's parked for a quest across the sea stays parked until you're there.
- **Materials go to the auction house, never a vendor**; an item bought back from the vendor's own
  Buyback tab isn't sold again.
- **Paladin seal and blessing**: your pick in Settings (`/flow seal`, `/flow blessing`); in Auto,
  the one you last cast on yourself for your role, else your role's own. Your role is the one you
  chose under Your role, else your talents, else your class. A seal you cast in a fight counts for
  that fight.
- **Flow Trader**: when Flow reads the auction house's listings it looks for deals: listed under what
  a vendor pays (a certain gain), or at half an item's usual price or less (buy and post again: a
  guess). Its tab on the auction house lists them, each with a button; every payment is your click
  (`/flow trader`). When your route sends you there to buy something ("Buy 8 Dig Rat at the
  auction house"), that item heads the list with the same Buy button.
- **One Flow line on an item's tooltip**: what Flow does with it, whether it goes to your bank,
  and the reason that matters.
- **Flow Prices**: an item's auction price over time as a chart, time to scale, a dot for each
  visit to the auction house (hover for the price and when). Alt + click an item, click a line
  of Flow Banker's Auction prices, or `/flow price <item>`.
- **Flow Auctions**: at the auction house, what Flow would post and at what price; one click
  posts each. What keeps coming back unsold becomes a vendor item.
- **Flow Banker**: at a bank it lists what you won't need soon (materials Flow keeps for
  later that no step on your route uses) and deposits it at a click; the route adds a bank
  step when one is on your way. Away from a bank its "In your bank" view shows what was there
  when you last opened it (laid out like the bank, your things from the top left), and
  "Auction prices" what Flow last saw at the auction house. A Flow Banker tab on your bags and
  on the bank window opens it (`/flow banker`). An NPC the quest data calls a banker who opens
  no bank is learned as not one.
- **Leave junk behind when looting** (Flow Settings, off by default; `/flow loot nojunk`): Flow
  loots everything but grey items and closes the window, with a note by your cursor naming what
  it left; open the corpse again to take it by hand. Not for skinners: a corpse with junk still
  on it can't be skinned, and Flow says so when you have Skinning.
- **Flow Seller**: at a vendor Flow auto-sells grey junk and everything else it marks "sell"
  (outgrown gear, food and drink you've outgrown...), 12 a visit, the size of the buyback tab.
  One item at a time, all the junk first, so your own items are the last sold and the ones the
  buyback tab keeps; "Buy back" lists only what the vendor still holds.
  It never sells profession tools or materials you need. Green gear and better materials go
  to the auction house only on a price Flow has seen that beats the vendor after the cut and
  the listing fee; with none known they're vendored (rare gear is always held). Ammunition
  your class can't shoot and other classes' spell reagents are sold too. Buy any item back with one click, and
  Flow then never sells it again. Auto-sell has its own switch on the drawer and in Options.
  With full bags a "sell at a merchant" step goes on the route. After 12 sales the drawer says
  why it stopped and what selling the rest costs you.
- **Skill books**: tells you to hold "+N skill" items until the last points before a cap.

### Progress advice
- **Advice list** (the round spyglass button with a count): spells to train (with cost), items
  to equip, professions behind your level, talents and habits from your best fights. Rows that
  are places route you there.
- **Your choices** (`/flow choices`): every spell you cast in a fight is set beside what the
  target button advised at that moment: cast as advised, your key while the advice was a bar
  spell, or your own pick. For the differences Flow notes the situation (moving, the enemy on
  you, the advice out of range...) and compares kill speed in fights with and without that
  choice. The rotation is tuned from this report: a pattern with a reason becomes a rule.
- **Training and talents**: trainer reminders, profession targets for your level, and spec
  advice (`/flow spec`).
- **Flow Talents** (`/flow talents`): your talent trees as the game has them, with Flow's
  levelling build over them: what to take with the points you have now (gold), what comes at
  each of your next levels, and where the build ends up (druid: 5 / 41 / 5). Hover a talent
  for the game's own text and why it's in the build. A reference: you spend the points.
  A build is one registration per class (`talentBuild`); a class without one still sees its
  trees.
- **Flow buttons on WoW's windows**: a Flow tab standing on top of the game's talent
  window, spellbook, profession window and character window opens the Flow view that goes with
  it (Flow Talents, Flow Key Bindings, Flow Professions, Flow Improvements). Nothing opens until
  you click. `/flow buttons`; one registration each (`gameButton`).

### Quality of life
- **Each character keeps its own**: fights, trainer, recipes, profession plan, role, hidden
  steps and the like are saved per character, so "Ways to improve" and the route are about the
  character you're on. Settings, learned trails and NPC places are shared by all of them.
- **Options > AddOns > Flow**: Flow's options, grouped by when you use them (easy keys: the
  target and self buttons' four keys, hover-to-bind and the keys bound to spells; in
  a group, finding your way, quests, loot and selling, new spells and professions, what's on
  your screen), and, kept apart, Flow's suggested WoW
  settings (auto loot, nameplates, target of target, camera zoom, the camera staying where you
  put it, the low-health warning, health and mana numbers on your and your target's frames,
  the Interact key reaching objects, timestamps...) with a "Use
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
- **Tooltips with room**: a tooltip Flow opens is wide enough for its sentences.
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
`/flow nav xp|distance|northup|unhide|sort|steps`, `/flow prof plan`, `/flow gear sets`, `/flow sell`,
`/flow bind`, `/flow fights`, `/flow talents`, `/flow splash`, `/flow perf`, `/flow log auto`,
`/flow test`, `/flow api`, `/flow copy` (what Flow said lately, ready to copy), `/flow nearfirst`,
`/flow dungeons`, `/flow zones`, `/flow threat`, `/flow meters`, `/flow selfbutton`, `/flow selfkey`,
`/flow leftovers`, `/flow banker`, `/flow inventory`, `/flow questbags`, `/flow keepsets`,
`/flow legs`, `/flow trader`, `/flow hop`, `/flow where`, `/flow price <item>`, `/flow combo`,
`/flow height`, `/flow audioreset` (WoW silent after your
speakers came back from a sleeping screen or Remote Desktop).

## For developers
Start with [CONTRIBUTING.md](CONTRIBUTING.md) (it lists what review keeps finding, so your pull
request needs fewer fixes; the maintainer's side of a merge is [docs/MERGING.md](docs/MERGING.md)).
Using Claude or another AI assistant? Point it
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
- **Looking at the game:** `tools/look.ps1` saves a picture of the game's window (only that
  window, on your own machine) so an AI assistant can check how something looks while you play.
- **Checking the route:** `/flow export` (and every diagnostics snapshot) writes your quests,
  skills and the route as lines a script reads; `tools/route-check.ps1` plans the shortest
  walk through the same steps by itself and says where Flow's order differs, what the
  hearthstone would save and what has no step at all.
- **Dev install:** the game's `Interface\AddOns\Flow` is a junction to this repo, so `/reload`
  picks up changes.
- **`/reload` is enough, always (people and AI assistants: don't ask for a game restart).**
  WoW: Forever loads everything again on `/reload`: changed files, new files and the changed
  `Flow.toc`. Older WoW clients needed a restart for a new file; this one doesn't. Checked on
  2026-11-10 by adding `Modules/Nav/RouterDock.lua` while the game ran: it loaded at the next
  `/reload`. A self-test ("core: a file added while the game runs loads on /reload") keeps
  watch; restart only if it fails.
- **Packaging:** `tools/package.ps1` builds a release zip; see [docs/PUBLISHING.md](docs/PUBLISHING.md).
- **Where the route is going:** [docs/FLOW-GRAPH.md](docs/FLOW-GRAPH.md) is the plan for
  sharing learned trips between players and for one optimised order through every quest. A
  plan: nothing is uploaded anywhere.
- **Price history:** `tools/save-prices.ps1` saves the day's public auction prices
  (TradeSkillMaster's public data) into a folder beside the repository, a day a folder.

## Licence
Copyright (C) 2026 Sooth. Flow is free software: you can redistribute it and/or modify it
under the terms of the [GNU General Public License, version 3](LICENSE). It comes with no
warranty.

# Changelog

## Unreleased

- **Druid: Balance and Feral talents now set your role to DPS;** tanking stays your choice.
- **A class Flow has no rotation for still gets potions, bandages, food, drink and breaking free.**
- **`/flow spec` always says your role and where it came from;** Flow Talents says when its build isn't for your role.
- **Stones, oils, elixirs and Well Fed food now come up at a dungeon's entrance.**
- **With Professions off, a skill a quest asks for stays on the route.** The step reads "needed for quest <name>";
  plain skill-ups still drop.
- **Skinning gets a levelling plan.** Skin beasts of the level your skill allows, along the way (never a detour),
  plus a stop to buy a Skinning Knife when you carry none.
- **Checks on every push and pull request:** lint, toc/file structure, and the self-tests that need nothing of the
  game, run offline on Lua 5.1 (`tools/run-tests.ps1`; tests that need the game are reported as skipped).
  `check-paths` now catches single-backslash texture paths. New docs: `docs/TESTING.md`, `docs/PERFORMANCE.md`;
  README covers installing, troubleshooting and rollback.
- **Flow no longer says "Turn in" for a quest you haven't finished.** When a quest's objective was off the route
  (a quest 3 or more levels above you held until you level, an elite, a zone you didn't pick), its hand-in had
  nothing left to wait for, so "Turn in: Deepmoss Spider Eggs" showed at 0/15. Now the hand-in waits off the
  route with its objective, listed with the reason, and comes back when the objective does. A step that only
  goes after another one to save a trip still stays: class training isn't held back because the quest that
  teaches Bear Form is.
- **The Flow key turns on Find Minerals or Find Herbs whenever the minimap tracks nothing.** It used to offer it
  only at a mining or herb step on the route, so after dying or logging in you gathered blind. One press; the game
  lets an add-on cast only from a key press. Away from a gathering step it never replaces tracking you chose
  (Find Fish, Track Beasts); town tracking (Flight Master, Repair) doesn't count. With both skills, Find
  Minerals, or Find Herbs when an herb step is on the route. Only when there's nothing else for the key to do,
  and never in a fight, mounted, on a flight or while you eat or drink (a cast would stand you up). If the
  minimap still reads it off after you cast it, Flow stops asking instead of asking again.
- **Your role: set it in Settings, or Flow reads it from your talents.** Settings, Easy keys, "Your role": Auto,
  DPS, Heal or Tank (also /flow spec dps|heal|tank|auto). Auto is now the talent tree you've put the most points in
  (before talents, or with two trees tied, your class's usual levelling role); it used to be the recommendation
  only, whatever your talents. Your choice always wins over your talents, everywhere Flow uses your role: gear,
  food, a paladin's seal, blessing and Righteous Fury, a druid's Bear Form.
- **Your talents are read on WoW: Forever.** Forever's talents are one sheet with no classic talent API, so Flow saw
  none and Auto stayed on the recommended role whatever you'd spent. Flow now reads the sheet's three trees, and
  tries again a few seconds later when the game hasn't loaded your talents yet (at login), instead of seeing none
  until your next /reload.
- **Paladin: Righteous Fury when you tank.** Suggested when your role is Tank (your choice, or Protection talents in
  Auto) and it's missing or running out between fights. With "Your role" set to DPS or Heal, never, whatever your
  talents.
- **Paladin: the seal follows your role.** Tanking: Fury; DPS: Command once you have it; healing in a group: Wisdom;
  otherwise Righteousness. A seal you pick (Settings, /flow seal) now goes on at once even while another seal is up.
- **Paladin: cast the seal you want and Flow suggests it from then on.** No settings or command needed: in Auto, a
  seal you cast yourself that differs from Flow's suggestion is kept for the role you're playing, every fight,
  until you cast another (it used to last only until the fight ended). Casting the seal Flow suggested, or using
  Flow's key, changes nothing. A seal you picked in Settings stays: a cast then lasts the fight. /flow seal auto
  (or Settings, Auto) goes back to your role's seal.
- **Paladin: the blessing follows your role, and the one you cast.** Healing: Wisdom; tanking: Kings once you have
  it; otherwise Might (it was always Might). A blessing you pick (Settings, "Paladin blessing", or /flow blessing)
  stays, and replaces the one you have up. In Auto, cast another blessing on yourself and Flow keeps that one for
  the role you're playing; casts from Flow's own keys and blessings on someone else don't count. /flow blessing
  auto, or Auto in Settings, forgets it.
- **Druid: Bear Form when tanking.** With your role Tank, Flow suggests Bear Form (Dire Bear Form once known) when
  you target an enemy or are in a fight.
- **Food no longer jumps ahead of your buffs and rotation.** The self button put Well Fed food before your aura,
  seal and blessing, and the Flow key put it before the rotation's own suggestion. Now your buff spells come first
  and food comes when they're up. The food is scored for the spec Flow plays you as at that moment (it used to be
  scored once, when your bags were read, so a spec or talent change kept the old pick). Healing up still comes
  before both on the self button: a cure, a drink, a heal spell or food that heals you shows before the Well Fed
  food and your buff spells (only a bandage waits, since the Well Fed food heals you too). `/flow rot why` lists
  your Well Fed foods best first, what each gives, Flow's pick, which ones are skipped and why, and says when
  you're already Well Fed.

- **Flow now suggests the Well Fed food that's best for your fights.** It used to suggest the first Well Fed food
  in your bags, so Smoked Sagefish (mana every 5 seconds) could come before Dry Pork Ribs (Stamina and Spirit).
  Now it reads what each food's buff gives (Stamina, Strength, Agility, Intellect, Spirit, mana or health every
  5 seconds, attack power, spell damage and healing, alone or several at once) and picks by your class: Stamina
  first for everyone, Strength and Agility for those who hit, mana and Intellect only for those with mana. For
  paladins and druids the stats that count are the ones Flow's gear advice weighs for your spec. Food whose buff
  does nothing for you (mana food on a warrior or rogue) isn't suggested for the buff. Two foods that score the
  same: the higher level one, then always the same one, whatever order your bags are in.

## 0.35.377

- **A custom route now does the errands on the way.** It used to be only your quest lines'
  steps, so landing in the Undercity with spells to train or a flight path to learn, the
  route walked you past them. Now a custom route is your lines **in place of the quest
  kinds**, plus the errands ticked under **Route includes** in the Flow menu:
  - on from the start: class trainer, weapon skills and riding; repair, selling and
    hearthstone; the bank; flight paths to learn; crossing to another continent;
  - off from the start: professions.
- **Route includes shows it.** On a custom route its first row is your custom route, ticked
  and greyed (clear the custom route to leave it), and Current quests, New quests, Low-level
  quests and Battlegrounds are greyed with "your custom route instead". The other ticks are
  the custom route's own: change them, or use Select all and Clear all, and your usual
  route's ticks are as you left them when you clear it. Clear all leaves just your lines.
- A crossing is still only on a custom route for a line that needs it. `/flow focus` lists
  the errand ticks and how many errand steps the route kept.
- For add-on authors: a `routeKind` can say `custom = "lines"` (the picked lines stand in
  for it) or `custom = false` (starts unticked on a custom route).
## 0.35.376

- **Every gear set has a default picture, and its icon's menu can put it back or change it.**
  Right-click a set's icon on your bags:
  - **Reset to the default** drops the picture you picked for that set and hands the default
    to the game as well, so the Equipment Manager shows it too. Use it on sets you had before
    Flow gave sets pictures (your Feral (Cat), Feral (Bear) and Restoration sets): they get
    their spec's icon;
  - **Make this the default for (set)** makes the picture the set shows now the default for
    sets of that name, on all your characters. From then on a reset, or Flow building that
    set again, uses it;
  - **Forget my default** goes back to Flow's own.
- Flow's own default is one rule for everything it builds: a spec's set has its spec's icon,
  Fishing has the fishing one, and any set added later has one by having an icon. A set of
  your own making has none until you make one: a reset leaves it with the game's picture.
## 0.35.375

- **The gear set icons on your bags are bigger, and have a menu.** They're 26 pixels now (20
  before). Right-click one for:
  - **Icon size**: Small, Medium or Large;
  - **Picture**: your specs' icons, Fishing, and a few plain ones (shield, sword, staff, armor,
    bag). The pick is kept for that set and handed to the game, so its Equipment Manager shows
    the same where the game allows. For any other picture the menu says where the game's own
    chooser is: character window, Equipment Manager, pick the set, Change Name/Icon;
  - **Build a set**: the sets Flow can make for you that you don't have yet.
- **Sets get a picture that matches.** A spec's set shows its spec's icon (Cat Form for Feral
  (Cat), and so on) instead of whatever the game gave it; a set you made yourself keeps the
  game's picture unless you pick one.
- **New: a Fishing set.** With Fishing and a pole in your bags, "Build sets" (and the icon
  menu) makes a "Fishing" set: Flow puts your pole on, saves the set, and puts your own gear
  back. From then on its icon is on your bags: one click and the pole is in your hands, and
  the target button casts as it does whenever you hold one. Click your spec's icon to switch
  back.
- For add-on authors: a set Flow can build is one `ns:Register("gearSet", ...)` (its name,
  icon, when to offer it and what goes on); `Modules/Gear/SetRecipes.lua`.
## 0.35.374

- **"Quest here?" asks once, and takes No for an answer.** Leaving Durotar on the zeppelin,
  the note came up, you said no, the game flickered between zones and it asked again.
  - **No is for good**: the second button is now "No thanks", and Flow never asks about that
    zone again on this character. To quest there later, tick it in the Flow Router (Route,
    Zones).
  - **It waits until you've settled**: the note only comes up after 30 seconds in a zone
    without a break, so passing through, a zeppelin leaving and the game's flickers between
    zones don't bring it up.
## 0.35.373

- **Fixed: the stutter in the first seconds after the game loads.** It was Flow's own
  self-tests. They ran 8 seconds after every login, spread over frames since 0.35.336, but
  they're about 3 seconds of work and single tests take half a second, which no spreading can
  cut up: the log showed 17 to 21 frames of 150 ms or more after each login, the longest near
  600 ms. They no longer run by themselves after login, for anyone. `/flow test` still runs
  them when you ask.
- **Players no longer pay for them at logout or `/reload` either.** The diagnostics ran every
  test as you logged out, about 3 seconds each time. Only a developer install does that now.
- **Lite mode covers raid groups and battlegrounds.** Flow already eased off inside a dungeon
  or raid and in a boss fight. Now also whenever you're in a raid group, wherever you are, and
  in a battleground or arena. And it eases off more:
  - the route is gathered at most once every 20 seconds, however many quest and bag events
    arrive (each gathering is about 60 ms of work);
  - the arrow and minimap run at 2 a second, the map and tracker every 2 seconds, the meters
    once a second; trips aren't timed.
  Your buttons, the rotation, the meters and your bags run as always. `/flow perf` says
  whether it's on and why; Flow Settings, In a group, "Ease off in raids, dungeons and
  battlegrounds" turns it off.
- Fixed a self-test that failed while you were on a custom route.
## 0.35.372

- **"Go here next" works on a step across the sea.** Those steps are locked rows (they can't
  be walked to), so the entry was greyed out. Now picking one adds its quest line to your
  custom route and makes its zeppelin or boat your next step; Flow says so in chat. In the
  Flow Tracker's and the Flow Router's right-click menus, and on the step's card.
- **The crossing comes first when you're standing next to it.** It was always planned after
  everything left on your continent, wherever you were, so in Orgrimmar with steps waiting in
  Silverpine the route still sent you back out first. Now, within about 800 yards of the
  tower or dock:
  - with your hearthstone ready (the way back is one cast), the crossing is the next step;
  - without it, the crossing is planned with the rest by its distance;
  and far from it, it still waits until you've finished here. The step's details say which.
## 0.35.371

- **Flow Improvements' link button says what it does.** Hovering it now reads "Add to custom
  route" at the top, then the step on its own line, then the explanation: its quest line
  becomes your route, with any lines you added before. A step that's already on your custom
  route says so, and one that can't be walked to from where you are says "Open the step" and
  why it isn't added.
## 0.35.370

- **Quest levels beside steps follow the game's map filter.** The level in brackets after a
  step's number ("3 [16]", in the Flow Tracker, the Flow Router, the world map's pins and a
  step's tooltip) now goes by the game's own **Show quest levels**: untick it in the map
  filter and the brackets are gone from Flow too.
- **And they're coloured by what the quest is worth to you**, while the game's **Quest
  difficulty color** is on:
  - **red**: 5 or more levels above you; **orange**: 3 or 4 above (hard);
  - **yellow**: about your level, full XP; **green**: a few levels below, easy and still full XP;
  - **olive**: 6 to 9 below, the XP is dropping; **grey**: 10 or more below, next to no XP.
  A step's tooltip says it in words ("Level 16: well below you: the XP is dropping").
- Show quest levels is read from the game for certain. The name of the colour setting
  couldn't be checked from outside the game: Flow looks for it under the names it's likely to
  have, and `/flow questlevels` says which it found. If it finds none, levels stay coloured.
## 0.35.369

- **New: the route takes you to the zeppelin or the boat.** Steps on another continent were
  only locked rows with a sentence about how to cross. While any of your steps wait across the
  sea, the route now has a step for the crossing itself: "Zeppelin to Undercity (3 steps wait
  in the Eastern Kingdoms)", with the arrow leading to the boarding place. Flow picks the
  crossing that makes the whole trip shortest: from where you stand to the tower or dock, plus
  from where it lands to the nearest of those steps (Undercity for Silverpine, Grom'gol for
  Stranglethorn, the Ratchet boat when that's nearer). It's planned after what's left to do
  here; on a custom route whose quest line continues across the sea, it's the step you're
  led to. It works the same way coming back.
  - Horde: Orgrimmar to Undercity, Orgrimmar to Grom'gol. Alliance: Theramore and Auberdine to
    Menethil Harbor. Anyone: Ratchet to Booty Bay.
  - The boarding places are Classic's, so they may be a little off on WoW: Forever: the first
    time you cross near one, Flow corrects it from where you actually stood and landed.
  - Route includes has a tick, "Crossing to another continent"; `/flow crossings` lists them.
## 0.35.368

- **New: your gear sets as icons on your bags.** On top of the bag window, just left of the
  Flow Banker tab, there's now a small icon for each of the game's equipment sets (up to
  twelve), each with the set's own picture. Hover one for its name and how much of it you're
  wearing; click it to put the set on. The one you're wearing has a gold edge. Out of a fight
  only: in one the game swaps weapons at most, and Flow says so. Flow Settings, On your
  screen, "Gear set icons on your bags" turns them off.
## 0.35.367

- **Fixed: the arrow vanished after clicking a line in Flow Improvements.** In 0.35.358 that
  click made a custom route of the line's step. For "First Aid 141 of 150" that step has no
  place Flow can take you to, so the custom route was empty: no arrow, nothing in the Flow
  Tracker. Now:
  - a line is only added to your custom route when its step can be walked to from here; for
    one that can't, the click just opens the step, as it did before;
  - if a custom route ever has nothing you can do from where you are, your usual route shows
    again and the bar under the Flow Tracker says the custom route is waiting (click it to
    clear);
  - a profession step you picked is on the main arrow, not the faint profession one.
- **Fixed: Flow Improvements lost its link buttons while you were on a custom route** (Cure
  Poison and Aquatic Form had none). The steps a custom route sets aside can still be opened
  and added from there.
## 0.35.366

- **The Flow menu shows which section you're in.** Pointing at a folded section (Order, Route
  includes, Steps...) pops its entries out beside the menu, and the row's highlight went out
  the moment your mouse moved over to them. The row now stays lit, in orange, for as long as
  its pop-out is open, also after you set a tick in it.
## 0.35.365

- Fixes from the review of pull requests 23 to 28:
  - buying an item back from the vendor's own Buyback tab said "that item bought back"; it
    names the item now;
  - the world map's zone card shows fish names in your game's language where the game has them;
  - a paladin's own seal cast is noticed on this client too (it relied on a call WoW: Forever
    doesn't have).
- Known limit, not fixed here: the paladin's "seal by your talents" reads talents the classic
  way, which WoW: Forever doesn't offer, so on this client the automatic seal goes by your
  role (tank: Fury, otherwise Righteousness) until you pick one in Settings or with `/flow seal`.

## 0.35.364

- **Zone info when you hover the world map.** On the Kalimdor and Eastern Kingdoms maps, the zone
  under the cursor shows a small card in the map's top left corner: its name, level range (coloured against your
  level: red well above you, orange a little above, yellow your level, green easy, grey outgrown)
  and the fishing skill its waters need, in light blue ("130 (205)": some need more). With
  nothing hovered it shows the zone you're in, in the same corner. Settings "Zone info when hovering the world map" and "World map: your
  zone's info without hovering". Ranges from the Classic zones-by-level list; fishing from the
  Classic fishing tables. Hold Shift for the fish a zone's waters give and how often
  ("Raw Brilliant Smallfish 54%"), from Wowhead's Classic catch records; zones with few records say
  "few catches recorded", and zones with almost none (Burning Steppes, Un'Goro) show no list.
  (Thanks, YourBIMpossible: pull request 24.)

## 0.35.363

- **Paladin seal by your spec, your choice, or the fight.** Automatic now goes by your talents:
  Retribution Command, Protection (or tanking) Fury, Holy in a group Wisdom, otherwise
  Righteousness. Settings, Easy keys, "Paladin seal" picks one for this character (also
  `/flow seal command`, `/flow seal auto`). Cast a different seal and Flow keeps that one until
  the fight ends.
  (Thanks, YourBIMpossible: pull request 23.)

## 0.35.362

- **Flow no longer sells crafting materials to a vendor.** Cloth, ore, bars, stone, leather, herbs and every
  other trade good that none of your professions uses, or that your skill has moved past (Rough Stone for a
  Blacksmith past 120), now gets the auction house mark instead, on WoW: Forever too, where Flow has no auction
  prices to go on. The reason says why, with the price when Flow has seen one. One that keeps coming back unsold
  says so, and still isn't vendored.
- **Buying something back from the vendor's own Buyback tab now stops Flow selling it again.** Only Flow's own
  "Buy back" button used to remember, so an item bought back from the tab was sold again on the next visit.
  (Thanks, YourBIMpossible: pull request 28.)

## 0.35.361

- **Solo, quests you can't do yet wait off the route.** A quest in your log that's 3 or more
  levels above you is held (listed, locked, "at level 19") until you're within 2 levels of it,
  unless every mob it needs is near your level; an elite one until you're 3 levels above its
  mobs. In a group they're routed as before. Settings, Finding your way: "Hold hard and elite
  quests while solo".
  (Thanks, YourBIMpossible: pull request 26.)

## 0.35.360

- **The profession arrow sends you for the recipe before its materials**, and no longer to a
  trainer or vendor on another continent: a recipe you don't have yet gets no "gather for it"
  steps until you've learned it.
  (Thanks, YourBIMpossible: pull request 25.)

## 0.35.359

- **Pointing at a Flow Tracker row lights its step on the world map again.** It only did on a
  click. Also: two self-tests that failed on a character with Blacksmithing past Rough Stone, and
  on how the game hands back a texture's points.
  (Thanks, YourBIMpossible: pull request 27.)

## 0.35.358

- **A custom route is now the quest lines you pick, and nothing else.** "Go here next" on a
  step (or its ^ in the Flow Router) used to put that step first and leave the other hundred
  on the route. Now it picks the step's **quest line**: its quest, the quests you still have
  to do before it, and the quests that follow it, to the end of the chain. For a class quest
  that's the whole way to the spell ("Curing the Sick" becomes the line "Cure Poison"). Your
  route, the Flow Tracker and the Flow Router then show only that line's steps, in the best
  order; the next quest of the line is added as soon as you can pick it up.
- **Add more lines.** "Go here next" on another step adds its line, and so does the link
  button of a line in Flow Improvements (it also still opens the step). Two or three lines are
  planned together, by the shortest way through all of them. A trainer or a profession step
  can be picked the same way: a line of one.
- **Remove a step or a line.** Right-click a step of your custom route: "Remove this step
  and what follows it" ends its line before that quest (what comes before it stays);
  "Remove its whole quest line" takes the line out. A line whose quests are done leaves by
  itself, and when the last one is done the route goes back to Shortest or Most XP.
- **You can see you're on one, and leave with a click.** A bar under the Flow Tracker says
  "Custom route: Cure Poison + Aquatic Form" (hover for the lines); click it to clear. The Flow
  menu has "Clear your custom route" at the very top while you're on one. Picking Shortest or
  Most XP clears it too. `/flow focus` lists your lines.
- **The Warsong Reports and quests like it get a place.** Its three "updates" are handed over
  by people the quest data lists for the quest as a whole, not for each objective, so Flow
  said "doesn't know where: first you need Warsong Report". Flow now sends you to those spots
  when a quest's objectives have no place of their own. (It isn't a battleground quest, so
  the Battlegrounds tick doesn't hide it.)
## 0.35.357

- **New: Battlegrounds in Route includes.** Battleground quests sat among your ordinary
  quests: the ones in your log as steps Flow can't place ("from battlegrounds"), the ones to
  pick up as trips to a battlemaster. They're now a tick of their own, "Battlegrounds (their
  quests)", **off until you tick it**: unticked, they're left out of your route, the Flow
  Tracker and the lists; ticked, they're all there again. A quest counts as one when the quest
  data files it under Warsong Gulch, Arathi Basin, Alterac Valley or "Battlegrounds", or when
  the step asks for a Mark of Honor.
- Hover any quest step, a battleground's too, for the XP it gives at your level ("XP: about
  1010 (full XP)", or "40% XP: going grey"): that line was already there, and the tick's
  tooltip now says so.
## 0.35.356

- **Flow Meters count damage taken, interrupts and deaths.** Right-click the meters: the
  second list can now show them, from the game's own counts, like damage and healing.
- **New: Flow Deaths.** Who died, and for each death a play-by-play: what hit them, who did
  it, how much, and the health left, oldest first, the killing blow last. Above it, what
  killed them, how much they took and who healed them; and a graph of their health over those
  moments. Hover a point on the graph and its line lights up; hover a line and its point does.
  Open it with a left-click on the meters while they count Deaths, from their right-click
  menu, or `/flow deaths`.
  It shows the game's own record of each death (this game gives add-ons no combat log to make
  one from), so it holds what the game kept: whether heals are in it, and how far back it
  goes, is the game's choice. **Not yet seen with a real death**: `/flow deaths` and the
  diagnostics say what the game's record holds, so the first death will show what's there.
## 0.35.355

- The README now covers everything added since 0.35.321: the auto-attack badge, opening from
  stealth, combo points on the nameplate, the arrow's stacked words and alignment lines, trips
  Flow learns, quest items in your bags, "Keep set for", Flow Banker's To sell and Take out,
  Flow Trader, Flow Improvements in colour, the one-line tooltip, and the new commands.
## 0.35.354

- For the maintainer, nothing in the game changes: `tools\save-prices.ps1` saves the day's
  public auction prices for WoW: Forever (TradeSkillMaster's public data: the region and each
  ruleset's auction house) into a folder beside the repository, a day a folder, so a price
  history builds up. One fetch a file a day; `-Summary` says what's saved.
## 0.35.353

- **New: a Buy button for what your route sends you to the auction house for.** "The route is
  telling me to buy 8 Dig Rats at the auction house ... a button that would search for that
  item right away, since it's part of my current objective." Open the auction house with such
  a step on your route and Flow Trader opens with it at the top: "8 x Dig Rat for your route".
  **Buy** looks it up, then you confirm and pay, as for any deal. Flow buys the cheapest, no
  more than the step asks for, at up to three times the price it last saw.
- **New: Take out does a bank step.** "The route was taking me to the bank to get the Mild
  Spices out ... a button that takes those things I need out of my bank." What a step has you
  fetch ("Get from your bank: 5 Mild Spices", a recipe you can learn now) is in Flow Banker's
  Take out list, marked "your route", and at the bank the window opens on that list: one click
  on **Take out**. What a step takes out isn't offered back in.
- **A probe for "above or below you".** The game gives add-ons no height, and its minimap
  arrows have no call behind them. The one thing that could tell is the game's own marker in
  the world for a tracked spot; at a reload it never had a frame to measure. Flow now watches
  it while you play and logs what it answers (`/flow height`), so the next diagnostics show
  whether an up or down arrow is possible at all. Nothing is shown yet.
## 0.35.352

- **New: Flow Trader.** When Flow reads the auction house's listings (it does when you open
  it, at most every 15 minutes) it now looks at every one for a deal:
  - **vendor**: listed for less than a vendor pays. Buy it, sell it to any vendor: a certain
    gain, usually small.
  - **resell**: listed at half or less of what the item has usually gone for when Flow looked
    (the middle of its price history, from at least four visits). Buy it and post it again: a
    guess. The auction house's 5% is taken off the gain shown; the deposit isn't, and it may
    not sell.
  The Flow Trader window opens with what it found (a Flow Trader tab on the auction house
  opens it too), the most gain first, each with a button. **Buy** looks the item up again,
  **Confirm** and **Pay** buy it: every payment is your click, Flow pays no more than the
  limit, drops the trade if the price moved, and spends at most a quarter of your gold on one
  trade (`/flow trader share 10` for a tenth). Only things Flow wouldn't keep for you are
  offered; what you buy comes by mail, and the Flow Seller or Flow Auctions sell it on.
  `/flow trader`; Settings, Loot and selling, keeps the window from opening by itself.
  **Not yet tried at a real auction house**: the buttons use the game's purchase calls, and
  the log records each step, so the first trade will show whether this client takes them.
## 0.35.351

- **Fixed: Flow Banker still took quest things out of the bank and then wanted them back in**
  (Half Pendant of Aquatic Agility, Incantations from the Nether, Spells of Shadow). The cause:
  with the books in your bags their quest is finished and handed in across the sea, so they go
  to the bank; in the bank, the game calls the quest unfinished again, a "collect it" step
  comes back on this continent, and Flow asked for them back out. Three changes, so it can't
  come back another way:
  - **A thing in your bank is a thing you have.** A step that only fetches something lying in
    your bank no longer counts as a step.
  - **Parked means parked.** A thing banked for a quest across the sea stays "waiting",
    wherever it lies and whatever the quest log says meanwhile, until you're on the continent
    its quest goes on on, or the quest has left your log. Nothing else brings it out.
  - **One move, not two.** Whatever its reasons say, Flow doesn't offer to move a thing back
    the way it just came until you've changed continent or reloaded. Your own choice for a
    thing is never held back.
  If where you are isn't known (a loading screen), nothing is moved for a quest either way.
  `/flow banker` lists what's parked and what Flow moved this session.
## 0.35.350

- **New: Flow learns how long your trips take, and plans your route by it.** Until now the
  route was ordered by the straight line between steps (or a flight, a gate, a travel spell
  where Flow knew one), so a cliff, a river or a winding road between two steps didn't count.
  Now every trip from one step to the next is timed: the seconds you were travelling (not
  fighting, not standing still), and whether you ran, rode or flew. Flow keeps your quickest
  for each pair of places, and the route uses it:
  - a trip you've made before costs what it took you;
  - a trip between two neighbourhoods you've crossed before is the straight line, stretched
    by how much longer such trips took;
  - anywhere else, the straight line, as before.
  A trip with a hearthstone, a teleport, a death or a long wander in it isn't kept.
  `/flow legs` shows what it has learned; Settings, Finding your way: "Learn how long my
  trips take, and plan by it". Nothing leaves your computer.
- [docs/FLOW-GRAPH.md](docs/FLOW-GRAPH.md): the plan for sharing those trips between players
  and for one optimised order through every quest in the game. A plan only: it lists what has
  to be decided before anything is uploaded anywhere.
## 0.35.349

- **The "Keep set for" ticks moved under your bags**, right below the money line. They were
  above the top edge, where the Flow Banker tab stands.
## 0.35.348

- **Fixed: Flow Banker took things out of the bank, then wanted to put the same things back.**
  Two causes, both from 0.35.344:
  - it took a quest's things out for any quest in your log, even one Flow can't lead you
    through (32 Raw Brilliant Smallfish for Stalk With The Earthmother), and then banked them
    again as a material you keep. Now a thing comes out for a quest only when Flow can lead
    you through that quest here, and the same list keeps it out of "To bank";
  - a thing banked because its quest goes on across the sea stopped counting as "waiting"
    once it had left your bags, so it was offered straight back out.
  What Flow keeps for later stays in the bank. Only what sells or auctions, or what a quest
  here can use now, comes out. `/flow banker` has a line that must read "taken out and put
  back: none".
- **To sell's bottom-left button is now "Reset to Flow's"**: it drops every sell or keep
  choice of yours (and buy-backs) at once, so Flow decides what sells again. "All my choices"
  there showed a list that read as "keep everything". One line is still flipped with a click
  and reset with a right-click.
- A self-test about the Flow Tracker failed whenever the tracker had a row when it ran; it
  expected pointing at a row to light the world map, which a click does.
## 0.35.347

- **Fewer Flow lines on a tooltip.** Hovering a quest item in a Flow Banker cell showed eight
  of them, most saying the same thing twice. Now:
  - **An item in your bags gets one Flow line**: what Flow does with it, whether it goes to
    your bank, and the reason that matters: "Flow: Keep, to your bank at the next visit: for
    your quest: The Power to Destroy...". (It was three lines; "vendors won't buy it; quest
    item" is left out when there's a real reason beside it.)
  - **A Flow Banker cell adds three lines**, not five, and leaves the item's own Flow line
    out: where it goes and why, why Flow keeps it, and the clicks.
## 0.35.346

- **New: Flow Improvements colours each line by how pressing it is.**
  - **White**: worth doing, nothing is lost by waiting.
  - **Yellow**: close to a limit, or important. A profession within 15 points of its cap that
    you can already train further ("Cooking 62 of 75: you can learn Journeyman Cooking now"),
    nearly full bags, training and upgrades.
  - **Red**: you're losing something until it's done. A profession **at its cap** ("Herbalism
    is capped at 75: learn Journeyman Herbalism"): every skill-up since is lost. Full bags
    with quest items to hand in: loot is being lost.
  The same colours are in the tooltip of the Flow Improvements button, and a line's own
  tooltip says what its colour means.
## 0.35.345

- **Fixed: a thing you clicked in Flow Banker's To sell disappeared, with no way back from
  there.** A click told Flow to keep it, and it left the list. Now it stays in To sell, marked
  "Kept: ... (your choice)", and the list works like To bank:
  - **click** a line to flip it: a thing that sells is kept, a kept thing sells;
  - **right-click** for Flow's own choice again;
  - **All my choices** (bottom left) lists every sell or keep choice you've made, also for
    things you don't carry now, to flip or reset the same way.
  Things you once bought back from a vendor are listed there too ("Kept: ... (you bought it
  back)"). The things you clicked before are back in the list as Kept.
## 0.35.344

"20 items in my bags are quest items, I can't carry anything." Looking at those bags: 11 of
the slots belonged to quests that were already finished, and two of those hand-ins weren't on
the route at all; 4 were for quests that go on across the sea; 3 were leftovers.

- **Fixed: a finished quest's hand-in could be missing from your route.** The route is planned
  from the 30 nearest steps, and with many quests to pick up nearby, a hand-in further off (two
  finished quests in Ratchet, 4 bag slots) never made it. While your bags are nearly full (4
  slots free or fewer), the hand-in of any finished quest whose items you carry now always
  stays on the route, comes early, and says what it gives back: "Turn in: Chen's Empty Keg
  (frees 3 bag slots)".
- **New: quest things you can't use here go to the bank.** Flow Banker now puts away the items
  of a quest whose next step is on another continent, and leftovers that wait for a quest you
  don't have yet. When a quest here can use one again, To sell lists it ("In your bank: ...
  (your quest: ...)") and Take out brings it back; the route's bank step counts it.
- **Fixed: Flow Banker wanted to bank what a quest in your log asks for** when it wasn't a
  "quest item" by kind (14 Earthroot for Gathering the Cure, the day before the hand-in).
- **A leftover whose quest is 15 or more levels away is sold**, when a vendor buys it (2 Small
  Furry Paws for a level 60 quest).
- **New: `/flow questbags`**: every quest thing in your bags and what clears it: hand in
  (finished), sell, bank, finish (in progress here), or "Flow can't place it". Flow
  Improvements says the first thing to do while your bags are nearly full.
## 0.35.343

- **New: your own "sell it" or "keep it" for any item**, the way you already choose "bank it".
  In Flow Banker:
  - **To bank** (the things Flow keeps): **Shift-click** one to sell it. The Flow Seller takes
    it at the next vendor, whatever Flow's rules say ("you chose to sell it").
  - **To sell**: **click** a line to keep that thing instead ("you chose to keep it"). A line
    that's there by your own choice is marked "Your choice:"; a click on it, or a right-click
    on any line, goes back to Flow's choice.
  - A thing you chose to keep (or once bought back) is undone with **Alt-click** in To bank.
  Tooltips say which clicks do what. Per character; `/flow banker` lists your choices. A thing
  vendors won't buy can't be chosen to sell.
## 0.35.342

- **New: "Keep set for" ticks at the top of your bags**, one for each of your specs (a druid:
  Feral (Cat), Restoration, Feral (Bear)). Ticked, Flow keeps gear that's better for that spec
  and what's in its set, as before. **Unticked, that gear is no longer kept**: it's sold,
  auctioned or disenchanted like anything else you don't need, unless a ticked spec wants it.
  The spec you level as is always kept. The keep reason now names the spec ("better for
  Feral (Bear)", "in your Restoration set"). Per character.
- **New: Build sets.** The button at the end of that row makes the game's own equipment sets
  (character window, Equipment Manager) for the ticked specs, named after the spec; ticking a
  spec that has no set builds it too. The game only saves a set from what you're wearing, so
  for a spec you aren't wearing Flow puts on what's better for it from your bags, saves the
  set, and puts your own gear back on (a few seconds, out of a fight only). `/flow keepsets`
  says how it stands; Settings, Loot and selling, hides the row.
## 0.35.341

- **New: "To sell" in Flow Banker**, beside To bank, In your bank and Auction prices. It lists
  what the Flow Seller takes at the next vendor or auction house, each with where it goes and
  why ("40 x Linen Cloth (vendor: your First Aid is past it)").
- **New: things in your bank that Flow would now sell come back out.** "Linen Cloth says
  sell, your First Aid is past it, but it doesn't take it back out of my bank." To sell lists
  those too, marked "In your bank"; at a bank, **Take out** brings them to your bags (as many
  stacks as you have room for) and the Flow Seller sells them at the next vendor or auction
  house. The route's bank step says so: "Bank: put 4 stack(s) away, take 2 thing(s) out to
  sell". Gear and quest items are never taken out, nor anything you chose to bank yourself.
- **Why Flow keeps a thing**: in To bank, a thing's tooltip now gives Flow's reason ("Flow
  keeps it: for First Aid: Wool Bandage"), not only whether it goes to the bank.
- **A bought-back item isn't kept forever any more.** "It says you bought it back before, so
  now Flow thinks I want to keep it forever, and that's not true." Alt-click it in To bank
  and Flow goes by its usual rules for it again (its tooltip says so). `/flow banker` lists
  what's on that list.
## 0.35.340

- **New: a quest's materials can be bought at the auction house.** "Gathering the Cure has me
  collect 5 Earthroot. Can't I just buy those?" When a quest asks you to collect something
  Flow has seen for sale at the auction house, buying it is a step too: "Buy 5 Earthroot at
  the auction house (about 6s): Gathering the Cure", at an auctioneer, once you can pay. It's
  optional, so it's on your route only while an auctioneer is close to your way (you're going
  for wool anyway). Whichever you reach first settles it: buy them and the collecting step
  goes; collect them and the buying step goes. The collecting step's details name the price
  as well. Settings, Finding your way: "Offer the auction house for a quest's materials".
- **Fixed: what a quest in your log asks for is kept from the first moment.** Flow keeps
  such items ("for your quest: Gathering the Cure"), but its list was only filled once a
  search through the upcoming quests had finished: a moment after login, and longer in a
  fight. Until then nothing was held back for a quest. Now your log's items count at once.
- The log names which of your own items a sale at a vendor sold (it only had how many), so
  "it keeps getting sold" can be checked after a reload.

## 0.35.339

- **Fixed: clicking the auto-attack badge beside the target button didn't turn auto attack
  off.** The badge listened for the release of the mouse button, and with the game set to act
  on the press ("cast on key down") a click that way does nothing. It now listens for the half
  of the click your game acts on. Turned off, auto attack stays off until you attack again:
  your next attack on the target key starts your swings, as every attack does.

## 0.35.338

- **The auto-attack badge shows the game's own Attack picture for your shape.** In Cat Form it
  showed Claw's picture, which is the very picture on the target button, so it looked like a
  second copy of that button. It now shows what the Attack button on your action bar shows:
  your weapon as yourself, the cat's or the bear's own attack in a form.

## 0.35.337

- **The auto-attack badge glows on the inside while auto attack is on**, the way the game's own
  buttons do when they're switched on: a yellow glow from the border inward that fades toward
  the middle (the game's own highlight, the one on the action bar's Attack button). The orange
  ring round the outside from 0.35.335 is gone.

## 0.35.336

- **Fixed: the freeze a few seconds after every login or /reload.** It was Flow checking itself:
  all of its self-tests (some 550) ran in one frame, 8 seconds after login, and the game stood
  still for over a second while they did. They now run a few milliseconds a frame, spread over
  a few seconds, with the same results. In a fight they wait.
- Flow now notes any frame that takes far too long in the first 40 seconds after login, and
  when it happened, so what's left of a hitch (Flow's or not) can be found.

## 0.35.335

- **Druid: Prowl is suggested before a pull.** In Cat Form, out of a fight, with an enemy
  targeted and you not prowling yet, the self button offers Prowl. Once you prowl, the target
  key holds your opener from stealth (Ravage, Pounce or Shred when you have them; Rake before
  that), and moves to your cat rotation when you hit. It isn't suggested with nothing targeted:
  prowling slows you, so it shouldn't be asked for while you travel.
- **The auto-attack badge pulses while auto attack is on.** The soft glow added in 0.35.327
  didn't show. The badge now has a ring that pulses on the same beat and in the same orange as
  Flow's other "this is live" marks; the weapon-coloured edge stays inside it.

## 0.35.334

- **Combo points on the nameplate are a bar in sections now, like the game's own bars.** In
  place of the separate squares: one bar right under your target's health bar (under its power
  bar when the nameplate shows one), as wide as that bar, with the game's bar texture and a dark
  edge, cut into five sections. It fills a section for each combo point, in the game's own combo
  point colour.

## 0.35.333

- **Your combo points on your target's nameplate.** A row of small pips under the nameplate of
  the enemy you have targeted, one for each combo point you can hold: the ones you have are
  lit gold, and all of them turn red when you're full. For a rogue, and for a druid in Cat
  Form. With no points yet the empty pips still show. It's on from the start; off in Flow
  Settings (On your screen) or with `/flow combo off`. The game needs enemy nameplates on for
  there to be one to draw under (the V key by default).

## 0.35.332

- **A quest item with nothing to click no longer gets a button.** On "The Stagnant Oasis" the
  Flow Tracker showed the Dried Seeds as a button, and clicking it did nothing: the seeds are
  used by clicking the fissure in the water, not the item. Flow showed whatever the game calls
  the quest's item; it now shows it only when the item has a use of its own (a horn you blow,
  a sampler you fill). The same goes for the target key's "use your quest item". `/flow
  questitems` says which quest items have no button, and why.

## 0.35.331

- **"Show on map" for a step in another zone: click it again and the map zooms out to where
  the step shows.** The first click opens the game's map, which always opens on the zone
  you're in. With the mouse still on the link, a second click now goes to the map's own bar of
  parent maps (World > Kalimdor > The Barrens) and the game turns its map to the nearest one
  both zones are on, usually the continent, where the step's dot is drawn. One more click on
  the zone, the game's own, and you're there. Flow still doesn't turn the map itself: that is
  what breaks the map's buttons in a later fight. With the map already open, the first click
  does it.
- **"Select in quest log": the second click is ready at once.** The first click opens the log
  with the quest selected; the next click on the same link opens the quest itself. You no
  longer have to move the mouse off the link and back for that. A small note says so.

## 0.35.330

- **Fixed: the alignment lines when you move Flow's buttons were wrong, and didn't say what
  they lined up with.** With the two buttons docked, the one you dragged was compared with its
  own docked partner, which moves with it: so a line always ran through the pair wherever it
  was, and it never settled on the middle of the screen. It was also compared with the edges
  of the arrow's frame, a box you can't see. Now the lines only use what's on screen and stays
  put: the middle of the screen, Flow's other button when the two aren't docked, and the middle
  of the arrow. A line to the middle of the screen runs right across; a line to another thing
  runs just from the button to that thing, and that thing is outlined in white while the line
  shows.

## 0.35.329

- **The route plans a visit to each group of a quest's mobs, not one spot a quest.** A kill or
  collect step used to count as a single stop at whichever of its spots was nearest. Ten boars
  aren't at one spot, so such a step is now planned as up to three visits, one to each of its
  nearest groups of spots, as many as what's left to get is likely to need (about four a
  group). Each visit is ordered like any step, so another quest's group or errand that lies
  between two of them comes in between, and the turn-in waits for the last visit. The step is
  still one line on your route; the arrow leads from group to group in the planned order. Flow
  can't see what's alive, so how many a group yields is a guess, and the plan is made again as
  you go. Off: Flow Settings, Finding your way.

## 0.35.328

- **Flight masters on the map: one pick, and point at a line for its flight.** Click a flight
  master and its lines go out, bolder than before: green where you can fly, red where you
  can't yet. Move the mouse onto a line, or just near it, and that line is drawn bolder still
  with the flight's time at its middle ("Crossroads to Camp Taurajo: about 1 min 20 s"), or
  what's missing. The next click, on any flight master or anywhere on the map, clears the
  lines. Picking a second flight master is gone: pointing does its job.
- **Right-click a flight master again to take the waypoint off.** A right click points Flow's
  arrow there, as before; a right click on the same one now removes that waypoint, and its
  tooltip says which of the two a right click will do.

## 0.35.327

- **Alignment lines while you move Flow's buttons.** Ctrl + drag the target button or the self
  button: when its edge or middle comes level with the middle of the screen, or with the edge or
  middle of Flow's other button or the arrow, a line shows there. Let go while a line shows and
  the button settles exactly on it: middle to middle, its top on the other's bottom, edge to
  edge. (The snap happens when you let go: the game doesn't let a frame be nudged while it's
  being dragged.) Off: Flow Settings, On your screen.
- **Druid: prowling, the key no longer says "Attack".** With an enemy targeted the key offered
  auto attack, which makes you swing the moment you're in reach and throws the opener away. The
  opener (or Rake, or Claw) starts your swings by itself, as every attack does, and does so
  again each time you attack after turning them off.
- **The auto-attack badge shows what you hit with, and glows softly when on.** A claw in Cat
  Form, a paw in Bear Form, your weapon otherwise; its edge is the colour of the weapon in your
  main hand. While auto attack is on, a faint glow breathes round it instead of the whole badge
  blinking. Click it to turn auto attack off or on, as before.

## 0.35.326

- **Druid: prowling, your key is your opener; the moment you attack it's your cat rotation.**
  In Cat Form with Prowl up, the target key holds the best opener you know (Ravage, then
  Pounce, then Shred; before those, Rake). When stealth breaks, the game itself moves the key to
  Claw and your other presses to their Cat Form spells, in the middle of the fight, the same
  way the key already follows a change of form. Ravage and Shred only land from behind the mob;
  the icon's reason says so. `/flow key test` lists what the key holds while stealthed.

## 0.35.325

- **From group to group in a quest's area.** A kill or collect step took you to the nearest of
  its spots, became a ring ("You're in the area"), and stopped there. Now the ring's line says
  how far the next group of spots is, and when you walk out of a group, or stand in one for 20
  seconds with no fight and nothing looted, the arrow points to the nearest group you haven't
  just worked: "Next group: 140 yd (Deviate Hides)". The next group can belong to another kill
  or collect step near the front of your route, so you work through several quests' mobs on
  the way instead of finishing one and walking back. A worked group rests for five minutes.
  Flow can't see what's alive, so a group may be empty when you arrive; standing there a moment
  sends you on. Off: Flow Settings, Finding your way. `/flow hop` lists the groups.

## 0.35.324

- **The target and self buttons' small icons run toward the side of the screen the button is
  on.** In the left half of the screen they go off to the left, as before; move a button into
  the right half and they go off to the right instead, biggest nearest, bottoms level with the
  button. Each button goes by where it is; docked, the two swap together as one mirrored block.
  What sat on the other side (the key's name when docked, the auto-attack badge) swaps over, so
  nothing lies under the icons.

## 0.35.323

- **The arrow's lines of text are stacked by length, like a triangle pointing at the arrow.**
  The step's name, the distance line, the profession arrow's line and the party and dungeon
  lines all sit on one side of the arrow now, the shortest next to it and the longest furthest
  away. With the arrow in the top half of your screen they're above it; in the bottom half
  they're below it. If the arrow sits so close to the top edge that the lines wouldn't fit above
  it, they go below instead, so nothing runs off the screen: drag the arrow down a little
  (Ctrl + drag) to get them above.

## 0.35.322

- Fixed: quest rewards got neither the green arrow nor the gold coin when one choice was an
  upgrade for another spec only. "The Disruption Ends" offers a Binding Girdle (better for
  healing, not for the cat you level as) and a mail Cinch Belt you can't wear that sells for
  more: the coin waited for nothing to be better for ANY spec, and the arrow is only for the
  spec you level as. The coin now goes on the one that sells for most whenever nothing is an
  upgrade for the spec you level as; the spec marks still show the girdle's healing arrow.
- **Click flight masters on the map.** Click one and lines go to every other flight master
  on the map: green where you can fly (you have both flight paths), red where you can't yet.
  Click another and the line between them is drawn bold, with the flight's time at its middle
  (your last flight of it, or Flow's estimate: "Crossroads to Camp Taurajo: about 1 min 20 s"),
  or what's missing ("learn the flight path at Bragok first"). Click a third and it takes the
  second's place; click one of the two again, or anywhere on the map off them, to clear. A
  flight master's tooltip says the flight from the one you picked. Right-click one to point
  Flow's arrow there (a left click did that before, which is why a "selection" seemed to stick:
  it was your next step's flight).

## 0.35.321

- **Leaving junk behind: a skinner is told, instead of Flow working round it.** 0.35.320 took
  the junk from beasts so they could be skinned; that's gone. A corpse can only be skinned once
  nothing is left on it, so now Flow just says so: turn "Leave junk behind when looting" on
  while you have Skinning and a line in chat tells you, with how to turn it off (`/flow loot
  junk`); if it was already on, you're told once. The setting's tooltip says it too. The note
  by your cursor and the corpse that stays open the second time stay as they were.

## 0.35.320

- Fixed: with "Leave junk behind when looting" on, a corpse you'd looted opened and shut at
  once, every time. Flow takes everything but grey items and closes the window when only junk
  is left; the junk keeps the corpse sparkling, so you open it again, and Flow shut it again
  before you could take anything. Now it closes the window only the first time it looks at a
  corpse: open it again and the window stays, to take what you like by hand. When it closes, a
  short note by your cursor says why: "Flow left the junk: Thin Black Claw (open it again to
  take it)"; the first time in a session, a line in chat too. An item whose quality the game
  hides is taken, never left as junk. Each corpse's take is in the diagnostics' log.
- **Corpses you'll skin are emptied, junk and all.** A corpse can only be skinned once nothing is
  left on it, so leaving the junk kept you from skinning. From a beast or a dragonkin while you
  have Skinning, Flow now takes the junk too; the Flow Seller sells grey items at your next
  vendor. Junk is still left on mobs you don't skin.

## 0.35.319

- **Mobs your professions want are marked.** The route's "Loot Kodo Meat" and "Loot Strider
  Meat" steps are along the way, never a stop of their own, and nothing marked their mobs, so
  it was easy to walk past them. Now each mob that drops it has that profession's icon over its
  nameplate (Cooking's for meat) with your count ("0/8"), beside any quest marks, and its
  tooltip says "Flow: loot Kodo Meat for Cooking, 0 -> 8". The count follows as you loot.
- **Which spells take you out of a form** (druid). The game doesn't say it of a spell, so Flow
  watches your casts: cast a spell in Bear or Cat Form and Flow notes whether you stayed in it or
  were shifted out. The spell's tooltip, on your bars and in the spellbook, then says "Flow:
  takes you out of Bear Form" or "Flow: keeps you in Bear Form and Cat Form"; one Flow hasn't
  seen cast in a form says so. A form's own abilities (Maul, Claw...) say so from the start.
  `/flow forms` lists everything seen. Kept for your account, so your other druids know it too.

## 0.35.318

- **Loot rolls show their marks on the item.** The green upgrade arrow was drawn under the
  item's picture on the roll window, so it never showed. Now Flow's marks sit on top of the
  picture, as in your bags: the big green arrow and how much better for an upgrade; otherwise
  what Flow would do with it (the gold coin to vendor it, the auctioneer's mark, DE to
  disenchant); and the spec marks along the bottom (up, down or the same, per spec). The line
  above says it too: "Flow: not an upgrade: Greed, then vendor it". An item that binds when
  picked up never gets the auction mark. The diagnostics' log says which part of the roll
  window the marks went on.
- **The target button blinks red while Maul waits for your next swing**, as the game's action
  bar does: the same red, on the bar's beat. When the button shows another spell, Maul's own
  small picture blinks at its top right. (Other classes' swing spells are one line in their
  class files.)
- Fixed: a self-test from 0.35.316 expected "18.5k XP" where Flow rounds to "19k".

## 0.35.317

- **Bag icons: what Flow will do top left, what the item is top right.** The auctioneer's mark,
  the gold coin (sell) and DE (disenchant) move to the top left, with the (o) for your step's
  item and the bank icon: everything about what happens to the item is in one corner. The top
  right is for what it is: a quest item's "!", a profession's icon for its materials and tools.
  Each corner shows one mark. (For add-on authors: every mark is now a `bagMark` registration
  whose group, "action" or "kind", decides its corner; docs/ARCHITECTURE.md.)

## 0.35.316

- **You pick your questing zones; Flow no longer picks for you.** Until now every zone was on
  the route unless you unticked it, so quests to pick up anywhere around your level pulled you
  into zones you hadn't chosen. Now the route takes quests only in the zones you've ticked in
  the Flow Router (Route, Zones). Your first zones are the one you're in and those where the
  quests in your log are (a zone you'd unticked before stays out). Kept per character: an alt
  has its own. A trainer, vendor or flight master is still wherever it is.
- **The Zones list shows every option, with what it holds.** Your zones first, then the zones
  with quests for your level, each with its levels and how many steps or quests to pick up. A few
  are marked "suggested". Hover a zone for: your steps there, quests to pick up and about how much
  XP, where the quest givers stand (all in one place, or in how many), how far apart the quests'
  mobs are ("about 30 yd apart, close together"), mob levels, elite quests, class quests there,
  and what you could gather. The separate "Where next" lines are gone from the menu (it's all on
  the rows now); `/flow where` still lists them in chat.
- **A note when you're in a zone you haven't picked.** A bar at the top of the screen, its edge
  pulsing orange for a few seconds: "You're in Stonetalon Mountains: not one of your questing
  zones", what it holds, and **Quest here** (one click: it becomes one of your zones) or **Not
  now** (until you leave and come back). Not on a flight, in a dungeon or in a fight; Ctrl-drag
  moves it. Off: "Say when you're in a zone you haven't picked" in Flow Settings (Finding your
  way). The Zones list also has "Quest in the zone you're in".

## 0.35.315

- **The Flow Seller sells your junk first, really.** Flow used to ask the game to sell
  everything in the same instant, and the game didn't always finish them in that order: some
  junk went last and pushed your own items out of the vendor's buyback tab, so "Buy back"
  offered items that were gone. Now each item is sold and Flow waits until it has left your
  bags before the next: all the junk, then the rest, so your own items are the last 12 sold.
  The Sell button says "Selling... 5 left" meanwhile. The "Buy back" list shows only what the
  vendor's buyback tab still holds. Bags are tidied and gear repaired once the selling is done.
- **Ctrl moves the target and self buttons again**, more reliably: Flow now watches Ctrl
  itself as well as waiting for the game to say a key changed, and one button's handle can no
  longer keep the other's from showing. Docked, Ctrl-dragging the self button moves the pair
  (it used to do nothing). If it still won't move, Flow's diagnostics now say what lay under
  your mouse when you pressed Ctrl.
- **The Flow Router button points the game's way.** Its arrow now matches the quest log button
  beside it: right while the list is closed, left while it's open. The button shows a little
  route list in the route's colour. A click opens the list even if drawing the route on the
  map runs into trouble (that's noted for the diagnostics).
- Fixed: two spots where Flow read a value the game hides (a loot name, and a check of what
  lies over the self button that ran every half minute) and was logged as tainting the game's
  own windows. The check over every frame now only runs when you ask: `/flow selfbutton why`.
- Fixed: the self-test for the docked self button expected it at the target button's size; it
  has had a size of its own since 0.35.253.

## 0.35.314

- **Flight masters on the world map.** A new Flow button on the world map, above the route
  on/off button, shows them (click again to hide them; it's off until you click it):
  green rings for the flight paths you have, light blue rings for the flight masters whose path
  you don't have yet (free: talk to them once; the same colour as the route's "Learn the flight
  path" steps), and, in the route's colour joined by a line, the flight your next step is
  quicker by ("Fly from here", "Land here: next step"). Hover one for the flight master's name
  and what it's for; click it to point Flow's arrow there. Also "Flight masters on the world
  map" in Flow Settings (Finding your way). Flight masters you don't have yet are shown for the
  continent you're on.

## 0.35.313

- Fixed: two of Flow's self-tests failed at login after 0.35.311 (the red line in chat). The
  Zones section's quick choices are now **Select all zones** and **Select no zones** (Route
  includes already had a "Select all", and no entry may be in the Flow menu twice), and a test
  no longer trips over the line above them.

## 0.35.312

- **Your next step's flight master is ringed on the flight map.** Open a flight map and the
  flight master that lands you nearest your next step (the one the arrow points at) gets a
  slowly turning ring of dots in the route's colour, with the step's name under it ("Flow: Turn
  in: The Ashenvale Hunt"). Nothing is ringed when the step is about as quick to walk to from
  the flight master you're standing at. The ring takes no clicks: click the flight master as
  always. Off: "Ring your next step's flight master on the flight map" in Flow Settings
  (Finding your way).

## 0.35.311

- **Finish the zones you pick first.** In the Flow menu, Order's "Finish the area you're in
  first" is now **"Finish the selected zones first"**: tick the zones you want under Zones, and
  the route does their quests first and the other zones' after them (nothing is left out). The
  Flow Tracker says "Finishing The Barrens and Stonetalon Mountains first", and a waiting step
  says "(Ashenvale, after your zones)". Off (as before): an unticked zone is left out of the
  route. Also in Flow Settings (Finding your way). The 300-yard "Finish the area you're in
  first" is still there, in Flow Settings.
- **Under the zones, a line and three quick choices:** Select all zones, Select no zones and Current zone
  only, to start a choice and then tick the zones you want. `/flow zones all | none | here`,
  and `/flow zones first` turns the option on or off.

## 0.35.310

- **Spell levels come from your trainer, not from Classic's list.** Flow read your class
  trainer at every visit and kept what it said, but used it only to drop spells a trainer
  doesn't have. Its levels still came from Classic, so it said "Rake: after Cat Form" at level
  20 when WoW: Forever's trainer teaches Rake at 24 (Claw at 28, Prowl at 40, Shred at 20). Now
  the level a trainer first lists a spell you don't have puts Flow's list right, at once and
  from what Flow already saw. `/flow facts` shows what was put right.
- **A class quest's steps say which spell they're for:** "Turn in: The Principal Source (for
  Cure Poison)". On WoW: Forever some spells come from a class quest instead of the trainer
  (Cure Poison, Cat Form), and the route only showed the quest's name.
- Shared facts (`/flow places share`, `tools/share-facts.ps1`) carry these first levels too, so
  one player's trainer visit puts the levels right for everyone.

## 0.35.309

- **Locked steps say more in their row.** A step across the sea names the zone: "in Silverpine
  Forest", and the steps waiting on it "after Silverpine Forest" (they said "overseas" and
  "waits for a step overseas"). A quest step Flow can't place because it needs something first
  that nobody knows the place of now says what: "needs Raw Brilliant Smallfish" (Stalk With The
  Earthmother) or "needs 4 things first" (Traditions of the Bluff, with the four listed on its
  card), instead of "no known spot".

## 0.35.308

- **`/flow audioreset` brings WoW's sound back.** When your speakers go away and come back (a
  monitor's speakers vanish while the screen sleeps, or while you're on Remote Desktop), WoW
  sometimes stops its sound to follow them and never starts it again: the game is silent while
  everything else plays, and its Audio settings show only "System Default". The command
  restarts the game's sound without restarting the game.
- **Flow does it by itself, too:** a few seconds after the game says your speakers changed,
  Flow restarts the game's sound once things settle. The sound may cut out for a moment. Off:
  "Restart WoW's sound when your speakers change" in Flow Settings (More).

## 0.35.307

- **Money reads at a glance, the same everywhere.** A step held back for money said "needs
  13552c". Every price Flow shows is now about three figures in its biggest coin: 52c, 5.52s,
  69.6s, 1.36g, 13.6g, 124g. That's the route ("needs 1.36g"), the Flow Seller, repairs, the
  trainer list, mount savings, auction prices, Flow Prices and the Flow Banker. (Most of these
  showed plain copper before: the game's coin text isn't there in WoW: Forever.) Prices are
  rounded to the nearest, and a price typed for `/flow ah watch` still reads "1.36g".

## 0.35.306

- **"Show on map" and a step in another zone: finding out what the game allows.** Flow still
  can't turn the game's map to the step's zone itself (an add-on doing that breaks the map's own
  buttons in a later fight). It could pass your click to one of the game's own controls that
  does, if WoW: Forever has one. `/flow buttons` (and the diagnostics) now list the map's
  controls for other zones, and say what the map did after the last click Flow passed to a
  quest's line in the log. Nothing changes on screen yet.

## 0.35.305

- **The ring of dots on the minimap is turned 22.5 degrees.** A dot sat straight above and
  straight below your next step's spot, over the game's little up and down arrows. Two dots now
  flank the top and two the bottom, and the arrow shows in the gap between them.

## 0.35.304

- **Bag items for the auction house show the auctioneer's mark** instead of the letters "AH".
  (A game without that picture keeps the letters.)
- Fixed: the arrow's long second line still sat under the step's name. The change in 0.35.302
  never took effect (Flow's own self-test said so at login); it does now.

## 0.35.303

- **Flow's menus widen for long lines.** The dungeon run's details (click the line under the
  arrow) ended in "..." ("You're missing 1 quest (to pick up..."). Every Flow menu is now as
  wide as its longest line needs, up to about two and a half times the old width. A line longer
  than that still ends in "...", and pointing at it shows all of it.
- For an up/down mark on the arrow: `/flow api` (and the diagnostics) now say whether this game
  has its own marker in the world for a tracked spot, which is the one thing that could tell
  above from below. Nothing is shown on the arrow yet.

## 0.35.302

- **The arrow's long line sits above the arrow.** A line such as "2166 yd (to the flight
  master: fly Thunder Bluff, Mulgore to Crossroads...). Hearthstone is about 3 min quicker" ran
  across half the screen under the step's name. Long lines are now above the arrow, wrapped; a
  short one ("184 yd ~40s") stays where it was.
- **The teleport or hearthstone picture by the arrow no longer looks like a button.** It's
  round, smaller and a little see-through, like a mark on a map. Clicking it still opens the
  arrow's details, as clicking the arrow does; your Flow key is what casts it.
- **Recipes say what to do with them.** A pattern or recipe for a profession you don't have:
  the auction house when it's worth it there, otherwise a vendor. For one of your professions:
  learn it now, keep it until your skill reaches what it asks, or let it go when you already
  know it.
- **A quest item's tooltip names the quest in your log it's for**, so you can see which quest
  to finish to get it out of your bags. `/flow leftovers` lists them all.

## 0.35.301

- **Flow Prices: an item's auction price over time, as a chart.** Alt + click an item (bags, a
  chat link, the auction house), click a line in Flow Banker's "Auction prices", or type
  `/flow price <item>`. The chart shows the cheapest buyout (each) Flow saw at each visit to the
  auction house, with time to scale: two scans an hour apart sit close together, a week without
  one is a long stretch. Hover a dot for its price and when. Above it: the price now, the
  lowest, highest and average, and how it moved from the first look to the last.
- Flow now keeps up to 48 points of history an item (it kept the last 8 looks); the looks it
  already had start the chart. A long history thins at its far end instead of losing it.
- The Alt + click can be turned off in Flow Settings, under "Loot and selling".

## 0.35.300

- **A bank icon on what goes into your bank.** Items in your bags that Flow Banker will put
  away at your next bank visit now show a small bank icon in the top left corner, and their
  tooltip says so. It's the same list the Deposit button uses, so a choice you make in the
  Flow Banker (carry this, bank that) changes the icons too.

## 0.35.299

- **"Steps on the map" is now just "Steps"**, in the arrow's menu and in Flow Settings. It
  chooses the same thing as before: how many steps the world map and the Flow Tracker show.

## 0.35.298
- **Where next.** `/flow where` lists the zones with the most to do at your level: for each,
  how many quests you could pick up there (that you haven't done, for your race and class,
  around your level), their levels and about how much XP they'd give you, how many are class
  quests, what you could gather there with your profession (or the skill its herbs ask for),
  and whether it's on another continent. Most XP first. The top five also show in the Flow
  menu's Zones section, under the zones your route already covers. It doesn't choose for you,
  and it doesn't know how close together a zone's quests lie or how long the trip takes.

## 0.35.297
- **Cat Form's quest is found in the quest data, and so is Cure Poison's.** For a spell your
  trainer doesn't have, Flow now takes the class quest chain that starts at that spell's level
  from the quest data and treats it as the spell's class quest: its step is always on your
  route, the spells that wait for it (Rake, Claw, Prowl, Shred) link to it, and Flow
  Improvements says where you are in it ("Get Cat Form (level 20, class quest: "The Great
  Cat Spirit" is in your log)"). A form ranks above ordinary training there.
- A self-test put right after the tooltip's new mob lines.

## 0.35.296
- **A spell your trainer doesn't have points at your class's quests.** Flow said "Rake: after
  Cat Form" and nothing about getting Cat Form: its list had Cat Form at the trainer, and on
  this game the trainer doesn't have it. Flow now looks through the quest data for the quests
  that are only for your class, and when a spell isn't at the trainer and has no quest Flow
  knows, Flow Improvements says so and names the class quests you haven't done, with a link
  to the first one's step. A new form ranks above ordinary training. `/flow classquests`
  lists them all.
- **A leftover quest item links to its step.** "Sunscale Feather ... The Angry Scytheclaws"
  now opens the step to accept that quest, or, while an earlier part is still in your log,
  that quest's step.
- A self-test of the move note put right.

## 0.35.295
- **A step's tooltip in short lines.** Its details wrapped into a narrow column ("Devouring
  Ectoplasm, level 16-17: drops it 100% of the time" over two lines, six times). Each mob is
  one bullet now ("- Devouring Ectoplasm (16-17): 100%") under one heading, bullets and short
  lines are never wrapped, and the hints at the bottom are one a line.
- **Dungeons say "3 of 5".** In the Dungeons list a run reads "Wailing Caverns: 3 of 5" (done,
  out of all its quests) so it no longer runs off the menu. Hover it for each count on its
  own line: quests completed, the ones you're on, the ones you're missing, any that start
  inside, and the total. The line under the arrow reads "Dungeon route: Wailing Caverns, 3 of 5".

## 0.35.294
- **The professions card no longer pops up to train the next tier.** It appeared at login, on
  a new level and in towns whenever a tier was ready ("Train the next Skinning tier"), with
  "Choose others...". Training a tier is already a step on your route and a line in Flow
  Improvements. The card now pops up only for a main profession you've still to learn while
  you have fewer than two, and when what Flow suggests for your class changes (then the
  picker opens). The Flow Professions button on the profession window still opens it any time.

## 0.35.293
- **Your quests by zone, and leaving a zone out.** The Flow menu has a "Zones" section: each
  zone where you have quest steps, with how many and their levels ("Stonetalon Mountains: 6
  steps (2 to accept), levels 17-22"). Untick a zone and the route stops taking you there:
  its quests stay in your log and come back when you tick it again. `/flow zones` lists them;
  `/flow zones off stonetalon`, `/flow zones on stonetalon`, `/flow zones all`. Only quest
  steps count: a trainer or a vendor in a zone you've left out is still used.

## 0.35.292
- **The target button always names its spell.** The line over the icon now always says what
  the press casts, by name ("Wrath"), and who it's for when that's someone else ("Regrowth on
  Beryl"). Hold a modifier and it changes to that modifier's spell ("Moonfire"), without the
  "CTRL + key:" in front. Before, an ordinary spell had no name at all, and 0.35.287 had
  taken the name away while a modifier was held.

## 0.35.291
- Self button: the diagnostics (and `/flow selfbutton why`) now say whether presses came by
  mouse or by its key, what it's set to cast, and every frame that takes clicks and lies over
  it, to find out why a click on it doesn't cast.

## 0.35.290
- **A step that needs something from another continent waits for it, and says where.** "Trial
  of the Sea Lion" sent you to the shrine with half the pendant: the other half is across the
  sea, so its step wasn't on your route, and nothing held back the steps that need it. Those
  steps are now listed as waiting, with what comes first, the zone and continent it's in, and
  how to cross: "first: Trial of the Sea Lion: Get Half Pendant of Aquatic Endurance. That's
  in Silverpine Forest, Eastern Kingdoms. Zeppelin from the tower outside Orgrimmar...".

## 0.35.289
- **Hovering a step in the Flow Router shows that step alone.** The map used to add the step
  before and the step after, muted, with the lines between them ("from" and "to"). Now it's
  only the step you point at, with its areas.
- **"Show on map" says which zone a step is in.** When the step isn't on the map that opens,
  a line across the top of the map says so: "This step is in The Barrens: right-click the
  map to zoom out, then click The Barrens." Flow can't turn the game's map to another zone
  itself: an add-on doing that breaks the map's own buttons in a later fight.

## 0.35.288
- **Cooldowns on the small icons, in a fight too.** The icons beside the target button and the
  self button showed a cooldown number only when Flow could read the time, and in a fight the
  game hides it, so they showed nothing there. Each small icon now has the game's own
  cooldown sweep and countdown, as the big icon does: it darkens and counts down while the
  spell or item is cooling.

## 0.35.287
- **No "CTRL + key: Moonfire" line over the target button.** While you held a modifier that
  line was written over the icon. The modifier is already shown by the key bind ("CTRL +")
  and the picture says the spell, so it's gone. A Flow Action still says what the press does,
  and a buff or heal for someone still says who it's for.

## 0.35.286
- **Trails remember how long each stretch takes.** Flow learned where you walk, not how
  long it took. Each stretch now keeps the quickest you've covered it, and when two known
  ways lead to a step the arrow takes the one you got through faster (a road over a swim),
  not just the shorter line. Time you spent standing or fighting isn't counted. It starts
  from what you walk from now on; trails learned before are used by their length, as before.
- **A full trail network thins itself.** A continent holds 6,000 trail points, and once full
  Flow learned nothing new there. When it's nearly full, points in the middle of a straight
  run are taken out and their neighbours joined, so the same ground takes fewer points.
  Corners, forks and points inside caves and buildings stay.

## 0.35.285
- **A "banker" who isn't a bank is learned as not one.** Flow kept sending you to bank at the
  Crossroads, where an NPC is titled a banker but opens no bank: the quest data marks them as
  one. Flow can't know better until you talk to them. Now, when you talk to someone the quest
  data calls a banker and no bank opens, Flow notes it, says so, and stops sending you there
  (for all your characters). If a bank does open there later, the note is dropped.
- **Gathering for the zone you're in waits behind your quests.** "Herbalism 35 -> 50
  (Mageroyal here needs 50)" was a step like any other and could come first. It's optional
  now: the route takes it in when it's near the way you're going, and the minimap still
  shows the herbs. When your route is about to take you to another zone whose herbs are
  beyond you, gathering comes before you leave, as a proper step.
- Two self-tests put right (a class quest already in your log; the quest item row).

## 0.35.284
- **Flow windows, Flow Meters: the tick means "always shown".** It's just "Flow Meters" now
  (no "(right-click...)"). Tick it and the meters are on and always shown, also if they were
  hidden or off. Untick it and they show as before (in a group, or in combat). "In combat"
  and "in a group" are chosen by right-clicking the meters themselves, and with those the
  tick is off.

## 0.35.283
- **Before you leave a zone, the next one counts for your gathering skill.** When your next
  step is in another zone and something grows there that your skill can't gather, reaching
  that skill is a step now, here, before you go: "Pick Peacebloom or Silverleaf: Herbalism
  35 -> 50 (Mageroyal in The Barrens needs 50)". Until now Flow only noticed once you were
  already standing among herbs you couldn't pick.

## 0.35.282
- **A material nothing drops or sells becomes a step at the auction house.** "Get 57 Wool
  Cloth" sat in the blocked list. When Flow has seen a price for it at an auction house and
  knows an auctioneer, it's a step there: "Buy 57 Wool Cloth at the auction house (about 58
  silver)", and the route waits until you can pay. With no price seen, or no auctioneer known
  yet, it stays listed and says which is missing.

## 0.35.281
- **A quest that needs you to bring something sends you to fetch it first.** "Trial of the
  Lake" wants a Shrine Bauble from the lake, then taken to the shrine; the arrow went
  straight to the shrine. When the quest data says a quest needs an item that isn't one of
  its objectives and you don't carry it, getting it is now a step of its own where it's
  found ("Trial of the Lake: Get Shrine Bauble"), and the quest's other steps wait for it.
- Three self-tests that still expected the old menu are put right.

## 0.35.280
- **Flow Settings: the keys in one place, nothing twice.** The first group is "Easy keys", and
  its four keys are named by button: Target button key, Target button second key, Self button
  key, Self button second key. "Hover to bind keys" was there twice (one came with the
  entries moved out of the menu): once now, with "Show keys bound to spells" beside it.
  Text-to-speech was there twice too (under Bonus mode, and again as "Extras"): once now,
  under Bonus mode.

## 0.35.279
- **Aquatic Form links to its quest.** "Get Aquatic Form (level 16, class quest)" had no step
  to open. It's a quest chain, and Flow now knows it: the line says where you are in it
  ("class quest: "A Lesson to Learn" is in your log") and opens that quest's step on your
  route, or the step to accept its first part.
- **Cure Poison is no longer advised once a trainer has shown it isn't there.** Flow had
  noted that no trainer listed it, but asked again each time you gained a level.
- **A leftover's quest says what comes first.** "…one you haven't done does: The Angry
  Scytheclaws (level 17); it comes after "Echeyakee", in your log". (There's no Accept step
  for it until then: the game doesn't offer it.)
- **The gathering step shows its area on the world map**, as a kill step does, and inside it
  the arrow goes from spot to spot.
- **Flow Router: room under a title that takes two lines.** The first row no longer runs into it.

## 0.35.278
- **The two buttons are now the target button and the self button.** What was the "easy
  button" is the target button (attacks on an enemy; heals, buffs and cures on a friendly
  target and your group); what was the "buff button" is the self button (your heals, food,
  bandage, cures and buffs). Every message, menu, tooltip, setting and the docs say so.
  `/flow selfbutton`, `/flow selfkey` and `/flow selfkey2` are the commands; the old
  `/flow buffbutton` and `/flow buffkey` still work.

## 0.35.277
- **A shorter Flow menu.** The arrow's look, the key bindings and the extras left the
  right-click menu for Flow Settings, where the same choices are ticks and buttons: "The
  arrow" under Finding your way, "Key bindings" with your keys, "Extras" under Just for fun.
  The menu keeps a "Buttons" section with two ticks: the buff button on or off, and docked
  under Flow's icon or not.
- **Flow Meters is one tick in the menu:** shown or not. When they show (in combat, in a
  group, always) and how many rows (2, 5, 10) are on the meters' own right-click menu.

## 0.35.276
- **The gathering step says what to pick.** "Herbalism: 35 -> 50 (Mageroyal here needs 50)"
  named the skill and the herb out of reach, not the ones to gather. It now reads "Pick
  Earthroot, Peacebloom or Silverleaf: Herbalism 35 -> 50 (Mageroyal here needs 50)": the
  herbs on this map you can pick that still raise your skill, the best first. The arrow leads
  to the nearest spot and on to the next; once you're at 50 the step moves on to the next
  herb this zone has beyond you.

## 0.35.275
- **Loot rolls: the upgrade arrow on the roll window.** An item that's an upgrade for you now
  has the green arrow of your bag icons on its picture in the roll window, with how much
  better beside it ("+2.1"), as well as the "Flow: upgrade: Need" line. Flow still never rolls
  for you.
- **Flow Seller says why it stopped at 12.** After selling 12 it used to just show "Sell 7
  items". Above it now: Flow stopped on purpose, because a vendor keeps only your last 12
  sales to buy back; the 7 are still to sell; selling them now means the first ones can no
  longer be bought back, or leave them for your next visit.

## 0.35.274
- Flow Meters: when you cast a taunt (Growl), your threat as the game reports it is noted in
  the diagnostics, at the cast and a moment later, to find out why the meter didn't show the
  jump.

## 0.35.273
- **Every small icon shows its cooldown and whether it can be cast.** The buff button's four
  icons (Shift, Ctrl, Alt, C+S) had neither; Flow's own showed it for spells only. All of
  them now show the time left on a cooldown in the middle, go grey while cooling down or when
  they can't be cast (no mana, none left in your bags), and red when out of range. Items too:
  a potion's and a bandage's cooldown.
- **Threat on nameplates: a little higher, and coloured by your share.** The number sat on the
  level beside the name; it's raised clear of it. When you're not tanking: green way below,
  yellow from 50%, red above 90%, flashing red at 100% and over. Tanking keeps its own
  colours (green: it's on you; orange: you're losing it), since 100% is where a tank wants
  to be.

## 0.35.272
- **A player's tooltip says which of your buffs they have, whoever cast them.** The game's own
  party tooltip lists only buffs you could have cast and leaves out a stronger or group
  version. Hover any friendly player and Flow adds a line for each buff you give others:
  "has it (24 min)", "has Gift of the Wild (51 min)", "has a more powerful one", or "MISSING"
  in red. Only the buffs that fit the person (Thorns for a tank). Flow Settings, In a group:
  "Your buffs on a player's tooltip".

## 0.35.271
- **In a party, you're no longer listed as a party member.** The choices under the arrow showed
  "Your own route", "Join the party route" and "Just <your name>'s quests", which was your
  own route again. The game gives Flow one name for you and signs your messages with another
  (with your second name), so Flow took its own messages for someone else's. It now
  recognises a message of its own coming back and remembers that name as you.

## 0.35.270
- **Flow no longer says "destroy" of a quest item it knows no quest for.** It said so of
  Sunscale Feathers, which a quest you get later uses. Flow now looks through every quest in
  the quest data for the item (not only the short list the data keeps per item), and when it
  finds one you haven't done it says "keep" and names it. When it finds none, the item is
  kept and it says to read its tooltip first. Only a quest you've done makes it sell or destroy.
- **Things only another class can use** (the scrolls: "Classes: Mage") are no longer just
  kept. They go to the auction house when the price there is worth it, else to a vendor, with
  the reason "only a Mage can use it".
- **Flow Banker, In your bank: no empty rows on top.** Your things start at the top left, as
  in the bank; a container with nothing in it comes after them. (Open your bank once for the
  new picture.)
- **A Flow Banker button on the bank's own window**, beside the one on your bags.

## 0.35.269
- **Flow Banker: Deposit no longer overlaps "All my choices".** Deposit sat in the middle of
  the bottom row, over the end of the choices button. It's on the right now, the choices
  button on the left.

## 0.35.268
- **The auction house scan says it's done once, and doesn't start again at once.** With the
  window open, "read N listings" was printed over and over (the game repeats its signal and
  Flow read the list each time). It's read once per request now. And opening the window again
  within five minutes no longer looks everything up again; `/flow ah scan` does it right away.
- **Flow Settings: the key rows have room.** The key shown for "Buff button's second key" ran
  under its Set key button. Each key now has a column of its own between the label and the
  buttons, and the four rows are a little further apart.

## 0.35.267
- **Item tooltips say how many you have.** One line on every item's tooltip, wherever it's
  shown (your bags, a vendor, a quest reward, the auction house, a chat link): "You have 52:
  12 in your bags, 40 in your bank". Nothing when you have none. The bank's count is from the
  last time you had it open. Flow Settings, Loot and selling: "How many you have, on item
  tooltips".

## 0.35.266
- **A leftover quest item now reads the same in your bags and in Flow Improvements.** The bags
  said "quest item: keep" for anything of the game's Quest kind without looking at your log,
  while Flow Improvements said it was left over. Both now go by one check, and by what the
  quest data says the item is for:
  - a quest you haven't done uses it: keep, and it names the quest;
  - nothing left uses it and a vendor pays: sell;
  - nothing left uses it and vendors won't take it: "destroy it for the slot" (Flow never
    destroys anything itself).
- The diagnostics list, for each leftover, the quests the quest data ties it to and whether
  you've done them; and everything a tooltip says for things with no "Use:" line (the scrolls).

## 0.35.265
- **A form's new spell goes on that form's bar.** The game drops a new spell into the first
  empty slot of whichever bar is showing: learn Maul in caster form and it lands on your
  caster bar. Flow now moves it to the first empty slot of the bar that form shows (Bear Form,
  Cat Form, a warrior's stances, stealth). Which form a spell needs is read from its tooltip
  ("Requires Bear Form"). Out of a fight only; a full bar is left alone and Flow says so.
  Flow Settings, New spells and professions: "Put a form's new spells on that form's bar".

## 0.35.264
- **Flow's minimap marker no longer covers the game's icon.** The (o) sat on the step's spot
  and hid the game's own icon there, with its little arrow for "above you" or "below you". It
  can't go behind it (the game draws its icons into the minimap itself), so in view the
  marker is now a ring of small dots round the spot with the middle left clear. At the
  minimap's edge it's still the solid (o).

## 0.35.263
- **The dungeon route gets you ready on the way.** On the dungeon route Flow used to drop
  everything but the run's own steps, so a trip to Thunder Bluff for a dungeon quest walked
  you past your trainer. It now keeps the errands: training that's waiting (class spells, a
  profession tier, a weapon skill), selling and repairs, and your bank, planned in with the
  run's steps. The route's menu (the "Dungeon route" line under the arrow) has a tick, "Get
  ready on the way", to turn that off.

## 0.35.262
- **A material your skill has moved past is let go.** Linen Cloth was kept "for First Aid:
  Heavy Linen Bandage" although First Aid 80 is on Wool Bandage. Once you're at the end of
  every recipe in Flow's guide that takes a material, that profession no longer claims it:
  it's sold, or goes to the auction house when the price there is worth it, with the reason
  "your First Aid is past it (Heavy Linen Bandage)".
- **Spare bags.** A bag lying in your bags that's no bigger than any bag you wear is marked to
  sell ("spare 8-slot bag"). One that's bigger than a bag you wear, or when a bag slot is
  empty, says "put it on".
- The diagnostics now carry the game's own "Use:" line for things Flow can't place (the
  scrolls), so a rule can be written for them.
- Fixed a self-test of the meters' headings that failed on every reload.

## 0.35.261
- **Flow Meters menu: Show and Rows.** Right-click: under "Show", pick "Show in combat",
  "Show in group" (the usual; a training dummy counts) or "Always show". Under "Rows", 2, 5 or
  10 players (the group's row sits on top of them).
- **Dungeons read "Quests: 1/3".** How many of a run's quests are in your log, out of how many
  it has, in the Dungeons list, `/flow dungeons` and the line under the arrow ("Dungeon
  route: Ragefire Chasm · Quests: 2/5").
- **Flow's tooltips have room for their sentences.** The longer explanations were wrapped into
  a narrow column of short lines. A tooltip Flow opens is wider now; the game's own tooltips
  keep their width.

## 0.35.260
- **Ask your group in chat for a dungeon's quests.** On a dungeon run's menu (the arrow's
  Dungeons list, and the "Dungeon route" line under the arrow): "Ask my group in chat who has
  its quests". It says one line in party or raid chat, the quests you still need ("... Can
  anyone share them?"), or the ones you can share when you have them all. Anyone can read it,
  with Flow or without. Nothing is said unless you click it.

## 0.35.259
- **An empty herb or ore spot no longer holds you.** Flow knows where herbs can grow, not
  which ones are up right now (the game doesn't tell add-ons; its own Find Herbs dots are the
  live ones). So it can't check before it sends you. What it does now: stand at a spot for a
  few seconds without picking anything and that spot rests, like one you just picked, and the
  arrow goes on to the next. The step's tooltip says so.

## 0.35.258
- **Flow Meters: this fight, or all fights.** Right-click: "This fight" starts again at every
  pull (as before); "All fights" is everything since the last reset, all the damage (or
  healing) over all the time in combat, for the group and for each player. "Reset the counts"
  starts it over. The list's title says "(all fights)" when it's that.
- **The row choices are players now, with the group on top.** 5 and 10 show the group's row
  and then 5 or 10 players (the group used to take one of the rows). Compact shows the group
  and the top 2, and 2 rows of threat.

## 0.35.257
- **The dungeon route shows.** While a dungeon run is prepared there's a line under the arrow,
  like the party route's: "Dungeon route: Ragefire Chasm, 3 to pick up", then "... 5 quests
  ready: go in". Click it for the run's quests and three choices: leave the dungeon route
  (your usual route; the run is kept), go back on it, or cancel the run. `/flow dungeons
  <name>` now puts you on the dungeon route; `/flow dungeons leave`, `back` and `off`.
- **Dungeon lists say what you've done.** Each run reads "5 quests: 2 in your log, 3 to get;
  1 done", in the arrow menu and in `/flow dungeons`, and a dungeon whose quests you've all
  done is listed as "all done".
- **Flow Meters: flat bars.** A plain colour, no gloss.

## 0.35.256
- **Flow's icon and the buff button are the same size, with the same edge.** Flow's coloured
  edge was drawn over the outer 3 pixels of its picture, the buff button's blue edge round its
  picture, so Flow's looked smaller and the cast bar lay on Flow's edge. Both edges now go
  round the picture, and the cast bar sits inside the edge on both. Docked, the gap between
  the two is a little bigger so the modifier names still fit.

## 0.35.255
- **`/flow dungeons`: the dungeon runs at your level as a checklist.** Each run with its quests
  (who gives each, and where), and one line that says whether you have them all: "You have 2
  of 5: 3 still to pick up before you go in." `/flow dungeons wailing` prepares that run: its
  quests to pick up go on your route, then the entrance. `/flow dungeons off` cancels it. All
  of this was already in the arrow's right-click menu (Dungeons); now it can be read at a
  glance, and it's in the diagnostics.

## 0.35.254
- **Suggested game setting: health and mana numbers on your and your target's frames.** A new
  row under "Suggested WoW settings" (Flow Settings, and `/flow setup`), ticked by "Flow
  suggests": the numbers written on the bars, so you read how much is left. If you already
  show percent or both, that's kept. Flow doesn't change it by itself: tick it and Apply.

## 0.35.253
- **Docked: the buff button has a size of its own.** Hold Ctrl and turn the mouse wheel over
  the buff button and only it grows or shrinks; Flow's icon keeps its size, and the buff
  button stays docked under it. Until you resize it, it's the size of Flow's icon. It still
  can't be dragged while docked (it goes where Flow's icon goes), and the one "drag to move"
  note stays under the pair.

## 0.35.252
- **A herb you can't pick yet now puts gathering on your route.** In the Barrens with
  Herbalism 35, Mageroyal (50) was everywhere and out of reach, and Flow had planned nothing:
  its skill-up step was optional, and on Kalimdor it found no herb spots at all. Now, when
  something grows in the zone you're in that your skill can't gather, reaching that skill is
  a step of its own ("Herbalism: 35 -> 50 (Mageroyal here needs 50)"), at the herbs here
  that you can pick and that still raise your skill.

## 0.35.251
- **"Stop" is now "step" everywhere.** One thing the route has you do was called a stop, which
  read oddly for things that aren't a place ("skip this stop" for making bandages). It's a
  step now, in every message, menu, tooltip, setting, the help and the docs: "Next step only",
  "Hide this step", "12 steps". `/flow nav steps 3` is the command; the old `/flow nav stops 3`
  still works. A quest's own lines stay objectives, and a spot you set yourself stays a waypoint.

## 0.35.250
- **Flow Meters: each list's heading looks like a Flow title bar.** "Threat" and "DPS" (or
  Damage, HPS, Healing) now sit on the same dark bar with the orange accent as the Flow
  Tracker's title, small.

## 0.35.249
- **Flow Meters: right-click to pick what the second list counts.** Damage per second (as
  before), total damage, healing per second or total healing, each from the game's own count
  for this fight. The list's title says which.
- **Pets on the threat list.** Only your own pet was asked about; now every party or raid
  member's pet is too, so a hunter's or warlock's pet holding a mob shows.

## 0.35.248
- **Your threat on each enemy's nameplate.** In a fight, in a group (or with a pet out), a
  small number at the right of each enemy's nameplate: your threat as a share of whoever it's
  attacking. Its colour says where you stand. Tanking (a bear, or a role of Tank): green it's
  on you, orange it's on you but someone has more threat (you're losing it), yellow nearly
  yours, red it's on someone else. Otherwise: grey fine, yellow you're about to take it, red
  it's on you. While it's on you, the number shows who's closest behind ("100% · Beryl 85%").
  Enemy nameplates must be on (V). Flow Settings, On your screen; or `/flow threat on|off`.
  If the game hides threat numbers in a fight, the number is white and Flow can't say more.

## 0.35.247
- **Docked: one "drag to move · wheel to resize" note, under both buttons.** Holding Ctrl
  showed it twice, once under Flow's icon and once under the buff button. Docked, the buff
  button goes where Flow's icon goes, so it has no handle of its own now, and the one note
  sits under the pair. Undocked, each button keeps its own.

## 0.35.246
- **"A more powerful spell is already active": Flow moves on.** When someone already has a
  stronger buff than yours (a higher rank, or one Flow can't see), the game refuses your cast,
  and Flow kept offering it. Now that refusal is remembered for that person and spell: your
  next buff for them, or the next person, comes up at once. Flow asks again after 5 minutes,
  in case the stronger one has run out.

## 0.35.245
- **The world map shows the way to a stop in another zone.** With your next stop on another map
  than you, there was no line at all. Now the dotted line (with its dots walking the way you
  go) leaves from you, bends through the gate when Flow knows one on this map, and runs to the
  map's edge towards the stop. Looking at the stop's own map, it comes in from the edge or the
  gate to the stop. And there's no longer a line from you to a later stop that happens to be
  on your map when the next one isn't.

## 0.35.244
- **Flow's key buffs your party again, with the buff button on.** Out of a fight, with nothing
  else to press and no enemy targeted, Flow's key casts your buffs on whoever in your group is
  missing them (a druid's Mark of the Wild for everyone, Thorns for the tank), straight on
  them: no targeting. Since the buff button came, those had moved to it; now the buff button
  is for you and Flow's key is for the others. Not in a fight, a city or an inn, and for a
  druid only in caster form.
- The diagnostics say, for each person in your group and each buff, whether they have it and
  why Flow isn't offering it when it isn't.

## 0.35.243
- **No more red "Flow error (CHAT_MSG_SYSTEM)" line in a fight in a group.** There the game
  hides system messages and your target's ID from add-ons. Flow tried to read a hidden message
  (looking for "You have learned...") and to compare a hidden target ID (the fight record), and
  each try was an error. Both are now skipped when hidden.

## 0.35.242
- **The small "press this instead" icon has its own place when docked.** In a fight, when
  Flow advises a spell your key doesn't hold, a small pulsing icon says which. Docked, it sat
  on the icon's bottom right corner: under the auto-attack badge and over the gap to the buff
  button. Docked it now stands right of the key bind, with its words after it. On its own it
  stays on the corner. In both it is drawn above everything else.

## 0.35.241
- **The buff button is yours, Flow's key is your target's.** With the buff button on and a
  key on it, out of a fight too (in a fight it already was):
  - **The buff button, for you:** healing up after a fight (your heal spell, bandage, food,
    drink), a poison or curse to take off yourself, your buffs, fishing.
  - **Flow's key, for your target:** attacks on an enemy; heals, buffs and cures on a
    friendly player you target.
  Flow's icon no longer says "cast a heal" on yourself between fights: the buff button does,
  and which key you press says who gets it. "Flow's key keeps its heal and potion" (Flow
  Settings) puts healing yourself back on both. `/flow carekeys` says which it is.

## 0.35.240
- **No "Turn in" for a quest that isn't done because its stop is hidden.** "Turn in:
  Centaur Bracers" was on the route at 10/15: the stop for collecting the bracers had been
  hidden, and the hand-in stayed behind without it. A stop that comes after one you hid now
  leaves the route with it, and the Flow Router says why ("first: ... you hid that stop").
  Unhide the stop and both come back.
- **Fishing is on the buff button only.** With the buff button on and a key on it, the pole,
  the lure, the cast and reeling in are its steps alone; they no longer show on Flow's icon
  as well. Without a buff button key the Flow key fishes as before.
- **The buff button is docked under Flow's icon unless you take it off** (Flow menu, Keys,
  or Flow Settings).

## 0.35.239
- **Docked: modifier, key bind, auto-attack, one above the other.** With the buff button
  docked under Flow's icon, the key bind of each button is at the middle of its right side,
  and the modifier you hold is on its own line above it ("CTRL +" over "Q / MB5"). The
  auto-attack badge is as small as those letters and sits at the bottom right of Flow's
  icon, under the bind; it can still be clicked. On their own the buttons are unchanged.

## 0.35.238
- **Flow Banker, Auction prices: the two lines of words at the top no longer run into the
  list.** The list began at a fixed height that left room for one line. It now starts under
  the words, however many lines they take, with a gap; the window is a little taller for it.

## 0.35.237
- **Docked, all four modifier names are there: SHIFT, CTRL, ALT, C+S.** The names between
  the two rows came from the buff button's own icons, and it only made an icon for a press
  that had something on it. With no potion or healthstone in the bags, Alt had nothing: no
  "ALT", and the C+S icon slid over to stand under Flow's Alt. Docked, each press now keeps
  its own column under Flow's icon for the same modifier, and the four names are written
  once, whether or not the buff button has something on each.

## 0.35.236
- **The label moves are for the docked mode only.** 0.35.233 moved the key binds and spell
  names on both buttons whether docked or not. On their own the buttons are back as they
  were: key above, name below. With the buff button docked under Flow's icon: Flow's key is
  at the icon's bottom right, its spell name on top of the icon; the buff button's key is
  at its top right and its name under it.

## 0.35.235
- **The "Making ... 3/10" bar can't get stuck.** Attacked in the middle of a batch, the bar
  stayed up until a reload: the batch had ended without the game naming the interrupted
  cast, so nothing closed it. A batch now also ends when a fight starts, when an
  interruption comes with no name, and when nothing has been made for a few seconds. It
  says "Stopped: ... 3/10" and goes.
- **It says how long is left:** "Making Linen Bandage 3/10 (about 21 s)", counting down,
  once the first one tells how long each takes.

## 0.35.234
- **Vendor materials are bought when you can use them.** Flow sent you to buy Shiny Red
  Apples for a stew whose recipe you couldn't learn yet, and you carried them for levels. A
  "Buy ..." stop for something a vendor sells now comes only once its craft is otherwise
  ready: you know the recipe and the other materials are in your bags (or bank). Until
  then there's no stop for it.

## 0.35.233
- **One sign for "press this".** The glow on your action bar, the ring round a modifier's
  icon, the small icon in the corner, the heal prompt and the buff button's edge all meant
  "Flow suggests this", each in its own gold and its own blink. They're all the orange of a
  legendary item now, and they pulse together, on one beat.
- **Cast time on the buttons.** While you cast or channel, a thin bar runs along the bottom
  edge of Flow's icon and of the buff button.
- **The buff button shows the global cooldown** (and its spell's own) as a sweep over the
  icon, like Flow's.
- **Key binds to the right, spell names underneath.** Each button's key is written at its
  top right; the name of what it casts hangs under the button from its left edge. Docked,
  each name sits under its own button.
- **Exact stops before spread-out ones.** A quest whose mobs or items are all over an area
  (20 spots or more) is planned a little later than a stop at one exact place nearby, so
  you go to the exact ones and get the spread-out ones on the way. Its details say so.
- **`/flow roll` no longer speaks at every login** (a self-test was calling it out loud), and
  its words say what it is: a suggestion. Flow never rolls for you.
- Not seen in game yet.

## 0.35.232
- **Flow Meters are bars now.** DPS: the first row is the whole group; under it the top
  player with a full bar, and each row after measured against that player. Threat: whoever
  the enemy is attacking is on top, then the most threat; the figures are the share of the
  tank's threat, so 110% or 120% shows before a boss turns on someone, and the bars
  stretch to the highest figure.
- **Whole numbers.** The long strings of decimals are gone. Right-click the meters for
  1, 2 or 3 decimals, the number of rows, "always shown" and off.
- **A stop says how high its mobs are and how often they drop the item.** Hover a stop (on
  the map, in the Flow Router or the Flow Tracker): "Greater Plainstrider, level 11-12:
  drops it 25% of the time", best dropper first, from the quest data's own drop figures.
  A mob to kill shows its level.
- Where the game hides the numbers from add-ons in a fight, Flow can't sort those rows; the
  bars still fill, since the game draws them itself.

## 0.35.231
- **A second key for the buff button.** Like Flow's own key, the buff button can have two
  keys: Flow Settings has a "Buff button's second key" row (with the same check of what the
  key already does), or `/flow buffkey2 <key>`. Both keys press the button, and Shift,
  Ctrl, Alt and Ctrl + Shift with either cast its heals and potion. The button shows both
  ("E / R").

## 0.35.230
- **Auto attack starts whichever press you open with.** Flow already made the first press of
  your key at a new enemy the game's Start Attack (your opener comes with the next press),
  but only the plain key: opening with Shift, Ctrl, Alt or Ctrl + Shift + key cast its
  spell and never started your swing. While that first press is pending, every one of the
  key's presses is Start Attack now.
- **The auto-attack badge:** a click did nothing. If Attack is on one of your action bars,
  the badge now presses that bar slot, which is what the game's own Attack button does; if
  it isn't, it still tries the Attack spell. Each click writes to the log how the badge is
  set and whether your swing changed. If the click still does nothing, put Attack from your
  spellbook on any action bar slot.
- Once a fight is on, Flow can't turn auto attack on from the key: the game allows no key
  to change mid-fight. The badge is for that.

## 0.35.229
- **The spyglass starts on the minimap.** The round Flow Improvements button used to start
  in the middle of the screen; if you've never moved it, it now sits on the minimap's rim,
  bottom right, like the game's own minimap buttons. Where you dragged it to is kept.

## 0.35.228
- **Dock the buff button under the Flow icon.** A tick in the Flow menu (Keys) and in Flow
  Settings joins the two into one block: the buff button right under Flow's icon, its
  little icons under Flow's, with Shift, Ctrl, Alt and C+S written once between the two
  rows, and both spell names below. Untick it and the buff button goes back where it stood.
- **The buff button shows what a held modifier casts**, like Flow's icon: hold Shift, Ctrl,
  Alt or Ctrl + Shift and its icon and name become that press's spell or item.
- **The buff button counts down its spell's cooldown** on the icon, and turns red when its
  target is out of reach.
- **The auto-attack badge wears your main-hand weapon.**
- The name under Flow's icon in a fight no longer starts with "key:": just the spell.
- Not seen in game yet.

## 0.35.227
- **No spell on two presses.** Bash could sit on two of the easy button's modifiers: the
  druid had one list for the pull and another for a change of form, and they disagreed.
  There's one list now, and the easy button never gives a second press the spell an earlier
  one already casts.
- **Shift is the nearest icon, Ctrl the next,** on both buttons; the spells stay where they
  were. Easy button, as a caster: Moonfire is Shift + key, Entangling Roots Ctrl + key.
  Second key: Healing Touch is Shift, Rejuvenation Ctrl. (Where your heal lives on the easy
  button itself, it stays on Shift.)
- **Click the little icons to cast.** A click on an icon beside the Flow icon, or beside the
  buff button, casts what its modifier press casts. "Click the icons beside the Flow icon
  to cast" in Flow Settings turns the easy button's off.
- **Auto-Attack badge:** the crossed swords right of the Flow icon say "Auto-Attack" on
  hover, show dim in a fight or with an enemy targeted while you aren't swinging, and a
  click turns your swing on or off.
- **In a fight** a small crossed-swords mark shows at the Flow icon's top left corner.
- Self-tests: three that failed are fixed (one failed whenever Ctrl was held while the
  tests ran; one didn't know the menu's new divider lines; one waited on the search box).
- The clickable icons and the badge haven't been seen working in game yet.

## 0.35.226
- **The dungeon key has a tick under Route includes.** "Dungeon key above the Flow Tracker
  (suggests runs)" turns the gold key on and off, with the rest of what the route has. (The
  Dungeons section keeps its "Suggest dungeons" tick: the same switch.)
- **Route includes is easier to read:** a line above "Select all" and another above
  "Unhide all stops".

## 0.35.225
- **"Next stop only" is the default** for Stops on the map (the map and the Flow Tracker). It
  was "All objectives in this area" unless you had picked a number. If you never chose, you
  now get the next stop only; a choice you made is kept.
- **The area choice is last in the list and is called "All stops in this area".** What it
  shows hasn't changed: your next stop, plus the stops near you and near it. Where nothing
  else is nearby (a city, Moonglade) that is just your next stop, which is why it could
  look the same as "Next stop only".
- **One word for one thing.** A *stop* is one place on your route where you do one thing; an
  *objective* is a line of a quest, as the game writes it; a *waypoint* is a spot you set
  yourself. Flow's menus and settings now say "stops" where they meant stops. `/flow help`
  has the three definitions.

## 0.35.224
- **Your Flow key casts the teleport or hearthstone.** When the arrow shows a travel spell
  or your hearthstone as the way to your next stop, the Flow key casts it: out of a fight,
  with no enemy targeted, and only when the key has nothing else to do (loot, quest items
  and the rest come first). Both are ten-second casts, so moving cancels one you didn't
  mean.
- **And the Flow Tracker has a button for it** on that stop's row, like a quest's item.
- "Walk there instead" (Flow menu, Arrow) takes it off the arrow, the key and the tracker
  for that stop. "The Flow key casts your teleport or hearthstone" in Flow Settings
  (Finding your way) turns the key and the button off.
- Not seen in game yet.

## 0.35.223
- **The arrow shows the teleport or the hearthstone.** When your next stop is a cast away
  (Teleport: Moonglade) or clearly quicker by hearthstone, that spell's or the stone's icon
  stands where the arrow was, so it's plain what to do; the arrow, half its size, sits
  beside it and still points the way on foot.
- **Walk there instead.** Flow menu, Arrow: "Walk there instead" drops the icon for that
  stop and the arrow is the arrow again; the same place brings it back.
- Not seen in game yet.

## 0.35.222
- **"Regrowth on Bob" now heals Bob.** With a friendly player targeted, the easy button
  showed a heal "on <their name>" but the key cast it on you; only Ctrl + key reached them.
  A heal now goes on whoever the icon names. A heal that names nobody still goes on you.

## 0.35.221
- **Flow Banker: search the auction prices.** A small box under the list: type any part of
  a name and the list narrows to the items that have it.
- **"To put away" is now "To bank".** The words above its grid have room for two lines (they
  ran under the first row of icons).
- **All my choices.** A button in "To bank" switches between the things in your bags and
  every banking choice you've made, also for things you don't carry right now. Click one to
  flip it, right-click to drop it and leave it to Flow again.

## 0.35.220
- **Flow keeps what the game tells it, and gets better from it.** Each time you open a class
  trainer, Flow records what it really teaches (spell, rank, level, price) and which spells
  Flow's own list expected that it doesn't have. Together with the quest spots it learns
  where you do quests the data can't place, these correct Flow's built-in lists at once,
  for all your characters: a spell no trainer has is no longer advised on any of them.
  `/flow facts` shows what it has learned.
- **Sharing them** is the same opt-in as the NPC spots: `/flow places share` now lists these
  game facts too (a class, a spell, a level, a price, a quest number, a map spot: nothing
  about you), and `tools\share-facts.ps1` merges them into `Learned\Facts.lua`, which comes
  with Flow for every player once merged. Nothing leaves your computer by itself.
  A quest spot another player shared is used when you have none of your own.

## 0.35.219
- **No "Get Cure Poison" when your trainer doesn't teach it.** Flow's own class list has
  Cure Poison at level 14, and kept a trainer stop on the route for it after the Moonglade
  trainer showed no such spell. A spell from Flow's list that your class trainer, read at
  your current level, doesn't list at all is no longer advised, and no longer keeps the
  trainer on your route. The log notes it, so the list can be corrected.

## 0.35.218
- **No "Learn the flight path: Silva Fil'naveth".** She and Bunthen Plainswind fly druids out
  of Moonglade themselves; there is no flight path to learn from them (and Silva only
  flies Alliance druids). The quest data marks them as flight masters, so since 0.35.216
  Flow offered them. They're left out now.

## 0.35.217
- **WoW's quest tracker popping up in fights.** With "Show WoW's quest tracker" unticked,
  Flow hid the game's tracker each time it came up, but in a fight it had to wait until the
  fight was over, so in a dungeon it kept appearing. In a fight Flow now makes it
  see-through at once (the game allows that) and hides it after. Each time the game's
  tracker comes up, Flow also writes down what decided it (your setting, a fight, a
  dungeon, Questie's tracker), so a report of it can be traced. If yours is still set to
  "leave it to the game", untick "Show WoW's quest tracker" in the Flow Tracker's
  right-click menu.
- **Leftover quest items.** Flow Improvements lists a quest item in your bags that no quest
  in your log asks for (left from a dropped quest), to look at and destroy for the slot.
  Flow never destroys anything. `/flow leftovers` lists them.
- **Flow Banker: Auto-cleanup.** A tick in the window's header, as in the Flow Seller: after
  Deposit, the game's Clean Up tidies your bank, then your bags.

## 0.35.216
- **Fixed: Flow took stable masters for flight masters.** Xon'cha in Orgrimmar, Seikwa in
  Bloodhoof Village, Shoja'my in Razor Hill: each a stable master, each offered as "Learn
  the flight path". Flow read the quest data's NPC roles with a later game's numbers; on
  WoW: Forever the data uses the first game's, where that number means stable master. The
  same mistake made every "vendor" from the data an innkeeper and every "repairer" an
  auctioneer (the NPCs you had talked to yourself were always right). Roles are now read
  by the data's own list, so the real flight masters, vendors, repairers, innkeepers,
  bankers and auctioneers are found.
- **Flow Banker, "To put away": a grid, and your own rules.** Everything Flow keeps in your
  bags as icons: green edge goes to the bank, grey and dimmed stays with you. Click an item
  to change which; it gets a gold edge and Flow follows your choice from then on, on every
  character. Right-click gives the choice back to Flow. Hover says what Flow would do and why.

## 0.35.215
- **Flow Banker shows your bank as it looks.** "In your bank" is now a grid of slots like the
  bank's own: each item's icon and count where it sits, empty slots as empty squares, the
  item's tooltip on hover, the wheel to scroll. It's read only: a picture of what Flow last
  saw, usable anywhere. Open your bank once on this version so Flow records the slots;
  until then it shows what it knew before, by name.

## 0.35.214
- **Flow Auctions: post with one click an item.** At the auction house a small window lists
  what in your bags Flow marks for the auction house, with the price it would ask: one
  silver under the cheapest buyout Flow last saw (the game takes whole silver only). "Post"
  on a row, or "Post next", puts up every one of that item you carry, for 12, 24 or 48
  hours. The game needs a click of yours for each auction, so it can't post by itself.
  A "Flow Auctions" tab on the auction window opens it; `/flow auctions` lists it all.
- **What doesn't sell goes to the vendor.** Flow counts the deposit lost each time one of
  your auctions runs out unsold. Once those deposits reach what the auction house would
  have earned over the vendor, the item becomes "sell" in the Flow Seller, with the reason
  "didn't sell at auction N times (deposits ...)". A sale wipes the count;
  `/flow auctions forget` wipes them all.
- Items worth under a silver each aren't listed: the game takes no copper prices.
- Not seen working at an auction house yet.

## 0.35.213
- **`/flow meter`: the meters whenever you want them.** It shows Flow Meters and keeps them
  shown, alone too; typed again, they go back to showing only in a group or at a training
  dummy. The Flow menu (Flow windows) has the same switch.
- **Auction house read:** Flow now says when it starts reading every listing ("about half a
  minute"), and during a long read at most one line every 15 seconds with how far it is.
  The read is one pass over the whole list, not page by page, and it worked in the game:
  217,229 listings, prices for 6,006 items, in 36 seconds.

## 0.35.212
- **Your hearthstone stays where your quests are.** In Orgrimmar for a dungeon, with every
  quest round the Crossroads, Flow asked to set your home in the city ("a city beats a
  village"). It now counts where your quests' stops are: with more of them nearer your home
  than the inn you're standing by, your home stays.
- **The flight path of the town you're in.** A flight master you don't have yet, on the map
  you're on and within 800 yards, is now a stop for its own sake. Before, it only joined
  the route when it lay within 250 yards of the way you were going anyway, so in Orgrimmar
  (440 yards off) it was left out.
- **Need or Greed on loot rolls.** When a roll comes up, Flow writes on the roll window
  whether the item is an upgrade for you ("upgrade +2.1: Need") or not ("not an upgrade:
  Greed"), by the same scores as the icons in your bags, and says an upgrade in chat too.
  It never rolls for you. "Roll hints" in Flow Settings (In a group) turns it off;
  `/flow roll <item>` asks about any item. Not seen in game yet.
- **Stopping a cast:** a druid's Bash (Bear Form) and a paladin's Hammer of Justice join
  War Stomp as the spells Flow asks for when your target starts casting.
- The log's group-buff lines no longer include the self-tests' made-up party.

## 0.35.211
- **Flow Meters: threat and DPS.** In a party or raid, and at a training dummy, two small
  lists stacked on each other: threat on your target (percent of the tank's) and damage per
  second in this fight, with the group's total. Three rows each by default: the top two and
  you; if you're one of them, the third. Flow menu, Flow windows: on or off, and 3, 5 or 10
  rows. Ctrl + drag moves them. The numbers are the game's own; in a fight the game may
  hide some of them from add-ons, and then those rows show in the game's order instead of
  being sorted (`/flow meters` says which). After each fight the numbers go into the log.
  Not seen working in game yet.
- **Walking into a dungeon:** Flow says which of that dungeon's quests are in your log and
  which you could have but don't, with who gives them (`/flow dungeon` says it again).
  Bosses and a dungeon map aren't part of this yet.
- **Hovering your first stop** in the Flow Router or Flow Tracker now shows the way from
  you to it; before, only the stop and the one after it showed.
- Flow menu, Flow windows: Flow Banker is listed too.

## 0.35.210
- **Your own waypoint: the map shows it alone.** While you have a waypoint of your own, the
  world map leaves out Flow's route, stops and areas, so it's clear where you're headed.
  Clear the waypoint and the route is back. Pointing at a stop in the Flow Router or Flow
  Tracker still shows that stop. Flow menu, Your waypoint, "On the map, show only my
  waypoint while one is set" turns it off.

## 0.35.209
- **The buff button looks like Flow's icon.** The same size (52), its key written above it
  in the same letters, and its Ctrl, Shift, Alt and C+S icons out to the left in the same
  stepped sizes and order. Its blue edge still tells the two apart.
- **Fixed: an error when looting in a group.** There the game hides a corpse's name and ID,
  and Flow's drop counting compared them anyway (seen in the diagnostics after a dungeon
  group formed). It now skips such a corpse.
- For checking group play: each party buff Flow suggests is written to the log once, with
  how many are in the group.
- The key that follows your form (0.35.205) is confirmed in the game: after shifting to
  Bear Form in a fight the key cast Maul.

## 0.35.208
- **The buff button only when something is due.** It used to be always there, showing the
  buff that runs out first. Now it shows up when a buff, a stone, a bandage or food is due;
  with an enemy targeted (and heals on its key) it shows your heal, ready for the fight;
  otherwise it stays away, like Flow's icon. "Buff button always shows my next buff" in
  Flow Settings brings the old way back.
- **Key messages stand out.** In Flow Settings, what a key already does (and the buttons to
  use it anyway, unbind it or pick another) now sits in an orange box that flashes when it
  appears; a key that was set flashes green.
- A self-test that expected "no known spot" for a quest handed in inside a dungeon now
  expects the dungeon's name (it was right in the game, the test was behind).

## 0.35.207
- **Heal and potion moved to the second key.** With the buff button on and a key of its own,
  Shift + Flow's key and Alt + Flow's key are two more attacks instead of your heal and
  potion. A caster druid's five presses: Wrath, Moonfire (Ctrl), Entangling Roots (Shift),
  Nature's Grasp (Alt), War Stomp (Ctrl + Shift). A heal Flow advises in a fight lights the
  buff button and names its key. "Flow's key keeps its heal and potion too" in Flow
  Settings keeps them on both.
- **Every press follows your form.** Change form in a fight and all of Flow's key changes
  with it, not only the key and Ctrl: in Bear Form at this level Maul, Demoralizing Roar
  (Ctrl), Growl (Shift), Enrage (Alt). `/flow key test` lists each form's presses.
- **Keys in one place.** Flow Settings has a third row, "Buff button's key", beside Flow's
  key and its second key. A key one of Flow's buttons already has moves to the one you set
  it for. A key something of the game's uses: Flow says what, that the key will do only
  Flow's thing while Flow has it (never both), and offers "Use it and unbind" to take the
  other binding off that key for good.
- **Flow menu, Keys:** "Set Flow's keys" opens that page, and a tick turns the buff button
  on and off.
- None of this has been seen working in game yet.

## 0.35.206
- **A second key for heals and potions.** Flow already had a second button with its own key:
  the buff button (`/flow buffbutton on`, then `/flow buffkey <key>`). That key now has
  modifiers of its own, like Flow's key:
  - the key itself: out of a fight your next buff, bandage or food, as before; in a fight
    your quickest heal, on you
  - Shift + it: your heal over time (Rejuvenation)
  - Ctrl + it: your other heal (Healing Touch)
  - Alt + it: your healthstone or healing potion
  - Ctrl + Shift + it: your best bandage (without one, your cure)

  Little icons left of the buff button show what each press casts. All of it is set before
  the pull. Flow's own key is unchanged for now: Shift + key still heals and Alt is still
  your potion. "Heals and potions on the buff button's key" in Flow Settings turns the new
  presses off; `/flow carekeys` lists them. Not seen working in game yet.

## 0.35.205
- **No icons on quest mobs: your enemy nameplates are off.** The skull, the diamond and the
  count sit on nameplates, and the diagnostics showed none in view with the game's enemy
  nameplates switched off. Flow now says so once a session when a quest of yours wants mobs:
  press V, or type `/flow quest plates`.
- **"No known spot" stops.** Three kinds, each handled its own way:
  - *Inside a dungeon* (Testing an Enemy's Strength, the turn-in of Searching for the Lost
    Satchel): the row now says "in Ragefire Chasm" and why it isn't on your route.
  - *From battlegrounds* (Battle of Warsong Gulch): the row says "from battlegrounds".
  - *Quests with no place in the quest data* (the ones new to WoW: Forever, like Stalk With
    The Earthmother): Flow now learns the spot when you do the objective or hand the quest
    in, and uses it the next time that quest is in a log (any of your characters).
    `/flow spots` lists what it has learned. Until someone has done it once, it still reads
    "no known spot".
  - "Make Strider Stew: buy the recipe first" no longer says "buy" for a recipe you own:
    "the recipe is in your bank: learn it at Cooking 50".
- **The easy key follows your form in a fight.** Pull as a caster, go Bear Form, and the key
  casts Maul and Ctrl + key Demoralizing Roar (Swipe once you have it); back out of the form
  and they are Wrath and Moonfire again. The game does the switch itself, from a list Flow
  hands it before each pull. Shift, Alt and Ctrl + Shift keep what they had at the pull.
  "The key follows your form in a fight" in Flow Settings turns it off; `/flow key test`
  shows what each form is given. Not seen working in game yet.
- **Druid caster keys:** Moonfire is on Ctrl + key now and Entangling Roots on
  Ctrl + Shift + key (the key still opens with Roots before the pull).
- **Regrowth isn't suggested again while it's still healing you** (21 s). Hit a lot in a
  fight, Flow asks for another heal instead (Healing Touch).
- For route checks: `tools\route-check.ps1` now lists every stop Flow can't place, sorted
  into expected ones (a dungeon, a battleground, waiting for another step) and ones to fix.

## 0.35.204
- **Map numbers keep their distance.** A stop's number used to sit right against its point
  even when that put it on top of another number or point. Now it keeps a little room from
  everything else, and where there's none by the point it moves one or two steps further
  out, with a thin line back to its point.
- **Point at a stop in a list, see only that stop.** With the map open, hovering a row in the
  Flow Router or the Flow Tracker hides the rest of the route: that stop shows with its
  area, and the stop before and the stop after stay as muted points joined to it, so you
  see how the route gets there. Hovering a point on the map itself leaves the map as it is.
  The highlighted point is smaller: it fills the point instead of covering its neighbours.
- **"Select in quest log", second click.** The first click opens the log with the quest
  selected (as before). With the log open, a click on the link now goes to the quest's own
  line in the game's list, which opens the quest's details. Not seen working in game yet.
- **For "this mob has no icon":** `/flow quest` (and the diagnostics) now list every
  nameplate in view with the marks it got, who Flow thinks drops each item, and whether
  markers and enemy nameplates are on. A marker that fails says why in the log.

## 0.35.203
- **A recipe in your bank isn't bought again.** Flow Banker put a bought recipe in the bank,
  and the route then asked to buy it once more. Recipes now stay in your bags, and one that is
  already in the bank counts as yours: nothing happens until your skill can learn it, then
  the route says "Bank: take out ...".
- **Flow Banker anywhere.** Its window has three views now: "To put away" (as before), "In
  your bank" (what Flow saw there the last time the bank was open, with how long ago) and
  "Auction prices" (the cheapest buyout Flow last saw for each item). The mouse wheel
  scrolls. A "Flow Banker" tab on your bags opens it; `/flow banker bank` and
  `/flow banker prices` too.
- **A flight master with no flight path for you yet is tried again later.** Flow dropped
  such a stop for good; some only fly you after a quest or event. Flow can't see which, so
  the stop now comes back each time you gain a level, until their flight map opens.

## 0.35.202
- **Auction prices on WoW: Forever.** This client only has the newer auction house, which
  Flow couldn't read, so it knew no prices. Opening the auction house now starts two things:
  a read of the whole list where the client allows it (about once in 15 minutes), and a
  price lookup for each tradeable item in your bags and on your watch list, one search at a
  time. Flow says in chat how many it priced; the prices feed "auction or vendor" in the
  Flow Seller and bag icons. Which auction calls the client has is logged for the
  diagnostics. Not seen working in game yet when this was written.

## 0.35.201
- **Flow no longer asks you to sit by every campfire.** The camp-buff step is off unless you
  tick "Sit by a campfire for the camp buffs" in Flow Settings (Your easy key).
- **Someone with no flight path for you isn't a flight path stop.** Flow took Seikwa for a
  flight master and sent you there. When you talk to such an NPC and no flight map opens,
  Flow says so, drops the stop and doesn't offer it again.
- **Point at a row of the Flow Tracker with the map open** and its stop lights up on the
  map, as it does from the Flow Router.
- **Flow Banker moves with Ctrl-drag**, and stays where you put it.
- Fixed two self-tests that the new bank and flight path kinds broke; "quests only" routes
  leave those two kinds out.

## 0.35.200
- **Flow Banker.** At a bank, a Flow Banker window lists what you won't need soon: profession
  materials, trade goods you told Flow never to sell and recipes waiting for skill, when no
  stop on your route uses them. "Deposit" puts them in, a stack at a time; nothing moves
  until you click. Quest items, tools, food, water, bandages, potions and gear always stay
  with you. With four or more stacks to put away (or two with your bags nearly full), the
  route gets "Bank: put N stacks away" when a banker is close to the way you're going (its
  own tick under Route includes). `/flow banker` lists them; `/flow banker on|off`.
  Not built yet: fetching things back as a stop before the crafting that needs them.

## 0.35.199
- **Before you leave a zone, Flow says what's still to train or level there.** When your
  next stop is in another zone, chat lists, once, what Flow Improvements still has about
  training and professions: spells to train, professions behind your level, a tier to buy.
  It tells you; it doesn't hold the route back.
- The tag for the modifier you hold ("CTRL+", "SHIFT+") is on the same line as the key's
  bind, just left of it, in the same size: "SHIFT+ MB5 / Q".

## 0.35.198
Found by running the new route check (`tools\route-check.ps1`) on a real route: Flow's 30
stops came to 31,663 yards where the shortest order was 19,599.
- **Full bags no longer send you to Moonglade.** A druid's Teleport: Moonglade counts as
  "one cast away", so with bags full the nearest merchant was the one in Nighthaven, 10,000
  yards from everything else, and the route went there and back. A spot reached only by a
  travel spell is now left out when the same errand (a merchant, a trainer, a mailbox) can
  be run on foot. A stop that is only there, like the class quest, is still a cast away.
- **Flight paths to learn as you pass.** Five flight masters stood within 160 yards of that
  route and none was a stop. The route now has "Learn the flight path: <name>" for each
  flight master whose path you don't have, taken only when it's close to the way you're
  going anyway. It's its own kind of stop ("Flight paths to learn" under Route includes).
  Flow counts a path as learned once you've opened that master's flight map.
- **The arrow says when your hearthstone is clearly quicker**: "... Hearthstone (Thunder
  Bluff) is about 4 min quicker", beside the distance. The estimate was only in the arrow's
  panel. Flow still never uses the stone for you.
- The route check reads exports from the first version of the format too.

## 0.35.197
- **After a fight: eat and drink in one sit, or bandage when that covers it.** The key
  followed your recovery order whatever your mana was, and a drink came only when you were
  nearly empty. Now:
  - When you'll sit to drink (low on mana, or you've cast three or more spells and carry a
    drink), **food comes before the bandage**, even when you're only a little hurt, and the
    **drink is offered the moment you're eating**: one press for food, the next for water.
  - When no drink is needed and **a bandage covers what you're missing**, the bandage comes
    first: eight seconds standing, not thirty sitting.
  - Otherwise your own order, as before.
  The game hides your mana here, so "spent" is counted in casts: each cast that costs mana
  adds one; out of a fight one comes back every 12 seconds, drinking one every 3. "After a
  fight: eat and drink in one sit..." in Flow Settings (Your easy key) turns it off.

## 0.35.196
- **A second opinion on the route.** `/flow export` (and every diagnostics snapshot) now
  writes your quests and their objectives, your professions, every stop Flow knows of (on
  the route, locked or hidden, with where it is and what it waits for), the route in order,
  your flight paths, the flight masters around, and Flow Improvements, as lines a script
  can read. `tools\route-check.ps1` reads them, plans the shortest walk through the same
  stops by itself, and reports where Flow's order differs and by how many yards, what one
  use of your hearthstone would save, and what isn't on the route at all: quests in your log
  with no stop, flight paths you pass without learning, improvements with nowhere to go.
  For developers and for Claude: see CLAUDE.md.

## 0.35.195
- **The arrow no longer points the wrong way for a while and then flips.** Since 0.35.172
  the arrow follows trails you've walked by default, and a trail up to half again as long as
  the straight line can set off well to one side, or back to its nearest point, before it
  bends round. In open country that looked like an arrow pointing the wrong way, until you
  walked far enough off the trail for Flow to drop it. A trail is now followed only while
  it heads within 60 degrees of where the stop is; otherwise the arrow points straight at
  the stop. Trails into caves are kept whatever their heading. Flow notes in its log each
  time it turns a trail down, so this can be checked.

## 0.35.194
- **The suggested spell on a modifier of its own: Ctrl + Shift + your key.** When Flow
  advised something your key couldn't cast mid-fight, it was a little icon in the corner
  of the big one, to find and press on your action bar. There is now a fourth small icon
  in the row left of the big one, marked **C+S**: Ctrl and Shift together, plus your key,
  cast it. It holds the fight's next most likely spell that no other press already casts
  (for a druid caster with a potion on Alt: Nature's Grasp; without one, Moonfire), and it
  pulses when that's what Flow advises, so you can see which keys to hold. Like the other
  three it's set before the pull and stays for the fight; something on none of the presses
  still shows in the corner and glows on your bar. Hold Ctrl + Shift out of a fight to see
  it on the big icon.
- The "drag to move, wheel to resize" note that shows while you hold Ctrl is now below
  the button and its text, small and faint (it brightens when the mouse is on the handle).
  It used to flash above the button, over the key's name, at every Ctrl + key.

## 0.35.193
- **A friendly player targeted: your buffs, then a heal.** Out of a fight of your own, with
  a living friendly player targeted (in your group or not), your key casts your buffs for
  others on them: a druid's Mark of the Wild, then Thorns. With those on, the key becomes a
  heal when they're hurt; hurt and in a fight, the heal comes before the buffs. Where the
  game hides their health (it may, as it hides yours), Flow heals them while they're in a
  fight, and otherwise puts one heal over time on them and stops. Not in a city or inn.
  Mana sense: buffs for others only with half your mana or more, heals with a quarter. A
  tick in Flow Settings (In a group) turns it off.
- **Nature's Grasp when it's on you.** A melee mob that is on you and has just hit you (or
  swung and missed): Flow advises Nature's Grasp, ahead of Entangling Roots, because Roots
  is a cast and gets pushed back under blows. Entangling Roots stays the advice for a mob
  still on its way. Only with mana left to cast after it. In a fight your key can't change,
  so it shows in the corner of the icon and glows on your action bar; when you carry no
  healing potion or healthstone, Alt + key casts it.
- **Skinning only when it can be done.** The key offers to skin only a corpse that has been
  emptied (you opened it, or the game says nothing on it is yours) and is within reach
  (about 10 yards).
- The tag that names the modifier you're holding ("SHIFT+") is on the left again, right
  above the modifier names.

## 0.35.192
- Fixed a self-test that 0.35.189 broke (the Flow Tracker's title now stops at the locked
  count, which stops at the +/- button: the test still looked for the old arrangement).
- The log no longer says "the button did NOT get the click" after Ctrl, Shift or Alt + your
  key: those presses do reach the button (the line above it said what they cast), they just
  weren't counted.

## 0.35.191
- **The easy button skins.** After you've looted a kill, with its corpse still targeted, the
  key skins it: when the game writes "Skinnable" on the corpse and you have Skinning with
  the skill for it (red means too low: then it isn't offered). Loot first, then skin, one
  press each, walking up as for looting. The same is read for corpses that Herbalism,
  Mining or Engineering gather from, on game versions that have those. "The Flow key skins
  a looted corpse" in Flow Settings (Loot and selling) turns it off.
- **The easy button raises a dead friend.** With a dead player targeted, out of a fight,
  the key casts your resurrection on them (a druid's Revive, Resurrection, Redemption,
  Ancestral Spirit). Not on someone who has released. A tick in Flow Settings (In a group)
  turns it off.

## 0.35.190
- **A Flow Talents tab on the game's talent window.** Flow already put a small button in
  that window's title bar, and the game reported it there, but it wasn't being seen. It's
  now a tab standing on top of the window, near its right end, with a gold outline and
  bigger letters, where nothing of the window can cover it; click it for Flow Talents (what
  to take now, and at each level). It's also put on every kind of talent window the client
  has, in case the one you open isn't the one Flow picked. The same goes for the tabs on
  the spellbook (Flow Key Bindings), the profession window (Flow Professions) and the
  character window (Flow Improvements). The first time one shows, Flow notes where in its log.

## 0.35.189
- The Flow Tracker's title showed "|..." in place of its lock while the route was being
  worked out ("updating route..." left no room, and the cut went through the lock's picture
  code). The lock and its number now have a place of their own beside the +/- button, and
  only the title's words are ever shortened.

## 0.35.188
- **The easy button's modifier icons run out to the left.** The CTRL, SHIFT and ALT icons
  used to run off to the right of the big icon; they now run to its left, CTRL nearest. The
  crossed swords for auto attack moved from the left to the right of the big icon, and the
  "SHIFT+" tag you see while holding a modifier sits above the icon's right corner, clear
  of both.

## 0.35.187
- **The easy button uses the quest's item.** Standing at a quest's stop, out of a fight and
  with no enemy targeted, your Flow key uses the item the quest gave you (the totem at the
  well, the dust at the stone): the same item that sits on the quest's row in the Flow
  Tracker. Not at the quest's turn-in, not while mounted, and with an enemy targeted the key
  stays with the fight (click the icon in the Flow Tracker for an item you use on an enemy).
  "The Flow key uses a quest's item at its stop" in Flow Settings (Quests) turns it off.

## 0.35.186
- The Flow Tracker's title showed its locked stops as "9...": "9 blocked" didn't fit beside
  "1 here, 29 stops". It's now a small lock and the number, and the title's tooltip says
  what the lock means.

## 0.35.185
- **The quest's item on its Flow Tracker row: click to use it.** A quest that hands you
  something to use (a totem for a well, dust for a stone) shows that item's icon at the
  right end of its row in the Flow Tracker. Click the icon and the item is used; hover it
  for the item's tooltip. Flow takes the game's own "quest item" for the quest where the
  client has one, else the item the quest data (Questie) says the quest gives you, when
  it's in your bags and has a use. The icon can only be placed out of a fight (the game's
  rule for anything that uses an item): one that should appear or go during a fight does so
  when the fight ends. `/flow questitems` lists what Flow found.

## 0.35.184
- **A lift is learned going down too.** Flow only learned a way between maps when you rode
  INTO a walled place. A druid who flew into Thunder Bluff and rode the lift down had taught
  it nothing, and it still knew no way up. A lift ride now counts in either direction (the
  rim, a jump off the edge and a city wall still don't).
- **The "Waypoint" tooltip no longer covers the spot you're about to click.** It sits down
  and to the right of the cursor and follows it.

## 0.35.183
- **Flow Improvements: a link icon and a hide icon on every row.** The link icon, or a click
  on the row, opens what the improvement is about: for a stop, its card (where it is, "Go
  here next", "Point the arrow here"). The hide icon puts the row under Hidden; a click on
  the row no longer hides it.
- **Improvements lead you there.** Training leads to your class trainer even while the route
  has that stop locked (not enough money yet) or you've hidden it; a class quest leads to
  its giver, or to its next step when it's in your log. And a spell that waits for another
  ("Maul: after Bear Form") now links to where that other one comes from: the Bear Form
  quest's stop. A stop with no known place says why in chat.

## 0.35.182
- **The Flow menu, tidied.** Every Flow menu (the arrow's, the Flow Tracker's, a stop's, the
  Flow Router's Route button) now has the same sections in the same order, each one a row
  that pops out: **Order**, **Route includes**, **Go to the nearest...**, **Your waypoint**,
  **Dungeons**, **Party**, **Stops on the map**, **Arrow**, **Keys**, **Extras**, **Flow
  windows**. Nothing is loose at the bottom any more (two rows used to be called "More"),
  and nothing is listed twice (the faint profession arrow was). "Unhide all stops" is under
  Route includes, the arrow's look is its own section in every menu, and Flow Settings, Flow
  Improvements, Flow Professions and Flow Setup open from Flow windows. A section that is
  one switch says "on" or "off" beside its name.
- **Text-to-speech has a switch you can find.** NPCs reading their words aloud is Flow's
  "Spoken" extra; it was only in Flow Settings, under "Bonus mode". It's now a tick in every
  Flow menu: Extras > "NPCs read their words aloud (text-to-speech)". Flow Settings names it
  text-to-speech too, and `/flow bonus off` still turns all extras off.
- **Flight paths are ways between maps too.** `/flow gates` now lists the flight paths Flow
  knows and the people who carry you (the druids' flight masters), beside the ways on foot.
  And for a walled place with no way known on foot (you flew into Thunder Bluff, so Flow
  knew no way out): when flying from a flight master you know gets you nearer your stop,
  that flight master is the way. The arrow leads there and says where to fly. Flow learns
  flight paths when you open a flight master's map.

## 0.35.181
- The intro on the arrow after a login or /reload said "no quest database" while Questie was
  installed and still starting up. It now says "Questie starting up" then, "Questie linked"
  once Flow can read it, and "no quest database" only when there is none.

## 0.35.180
- **On a flight, the arrow tells you about the flight.** You can't steer in the air, so its
  two lines become "Flying to Thunder Bluff" and "landing in ~2m 10s, then: Train 1 spell(s)
  at your class trainer". It did some of this for flights taken from a flight map, but a
  flight that starts with a word to someone (the druids' ride out of Moonglade) wasn't seen
  as a flight at all: the arrow showed the walking time (11 minutes, in the air). Flow now
  notices any flight, takes where it lands from the ride you were standing by, times it the
  first time and counts down from then on. A /reload in the air keeps the flight.
- **Flow Improvements: one line an entry.** In the button's tooltip a long entry wrapped
  under its number. Each numbered entry now stays on one line, the tooltip may grow to
  twice its usual width for it, and one longer still ends in "..." (the list has it whole).
  The list itself also widens for its longest row, up to twice its usual width.

## 0.35.179
- **No crack in the beam.** Standing on a waypoint, the light through the ring is one picture
  drawn upright and again mirrored below it, and a thin dark line showed where the two met
  (the picture has a see-through row round its edge). Both now end on the picture's
  brightest row, so they meet with nothing between.
- **The easy button's key is written above it**, the way CTRL, SHIFT and ALT are above the
  smaller icons beside it. It used to sit in the corner of the icon, over the spell's picture.
- **"Waypoint".** Holding Ctrl over the world map turns the cursor into the map pin (a click
  sets your waypoint): that stays as it is, and the first two times a tooltip at the cursor
  says "Waypoint".
- **Menus:** the "Go to the nearest (your waypoint)" section is now "Go to the nearest...",
  and "Shortest path" (the default) is listed above "Most XP first", in the menus and in the
  Flow Router.
- For developers: `tools\look.ps1` saves a picture of the game's window (only that window),
  so Claude can check how something looks while you play. See CLAUDE.md.

## 0.35.178
- **The way back from Moonglade.** "How do I get back now? Where do I go from Moonglade?"
  Flow knew the way in (Teleport: Moonglade) and no way out, so the arrow pointed across all
  of Kalimdor. The way out is a person: Bunthen Plainswind (Horde) and Silva Fil'naveth
  (Alliance) fly druids home for free. While a druid is in Moonglade and the next stop is
  outside it, the arrow now leads to them and says so ("140 yd to Bunthen Plainswind: he
  flies druids to Thunder Bluff, free"), the panel says the same, the map's path ends at
  them, and the route counts the flight, so what's in Thunder Bluff comes next. A stop next
  door (Felwood) is still walked. `/flow rides` lists them; more can be registered
  (`ns:Register("ride", ...)`).
- **Set your hearthstone, in the right place, before you leave.**
  - Only Alliance inns were listed, so a Horde character never got the "Set hearthstone"
    stop at all. Thunder Bluff, Bloodhoof Village, Orgrimmar, Razor Hill, the Crossroads,
    Camp Taurajo, Brill, Undercity, the Sepulcher and Sun Rock Retreat are in now, with
    Stormwind, Ironforge, Darnassus and five more Alliance towns.
  - **A city beats a village.** In Thunder Bluff with your home in Bloodhoof Village, the
    route gets "Set hearthstone: Innkeeper Pala (Thunder Bluff)" as you arrive. Walking back
    down into Mulgore doesn't offer Bloodhoof Village again; a town far from your city (the
    Crossroads) is still offered when you get there.
  - **Home first, then the trip.** A stop that's a teleport away (Moonglade) waits for the
    "Set hearthstone" stop where you are. Hide that stop and nothing waits.
  - The arrow's panel says when your hearthstone then a run is clearly the quicker way to
    the next stop (an estimate: Flow never uses it for you), and `/flow nav why` says where
    your home is and whether the stone is ready.

## 0.35.177
- **Flow's right-click menus fold.** The menu on a stop, the arrow, the Flow Tracker and the
  rest used to be one long list. Now the part about the thing you clicked is open as before,
  and each section after it (Order, Route includes, Arrow, ...) is one row that says what
  it's set to ("Order  Shortest path", "Route includes  4 of 6"). Point at the row, or click
  it, and its entries pop out beside the menu. Ticks you set in a pop-out keep it open.
- **The easy button suggests a drink again.** It never did, with water in the bags. Two
  things could cause that and the saved data can't say which, so both are covered: where the
  game hides your mana (as it hides your health here) Flow now counts you as low when one of
  your heals is out of reach, and a drink is recognised by any "restores ... mana" wording
  (a fraction in the number was enough to miss it) or by its use being the Drink spell.
  `/flow rot why` has a new "Drink:" line that says which it was: your mana as the game
  reports it, whether a heal is out of reach, and which drink Flow would take.
- **Locked stops say why in a few words.** "Flow doesn't know where: Questie has no spot for
  Fish Chunks. Your quest log says how." ran out of the Flow Router and across the quest log
  beside it, once for every such quest. The row now says "no known spot" (or "no known
  seller", "needs a Mining Pick", ...), the reason's column can't grow past its share of the Router,
  and the whole sentence is in the stop's tooltip and in chat when you click the row.
  These stops are quests with no place on the world map that Flow can read: a dungeon
  (Ragefire Chasm), a battleground, something you craft, or one of WoW: Forever's own quests.

## 0.35.176
- **The next profession tier waits until you can pay for it.** Third and, this time, checked
  answer to "Journeyman Skinning ... I don't have it, but it is taking me there". Flow read
  the trainer's own line today: Journeyman asks for skill 50 and no level, and costs 5 silver.
  The skill was there (58); the 5 silver wasn't (2s 30c); and the stop had no price, so the
  route sent you to a trainer you couldn't pay. The stop now carries the tier's price (what
  that trainer, or any profession's trainer, charged for it; 5 silver for Journeyman until
  seen), and the route skips it until you have the money, as it does for your class trainer.
  0.35.173 blamed the profession list and 0.35.174 a level rule; both were wrong.
- **Leaner bags**, from going through a druid's 40 slots:
  - **No auction price known: to a vendor.** Green gear and better materials you have no use
    for used to be held with the auction house mark. They go there now only on a price Flow
    has seen that beats the vendor after the house's cut and the listing fee (a listing that
    doesn't sell costs the fee); with no price known they're sold to a vendor. Rare (blue)
    tradeable gear is still never vendored unseen. "Sell what has no auction price" in Flow
    Settings (Loot and selling) turns this off.
  - **Ammunition your class can't shoot** (bullets in a druid's bags) is sold.
  - **Spell reagents of other classes** (a Light Feather is a mage's and a priest's) are sold.

## 0.35.175
- **Bear Form: the class quest in your log comes first.** "Moonglade" was in the log, but
  its stop is at the far end of Kalimdor, so the route left it for last and the Flow Tracker
  never sent you. A class quest that leads to a spell you don't have is now a milestone: it
  isn't put off for being far or in another zone. And a druid's **Teleport: Moonglade**
  counts as travel: a stop in Moonglade is one cast away, the arrow says "cast Teleport:
  Moonglade", and its panel says so too (or, if you don't know the spell yet, where it comes
  from). Other travel spells: `ns:Register("travelSpell", ...)`.
- **Thunder Bluff's lifts, not its rim.** Walking along the edge of the bluff the game's map
  flips between Mulgore and Thunder Bluff, and Flow took each flip for a way up: four in
  twenty minutes, on a mesa with two lifts. A way into Thunder Bluff is now learned only when
  you stood still as the map changed (a lift carried you). The ones learned before are
  forgotten: ride a lift up once more.

## 0.35.174
- **A quest in your log is always on your route.** Thunderhorn Cleansing and Stalk With The
  Earthmother were in the log but not on the route: Flow dropped any objective it had no place
  for. Now: an objective that's "do this at a place" (Cleanse the Thunderhorn Water Well) is
  a stop at the place the quest data has for it; one the quest data has no place for goes to
  the game's own marker for the quest when the game has one; and where neither knows, it's on
  the list with a lock and the reason ("Flow doesn't know where: no spot for Pine Salve. Your
  quest log says how"), instead of not being there at all. The same for a finished quest with
  nowhere known to hand it in, and for a quest the quest data doesn't have.
- **The class quest for a spell is always a stop.** Flow Improvements said "Get Bear Form
  (class quest)" while the route never went there: the quests to pick up are chosen by zone
  and level, and a class quest can fall outside both. The part of the chain you can pick up
  now is worked out on its own and always put on the route ("Accept: Heeding the Call (Bear
  Form)"), and the improvement names the quest and links to that stop. `/flow nav why` says
  where each class quest stands.
- **Upgrades at vendors.** Gear a vendor sells carries the same badge as your bags and quest
  rewards: per spec, a green arrow up (better than what that spec wears), a red one down, or
  a dash. When something for sale is better for the spec you level as, Flow says so once in
  chat with the price.
- **Profession tiers: the trainer's word decides.** Flow now reads what a profession trainer
  says about the next tier each time you open one (the level and skill it asks for, the
  price, whether you can learn it) and goes by that. (This entry first said WoW: Forever asks
  for more than classic's skill 50 for Journeyman. It doesn't: see 0.35.176.)
- **Click bindings: a false alarm fixed.** 0.35.171's check expected the buttons under other
  names and called a working left and right click dead (also in Flow Improvements). Your
  click bindings are the game's defaults; that wasn't why party frames ignored clicks.

## 0.35.173
- **Professions are read from every list the game has**, not only its two profession slots:
  the slots, the trade skill lines and the profession's own spell, put together. A profession
  Flow can see you have but can't read the skill of is yours all the same: no trip to its
  trainer, and no skill-ups planned from a number it would have to make up. `/flow skills`
  shows what each part of the game reports (also in the diagnostics).
  (This was meant to stop the route sending a druid to the Skinning trainer too early. It
  wasn't the cause: the slots had Skinning all along. The real fix is in 0.35.174.)

## 0.35.172
- **The way up Thunder Bluff, and into the next zone.** The game gives add-ons no map of
  walkable ground and no heights, so a stop on the bluff and one at its foot looked a few
  yards apart and the arrow pointed through the cliff. Flow now learns the **ways between
  maps**: each time you walk (or ride a lift) from one map into another, the spot is kept, for
  all your characters. A stop in another part of the map then goes by the way you've used:
  the arrow leads to the lift ("by the way into Thunder Bluff"), then on; the route counts the
  ride, so everything on the bluff is done together instead of mixed with stops below; and
  the map's path bends through it. Capital cities are walled: where Flow doesn't know a way
  in yet, the arrow's panel says so, and one trip in teaches it. `/flow gates` lists them.
  (One ride up each lift after this update: Flow can't tell lifts from old trails.)
- **The dots follow the path.** On the world map the stretch from you to your next stop is
  drawn along the trail the arrow is following, through the gate or the cave's entrance, not
  as a straight line; later stretches bend through their gates and entrances too.
- **Trails you've walked are used by default** ("Arrow follows paths you've walked" was off
  unless ticked): round a cliff or along a road you've walked before, when that's at most half
  again as long as the straight line. Flow still has no terrain data: in places you've never
  been it points straight.
- **A recipe isn't bought long before you can learn it.** "Buy Recipe: Longjaw Mud Snapper"
  (it needs Cooking 50) was on the route at Cooking 32, and once bought Flow asked you to use
  a recipe the game wouldn't teach yet. A bought recipe now joins the route when your skill
  is within 10 points of it, and "use it" waits until you can.

## 0.35.171
- **Auto attack starts at the pull.** Casting at an enemy doesn't turn your auto attack on in
  WoW: Forever, and your key can't change once the fight is on, so a caster never swung. Now,
  with a new enemy targeted and no fight yet, the first press of your key turns auto attack on
  (instant, the game's own Start Attack: on, never off) and your opener comes with the next
  press. If two presses don't start it, Flow lets it go and shows your opener. Off: "Start
  auto attack at the pull" in Flow Settings (Your easy key). While it's on and the enemy is
  out of reach the game may say "You are too far away". One enemy can be left out:
  `ns:Register("noAutoAttack", "<its name>", { why = "..." })`.
- **The heal prompt clears when your health is full.** Your health is hidden from add-ons
  here, so Flow only counted down by the clock and could ask for a heal for a minute at a full
  bar. The game still says when your health changes: out of a fight, six seconds with no
  change means it's full, and the prompt goes.
- **"Show on map" and "Select in quest log" open the map** when it's closed. The game opens
  its own window (Flow passes your click to the zone name over the minimap, or the Quest Log
  button), so Flow's code still never runs the map. In a fight the links do what they did.
- **Clicking a party member does nothing?** `/flow clicks` lists what each mouse button does
  on unit frames (the game's Click Bindings). Binding a spell to the plain left or right
  button takes it from "Target" / "Open menu", and moving the spell to a modifier later
  doesn't give it back: the plain click is left with nothing. Flow says so (also in Flow
  Improvements) and where to fix it. `/flow under` says what's under the mouse.
- **`/flow inventory`**: every item in your bags with what Flow would do (sell, auction house,
  keep), why, which rule said so, the vendor price and the last auction price. Saved with the
  diagnostics, to go through the bags slot by slot.

## 0.35.170
- **The path on the world map moves.** Its dots drift slowly from each stop toward the next,
  so you can see which way the route goes. The game moves them, so it costs Flow nothing while
  they drift. "Path moves along the route" in Flow Settings turns it off (`/flow map move off`).
- **Path opacity**: a slider in Flow Settings (Finding your way), from barely there to solid.
  50% is the look it had (`/flow map opacity 10-100`).
- **Shortest path is the default route order** for a character that never chose one (it was
  Most XP first). Your own choice stays as it is.
- **Flow Settings are grouped by when you use them**, not by which part of Flow they belong
  to: Your easy key, In a group, Finding your way, Quests, Loot and selling, New spells and
  professions, On your screen, Just for fun. WoW's own settings (Flow's suggestions) stay
  apart, at the bottom. Nothing was removed; the ticks only moved.
- **Show WoW's quest tracker**: a tick in Flow Settings (On your screen) and in the Flow
  Tracker's right-click menu. With Questie's tracker off, the game's own came back at every
  /reload; unticked, Flow hides it and keeps it hidden. "Hide Questie's tracker" now reads
  "Show Questie's tracker", so both ticks say the same thing.
- **Flow buttons on WoW's windows**: a small button in the title bar of the game's talent
  window opens Flow Talents; the spellbook has one for Flow Key Bindings, the profession
  window for Flow Professions, the character window for Flow Improvements. Nothing opens until
  you click. `/flow buttons` lists them; "Flow buttons on WoW's windows" in Flow Settings turns
  them off. (If one doesn't show on your client: open that window, type `/flow buttons`, and
  the window's name is in the diagnostics.)
- The "press audit" self-test failed on its second run in a session (it counted a press left
  over from its first); it now cleans up, and no longer writes to your log.
- For contributors: `docs/MERGING.md` is how pull requests are merged, with the list of what
  review keeps finding; CONTRIBUTING.md has the short version to check before sending one.

## 0.35.169
Fixes from the review of pull requests 18 to 22 (0.35.164 to 0.35.168):
- **Profession window:** the goal box shows only when there is something to make (it said
  "nothing to make here" with a dead "Make 0" beside the make-now list), and on a narrow
  profession window the lists sit under it instead of over it.
- **Cannibalize:** asking how far the corpse is goes through Flow's guarded check (the game
  forbids that question in a fight). With a corpse to eat, the other ways to heal up are still
  offered on Ctrl and Alt + key.
- **Buff button:** its "what's next" list read every buff of yours ten times a second, in
  fights too; now once a second, out of a fight.
- **Route planning with flights:** your speed and each pair of flight masters are worked out
  once a plan, not for every pair of spots; with fewer than two known flight masters the
  planner isn't asked at all.
- **Only the dungeon run** is a tick of its own under what the route includes (the three
  routes it sat with are ticks since 0.35.157), kept per character. A run you prepared no
  longer forces its "only if you pass by" quests to the front of the route.
- **Artisan Cooking, First Aid and Fishing** go on the route at skill 225, which their quests
  ask for, not 200. A capped profession whose trainer Flow can't place is listed with the
  reason instead of vanishing.
- **Guides:** Thorium needs Mining 245 (not 230). Cooking 225 to 250 goes through Monster
  Omelet and Tender Wolf Steak again. The enchanting rods are named, count when they carry
  another item number on this client, and no longer ask for a Blacksmithing stop nobody plans.
- Self-tests: one called an item function Forever doesn't have (so it failed at every login),
  one only held on an English client.

## 0.35.168
- **Profession guides: Tailoring, Leatherworking, Alchemy, Enchanting and Engineering, 1-300.** Each follows
  the cheapest levelling route: trainer recipes plus the fewest bought patterns (Runecloth Gloves; Wicked
  Leather Gauntlets and Runic Leather Headband; Superior Mana and Major Healing Potion; the Enchanting formulas
  for Minor Agility, Lesser Strength, Lesser Mana Oil, Greater Stamina and Superior Defense; the Thorium Widget
  and Thorium Tube schematics), with vendor prices for the thread, dye, vials and rods they need. Herbs come
  from Herbalism nodes; cloth, leather and enchanting dust show as Auction House buys. Enchants say which rod
  they need and Engineering says when you need the Arclight Spanner; an engineer's Blacksmith Hammer is kept.
  The Artisan trainer is the one each profession really uses (Annora in Uldaman for Enchanting).
  (Thanks, BIMpossible: pull request 22.)

## 0.35.167
- **Profession guides: the recipes to 300.** Cooking now goes past 225 with the bought Artisan recipes the
  levelling guides use (Monster Omelet, Tender Wolf Steak, Spotted Yellowtail, then Nightfin Soup, Sunscale
  Salmon, Mightfish Steak, Lobster Stew and Baked Salmon), with their vendor prices and the fish they need.
  Blacksmithing 265-300 is Imperial Plate: its plans are quest rewards, so the stop says to accept Derotain
  Mudsipper's quest in Gadgetzan (and why) instead of "buy". Thorium Bars smelt from Thorium Ore, and Mining
  knows the Mithril and Thorium skill colours. The last three bandages are learned from your side's Triage
  doctor, not the city trainer.
  (Thanks, BIMpossible: pull request 21.)

## 0.35.166
- **Dungeon key: the quests and the route show.** The run's tooltip, its menu and the "Prepare" chat line now
  list each quest: what to pick up, who gives it and in which zone, the lead-ins, the ones in your log and the
  ones that start inside. Once you prepare a run, the route goes to the pickups first and then to the entrance
  (the entrance used to show only once every pickup was in your log, so the route never said where the run
  went). A giver Questie can't place is named on the entrance stop.
- **Route: Dungeon run.** A fourth choice next to Quests only / Optimal / Completionist in the Route menu (and
  "Route: only this run" in a run's own menu): the route holds only that run's stops: its quest givers, the
  objectives and turn-ins of its quests in your log, then the entrance. The run's quest givers on the other
  continent now get pins on that continent's map and rows in the Flow Router marked with where they are, and
  when nothing is left on your side the arrow says how to cross (zeppelin or boat). Picking another route or
  cancelling the run turns it off.
- **Travel time, flights counted.** When a stop can be done at more than one spot (a forge, an anvil, a cooking
  fire, a trainer), Flow picks the one quickest to reach, counting the flight paths you know, not the one
  closest in a straight line. Every forge and anvil you've used and every Blacksmithing and Cooking trainer's
  is now a choice. Smelting no longer counts for half, so the plan doesn't send you far out to smelt.
- **Cannibalize.** Undead: after a fight, hurt, with a dead humanoid or undead targeted close by, the buff button
  and the Flow key show Cannibalize before food or a bandage (turn it off in Buff items).
- **No heals above 80% health.** The buff button and the Flow key no longer suggest food or a bandage
  to heal while you're above 80% health.
- **No learn tips for professions you don't have.** Recipes and patterns for a profession you lack, or need
  more skill than you have, are no longer offered as "Learn" in your bags.
  (Thanks, BIMpossible: pull request 20.)

## 0.35.165
- **Professions: training goes on the route, and plans stop at your cap.** The next tier (Journeyman, Expert,
  Artisan) is now a route stop from 25 points below your cap, as soon as your level allows, for every
  profession you have. Cooking, First Aid and Fishing get their Expert book (buy it, then read it) and their
  Artisan quest instead of a trainer. The skill plan no longer plans past your cap: Cooking 62 of 75 plans to
  75, then "Train Journeyman Cooking", instead of buying 45 apples for points you can't get yet. Vendors of the
  other faction are no longer picked for a "Buy" stop.
- **Quests: more checks before planning a pickup.** Flow now leaves out quests over their highest level, parts
  of a quest you aren't on, breadcrumbs for a quest you're already on or past, quests Questie marks as never
  offered, and quests that need a reputation, profession skill or spell you don't have. Lead-in quests count
  as done as soon as the game says so, even before Flow's list has them.
- **Buff button: Well Fed food before a bandage.** Hurt after a fight and not Well Fed with the food for it in
  your bags: the button shows the food first, since one meal heals you and buffs you.
- **Well Fed food first.** Not Well Fed and carrying the food for it, the buff button and the Flow key show
  that food before elixirs, weapon stones, oils and your buff spells (it lasts longest, and you sit to eat).
- **Buff button: lure for your fishing pole.** With a fishing pole on and no lure on it, the buff button shows
  "Put <lure> on your pole", lit, anywhere (not only at a fishing stop). It picks the lure with the biggest
  bonus you carry and can use first, the smallest last. Healing up after a fight still comes first. At a
  fishing stop without your pole on, the button shows "Equip your Fishing Pole" (your weapons go back on when
  you leave, as with the Flow key). Then it casts your line, and with a buff key set (/flow buffkey Q), that
  key reels in while the line is out: press it when the bobber splashes.
- **Professions: follow the levelling guides' path.** The skill plan now makes what the public levelling guides
  make at each skill, instead of grinding one recipe on until it turns grey (Cooking 62 no longer says 105
  Charred Wolf Meat). Cooking has a Horde path (Kodo, Strider Stew, Lizard Tail) and an Alliance path (Bear
  Meat, Crab, Wolf Kabob) to 130, then Omelet and Roast Raptor to 225; fish you catch stand in for the meat
  they match. First Aid runs to 300, Blacksmithing to 270. Recipes sold by a vendor get a "Buy" stop, and the
  plan and profession window say when the guides switch recipe. Recipes only a quest teaches are left out.
- **Buff button: shows your next buff ahead of time.** Out of combat the blue buff button now always shows the
  next buff it would do (a missing aura or blessing, your stone or oil, buff food), faded, so you can use it
  when you choose. It lights up only when a fight is near: an enemy targeted, a kill stop, or just after a fight.
  Your bandage or food when hurt and the campfire steps are faded the same way until then. Hover it for why.
  (Thanks, BIMpossible: pull request 19.)

## 0.35.164
- **Profession window: make-now list is honest about chance.** Orange rows say "sure skill points"; yellow and
  green say "maybe ... (not every time)", since a couple of yellows can give nothing. On the same number of
  whole points, the sure recipe now comes first.
- **Profession window: the goal gets its own box.** What Flow wants you to make next (with its materials and
  the Make button) now sits in its own box under the right side of the profession window, with a legendary
  orange border. The box under the left side keeps only the lists: make now from your bags, cheapest to buy,
  and the upgrades fold-out.
- **Map: a quieter next-stop marker.** The stop you're heading to on the world map is smaller (12 instead of 16)
  with a thin, faint white ring instead of a bold one.
- **Profession window: make now from your bags.** A new list above the cheapest one shows the recipes your bags
  can make right now that still give skill, most skill points first, with how many you can make.
- **Profession window: cheapest recipes for a skill point.** Under the profession window Flow now lists the
  three recipes that cost the least in materials for each skill point, cheapest first. Costs come from auction
  prices Flow has seen, then vendor prices. Hover a row for its materials; click it to show that recipe.
  (Thanks, BIMpossible: pull request 18.)

## 0.35.163
- **Fixed a blocked action** ("Flow has been blocked from an action only available to the
  Blizzard UI"). The cast recorder asked the game how far your target was on every cast in a
  fight, also with a friend, yourself or nothing targeted, which the game forbids there. It now
  asks in a fight only about an enemy.
- **Press audit: does the key cast what the icon shows?** At every key press Flow notes what
  the icon showed, what the key was really set to cast, and what was cast. A press where the
  icon and the key disagree is kept, with a screenshot of that moment (`/flow audit`;
  `/flow audit shots off` for none). `/flow mark [note]` notes "it just happened" yourself.
- **Hit a lot in a fight: a heal that lands at once.** Flow advised Rejuvenation; you healed
  six times and each time with Healing Touch, and left 48 Rejuvenation prompts alone. A heal
  over twelve seconds doesn't answer being badly hurt, so the advice is now your quickest
  direct heal (Regrowth once trained, else Healing Touch), and Shift + key casts the same.
- **Druid caster: Entangling Roots on Ctrl + key** (Moonfire on Alt when no potion holds it).
  Roots is what Flow asks for most in your fights (18 times against Moonfire's once).
- **Flow Talents: "Take these points"** spends your unspent points on the gold talents, after
  you confirm. All or none: if the game refuses one, nothing is kept.
- **Every Flow window's X closes it in a fight too** (six windows used the game's own close
  handler, which can't close an add-on window in combat; Escape still worked).
- **Flow's buttons sit under the game's own windows** (game menu, Settings).
- **The arrival beam is mirrored below the ring**: it fades down as it fades up.
- The menu has "Show keys bound straight to spells"; `/flow test` isn't run in a fight.

## 0.35.162
- **The queue: four things on one key.** Right of the easy button, each a little smaller, are
  the three things your key casts with a modifier held, the modifier written above each:
  - **CTRL**: your second attack (Moonfire while the key casts Wrath; a cat's finisher; a
    bear's Swipe). Between fights it's the next way to heal up (food while the key bandages),
    or the shown heal or buff on a friend you target.
  - **SHIFT**: your quickest heal, on you.
  - **ALT**: your healthstone or healing potion. Without one, the spell that holds or stops
    your target (Entangling Roots, Bash, Hammer of Justice).
  Hold a modifier and the big icon becomes that spell, with a flash and "CTRL+" beside it. In a
  fight the game lets no add-on change a key, so all four are set at the pull and stay; the one
  Flow advises pulses gold, so "press Moonfire on your bar" is now "press Ctrl". Advice that's
  on none of the four still shows in the corner. They replace the "on deck" icons.
- **Why:** you play on the key. In one evening's combat log none of 221 casts was Moonfire,
  though Flow advised it all night, and in one death a heal was advised 65 times without
  Shift + key being pressed once.
- **Shift + key and Alt + key are set the way the game looks them up.** They were set in a way
  the game's own rules only find when no modifier is held; with Shift down, by those rules,
  the press falls through to the key's own spell (Wrath, not your heal). This comes from
  reading the rules, not from seeing it in play (the modifiers went unused): the next fights'
  diagnostics will show what each press cast.
- The diagnostics count Ctrl, Shift and Alt + key presses per fight, and `/flow key test` lists
  what each casts and is bound to.

## 0.35.161
- **A `/reload` is always enough.** WoW: Forever loads new files on `/reload` too (older WoW
  clients needed a restart for them). Checked by adding a file while the game ran: it loaded at
  the next `/reload`. Flow, its update message, its guides and its notes for AI assistants no
  longer say "restart WoW"; a self-test keeps watch in case that ever changes.

## 0.35.160
- **"Heal: SHIFT+" in gold beside the easy button** while Flow advises a heal in a fight and
  your key holds another spell. In your last death Flow advised a heal 65 times in 80 seconds
  and Shift + key, which casts it, was pressed 0 times: the small corner icon was too quiet.
- **The Well Fed countdown costs nothing while idle.** It read your buffs ten times a second
  whenever the easy button had nothing to show (0.9 ms a second since 0.35.156); now only
  from the moment the button shows Well Fed food until the buff lands.
- Self-tests: three heal tests failed when you reloaded as a ghost (a ghost is never advised a
  heal); they now wait until you're alive. The profession arrow's tests follow the new route
  ticks.

## 0.35.159
- **Flow learns from what you cast.** In every fight, each spell you cast is set beside what the
  easy button advised at that moment: cast as advised, your key while the advice was a spell
  on your bar, or your own pick. For the differences Flow notes the situation (moving, the
  enemy on you, the target far, hurt, low mana, the advice out of range or on cooldown...), and
  each fight remembers its choices, so fights with a choice can be set beside fights without
  it. `/flow choices` shows the tally: what you do differently, when, and what it did to kill
  speed. The rotation is then changed from that report, reason first, never as a blind copy.
- The diagnostics now keep that tally and what the fight profiler has learned (`/flow fights`).

## 0.35.158
- **Flow Talents** (`/flow talents`, or the "Spend N talent points" advice): your talent trees
  as the game has them, with Flow's levelling build laid over them. Gold is what to take with
  the points you have now; the line under it says what comes at each of your next levels; the
  title says where the build ends up. Hover a talent for the game's own text and why it's in
  the build. It's a reference to read beside the talent window: Flow never spends a point.
- **Druid build**: Improved Wrath first (you cast until Cat Form at 20), then down the Feral
  tree, Heart of the Wild after its last row: 5 / 41 / 5 at level 60. Other classes see their
  trees, without a build yet.
- **Unspent talent points are noticed on Forever.** The reminder and the advice read the old
  talent system's count, which this client doesn't have; they now read the game's own.
- The diagnostics now keep each talent's text and what it leads to, to check builds against.

## 0.35.157
- **Tick what your route includes.** The three routes (Quests only, Optimal, Completionist) and
  their Professions switch are now one tick each, in the route menu (the Flow Router's "Route:"
  dropdown, or right-click the arrow): **Current quests**, **New quests**, **Low-level quests**
  (grey ones too: the old Completionist), **Class trainer, weapon skills, riding**,
  **Professions** and **Repair, selling, hearthstone**. Tick any mix; **Select all** and **Clear
  all** do it in one click, and the menu stays open while you choose. Hover a tick to see what
  it covers. Your saved route moves over to the same ticks by itself.
- **Professions: on the route or on their own arrow**, right under the Professions tick ("on
  their own faint arrow"). It no longer needs the Optimal route.
- **Go to the nearest** repairer, vendor, flight master, innkeeper, mailbox or banker sits
  right under those ticks, one click each.
- **Fewer route refreshes.** The game's "quest log updated" event fires even when nothing in
  your log changed, and each one refreshed and re-planned the whole route (25 times in six
  minutes of play). Flow now refreshes only when a quest, a count or a completion really
  changed.
- `/flow nav include all|none|<kind> on|off` sets the ticks; `/flow nav quests|optimal|complete`
  still work.

## 0.35.156
- **The easy button comes up as soon as you target an enemy.** Too far for anything, it shows
  the spell you'd open with, tinted red and saying "Out of range", instead of staying hidden
  until you're close.
- **Well Fed countdown.** When the easy button gives you Well Fed food and you start eating, it
  counts down the 10 seconds to the buff in aqua ("Well Fed in 7"), so you know when you can
  stand up. It only shows; the key never eats a second one.

## 0.35.155
- **The quest log and the Flow Router are separate.** Each opens and closes with its own
  button, and both can be open at once: the Flow Router sits just right of the map, so right of
  the quest log, instead of covering it. The quest log key (L) no longer closes the Router. On
  a maximised map with no room on the right, the Router sits inside the map's right edge, left
  of the quest log.

## 0.35.154
- **No more waypoint on your character.** A "make it where you stand" stop (like "Make 1 x
  Charred Wolf Meat") follows you, but the world map pinned it where you stood when the route
  was last planned: right on you after each re-plan, or somewhere you'd left. It now gets no
  pin, area or line on the map; it's still listed in the Flow Router and Flow Tracker.
- **The Flow Tracker and Questie's tracker are separate.** Opening one no longer folds the
  other: either, both or neither can be open. (`/flow tracker flow|fold` opens or folds Flow's.)
- **The Flow Tracker's title no longer runs under its +/- button**: a long "N blocked" is cut
  short instead.
- **FLOW in the login spin is half see-through**, so the arrow shows through it.

## 0.35.153
- **The Flow key's biggest cost, gone.** Looking for quest NPCs to heal (like "Injured
  Deathguard healed") checked every stop of your route around you, ten times a second, even
  when no stop needed healing: 2.2 ms of work a second, more than choosing your spell. It now
  knows which stops need healing once per route (usually none) and checks only those. The
  "where you are" check skips stops whose spawns are nowhere near you, the same way the map
  does since 0.35.150.

## 0.35.152
- **Fewer route refreshes.** When the profession plan checks whether a craft would be a gear
  upgrade and the item doesn't exist on this client (item numbers differ on Forever), the
  game's "no such item" answer refreshed the whole route, and the refresh asked again. Such an
  item now simply counts as no upgrade. Since 0.35.130 the route has been refreshed about twice
  as often as before.
- **`/flow perf` says why the route refreshes.** Under "route: gather stops" it lists what asked
  for each refresh (a quest update, a skill change, money, the 30-second check...), how often,
  and what those refreshes cost; under "gather: skillplan", the time each profession's plan
  takes.

## 0.35.151
- **`/flow perf` says which Flow Action costs.** Flow Actions (the key's loot, equip, learn,
  fishing and crafting steps) turned out to be the easy button's biggest cost, about four times
  choosing the spell. Its row now lists the steps that took the most time, with each one's
  worst moment, so the next fix goes where the time is. The rotation's own row counts real
  ticks (ten a second) instead of every frame.

## 0.35.150
- **Flow uses less of your computer again.** Since 0.35.140 Flow had grown from about 9 to 12
  ms of work per second. The "in this area" check on the map and Flow Tracker now rules out an
  objective nowhere near you at once instead of checking its spawns one by one; whether you can
  farm a material in this zone is worked out once per route update instead of every time it's
  asked; and the easy button stops making two small throwaway functions ten times a second.
  `/flow perf` now times choosing the spell, Flow Actions and the status icons on their own
  lines, so the next slow spot shows exactly where it is.

## 0.35.149
- **Profession window: upgrades show their materials.** Flow now reads each recipe's materials on
  this client (it saved none before, so every upgrade said "open this window again"). Hover an
  upgrade for what it takes and what you have; click it to show that recipe in the profession
  window. Make works in the new-style window too, and hover text sits beside the panel instead
  of over its Make button. When your next skill-up recipe has nothing to make it from yet, the
  window names it and what to gather, and it updates as soon as the plan does (an upgrade you
  just made stops being asked for). (Thanks, BIMpossible: pull request 17.)

## 0.35.148
- **Quests an NPC doesn't give.** Questie lists some of Forever's own quests with nothing to
  do first (a second "Arugal's Folly", "Return to Quinn (Again)", "Wild Eyes"), so Flow sent you
  to accept them early. Now one talk with the giver is enough: if a quest you could take isn't
  among what they show, its stop goes for ten minutes, and for a day when it's missing again.
  It also counts when the NPC only takes a hand-in or opens one quest without a list. Quests you
  can't take yet (the next part of a chain, a higher level) are never judged. (Thanks,
  BIMpossible: pull request 16.)

## 0.35.147
- **Bandages, food and the campfire on the buff button** (when it's on: `/flow buffbutton on`).
  Hurt after a fight, the blue buff button offers your bandage or food; by a campfire, once the
  button has its own key (`/flow buffkey Q`), it places your camp objects and its key sits you
  down. The Flow key then keeps to the fight, loot and gathering. Your recovery order still
  holds: a heal spell on the Flow key waits while a bandage or food you put first is there.
  (Thanks, BIMpossible: pull request 13.)

## 0.35.146
- **Dungeon key: a gold key atop your quest list.** A dungeon run worth doing (or the one you
  prepared) shows as a gold key above the top-left corner of your quest list (Questie's, else the
  Flow Tracker), not as an icon above the Flow key. Hover it for why, click it to prepare the
  run. Restart WoW once: a new picture. (Thanks, BIMpossible: pull request 15.)

## 0.35.145
- **Professions: a switch of their own.** The route list is Quests only, Optimal and
  Completionist, with one "Professions" tick under them, instead of two "Optimal with / without
  professions" routes. (Thanks, BIMpossible: pull request 14.)

## 0.35.144
- Fixed three self-tests that failed at every login after 0.35.143: they expected the faint
  profession arrow on by default (it's off unless ticked now) and water not to count (the key
  drinks it since 0.35.136). The arrow-layout check now says its numbers when it fails.

## 0.35.143
- **A faint profession arrow (off unless you tick it).** Arrow menu or Flow Settings: "Faint
  profession arrow". With "Optimal with professions", profession stops (training, skill-ups,
  materials) get their own route and a long, narrow, smoked-glass arrow behind the main one,
  with the stop's name and travel time; the main arrow then only takes you to quests. Its stop has
  its own pin on the world map and dot on the minimap, with a dotted path. At that stop the
  Flow key still does the steps (open the profession, make the bars, fish, gather).
- **Profession materials from your bags, bank and smelting.** The plan counts what you carry and
  what the bank held when you last opened it (a bank stop says how sure Flow is), smelts ore into
  bars, and holds a craft back while its materials stop is off the route. A far bank is only
  worth it when it holds plenty (10 or more): otherwise Flow farms the material where you are.
- **Gear you can make that's an upgrade** for you shows on the profession window and its craft
  stop (while that profession is being raised).
- **Travel time**: the arrow, its drawer and the stop card say about how long it takes, by air when
  a flight is quicker (Flow learns flight masters and flight times as you fly), and when the next
  zone starts.
- **"Finish the area you're in first"** (Flow Settings, off by default): clear the stops around
  you before going the other way. Off, the arrow follows the shortest whole trip.
- (Thanks, BIMpossible: pull request 12's newer commits.)

## 0.35.142
- **Training waits for what it needs.** Demoralizing Roar, Maul, Growl and the other bear
  spells need Bear Form first, which a druid gets from a class quest, not the trainer (cat
  spells need Cat Form). Flow counted them as "to train" and sent you to the trainer for them.
  Now the training stop counts only what you can train now, lists the rest ("After Bear Form:
  Demoralizing Roar, Maul..."), and with the Bear Form quest on your route goes after it, so one
  trip trains everything. A spell that was red at the trainer for something other than your
  level waits too, instead of sending you back.
- **Stops in the right order, in general.** Any stop can now say what it needs first (a spell,
  a level, a quest, an item): it goes after the stop that provides it, marked "(after ...)", or
  waits with the reason when nothing on the route does. The town's errands no longer pull a
  stop ahead of what it waits for, and the planner brings in what a must-do stop waits for
  instead of dropping it.
- Restart WoW once: a new file.

## 0.35.141
- **New spells: one Flow Spells list.** Training several spells used to show a card for each,
  one at a time, every new one closing the last. Now they all go into one list: a row per spell
  with its icon (drag it to any bar slot) and Bar, Key and Skip buttons, plus **Place all on
  bar** for every one that isn't on a bar or a key yet. It stays while you use it, then closes
  by itself after half a minute.
- **`/flow keys`**: the keys that cast a spell directly rather than from a bar, and the Flow
  key's own. The game's Key Bindings window doesn't list spells bound to a key.
- `/flow help`: Ctrl moves things; what the corner of the easy button means.

## 0.35.140
- **The map and the arrow agree.**
  - "All objectives in this area" (the map and the Flow Tracker) now counts a stop when any
    place its mobs live is near you or your next stop, the way the arrow's "in the area" does.
    It went by the stop's one route spot, so wolves roaming right where you stand could be
    missing from the map while the arrow listed them under "Also here".
  - Your next stop shows every place its mobs live on the map, as the minimap does; later stops
    show the patch the route goes to.
  - The dotted trail breaks where a stop isn't shown, instead of a line from stop 2 to stop 5
    the route never walks.
  - "Point the arrow here", the stop card's distance and the cave note use the same spot as the
    arrow: the stop's route spot, or (off the route) its spawn nearest you, not the first one
    Flow happened to keep.

## 0.35.139
- **The arrow's drawer: click to open, X to close.** Click the arrow to open it; click the arrow
  again, or the X at its top right, to close it. The pin is gone (it stays open, following your
  stops and across a /reload, until you close it), and so are the pull tab, closing by clicking
  inside it, opening on hover, and the slide: it opens and closes at once.

## 0.35.138
- **Ctrl-drag moves things now, as in Questie** (it was Shift, which now shows what Shift +
  your key casts). The Flow key, the arrow and its drawer, the Flow Tracker, the buff button and
  every Flow window: hold Ctrl and drag. Ctrl + mouse wheel over the Flow key resizes it.
- **Hide Questie's tracker**: a Flow Settings tick box (and the Flow Tracker's right-click
  menu) turns Questie's own quest tracker off, using Questie's own setting, so your tracked
  quests are kept. The Flow Tracker then sits on its own.

## 0.35.137
- **The easy button shows what your key will cast.** In a fight WoW won't let the key change,
  so Flow sets it at the pull (Wrath, Maul, Claw...). The icon now shows that spell, what a
  press really does. A better spell the key can't switch to (Moonfire, War Stomp, Entangling
  Roots) shows in the bottom-right corner, marked "bar:": press it on your action bar, where it
  glows. When it's your heal, the corner says "Shift+" (Shift + key casts it). It used to be the
  other way round, which made the key look like it ignored the icon.
- **Hold Shift to see what Shift + key casts**: your heal swaps onto the icon, with a pulsing
  green "SHIFT+" beside it; let go and it swaps back.

## 0.35.136
- **The Flow key drinks too.** Out of a fight with no enemy targeted, at half your mana or
  less, it drinks your best water (also while you're eating: press again after the food).
  Right-click the Flow key: "Drink when low on mana" turns it off.
- **Well Fed food when it pays.** When you eat with fights ahead (a kill stop, or just after a
  fight) and you aren't Well Fed, food that also makes you Well Fed comes first: one meal heals
  and buffs. Otherwise plain food first, as before.

## 0.35.135
- **Druid: Entangling Roots.** On a melee mob (one without a mana pool), Flow opens with
  Entangling Roots: the key casts it before the pull, then stays on Wrath for the fight while
  Moonfire shows on the icon. When the mob comes for you again mid-fight, Roots shows on the
  icon: press it on your bar and step back. Not when several mobs come at once.
- **War Stomp stops a cast.** When your target starts casting within about 8 yards, the icon
  shows War Stomp (tauren), ahead of your damage. In a fight the key can't change, so press it
  on your bar: it glows there.

## 0.35.134
- **The smallest bandage that fills you.** After a fight the Flow key picks the smallest bandage
  you carry that heals what you're missing (a Heavy Wool Bandage on a scratch wasted most of
  it), else your biggest. The game hides your health, so "missing" is Flow's own estimate of
  how hurt you are; when it can't tell, it uses your biggest as before. "Lowest bandage first"
  (right-click the Flow key) still always takes the lowest.

## 0.35.133
- **Alt + Flow key: your healthstone, or your best healing potion**, in fights too, even when
  it's on none of your bars. It's set before the fight (WoW won't let it change during one).
  Flow Settings: "Alt + easy key: healthstone or potion".
- **One recovery order out of a fight.** Every heal goes through your order (bandage, food,
  heal spell by default): a heal spell no longer jumps ahead, and "Cast heals" off means none.
  Food that also makes you Well Fed is eaten to heal when you carry no plain food (right-click
  the Flow key to keep it for the buff). Fight healing is unchanged.
- **Worn gear**: under 20% durability an anvil shows above the Flow key (hover: the item and the
  nearest repair vendor Flow knows) and the route gets a Repair stop. No chat line. Flow Setup:
  "Warn early when gear wears out".
- **Repairing waits for your sale**: Flow sells first, repairs after, and tries again as the
  sale's gold comes in; it says once if you still can't afford it. With auto-repair off it says
  nothing.
- **Hearthstone estimate**: when a service (or the repair vendor) is far away, Flow says if your
  hearthstone then a run looks clearly quicker. An estimate, only for inns Flow knows; it never
  uses the hearthstone for you.
- **Campfires**: a camp object you placed counts for that visit to the fire, not an hour; your
  group's objects are listed as near you, elsewhere or unknown, and people who leave the group
  (or raid) drop off the list.
- **Buff button** (new, off by default: `/flow buffbutton on`): buffs and weapon stones, oils and
  buff items on their own blue button left of the Flow icon, so the Flow key is only your fight.
  Its own key: `/flow buffkey Q`. Group buffs cast from it are remembered like the key's.
- Flow Actions that error are logged for the diagnostics instead of vanishing quietly.
- (Thanks, BIMpossible: pull request 11's newer commits. Restart WoW once: new files.)

## 0.35.132
- Fixed a self-test that failed whenever your route was set to Shortest (near first rightly
  stays off there; the test now checks both ways).

## 0.35.131
- Fixed the last self-test that failed at every login (the anvil, forge or fire step's own
  test). Correction to 0.35.130: the step itself worked in the game; its test used spots
  without a map, which Flow's distance check couldn't handle. Now it can (plain yards).

## 0.35.130
- An NPC spot saved without a map no longer stops the anvil/forge/fire step looking for
  trainers (it's skipped).
- Fixed two self-tests that failed at every login (the arrow colours, camp objects from your
  group): the tests were wrong, not Flow.

## 0.35.129
- **Fixed: The Longwalkers doesn't need a fishing pole.** 0.35.128 got it wrong: when you
  reached the back of Palemane Rock, Perith Stormhoof was away, walking another player out. The
  quest is on your route again with or without a pole.
- **Escort quests say so on their stop**: "Accept: The Longwalkers (escort, deep in Palemane
  Rock)". Its details explain that if another player is escorting the giver, they're away for
  a few minutes: wait by their spot, or come back later. Flow spots every escort quest from
  Questie's data by itself. The Longwalkers also notes that you'll fight your way into the cave.
- **Restart WoW once** if you haven't since 0.35.126: those versions added files.

## 0.35.128
- **The Longwalkers waits until you have a fishing pole.** Perith Stormhoof, at the back of
  Palemane Rock, offers nothing without one, and nothing told Flow that, so it sent you through
  a cave of gnolls for a quest you couldn't take. Now the pickup stays off the route, and the Flow
  Router lists it as "needs a Fishing Pole first" with who sells one. It comes back as soon as you
  carry a pole. Its stop also reads "Accept: The Longwalkers (deep in Palemane Rock)", with a note
  to expect a fight on the way in.
- Quests like it are easy to add: one line each in `Modules\Quests\QuestNeeds.lua`, for whatever
  a giver wants you to carry first (a profession's tool or an item).
- **Restart WoW once** for this version: it adds a file (QuestNeeds.lua).

## 0.35.127
- **A new arrow: modern, glossy, coloured by distance.** It's grey while your stop is in another
  zone, turns from orange to green as you close in, and blue once you're in the area. It's the
  new default: if you had the 3D arrow, you get the modern one once; switch back from the
  arrow's right-click menu or Flow Settings (Arrow: Modern, 3D or Flat). "Arrow colour by
  distance" off gives the route's own colour, as before. The minimap dot matches the arrow.
- **The route on the world map is a faint dotted trail**, like a treasure map, instead of a solid
  line with crawling chevrons: it shows the way without covering the map. The stretch from you
  to your next stop (and that stop's dot) wears the arrow's colour; the rest of the route is
  fainter. Your waypoint's trail is dotted too. Nothing moves every frame any more; /flow perf
  shows the dots as "route dots".
- **Resize the Flow button**: hold Shift over it and turn the mouse wheel (half to double size);
  Shift-drag still moves it. Its spot and size are kept.
- **Flow Copy: copy what Flow says.** `/flow copy` opens what Flow printed in chat lately, all
  selected for Ctrl+C, with a button that picks out each web address in it. Flow Chat has a Copy
  button in its title bar for the whole conversation.
- **Restart WoW once** for this version: it adds new files (pictures and code), which a reload
  doesn't load. (Thanks, BIMpossible: pull request 12.)

## 0.35.126
- **Dungeon runs (needs Questie).** The arrow menu has a new **Dungeons** section: the runs at
  your level (one wing, the quests you can do on this trip) and how each compares to your
  questing XP per hour. **Prepare this run** puts its pickups and lead-in quests on the route,
  each once you can take it, then the entrance; inside, the route shows only that dungeon's
  quests (and your group's shared route). **Share quests** in a group gives party members the
  run quests they lack. A key icon above the Flow key suggests the best run; "Suggest dungeons"
  turns that off. Scarlet Monastery, Blackrock Spire and Stratholme are split into their wings.
  A prepared run stays on the route in "Current quests only" too.
- **The route finishes what's around you first.** Far stops (more than 300 yd away) and item
  drops whose mobs aren't near you wait until the stops next to you are done, so one far stop
  no longer splits up a cluster of nearby ones. Not on the "Shortest" route, which stays the
  shortest. `/flow nearfirst off` turns it off.
- **Route updates no longer cause a hitch**: Flow reads one kind of stop per frame.
- (Thanks, BIMpossible: pull request 10. Restart WoW once: this version adds new files.)

## 0.35.125
- **Your weapon stone goes on with one press, and food that makes you Well Fed too.** When
  you're about to kill a lot (at a kill or loot stop, or right after a fight) and your main hand
  has no sharpening stone, weightstone or oil on it, the Flow key (out of combat, not in inns or
  cities) puts the one in your bags on it, no more opening bags and clicking the weapon. Stones
  and weapon oils are now found by name too, not only when the game files them as an item
  enhancement. Never oil on a fishing pole. It shows on Flow's icon ahead of the out-of-combat
  buff the rotation suggests (a paladin's seal, say), except when an enemy is targeted or you're
  hurt (by Flow's own estimate, since the game hides your health). Same moment, if you aren't Well Fed and carry food that says it makes you
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
  once it's under 30, in aqua (the mana wait stays blue). A cooldown or mana wait takes the
  middle when there is one.
- **Healthstone, then potion, at low health in a fight.** When the game's low-health warning is
  on (or you're at a third of your health, where it's shown), Flow's icon shows your healthstone,
  else your best healing potion, ahead of any heal spell, for every class, when it's on one of
  your action bars. The key is locked in a fight, so press it on your bar: it glows there.
- **After a fight: bandage, then food, then a heal spell.** Hurt out of combat, the Flow key uses
  your best bandage (not while Recently Bandaged), then food that heals (when you're quite hurt and
  no enemy is targeted), then your heal spell. **Right-click the Flow key** for the options: the
  order of the three steps, turning any of them off, best or lowest bandage first, the in-fight
  healthstone/potion, and placing camp objects. Right-click never casts, with Shift or Ctrl
  held too. Opening the First Aid window no longer counts as using a bandage.
- **Status icons above the Flow key** (between fights, no chat spam): a small row for things to
  sort out (so far: what your group can add to the camp). Hover one for what it means; the key's
  own tooltip lists them too. Turn the row off from the key's right-click menu.
- **Auto-repair**: opening a vendor who repairs fixes everything if you have the gold, and says
  what it cost (Options: "Auto-repair at vendors", on by default). It waits until Flow has sold
  your junk, so that gold counts.
- **The diagnostics no longer stall the game after a login or reload**: Flow gathers them one
  check per frame, and reuses the self-tests it ran 8 seconds after login.
- (Thanks, BIMpossible: pull request 11.)

## 0.35.124
- **By an anvil, a forge or a cooking fire, the Flow key opens your profession** (Blacksmithing,
  Smelting when you carry ore, or Cooking), when you have something to make there: a recipe
  you've seen in that profession's window with everything for it in your bags. Flow learns
  where the game's anvils, forges and fires are each time your profession window says you're
  by one; until then it guesses from where the blacksmith and cooking trainers stand. Your own
  campfire counts too. (Thanks, BIMpossible: pull request 5.)

## 0.35.123
- **Fixed: in a group, the easy button chose nothing out of a fight.** Before suggesting a
  cleanse or a buff, Flow asks the game whether each person is in range. Forever hides that
  answer, and the hidden yes/no stopped Flow before it got to your spells, so the button sat
  empty between pulls. Now an answer the
  game hides counts as "near" (the cast still checks range), and buffing and cleansing your
  group work again.
- **Fixed: "All objectives in this area" showed nothing on the map or in the Flow Tracker.**
  Two of Flow's functions had the same name, and the second replaced the first, so every check
  for "is this stop in the area" failed. They have separate names now, and Flow's lint check
  refuses a function defined twice in one file, so this can't happen again unnoticed.

## 0.35.122
- **Flow Chat sends by a quick reload, as plain text** (the default since 0.35.114; sending by
  screenshot stays an option, `/flow chat live on`). The notes in Flow, the bridge and
  `docs\ASK-CLAUDE.md` now say why: WoW: Forever writes its chat log only when the game closes, so
  no text file can carry a message while you play. (Earlier notes said it never logged whispers.)

## 0.35.121
- **Out of mana, the easy button counts down until you have enough** (in blue), like it does for a
  cooldown. Flow works it out from the spell's cost, your mana and how fast it comes back. When
  the game hides those in a fight, the button just stays grey.

## 0.35.120
- **Fixed: Claude's answers were missing from Flow Chat.** The window put every message still
  waiting for an answer after all the answers, and showed only the last 6. Five old test messages
  that never got an answer filled it, so no answer showed. Now the conversation is in time order,
  newest at the bottom, in a box that scrolls with the mouse wheel. Long answers aren't cut off
  any more, and a message still waiting after a day leaves the list.

## 0.35.119
- Fixed two self-tests of the map that assumed the number of stops decides what it shows (since
  0.35.116 the "All objectives in this area" choice does, by default).

## 0.35.118
- **Fixed: at your trainer, training still waited as stop 8.** 0.35.115 skipped it once you'd
  opened the trainer at your level, even if you hadn't bought anything (Yang still had Blessing of
  Might to learn). Now it's skipped only when the trainer's own list shows nothing left for you.

## 0.35.117
- **Quests that have you heal NPCs: the easy key does it.** Near a stop like "Injured Deathguard
  healed: 0/5", one press targets the next one you can see, and the next press casts your heal on
  it (Holy Light for a young paladin). Then it moves on to the next, until the objective is done;
  ones you've healed are skipped.
- **They're marked.** While you're at such a stop, Flow turns friendly nameplates on (and back off
  when you leave), and Flow's marker shows over each NPC. Before, friendly nameplates were off, so
  nothing marked them and they were hard to find. The marker now also goes on friendly NPCs of
  the other stops right by your waypoint, not only enemies.

## 0.35.116
- **"All objectives in this area" is now a choice of Stops on the map,** the first one and the
  default, in place of the Flow Tracker's own "Everything here / Next stops" switch. One
  setting for the map and the Flow Tracker: everything around you and your waypoint, or your
  next 1, 3, 5, 10 or all stops. It's in the right-click menus (the arrow's, the Flow Tracker
  title's), on the Flow Settings page ("Area"), and `/flow nav stops area`. Each character keeps
  its own. If you'd switched the Flow Tracker to "Next stops", that stays.

## 0.35.115
- **Standing at your trainer, training comes first.** If your class trainer (or a profession
  trainer) is within 60 yards and you can pay for something, training is part of the town's
  business, with the turn-ins and the quests to pick up there, before you head out. It used to
  wait as stop 7. Farther away it's still fitted into the route, so it never pulls you off the
  mobs you're killing (0.35.98's 300 yards did). Not again once you've trained at this level.

## 0.35.114
- **Sending by screenshot is off unless you turn it on** (`/flow chat live on`). By default
  Send reloads again, while we look for a plain-text way out of the game.

## 0.35.113
- **Confirmed: Flow Chat sends without a reload.** Yang's `/si test7` reached Claude straight
  away by screenshot, with no reload.
- Fixed a self-test of the Flow Tracker's menu that a test edit in 0.35.111 had broken ("and back").

## 0.35.112
- **Sending without a reload now goes by screenshot.** WoW: Forever writes its chat log only when
  the game closes (it stayed empty through every reload and every attempt to force it, then
  everything appeared at once when WoW exited), so it can't carry a message live. WoW does write a
  screenshot straight away, though. So Send (or `/si <message>`) shows
  your message for a moment as a block of black and white squares in the top left of the screen,
  takes a screenshot and hides them. You see a quick flash and "Screen captured". The bridge
  decodes the squares, passes your message on at once, and deletes that screenshot; your own
  screenshots are left alone. If the screenshot doesn't work, Flow says so and Reload sends it
  (it's in Flow's saved data too).
- Flow no longer whispers to you or uses WoW's chat log, and switches the chat log back off if
  0.35.107-0.35.110 turned it on.

## 0.35.111
- **Hide a Flow window and the other menus bring it back.** While the Flow Arrow, the Flow Tracker
  or the Flow easy button is hidden, every Flow right-click menu ends with "Show <that window>".
  Flow Settings also has a "Show the ..." box for each.
- Fixed a self-test that still expected the Flow Tracker's old "next stops" list (since 0.35.108
  it shows everything here by default).

## 0.35.110
- **Tried: switching chat logging off and on after each message, to make WoW write its chat log
  at once.** It didn't help: WoW: Forever writes the chat log only when the game closes (found
  later; 0.35.112 sends by screenshot instead, 0.35.114 by reload again).
- The bridge prints an `INFO` line the first time WoW writes its chat log, so you can see that
  messages are coming through live.

## 0.35.109
- **The easy button greys out when you can't cast it,** like an action button: grey when you
  don't have the mana (or the game says it isn't usable right now), red when your target is out
  of its range.
- **Cooldowns show in fights too.** WoW: Forever hides spell cooldowns from add-ons in a fight,
  so the button showed none. Now the game draws the sweep (and its own countdown numbers) from
  the hidden values. `/flow rot why` says how the cooldown was drawn and why the button is tinted.

## 0.35.108
- **The Flow Tracker shows everything to do where you are.** It lists your waypoint (the next
  stop) and every stop within about 150 yards of you or of it, in route order, so in an area you
  see all of its objectives at once. Each one drops off as you finish it. It's on and open for
  everyone (once); the map still shows only your next stops.
- **Right-click the Flow Tracker's title for its menu:** everything here, or your next stops as
  on the map; open or folded; docked under Questie's tracker; hide it; and the route options.
  `/flow tracker here|next` does the same.
- **Every mob at your waypoint gets Flow's (o) marker,** not just the first objective's: the
  other objectives right there are marked too, with their counts.

## 0.35.107
- **Flow Chat sends without a reload.** WoW never lets an add-on read or write files while the
  game runs, but it writes its chat log (`Logs\WoWChatLog.txt`) as chat arrives. So Send (or
  `/si <message>`) turns the chat log on and whispers your message to yourself, tagged and hidden
  from your chat window. The bridge reads it from the log straight away. If it can't go that way,
  Flow says so and Reload sends it. `/flow chat live off` goes back to sending by reloading.
- **`/si` connects Claude for you.** If no Claude session was watching at your last reload, `/si`
  shows a prompt, already selected (Ctrl+C), to paste into Claude Code on your PC. It finds your
  Flow source, starts the bridge and watches. Anyone with Flow's source can connect this way.
  `/si setup` shows it again.
- **A Reload button in Flow Chat** (it was "Check now"). Answers still need a reload, the only time
  WoW reads Flow's files, so you choose when. It also loads any change Claude made to Flow.
- The bridge (`tools\claude-bridge.ps1`) watches WoW's chat log too, and writes "connected" into
  `Learned\ClaudeInbox.lua` every 10 minutes while it runs.

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
  `tools\read-diag.ps1` prints it.

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

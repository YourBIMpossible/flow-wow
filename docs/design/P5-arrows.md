# P5: one arrow per activity (design)

Status: design only, no code. Written for WOW-3 on base `program-integ` a529eea.
File and line references are to that commit. Lines listed under "Checked by hand" (1.8) were
read line by line; the rest come from a grep pass and should be re-read by whoever builds each PR.
Nothing here was run in the game.

It builds on the P2 activity contract (`docs/design/P2-activity-contract.md`, branch
`wow-p2-design`). It was started against ed8142c and aligned with the WOW-5 revision,
c36ca7d, whose section 6 "What P5 needs from this contract" this design relies on.
Section 5 says what is used and the one place this design asks for more.

## 0. What this is for

- **One arrow per activity.** The quest activity and the profession activity each have an
  arrow that points at that activity's selected step.
- **Stacked by default; can be separated and stacked again.** Stacked is today's look: one
  place on screen, the other activity's arrow as the long faint needle behind the main one.
  Separated: that arrow is a full arrow of its own, wherever the player put it.
  **This is a mandatory acceptance requirement** (section 7.1).
- **Position and state survive /reload** (and a relog).
- **Each arrow has its own controls**: its own click, its own right-click menu, its own
  "separate / stack", its own text switch, its own off switch.

Words: *step* is Flow's word for a route entry; in code it is a *goal* table
(docs/ARCHITECTURE.md "Words"). An *arrow* here is the whole on-screen thing: the pointer,
its text and its click areas.

## 1. Current state

### 1.1 Who owns the arrow

One frame, built by one file-local function, updated by one file-local function. There is
no registry kind for arrows.

| Thing | Where | Notes |
|---|---|---|
| `FlowNavArrow` (Button, 56x56, strata HIGH) | `buildArrow()`, Nav.lua:4362-4513 | The only arrow frame. Kept in the file-local `frame` (:5027) and in `N.arrowFrame` (:4394). |
| Main pointer `f.arrow` | `N:MakeArrow(f)`, Nav.lua:2086 | Style `nav.arrowStyle` (modern / 3d / flat), colour mode `nav.arrowColor`. |
| Text `f.text`, `f.sub` under it | Nav.lua:4395-4398 | Laid out by `N.LayoutLines` (:2299) five times a second (:4402-4411). |
| Click area `f.textHit` | Nav.lua:4459-4463 | Forwards to the arrow's own OnClick. |
| Profession holder `f.prof` | Nav.lua:4372-4392 | A **child** of the main arrow: `SetAllPoints(f)`, one frame level lower, alpha 0.85. Holds the needle `f.prof.arrow` (`N:MakeProfArrow`, :2143), the "at the step" ring, its text above the arrow and a click area `f.prof.hit` (:4496-4510). |
| Drawer (the step's details and trip) | `buildPanel` :3976, `placeDrawer` :4096, `showPanel` :4155 | One drawer, `FlowNavPanel`, opens beside the arrow or at `nav.drawerPoint`. It has its own "hero" header, not `ns.theme:TitleBar`. |
| Window entry | Nav.lua:5290 | `ns:Register("window", "arrow", { name = "Flow Arrow" ... })`: `/flow nav off` hides it, the menus offer it back. |

So today there is one arrow and a half: the profession needle cannot exist, move or be
clicked without the main arrow, and it has no frame name.

### 1.2 What each one points at

- Main arrow: `current` / `N.current`, set each tick by `update()` (Nav.lua:4706) from
  `choose(p)` (:3522), or replaced by an overlay. Order at :4738: a followed party member
  (`ns.follow.Choice`) beats your own waypoint (`N.WaypointChoice` :3625), which beats the
  route. Before that: your corpse (`N:ShowCorpse` :4627, writes straight into `frame.text` /
  `frame.sub`), the login intro (`N.intro`), the reveal gate (`ns.reveal:Shown("arrow")`).
- Profession needle: `N.profChoice`, set by `updateProf(p)` (Nav.lua:4671-4704) from
  `chooseProf(p)` (:3577), only while `N:ProfPointerOn()` (:739): `nav.profArrow == true`
  and the `professions` route kind ticked.
- `N.ProfArrowMode(mainHere, profHere, canPoint)` (:4660) decides needle / ring / off. It
  hides the needle while you stand on the **main** step's point: a rule that only makes
  sense when the two share one place.
- `N.SetOverNeedle` (:2209) shrinks and fades the main pointer (scale 0.8, alpha 0.7) while
  the needle shows.

### 1.3 Saved state

All under `ns.db.nav`. None of the arrow's own keys is per character (the per-character
list is Nav.lua:4997-5004: `hidden`, `deferred`, `selectedKey`, `stopsShown`, `stopsArea`).

| Key | Scope | Meaning |
|---|---|---|
| `nav.point = { a, r, x, y }` | account | Where the arrow is (written on drag stop, :4416-4420). Nil: TOP, 0, -120. |
| `nav.enabled` | account | The arrow on or off. |
| `nav.arrowStyle`, `nav.arrowColor`, `nav.arrowPaths` | account | Look. |
| `nav.profArrow` | account | The profession lane **and** its needle, one switch (`N:SetProfArrow` :1289 re-collects the route). |
| `nav.profArrowText` | account | The needle's text. |
| `nav.drawerOpen`, `nav.drawerPoint`, `nav.cardPoint` | account | Drawer open across /reload; where the drawer and the step card were dragged. |
| `nav.selectedKey` | character | The quest lane's picked step. |

There is no key for a second arrow's position, and no key for "stacked or separate".
The arrow has no scale and no "reset position" command.

### 1.4 Controls today

| Control | Where | Does |
|---|---|---|
| Ctrl-drag the arrow | :4413-4420 (`ns.MoveKeyDown`, Core.lua:365) | Moves it; saves `nav.point`. Hand-rolled: not `ns:MakeMovable` (Core.lua:372), not `ns:MoveHandle`. |
| Left-click arrow or its text | :4450-4455 | Opens or folds the drawer. |
| Right-click arrow or its text | :4422-4447 | Menu: this step (Open it, Hide this step) or the follow / waypoint entry, then `ns.menu:RouteItems()`. |
| Left-click the needle's text | :4500-4503 | `N:OpenStop(N.profChoice.goal)`. |
| Right-click the needle's text | :4501 | The **main** arrow's menu. The needle has no menu of its own. |
| Flow menu, "Arrow" section | `N:ArrowMenuItems` :5265, used by Menu.lua:480 | Style, colour, needle text, drawer back beside the arrow. |
| Route menu, "Route includes" | Menu.lua:407-410 | "on their own faint arrow" under Professions. |
| Settings, "Finding your way" | Nav.lua:5297-5306, `S:AddCheck{ group = "route" }` (Settings.lua:65) | "Faint profession arrow". |
| Slash | `ns.commands.nav`, Nav.lua:5084-5256 | `/flow nav on|off`, `profarrow on|off`, `arrow modern|3d|flat`, `arrowcolor`. |

### 1.5 The other places that draw "the profession arrow"

| Surface | Where | Reads |
|---|---|---|
| Minimap: the route dot | `P:Update`, MinimapPin.lua:384 | the main arrow's step |
| Minimap: the profession dot | `P:UpdateProf`, MinimapPin.lua:415-438, called from `updateProf` | `N.profChoice`; frame `FlowMinimapProfPin`, colour `ns.theme.profPointer` |
| World map: dotted profession path and pin | `drawProf`, MapOverlay.lua:1062 | `N.profPlan`, first 5 steps (`M.PROF_STOPS`) |
| World map: redraw check | MapOverlay.lua:2036-2040 | `N.profChoice` key and point, by polling |
| Flow Tracker | `RT:Refresh`, RouteTracker.lua:462 | `ns.nav.plan` only. Profession-lane steps are not listed. |
| Theme | Theme.lua:59 | `profPointer`, the one colour for the second arrow everywhere |

Each of these is written for exactly two lanes with fixed names. None takes an activity key.

### 1.6 Other code that holds on to the main arrow

Found by grep for `FlowNavArrow` and `arrowFrame`; each must keep working when the arrow
becomes a view, and each stays on the leader (2.1):

- TravelIcon.lua:71-130: `frame.travel`; `N.ShowTravel` halves the pointer and re-anchors it
  beside the travel icon.
- Follow.lua:234-249: the follow toggle, a button parented to `_G.FlowNavArrow`.
- Reveal.lua:18 (`FRAMES = { arrow = "FlowNavArrow" }`), Splash.lua:125 (the intro).
- MoveGuides.lua:127-129 (alignment guide), Dungeons.lua:1657 and :1941, Party.lua:403,
  PartyHelp.lua:629.
- `N:SetArrowStyle` (Nav.lua:2104-2123) rebuilds both `frame.arrow` and `frame.prof.arrow`.

### 1.7 Tests that pin today's behaviour

Tests.lua: `click: arrow style and colour...` (:2407), `arrow panel: a drawer under the
arrow...` (:2585), `click: the arrow's right-click menu opens` (:3130), `click: the faint
profession arrow (menu switches, its text)` (:3140, asserts `f.prof` is drawn behind
`f.arrow`), `arrow drawer: opens on the side...` (:5549), `click: the arrow drawer's X
closes it` (:6806), `arrow: its lines stack by length...` (:15053). They reach the arrow
through `N.arrowFrame` and `f.prof`; section 2.1 keeps those names alive.

### 1.8 Checked by hand

Nav.lua:739-742, :1289-1292, :2209-2216, :4096-4111, :4362-4513, :4660-4704, :4997-5004,
:5265-5306; Theme.lua:55-98; MinimapPin.lua:411-448; MapOverlay.lua:1062, :2036-2040;
RouteTracker.lua:201-224, :462; Core.lua:365-387; Tests.lua:3140-3162.
Not read in full: Focus.lua, Follow.lua, Waypoint.lua, TravelIcon.lua, Splash.lua, Reveal.lua,
Modules/Tests/UX.lua. The builder of PR A must re-read 1.6 before moving anything.

## 2. Proposed design

### 2.1 One view per activity

A small table per arrow, made by one factory, so the second arrow is the same code as the
first and a third costs a registration.

```lua
-- Modules/Nav/Arrows.lua (new; after Nav.lua in Flow.toc)
local V = N:ArrowView(key)   -- builds once, returns the same view afterwards
V.key        -- activity key: "quest", "professions"
V.frame      -- Button. "quest" keeps the name FlowNavArrow; others FlowNavArrow_<key>
V.pointer    -- the full pointer (N:MakeArrow), used when it stands alone or leads the stack
V.needle     -- the long faint pointer (N:MakeProfArrow), used when stacked under a leader
V.ring, V.text, V.sub, V.hit
V:Show(choice, p) / V:Hide()
```

- `N.arrowFrame` stays the quest view's frame, and `N.arrowFrame.prof` stays a table with
  `arrow`, `ring`, `text`, `hit` that points into the `professions` view, for one release, so
  the tests in 1.7 and the readers in 1.6 keep working. Then callers move and it goes.
- **The leader** is the view that carries the stack: the quest arrow. Follow, waypoint,
  corpse, intro, reveal, the travel icon and the follow toggle are drawn on the leader only,
  stacked or not (P2 6.5: `A:Target("quest")` returns the overlay; no other lane carries
  one). While dead, the leader points at the corpse and every other arrow hides, stacked
  or separate, as the needle does today. If the quest lane has no step and no overlay the
  leader hides and the other arrows stay (P2 6.5); whether a profession step then moves
  onto it is P2's Q7, an owner decision, and does not change the frames.

### 2.2 Stacked and separate

One saved mode, `nav.arrows.mode`, as P2 6.2 reserves it: "stacked" (default) or
"separate". With two arrows that is the whole behaviour. Section 5 need 2 says what
changes if there are ever more than two.

| State of a non-leader arrow | Anchor | Drawn as | Text | Hidden while on the main step's point |
|---|---|---|---|---|
| **stacked** (default) | `SetAllPoints(leader)`, one frame level lower | `needle` + `ring`, as today | where it is today | yes (`N.ProfArrowMode`, as today) |
| **separate** | `UIParent` at its saved point | `pointer`, full size, the activity's colour | under it, laid out by `N.LayoutLines` | no: it has its own place |

- The leader shrinks (`N.SetOverNeedle`) only while at least one stacked needle shows.
- With more than one stacked needle (Q1 answered "one per profession"), only the first by
  activity `order` draws its needle; the others show as one line of text each. A stack must
  stay readable; five needles would not. Each can still be separated.
- First separation with no saved point: the arrow lands beside the leader on the side with
  room (the pure `N.DrawerSide`, Nav.lua:4080, reused), not on top of it.
- Stack again: the arrow returns to the leader; its saved point is **kept**, so separating
  again puts it back where it was.
- A separated arrow dropped within `N.STACK_SNAP` (40 pixels) of the leader's centre stacks.
  Pure: `N.StackSnap(dx, dy, snap) -> bool`.

The arrows are ordinary (non-secure) frames, so moving, showing and re-anchoring them in
combat is allowed. No part of P5 touches a secure frame.

### 2.3 Saved data

New keys only; nothing existing is renamed or moved, so no migration.

| Key | Scope | Default | Meaning |
|---|---|---|---|
| `nav.point` | account (unchanged) | nil | The stack's position, and the quest arrow's when separate. |
| `nav.arrows.mode` | account | nil = "stacked" | "separate": every other arrow stands on its own. |
| `nav.arrows.points[key] = { a, r, x, y }` | account | nil | That arrow's own position; kept while stacked. |
| `nav.arrows.hidden[key]` | account | nil = shown | The arrow hidden, **the lane still planned** (P2 6.1). |
| `nav.arrows.text[key]` | account | nil = shown | Its text. **Not in P2's reserved shape; P5 adds it.** For `professions`, `nav.profArrowText` is read as the fallback and written through for one release. |

`mode`, `points` and `hidden` are exactly the shape P2 6.2 reserves; `nav.arrows` absent
means stacked at `nav.point`. An arrow with no saved point starts beside the stack.

- Account scope on purpose: `nav.point` and every other Flow window position is shared
  across characters (1.3). A per-character arrow layout would be the odd one out.
  P2 6.2 says the same. The alternative, named so it can be rejected:
  `ns:PerCharacter("nav.arrows")` (Q3).
- Written at the moment of the change (drag stop, menu click), never on logout, so /reload
  cannot lose it. Read in `N:ArrowView` when the frame is built.
- A key for an activity that is no longer registered is left alone (the player may have
  the profession back later).
- A saved point off screen (resolution changed): `SetClampedToScreen(true)` on every
  separated arrow, as `ns:MakeMovable` does. Whether today's arrow is clamped was not
  confirmed.

### 2.4 Controls, per arrow

| Control | Leader (quest) | Any other arrow |
|---|---|---|
| Ctrl-drag | moves the stack (leader + everything stacked on it) | separate: moves it. Stacked: Ctrl-drag its **text** pulls it out of the stack |
| Left-click | drawer, as today | `N:OpenStop(goal)`, as the needle's text today; a drawer of its own is PR F |
| Right-click | today's menu | **its own menu**, below |
| Hover | today's tooltip | `N:FillTooltip` for its step |

A non-leader arrow's menu, built by `N:ArrowItems(key)` and opened with `ns.menu:Open`:

1. Title: the step. "Open it". "Hide this step".
2. "Go here next" on another step of this activity: only once P2 PR 5 exists.
3. "On its own (separate from the main arrow)" / "Stacked on the main arrow": a tick.
4. "Text by this arrow": a tick.
5. "Hide this arrow": sets `hidden`; the Flow menu's hidden-windows list offers it back.

`ns.menu:RouteItems()` stays on the leader's menu only. The leader's menu gains one row
while separate: "Stack the arrows again". `N:ArrowMenuItems` (the Flow menu's "Arrow"
section) carries the same separate / stacked tick, so the choice is reachable without
finding the arrow. Settings: one `S:AddCheck{ group = "route", label = "Each arrow on its
own" }` beside the existing "Faint profession arrow" (`AddCheck` only makes ticks, which is
all this needs). Slash: `/flow nav arrows stack | separate`.

Dropping a separated arrow on the leader to stack has a precedent: the Flow Tracker
re-docks when dropped within 40 pixels of its dock (RouteTracker.lua:289-299).

Every one of these goes through a named function (`N:SetArrowsMode(mode)`,
`N:SetArrowText(key, on)`, `N:SetArrowHidden(key, on)`), so the menu, the
settings page, the slash command and the drag all do the same thing and one test covers it.

### 2.5 The other surfaces

- Minimap: P2 6.4 gives `ns.minimapPin:UpdateLane(key, p, point, goal)`; P5 gives it
  one pin per key and the lane's colour (`FlowMinimapPin_<key>`; `FlowMinimapProfPin` kept as the professions
  pin's name). It follows the lane, not the arrow: a `hidden` arrow keeps its dot
  unless `nav.minimapPin` is off.
- World map: `drawProf` becomes `drawLane(key, ...)` over `A:State(key).plan`, same dotted path.
- Colour: `ns.theme.profPointer` stays the professions colour. A new activity names a theme
  key in its registration (`color = "profPointer"`); no hex values outside Theme.lua.
- Flow Tracker: unchanged in P5. Listing a second lane's steps there is a product question (Q4).

## 3. "Flow <Name>" and `ns.theme:TitleBar`

The repo rules (CLAUDE.md): every view is named "Flow <Name>"; every panel gets its title
bar from `ns.theme:TitleBar(parent, title, icon, frameType)` (Theme.lua:69); colours come
from `ns.theme`.

- **An arrow is not a panel** and gets no title bar. It is a view, so it has a name and a
  `window` registration, which is what lets the menus offer a hidden one back:
  `ns:Register("window", "arrow", { name = "Flow Arrow" })` stays for the leader;
  each other arrow registers `"arrow:" .. key` with `name = "Flow " .. def.label .. " Arrow"`
  ("Flow Professions Arrow"), `hidden = fn`, `show = fn`, `hide = fn` over `nav.arrows.hidden[key]`.
- **Any panel P5 adds uses `ns.theme:TitleBar`.** The only one planned is the per-arrow
  drawer in PR F: built by `buildPanel(name)` (it already takes a name, Nav.lua:3976), titled
  `"Flow " .. def.label` with the activity's icon, `frameType` `"Button"` only if the bar
  itself is clickable. No hand-made header, no copied colours.
- **Finding, not a P5 change:** today's arrow drawer has a hand-built "hero" header, not
  `TitleBar`. PR F must not copy that. Whether the existing drawer is brought under the
  rule is its own item (Q5).
- P5 adds no "Flow Arrows" management window. The controls in 2.4 cover it; a window for
  two arrows would be more surface than the feature.

## 4. What stays the same for the player by default

With `nav.profArrow` off there is one arrow and nothing changes. With it on and nothing
separated, the screen is today's: main arrow, faint needle behind it, its grey text. P5 is
only visible once the player separates an arrow or opens its menu.

## 5. Dependency on WOW-2 / WOW-5 (the P2 contract)

P5 draws what P2 exposes: **one selected step per activity**. It reads only `A:Each()`,
`A:Target(key)`, `A:State(key)` and `A.version`, and writes only `nav.arrows` and
`A:Select`. References are to the contract at c36ca7d.

| # | P5 needs | P2 provides (c36ca7d) | P5's side |
|---|---|---|---|
| 1 | Lane existence separate from arrow display | 6.1: `exists(ctx)` / `ns.nav:ProfLaneOn()`; `nav.profArrow` now means "professions have their own lane" | `nav.arrows.hidden[key]` hides an arrow without touching the lane. |
| 2 | A saved display mode and a per-activity arrow position | 6.2: `nav.arrows = { mode, points, hidden }` reserved for P5 | Used as reserved (2.3). **Asks for more in one case:** `mode` is one switch for all arrows. That is right for two. If Q1 is answered "one per profession", pulling one arrow out of five needs a per-arrow flag (`nav.arrows.apart[key]`, with `mode` then meaning "all"). Not built unless Q1 goes that way. Also adds `nav.arrows.text`. |
| 3 | A per-lane change signal | 6.3: `A:State(key).version` (plan, choice, selection, existence), `A.version` (set of lanes) | Each view redraws when its lane's version moves; views are built or dropped when `A.version` moves. |
| 4 | A per-lane travel route and minimap pin | 6.4: `A:State(key).route`; `ns.minimapPin:UpdateLane`; flight, taxi and area-hop helpers **stay on the quest lane** | A separated profession arrow follows its own path but shows no "fly to" text and no travel icon. A stated limit, not a defect (Q7 in section 8). |
| 5 | Which arrow carries follow, waypoint and corpse | 6.5: the quest arrow; others hide while dead | The leader (2.1). |
| 6 | Per-arrow selection | 6.6 and PR 5: `A:Select(key, stepKey)` | "Go here next" on a non-quest arrow's menu (2.4). |
| 7 | Stable order and a label per activity | `order`, `label` on the activity | Stack order; the "Flow <label> Arrow" names. |

What does **not** wait for P2: the profession lane already exists as `N.profChoice` /
`N.profPlan`, so the frames, the saved keys and stack / separate / stack-again (PRs A-D
below) can be built and accepted on today's two lanes. P2 PR 3 then swaps the data source.
P5 does not need the reservation ledger.

Owner decisions that shape P5, left open in P2: **Q1** (one profession activity or one per
profession: decides two arrows or more) and **Q7** (no quest step left: does the
profession step move to the leader; does the profession lane exist by default).

## 6. Build order

Small PRs; each one lint-clean (`tools\lint.ps1`), with tests, and no version bump by the
contributor.

| # | PR | Changes | Needs | Player sees |
|---|---|---|---|---|
| A | Arrow views | `Modules/Nav/Arrows.lua`: `N:ArrowView(key)`; `buildArrow` and `updateProf` use it; `N.arrowFrame` and `.prof` kept; no new behaviour | nothing | nothing |
| B | Stack and separate | `nav.arrows` keys; `N:SetArrowsMode`, `N.StackSnap`; Ctrl-drag out of and into the stack; the separate look (2.2); positions restored on load | A | **the mandatory behaviour**, on quest + professions |
| C | Per-arrow controls | `N:ArrowItems(key)`; text and off switches; `window` entries; Flow menu rows; settings check; slash command | B; "Hide this arrow" needs P2 6.1, else leave that row out | each arrow has its own menu |
| D | Pins and map per lane | `P:UpdateLane`, `drawLane`, theme colour by key | A | nothing new for two lanes |
| E | Read from the contract | views built from `A:Each()`, steps from `A:Target(key)`, redraw on `version` | P2 PR 3, needs 3 and 6 | nothing (or more arrows, per Q1) |
| F | Per-arrow selection, travel and drawer | "Go here next" on any arrow; travel text per lane; a drawer per arrow with `TitleBar` | P2 PR 5, need 4 | pick a profession step from its arrow |

A, B and D can start now. C can start after B. E and F wait for P2.

## 7. Acceptance and test obligations

### 7.1 Mandatory acceptance: stacked and separated arrows

P5 is not accepted unless every row holds, checked by the named test and by the owner in
the game. (This document makes no in-game claim.)

| # | Must hold | Test |
|---|---|---|
| S1 | With the profession arrow on and nothing saved, the arrows are stacked: one place, needle behind the main arrow. | `arrows: stacked by default` |
| S2 | An arrow can be separated from its menu and by Ctrl-drag; it then draws as a full arrow at its own place and the main arrow returns to full size. | `click: an arrow separates` |
| S3 | A separated arrow can be stacked again from its menu, from "Stack the arrows again", and by dropping it on the main arrow. | `click: an arrow stacks again` |
| S4 | Separate, move, /reload: same place, still separate. Stack, /reload: still stacked. | `arrows: place and state survive a reload` (build the view twice over the same saved table) |
| S5 | Stack then separate again: it returns to its last own place. | same test |
| S6 | Moving the main arrow moves everything stacked on it and nothing separated. | `arrows: the stack moves as one` |
| S7 | Each arrow's click, menu, text switch and hide switch act on that arrow only. | `click: each arrow has its own menu` |
| S8 | Separating never changes what either arrow points at, the route, or the other arrow's selection. | `arrows: separating changes no step` |

### 7.2 Click tests (the repo rule: anything clickable gets a "click:" test, OnClick in a `pcall`)

Registered as `ns:Register("test", "click: ...", function(t) ... end)`:

- every view's `frame` and `hit`: left and right button, `pcall`, the menu or card shows;
- each row of `N:ArrowItems(key)`: call its `func` in a `pcall`, then check the saved key
  and the frame's anchor (separate tick, text tick, hide, "Open it", "Hide this step");
- "Stack the arrows again" on the leader's menu;
- the Flow menu "Arrow" rows and the settings check, found the way Tests.lua:2407 finds
  today's;
- the drag handlers: call `OnDragStart` / `OnDragStop` in a `pcall` with the move key
  stubbed down and up; a drop inside and outside `N.STACK_SNAP`;
- hidden-window "show it again" for each `arrow:<key>` window entry;
- PR F: the drawer's X and its title bar (`TitleBar` sets `h.flowTitleBar`: assert it, so a
  hand-made header fails the test).

Most "click:" tests skip offline today (docs/TESTING.md); these will too. They run in the
client's self-test, which only the owner can run.

### 7.3 Pure tests (run offline, `pwsh tools/run-tests.ps1`)

`N.StackSnap`; the anchor chosen for a first separation; the stack order from a list of
activity defs; `N.ProfArrowMode` unchanged for stacked and never "off" for separate; the
saved table round trip (2.3) including the `nav.profArrowText` fallback; the old test at
Tests.lua:3140 still passing through the compatibility names.

## 8. Open questions

| # | Question | Whose |
|---|---|---|
| Q1 | One profession arrow, or one per profession (P2 Q1)? The frames allow either; per profession needs the per-arrow flag in section 5 need 2. | owner |
| Q2 | No quest step left (P2 Q7): does the profession step move to the main arrow, or does the main arrow go quiet? | owner |
| Q3 | Arrow layout shared across characters (recommended, like every other Flow position) or per character? | owner |
| Q4 | Should the Flow Tracker list the other lane's steps once its arrow stands alone? | owner |
| Q5 | Bring the existing arrow drawer's header under `ns.theme:TitleBar`? | owner |
| Q7 | Should a separated non-quest arrow get flight and travel text? P2 6.4 keeps those on the quest lane. | owner, then P2 |
| Q6 | Should a separated arrow be resizable (mouse wheel, as `ns:MoveHandle` gives other Flow frames)? Not in P5 unless asked. | owner |

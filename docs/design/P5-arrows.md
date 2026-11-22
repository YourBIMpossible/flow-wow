# P5: one arrow per activity (design)

Status: design only, no code. Revision 3 (WOW-11): the owner's binding acceptance text is
section 7.5 and wins wherever this document differed (section 10 lists each difference).
Revision 2 (WOW-8) followed the lead's round-2 review (findings P5-1 to P5-12). Written for WOW-3 on `program-integ` a529eea; this branch now
sits on `wow-p2-design` (c36ca7d), so the P2 document it cites is in the same tree.
File and line references are to source at a529eea. Lines listed under "Checked by hand" (1.8) were
read line by line; the rest come from a grep pass and should be re-read by whoever builds each PR.
Nothing here was run in the game.

It builds on the P2 activity contract (`docs/design/P2-activity-contract.md`, branch
`wow-p2-design`, c36ca7d), whose section 6 "What P5 needs from this contract" this design relies on.
Section 5 says what is used and the places this design asks for more.

## 0. What this is for

- **One arrow per activity.** The quest activity and the profession activity each have an
  arrow that points at that activity's selected step.
- **Stacked by default; can be separated and stacked again.** Stacked is today's look: one
  place on screen, the other activity's arrow as the long faint needle behind the main one.
  Separated: that arrow stands on its own, wherever the player put it, still the fainter
  of the two (2.2).
  **This is a mandatory acceptance requirement** (section 7.1).
- **Position and state survive /reload** (and a relog).
- **Each arrow has its own controls**: its own click, its own right-click menu, its own
  "separate / stack", its own text switch, its own hide switch.

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
V.pointer    -- the full pointer (N:MakeArrow): the quest arrow only, graphic and size as today
V.needle     -- the long faint pointer (N:MakeProfArrow): every other arrow, stacked or separate
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
- **Siblings, not children.** Every view's frame is parented to `UIParent`. A stacked
  arrow is *anchored* to the leader (`SetAllPoints`), never parented to it, so hiding the
  leader does not hide it by accident; what shows is decided by 2.6, in one place. (Today
  the needle is drawn inside the main arrow's frame and disappears with it.)

### 2.2 Stacked and separate

One saved mode, `nav.arrows.mode`, as P2 6.2 reserves it: "stacked" (default) or
"separate". With two arrows that is the whole behaviour. Section 5 need 2 says what
changes if there are ever more than two.

| State of a non-leader arrow | Anchor | Drawn as | Text | Hidden while on the main step's point |
|---|---|---|---|---|
| **stacked** (default) | `SetAllPoints(leader)`, one frame level lower | `needle` + `ring`, as today | where it is today | yes (`N.ProfArrowMode`, as today) |
| **separate** | `UIParent` at its saved point | the same `needle` art at the same size and the same lower opacity (holder alpha 0.85, Nav.lua:4375), **tinted with the quest arrow's colour meanings** (below) instead of `ns.theme.profPointer` | above it, where it is when stacked (Nav.lua:4387-4388): the same words, travel text included | no: it has its own place |

Owner's acceptance (7.5): the quest arrow keeps its graphic, size, colour meanings and
interactions in both modes, and the other arrow stays the secondary one in both modes.
So separating changes two things about the profession arrow and nothing else: where it
stands, and its colour.

- **The quest arrow's colour meanings, in source.** The mode is `N:ArrowColorMode()`
  (Nav.lua:2096-2098, saved as `nav.arrowColor`). In "distance" (default) the colour is
  `N.ArrowColor(N.ArrowState(p, point, here), d)` (Nav.lua:1864-1872 and :1880-1887, called
  at :4879-4881): grey in another zone, orange through yellow to green from `COLOR_FAR`
  600 yd to `COLOR_NEAR` 40 yd (:1850), blue in the step's area. The five colours are
  `arrowAway / arrowFar / arrowMid / arrowNear / arrowHere` in Theme.lua:31-35, and
  :43-47 for the colour-blind palette. In "route" the colour is `ns.theme.route`, or
  `ns.theme.waypoint` for the player's own waypoint (Nav.lua:4883; Theme.lua:21-25, set by
  `ns.theme:UpdateRoute`, Theme.lua:107). Both functions are pure and take the point and
  distance as arguments, so the separated arrow calls them with **its own** step's point
  and distance. It never has a waypoint (P2 6.5), so in "route" mode it wears
  `ns.theme.route`.
- **Applying it.** The needle already has `SetVertexColor` (Nav.lua:2182); today it is
  called once with `ns.theme.profPointer` (:2183-2184, Theme.lua:59). Separate: called each
  update with the colour above. Stacked: `profPointer`, as today. No new colour values.
- **Still secondary.** Holder alpha 0.85, the needle's narrow long shape
  (`N.PROF_WID_K`, `N.PROF_LEN_K` = 0.5, 1.5, Nav.lua:2137), the faint ring at the step
  (`N.PROF_RING_ALPHA` 0.35, :2142), small muted text (:4386-4390), no beam, no bouncing
  icon, no wave: all unchanged when separate. Whether a coloured needle at 0.85 reads as
  secondary next to the quest arrow can only be judged in the game (7.5 O8).
- **The quest arrow when separate** is exactly today's arrow with no needle out: scale 1,
  alpha 1 (`N.SetOverNeedle(frame, false)`, Nav.lua:2209-2215).

- The leader shrinks (`N.SetOverNeedle`) only while at least one stacked needle shows.
- With more than one stacked needle (AQ1 answered "one per profession"), only the first by
  activity `order` draws its needle; the others show as one line of text each. A stack must
  stay readable; five needles would not. Each can still be separated.
- First separation with no saved point: the arrow lands beside the leader on the side with
  room (the pure `N.DrawerSide`, Nav.lua:4080, reused), not on top of it. That point is
  **written to `nav.arrows.points[key]` at once**, not at the first drag, so a /reload
  straight after separating finds the arrow where it was.
- Text is not lost or moved by separating. The stacked needle's line today is the step's
  name, the distance and `N.TravelText(p, pt, d)` (Nav.lua:4698), above the arrow, clear of
  the needle by `N.NeedleClearance` (:2201-2204); the separated arrow shows the same line
  in the same place relative to itself. The quest arrow's own lines stay with
  `N.LayoutLines` (:2299) in both modes. Only the travel *icon* and the "fly now" overlay stay on the leader (section 5
  need 4).
- Stack again: the arrow returns to the leader; its saved point is **kept**, so separating
  again puts it back where it was.
- A separated arrow dropped within `N.STACK_SNAP` of the leader's centre stacks.
  `N.STACK_SNAP` is 40, in `UIParent` units (the units `GetCenter()` returns for a frame
  parented to `UIParent`), measured centre to centre. The arrows have no scale of their
  own, so no conversion is needed; if AQ6 ever adds one, the distance is taken after
  multiplying each centre by its frame's `GetScale()`.
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
| `nav.arrows.text[key]` | account | nil = shown | Its text. **Not in P2's reserved shape at c36ca7d; P5 asks P2 to reserve it (WOW-7).** For `professions`, `nav.profArrowText` is **read** as the fallback when this key is nil. P5 never writes `nav.profArrowText`. |

`mode`, `points` and `hidden` are exactly the shape P2 6.2 reserves; `nav.arrows` absent
means stacked at `nav.point`. An arrow with no saved point starts beside the stack.

- Account scope on purpose: the arrow's own place, `nav.point`, is account-wide today
  (Nav.lua:4419), and P2 6.2 reserves `nav.arrows` the same way, so the new keys follow
  the arrow. Not every Flow window is account-wide: Flow Professions saves its place per
  character (Professions.lua:50 with `ns:PerCharacter("prof")` at :152). The alternative,
  named so it can be rejected: `ns:PerCharacter("nav.arrows")` (AQ3).
- Written at the moment of the change (drag stop, menu click), never on logout, so /reload
  cannot lose it. Read in `N:ArrowView` when the frame is built.
- A key for an activity that is no longer registered is left alone (the player may have
  the profession back later).
- A saved point off screen (resolution changed): `SetClampedToScreen(true)` on **every**
  arrow frame, the leader included. The leader is not clamped today: `buildArrow` sets
  movable and drag at Nav.lua:4413-4420 and never clamps, so a smaller resolution can put
  the whole stack out of reach. Clamping the leader is a small behaviour change, made in
  PR B. The pure `N.ClampPoint` (2.6) does the same sum offline so it can be tested.
- **Reset.** `N:ResetArrows()` clears `nav.point`, `nav.arrows.points`, `nav.arrows.hidden`
  and sets `mode` to nil: the arrows are stacked at the default place and all shown. Text
  switches are kept. Reached from `/flow nav arrows reset` and the menu row "Put the arrows
  back" (2.4).

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
3. "Each arrow on its own": a tick (on = separate, off = stacked).
4. "Text by this arrow": a tick.
5. "Hide this arrow": sets `hidden`; the Flow menu's hidden-windows list offers it back.

`ns.menu:RouteItems()` stays on the leader's menu only.

**One label, everywhere: "Each arrow on its own"**, a tick. It is on every arrow's menu
(the leader's too), in `N:ArrowMenuItems` (the Flow menu's "Arrow" section, so the choice
is reachable without finding the arrow), and on the settings page as
`S:AddCheck{ group = "route", label = "Each arrow on its own" }` beside the existing "Faint
profession arrow" (`AddCheck` only makes ticks, which is all this needs). There is no
second wording such as "Stack the arrows again": unticking is how you stack. Next to it,
in the same three menus, one row: "Put the arrows back" (reset, 2.3).

Slash, all four forms:

| Command | Does |
|---|---|
| `/flow nav arrows` | Status: the mode, then one line per arrow: shown or hidden, text on or off, stacked or its own place. Changes nothing. |
| `/flow nav arrows stack` | `mode = "stacked"`. |
| `/flow nav arrows separate` | `mode = "separate"`; any arrow with no saved point gets one at once (2.2). |
| `/flow nav arrows reset` | `N:ResetArrows()` (2.3). |

Dropping a separated arrow on the leader to stack has a precedent: the Flow Tracker
re-docks when dropped within 40 pixels of its dock (RouteTracker.lua:289-299).

Every one of these goes through a named function (`N:SetArrowsMode(mode)`,
`N:SetArrowText(key, on)`, `N:SetArrowHidden(key, on)`, `N:ResetArrows()`), each a thin
wrapper over the pure `N.ArrowApply` (2.6), so the menu, the
settings page, the slash command and the drag all do the same thing and one test covers it.

### 2.5 The other surfaces

- Minimap: P2 6.4 gives `ns.minimapPin:UpdateLane(key, p, point, goal)`, and says `Update`
  and `UpdateProf` become calls to it. Ownership, as the lead ruled (WOW-12): **P2 owns the
  signature and the contract test; P5 PR D owns the body and the calls**, so PR D writes
  `UpdateLane`, replaces the `Update` / `UpdateProf` calls in the nav update with it, and
  draws one pin per key (`FlowMinimapPin_<key>`; `FlowMinimapProfPin` kept as the professions
  pin's name). Revision 2 read this the other way round; corrected here. It follows the lane, not the arrow: a `hidden` arrow keeps its dot
  unless `nav.minimapPin` is off.
- World map: `drawProf` becomes `drawLane(key, ...)` over `A:State(key).plan`, same dotted path.
- Colour: `ns.theme.profPointer` stays the professions colour for the stacked needle, the
  minimap dot and the map path. Only the **separated arrow** changes colour (2.2); the
  owner's text names the arrow, so the dot and the path are left as they are (AQ8). A new
  activity names a theme key in its registration (`color = "profPointer"`); no hex values
  outside Theme.lua.
- Flow Tracker: unchanged in P5. Listing a second lane's steps there is a product question (AQ4).

### 2.6 Pure layout functions (required for acceptance)

The offline runner skips any test that touches a frame: every fixture frame method and
`CreateFrame` itself mark the test "needs the client" (tools/offline/stubs.lua:114-127,
161-162; docs/TESTING.md:173). So the mandatory behaviour must not live in frame code. It
lives in three pure functions (plain tables in, plain tables out, no client global), and
the frame code only carries out what they return.

```lua
-- What is on screen. Called on every arrow update.
-- saved = { point = nav.point, arrows = nav.arrows }          (read only)
-- lanes = { { key, order, hasStep, overlay }, ... }           (from A:Each / A:Target)
-- ctx   = { gate, screenW, screenH, size, defaultPoint }      (gate: see 2.7)
N.ArrowLayout(saved, lanes, ctx) -> {
    [key] = {
        shown  = bool,
        anchor = "screen" | "leader",     -- "leader": SetAllPoints(leader's frame)
        point  = { a, r, x, y } | nil,    -- when anchor == "screen", already clamped
        look   = "pointer" | "needle" | "text",   -- "pointer": the quest arrow only
        tint   = "own" | "quest",         -- "quest": the quest arrow's colour meanings (2.2);
                                          --   a non-leader arrow while separate, else "own"
        faint  = bool,                    -- every non-leader arrow, in both modes (alpha 0.85)
        small  = bool,                    -- the leader, shrunk over a stacked needle
        text   = bool,
    }, ...
}

-- What a control does. Returns a NEW saved table; never touches a frame or ns.db.
N.ArrowApply(saved, action, ctx) -> saved2
--   { type = "mode", mode = "stacked" | "separate" }  separate: fills missing points
--   { type = "move", key = k, point = {a,r,x,y} }      drag stop, away from the leader
--   { type = "drop", key = k, point = ..., leader = {x,y} }  inside STACK_SNAP: stacks
--   { type = "hide", key = k, on = bool }
--   { type = "text", key = k, on = bool }
--   { type = "reset" }

-- A saved point brought back on screen. Used by ArrowLayout for every "screen" point.
N.ClampPoint(point, size, screenW, screenH) -> point
```

- The frame side is then one loop: `for key, L in pairs(N.ArrowLayout(...))` show or hide
  the view, anchor it, pick the look. The control side is one line:
  `saved = N.ArrowApply(saved, action, ctx)`, write the result to `ns.db.nav`, redraw.
- /reload is, for these functions, "call `ArrowLayout` again on the same saved table".
  That is what makes S4 and S5 testable offline.
- `N.StackSnap` and `N.DrawerSide` are used inside `ArrowApply`; they stay public and pure.

### 2.7 When the leader is not showing

Today the arrow update returns before `updateProf(p)` (Nav.lua:4893) in four cases, all
near its top: nav switched off (Nav.lua:4714), the new-player reveal gate closed (:4716),
the login intro playing (:4717) and no player position (:4719). The first, second and
fourth hide the main frame; the intro returns and leaves it as it is. The needle is inside
that frame, so it goes with it. With sibling frames (2.1) that no longer happens by
itself, so it is specified here. The gate is worked out first, by the pure
`N.ArrowGate(enabled, revealShown, intro, hasPos, dead) -> "off" | "intro" | "corpse" | "open"`,
and handed to `ArrowLayout` as `ctx.gate`, so **the early returns hide every view, not
only the leader**.

| Case (`gate`) | Leader (quest) | Other arrow, stacked | Other arrow, separate |
|---|---|---|---|
| Nav off, `nav.enabled` false (`off`) | hidden | hidden | hidden. "Arrow off" means every arrow; pins hidden as today. |
| Reveal gate closed (`off`) | hidden | hidden | hidden. A new player sees no arrow of any kind until Flow reveals the first. |
| Login intro playing (`intro`) | the intro draws on it | hidden until the intro ends | hidden until the intro ends |
| No player position (`off`) | hidden | hidden | hidden. Nothing can be pointed at. |
| Dead (`corpse`) | points at the corpse | hidden | hidden (P2 6.5) |
| Open, quest lane has a step or an overlay | shown; small if a needle is stacked under it | needle behind it (or hidden on the same point, `N.ProfArrowMode`) | its needle at its own place, quest colour meanings (2.2) |
| Open, quest lane has no step and no overlay | hidden (P2 6.5) | **its needle, as when stacked, at the stack's place** (`nav.point`): same art, same opacity, `profPointer` | its needle at its own place, quest colour meanings |
| Open, the leader hidden by the player (`hidden.quest`) | hidden | as the row above | its needle at its own place, quest colour meanings |
| Open, the other arrow hidden by the player (`hidden[key]`) | shown, full size | hidden | hidden |

- In the two "leader hidden, others stay" rows a stacked arrow is still **stacked** in the
  saved data: `mode` does not change and nothing is written. When the leader comes back it
  goes behind it again. Ctrl-dragging it there moves the stack (`nav.point`).
- The follow toggle, travel icon and drawer hang off the leader's frame (1.6) and go with it.
- Whether a profession step should instead *move onto* the leader when the quest lane is
  empty is P2's Q7 (owner). This table is the behaviour if the answer is "no"; if "yes",
  the two rows marked P2 6.5 cannot occur and the rest is unchanged.

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
  rule is its own item (AQ5).
- P5 adds no "Flow Arrows" management window. The controls in 2.4 cover it; a window for
  two arrows would be more surface than the feature.

## 4. What stays the same for the player by default

With `nav.profArrow` off there is one arrow and nothing changes. With it on and nothing
separated, the screen is today's: main arrow, faint needle behind it, its grey text. P5 is
only visible once the player separates an arrow or opens its menu.

## 5. Dependency on WOW-2 / WOW-5 (the P2 contract)

P5 draws what P2 exposes: **one selected step per activity**. It reads only `A:Each()`,
`A:Target(key)`, `A:State(key)` and `A.version`, and writes only `nav.arrows`, `nav.point`
(already the arrow's own key) and `A:Select`. It does not write `nav.profArrowText`. References are to the contract at c36ca7d.

| # | P5 needs | P2 provides (c36ca7d) | P5's side |
|---|---|---|---|
| 1 | Lane existence separate from arrow display | 6.1: `exists(ctx)` / `ns.nav:ProfLaneOn()`; `nav.profArrow` now means "professions have their own lane" | `nav.arrows.hidden[key]` hides an arrow without touching the lane. |
| 2 | A saved display mode and a per-activity arrow position | 6.2: `nav.arrows = { mode, points, hidden }` reserved for P5 | Used as reserved (2.3). **Asks for more in one case:** `mode` is one switch for all arrows. That is right for two. If Q1 is answered "one per profession", pulling one arrow out of five needs a per-arrow flag (`nav.arrows.apart[key]`, with `mode` then meaning "all"). Not built unless P2 Q1 goes that way (deferred with P2 Q1, review P5-12). Also asks P2 to reserve `nav.arrows.text` (2.3). |
| 3 | A per-lane change signal | 6.3: `A:State(key).version` (plan, choice, selection, existence), `A.version` (set of lanes) | Each view redraws when its lane's version moves; views are built or dropped when `A.version` moves. |
| 4 | A per-lane travel route and minimap pin | 6.4: `A:State(key).route`; `ns.minimapPin:UpdateLane` (signature and contract test; WOW-12); flight, taxi and area-hop helpers **stay on the quest lane** | A separated profession arrow follows its own path and keeps the travel words it has today as a stacked needle (`N.TravelText`, Nav.lua:4698). It gets no travel *icon* and no "fly now" overlay: those stay on the leader. A stated limit, not a defect (AQ7 in section 8). Minimap: P5 PR D writes the body of `UpdateLane` and its calls (2.5). |
| 5 | Which arrow carries follow, waypoint and corpse | 6.5: the quest arrow; others hide while dead; quest lane with no step and no overlay: its arrow hides, the others stay | The leader (2.1), in P2's words; every other leader-hidden case is 2.7. |
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
| B | Stack and separate | the pure `N.ArrowLayout`, `N.ArrowApply`, `N.ArrowGate`, `N.ClampPoint`, `N.StackSnap` with their offline tests first; then `nav.arrows` keys; `N:SetArrowsMode`, `N:ResetArrows`; sibling frames and the 2.7 table; every arrow clamped; Ctrl-drag out of and into the stack; the separate look (2.2: the needle kept, quest colour meanings, `tint` / `faint`); positions restored on load | A | **the mandatory behaviour**, on quest + professions |
| C | Per-arrow controls | `N:ArrowItems(key)`; text and hide switches; `window` entries; Flow menu rows; settings check; the four slash forms | B; "Hide this arrow" needs P2 6.1, else leave that row out | each arrow has its own menu |
| D | Pins and map per lane | the body of `ns.minimapPin:UpdateLane(key, p, point, goal)` to P2's signature, passing P2's contract test; the nav update's `Update` / `UpdateProf` calls replaced by it; a pin per key; `drawLane`; theme colour by key | A; P2's PR that lands the signature and the contract test | nothing new for two lanes |
| E | Read from the contract | views built from `A:Each()`, steps from `A:Target(key)`, redraw on `version` | P2 PR 3, needs 3 and 6 | nothing (or more arrows, per Q1) |
| F | Per-arrow selection and drawer | "Go here next" on any arrow; a drawer per arrow with `TitleBar` | P2 PR 5, need 4 | pick a profession step from its arrow |

A, B and D can start now. C can start after B. E and F wait for P2.

## 7. Acceptance and test obligations

### 7.1 Mandatory acceptance: stacked and separated arrows

P5 is not accepted unless every row holds. Each row has an **offline** test on the pure
functions of 2.6, which runs in CI (`pwsh tools/run-tests.ps1`) and is the acceptance
evidence the contributor can produce, and, where a frame is involved, a client test or a
line of the in-game checklist (7.4), which only the owner can run. This document makes no
in-game claim.

| # | Must hold | Offline test (pure, 2.6) | In the client |
|---|---|---|---|
| S1 | With the profession lane on and nothing saved, the arrows are stacked: one place, needle behind the main arrow. | `arrows: stacked by default`: `ArrowLayout` on an empty saved table | checklist |
| S2 | The arrows can be separated from any arrow's menu and by Ctrl-drag; the other arrow then stands at its own place as the same faint needle, in the quest arrow's colour meanings (2.2, 7.5), and the main arrow returns to full size. | `arrows: separating gives each a place`: `ArrowApply` mode and move, then `ArrowLayout` | `click: an arrow separates` |
| S3 | They can be stacked again by unticking "Each arrow on its own" and by dropping the arrow on the main arrow. | `arrows: stack again by tick and by drop`: `ArrowApply` mode and drop, inside and outside the snap | `click: an arrow stacks again` |
| S4 | Separate, move, /reload: same place, still separate. Stack, /reload: still stacked. Separate with no drag, /reload: same place. | `arrows: place and state survive a reload`: `ArrowLayout` twice on the same saved table, and on a copy made through a plain-table round trip | checklist |
| S5 | Stack then separate again: it returns to its last own place. | same test: `points` survive mode "stacked" | checklist |
| S6 | Moving the main arrow moves everything stacked on it and nothing separated. | `arrows: the stack moves as one`: change `saved.point`, compare layouts in both modes | checklist |
| S7 | Each arrow's click, menu, text switch and hide switch act on that arrow only. | `arrows: a control changes one arrow`: `ArrowApply` hide and text for one key leave the other key's layout equal | `click: each arrow has its own menu` |
| S8 | Separating never changes what either arrow points at, the route, or the other arrow's selection. | `arrows: separating changes no step`: `ArrowApply` returns a table whose only changed keys are under `arrows`; `ArrowLayout` takes no step as input beyond `hasStep` | none needed |
| S9 | Hide an arrow, switch the mode, show it again: it comes back in the current mode, at its saved place if separate. The profession lane switched off and on again (`nav.profArrow`): same mode, same place, saved keys untouched while it was off. | `arrows: hide, switch, unhide` and `arrows: a lane off and on keeps its keys` | checklist |
| S10 | A second character sees the same layout (account-wide). A character with no profession lane sees one arrow, and the other arrow's saved keys are left alone. | `arrows: a missing lane leaves its keys`: `ArrowLayout` with one lane over a saved table that has two | checklist |
| S11 | Every row of the 2.7 table: nav off, reveal gate, intro, no position, dead, quest lane empty, either arrow hidden, each in both modes. Dead while separate: one arrow, on the corpse; on release the others return to their places. | `arrows: what shows when the leader does not`: one check per cell of 2.7; `N.ArrowGate` for each early return | checklist |
| S12 | A saved place off screen comes back on screen, for the leader and for a separated arrow. Reset puts the arrows back, stacked, at the default place, all shown. Ctrl-drag during a fight raises no error and is saved. | `arrows: clamped to the screen` (`N.ClampPoint`, and through `ArrowLayout`); `arrows: reset` (`ArrowApply`) | `click: put the arrows back`; drag in a fight: checklist only |

### 7.2 Click tests (the repo rule: anything clickable gets a "click:" test, OnClick in a `pcall`)

Registered as `ns:Register("test", "click: ...", function(t) ... end)`:

- every view's `frame` and `hit`: left and right button, `pcall`, the menu or card shows;
- each row of `N:ArrowItems(key)`: call its `func` in a `pcall`, then check the saved key
  and the frame's anchor (separate tick, text tick, hide, "Open it", "Hide this step");
- "Each arrow on its own" and "Put the arrows back" on the leader's menu;
- the Flow menu "Arrow" rows and the settings check, found the way Tests.lua:2407 finds
  today's;
- the drag handlers: call `OnDragStart` / `OnDragStop` in a `pcall` with the move key
  stubbed down and up; a drop inside and outside `N.STACK_SNAP`;
- hidden-window "show it again" for each `arrow:<key>` window entry;
- PR F: the drawer's X and its title bar (`TitleBar` sets `h.flowTitleBar`: assert it, so a
  hand-made header fails the test).

Most "click:" tests skip offline today (docs/TESTING.md:173: a test that touches a frame
method is reported SKIP, "needs the client"); these will too. They run in the client's
self-test, which only the owner can run. That is why none of S1 to S12 rests on a click
test alone: each has an offline test in 7.1.

### 7.3 Pure tests (run offline, `pwsh tools/run-tests.ps1`)

The twelve tests named in 7.1, over `N.ArrowLayout`, `N.ArrowApply`, `N.ArrowGate` and
`N.ClampPoint`. They must be written so nothing of the client is touched (no frame, no
`ns.db` read through a client call), or the runner reports them SKIP and they prove
nothing; the PR shows them in the PASS count. Also: `N.StackSnap` at, inside and outside
40; the side chosen for a first separation; the stack order from a list of activity defs;
`N.ProfArrowMode` unchanged for stacked and never "off" for separate; the four tests
named in 7.5 (O1, O4, O7, O8); the
`nav.profArrowText` read-only fallback (2.3); the old test at Tests.lua:3140 still passing
through the compatibility names (in the client).

### 7.4 In-game checklist (owner; nothing here has been run)

1. S1 to S6 and S9 to S12 by hand, once each, with a real /reload.
2. **Moving in a fight.** The arrow holds no secure frame today (`buildArrow` makes a plain
   `Button`, Nav.lua:4363; the follow toggle is a plain `Button` on it, Follow.lua:238), so
   moving, showing and re-anchoring arrows in combat should be allowed. This is read from
   source, not seen in the game: Ctrl-drag each arrow, stack and separate, during a fight,
   and watch for a blocked-action message.
3. Change the resolution or UI scale with an arrow near an edge: both arrows stay reachable.
4. Die while separate; release; both arrows return.
5. Log a second character: same layout.
6. The visual checks O1 to O4, O7 and O8 of 7.5, by eye, in both colour modes and with the
   colour-blind palette.

### 7.5 The owner's binding acceptance (WOW-11)

The owner's text, verbatim. It is binding and overrides anything else in this document:

> Preserve the current solid foreground quest arrow and translucent background profession
> arrow, including their independent clock-hand rotation and existing text placement when
> stacked. Preserve the quest arrow's current graphic, size, color meanings, and
> interactions. Add independent placement and restacking. When separated, apply the quest
> arrow's color meanings to the profession arrow while retaining its lower opacity and
> secondary visual emphasis. Do not claim this is implemented until code, saved-layout
> tests, and in-game visual checks demonstrate it.

One row per clause. "Offline" is a saved-layout test on the pure functions (2.6), run by
`pwsh tools/run-tests.ps1`. "In game" is a visual check only the owner can make. A row is
met only when **both** of its columns are shown; none is shown today.

| # | Clause | Today, in source (a529eea) | Offline (saved-layout test) | In game (visual) |
|---|---|---|---|---|
| O1 | Stacked: the quest arrow in front, the profession arrow translucent behind it. | Holder one frame level lower at alpha 0.85 (Nav.lua:4372-4375); needle in `profPointer` (:2183, Theme.lua:59); the quest arrow over it at scale 0.8, alpha 0.7 (`N.SetOverNeedle`, :2136, :2209-2215). | `arrows: the stacked look is today's`: `ArrowLayout` on an empty saved table gives the other arrow `anchor = "leader"`, `look = "needle"`, `tint = "own"`, `faint = true` and the leader `small = true`; the four constants keep their values. | Side by side with a screenshot from before PR A: no visible change. |
| O2 | Stacked: each turns on its own, like two clock hands. | Each has its own `SetRotation` and its own easing (needle: :4690, :2185-2192; quest arrow: `update()`). | None possible: the layout holds no angle and the offline runner has no frame. S8 shows only that separating changes no step. | Two steps in different directions: the hands point apart and turn separately, stacked and separate. |
| O3 | Stacked: the text stays where it is. | Needle's line above the arrow, clear by `N.NeedleClearance` (:4387-4388, :2201-2204); the quest arrow's lines by `N.LayoutLines` (:2299). | `N.NeedleClearance` and `N.LayoutLines` tests unchanged and passing; `ArrowLayout` gives `text` per arrow and no position for it. | Same screenshot comparison as O1, with text on. |
| O4 | The quest arrow keeps its graphic, size, colour meanings and interactions. | `N:MakeArrow` (:2086-2091), 56 x 56 (:4364), colours as 2.2, controls as 1.4. | `arrows: the quest arrow is untouched`: the leader's entry is `look = "pointer"`, `tint = "own"`, `faint = false` in every mode and gate; `N.ArrowColor` returns the same values for fixed inputs before and after; every existing arrow test still passes. | Existing `click:` tests (1.7) pass in the client; by eye in both modes. |
| O5 | Independent placement. | Not possible today (1.1). | S2, S4, S6, S10, S12. | Checklist 1 and 3. |
| O6 | Restacking. | Not possible today. | S3, S5, S9. | Checklist 1. |
| O7 | Separated: the profession arrow wears the quest arrow's colour meanings. | One fixed colour today (:2183-2184). | `arrows: a separated arrow wears the quest colours`: `tint = "quest"` only for a non-leader arrow in mode "separate", `"own"` again after stacking; the colour is `N.ArrowColor(N.ArrowState(...), d)` for that arrow's own point and distance, and `ns.theme.route` in "route" mode. | Walk towards a profession step while separate: grey, orange, yellow, green, then blue in its area; the same in the colour-blind palette; "route" mode shows the route colour. |
| O8 | Separated: it keeps its lower opacity and stays the secondary arrow. | Alpha 0.85, the narrow long needle, the faint ring, small muted text (2.2). | `arrows: the other arrow stays faint`: `faint = true` and `look = "needle"` for every non-leader arrow in both modes and every gate of 2.7. | By eye: next to the quest arrow, the coloured needle still reads as the lesser of the two. If it does not, the opacity is the owner's to set; the design does not lower it on its own. |
| O9 | No claim of "implemented" until code, saved-layout tests and in-game visual checks show it. | - | PR B's description gives the PASS count including the tests above, none SKIP. | The owner's ticks against checklist 1 to 6. This document claims none of it. |

One thing in the owner's text does not match source word for word: the quest arrow is
called "solid", and today it is drawn at alpha 0.7 and scale 0.8 **while a needle shows
under it** (`N.ON_NEEDLE_ALPHA`, `N.ON_NEEDLE_SCALE`, Nav.lua:2136). "Preserve the current"
is read as keeping those values. If the owner means alpha 1 when stacked, that is one
constant and a new decision, not part of this design (AQ9).

## 8. Open questions

Numbered AQ ("arrow question") so they cannot be mistaken for P2's Q1 to Q9. Revision 1
called these Q1 to Q7; the old number is in brackets.

| # | Question | Whose |
|---|---|---|
| AQ1 (Q1) | One profession arrow, or one per profession (**P2 Q1**)? The frames allow either; per profession needs the per-arrow flag in section 5 need 2. | owner |
| AQ2 (Q2) | No quest step left (**P2 Q7**): does the profession step move to the main arrow, or does the main arrow hide (2.7)? | owner |
| AQ3 (Q3) | Arrow layout shared across characters (recommended: the arrow's place already is, Nav.lua:4419) or per character (as Flow Professions' window is)? | owner |
| AQ4 (Q4) | Should the Flow Tracker list the other lane's steps once its arrow stands alone? | owner |
| AQ5 (Q5) | Bring the existing arrow drawer's header under `ns.theme:TitleBar`? | owner |
| AQ6 (Q6) | Should an arrow be resizable? There is no scale today and none is designed (review P5-11, closed without change). Not in P5 unless asked. | owner |
| AQ8 | When separated, should the profession minimap dot and map path also take the quest colour meanings? The owner's text names the arrow only; they stay `profPointer` (2.5). | owner |
| AQ9 | Stacked, the quest arrow is at alpha 0.7 and scale 0.8 over the needle today. Keep (as designed, "preserve the current"), or make it fully solid? | owner |
| AQ7 (Q7) | Should a separated non-quest arrow get the travel icon and "fly now" overlay? P2 6.4 keeps those on the quest lane. Its travel words are kept either way (2.2). | owner, then P2 |

## 9. Round-2 review: what changed in revision 2

Cited source lines were re-read at a529eea before each change.

| Finding | Disposition | Where |
|---|---|---|
| P5-1 | Applied. Pure `ArrowLayout`, `ArrowApply`, `ArrowGate`, `ClampPoint`; every S row has an offline test. Skip rule confirmed at stubs.lua:114-127, 161-162 and TESTING.md:173. | 2.6, 7.1, 7.3 |
| P5-2 | Applied. Sibling frames; a table for each leader-hidden case in each mode. Early returns confirmed at Nav.lua:4714-4719, `updateProf` at :4893. | 2.1, 2.7 |
| P5-3 | Applied. Every arrow clamped, leader included; reset command and menu row; test S12. No clamp in Nav.lua:4413-4420 confirmed. | 2.3, 2.4, 7.1 |
| P5-4 | Applied. The wrong sentence is replaced; Professions.lua:50 and :152 confirmed per character, Nav.lua:4419 account-wide. | 2.3, AQ3 |
| P5-5 | Applied. Status and reset forms; one label; first separation saved at once; the 40 given a unit. | 2.2, 2.4 |
| P5-6 | Applied. S9 to S12. | 7.1 |
| P5-7 | Applied. In-game check added; the source lines confirmed (Nav.lua:4363, Follow.lua:238). | 7.4 |
| P5-8 | Applied on P5's side: `nav.profArrowText` is read only; the leader rule uses P2 6.5's words; the questions are renamed AQ. The minimap owner was read the wrong way round in revision 2 and is corrected in revision 3 to the lead's ruling (WOW-12): P2 the signature and the contract test, P5 PR D the body and the calls. Still open for P2: reserving `nav.arrows.text`. | 2.3, 2.5, 5, 6, 8 |
| P5-9 | Applied. Rebased on `wow-p2-design` c36ca7d; pushed as `wow-p5-design-r2`. | header |
| P5-10 | Applied. The separated arrow keeps the travel words (Nav.lua:4698 confirmed). | 2.2, 5 |
| P5-11 | No change, as the review disposed; recorded as AQ6. The cited file is `Modules/Nav/Party.lua` (:405-408: the party toggle is anchored under the arrow at a fixed size; nothing scales the arrow). | 8 |
| P5-12 | No change; deferred with P2 Q1. | 5 |

Nothing rejected.

## 10. Revision 3 (WOW-11): where the design differed from the owner's text

Each cited line was re-read at a529eea. The owner's text (7.5) wins in every case.

| # | Revision 2 said | Owner's text | Corrected to | Where |
|---|---|---|---|---|
| D1 | Graphic: a separated arrow is drawn as a full `pointer`, the quest arrow's art. | The profession arrow keeps its secondary emphasis. | It keeps its needle art. | 2.1, 2.2, 2.6, 2.7, S2 |
| D2 | Size: a separated arrow is "full size". | Secondary emphasis; only the quest arrow's size is named, and it is preserved. | The needle keeps its size (`N.PROF_WID`, `N.PROF_LEN`); the quest arrow is 56 x 56 as today. | 2.2 |
| D3 | Colour: a separated arrow wears "the activity's colour" (`profPointer`). | The quest arrow's colour meanings. | `N.ArrowColor` / `N.ArrowState` or the route colour, by `nav.arrowColor`, on the arrow's own step. Stacked stays `profPointer`. | 2.2, 2.5, 2.6 (`tint`), O7 |
| D4 | Opacity: not stated for a separated arrow; a full pointer implied alpha 1. | Retain its lower opacity. | Holder alpha 0.85 in both modes (`faint`). | 2.2, 2.6, O8 |
| D5 | Stacked text placement: "where it is today"; separated text "under it" by `N.LayoutLines`. | Existing text placement when stacked. | Stacked unchanged, now with its source lines; separated keeps the same placement relative to the arrow (above), so one arrow has one layout. | 2.2, O3 |
| D6 | Leader hidden: a stacked arrow "shown as a full pointer". | As D1 and D4. | Its needle, as when stacked. | 2.7 |
| D7 | Minimap: P2 owns `UpdateLane` and its calls. | Lead's ruling (WOW-12), not the owner's text. | P2 the signature and contract test; P5 PR D the body and calls. | 2.5, 5, 6, 9 |

No difference found for: the stacked look (frame level, alpha, `N.SetOverNeedle`), the
independent rotation, or the quest arrow's graphic, colour meanings and interactions.
Revision 2 already left those as they are. New questions: AQ8, AQ9.

Nothing here is implemented or tested, in the game or offline.

# Working on Flow (for Claude and other AI assistants)

Flow is a World of Warcraft: Forever addon (Lua 5.1, interface 16001): a levelling companion
with a rotation helper, route planner and arrow, gear scoring, bag sorting and profession
plans. Read [README.md](README.md) for what it does and
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how it's built.

## The one design rule

**Extend by registering, don't edit the core.** `Core.lua` has registries
(`ns:Register(kind, key, value)`, `ns:Get`, `ns:Each`). New classes, rotations, advisors,
route goals, profession guides, item sources, gear analyzers, setup rows and tests are new
registrations, usually in a new file listed in `Flow.toc`. The table of registry kinds is in
`docs/ARCHITECTURE.md`. If a change seems to need edits all over the core, look for the
registry first, or add one.

## Map of the code

| Path | What |
|---|---|
| `Flow.toc` | Load order. Every new file must be listed here or WoW never loads it. |
| `Core.lua` | Event bus (`ns:On`), registries, saved data (`ns:OnLoad`), `/flow` commands (`ns.commands.x`). |
| `Classes/<Class>/` | Class data, trainer spells, rotation. Paladin and Druid so far: adding a class is a great first contribution. |
| `Modules/Rotation/` | Rotation engine, cast button/key, the Forever API shims (`Compat.lua`, `ns.api`). |
| `Modules/Nav/` | Route: goals (`Goals.lua`), planner, arrow and panels (`Nav.lua`), world map (`MapOverlay.lua`), tracker. |
| `Modules/Crafting/` | Profession guides, recorded recipes, skill plans that become route steps. |
| `Modules/Gear/`, `Modules/Items/` | Gear scores per role, bag icons, selling, keep reasons. |
| `Modules/Advisor/` | The advice list. |
| `Modules/Tests.lua` | Self-tests. |
| `tools/` | PowerShell: read the in-game diagnostics, look at the game's window, analyse combat logs, package a release, render the CurseForge graphics, save the day's public auction prices (`save-prices.ps1`). |

## Testing: the real check is in the game; the pure tests also run offline

- `powershell -ExecutionPolicy Bypass -File tools\run-tests.ps1` runs the registered tests
  outside the game, on Lua 5.1 with fixtures. Only tests that touch nothing of the client can
  PASS there; the rest are SKIP. A FAIL, ERROR or SKIP-FAIL, a file that doesn't load and a
  global that is neither Flow's nor in `tools/offline/client-globals.txt` each fail it. CI
  runs it, with `tools\lint.ps1` and `tools\check-structure.ps1`. On Z-Flow the GitHub
  "Checks" workflow runs them once per branch tip before READY; nobody reruns an unchanged
  commit, per commit or per handoff. It is not a test in the game and never stands in for one (`docs/TESTING.md`).
- Add a test for every behaviour you change: `ns:Register("test", "area: what it checks", function(t) ... end)`
  in `Modules/Tests.lua`, using `t:ok(cond, msg)`, `t:eq(a, b, msg)`, `t:near(a, b, tol, msg)`.
  Restore any saved data you change inside a test.
- Tests run on every `/reload` and with `/flow test`. The results are saved with the
  diagnostics snapshot, which you can read without asking the player to copy anything:
  `powershell -ExecutionPolicy Bypass -File tools\read-diag.ps1`. It finds the WoW folder and
  account by itself (override with `FLOW_WOW_DIR` / `FLOW_WOW_ACCOUNT`).
- The saved file is written when the game reloads or logs out, so it shows the **previous**
  session. Ask the player to `/reload` (twice if you need the run that includes your change).
- Useful in game: `/console scriptErrors 1`, `/flow api` (which APIs this client has),
  `/flow rot why`, `/flow nav why`.
- With the repo junctioned into `Interface\AddOns\Flow`, `/reload` picks up edits.
- **A `/reload` is always enough. Never ask the player to restart the game.** WoW: Forever
  reads everything again on `/reload`: changed files, **new files** and the changed `Flow.toc`
  (older WoW clients needed a restart for a new file; this one doesn't). Checked on 2026-11-10:
  `Modules/Nav/RouterDock.lua` was added while the game ran and loaded at the next `/reload`
  (the game client hadn't been restarted). The self-test "core: a file added while the game
  runs loads on /reload" fails if that ever stops being true; only then say "restart".

## Looking at the game while it runs

The saved data only changes on `/reload`, and an add-on can't be asked anything from outside
the game (no sockets, no files: WoW's Lua can't host a service). To see how something looks
right now, take a picture of the game's window and read it:

    powershell -ExecutionPolicy Bypass -File tools\look.ps1
    powershell -ExecutionPolicy Bypass -File tools\look.ps1 -Crop "0.40,0.00,0.20,0.15"

It prints `LOOK <path> <width>x<height>`; open that file with the Read tool. `-Crop` (left, top,
width, height as shares of the window) gives a close look at one part at full size: use it for
small things (the arrow, a menu), which a whole 4K window shrinks too far to judge. `-Scale 0.5`
halves a whole-window picture.

- Only when the player asks you to look, or asked for a visual fix you can check this way.
  It's their screen: a window lying over the game (this app included) is in the picture too.
  The picture stays in `%TEMP%\flow-look`; don't copy it into the repo.
- It shows what's on screen, nothing more. What Flow is thinking is still in the diagnostics
  (`tools\read-diag.ps1`, after a `/reload`).
- Checked on 2026-11-13: the game runs as a borderless window and the capture reads fine.

## Checking the route against a plan of your own

Every diagnostics snapshot carries an export (`Modules/Export.lua`, the `E^...` lines): the
player's quests and objectives, professions, every step Flow knows of (on the route, locked,
hidden) with its place, the route in order, flight paths, nearby flight masters, and Flow
Improvements. After the player reloads:

    powershell -ExecutionPolicy Bypass -File tools\route-check.ps1

It plans the shortest walk through Flow's own steps (keeping what must come first), prints
both orders side by side with their straight-line yards, says what one use of the hearthstone
would save, and lists what has no step at all (a quest in the log, a flight master on the way,
an improvement). Use it whenever the player asks whether the route is right, and before
changing the planner: where Flow is longer, find the rule that made it so (a class quest
first, the zone first, a hub's quests picked up before leaving) and decide whether the rule
or the route is wrong. It doesn't weigh XP or know terrain; say so when you report.
Its last section, "Steps Flow can't place", sorts every locked step into expected ones (a
dungeon, a battleground, waiting for another step) and `TO FIX` / `CHECK` ones: each time
you run it, fix those (a missing source, a reason that reads wrong, a new kind of step) in
the same change, without being asked.
`-From file.txt` runs it on a file of export lines; `-Dump` prints the lines.

## "Watch Flow's in-game chat" (/si in game)

When the player asks you to watch the in-game chat (docs/ASK-CLAUDE.md), or pastes the connect
prompt that `/si` shows in game:

1. Start `powershell -ExecutionPolicy Bypass -File tools\claude-bridge.ps1` with your **Monitor**
   tool (timeout at the maximum; start it again each time it expires). It reads messages from
   Flow's coded screenshots as they're sent (no reload; it deletes them after) and from Flow's
   saved data at a reload, and marks Claude as connected for `/si`. Each stdout line is an event:
   - `READY ...`: it's watching. Tell the player to press Reload in Flow Chat (`/si`), then type
     `/si hello`.
   - `ASK <id> | <who> | <message>`: a message typed in game. Do what it asks in this repo, the
     way this file says (a change gets a test, lint, and on the maintainer's branch a version bump,
     changelog and commit; never push). Then answer it:
     `powershell -ExecutionPolicy Bypass -File tools\claude-bridge.ps1 -Reply <id> -Text "<answer>"`
     The answer shows in WoW's chat window: at most 3 short sentences, plain text, no markdown,
     and say whether they need to `/reload` to see a change (a `/reload` loads new files too:
     never say "restart WoW").
   - `INFO ...`: news about the bridge itself (a Flow screenshot it couldn't read, kept for a
     look). Usually nothing to do.
   - `UPDATE ...`: Flow was updated from GitHub (or an update is waiting). Nothing to do; the
     player was told in game.
   - `DEATH <id> | <who> | <summary> || <findings>`: the player died. Do a **post-mortem**: how
     could the target button have prevented it? Read `tools\read-diag.ps1` (the `[death]` lines
     for that death, which list what Flow suggested and what was cast, plus the `[heal]` and
     `[cast]` lines of that fight). Look for a heal that came late or not at all, a pull the key
     was locked to badly, a missing warning (too many mobs, an elite, out of mana), or a spell
     Flow didn't suggest. Make the improvement the way this file says (a test, lint, and on the
     maintainer's branch a version bump, changelog and commit; never push). Then tell the
     player in 1 or 2 sentences:
     `powershell -ExecutionPolicy Bypass -File tools\claude-bridge.ps1 -Note "Your death at 23:10: ... Flow now ..."`.
     If nothing would have helped, say so in the note.
2. On a clone that follows `main` (not the maintainer's branch), change files but don't commit or
   bump the version; offer to open a pull request (CONTRIBUTING.md).
3. Every answer is shown only after the player's next reload: **Reload** in Flow Chat (`/si`)
   does one, when they choose. WoW can't read files any other way. So say "press Reload" when
   there's something to see.

## "Share my Flow places" (send learned NPC spots to every Flow player)

Flow learns every NPC the player talks to (vendors, repair, trainers, flight masters, innkeepers,
bankers, auctioneers, quest givers) and mailboxes. A player can share those with everyone
(docs/SHARE-PLACES.md). When they ask you to:

1. In game they type `/flow places share`, then `/reload` (the game saves the list on reload).
2. Run `powershell -ExecutionPolicy Bypass -File tools\share-places.ps1` (`-DryRun` first if you
   like). It merges their list into `Learned\Places.lua` and says how many spots it added.
   Then `tools\share-facts.ps1` the same way: it merges the game facts their Flow learned (what
   class trainers teach and don't, where unplaced quests were done: `Modules/Facts.lua`) into
   `Learned\Facts.lua`. "No game facts shared" just means they have none yet.
3. On a clone that follows `main`: a branch, commit only `Learned\Places.lua` and
   `Learned\Facts.lua`, and open a pull
   request to Perpetuator-LLC/flow-wow (CONTRIBUTING.md). Data-only pull requests need **no version
   bump and no CHANGELOG entry**. On the maintainer's branch: commit it with the next version.
4. Never put anything about the player in it: the scripts only write NPC names, NPC IDs, where
   they stand, their roles and the faction that used them, and game facts (class, spell, rank,
   level, price, quest number, map spot). Don't hand-edit the files.
5. **When a player's report shows Flow's built-in data is wrong** (a spell a trainer doesn't
   teach, an NPC with the wrong role, a quest with no place), don't only patch that one case:
   make the game's answer something Flow records (`Modules/Facts.lua`, `Quests/LearnedSpots.lua`,
   `Nav/Places.lua`) so it corrects itself for every player who shares.

## Blocked actions ("Flow has been blocked from an action only available to the Blizzard UI")

These are taint bugs and always ours to fix. **Every time you read the diagnostics, check the
"Blocked actions" section** that `tools\read-diag.ps1` prints (and the `taint.log` lines under it).
If anything is there, fix it before other work, even if nobody mentioned it:

1. The log line names the blamed add-on, the protected function and what was open.
2. `taint.log` (developer installs turn it on: `## X-Flow-Dev: 1` in `Flow.toc`) says which
   Flow line first tainted the path.
3. Fix the cause, not the symptom. Usual causes: assigning a Blizzard global or table
   (`StaticPopupDialogs = ...`), calling Blizzard panel functions from add-on code
   (`ShowUIPanel`/`HideUIPanel` on their frames, `HandleUserActionToggleSidePanel`), or changing
   protected frames or settings in combat. Also tests that stand in for a game function
   (`with(_G, "UnitExists", ...)`): even a moment taints it for the whole session and blocks
   the Flow key (0.35.102). Stand in for Flow's own functions or pass values in; lint refuses it.
4. Add a test (see "taint:" tests in `Modules/Tests.lua`, which use `issecurevariable`).
5. If you can't tell the root cause from the log and taint.log, ask the player what they clicked.
   Don't guess-fix.

## WoW: Forever quirks (learned the hard way)

- **Secret values:** player health and some unit data are hidden from addons. Code must cope
  with `nil`/secret values; `ns.api.Safe(x)` unwraps what it can.
- **Auras** can error when read from tainted code: `Compat.lua` wraps them in `pcall` and falls
  back to remembering your own casts.
- **Combat lockdown:** a secure button can't change what it casts in combat, so the cast key is
  locked to one spell at the pull. Don't try to retarget, interrupt or heal others in combat.
- Macro-type secure buttons are ignored on Forever; use `type = "spell"`.
- `UnitPosition` height is always 0 (no elevation), and nameplate positions are restricted
  ("Can't measure restricted regions").
- Item IDs can differ from classic: match tools and materials by ID **or** name.
- Talents use `C_ClassTalents` / `C_Traits`, not the classic talent API.
- **What a trainer teaches, and for how much, is read from the trainer.** Flow reads the next
  profession tier's line whenever a profession trainer is open (`TR.ReadTier`, kept in
  `ns.db.prof.tierSeen`), and `SP.Tier(..., SP.TierSeen(prof, max))` and `SP.TierCost` go by
  that. Read on Forever (2026-11-13): Journeyman asks for skill 50, no level, 5 silver, as in
  classic. A step at a trainer must carry its price (`goal.cost`), or the route sends a
  player who can't pay.
- **Don't explain a player's report from memory of how the game works: get the game to say.**
  "Journeyman Skinning needs 50 and I don't have it, but it's taking me there" was blamed on
  the profession list (0.35.173), then on a level rule (0.35.174); it was the 5 silver
  (0.35.176). Each guess shipped as a fix and a paragraph of wrong documentation. When a
  report has more than one reading, add the line to the diagnostics that tells them apart
  and wait for it, and say in the reply that the cause isn't known yet.
- Read professions through `ns.api.Professions()` / `ns.api.Skill(name)`: they merge the
  profession slots, the trade skill lines and the profession's own spell (`/flow skills`
  shows each). `ns.api.Skill` returns `0, 0, true` for a profession you have whose skill the
  game doesn't report: treat that as "has it", and plan nothing from the 0. (On the one
  character checked, the slots alone already listed everything.)
- Some item globals are gone (`GetItemCount` lives in `C_Item`). Use `ns.api.Count(id)`,
  `ns.api.ItemInfo`, `ns.api.ItemIcon`, `ns.api.IsUsableItem` (Compat.lua), never the bare globals.
- Never move, resize, show or hide a secure frame (the cast button) in combat, and finish any
  drag of one in `PLAYER_REGEN_DISABLED` (see `ns.cast:EndMove`).

## Lua gotchas that have bitten us

- **Backslashes:** texture paths need doubled backslashes, `"Interface\\Icons\\X"`. In Lua 5.1
  `"\I"` silently becomes `"I"` and the texture is blank. Run `tools\check-paths.ps1` before
  committing: shell heredocs and sed tend to eat one of the two backslashes.
- A `local` must be declared before any function that uses it is defined.
- `ns:Register` errors on a duplicate key; tests that register helpers must do it once, at
  file level.
- **A function defined twice in one file** (`function N:InArea` twice) silently keeps only the
  later one. It broke the map twice (0.35.76, 0.35.123). Lint now refuses it; rename one.
- **Never test a value the game may hide** (`if checked then`, `x > 0`): testing a secret
  errors. Unwrap it first with `ns.api.Safe(x)` (nil = unknown) or `ns.rotation.Yes(x, default)`.

## Data rules

- **Don't copy Questie (or other addons') data into this repo.** Flow reads Questie/QuestieDB
  at runtime when they're installed; that's the arrangement.
- Profession and item data in `Modules/Crafting/Guides.lua` is our own, approximate, and
  corrected by what the game shows.
- **Saved data is shared by every character on the account** (`FlowDB`) unless you declare it
  per character. Anything about one character (its fights, trainer, recipes, spells, bars,
  choices for this character) gets `ns:PerCharacter("section")` or
  `ns:PerCharacter("section.field")` next to its `ns:OnLoad` (see `charData` in
  docs/ARCHITECTURE.md). Settings, learned trails and NPC places stay shared.

## Style

- **Step, objective, waypoint** each mean one thing (docs/ARCHITECTURE.md, "Words"): a *step* is
  one thing the route has you do, usually at one place (Flow's word, for everything Flow plans
  or shows; it was "stop" until 0.35.251, and code names such as `StopKind` still say so); an *objective* is a line of a quest (the game's word, only for quests); a *waypoint*
  is a spot the player set themself. Never "objectives" for steps.
- Comments explain *why* and what the player sees, in plain English.
- Player-facing text is short, plain and specific ("Loot Stringy Wolf Meat 9/66"), never
  jargon.
- Keep features optional and quiet: nothing should nag; the route should just be right.
- Every Flow panel gets its title bar from `ns.theme:TitleBar(parent, title, icon)`
  (`Modules/Theme.lua`): the same dark bar, orange accent and gold title as the Flow Tracker,
  Router and Seller. Colours come from `ns.theme`, never hard-coded per panel.
- **Every view is named "Flow <Name>"**: Flow Tracker, Flow Router, Flow Seller, Flow
  Improvements, Flow Chat, Flow Spells, Flow Talents, Flow Professions, Flow Settings, Flow
  Setup, Flow Key Bindings, Flow Banker, Flow Meters, Flow Auctions, Flow Prices, Flow Trader, Flow Deaths. Use that name in its title and wherever text mentions it ("Buy it back in the Flow
  Seller"), and give any new view one the same way.

## Every change

1. Code + a test in `Modules/Tests.lua`. For anything the player clicks (a button, a menu, a
   dropdown), add a **click test**: call its OnClick script in a `pcall` the way a click would,
   and check what should appear did (see "click:" tests). Self-tests run at every `/reload` and
   logout on a developer install (with the diagnostics), never by themselves on a release, and
   not after login unless `/flow test login on` (0.35.373: they are about 3 s of work and made
   the first seconds after login stutter). So a broken button shows in the next diagnostics.
   Anything that builds a menu goes through `ns.menu:RouteItems()`-style safe builders: one
   failing entry must not stop the menu opening.
2. Before READY, the branch tip's GitHub Checks run must show `tools\lint.ps1` at **0 warnings** (it runs luacheck with `.luacheckrc`, then `check-paths.ps1`). It catches
   a missing `local`, a `local` used before it's declared, typos in names and unused values.
   Fix the code rather than widening `.luacheckrc`; use `_` for values you don't need.
   Lint can't see game values that differ on Forever (vectors that are plain tables, globals
   moved into `C_*`): those need an in-game test.
3. Bump `## Version:` in `Flow.toc` (patch number) and add a `CHANGELOG.md` entry at the top,
   written for players. **Contributors sending a pull request** (anyone but the maintainer):
   don't bump the version; put the entry under `## Unreleased` at the top of `CHANGELOG.md`.
   The maintainer numbers it when merging. See CONTRIBUTING.md for the fork / branch / PR steps.
4. If you add a registry kind, a command or a feature, update `docs/ARCHITECTURE.md` and the
   README feature list.
5. One commit per change, message `Flow x.y.z: what changed`.
6. **A new option** goes in the settings group where a player would look for it while doing
   that thing (`S.GROUPS` in `Modules/Settings.lua`: Your easy key, In a group, Finding your
   way, Quests, Loot and selling, New spells and professions, On your screen), not in a group
   named after the part of Flow that implements it. From another file:
   `ns.settings:AddCheck{ group = "route", ... }`. The game's own settings stay apart, under
   "Suggested WoW settings".
7. **A new Flow view that goes with one of the game's windows** gets a button on that window:
   one `ns:Register("gameButton", ...)` (`Modules/GameButtons.lua`). The view stays closed until
   it's clicked.

## Merging pull requests (the maintainer's branch only)

[docs/MERGING.md](docs/MERGING.md) is the checklist: fetch the heads, merge stacked pull
requests bottom up in a side worktree, settle the changelog with `tools/pr-changelog.sh`,
review against the list of things that keep coming up, fix on top as one more version, check
the heads again, fast-forward, push, confirm they closed. If a merge teaches you something that
isn't in it, change that file in the same commit.

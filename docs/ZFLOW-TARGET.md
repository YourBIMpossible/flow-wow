# Z-Flow target architecture

Status: revision 2, 2026-11-21, written by the WoW foreman on White. Working name Z-Flow; the public name is not settled.
Authority: the owner's "Architectural direction correction" and "Working product name: Z-Flow" messages (recorded verbatim in F:\flow-wow-program\ANCHOR.md).
Detail behind every verdict here: F:\flow-wow-program\arch\A-core.md, C-items-crafting.md, D-rotation-class.md, B-nav.md (B is not delivered yet; section 6 is delivered).
Nothing in this document has been run in the game.

## 1. What is fixed and what is free

Fixed (owner-approved experience):
- The quest arrow's graphic, size, colour meanings and interactions.
- The stacked presentation: solid quest arrow in front, translucent profession arrow behind, each turning on its own like a clock hand, text placed as it is today.
- Separate, place independently, restack. When separated the profession arrow takes the quest arrow's colour meanings and stays lower-opacity and secondary.
- Useful player data, carried by a deliberate import.
- The playable Flow installation stays untouched while Z-Flow is built.
- Flow never heals, retargets or interrupts for other players in combat.
- WoW: Forever features only. No third-party data without documented rights. Unknown stays unknown.

Free: architecture, registries, planner interfaces, settings schema, file boundaries, recent repairs, and the existing tests' wiring. Tests' assertions are kept as an acceptance list; their drivers may be rewritten. No check is weakened.

## 2. Installation identity

| Thing | Flow today | Z-Flow |
|---|---|---|
| Addon folder and TOC | Flow, Flow.toc | ZFlow, ZFlow.toc, Title "Z-Flow" |
| Namespace | private table plus some globals | private table only; no public global |
| Saved data | Flow's account and character tables | ZFlowDB (account), ZFlowCharDB (character) |
| Slash commands | /flow and others | /zflow; /way only if no other addon has claimed it |
| Frame names | Flow* | ZFlow*, always built from ns.id.framePrefix |
| Key binding header | FLOW | ZFLOW; secure button ZFlowCastButton |
| Addon message prefix | Flow | ZFlow, with a protocol version field |

Rule: every one of these strings is read from one file, Core/Identity.lua (ns.id = {addon, title, framePrefix, slash, commPrefix, bindingHeader}), plus the TOC, Bindings.xml and the folder name. No repository-wide search and replace. A structure check fails the build if a literal "Flow" identity string appears outside those places.

### Loading both at once: not supported, and guarded

Separate names do not prevent interference: both addons would claim the same key bindings, both would act at a vendor (sell, repair), both would accept and turn in quests, both would set the one waypoint, and both would hook the same client functions. So:
- If Flow is loaded, Z-Flow registers no events, bindings, hooks or automation. It shows one panel: "Flow is also enabled. Z-Flow is paused." with two buttons: Import from Flow, and Turn Flow off and reload.
- Z-Flow never writes Flow's saved tables and never reads them except inside the import below.

Needs a client check: load order between the two, whether an addon can be disabled from a button on this client, whether an old binding lingers after Flow is turned off, addon-message prefix registration.

### Import from Flow

- One pure function: Import.FromFlow(flowDb, flowCharDb) -> {account, char, dropped}. It copies; it never mutates its inputs. It has a version number and records what it did under ZFlowDB.imports (source schema, date, counts, dropped keys with reasons).
- Route 1 (default): in the client, while Z-Flow is paused and Flow is loaded. The player presses Import. Account data and the logged-in character's data are copied. Each other character imports when the player logs it in.
- Route 2 (optional, later): an offline tool the owner runs against saved files. It touches WTF, so it is the owner's action, never a worker's.
- Running import twice is safe: it merges learned data by key and never lowers a newer Z-Flow value.
- Tested offline with fixture tables built by hand. No real saved data enters the repository.
- Carried: learned places, flight paths, observed prices, observed facts, fight records, the player's settings where a matching Z-Flow setting exists, arrow positions. Dropped, with a listed reason: caches, anything derived, settings with no successor. Full key lists: arch\A-core.md section 3.

### Saved schema

ZFlowDB = { schema = 1, settings, layout, learned = { places, flights, prices, facts, fights }, imports }
ZFlowCharDB = { schema = 1, settings, layout, learned, state }

Changes after schema 1 go through an integer migration ladder, one tested step per number.

## 3. Verdicts by subsystem

K = keep, F = refactor, R = replace, X = remove.

### Core
| Subsystem | Verdict | Reason |
|---|---|---|
| Registry (ns:Register) | F | Kinds are declared (ns:Kind) so a bad row fails that row, not the file |
| Event bus | F | Handlers get an owner, can be removed, and are timed |
| Load sequence | R | Three phases (declare, wire, start) replace order-dependent OnLoad bodies |
| Timers | R | One Scheduler; today's scattered tickers cannot be budgeted or paused in combat |
| Saved-data bootstrap and per-character split | R | Two real stores with scope chosen per key; fixes F-009 |
| Migrations | R | Schema ladder plus the importer; old migrations are not carried |
| Settings | R | Declarative ns:Setting rows drive storage, the panel and setup; one source of defaults |
| Setup wizard | F | Reads the same setting rows |
| Menu, move handle | K | Widget is sound; content moves to the modules that own it; MakeMovable merges into the handle |
| Slash commands | F | A registry kind (F-100) |
| TOC | R | Generated from a manifest; hand-edited load order is the source of the OnLoad errors |
| Facts | F | Observed facts overlay first-guess values (F-017) |
| Perf | R | Folded into Scheduler timing; Pulse kept; Reveal refactored |
| Test harness | K, extended | Real skip status; a fake client so frame-touching logic runs offline; tests split per module; not shipped in the addon |

### Items, money, crafting
| Subsystem | Verdict | Reason |
|---|---|---|
| Reserve (branch p2-pr7-resources) | K with four changes | Becomes the Resources resolver; see section 4 |
| Disposition engine | K | One Decide(item, context) with a reason and a basis |
| Vendor | F | Acts only on a decision from Disposition; each automation defaults off |
| Banker | F | Drops its private "needed by" list; asks the resolver |
| Trader | F | Budget comes from the resolver |
| Quest bags | F | Becomes a claim producer |
| Skill planner file | R | Split into planner (pure) and presenter; the pure functions are kept |
| Profession guide data | R | Paths and colours are third-party with no documented rights; planning runs on observed recipes until the team authors its own model |
| Craft hint | F | Its second stock count is removed; uses the snapshot |
| Professions | F | Each profession registers as an activity |
| Prices | R | One service that always says observed, estimated or unknown (F-085) |
| Gear scoring | F | F-006; nil weights mean "no recommendation", never zero |
| Gear analysers | X where placeholder | Placeholder analysers present guesses as findings |
| Gear sets | F | Fix alt adoption (F-013) |

### Rotation and class
| Subsystem | Verdict | Reason |
|---|---|---|
| Decision core | R | Pure ns.Choose(snapshot, pack, prefs, bias) returning a suggestion and a trace; today's logic reads the client mid-decision and cannot be tested offline |
| Engine helpers, form plan, queue | K | Already pure |
| Survival model | F | Reads the snapshot |
| Cast layer | K behind ns.cast.Apply(plan) | Secure and taint-sensitive; rewriting it buys nothing |
| Display | F | The tick moves to the driver |
| Self-buff button | F | Stops patching the chooser at run time |
| Client compatibility | K, extended | Power, pet, totem, weapon coating, item counts |
| Class packs | R format, content ported | One declared pack per class with a provenance block and a structure check |
| Advisor | F | Items get a stable id and an evidence tag: fact, recommendation or first guess (F-099) |
| Group dispel advice in combat | X | Helping other players in combat stays out |

### Navigation and arrows (from arch\B-nav.md)
| Subsystem | Verdict | Reason |
|---|---|---|
| Nav.lua (5,326 lines) | R by decomposition | One file holds goals, planning, plan state and arrow frames; split into the parts below |
| Planner | F | Pure function over a context; fixes F-030, F-032, F-033 |
| NearFirst, XpValue | R | They patch the planner at run time and mutate goals |
| Needs | K | |
| Goals, Focus | F | Goals become immutable with a three-valued `known`; Focus stops wrapping selection |
| Legs, Crossings, Gates | K pure cores | Storage moves to the store |
| Places, Services, learned spots | F | Keys by id and faction; a learned spot can be corrected |
| Flight code (four files) | F, merged | One Travel layer |
| Party, party help, dungeons | F | Become activity policies; no in-combat help for other players |
| Quest modules | F | One QuestData reader; auto turn-in, quest levels, quest bags kept |
| Minimap pin | R | |
| Map overlay, route tracker, other readers | F | Read the plan store only |
| Zone fish and zone level tables | X or re-source | Marked as taken from Wowhead and a wiki; no rights recorded |
| Activity contract (branch p2-pr1-activity) | K registry kind, A.Of, A.Split and tests | The interim `exists` rule, the fallback and the compatibility views are not carried; `exists` never depends on arrow display |
| Arrow layout (branch p5-pra-arrowviews) | K four pure functions and tests | Views that wrap the old frame and its child are not carried |
| Arrow frames | R frames, K art | New frames driven by the layout function; art, sizes and colours fixed by section 5 |

Provenance to clear before these tables enter Z-Flow (class C or unsourced): zone fish, zone levels, Places notes taken from a levelling guide, skill spots carrying Questie object IDs, exported Questie-derived coordinates, and the unsourced innkeeper, crossing, ride and mount tables. Each is removed, re-read from the client, or re-authored with a note.

One correction to the P5 design: a separated profession arrow uses the quest arrow's colour meanings at lower opacity, not "the activity's colour".

## 4. Shared contracts

Kernel
- store:get(scope, path), store:set, store:watch, store:table. Scope is "account" or "char".
- ns:Setting{ key, scope, type, default, label, help, group, requires }
- bus:on(owner, event, fn), bus:off(owner), bus:emit(event, ...)
- sched:every, sched:after, sched:nextFrame, sched:afterCombat, sched:report
- client.*: the only place client API is called. Two implementations: real and fake.
- ns:Module{ name, needs, provides, settings, events, ticks, start }; ns.use(name)
- ns:Kind{ name, row }; ns:Register(kind, key, row)
- ns.id (section 2)

Items and money
- Items.Key(link or id) -> key
- Resources.Take() -> snapshot: a plain value { bags, bank, bankKnown, bankSeenAt, money, slots[family] = { free, total } or unknown, takenAt }. Resources.Fake(t) for tests.
- Claim: { owner, activity, kind, key, amount, required, selected, priority, bank }
- Resources.Resolve(snapshot, claims) -> grants. Two passes: required claims first, then optional by priority. grants:For(owner), grants:Held(key), grants:Free(key).
- Prices.Get(key, kind) -> { value, basis = observed | estimated | unknown, source, seenAt }; Prices.Record; Prices.Text. An estimate is always labelled and never decides affordability. Unknown reads "price unknown - check trainer".
- Disposition.Decide(item, context) -> { action, count, reason, rule, basis }
- ns:Register("activity", "profession:<name>", { order, targets, plan, present })

Rotation and class
- ns.Snapshot() and ns.SnapshotOf(fields): a plain value of everything a decision reads.
- ns:Register("classPack", CLASS, { provenance, roles, resources, maintain, lists, groups, heals = { self }, interrupts, breakers, dispels, keys, weights, proficiency, spells, talentBuilds, options }); ns.PackCheck(pack) fails on a missing key or an unknown required spell.
- ns.Choose(snapshot, pack, prefs, bias) -> suggestion, trace
- ns.KeyPlan(pack, prefs) -> bindings; ns.cast.Apply(plan)
- ns:Role()
- Advisor item: { id, text, evidence = fact | recommendation | firstGuess, ... }
- ns.fights.Add, ns.fights.Each
- Class data follows F:\flow-wow-program\CLASS-DATA-EVIDENCE-POLICY.md.

Navigation and arrows
- Activity: the shape in branch p2-pr1-activity (ns.activities).
- N.ArrowLayout(state) -> { quest = {...}, prof = {...} } with fields for position, alpha, scale, tint and faint (no scale control is added); N.ArrowGate, N.ClampPoint, N.StackSnap, N.ArrowBeside.
- Arrow positions are saved under layout; stacked is the default; restacking happens by snap when one arrow is dropped on the other, and from a menu item.
- Goal: immutable, with `known` = yes, no or unknown.
- Plans.Each, Plans.Get, Plans.Choice, Plans.Target, Plans.At, Plans.AllGoals, Plans.Select; bus events PLAN_CHANGED, TARGET_CHANGED, GOALS_CHANGED.
- Position.Get, Position.ToWorld and a position-changed signal.
- Signatures: arch\B-nav.md section 5. Exact arrow values with source lines: arch\B-nav.md section 3.1 (56x56 button, 64x64 art, six textures, easing 14; grey away, orange at 600 yd through yellow to green at 40 yd, blue in area, red corpse; needle 25.6x109.1 at holder alpha 0.85; quest arrow 0.8 scale and 0.7 alpha over the needle).
- Navigation build order: provenance cleanup, golden fixtures, services, goal and activity model, planner, plan store, arrows (pure first), readers, party and dungeon policies, import, then Nav.lua is deleted.

## 5. Arrow acceptance (owner's words govern; F:\flow-wow-program\ANCHOR.md)

1. Stacked: looks and behaves as today, including text placement.
2. Quest arrow: graphic, size, colour meanings and interactions unchanged, stacked or separated.
3. Each arrow can be dragged to its own place; both places survive reload and relog; an off-screen saved place is clamped back.
4. Restack returns to the exact stacked presentation.
5. Separated profession arrow: same colour meanings as the quest arrow, lower opacity, visibly secondary.
6. Not reported as implemented until code, saved-layout tests and in-game visual checks all show it.

## 6. Audit findings

Every finding in F:\flow-wow-program\LEDGER.md keeps its number and gets one of: closed by a replaced subsystem (named), carried as a test case into the new module, or still open with an owner. No finding is dropped because its file is replaced. The ledger gains a "Z-Flow disposition" column in the first integration checkpoint.

## 7. Scope carried forward

Shared quest and profession goals; dungeon preparation; goal-driven crafting; class support for all classes on this client; settings; diagnostics; verification. Nothing here adds scope beyond the agreed product.

## 8. Development line

- One branch, zflow, in the existing repository, started from program-integ a529eea, pushed to the fork only. No new repository.
- The first checkpoint is a tag, zflow-cp0: the base plus the worker branches that survive (Cat Form rule, Reserve, Activities, arrow layout, runner fixes), all three checks reported.
- Z-Flow is built in a new top-level folder, ZFlow, beside the existing Flow source. Modules move across as they are rebuilt on the kernel. The Flow source stays in the tree, building and tested, until Z-Flow covers it; then it is removed in one commit. This is a working arrangement, not a compatibility layer: Z-Flow code never calls Flow code.
- The live game install is not pointed at Z-Flow until the owner says so in an authorized handoff.

## 9. Build order

1. Kernel: Identity, Client boundary with fake, Store, Settings, Bus, Scheduler, Module and Kind, load phases, the load guard, generated TOC, test tiers.
2. In parallel on the kernel:
   - Items: snapshot, resolver, prices, Disposition context, then planner and presenter, craft hint, gear.
   - Rotation: snapshot, pure chooser and PackCheck, Druid then Paladin to parity, driver and Apply, then the other classes in pairs.
   - Navigation: activities, arrow frames on the layout function, then routes per B.
3. Import from Flow, with fixture tests.
4. Settings panel, setup and diagnostics on the setting rows.
5. Retire the Flow source.

Each step ends in a commit on zflow with lint, structure and test counts reported separately, and a line for what still needs the game.

## 10. Decisions (revision 2, 2026-11-21)

The owner's operating correction of 2026-11-21 settled most of the earlier questions. Classes: A = answered by the owner; B = engineering choice made by the lead; C = reversible product default chosen by the lead; D = open for the owner.

| # | Subject | Class | Decision |
|---|---|---|---|
| 1 | Where the profession arrow goes on first separation | C | Directly below the quest arrow, one arrow-height away. The player then drags it anywhere. |
| 2 | Minimap dot and map path colour when separated | A | No change. Separating the arrows does not alter map or path styling. |
| 3 | Quest arrow at 0.7 opacity and 0.8 scale while the profession needle is under it | C | Kept exactly as the source draws it today. The owner called the quest arrow "solid"; the source draws it slightly faded when stacked. Nothing is changed until this difference is looked at in the game (one line in the first in-game batch). |
| 4 | Arrow positions per account or per character | C | Per account. |
| 5 | Arrow scale control | A | None added. Not a prerequisite. |
| 6 | Vendor automations | A | Each defaults off for a new install; a deliberate import keeps the player's explicit choices. |
| 7 | Profession planning without third-party guide paths | A | Observed-only planning is an intermediate limitation. The team authors its own planning model under the evidence policy; the finished product is not observed-only. |
| 8 | Group cure icon in combat | A | Not shown. The restriction on helping other players in combat stands. |
| 9 | Existing Druid and Paladin weights and talent order | B | Re-derived by the team from client reads with a provenance note; the old values ship meanwhile labelled first guess. |
| 10 | Flow and Z-Flow loaded together | B | Not supported; Z-Flow pauses itself (section 2). |
| 11 | 3D and flat arrow styles | C | Carried unchanged. They are part of the current quest arrow. Inventory of both styles is part of the navigation behaviour inventory. |
| 12 | Tables with no recorded origin (innkeepers, crossings, rides, mounts) | B | Undocumented origin is not proof of copying. Each is checked against client reads and given a note, or re-read. Tables whose own header names a third-party source (zone fish, zone levels, guide notes, Questie IDs) are replaced by client reads or authored models. Nothing unresolved enters a public release. |

Open for the owner (class D): none at this revision.

## 11. Kernel as built (revision 3, 2026-11-22)

The kernel is merged on `zflow`. Where it differs from section 4, this section is the contract.

- `store:watch(scope, path, fn)`: the scope is the first argument.
- `store:get` returns the stored value only. Defaults come from settings rows.
- Event handlers and ticks receive `ctx` as their first argument. `bus:on` returns a cancel function.
- Ticks have no `when = "visible"` yet. It is added with the first frame code.
- The client surface has no bind, hook, unit or bag calls yet. The module that first needs one adds it to Core/Client.lua and Core/ClientFake.lua through the kernel owner (White).
- The load guard also treats an existing `FlowDB` table as "Flow is loaded".
- Not built yet: switching a module off after repeated errors; test tiers.
- Structure rule: no `print`, `_G`, `os` or `io` outside Core/Client.lua, tests included.
- To add a file: add its path to `files` in ZFlow/manifest.lua, then run tools/zflow-toc.ps1. Tests go under ZFlow/Tests/<Area>/ and build a fresh kernel with `ns.Kernel({}, ns.make.fakeClient())`.
- Checks: tools/zflow-tests.ps1 and tools/zflow-structure.ps1. tools/zflow-boot.lua stays usable for branches that have not merged the kernel yet.
- Not confirmed in the game client: which add-on-loaded query exists, debugprofilestop, the order of PLAYER_LOGIN against saved variables, InCombatLockdown, and that the generated TOC loads.

## 12. Navigation inventory and the "solid" quest arrow (revision 4, 2026-11-22)

- The full behaviour inventory is F:\flow-wow-program\arch\B-nav-inventory.md: 113 behaviours, about 60 saved keys, with a proposed Z-Flow home and test kind for each. No navigation source is retired until its rows there are built or deliberately dropped with a reason.
- Decision 3 is reconciled with the source. The quest arrow is drawn at full alpha and full scale by default. It is drawn at scale 0.8 and alpha 0.7 only while the profession needle is shown under it. That needs all of: the profession arrow setting on; a profession step chosen; the player more than 24 yd from that step and not inside it; more than 24 yd from the main step's own point; bearing and facing known. This holds in all three arrow styles. This is the approved stacked look and is kept. It is still in the first in-game batch to look at.
- When the arrows are separated there is no needle under the quest arrow, so the quest arrow is always at full alpha and scale.
- Faults in the source that Z-Flow must not copy (each is a required test): the corpse arrow keeps 0.8 / 0.7 if the player dies while the needle shows; the arrived ring is drawn at 0.8 / 0.7 inside a main step's area but off its point; the travel icon changes the arrow's scale and can leave scale 1.0 with alpha 0.7. Rule: scale and alpha are computed from the current state on every update, never left over from the last one.
- Source fact: the pure layout functions and saved `nav.arrows` on the Flow line are used only by tests, not by live frames; the live arrow is not clamped to the screen and has no reset. Z-Flow drives the live frames from the layout data, clamps to the screen, and has a reset.

## 13. Checkpoint 1: interface decisions (lead, 2026-11-22)

Merged at tag `zflow-cp1` plus the import module: Items (Key, Resources, Prices, Disposition), Rotation (Pack, Snapshot, Choose, KeyPlan), Classes/Druid, Nav/ArrowLayout, Import/FromFlow. All pure; nothing is wired to the client yet.

- `Prices.Get(book, key, kind)`: book first. Accepted.
- Disposition `basis` is one of "choice", "fact", "recommendation", "unknown"; actions keep, sell, auction, disenchant, equip. Accepted.
- `Resources.Take(read)` with `read.money()`, `read.bags()`, `read.items()`, `read.bank()`. Accepted; the adapter is built in Core/Client.lua (White).
- The "classPack" kind stays declared in Rotation/Pack.lua. Core owns only kinds used by more than one area.
- The binding list from KeyPlan is the input of `ns.cast.Apply(plan)`; shape as Twin proposed, final when Rotation/Cast.lua is built.
- Saved arrow layout: account scope, `layout.arrows = { mode, points = { quest, prof }, hidden, text }`, point `{ anchor, relativeAnchor, x, y }`. Accepted.
- Zones reach Nav as `{ cont, zone }` from Core/Client.lua (White).
- Player messages never spell the product name; they read it from `ns.id`.
- Import: `Import.FromFlow` and `Import.Merge` are pure and nothing calls them. Flow writes its vendor defaults into saved data, so a stored "on" for auto-junk or auto-repair cannot be told from a choice. Rule: the import screen lists every vendor automation it would switch on and the player confirms each; without that confirmation it stays off. The caller stamps the import date. Settings paths are provisional until setting rows exist.

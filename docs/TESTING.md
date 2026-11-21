# Testing Flow

Flow has one set of self-tests, registered in Lua and run two ways:

- **In the game** (`/flow test`): the real check. Every test runs against the real client.
- **Offline** (`tools/run-tests.ps1`): plain Lua 5.1 with fixture stubs. Only the tests that
  need nothing of the game can pass there; the rest are reported SKIP. It runs in CI too.

Neither is a gameplay test. A test checks Flow's own logic with made-up inputs. Whether a
feature works for a player is still checked by playing (class, level, zone in the PR).

Counts below are from 2026-11-21 (Flow 0.35.377 plus the program base d356a8f). Re-run the
commands to refresh them; don't edit the numbers by hand.

## How the harness works (Modules/Tests.lua)

- A test is a registration: `ns:Register("test", "area: what it checks", function(t) ... end)`.
  `t:ok(cond, msg)`, `t:eq(actual, expected, msg)`, `t:near(a, b, tol, msg)` each count as
  one check. `ns:Register` errors on a name used twice, so every test name is unique
  (`tools/check-structure.ps1` checks it without the game).
- Each test runs inside `pcall`. A test passes when none of its checks failed. A Lua error
  inside it counts as a failure, with the line `error: <message>`.
- Output: a summary `tests: P passed, F failed (C checks)`, then for each failure
  `FAIL <name>` followed by its failed checks, indented. A failed run also opens in Flow's
  copy window so it can be copied out.
- `/flow test <text>` runs only the tests whose name contains `<text>` (case doesn't matter):
  `/flow test route`, `/flow test click`.
- `/flow test` refuses to run in a fight: many tests open windows and set key bindings, which
  the game doesn't allow in combat.
- **When they run without being asked** (`ns.tests.Auto`):
  - A developer install runs them at `/reload` and logout, as part of the diagnostics
    snapshot. A developer install is one whose `Flow.toc` has `## X-Flow-Dev: 1`. The repo's
    copy has it; release zips drop it (`tools/package.ps1`).
  - On a developer install, after login, they run only if you turn it on with `/flow test login on` (and never in
    lite mode). They are spread over frames (`ns.tests.Spread`, at most `ns.tests.BUDGET` ms a
    frame) because all at once stalled the game for over a second.
  - A release install never runs them by itself; `/flow test` does.
- All 640 tests are in `Modules/Tests.lua` today. New lane work adds files under
  `Modules/Tests/`, which must also be listed in `Flow.toc`.

### Categories (by the name before the first colon)

The name's first part is the area. There are 212 such prefixes; the largest, with their
offline results as counted at 640 tests (today's totals are in the runner section below;
`-Verbose` gives each test's status):

| prefix | tests | offline PASS | offline SKIP | offline FAIL |
|---|---:|---:|---:|---:|
| click | 70 | 8 | 62 | 0 |
| route | 27 | 15 | 12 | 0 |
| target button | 26 | 16 | 10 | 0 |
| banker | 17 | 11 | 6 | 0 |
| bags | 15 | 3 | 12 | 0 |
| professions | 15 | 8 | 7 | 0 |
| actions | 12 | 6 | 6 | 0 |
| arrow | 11 | 7 | 4 | 0 |
| map | 11 | 3 | 8 | 0 |
| quests | 11 | 5 | 6 | 0 |
| gear | 9 | 2 | 7 | 0 |
| easy key | 8 | 4 | 4 | 0 |
| planner | 8 | 8 | 0 | 0 |
| skillplan | 8 | 2 | 6 | 0 |
| crafting | 7 | 3 | 4 | 0 |
| meters | 7 | 0 | 7 | 0 |
| self button | 7 | 3 | 4 | 0 |
| druid | 6 | 2 | 4 | 0 |
| dungeons | 6 | 5 | 1 | 0 |
| settings | 6 | 0 | 6 | 0 |
| tracker | 6 | 4 | 2 | 0 |
| flight paths | 5 | 1 | 4 | 0 |
| paladin | 5 | 4 | 0 | 1 |
| perf | 5 | 3 | 2 | 0 |
| (no colon in the name) | 10 | 3 | 7 | 0 |
| 187 other prefixes | 322 | 156 | 165 | 1 |
| **total** | **640** | **282** | **356** | **2** |

To recount the prefixes from the source:

```
grep -ohE 'ns:Register\("test", "[^":]+:' Modules/Tests.lua | sort | uniq -c | sort -rn
```

(That grep also counts the example in the file's header comment, `area: what it checks`.)

### Three kinds of test

- **Pure logic** (306 pass offline today): Flow's own functions with
  inputs passed in, such as the planner's order, a seal choice from a role, or a talent sheet split into
  trees. They touch no game global, so they run the same offline as in the game.
- **Game API** (365 skip offline today): they read the client (`UnitLevel`, `C_Map`,
  `GetItemCount`, Questie's data), build or click real frames (the `click` tests), or depend
  on timing (`GetTime`). Only the game can answer these. Offline they are SKIP, never PASS.
- **Secure and taint** (the `taint` prefix, 5 tests, all SKIP offline): what happens when a
  protected action is blocked, and that Flow's code doesn't taint Blizzard's. Taint exists
  only in the client. In the game, the result is in `read-diag`'s "Blocked actions" section
  and the `taint.log` lines under it (a developer install turns the game's taint log on at
  login).

### Skips

- **In the game** there is no SKIP. A test that can't run in your situation records a passing
  check and returns. For example, the heal tests use `deadSkip(t)` when you're a ghost
  (5 tests), with the message "(you're dead: this test runs again once you're alive)". It is
  counted as passed, so a ghost's "all passed" includes those 5 unrun tests.
- **Offline** a SKIP is explicit and names the first client global the test touched (below).

## Reading in-game results from outside the game

After a `/reload`, logout or exit, the game writes Flow's saved data, including the
diagnostics snapshot (`FlowDB.diag`).

```
powershell -ExecutionPolicy Bypass -File tools\read-diag.ps1 [-Tail 60] [-Account NAME] [-WowDir PATH]
```

It finds the WoW folder and account by itself (set `FLOW_WOW_DIR` / `FLOW_WOW_ACCOUNT` if the
guess is wrong). It reads `WTF\Account\<account>\SavedVariables\Flow.lua` and prints:

- `=== Snapshot ===`: one `--- <check> (<ms>)` heading per check. The `--- tests` section has
  the summary line and every `FAIL` line. It says "not run" on a release install, or after
  login unless `/flow test login on`.
- `=== Log ===`: the last lines of Flow's log, `[tests]` lines among them.
- `=== Blocked actions ===`: every "only available to the Blizzard UI" error. It is always
  printed, also when there are none.
- `=== taint.log (Flow lines) ===`.

The file is only as new as the last `/reload`. Its time is printed on the first line, so
check it before trusting a result. `read-diag` only reads the file; it never writes to the
game folder.

## Offline runner (tools/run-tests.ps1)

```
powershell -ExecutionPolicy Bypass -File tools\run-tests.ps1                 # Windows
pwsh -File tools/run-tests.ps1                                               # Linux / CI
tools\run-tests.ps1 -Filter route      # only tests whose name contains "route"
tools\run-tests.ps1 -Verbose           # every test's status, and what Flow printed
tools\run-tests.ps1 -ListModules       # which files loaded, and which touched the client
tools\run-tests.ps1 -NoKnown           # count the known failures too
tools\run-tests.ps1 -Known file.txt    # another known-failures list
tools\run-tests.ps1 -Strict            # a SKIP-FAIL fails the run too
tools\run-tests.ps1 -Root F:\other\worktree   # test another checkout with this runner
```

`-Root` tests another checkout's `Flow.toc` and files with this script's own
`tools/offline` (runner and stubs), so the other checkout needs no tools of its own. Its
known-failures list is `<Root>/tools/offline/known-failures.txt` if that exists, else none.

Lua 5.1 is searched for in this order: `$env:FLOW_LUA`, then `lua5.1` / `lua51` on PATH,
then `%USERPROFILE%\tools\lua51\lua5.1.exe`. Only 5.1 is accepted, because it is the game's
Lua. On Ubuntu: `sudo apt-get install lua5.1`.

What it does (`tools/offline/run.lua`):

1. Installs `tools/offline/stubs.lua` on `_G`. **Everything there is a fixture.** Pure
   library helpers the game also has (`strsplit`, `wipe`, `tinsert`, ...) are plain-Lua
   equivalents. `CreateFrame` gives inert frames, so files that build windows at load time can
   finish. Every other client global is missing: reading it gives a marker, which does nothing
   while files load. `io` is missing and `os` has only `time`, `date`, `clock` and
   `difftime`, so no test can end the run or print the runner's own lines.
2. Loads every file of `Flow.toc` in toc order with `("Flow", ns)`, as the game does. A file
   that fails to load (syntax error, runtime error, a key registered twice) or is listed but
   absent fails the run, since its tests would otherwise just be missing. The one allowed
   absence is `Learned/ClaudeInbox.lua`, generated on the player's PC.
3. Fires `ADDON_LOADED("Flow")` once, with empty saved data, like a fresh install. Errors
   Core catches there are always listed; they don't fail the run (fixture frames return nil,
   so `GetFrameLevel() + 2` fails), but a new one should be looked at.
4. Runs each test alone through the harness's own `ns.tests.Spread`, and reports one of:
   - **PASS**: ran to the end on Flow's own Lua and touched nothing of the client. A test
     that made no check at all is counted as "with no checks".
   - **FAIL**: a check failed, and nothing of the client was touched.
   - **ERROR**: a Lua error (or a call to `os.exit`), and nothing of the client was touched.
   - **SKIP** (`needs the client: <name>`): touched a client global or frame method first.
     The summary counts how many of them had a check fail after that touch: offline that
     can't be told apart from the client's absence.
   - **SKIP-FAIL**: a check failed *before* the first client touch, so the client can't be
     the cause. Always listed and counted; it fails the run only with `-Strict`.

The driver's last line is `offline: done, exit <n>`. If it is missing or `<n>` differs from
the exit code, `run-tests.ps1` reports a broken run (exit 2), never a pass. Exit 1: a FAIL or
ERROR outside the known list (or a SKIP-FAIL with `-Strict`), a file that didn't load, a
known name no test has, or no test run (a `-Filter` that matches nothing included).

Result on 2026-11-21, program-integ 560ba1c (about 0.2 s):

```
modules: 151 of 152 files in Flow.toc loaded (109 without touching any client global), 0 failed, 1 absent (1 allowed: generated on the player's PC)
offline tests: 673 run: 306 pass (1 with no checks), 0 fail, 0 error, 365 skip (need the client; 74 of them with checks failing after that), 2 skip-fail (...)
known failures: 0 listed, 0 known allowed (failing, not counted against the run), 0 now passing, 0 not found; 0 new failure(s)
result: OK
```

- **Modules.** 109 files touch no client global even at load time. `-ListModules` names each
  file and how many client names it touched while loading. 3 OnLoad errors (Display.lua:89,
  Nav.lua:4342, Advisor.lua:242), all fixture frames returning nil.
- **SKIP-FAIL today:** `perf: Flow's update loops are timed` and `click: the icons beside the
  Flow icon and the auto-attack badge take clicks`. Both check something the failed OnLoad
  (above) never built, so they are fixture effects, not Flow bugs; `/flow test perf` and
  `/flow test click` in the game decide.
- **The most common reasons to skip** (the first client name each test touched): QuestieLoader
  36, GetTime 32, UIParent 31, InCombatLockdown 30, UnitClass 25, C_Map 17, CreateFrame 13,
  WorldMapFrame 13, UnitLevel 11, GameTooltip 10.
- **Known failures.** `tools/offline/known-failures.txt` lists tests that fail on the base
  branch. They print as `FAIL (KNOWN)` and the summary counts them as "known allowed", apart
  from the passes. Any other FAIL or ERROR fails the run. A known test that passes again is
  reported, so its line can be removed; a known name that no test has fails the run. The list
  is empty today.

**Limits, plainly.** An offline PASS proves the logic on made-up inputs, nothing about the
client. A SKIP proves nothing either way. A file that loads offline could still fail in the
game, for example on an API Forever doesn't have. The offline run doesn't replace
`/flow test` in the game and `read-diag` afterwards.

## Static checks (no Lua needed to read them)

- `tools/lint.ps1`: luacheck with `.luacheckrc`, texture paths with single backslashes, a game
  global swapped inside a test, a function defined twice, and a close button without its own
  OnClick. It must say `lint OK`.
- `tools/check-structure.ps1`: every file `Flow.toc` lists exists, in the same case, and every
  `.lua` file of the add-on tree is listed (everything but `tools`, `.github`, `.claude`,
  `.git`, `dist` and `reports`, which it prints). `-Root path` checks another checkout. No registration key is used twice. It also lists registrations
  inside comments that name a real key (advisor `trainer`, mountRule `default`, talentBuild
  `DRUID`). Those are examples, not duplicates.

## CI (.github/workflows/checks.yml)

On every push and pull request, on Ubuntu, it runs `tools/lint.ps1`,
`tools/check-structure.ps1` and `tools/run-tests.ps1` with luacheck 1.2.0 and Lua 5.1 from
apt. All three are the same scripts a contributor runs locally. A green run means: lint
clean, the toc and registrations consistent, and no new offline failure. It does not mean the
add-on works in the game.

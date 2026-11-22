# Testing Flow

Flow has one set of self-tests, registered in Lua and run two ways:

- **In the game** (`/flow test`): the real check. Every test runs against the real client.
- **Offline** (`tools/run-tests.ps1`): plain Lua 5.1 with fixture stubs. Only the tests that
  need nothing of the game can pass there; the rest are reported SKIP. It runs in CI too.

Neither is a gameplay test. A test checks Flow's own logic with made-up inputs. Whether a
feature works for a player is still checked by playing (class, level, zone in the PR).

This file gives no test counts to keep up to date, apart from one dated sample of the
runner's output. The numbers come from the commands: `tools\run-tests.ps1` prints how many
tests are registered and how many passed, failed and skipped; `tools\check-structure.ps1`
prints how many are registered.

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
- Most tests are in `Modules/Tests.lua`; some are next to the feature they check. A new
  file of tests goes under `Modules/Tests/` and must be listed in `Flow.toc`. Which files
  register tests: `grep -rlF 'ns:Register("test"' --include=*.lua .`

### Categories (by the name before the first colon)

The name's first part is the area (`click`, `route`, `target button`, ...). To count the
tests of each area and how they did offline, largest first:

```
tools\run-tests.ps1 -Verbose -NoSelfCheck | Where-Object { $_ -cmatch '^(PASS|FAIL|ERROR|SKIP|SKIP-FAIL) ' } |
    ForEach-Object { $s, $n = $_ -split ' ', 2; [pscustomobject]@{ Status = $s; Area = if ($n -match '^([^:]+): ') { $Matches[1] } else { '(no colon)' } } } |
    Group-Object Area | Sort-Object Count -Descending |
    ForEach-Object { '{0,4}  {1}  ({2})' -f $_.Count, $_.Name, (($_.Group | Group-Object Status | ForEach-Object { "$($_.Count) $($_.Name)" }) -join ', ') }
```

It counts the tests the runner ran, so an example in a comment (`area: what it checks`, in
the header of `Modules/Tests.lua`) is not among them, as it would be in a grep of the source.

### Three kinds of test

- **Pure logic** (the offline PASSes): Flow's own functions with
  inputs passed in, such as the planner's order, a seal choice from a role, or a talent sheet split into
  trees. They touch no game global, so they run the same offline as in the game.
- **Game API** (the offline SKIPs): they read the client (`UnitLevel`, `C_Map`,
  `GetItemCount`, Questie's data), build or click real frames (the `click` tests), or depend
  on timing (`GetTime`). Only the game can answer these. Offline they are SKIP, never PASS.
- **Secure and taint** (the `taint` prefix, all SKIP offline): what happens when a
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
tools\run-tests.ps1 -AllowSkipFail     # list and count SKIP-FAILs without failing the run (never before a commit)
tools\run-tests.ps1 -MinTests 700      # another floor for the number of registered tests
tools\run-tests.ps1 -NoSelfCheck       # leave out the runner's own self-check
tools\run-tests.ps1 -Root F:\other\worktree   # test another checkout with this runner
```

`-Root` tests another checkout's `Flow.toc` and files with this script's own
`tools/offline` (runner and stubs), so the other checkout needs no tools of its own. Its
known-failures list is `<Root>/tools/offline/known-failures.txt` if that exists, else none.
Its list of the game's globals and its test-count floor are its own
(`<Root>/tools/offline/client-globals.txt`, `min-tests.txt`) if they exist, else this script's.

Lua 5.1 is searched for in this order: `$env:FLOW_LUA`, then `lua5.1` / `lua51` on PATH,
then `%USERPROFILE%\tools\lua51\lua5.1.exe`. Only 5.1 is accepted, because it is the game's
Lua. On Ubuntu: `sudo apt-get install lua5.1`.

What it does (`tools/offline/run.lua`):

1. Installs `tools/offline/stubs.lua` on `_G`. **Everything there is a fixture.** Pure
   library helpers the game also has (`strsplit`, `wipe`, `tinsert`, ...) are plain-Lua
   equivalents. `CreateFrame` gives inert frames, so files that build windows at load time can
   finish. Every other client global is missing: reading it gives a marker, which does nothing
   while files load. Which names are the client's is not guessed: see "The game's globals"
   below. `io` is missing and `os` has only `time`, `date`, `clock` and
   `difftime`, so no test can end the run or print the runner's own lines.
2. Loads every file of `Flow.toc` in toc order with `("Flow", ns)`, as the game does. A file
   that fails to load (syntax error, runtime error, a key registered twice, a global that is
   nobody's) or is listed but absent fails the run, since its tests would otherwise just be missing. The one allowed
   absence is `Learned/ClaudeInbox.lua`, generated on the player's PC.
3. Fires `ADDON_LOADED("Flow")` once, with empty saved data, like a fresh install. An error
   Core catches there ("Flow load error") is listed and fails the run: the `ns:OnLoad` that
   broke left Flow's state half set up, and tests of that state then pass because there is
   nothing to check. If the cause is a fixture frame (a getter that gave nil where the game
   gives a number, as `GetFrameLevel() + 2` once did), the fix is one name in `NUMBER` in
   `stubs.lua`, not a change to Flow.
4. Runs each test alone through the harness's own `ns.tests.Spread`, and reports one of:
   - **PASS**: ran to the end on Flow's own Lua and touched nothing of the client. A test
     that made no check at all is counted as "with no checks".
   - **FAIL**: a check failed, and nothing of the client was touched.
   - **ERROR**: a Lua error (or a call to `os.exit`), and nothing of the client was touched.
     Also: the test read a global that is neither Lua's, Flow's nor on the list of the
     game's (a typo), whatever else it did.
   - **SKIP** (`needs the client: <name>`): touched a client global or frame method first.
     The summary counts how many of them had a check fail after that touch: offline that
     can't be told apart from the client's absence.
   - **SKIP-FAIL**: a check failed *before* the first client touch, so the client can't be
     the cause: it failed on Flow's own Lua. Always listed and counted, and **it fails the
     run**, like a FAIL. `-AllowSkipFail` lists and counts them without failing the run; that
     is for looking at a branch, not for the check before a commit. One that is accepted for
     now goes on the known-failures list by name, where it stays visible. (`-Strict`, the
     old switch that made them count, is accepted and does nothing.)

**The game's globals (`tools/offline/client-globals.txt`).** One name per line: every global
of the game that Flow reads. luacheck (`.luacheckrc`) and the runner both read it. A missing
global that is on the list is the client's: a marker, and a SKIP for the test that touches
it. One that is not on the list is a mistake (`UnitLevle`, or `Distance` for `ns.Distance`):
luacheck warns, a file that reads it while loading fails the run, and a test that reads it is
an ERROR, even inside a `pcall`. A new game API costs one line in that file. Lines starting
`_G:` are names Flow only looks up through `_G` (`_G.MinimapCluster`, `_G["ContainerFrame" .. i]`),
which luacheck doesn't follow; a `*` there stands for the part built at run time. `lint.ps1`
fails on a listed name no Lua file uses any more and on a `_G.Name` that isn't listed. Not
covered: a mistyped field of a game table (`C_Map.GetBestMapForUnti`) is still only a SKIP.

**The timer (`debugprofilestop`).** The one client function with a stand-in, because Flow's
own timed code (`ns.perf`) calls it inside otherwise pure functions. No test passes on what
it measured: a test that reads the global itself is a SKIP, and a passing test whose code
called the timer is run twice more on made-up clocks (each reading 1000 ms after the last,
then 0.000001 ms). It stays a PASS only if it passes all three times; otherwise it is a SKIP,
`needs the client: debugprofilestop`. The summary line "timing fixture" counts both.

**The floor (`tools/offline/min-tests.txt`).** The fewest tests that may be registered,
counted before `-Filter`. Fewer fails the run: a file that stops registering its tests loads
without an error, and only the count shows it. Raise the number when tests are added (the
run prints `registered tests: <n>`); lower it only when tests were removed on purpose.

**The runner's self-check (`tools/offline/self-check.ps1`).** Run first on every run without
`-Filter`. It builds small made-up add-ons in a temporary folder (this checkout's `Core.lua`
and `Modules/Tests.lua` plus one made-up file) and checks that the real `run.lua` fails when
it should: a file that errors or has a syntax error, a file the toc lists that isn't there,
an `ns:OnLoad` that errors, a mistyped global at load, in a test and inside a test's `pcall`,
fewer tests than the floor, a failed check, a SKIP-FAIL; and that a timer-dependent test is
not a PASS and a known failure that now skips is not reported as fixed. If a case fails,
`run-tests.ps1` stops with exit 2 and runs nothing.

The driver's last line is `offline: done, exit <n>`. If it is missing or `<n>` differs from
the exit code, `run-tests.ps1` reports a broken run (exit 2), never a pass. Exit 1: a FAIL,
ERROR or SKIP-FAIL outside the known list, a file that didn't load, an OnLoad error, fewer
registered tests than the floor, a known name no test has, or no test run (a `-Filter` that
matches nothing included).

A sample of the summary (2026-11-21, on a529eea plus the runner changes; run it for
today's numbers):

```
modules: 152 of 153 files in Flow.toc loaded (110 without touching any client global), 0 failed, 1 absent (1 allowed: generated on the player's PC)
ADDON_LOADED delivered to 1 frame(s); 0 OnLoad error(s) caught by Core
offline tests: 717 run: 322 pass (1 with no checks), 0 fail, 0 error, 395 skip (need the client; 74 of them with checks failing after that), 0 skip-fail (a check failed before it touched the client; each fails the run)
client globals: 470 names and patterns in ...\tools\offline\client-globals.txt; unknown globals read: 0 while loading, 0 test(s)
timing fixture (debugprofilestop): 19 passing test(s) read it through timed code and pass on both made-up clocks too; 0 depend on what it said (SKIP)
known failures: 0 listed, 0 known allowed (failing, not counted against the run), 0 now passing, 0 now skipping (can't be judged offline), 0 not found; 0 new failure(s)
registered tests: 717 (floor 717: --min-tests)
result: OK
```

- **Modules.** `-ListModules` names each file and how many client names it touched while
  loading.
- **SKIP-FAIL: none on the base branch.** The two there used to be (`perf: Flow's update
  loops are timed`, `click: the icons beside the Flow icon and the auto-attack badge take
  clicks`) were the harness's doing: three `ns:OnLoad`s broke on a fixture frame whose
  `GetFrameLevel()` gave nil, so what those tests check was never built. With that fixed
  both are plain SKIPs, and 18 tests that had passed only because the frames they check
  didn't exist (they returned early) are SKIPs too.
- **The most common reasons to skip** (the first client name each test touched) are printed
  by every run: `QuestieLoader`, `GetTime`, `InCombatLockdown`, `UIParent` and `UnitClass`
  lead.
- **Known failures.** `tools/offline/known-failures.txt` lists tests that fail on the base
  branch. They print as `FAIL (KNOWN)` and the summary counts them as "known allowed", apart
  from the passes. Any other FAIL, ERROR or SKIP-FAIL fails the run. A known test that passes
  again is reported, so its line can be removed. One that now SKIPs is reported too, but stays
  on the list: offline can no longer say whether it still fails. A known name that no test has
  fails the run. The list
  is empty today.

**Limits, plainly.** An offline PASS proves the logic on made-up inputs, nothing about the
client. A SKIP proves nothing either way. A file that loads offline could still fail in the
game, for example on an API Forever doesn't have. The offline run doesn't replace
`/flow test` in the game and `read-diag` afterwards.

## Static checks (no Lua needed to read them)

- `tools/lint.ps1`: luacheck with `.luacheckrc` (which reads the game's globals from
  `tools/offline/client-globals.txt`, so run it from the add-on's root, as the script does),
  texture paths with single backslashes, a game global swapped inside a test, a function
  defined twice, a close button without its own OnClick, and that list itself (no name on it
  unused, every `_G.Name` on it). It must say `lint OK`.
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

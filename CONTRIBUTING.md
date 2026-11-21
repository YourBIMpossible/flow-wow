# Contributing to Flow

Thanks for helping! Flow is built to be extended without touching its core, so most
contributions are a new file or a new registration.

## Quick start (about 5 minutes)

1. Install World of Warcraft: Forever, and ideally **Questie** + **QuestieDB** (Flow reads their
   quest data at runtime).
2. Clone this repo, then link it into the game so `/reload` picks up your edits
   (Command Prompt; adjust the WoW path):
   ```
   mklink /J "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\Flow" "C:\path\to\flow-wow"
   ```
3. In game: `/console scriptErrors 1`, `/reload`, then `/flow test`. Everything should pass.
4. After a `/reload`, read what Flow saw (tests, logs, diagnostics) from outside the game:
   ```
   powershell -ExecutionPolicy Bypass -File tools\read-diag.ps1
   ```

## Using Claude (or another AI assistant)

Point it at this folder and ask for what you want ("add a Warrior rotation", "Flow should
plan Tailoring"). [CLAUDE.md](CLAUDE.md) gives it the design rule, the code map, how to test
in game and the Forever quirks. Ask it to run `tools\read-diag.ps1` after you `/reload` so it
can check its own work.

## Good first contributions

- **A new class:** `Classes/<Class>/Data.lua`, `Spells.lua`, `Rotation.lua`, listed in
  `Flow.toc`. See "Adding a class" in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
- **Profession data:** guides and item sources in `Modules/Crafting/Guides.lua` (Tailoring,
  Leatherworking, Alchemy, Engineering, Enchanting, Skinning have none yet).
- **Drop rates and Forever-specific item IDs** you've seen in game.
- **Tests** for anything that isn't covered.

## Pull requests

The repo is public: https://github.com/Perpetuator-LLC/flow-wow. With the
[GitHub CLI](https://cli.github.com/) (`gh auth login` once):

```
gh repo fork Perpetuator-LLC/flow-wow --clone      # your copy, with "upstream" set
git checkout -b my-change                          # one branch per change
# ...edit, test, lint...
git push -u origin my-change
gh pr create --repo Perpetuator-LLC/flow-wow --base main
```

Before starting a new change, bring your copy up to date: `git checkout main`,
`git pull upstream main`, then branch from there. If `main` moved while your PR was open,
`git fetch upstream` and `git rebase upstream/main` (fix any conflicts, lint again, then
`git push --force-with-lease`).

- One feature or fix per PR, with a test in `Modules/Tests.lua`.
- `powershell -ExecutionPolicy Bypass -File tools\lint.ps1` must say "lint OK" (needs
  [luacheck.exe](https://github.com/lunarmodules/luacheck/releases); the script says where to
  put it).
- `tools\check-structure.ps1` must say "structure OK", and `tools\run-tests.ps1` (Lua 5.1)
  must report no new FAIL or ERROR. CI runs all three on your PR. An offline PASS isn't a
  game test; see [docs/TESTING.md](docs/TESTING.md).
- **Don't bump the version** in `Flow.toc`. Add a player-facing line under `## Unreleased` at
  the top of `CHANGELOG.md` (add that heading if it isn't there). The maintainer gives it a
  version number when merging, so PRs don't collide over the version line.
- **If it builds on another open PR of yours**, say so in the description ("builds on #18").
  The maintainer merges them bottom up; knowing the order saves working it out.
- Say how you tested it in game (class, level, zone) and paste the `/flow test` result.
- Don't commit `Learned/CombatLog.lua` changes (it's generated from your own combat logs),
  anything from your `WTF` folder, or data copied from other addons or sites.
- Flow is licensed under the [GPLv3](LICENSE). By sending a PR you agree your contribution is
  licensed the same way.

### Before you send it: what review keeps finding

The same handful of things come up in most pull requests. A minute on each saves a round of
fixes after the merge (the full list, with the version each one bit in, is in
[docs/MERGING.md](docs/MERGING.md)):

- **Items through `ns.api`**: `ns.api.Count(id)`, `ns.api.ItemInfo(id)`, never the bare
  `GetItemCount` / `GetItemInfo` (gone or moved on Forever). Match an item by ID **or** name.
- **Nothing asked about distance in a fight** except through `ns.rotation.Near`: the game
  forbids `CheckInteractDistance` in combat on anything but an enemy, and the player gets a
  "blocked action" popup.
- **Nothing heavy on a tick**: code that runs 10 times a second, or on every refresh of an open
  window, mustn't read all your buffs, bags or the whole plan each time. Once a second, out of
  a fight, or kept until its inputs change. `/flow perf` shows what it costs.
- **One character's choice is saved per character**: `ns:PerCharacter("section.field")`.
- **A new option joins the group it belongs to** and looks like its neighbours: a tick among
  ticks, in the settings group where a player would look for it while doing that thing
  (`S:AddCheck{ group = "route", ... }`, see `Modules/Settings.lua`).
- **Tests don't depend on you**: not on being out of a fight, alive, on an English client, or
  on your own route ticks. Pass values in, and put back everything the test changes, including
  anything a module remembers between calls.
- **Anything clickable has a click test**, colours come from `ns.theme`, and a new view is
  named "Flow <Name>".
- **Skill numbers and item facts are checked**, not remembered: wrong data sends the route to
  the wrong place.

## Reporting a bug

Open an issue with what you did, what you expected, what happened, and the output of
`tools\read-diag.ps1` after a `/reload` (it has the error log and test results).

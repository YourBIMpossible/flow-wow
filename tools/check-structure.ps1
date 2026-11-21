<#
.SYNOPSIS
  Static checks of how the add-on is put together, without the game:
    1. Every file Flow.toc lists exists (WoW skips a missing file without a word).
    2. Every .lua file anywhere in the add-on tree is listed in Flow.toc (a file
       that isn't listed is never loaded). Not part of the add-on, so not checked:
       the folders tools\, .github\, .claude\, .git\, dist\ and reports\.
    3. No registration key is used twice for the same kind. ns:Register (Core.lua)
       raises "Flow: <kind> '<key>' registered twice" on a duplicate, and the rest
       of that file stops loading, so a duplicate is always a bug: there is no
       override. Only literal keys can be checked (a key built at run time is
       counted as "dynamic"); registrations inside comments are examples, not code,
       and are listed for information only.

.USAGE
  powershell -ExecutionPolicy Bypass -File tools\check-structure.ps1 [-Root path]
  pwsh -File tools/check-structure.ps1            # the CI job, on Linux

  -Root: the add-on checkout to check (default: the one this script is in), so
  one copy of the checker can check another worktree.

  Exit code 0 = clean, 1 = a problem above, 2 = no Flow.toc under -Root. Runs on Windows PowerShell 5.1 and
  PowerShell 7 (Windows and Linux).
#>
param([string]$Root)
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Join-Path $PSScriptRoot '..' }
if (-not (Test-Path -LiteralPath (Join-Path $Root 'Flow.toc'))) { "check-structure: no Flow.toc under '$Root'"; exit 2 }
$root = (Resolve-Path -LiteralPath $Root).Path
"check-structure: $root"
$fail = 0

# Files Flow.toc may list that aren't in the repo: generated on the player's PC.
# (Learned\ClaudeInbox.lua is written by tools\claude-bridge.ps1 and gitignored.)
$mayBeMissing = @('Learned/ClaudeInbox.lua')

function Get-Rel([string]$full) { $full.Substring($root.Length + 1).Replace('\', '/') }

# --- 1. Flow.toc lists only files that exist -----------------------------------
$tocPath = Join-Path $root 'Flow.toc'
$toc = @()
$n = 0
foreach ($line in [IO.File]::ReadAllLines($tocPath)) {
    $n++
    $t = $line.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    $rel = $t.Replace('\', '/')
    $toc += $rel
    $full = Join-Path $root $rel
    if (-not (Test-Path -LiteralPath $full)) {
        if ($mayBeMissing -contains $rel) { "info: Flow.toc:${n}: $t is generated on the player's PC (allowed to be missing)" }
        else { "Flow.toc:${n}: $t is listed but the file doesn't exist"; $fail = 1 }
        continue
    }
    # Exact case: Windows doesn't care, but a case slip hides a rename.
    $dir = Split-Path $full -Parent
    $leaf = Split-Path $rel -Leaf
    $actual = (Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Name -ieq $leaf } | Select-Object -First 1).Name
    if ($actual -cne $leaf) { "Flow.toc:${n}: $t differs in case from the file on disk ($actual)"; $fail = 1 }
}
$tocCount = $toc.Count
if ($fail -eq 0) { "Flow.toc: $tocCount files listed, all present" }

# --- 2. Every add-on .lua file is listed ----------------------------------------
# Top-level folders that aren't the add-on (developer tools, CI, worktrees, build output).
$notAddOn = @('tools', '.github', '.claude', '.git', 'dist', 'reports')
"not checked for toc listing (not the add-on): $($notAddOn -join ', ')"
$luaFiles = @(Get-ChildItem -LiteralPath $root -File -Filter *.lua) +
    @(Get-ChildItem -LiteralPath $root -Directory -Force | Where-Object { $notAddOn -notcontains $_.Name } |
        ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Filter *.lua })
$orphans = 0
foreach ($f in $luaFiles) {
    $rel = Get-Rel $f.FullName
    if (-not ($toc | Where-Object { $_ -ieq $rel })) { "${rel}: not listed in Flow.toc, so WoW never loads it"; $orphans++ }
}
if ($orphans -gt 0) { $fail = 1 } else { "every add-on .lua file is listed in Flow.toc ($($luaFiles.Count) files)" }

# --- 3. No duplicate registration keys ------------------------------------------
# ns:Register("kind", "key" ...) or ns:Register("kind", 1234 ...), one line.
$reg = [regex]'ns:Register\(\s*"([^"]+)"\s*,\s*(?:"((?:[^"\\]|\\.)*)"|''((?:[^''\\]|\\.)*)''|(-?\d+)\b|([^,\)]+))'
$seen = @{}       # "kind`tkey" -> "file:line"
$kinds = @{}      # kind -> count of literal registrations
$dynamic = 0
$examples = @()
$dupes = 0
# In Flow.toc order, so "already registered at" names the one the game loads first.
$order = @{}
for ($k = 0; $k -lt $toc.Count; $k++) { $order[$toc[$k].ToLowerInvariant()] = $k }
$allLua = @(@($luaFiles) |
    Sort-Object { $r = (Get-Rel $_.FullName).ToLowerInvariant(); if ($order.ContainsKey($r)) { $order[$r] } else { [int]::MaxValue } })
foreach ($f in $allLua) {
    $rel = Get-Rel $f.FullName
    $i = 0
    foreach ($line in [IO.File]::ReadAllLines($f.FullName)) {
        $i++
        foreach ($m in $reg.Matches($line)) {
            $before = $line.Substring(0, $m.Index)
            $kind = $m.Groups[1].Value
            $key = $null
            foreach ($g in 2, 3, 4) { if ($m.Groups[$g].Success) { $key = $m.Groups[$g].Value; break } }
            if ($before -match '--') { $examples += "${rel}:${i}: $kind '$key' (in a comment)"; continue }
            if ($null -eq $key) { $dynamic++; continue }
            $kinds[$kind] = 1 + [int]$kinds[$kind]
            $id = "$kind`t$key"
            if ($seen.ContainsKey($id)) {
                "${rel}:${i}: $kind '$key' is already registered at $($seen[$id]); ns:Register errors on the second one"
                $dupes++
            } else { $seen[$id] = "${rel}:${i}" }
        }
    }
}
# A comment example that names a key really registered elsewhere looks like a
# duplicate to a plain grep (advisor 'trainer', mountRule 'default',
# talentBuild 'DRUID' on main); it isn't one. Listed so nobody chases it.
foreach ($e in $examples) {
    if ($e -match ': (\S+) ''(.*)'' \(in a comment\)$' -and $seen.ContainsKey("$($Matches[1])`t$($Matches[2])")) {
        "info: $e names a real key (registered at $($seen["$($Matches[1])`t$($Matches[2])"])): an example, not a duplicate"
    }
}
$total = ($kinds.Values | Measure-Object -Sum).Sum
"registrations: $total literal keys in $($kinds.Count) kinds ($([int]$kinds['test']) tests), $dynamic with a run-time key (not checked), $($examples.Count) in comments"
if ($dupes -gt 0) { $fail = 1 } else { "no registration key used twice" }

if ($fail -ne 0) { "STRUCTURE CHECK FAILED: fix the lines above."; exit 1 }
"structure OK"

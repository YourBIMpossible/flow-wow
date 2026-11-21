<#
.SYNOPSIS
  A second opinion on Flow's route. Reads Flow's export (your quests, skills
  and the route Flow suggests, written into the diagnostics at every /reload:
  Modules\Export.lua), plans a route of its own over the same steps, and
  says where the two differ and what looks missing.

.USAGE
  powershell -ExecutionPolicy Bypass -File tools\route-check.ps1 [-Stops 30] [-Dump]
    -Stops N   how many of Flow's steps to compare (default 30: what Flow plans ahead)
    -Dump      also print the export lines themselves

  /reload in game first (twice for a change made since the last reload): the
  saved file holds the session before the reload.

.WHAT IT DOES
  Its own plan is the shortest walk through the same steps from where you
  stand, keeping what must come first (a turn-in after its objectives:
  "deps"), found by nearest-first and then improved by moving steps and
  reversing runs (or-opt, 2-opt) until nothing shortens it. Distances are
  straight lines in yards on one continent, the same for both routes, so the
  comparison is fair even though neither knows the terrain. One use of the
  hearthstone is tried too, when it's ready and Flow knows where it's set.
  It doesn't weigh XP: with Flow on "Shortest path" the two should agree, and
  where Flow is longer, the rule that made it so is named when it can be told
  (a class quest first, your zone first, quests picked up before leaving).
#>
param(
    [int]$Stops = 30,
    [switch]$Dump,
    [string]$From      # a text file of export lines, in place of the saved diagnostics (for trying the script out)
)
$ErrorActionPreference = 'Stop'
if ($From) { $diag = Get-Content $From }
else { $diag = & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'read-diag.ps1') 2>&1 | ForEach-Object { "$_" } }
$lines = @($diag | Where-Object { $_ -like 'E^*' })
if ($lines.Count -eq 0) {
    Write-Output "NO-EXPORT: the saved diagnostics have no export yet. It needs Flow 0.35.196 or later and a /reload (two, right after an update)."
    exit 1
}
if ($Dump) { $lines | ForEach-Object { Write-Output $_ } }

# --- read the records -------------------------------------------------------
function Parse-Line([string]$line) {
    $parts = $line.Substring(2).Split('^')
    $r = @{}
    for ($i = 1; $i -lt $parts.Count; $i++) {
        $eq = $parts[$i].IndexOf('=')
        if ($eq -gt 0) {
            $name = $parts[$i].Substring(0, $eq)
            # (An early export called a stop's own kind "kind", the same word as the record's: read it as "stop".)
            if ($name -eq 'kind') { $name = 'stop' }
            $r[$name] = $parts[$i].Substring($eq + 1)
        }
    }
    $r['kind'] = $parts[0]
    return $r
}
function Num($v) {
    if ($null -eq $v -or $v -eq '') { return $null }
    return [double]::Parse($v, [Globalization.CultureInfo]::InvariantCulture)
}
$rec = @($lines | ForEach-Object { Parse-Line $_ })
$head = $rec | Where-Object { $_.kind -eq 'export' } | Select-Object -First 1
$you = $rec | Where-Object { $_.kind -eq 'you' } | Select-Object -First 1
$opt = $rec | Where-Object { $_.kind -eq 'opt' } | Select-Object -First 1
$goals = @{}
foreach ($g in ($rec | Where-Object { $_.kind -eq 'goal' })) { $goals[$g.key] = $g }
$plan = @($rec | Where-Object { $_.kind -eq 'plan' } | Sort-Object { [int]$_.i })
$quests = @($rec | Where-Object { $_.kind -eq 'quest' })
$objs = @($rec | Where-Object { $_.kind -eq 'obj' })
$fms = @($rec | Where-Object { $_.kind -eq 'fm' })
$improve = @($rec | Where-Object { $_.kind -eq 'improve' })

Write-Output ("=== Route check (export v{0}, Flow {1}) ===" -f $head.v, $head.flow)
Write-Output ("{0}, level {1} {2}, {3}: at {4:N1}, {5:N1} on map {6}; order: {7}; {8}" -f `
    $you.name, $you.level, $you.class, $you.zone, (Num $you.x), (Num $you.y), $you.map, $opt.order, $opt.note)
Write-Output ("quests in your log: {0}; steps Flow knows: {1} ({2} on the route); hearthstone: {3}{4}" -f `
    $quests.Count, $goals.Count, $plan.Count, $you.hearth, $(if ((Num $you.hearthleft) -eq 0) { ' (ready)' } elseif ($null -ne (Num $you.hearthleft)) { " (ready in $([int]((Num $you.hearthleft) / 60)) min)" } else { '' }))

if ($plan.Count -eq 0) { Write-Output "Flow has no route right now: nothing to compare."; exit 0 }

# --- the steps to compare: Flow's first N, with a place on your continent -----
$cont = $you.cont
$nodes = New-Object System.Collections.ArrayList
foreach ($s in ($plan | Select-Object -First $Stops)) {
    if ($s.cont -ne $cont -or $null -eq (Num $s.wx)) { continue }
    $g = $goals[$s.key]
    [void]$nodes.Add([pscustomobject]@{
        key = $s.key; x = (Num $s.wx); y = (Num $s.wy); i = [int]$s.i
        text = $(if ($g) { $g.text } else { $s.key }); level = $(if ($g) { $g.level } else { '' })
        deps = @($(if ($g -and $g.deps) { $g.deps.Split(',') } else { @() }))
        milestone = ($g -and $g.milestone -eq '1'); kind = $(if ($g) { $g.stop } else { '' })
    })
}
$n = $nodes.Count
$start = [pscustomobject]@{ x = (Num $you.wx); y = (Num $you.wy) }
function Dist($a, $b) { return [Math]::Sqrt(($a.x - $b.x) * ($a.x - $b.x) + ($a.y - $b.y) * ($a.y - $b.y)) }
function Length($order) {
    $at = $start; $sum = 0.0
    foreach ($i in $order) { $sum += (Dist $at $nodes[$i]); $at = $nodes[$i] }
    return $sum
}
# deps: a step may not come before a step it waits for (when that one is among these).
$index = @{}
for ($i = 0; $i -lt $n; $i++) { $index[$nodes[$i].key] = $i }
function Valid($order) {
    $pos = @{}
    for ($k = 0; $k -lt $order.Count; $k++) { $pos[$order[$k]] = $k }
    foreach ($i in $order) {
        foreach ($d in $nodes[$i].deps) {
            if ($index.ContainsKey($d) -and $pos[$index[$d]] -gt $pos[$i]) { return $false }
        }
    }
    return $true
}

$flow = @(0..($n - 1))
$flowLen = Length $flow

# --- my own plan: nearest first (deps kept), then or-opt and 2-opt ------------
$left = New-Object System.Collections.Generic.List[int]
0..($n - 1) | ForEach-Object { $left.Add($_) }
$mine = New-Object System.Collections.Generic.List[int]
$at = $start
while ($left.Count -gt 0) {
    $best = -1; $bestD = [double]::MaxValue
    foreach ($i in $left) {
        $ready = $true
        foreach ($d in $nodes[$i].deps) { if ($index.ContainsKey($d) -and $left.Contains($index[$d])) { $ready = $false } }
        if ($ready) { $d2 = Dist $at $nodes[$i]; if ($d2 -lt $bestD) { $best = $i; $bestD = $d2 } }
    }
    if ($best -lt 0) { $best = $left[0] }   # (deps that can't be met: take what's there)
    $mine.Add($best); [void]$left.Remove($best); $at = $nodes[$best]
}
$order = @($mine)
$len = Length $order
$improved = $true; $rounds = 0
while ($improved -and $rounds -lt 60) {
    $improved = $false; $rounds++
    # or-opt: move one step somewhere else
    for ($a = 0; $a -lt $n; $a++) {
        for ($b = 0; $b -lt $n; $b++) {
            if ($a -eq $b) { continue }
            $try = New-Object System.Collections.Generic.List[int]
            $try.AddRange([int[]]$order)
            $v = $try[$a]; $try.RemoveAt($a); $try.Insert($b, $v)
            $t = @($try)
            $l = Length $t
            if ($l -lt $len - 0.5 -and (Valid $t)) { $order = $t; $len = $l; $improved = $true }
        }
    }
    # 2-opt: reverse a run
    for ($a = 0; $a -lt $n - 1; $a++) {
        for ($b = $a + 1; $b -lt $n; $b++) {
            $t = @($order[0..($a - 1)] | Where-Object { $a -gt 0 }) + @($order[$b..$a]) + @($order[($b + 1)..($n - 1)] | Where-Object { $b -lt $n - 1 })
            if ($t.Count -ne $n) { continue }
            $l = Length $t
            if ($l -lt $len - 0.5 -and (Valid $t)) { $order = $t; $len = $l; $improved = $true }
        }
    }
}

Write-Output ""
Write-Output ("--- The same {0} steps, two ways (straight-line yards from where you stand) ---" -f $n)
Write-Output ("Flow's order:   {0,7:N0} yd" -f $flowLen)
Write-Output ("shortest found: {0,7:N0} yd  ({1:N0} yd, {2:P0} shorter)" -f $len, ($flowLen - $len), $(if ($flowLen -gt 0) { ($flowLen - $len) / $flowLen } else { 0 }))
$firstDiff = -1
for ($k = 0; $k -lt $n; $k++) { if ($order[$k] -ne $flow[$k]) { $firstDiff = $k; break } }
if ($firstDiff -lt 0) {
    Write-Output "The two orders are the same."
} else {
    Write-Output ("They part at step {0}: Flow goes to ""{1}"", the shortest walk to ""{2}""." -f ($firstDiff + 1), $nodes[$flow[$firstDiff]].text, $nodes[$order[$firstDiff]].text)
    # why Flow may differ, where it can be told
    $f = $nodes[$flow[$firstDiff]]
    if ($f.milestone) { Write-Output ("  (Flow's choice is a milestone: a class quest or training isn't put off for being far.)") }
    elseif ($f.kind -eq 'accept' -or $f.key -like 'pickup:*') { Write-Output "  (Flow's choice is a quest to pick up: it gathers the quests of a hub before leaving it.)" }
    if ($opt.note) { Write-Output ("  (Flow's own note: {0}.)" -f $opt.note) }
}
Write-Output ""
Write-Output "  #  Flow's order                                              |  shortest found"
for ($k = 0; $k -lt [Math]::Min($n, 16); $k++) {
    $a = $nodes[$flow[$k]]; $b = $nodes[$order[$k]]
    $mark = $(if ($flow[$k] -ne $order[$k]) { '*' } else { ' ' })
    $ta = $a.text; if ($ta.Length -gt 52) { $ta = $ta.Substring(0, 52) }
    $tb = $b.text; if ($tb.Length -gt 52) { $tb = $tb.Substring(0, 52) }
    Write-Output ("{0}{1,2}  {2,-56} |  {3}" -f $mark, ($k + 1), $ta, $tb)
}

# --- one use of the hearthstone ------------------------------------------------
$hx = Num $you.hwx; $hy = Num $you.hwy
if ($null -ne $hx -and $you.hcont -eq $cont -and (Num $you.hearthleft) -eq 0) {
    $bind = [pscustomobject]@{ x = $hx; y = $hy }
    $bestSave = 0.0; $bestAt = -1
    $at = $start
    for ($k = 0; $k -lt $n; $k++) {
        $to = $nodes[$flow[$k]]
        $walk = Dist $at $to
        $viaHome = 150 + (Dist $bind $to)      # (the cast and the loading screen, as running yards)
        if ($walk - $viaHome -gt $bestSave) { $bestSave = $walk - $viaHome; $bestAt = $k }
        $at = $to
    }
    Write-Output ""
    if ($bestAt -ge 0 -and $bestSave -gt 300) {
        Write-Output ("--- Hearthstone ({0}, ready) ---" -f $you.hearth)
        Write-Output ("Using it before step {0} (""{1}"") saves about {2:N0} yd of walking on Flow's route." -f ($bestAt + 1), $nodes[$flow[$bestAt]].text, $bestSave)
        Write-Output "Flow's planner doesn't count the hearthstone as a way to travel (it only gives an estimate on the arrow's panel)."
    } else {
        Write-Output ("--- Hearthstone ({0}, ready): no leg of Flow's route is clearly shorter by it. ---" -f $you.hearth)
    }
}

# --- what looks missing --------------------------------------------------------
Write-Output ""
Write-Output "--- What isn't on the route ---"
$missing = 0
foreach ($q in $quests) {
    $onRoute = @($plan | Where-Object { $_.key -like ($q.id + ':*') }).Count
    if ($onRoute -eq 0) {
        $why = @($rec | Where-Object { $_.kind -eq 'goal' -and $_.key -like ($q.id + ':*') -and $_.blocked }) | Select-Object -First 1
        $todo = @($objs | Where-Object { $_.quest -eq $q.id -and $_.done -ne '1' } | ForEach-Object { $_.text }) -join '; '
        Write-Output ("quest in your log with no step: {0} [{1}]{2}{3}" -f $q.title, $q.id, $(if ($q.complete -eq '1') { ' (complete: hand it in)' } elseif ($todo) { " ($todo)" } else { '' }), $(if ($why) { " - Flow: $($why.blocked)" } else { ' - Flow has no step for it at all' }))
        $missing++
    }
}
$locked = @($rec | Where-Object { $_.kind -eq 'goal' -and $_.state -eq 'locked' -and $_.key -notmatch '^\d+:' })
foreach ($g in $locked) { Write-Output ("held back: {0} - {1}" -f $g.text, $g.blocked); $missing++ }
# Every step Flow lists but can't put on the route, by the kind of reason, so
# each check shows which ones are Flow's to fix ("fix all of these no known
# spot issues ... add these into it so they're folded in as we go", 0.35.205).
$unplaced = @($rec | Where-Object { $_.kind -eq 'goal' -and $_.state -eq 'locked' })
if ($unplaced.Count -gt 0) {
    Write-Output ""
    Write-Output ("--- Steps Flow can't place ({0}) ---" -f $unplaced.Count)
    foreach ($g in $unplaced) {
        $b = [string]$g.blocked
        $class = if ($b -match '^Inside |^Handed in inside ') { 'dungeon (expected: the dungeon run handles it)' }
            elseif ($b -match 'battleground') { 'battleground (expected)' }
            elseif ($b -match 'you hid that st[eo]p') { 'waits for a step the player hid (expected)' }
            elseif ($b -match 'not on this continent|^first: .* That''s in ') { 'on another continent, or waits for a step there (expected)' }
            elseif ($b -match "doesn't know where it's handed in") { 'TO FIX: turn-in with no place (learned when handed in once)' }
            elseif ($b -match "has no spot for|a kind Flow can't place") { 'TO FIX: objective with no place in the quest data (learned when done once)' }
            elseif ($b -match "doesn't know where .* comes from|doesn't know who sells") { 'TO FIX: no source known for the item' }
            elseif ($b -match ' first$|^needs |^buy |^learn |^use ') { 'waits for another step (expected)' }
            elseif ($b -match '^first: ') { 'waits for a step that is off the route (expected)' }
            else { 'CHECK: other reason' }
        Write-Output ("{0}: {1} [{2}] - {3}" -f $class, $g.text, $g.key, $b)
    }
}
# flight masters you pass without knowing their flight path
$routePts = @($nodes | ForEach-Object { $_ })
foreach ($f in $fms) {
    if ($f.known -eq '1' -or $f.cont -ne $cont) { continue }
    $fp = [pscustomobject]@{ x = (Num $f.wx); y = (Num $f.wy) }
    $near = $null; $nearD = [double]::MaxValue
    foreach ($p in $routePts) { $d = Dist $fp $p; if ($d -lt $nearD) { $nearD = $d; $near = $p } }
    if ($nearD -le 250) {
        Write-Output ("flight path not learned, {0:N0} yd from a step on your route (""{1}""): {2}" -f $nearD, $near.text, $f.name)
        $missing++
    }
}
foreach ($it in $improve) {
    if (-not $it.goal) { continue }
    $on = @($plan | Where-Object { $_.key -eq $it.goal }).Count
    if ($on -eq 0) {
        $g = $goals[$it.goal]
        Write-Output ("improvement with no step on the route: {0}{1}" -f $it.text, $(if ($g -and $g.blocked) { " - held back: $($g.blocked)" } elseif ($g) { " - Flow knows the step ($($g.state))" } else { ' - Flow has no step for it' }))
        $missing++
    }
}
if ($missing -eq 0) { Write-Output "nothing: every quest in your log, every improvement with a place and every flight master on the way has a step." }

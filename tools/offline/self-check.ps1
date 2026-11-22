<#
.SYNOPSIS
  Tests the offline runner itself (run.lua, stubs.lua): that it fails when it
  should. tools/run-tests.ps1 runs it first, on every full run; a runner that
  can't tell a broken add-on from a good one makes every result after it
  worthless, so a failure here stops the run (exit 2).

  Each case is a tiny add-on in a temporary folder: this checkout's Core.lua
  and Modules/Tests.lua (the real registry and the real test harness), plus
  one made-up file, run through the real run.lua with --filter "selfcheck:".
  Nothing is written inside the checkout.

.USAGE
  powershell -ExecutionPolicy Bypass -File tools\offline\self-check.ps1 -Lua <lua5.1> [-Root <add-on>]
  Exit code 0 = every case behaved; 1 = one didn't (listed); 2 = couldn't run.
#>
param(
    [Parameter(Mandatory = $true)][string]$Lua,
    [string]$Root
)
$ErrorActionPreference = 'Stop'
$runner = $PSScriptRoot
if (-not $Root) { $Root = Join-Path $PSScriptRoot '../..' }
$root = (Resolve-Path -LiteralPath $Root).Path
$globals = Join-Path $root 'tools/offline/client-globals.txt'
if (-not (Test-Path -LiteralPath $globals)) { $globals = Join-Path $runner 'client-globals.txt' }
foreach ($need in (Join-Path $root 'Core.lua'), (Join-Path $root 'Modules/Tests.lua'), $globals) {
    if (-not (Test-Path -LiteralPath $need)) { "self-check: missing $need"; exit 2 }
}

# The made-up file's parts. "selfcheck: control" is in every case: it must
# PASS, which shows the case really ran (the tree loaded, the filter matched).
$control = @'
local _, ns = ...
ns:Register("test", "selfcheck: control", function(t) t:eq(1 + 1, 2, "adds") end)
'@

$cases = @(
    @{  name = 'a good add-on passes (the control)'
        lua = $control
        exit = 0
        want = @('offline tests: 1 run: 1 pass \(0 with no checks\), 0 fail, 0 error, 0 skip ', '^result: OK$')
        never = @() },
    @{  name = 'a file that errors while loading fails the run'
        lua = $control + "`nerror(`"selfcheck: this file breaks while loading`")`n"
        exit = 1
        want = @('did not load \(its tests never registered\): SelfCheck\.lua', '^result: FAILED: .*1 file\(s\) did not load')
        never = @('^result: OK$') },
    @{  name = 'a file with a syntax error fails the run'
        lua = $control + "`nlocal = = 1`n"
        exit = 1
        want = @('did not load \(its tests never registered\): SelfCheck\.lua \(syntax: ', '^result: FAILED: .*1 file\(s\) did not load')
        never = @('^result: OK$') },
    @{  name = 'a file Flow.toc lists that is not there fails the run'
        lua = $null
        exit = 1
        want = @('absent: SelfCheck\.lua', '^result: FAILED: .*1 file\(s\) in Flow\.toc absent')
        never = @('^result: OK$') },
    @{  name = 'a mistyped global in a test is an ERROR, not a SKIP'
        lua = $control + @'

ns:Register("test", "selfcheck: typo", function(t)
    t:eq(UnitLevle("player"), 60, "level")
end)
'@
        exit = 1
        want = @('^ERROR selfcheck: typo: unknown global: UnitLevle', 'offline tests: 2 run: 1 pass \(0 with no checks\), 0 fail, 1 error, 0 skip ', 'unknown globals read: 0 while loading, 1 test\(s\)')
        never = @('^result: OK$') },
    @{  name = 'a mistyped global caught by the test''s own pcall is still an ERROR'
        lua = $control + @'

ns:Register("test", "selfcheck: typo in a pcall", function(t)
    local ok = pcall(function() return UnitLevle("player") end)
    t:ok(not ok or true, "always holds")
end)
'@
        exit = 1
        want = @('^ERROR selfcheck: typo in a pcall: unknown global: UnitLevle', ', 1 error, 0 skip ')
        never = @('^result: OK$') },
    @{  name = 'a real game global in a test is a SKIP (the list is read)'
        lua = $control + @'

ns:Register("test", "selfcheck: needs the game", function(t)
    t:eq(UnitLevel("player"), 60, "level")
end)
'@
        exit = 0
        want = @('offline tests: 2 run: 1 pass \(0 with no checks\), 0 fail, 0 error, 1 skip ', '^result: OK$')
        never = @('^ERROR ') },
    @{  name = 'a mistyped global while a file loads fails the run'
        lua = $control + "`nlocal level = UnitLevle`n"
        exit = 1
        want = @('did not load \(its tests never registered\): SelfCheck\.lua \(unknown global: UnitLevle', 'unknown globals read: 1 while loading')
        never = @('^result: OK$') },
    @{  name = 'fewer registered tests than the floor fails the run'
        lua = $control
        args = @('--min-tests', '1000000')
        exit = 1
        want = @('registered tests: \d+ \(floor 1000000: --min-tests\)', '^result: FAILED: only \d+ test\(s\) registered, the floor is 1000000')
        never = @('^result: OK$') },
    @{  name = 'a floor that is met does not fail the run'
        lua = $control
        args = @('--min-tests', '1')
        exit = 0
        want = @('registered tests: \d+ \(floor 1: --min-tests\)', '^result: OK$')
        never = @() },
    @{  name = 'a test whose result is what the timer said is not a PASS'
        lua = $control + @'

local timer = debugprofilestop   -- (kept at load, as Flow's timed code keeps it)
ns:Register("test", "selfcheck: fast enough", function(t)
    local before = timer()
    local took = timer() - before
    t:ok(took < 100, "took " .. took .. " ms")
end)
ns:Register("test", "selfcheck: timed, result not from the timer", function(t)
    local before = timer()
    t:ok(timer() >= before, "the clock doesn't run backwards")
end)
'@
        exit = 0
        want = @('offline tests: 3 run: 2 pass \(0 with no checks\), 0 fail, 0 error, 1 skip ', 'timing fixture \(debugprofilestop\): 1 passing test\(s\) .* 1 depend on what it said \(SKIP\)')
        never = @('^ERROR ', '^FAIL ') },
    @{  name = 'reading the timer''s global in a test is a SKIP'
        lua = $control + @'

ns:Register("test", "selfcheck: reads the timer", function(t)
    t:ok(debugprofilestop() >= 0, "a time")
end)
'@
        exit = 0
        want = @('offline tests: 2 run: 1 pass \(0 with no checks\), 0 fail, 0 error, 1 skip ')
        never = @('^ERROR ', '^FAIL ') },
    @{  name = 'a check that fails is a FAIL and fails the run'
        lua = $control + @'

ns:Register("test", "selfcheck: wrong", function(t) t:eq(1 + 1, 3, "adds") end)
'@
        exit = 1
        want = @('^FAIL selfcheck: wrong', 'offline tests: 2 run: 1 pass \(0 with no checks\), 1 fail, 0 error, 0 skip ')
        never = @('^result: OK$') },
    @{  name = 'a known failure that now skips is not reported as fixed'
        lua = $control + @'

ns:Register("test", "selfcheck: needs the game", function(t)
    t:eq(UnitLevel("player"), 60, "level")
end)
'@
        known = "selfcheck: needs the game`n"
        exit = 0
        want = @('^known failure now skips \(needs the client\).*: selfcheck: needs the game$', '0 now passing, 1 now skipping')
        never = @('take it off the list') }
)

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('flow-selfcheck-' + [Guid]::NewGuid().ToString('N'))
$bad = 0
try {
    New-Item -ItemType Directory -Path (Join-Path $tmp 'Modules') | Out-Null
    Copy-Item -LiteralPath (Join-Path $root 'Core.lua') -Destination (Join-Path $tmp 'Core.lua')
    Copy-Item -LiteralPath (Join-Path $root 'Modules/Tests.lua') -Destination (Join-Path $tmp 'Modules/Tests.lua')
    [IO.File]::WriteAllText((Join-Path $tmp 'Flow.toc'), "## Interface: 0`n## Title: Flow (runner self-check)`nCore.lua`nModules/Tests.lua`nSelfCheck.lua`n")
    $made = Join-Path $tmp 'SelfCheck.lua'
    $knownFile = Join-Path $tmp 'known.txt'
    foreach ($c in $cases) {
        if (Test-Path -LiteralPath $made) { Remove-Item -LiteralPath $made }
        if ($null -ne $c.lua) { [IO.File]::WriteAllText($made, $c.lua) }
        $luaArgs = @((Join-Path $runner 'run.lua'), $tmp, '--filter', 'selfcheck:', '--client-globals', $globals)
        if ($c.args) { $luaArgs += $c.args }
        if ($c.known) { [IO.File]::WriteAllText($knownFile, $c.known); $luaArgs += @('--known', $knownFile) }
        $out = @(& $Lua @luaArgs 2>&1 | ForEach-Object { "$_" })
        $code = $LASTEXITCODE
        $why = @()
        if ($code -ne $c.exit) { $why += "exit $code, expected $($c.exit)" }
        if ($out.Count -eq 0 -or $out[-1] -ne "offline: done, exit $code") { $why += "the last line is not 'offline: done, exit $code'" }
        foreach ($w in $c.want) { if (-not ($out | Where-Object { $_ -cmatch $w })) { $why += "no line matches /$w/" } }
        foreach ($n in $c.never) { if ($out | Where-Object { $_ -cmatch $n }) { $why += "a line matches /$n/" } }
        if ($why.Count -gt 0) {
            $bad++
            "self-check FAILED: $($c.name): $($why -join '; ')"
            $out | ForEach-Object { "    | $_" }
        }
    }
} finally {
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
}
if ($bad -gt 0) { "runner self-check: $bad of $($cases.Count) case(s) FAILED: the runner can't be trusted until this is fixed"; exit 1 }
"runner self-check: $($cases.Count) of $($cases.Count) cases OK (load failure, absent file, mistyped global, test-count floor, timer, known list)"
exit 0

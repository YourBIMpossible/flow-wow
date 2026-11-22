<#
.SYNOPSIS
  Fixture check for tools/zflow-check-all.ps1 (F-E). Each case root holds
  stub tools (tools/<check>.ps1) that print one line and exit with a set
  code; the runner is run on them in Windows PowerShell.

  Cases:
    all-pass      every stub exits 0, Lua and luacheck "found" (-LuaPath /
                  -LuacheckPath point at fake-lua.txt): exit 0, nine PASS
                  lines, one log per check plus summary.txt in -LogDir
    one-fail      the zflow-text stub exits 1: exit 1, a FAIL line for it
    no-lua        -NoLua: the five Lua checks are NOT RUN (no Lua / no
                  luacheck), never PASS, and the run exits 2, not 0
    missing-tool  no tools/zflow-coverage.ps1: NOT RUN (missing), exit 2

.USAGE
  powershell -ExecutionPolicy Bypass -File tools\fixtures\zflow-check-all\run.ps1

  Exit code 0 = every case as expected, 1 = not so.
#>
$ErrorActionPreference = 'Stop'
$tool = Join-Path $PSScriptRoot '..\..\zflow-check-all.ps1'
$fake = Join-Path $PSScriptRoot 'fake-lua.txt'
$luaChecks = @('lint', 'run-tests', 'zflow-structure', 'zflow-toc', 'zflow-tests')
$bad = 0

function Invoke-Case([string]$root, [string[]]$extra) {
    $logs = Join-Path ([IO.Path]::GetTempPath()) ('zflow-check-all-fixture-' + [guid]::NewGuid().ToString('N'))
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $tool, '-Root', (Join-Path $PSScriptRoot $root), '-LogDir', $logs) + $extra
    $out = (& powershell.exe @a 2>&1 | Out-String)
    return [pscustomobject]@{ Out = $out; Code = $LASTEXITCODE; Logs = $logs }
}

function Report([string]$name, [bool]$ok, $r, [string]$why) {
    if ($ok) { Write-Output ("PASS {0} (exit {1})" -f $name, $r.Code); return 0 }
    Write-Output ("FAIL {0}: {1} (exit {2})" -f $name, $why, $r.Code)
    Write-Output ($r.Out.TrimEnd())
    return 1
}

if (-not (Test-Path -LiteralPath $tool)) {
    Write-Output "FAIL all cases: tools/zflow-check-all.ps1 does not exist"
    Write-Output "zflow-check-all fixtures: 4 case(s), 4 not as expected"
    exit 1
}

# all-pass
$r = Invoke-Case 'all-pass' @('-LuaPath', $fake, '-LuacheckPath', $fake)
$passLines = ([regex]::Matches($r.Out, '(?m)^PASS\s')).Count
$logCount = @(Get-ChildItem -LiteralPath $r.Logs -Filter *.log -ErrorAction SilentlyContinue).Count
$summary = Test-Path -LiteralPath (Join-Path $r.Logs 'summary.txt')
$bad += Report 'all-pass' (($r.Code -eq 0) -and $passLines -eq 9 -and $logCount -eq 9 -and $summary) $r ("wanted exit 0, 9 PASS, 9 logs and summary.txt; got {0} PASS, {1} logs, summary {2}" -f $passLines, $logCount, $summary)
Remove-Item -LiteralPath $r.Logs -Recurse -Force -ErrorAction SilentlyContinue

# one-fail
$r = Invoke-Case 'one-fail' @('-LuaPath', $fake, '-LuacheckPath', $fake)
$bad += Report 'one-fail' (($r.Code -eq 1) -and ($r.Out -match '(?m)^FAIL\s+zflow-text\b')) $r 'wanted exit 1 and a FAIL line for zflow-text'
Remove-Item -LiteralPath $r.Logs -Recurse -Force -ErrorAction SilentlyContinue

# no-lua
$r = Invoke-Case 'all-pass' @('-NoLua')
$ok = ($r.Code -eq 2)
foreach ($c in $luaChecks) {
    if ($r.Out -notmatch ('(?m)^NOT RUN\s+' + [regex]::Escape($c) + '\b')) { $ok = $false }
    if ($r.Out -match ('(?m)^PASS\s+' + [regex]::Escape($c) + '\b')) { $ok = $false }
}
if ($r.Out -notmatch 'not run \(no Lua\)') { $ok = $false }
$bad += Report 'no-lua' $ok $r 'wanted exit 2, the five Lua checks NOT RUN and none PASS'
Remove-Item -LiteralPath $r.Logs -Recurse -Force -ErrorAction SilentlyContinue

# missing-tool
$r = Invoke-Case 'missing-tool' @('-LuaPath', $fake, '-LuacheckPath', $fake)
$bad += Report 'missing-tool' (($r.Code -eq 2) -and ($r.Out -match '(?m)^NOT RUN\s+zflow-coverage\b.*missing')) $r 'wanted exit 2 and NOT RUN zflow-coverage (missing)'
Remove-Item -LiteralPath $r.Logs -Recurse -Force -ErrorAction SilentlyContinue

Write-Output ("zflow-check-all fixtures: 4 case(s), {0} not as expected" -f $bad)
if ($bad -gt 0) { exit 1 }
exit 0

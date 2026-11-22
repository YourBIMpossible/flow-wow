<#
.SYNOPSIS
  Fixture check for tools/zflow-saved-size.ps1 (F-I). Each case folder
  holds a hand-written ZFlow.lua.

  Cases:
    pass           20 snapshots, the names once: exit 0, 0 problems
    toobig         the pass file with -MaxBytes 100: exit 1, TOOBIG
    snaps-fail     21 snapshots kept: exit 1, DIAGSNAPS
    names-fail     a snapshot with its own names table: exit 1, SNAPNAMES
    longlist-fail  a module list of 201 entries: exit 1, LONGLIST with its
                   path, and no entry of the list printed
    no-file        a path with no file: exit 2

.USAGE
  powershell -ExecutionPolicy Bypass -File tools\fixtures\zflow-saved-size\run.ps1

  Exit code 0 = every case as expected, 1 = not so.
#>
$ErrorActionPreference = 'Stop'
$tool = Join-Path $PSScriptRoot '..\..\zflow-saved-size.ps1'
$shell = (Get-Process -Id $PID).Path
$bad = 0
$cases = 0

function Invoke-Case([string]$name, [string[]]$extra) {
    $file = Join-Path (Join-Path $PSScriptRoot $name) 'ZFlow.lua'
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $tool, '-File', $file) + $extra
    $out = (& $shell @a 2>&1 | Out-String)
    return [pscustomobject]@{ Out = $out; Code = $LASTEXITCODE }
}

function Report([string]$name, $r, [int]$code, [string[]]$wanted, [string[]]$unwanted) {
    $script:cases++
    $why = @()
    if ($r.Code -ne $code) { $why += ("wanted exit {0}" -f $code) }
    foreach ($w in $wanted) { if (-not $r.Out.Contains($w)) { $why += ("missing: {0}" -f $w) } }
    foreach ($u in $unwanted) { if ($r.Out.Contains($u)) { $why += ("must not print: {0}" -f $u) } }
    if ($why.Count -eq 0) { Write-Output ("PASS {0} (exit {1})" -f $name, $r.Code); return }
    Write-Output ("FAIL {0}: {1} (exit {2})" -f $name, ($why -join '; '), $r.Code)
    Write-Output ($r.Out.TrimEnd())
    $script:bad++
}

if (-not (Test-Path -LiteralPath $tool)) {
    Write-Output 'FAIL all cases: tools/zflow-saved-size.ps1 does not exist'
    exit 1
}

$flags = @('TOOBIG', 'LONGLIST', 'DIAGSNAPS', 'SNAPNAMES')

$r = Invoke-Case 'pass' @()
Report 'pass' $r 0 @('zflow-saved-size: 0 problem(s)', 'ZFlowDB.diag.snaps') $flags

$r = Invoke-Case 'pass' @('-MaxBytes', '100')
Report 'toobig' $r 1 @('TOOBIG', 'the limit is 100', 'zflow-saved-size: 1 problem(s)') @('LONGLIST', 'DIAGSNAPS', 'SNAPNAMES')

$r = Invoke-Case 'snaps-fail' @()
Report 'snaps-fail' $r 1 @('ZFlowDB.diag.snaps: DIAGSNAPS: 21 snapshots kept, the limit is 20') @('TOOBIG', 'LONGLIST', 'SNAPNAMES')

$r = Invoke-Case 'names-fail' @()
Report 'names-fail' $r 1 @('ZFlowDB.diag.snaps[2]: SNAPNAMES') @('TOOBIG', 'LONGLIST', 'DIAGSNAPS', 'snaps[1]: SNAPNAMES')

$r = Invoke-Case 'longlist-fail' @()
Report 'longlist-fail' $r 1 @('ZFlowDB.learned.seen: LONGLIST: 201 entries, the limit is 200') @('TOOBIG', 'DIAGSNAPS', 'SNAPNAMES', '1001', '1201')

$r = Invoke-Case 'no-such-case' @()
Report 'no-file' $r 2 @('no file at') $flags

Write-Output ("zflow-saved-size fixtures: {0} case(s), {1} not as expected" -f $cases, $bad)
if ($bad -gt 0) { exit 1 }
exit 0

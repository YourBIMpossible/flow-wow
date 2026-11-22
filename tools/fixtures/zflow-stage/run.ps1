<#
.SYNOPSIS
  Fixture check for tools/zflow-stage.ps1 (F-F). Stages fixtures/zflow-stage/tree
  into fresh folders under %TEMP% (removed afterwards) in Windows PowerShell.

  Cases:
    refuse-game      -Out under "...\World of Warcraft\..." (any letter case):
                     exit 2, says it refuses, and creates nothing there
    excludes-tests   exit 0; ZFlow/Core/A.lua, UI/B.lua, manifest.lua,
                     ZFlow.toc and Art/icon.tga staged; no ZFlow/Tests
    build-lines      BUILD.txt beside ZFlow/ has commit:, dirty:, time: (UTC,
                     ISO 8601) and files: <n> lines, n = the staged file count,
                     and the run prints that count
    refuse-nonempty  -Out holds a file but no BUILD.txt (not a stage folder):
                     exit 2 and the file is untouched
    restage          a second run over a stage folder replaces it: exit 0

.USAGE
  powershell -ExecutionPolicy Bypass -File tools\fixtures\zflow-stage\run.ps1

  Exit code 0 = every case as expected, 1 = not so.
#>
$ErrorActionPreference = 'Stop'
$tool = Join-Path $PSScriptRoot '..\..\zflow-stage.ps1'
$tree = Join-Path $PSScriptRoot 'tree'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('zflow-stage-fixture-' + [guid]::NewGuid().ToString('N'))
$bad = 0

function Stage([string]$out) {
    $o = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tool -Root $tree -Out $out 2>&1 | Out-String)
    return [pscustomobject]@{ Out = $o; Code = $LASTEXITCODE }
}
function Report([string]$name, [bool]$ok, $r, [string]$why) {
    if ($ok) { Write-Output ("PASS {0} (exit {1})" -f $name, $r.Code); return }
    Write-Output ("FAIL {0}: {1} (exit {2})" -f $name, $why, $r.Code)
    Write-Output ($r.Out.TrimEnd())
    $script:bad++
}

if (-not (Test-Path -LiteralPath $tool)) {
    Write-Output "FAIL all cases: tools/zflow-stage.ps1 does not exist"
    Write-Output "zflow-stage fixtures: 5 case(s), 5 not as expected"
    exit 1
}

New-Item -ItemType Directory -Force -Path $scratch | Out-Null
try {
    # refuse-game (both letter cases); the folder must not be created
    $ok = $true
    foreach ($game in @((Join-Path $scratch 'World of Warcraft\_classic_\Interface\AddOns'), (Join-Path $scratch 'world of warcraft\Interface\AddOns'))) {
        $r = Stage $game
        if ($r.Code -ne 2 -or $r.Out -notmatch '(?i)refus' -or (Test-Path -LiteralPath $game)) { $ok = $false; $last = $r }
        else { $last = $r }
    }
    Report 'refuse-game' $ok $last 'wanted exit 2, a refusal, and no folder created'

    # excludes-tests
    $out = Join-Path $scratch 'stage'
    $r = Stage $out
    $z = Join-Path $out 'ZFlow'
    $want = @('Core\A.lua', 'UI\B.lua', 'manifest.lua', 'ZFlow.toc', 'Art\icon.tga')
    $ok = ($r.Code -eq 0) -and -not (Test-Path -LiteralPath (Join-Path $z 'Tests'))
    foreach ($w in $want) { if (-not (Test-Path -LiteralPath (Join-Path $z $w))) { $ok = $false } }
    Report 'excludes-tests' $ok $r 'wanted exit 0, the five add-on files staged and no ZFlow/Tests'

    # build-lines
    $build = Join-Path $out 'BUILD.txt'
    $ok = Test-Path -LiteralPath $build
    if ($ok) {
        $text = [IO.File]::ReadAllText($build)
        $ok = ($text -match '(?m)^commit: ([0-9a-f]{40}|not known)\s*$') -and
              ($text -match '(?m)^dirty: (yes|no|not known)\s*$') -and
              ($text -match '(?m)^time: \d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\s*$') -and
              ($text -match '(?m)^files: 5\s*$') -and
              ($r.Out -match '\b5 file\(s\)')
    }
    Report 'build-lines' $ok $r 'wanted commit:, dirty:, time: (UTC) and files: 5 in BUILD.txt, and "5 file(s)" printed'

    # refuse-nonempty
    $other = Join-Path $scratch 'someone-elses'
    New-Item -ItemType Directory -Force -Path $other | Out-Null
    $keep = Join-Path $other 'keep.txt'
    [IO.File]::WriteAllText($keep, 'not a stage folder')
    $r = Stage $other
    $ok = ($r.Code -eq 2) -and (Test-Path -LiteralPath $keep) -and -not (Test-Path -LiteralPath (Join-Path $other 'ZFlow'))
    Report 'refuse-nonempty' $ok $r 'wanted exit 2 and the folder untouched'

    # restage over the earlier stage folder
    [IO.File]::WriteAllText((Join-Path $z 'Core\Stale.lua'), 'left from an older stage')
    $r = Stage $out
    $ok = ($r.Code -eq 0) -and -not (Test-Path -LiteralPath (Join-Path $z 'Core\Stale.lua'))
    Report 'restage' $ok $r 'wanted exit 0 and the older stage replaced'
} finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output ("zflow-stage fixtures: 5 case(s), {0} not as expected" -f $bad)
if ($bad -gt 0) { exit 1 }
exit 0

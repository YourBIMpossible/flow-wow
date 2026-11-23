<#
.SYNOPSIS
  Fixture check for tools/zflow-read-diag.ps1 (F-H). Each case folder holds
  a hand-written ZFlow.lua (a ZFlowDB as the game would save it).

  Cases:
    two-characters  two characters over two starts: exit 0; each character
                    with its starts, reasons, errors, kernel phase and
                    failed probes; the layout; the write time; and no
                    money, bag or position value anywhere in the output.
                    The file is the same bytes after the run.
    old-names       a snapshot from before the cap, with its own names
                    table and no character: exit 0, the !! line, "unknown
                    character", "Names table: not saved"
    no-diag         a ZFlowDB with no diag: exit 1
    broken          a file cut off part way: exit 2
    no-file         a path with no file: exit 1

.USAGE
  powershell -ExecutionPolicy Bypass -File tools\fixtures\zflow-read-diag\run.ps1

  Exit code 0 = every case as expected, 1 = not so.
#>
$ErrorActionPreference = 'Stop'
$tool = Join-Path $PSScriptRoot '..\..\zflow-read-diag.ps1'
$shell = (Get-Process -Id $PID).Path
$bad = 0
$cases = 0

function Invoke-Case([string]$name) {
    $file = Join-Path (Join-Path $PSScriptRoot $name) 'ZFlow.lua'
    $out = (& $shell -NoProfile -ExecutionPolicy Bypass -File $tool -File $file 2>&1 | Out-String)
    return [pscustomobject]@{ Out = $out; Code = $LASTEXITCODE; File = $file }
}

# $wanted: texts the output must hold. $unwanted: texts it must not.
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
    Write-Output 'FAIL all cases: tools/zflow-read-diag.ps1 does not exist'
    exit 1
}

# two-characters
$path = Join-Path $PSScriptRoot 'two-characters\ZFlow.lua'
$before = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
$stamp = (Get-Item -LiteralPath $path).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
$r = Invoke-Case 'two-characters'
Report 'two-characters' $r 0 @(
    ("Written: {0}" -f $stamp),
    'Starts: 7',
    'Snapshots: 31 taken, 3 kept',
    'Names table: build 1.16.1 (7777)',
    '=== Aldric - Testrealm ===',
    'Starts seen in the kept snapshots: 1 (6)',
    'Snapshot reasons (2): login, vendor',
    'Recorded errors: 2',
    '!! start 6, phase started, x4: Interface/AddOns/ZFlow/Core/Diag.lua:333: attempt to compare a secret number value',
    '   start 6, phase started, x1: Interface/AddOns/OtherAddon/Main.lua:10: nil value',
    'Kernel phase: started (paused: Saved data is from a newer build.) [newest snapshot: vendor]',
    'Kernel problems: 1',
    'diag / collect, x2: boom at line 5',
    'Failed shape probes: 2',
    'health: not a function',
    'spellTabs: bad argument #1 to "GetNumSpellTabs"',
    '=== Brenna - Testrealm ===',
    'Starts seen in the kept snapshots: 1 (7)',
    'Kernel phase: booted [newest snapshot: login]',
    'Failed shape probes: 0',
    '=== Kit probe ===',
    'T2  template  ButtonFrameTemplate: works',
    "T5  template  SearchBoxTemplate: Couldn't find inherited node: SearchBoxTemplate",
    'G2  global  C_Texture.GetAtlasInfo: nil',
    'G6  global  GameTooltip: works (table)',
    'T7  template  PanelTabButtonTemplate: not asked',
    'X9  ?  ?: made, not confirmed',
    'Encounter Journal add-on loaded: no',
    'works 2, missing 2, not confirmed 1, not asked 20',
    'arrows.mode = separate',
    'arrows.points.quest = CENTER, CENTER, 200, 100',
    '=== Sell list: first grey item ===',
    'Cracked Bone: not read (price not read yet)',
    'listing: to sell 0, kept 1, not sold 1, not read 0'
) @('987654', '987111', '555444', '0.4321', '0.8765', '1411', 'bagStacks', 'money', 'level:', 'x3:')
$cases++
$after = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
if ($after -eq $before) { Write-Output 'PASS two-characters: the file is unchanged' }
else { Write-Output 'FAIL two-characters: the file was changed by the run'; $bad++ }

# old-names
$r = Invoke-Case 'old-names'
Report 'old-names' $r 0 @(
    'Names table: not saved',
    '!! 1 kept snapshot(s) still hold their own names table',
    '=== unknown character ===',
    'Snapshot reasons (1): settled',
    'none saved'
) @('GetMoney')

# no-diag
$r = Invoke-Case 'no-diag'
Report 'no-diag' $r 1 @('No diagnostics saved yet') @('===')

# broken
$r = Invoke-Case 'broken'
Report 'broken' $r 2 @('not readable as saved data') @('===')

# no-file
$r = Invoke-Case 'no-such-case'
Report 'no-file' $r 1 @('no saved data at') @('===')

Write-Output ("zflow-read-diag fixtures: {0} case(s), {1} not as expected" -f $cases, $bad)
if ($bad -gt 0) { exit 1 }
exit 0

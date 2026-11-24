<#
.SYNOPSIS
  Fixture check for tools/zflow-boss-loot.ps1 (lead DISPATCH 426). The case
  folders hold hand-written files in the form of an instance file; every
  number and word in them is made up.

  Cases:
    pass       two files: exit 0, the counts, and a written file that holds
               the bosses by encounter and by creature with their items in
               order, one boss with no items, the instance with no area id;
               that leaves out the quest and zone-drop items, the item its
               timeline removed, the item added in a later version and the
               creature with no items; that keeps the item whose timeline
               cannot be read; and that holds none of the prose of the file
    bad-file   a file that is not Lua: exit 1, the file named
    no-folder  a folder that is not there: exit 2
    no-commit  no commit given with -Files: exit 2

.USAGE
  powershell -ExecutionPolicy Bypass -File tools\fixtures\zflow-boss-loot\run.ps1

  Exit code 0 = every case as expected, 1 = not so.
#>
$ErrorActionPreference = 'Stop'
$tool = Join-Path $PSScriptRoot '..\..\zflow-boss-loot.ps1'
$shell = (Get-Process -Id $PID).Path
$bad = 0
$cases = 0
$commit = '0000000000000000000000000000000000000000'
$outFile = [System.IO.Path]::GetTempFileName()

function Invoke-Case([string]$name, [string[]]$extra) {
    $folder = Join-Path $PSScriptRoot $name
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $tool, '-Files', $folder, '-Out', $outFile) + $extra
    # What the tool writes to the error stream is part of what it says, not a stop.
    $ErrorActionPreference = 'Continue'
    $out = (& $shell @a 2>&1 | ForEach-Object { "$_" } | Out-String)
    return [pscustomobject]@{ Out = $out; Code = $LASTEXITCODE }
}

function Report([string]$name, $r, [int]$code, [string[]]$wanted, [string[]]$unwanted) {
    $script:cases++
    $why = @()
    if ($r.Code -ne $code) { $why += ("wanted exit {0}" -f $code) }
    foreach ($w in $wanted) { if (-not $r.Out.Contains($w)) { $why += ("missing: {0}" -f $w) } }
    foreach ($u in $unwanted) { if ($r.Out.Contains($u)) { $why += ("must not hold: {0}" -f $u) } }
    if ($why.Count -eq 0) { Write-Output ("PASS {0} (exit {1})" -f $name, $r.Code); return }
    Write-Output ("FAIL {0}: {1} (exit {2})" -f $name, ($why -join '; '), $r.Code)
    Write-Output ($r.Out.TrimEnd())
    $script:bad++
}

if (-not (Test-Path -LiteralPath $tool)) {
    Write-Output 'FAIL all cases: tools/zflow-boss-loot.ps1 does not exist'
    exit 1
}

try {
    $r = Invoke-Case 'pass' @('-Commit', $commit)
    Report 'pass: what the tool says' $r 0 @(
        '2 instances (1 without an area id)', '2 bosses with an encounter id', '2 by creature only',
        '1 with no items', '6 item entries', 'timeline: 1 kept, 2 left out, 1 kept unread',
        '1 creature groups without items left out', '0 files failed') @()

    # The written file, with its spaces taken out so the form of a line is not the test.
    $text = [System.IO.File]::ReadAllText($outFile)
    $data = $text.Substring($text.IndexOf('ns.BossLootData = {'))
    # Every number of the table, each between bars, so a left-out id is looked for whole.
    $numbers = '|' + ((([regex]::Matches($data, '\d+')) | ForEach-Object { $_.Value }) -join '|') + '|'
    $flat = [pscustomobject]@{ Out = (($data -replace '\s', '') + $numbers); Code = 0 }
    Report 'pass: the written file' $flat 0 @(
        ('commit="{0}"' -f $commit), 'build="1.60.1"',
        '{id=9000,bosses={{npcs={701},items={31}},}}',
        '{id=9001,area=7001,bosses={',
        '{e=501,npcs={601},items={11,12,15}}',
        '{npcs={602},items={21,22}}',
        '{e=502,npcs={604,605},items={}}') @(
        '|900|', '|901|', '|4001|', '|603|', '|13|', '|14|', 'MADE', 'PROSE', 'description')

    $r = Invoke-Case 'bad-file' @('-Commit', $commit)
    Report 'bad-file' $r 1 @('1 files failed', 'broken.lua') @()

    $r = Invoke-Case 'no-such-folder' @('-Commit', $commit)
    Report 'no-folder' $r 2 @('no folder') @()

    $r = Invoke-Case 'pass' @()
    Report 'no-commit' $r 2 @('commit is not known') @()
} finally {
    Remove-Item -LiteralPath $outFile -ErrorAction SilentlyContinue
}

Write-Output ("zflow-boss-loot fixtures: {0} case(s), {1} failed" -f $cases, $bad)
if ($bad -gt 0) { exit 1 }
exit 0

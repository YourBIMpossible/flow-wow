<#
.SYNOPSIS
  Z-Flow saved-data size check (F-I). Reads a ZFlow.lua saved-variables
  file and fails when saved data is not bounded:

    TOOBIG     the file is larger than -MaxBytes;
    LONGLIST   a list (entries 1..n) anywhere in it has more than -MaxList
               entries: a module is adding to a list and never trimming it;
    DIAGSNAPS  ZFlowDB.diag.snaps holds more than -MaxSnaps snapshots
               (Core/Diag.lua keeps the newest 20);
    SNAPNAMES  a diag snapshot holds its own names table (the names are
               saved once, as diag.names).

  It then lists the largest tables, so what fills the file can be seen.
  The file is only read; nothing is copied or changed, and only paths and
  sizes are printed, never a saved value.

.USAGE
  powershell -ExecutionPolicy Bypass -File tools\zflow-saved-size.ps1 -File path
      [-MaxBytes 524288] [-MaxList 200] [-MaxSnaps 20] [-Top 10]

  Exit code 0 = bounded, 1 = a problem above, 2 = could not run (no file,
  or not readable as saved data).
  Fixtures: tools\fixtures\zflow-saved-size\run.ps1.
#>
param(
    [string]$File,
    [long]$MaxBytes = 524288,
    [int]$MaxList = 200,
    [int]$MaxSnaps = 20,
    [int]$Top = 10
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'zflow-saved.ps1')

if (-not $File) { Write-Output 'zflow-saved-size: pass -File (the ZFlow.lua to check)'; exit 2 }
if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { Write-Output "zflow-saved-size: no file at $File"; exit 2 }
$info = Get-Item -LiteralPath $File
try {
    $saved = Read-ZSavedFile $info.FullName
} catch {
    Write-Output ("zflow-saved-size: not readable as saved data: {0}" -f $_.Exception.Message)
    exit 2
}

$problems = New-Object System.Collections.ArrayList
$sizes = New-Object System.Collections.ArrayList

if ($info.Length -gt $MaxBytes) {
    [void]$problems.Add(("{0}: TOOBIG: {1} bytes, the limit is {2}" -f $info.Name, $info.Length, $MaxBytes))
}

function Visit($table, [string]$path) {
    [void]$sizes.Add(@{ Path = $path; Size = ($table.End - $table.Start) })
    $n = Get-ZSavedLength $table
    if ($n -gt $MaxList) {
        [void]$problems.Add(("{0}: LONGLIST: {1} entries, the limit is {2}" -f $path, $n, $MaxList))
    }
    foreach ($key in $table.Keys) {
        $child = Get-ZSaved $table $key
        if (Test-ZSavedTable $child) {
            if ($key -is [string]) { Visit $child ("{0}.{1}" -f $path, $key) }
            else { Visit $child ("{0}[{1}]" -f $path, $key) }
        }
    }
}

foreach ($name in ($saved.Keys | Sort-Object)) {
    if (Test-ZSavedTable $saved[$name]) { Visit $saved[$name] $name }
}

$snaps = Get-ZSaved $saved['ZFlowDB'] 'diag' 'snaps'
$kept = Get-ZSavedLength $snaps
if ($kept -gt $MaxSnaps) {
    [void]$problems.Add(("ZFlowDB.diag.snaps: DIAGSNAPS: {0} snapshots kept, the limit is {1}" -f $kept, $MaxSnaps))
}
$i = 0
foreach ($s in (Get-ZSavedList $snaps)) {
    $i++
    if (Test-ZSavedTable (Get-ZSaved $s 'names')) {
        [void]$problems.Add(("ZFlowDB.diag.snaps[{0}]: SNAPNAMES: the snapshot holds its own names table" -f $i))
    }
}

Write-Output ("zflow-saved-size: {0}, {1} bytes, {2} table(s)" -f $info.Name, $info.Length, $sizes.Count)
Write-Output ("Largest tables (characters in the file):")
$sizes | Sort-Object { $_.Size } -Descending | Select-Object -First $Top | ForEach-Object {
    Write-Output ("   {0,9}  {1}" -f $_.Size, $_.Path)
}
foreach ($p in $problems) { Write-Output $p }
Write-Output ("zflow-saved-size: {0} problem(s)" -f $problems.Count)
if ($problems.Count -gt 0) { exit 1 }
exit 0

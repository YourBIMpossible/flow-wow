<#
.SYNOPSIS
  Dry-run staging for Z-Flow (F-F). Copies the add-on as it would ship
  (ZFlow/ without Tests/) into <Out>/ZFlow, writes <Out>/BUILD.txt, then
  compares every staged file with the tree byte for byte and prints the file
  count. It installs nothing.

  It never reads or writes the game folder: it refuses an -Out (or a -Root)
  whose path has a "World of Warcraft" folder in it, in any letter case, and
  creates nothing there. It also refuses an -Out inside the tree's ZFlow/,
  and an -Out that already holds files but no BUILD.txt (not a stage folder
  it made; that folder is left untouched). An earlier stage folder (one with
  BUILD.txt) is replaced.

  BUILD.txt:
    commit: <git HEAD of -Root, or "not known">
    dirty: yes | no | not known      uncommitted changes under ZFlow/
    time: <UTC, yyyy-MM-ddTHH:mm:ssZ>
    files: <n>                       the staged file count
    source: <full path of -Root>

  Pure PowerShell (Windows PowerShell 5.1 or later).

.USAGE
  powershell -ExecutionPolicy Bypass -File tools\zflow-stage.ps1 -Out folder [-Root path]

  -Root  the folder that holds ZFlow/ (default: this checkout).
  Exit code 0 = staged and identical to the tree, 1 = staged but a file
  differs or is missing, 2 = refused or could not run.
  Fixtures: tools\fixtures\zflow-stage\run.ps1.
#>
param(
    [Parameter(Mandatory = $true)][string]$Out,
    [string]$Root
)
$ErrorActionPreference = 'Stop'

function Test-GamePath([string]$path) {
    foreach ($part in $path.Split([char[]]@('\', '/'))) {
        if ($part -ieq 'World of Warcraft') { return $true }
    }
    return $false
}

if (-not $Root) { $Root = Join-Path $PSScriptRoot '..' }
$rootFull = [IO.Path]::GetFullPath($Root)
$outFull = [IO.Path]::GetFullPath($Out).TrimEnd('\', '/')
if (Test-GamePath $outFull) {
    Write-Output "zflow-stage: refused: -Out '$outFull' is under a World of Warcraft folder. Staging never touches the game folder."
    exit 2
}
if (Test-GamePath $rootFull) {
    Write-Output "zflow-stage: refused: -Root '$rootFull' is under a World of Warcraft folder. Staging never reads the game folder."
    exit 2
}
$src = Join-Path $rootFull 'ZFlow'
if (-not (Test-Path -LiteralPath $src -PathType Container)) {
    Write-Output "zflow-stage: no ZFlow folder under '$rootFull'"
    exit 2
}
$src = (Resolve-Path -LiteralPath $src).Path
$srcPrefix = $src.TrimEnd('\') + '\'
if ($outFull -ieq $src -or $outFull.StartsWith($srcPrefix, [StringComparison]::OrdinalIgnoreCase) -or $outFull -ieq $rootFull.TrimEnd('\')) {
    Write-Output "zflow-stage: refused: -Out '$outFull' is the tree or inside ZFlow/"
    exit 2
}

# -Out: new, empty, or an earlier stage folder (BUILD.txt present) to replace.
$build = Join-Path $outFull 'BUILD.txt'
$stageZ = Join-Path $outFull 'ZFlow'
if (Test-Path -LiteralPath $outFull) {
    if (-not (Test-Path -LiteralPath $outFull -PathType Container)) {
        Write-Output "zflow-stage: refused: -Out '$outFull' is a file"
        exit 2
    }
    $items = @(Get-ChildItem -LiteralPath $outFull -Force)
    if ($items.Count -gt 0 -and -not (Test-Path -LiteralPath $build -PathType Leaf)) {
        Write-Output "zflow-stage: refused: -Out '$outFull' holds files but no BUILD.txt, so it is not a stage folder; left untouched"
        exit 2
    }
    foreach ($i in $items) {
        if ($i.Name -ne 'ZFlow' -and $i.Name -ne 'BUILD.txt') {
            Write-Output "zflow-stage: refused: -Out '$outFull' holds '$($i.Name)', which a stage folder does not; left untouched"
            exit 2
        }
    }
    if (Test-Path -LiteralPath $stageZ) { Remove-Item -LiteralPath $stageZ -Recurse -Force }
    if (Test-Path -LiteralPath $build) { Remove-Item -LiteralPath $build -Force }
}
New-Item -ItemType Directory -Force -Path $stageZ | Out-Null

# The add-on as it ships: everything under ZFlow/ but Tests/.
$files = @(Get-ChildItem -LiteralPath $src -Recurse -File -Force | ForEach-Object {
        $_.FullName.Substring($srcPrefix.Length)
    } | Where-Object { -not ($_ -like 'Tests\*') -and $_ -ne 'Tests' } | Sort-Object)
foreach ($rel in $files) {
    $to = Join-Path $stageZ $rel
    $dir = Split-Path -Parent $to
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Copy-Item -LiteralPath (Join-Path $src $rel) -Destination $to -Force
}

# BUILD.txt
$commit = 'not known'
$dirty = 'not known'
try {
    $head = (& git -C $rootFull rev-parse HEAD 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -eq 0 -and $head -match '^[0-9a-f]{40}$') {
        $commit = $head
        $status = @(& git -C $rootFull status --porcelain -- ZFlow 2>$null)
        if ($LASTEXITCODE -eq 0) { $dirty = $(if ($status.Count -gt 0) { 'yes' } else { 'no' }) }
    }
} catch {
    $commit = 'not known'
}
$time = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
[IO.File]::WriteAllLines($build, [string[]]@(
        ('commit: ' + $commit),
        ('dirty: ' + $dirty),
        ('time: ' + $time),
        ('files: ' + $files.Count),
        ('source: ' + $rootFull)
    ))

# Compare: every tree file staged and identical, nothing extra.
$problems = New-Object System.Collections.Generic.List[string]
foreach ($rel in $files) {
    $a = (Get-FileHash -LiteralPath (Join-Path $src $rel) -Algorithm SHA256).Hash
    $staged = Join-Path $stageZ $rel
    if (-not (Test-Path -LiteralPath $staged -PathType Leaf)) { $problems.Add("missing from the stage: ZFlow/$($rel.Replace('\', '/'))"); continue }
    if ((Get-FileHash -LiteralPath $staged -Algorithm SHA256).Hash -ne $a) { $problems.Add("differs from the tree: ZFlow/$($rel.Replace('\', '/'))") }
}
$stagedCount = @(Get-ChildItem -LiteralPath $stageZ -Recurse -File -Force).Count
if ($stagedCount -ne $files.Count) { $problems.Add(("the stage holds {0} file(s), the tree {1}" -f $stagedCount, $files.Count)) }
if (Test-Path -LiteralPath (Join-Path $stageZ 'Tests')) { $problems.Add('the stage holds ZFlow/Tests') }

foreach ($p in $problems) { Write-Output ("zflow-stage: " + $p) }
if ($problems.Count -gt 0) {
    Write-Output ("zflow-stage: {0} file(s) staged to {1}; {2} problem(s) comparing with the tree" -f $files.Count, $outFull, $problems.Count)
    exit 1
}
Write-Output ("zflow-stage: {0} file(s) staged to {1}; they match the tree (commit {2}, dirty {3}; Tests/ left out)" -f $files.Count, $outFull, $commit, $dirty)
exit 0

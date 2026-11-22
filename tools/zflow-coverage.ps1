<#
.SYNOPSIS
  Z-Flow manifest coverage check (F-B). Compares ZFlow/manifest.lua with the
  .lua files under ZFlow/ and fails when:

    UNLISTED   a ZFlow/**/*.lua file (Tests/** and manifest.lua itself
               excepted) is neither a manifest line nor on the "not loaded"
               list;
    MISSING    a manifest line names a file that does not exist, or exists
               only with other letter case (the game's file loading is
               case-sensitive on some systems, Windows is not);
    NOTLOADED  a "not loaded" entry names a file that is missing, or that the
               manifest also lists.

  A manifest line is any quoted "....lua" path in manifest.lua outside a
  comment, so { "Core/ClientFake.lua", dev = true } counts as listed.
  The "not loaded" list is $NotLoaded below (the lead keeps it) plus, when
  given, a -NotLoaded file: one path per line, relative to ZFlow/, with
  forward slashes; blank lines and lines starting with # are skipped.

  Pure PowerShell (Windows PowerShell 5.1 or later); no Lua needed. The Lua
  structure check (tools/zflow-structure.ps1) overlaps rules 1-2 but needs
  Lua 5.1 and has no "not loaded" list.

.USAGE
  powershell -ExecutionPolicy Bypass -File tools\zflow-coverage.ps1 [-Root path] [-NotLoaded file]

  -Root  the folder that holds ZFlow/ (default: this checkout).
  Exit code 0 = clean, 1 = a problem above, 2 = could not run.
  Fixtures: tools\fixtures\zflow-coverage\run.ps1.
#>
param([string]$Root, [string]$NotLoaded)
$ErrorActionPreference = 'Stop'

# Files under ZFlow/ that are deliberately not loaded by the add-on, relative
# to ZFlow/ with forward slashes. Each entry needs a reason in a comment.
$NotLoadedBuiltIn = @(
)

if (-not $Root) { $Root = Join-Path $PSScriptRoot '..' }
$zflow = Join-Path $Root 'ZFlow'
$manifest = Join-Path $zflow 'manifest.lua'
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
    Write-Output "zflow-coverage: no ZFlow/manifest.lua under '$Root'"
    exit 2
}
$zflow = (Resolve-Path -LiteralPath $zflow).Path

# ---- the manifest's lines (comments removed: --[[ ... ]] blocks and -- to end of line)
$text = [IO.File]::ReadAllText($manifest, [Text.Encoding]::UTF8)
$text = [regex]::Replace($text, '--\[(=*)\[[\s\S]*?\]\1\]', { param($m) ($m.Value -replace '[^\n]', '') })
$listed = New-Object System.Collections.Generic.List[object]
$lineNo = 0
foreach ($line in $text.Split("`n")) {
    $lineNo++
    $code = [regex]::Replace($line, '--.*$', '')
    foreach ($m in [regex]::Matches($code, '"([^"]+\.lua)"|''([^'']+\.lua)''')) {
        $path = $m.Groups[1].Value
        if (-not $path) { $path = $m.Groups[2].Value }
        $listed.Add([pscustomobject]@{ Path = $path.Replace('\', '/'); Line = $lineNo })
    }
}

# ---- the "not loaded" list
$skip = New-Object System.Collections.Generic.List[object]
foreach ($e in $NotLoadedBuiltIn) { $skip.Add([pscustomobject]@{ Path = $e; From = 'tools/zflow-coverage.ps1' }) }
if ($NotLoaded) {
    if (-not (Test-Path -LiteralPath $NotLoaded -PathType Leaf)) {
        Write-Output "zflow-coverage: no not-loaded list at '$NotLoaded'"
        exit 2
    }
    foreach ($l in [IO.File]::ReadAllLines($NotLoaded, [Text.Encoding]::UTF8)) {
        $t = $l.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        $skip.Add([pscustomobject]@{ Path = $t.Replace('\', '/'); From = $NotLoaded })
    }
}

# ---- the files on disk (exact case), Tests/ and manifest.lua excepted
$onDisk = @(Get-ChildItem -LiteralPath $zflow -Recurse -File -Filter *.lua |
    ForEach-Object { $_.FullName.Substring($zflow.Length + 1).Replace('\', '/') } |
    Where-Object { -not $_.StartsWith('Tests/') -and $_ -ne 'manifest.lua' })
$diskSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
foreach ($f in $onDisk) { [void]$diskSet.Add($f) }
$diskFold = @{}
foreach ($f in $onDisk) { $diskFold[$f.ToLowerInvariant()] = $f }

$listedSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
foreach ($e in $listed) { [void]$listedSet.Add($e.Path) }
$skipSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
foreach ($e in $skip) { [void]$skipSet.Add($e.Path) }

$problems = New-Object System.Collections.Generic.List[string]
foreach ($e in $listed) {
    if ($diskSet.Contains($e.Path)) { continue }
    $other = $diskFold[$e.Path.ToLowerInvariant()]
    if ($other) {
        $problems.Add(("ZFlow/manifest.lua:{0}: MISSING: '{1}' is on disk as '{2}' (letter case differs)" -f $e.Line, $e.Path, $other))
    } elseif ($e.Path.StartsWith('Tests/')) {
        $problems.Add(("ZFlow/manifest.lua:{0}: MISSING: '{1}' is a test file; the test runner finds tests itself" -f $e.Line, $e.Path))
    } else {
        $problems.Add(("ZFlow/manifest.lua:{0}: MISSING: '{1}' does not exist" -f $e.Line, $e.Path))
    }
}
foreach ($f in ($onDisk | Sort-Object)) {
    if (-not $listedSet.Contains($f) -and -not $skipSet.Contains($f)) {
        $problems.Add(("ZFlow/{0}:1: UNLISTED: not in manifest.lua and not on the not-loaded list" -f $f))
    }
}
foreach ($e in $skip) {
    if (-not $diskSet.Contains($e.Path)) {
        $problems.Add(("{0}: NOTLOADED: '{1}' is on the not-loaded list but does not exist" -f $e.From, $e.Path))
    } elseif ($listedSet.Contains($e.Path)) {
        $problems.Add(("{0}: NOTLOADED: '{1}' is on the not-loaded list and in manifest.lua" -f $e.From, $e.Path))
    }
}

foreach ($p in $problems) { Write-Output $p }
if ($problems.Count -gt 0) {
    Write-Output ("zflow-coverage: {0} problem(s); {1} manifest line(s), {2} file(s), {3} not-loaded entr(ies)" -f $problems.Count, $listed.Count, $onDisk.Count, $skip.Count)
    exit 1
}
Write-Output ("zflow-coverage: clean; {0} manifest line(s), {1} file(s), {2} not-loaded entr(ies)" -f $listed.Count, $onDisk.Count, $skip.Count)
exit 0

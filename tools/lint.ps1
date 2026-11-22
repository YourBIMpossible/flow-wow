<#
.SYNOPSIS
  Checks the Lua before you /reload: runs luacheck (rules in .luacheckrc) and the
  texture-path check. Catches a missing "local", a local used before it's declared,
  typos in names, unused or overwritten values and unreachable code.

.USAGE
  powershell -ExecutionPolicy Bypass -File tools\lint.ps1            # whole add-on
  powershell -ExecutionPolicy Bypass -File tools\lint.ps1 Modules\Nav # one folder or file

  Exit code 0 = clean. Finds luacheck.exe via FLOW_LUACHECK, then PATH, then
  %USERPROFILE%\tools\luacheck\luacheck.exe.
  Get it from https://github.com/lunarmodules/luacheck/releases (luacheck.exe).
#>
param([string[]]$Paths)
$root = Split-Path $PSScriptRoot -Parent

$exe = $null
if ($env:FLOW_LUACHECK -and (Test-Path $env:FLOW_LUACHECK)) { $exe = $env:FLOW_LUACHECK }
if (-not $exe) { $c = Get-Command luacheck -ErrorAction SilentlyContinue; if ($c) { $exe = $c.Source } }
if (-not $exe) {
    $guess = Join-Path $env:USERPROFILE 'tools\luacheck\luacheck.exe'
    if (Test-Path $guess) { $exe = $guess }
}
if (-not $exe) {
    "luacheck not found. Download luacheck.exe from https://github.com/lunarmodules/luacheck/releases"
    "and put it in $env:USERPROFILE\tools\luacheck\ (or set FLOW_LUACHECK to its path)."
    exit 2
}

if (-not $Paths) { $Paths = @('.') }
Push-Location $root
try {
    & $exe @Paths --no-color
    $lua = $LASTEXITCODE
} finally { Pop-Location }

& (Join-Path $PSScriptRoot 'check-paths.ps1')
$tex = $LASTEXITCODE

# Tests must never stand in for the game's own functions (with(_G, "UnitExists", ...)):
# writing a game global, even for a moment, taints it, and the Flow key is then
# blocked for the rest of the session (0.35.102). Stand in for Flow's own
# functions instead, or pass the values in.
$taint = 0
$luaFiles = Get-ChildItem -Path (Join-Path $root 'Modules'), (Join-Path $root 'Classes') -Recurse -Filter *.lua
foreach ($s in ($luaFiles | Select-String -Pattern 'with\(\s*_G\s*,')) {
    "{0}:{1}: a test swaps a game global (taints it): {2}" -f $s.Path.Substring($root.Length + 1), $s.LineNumber, $s.Line.Trim()
    $taint = 1
}
if ($taint -eq 0) { "game globals untouched by tests" }

# A function defined twice in one file (function N:InArea ... function N:InArea):
# the later one silently replaces the first, and every call meant for the
# first gets the wrong arguments. It broke the map twice (ShowStop, 0.35.76;
# InArea, 0.35.123). Only top-level definitions count: a method on a frame
# built inside a function (function a:SetRotation) is its own object's.
$dupes = 0
foreach ($f in (@($luaFiles) + @(Get-ChildItem -Path $root -Filter *.lua))) {
    $seen = @{}
    foreach ($s in (Select-String -Path $f.FullName -Pattern '^function\s+([A-Za-z_][\w.:]*)\s*\(')) {
        $name = $s.Matches[0].Groups[1].Value
        if ($seen.ContainsKey($name)) {
            "{0}:{1}: {2} is already defined at line {3}; the later one replaces it. Rename one." -f $f.FullName.Substring($root.Length + 1), $s.LineNumber, $name, $seen[$name]
            $dupes = 1
        } else { $seen[$name] = $s.LineNumber }
    }
}
if ($dupes -eq 0) { "no function defined twice" }

# A window's X (UIPanelCloseButton) left on the game's own click handler:
# that handler hides through the game's panel code, which an add-on window
# can't use in a fight, so the X did nothing until the fight ended (Escape
# still worked). Every X sets its own OnClick within the next few lines
# (0.35.163: six windows didn't).
$closes = 0
foreach ($f in $luaFiles) {
    $lines = Get-Content $f.FullName
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '"UIPanelCloseButton"' -and $lines[$i] -match 'CreateFrame') {
            $next = ($lines[$i..([Math]::Min($i + 5, $lines.Count - 1))] -join "`n")
            if ($next -notmatch 'SetScript\("OnClick"') {
                "{0}:{1}: this close button has no OnClick of its own; in a fight the game's handler won't close an add-on window. Add :SetScript(""OnClick"", function() f:Hide() end)." -f $f.FullName.Substring($root.Length + 1), ($i + 1)
                $closes = 1
            }
        }
    }
}
if ($closes -eq 0) { "every close button has its own handler" }

# tools/offline/client-globals.txt is the one list of the game's globals Flow
# reads (luacheck and the offline runner both use it). Two things luacheck
# can't see: a name on the list that no Lua file uses any more (the list must
# not grow into "anything goes"), and a global read as _G.Name, which luacheck
# takes for a table field: such a name must be on the list too (a plain line
# or a "_G:" line), or be one of Flow's own.
$names = 0
$listPath = Join-Path $root 'tools/offline/client-globals.txt'
if (-not (Test-Path -LiteralPath $listPath)) {
    "tools/offline/client-globals.txt is missing: luacheck and the offline runner both need it"
    $names = 1
} else {
    $plain = New-Object 'System.Collections.Generic.HashSet[string]'
    $viaG = New-Object 'System.Collections.Generic.HashSet[string]'
    $patterns = @()
    $prev = ''
    $prevG = ''
    foreach ($raw in (Get-Content -LiteralPath $listPath)) {
        $l = $raw.Trim()
        if ($l -eq '' -or $l.StartsWith('#')) { continue }
        if ($l -cmatch '^_G:\s*(.+)$') {
            $n = $Matches[1]
            if ($n.Contains('*')) { $patterns += '^' + ([regex]::Escape($n) -replace '\\\*', '[\w ]*') + '$' }
            else { [void]$viaG.Add($n) }
            if ([string]::CompareOrdinal($n, $prevG) -le 0) { "client-globals.txt: '_G: $n' is out of order or listed twice (keep the _G: lines sorted)"; $names = 1 }
            $prevG = $n
        } elseif ($l -cmatch '^[A-Za-z_]\w*$') {
            [void]$plain.Add($l)
            if ([string]::CompareOrdinal($l, $prev) -le 0) { "client-globals.txt: '$l' is out of order or listed twice (keep the list sorted)"; $names = 1 }
            $prev = $l
        } else { "client-globals.txt: not a global's name: $l"; $names = 1 }
    }
    $words = New-Object 'System.Collections.Generic.HashSet[string]'
    $readViaG = @{}
    foreach ($f in (@($luaFiles) + @(Get-ChildItem -Path $root -Filter *.lua))) {
        $text = [IO.File]::ReadAllText($f.FullName)
        foreach ($m in [regex]::Matches($text, '[A-Za-z_]\w*')) { [void]$words.Add($m.Value) }
        foreach ($m in [regex]::Matches($text, '(?<![\w.])_G\.([A-Za-z_]\w*)')) {
            $n = $m.Groups[1].Value
            if (-not $readViaG.ContainsKey($n)) { $readViaG[$n] = $f.FullName.Substring($root.Length + 1) }
        }
    }
    foreach ($n in ($plain | Sort-Object)) {
        if (-not $words.Contains($n)) { "client-globals.txt: no Lua file uses '$n' any more: take the line off"; $names = 1 }
    }
    foreach ($n in ($readViaG.Keys | Sort-Object)) {
        if ($n -cmatch '^(Flow|SLASH_FLOW|BINDING_)') { continue }
        if ($plain.Contains($n) -or $viaG.Contains($n)) { continue }
        if ($patterns | Where-Object { $n -cmatch $_ }) { continue }
        "{0}: reads _G.{1}, which is not in tools/offline/client-globals.txt: a typo, or add a line `"_G: {1}`"" -f $readViaG[$n], $n
        $names = 1
    }
    if ($names -eq 0) { "client globals: every listed name is used, every _G.Name is listed" }
}

if ($lua -ne 0 -or $tex -ne 0 -or $taint -ne 0 -or $dupes -ne 0 -or $closes -ne 0 -or $names -ne 0) { "LINT FAILED: fix the lines above before committing."; exit 1 }
"lint OK"

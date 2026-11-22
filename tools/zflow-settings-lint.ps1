<#
.SYNOPSIS
  Z-Flow settings lint (F-C). Fails when:

    DUPKEY      a key appears twice in ZFlow/Settings/Model.lua's M.ROWS;
    ROWFIELDS   a row in M.ROWS has no type or no default;
    UNKNOWNKEY  a settings:get("x") call names a key that is not a row.

  The rows a get may name: the keys in M.ROWS, plus the rows add-on code
  declares at run time (the key of a k:Setting{...} / k:Setting({...}) call
  and of a module's settings = { { key = ... } } list, anywhere under
  ZFlow/ outside Tests/). A test file may also name any key it declares
  itself (any key = "x" in that file), and may read a key that is not a
  row when it compares the result to nil (a deliberate probe; listed as NOTE).

  A get is checked when its key is a string, or a Name.FIELD constant set to
  a string in the same file (X.SETTING = "vendor.list"). Any other key (a
  variable, a constant from another file) is not checked; those calls are
  listed as NOTE lines and do not fail the run.

  Comments are skipped; strings are read as Lua 5.1 reads them. Pure
  PowerShell (Windows PowerShell 5.1 or later); no Lua needed.

.USAGE
  powershell -ExecutionPolicy Bypass -File tools\zflow-settings-lint.ps1 [-Root path]

  -Root  the folder that holds ZFlow/ (default: this checkout).
  Exit code 0 = clean, 1 = a problem above, 2 = could not run.
  Fixtures: tools\fixtures\zflow-settings-lint\run.ps1.
#>
param([string]$Root)
$ErrorActionPreference = 'Stop'

if (-not $Root) { $Root = Join-Path $PSScriptRoot '..' }
$zflow = Join-Path $Root 'ZFlow'
$modelPath = Join-Path $zflow 'Settings/Model.lua'
if (-not (Test-Path -LiteralPath $modelPath -PathType Leaf)) {
    Write-Output "zflow-settings-lint: no ZFlow/Settings/Model.lua under '$Root'"
    exit 2
}
$zflow = (Resolve-Path -LiteralPath $zflow).Path
# ------------------------------------------------------------------ scanner
# Splits Lua 5.1 source into code (comments blanked, each string replaced by
# "@<index>", line breaks kept so line numbers hold) and the decoded strings.
function Get-LuaScan([string]$text) {
    $code = New-Object System.Text.StringBuilder
    $strings = New-Object System.Collections.Generic.List[object]
    $line = 1
    $i = 0
    $n = $text.Length

    # The level of a long bracket at $at ("[[" = 0, "[==[" = 2), or -1.
    function LongLevel([int]$at) {
        if ($at -ge $n -or $text[$at] -ne '[') { return -1 }
        $j = $at + 1
        while ($j -lt $n -and $text[$j] -eq '=') { $j++ }
        if ($j -lt $n -and $text[$j] -eq '[') { return ($j - $at - 1) }
        return -1
    }

    while ($i -lt $n) {
        $ch = $text[$i]
        if ($ch -eq '-' -and $i + 1 -lt $n -and $text[$i + 1] -eq '-') {
            $lvl = LongLevel ($i + 2)
            if ($lvl -ge 0) {
                $close = ']' + ('=' * $lvl) + ']'
                $end = $text.IndexOf($close, $i + 4 + $lvl, [StringComparison]::Ordinal)
                if ($end -lt 0) { $end = $n } else { $end += $close.Length }
                $body = $text.Substring($i, $end - $i)
                foreach ($c in $body.ToCharArray()) { if ($c -eq "`n") { [void]$code.Append("`n"); $line++ } }
                $i = $end
            } else {
                while ($i -lt $n -and $text[$i] -ne "`n") { $i++ }
            }
            continue
        }
        if ($ch -eq '"' -or $ch -eq "'") {
            $q = $ch
            $start = $line
            $bytes = New-Object System.Collections.Generic.List[byte]
            $i++
            while ($i -lt $n -and $text[$i] -ne $q -and $text[$i] -ne "`n") {
                $c = $text[$i]
                if ($c -eq '\' -and $i + 1 -lt $n) {
                    $e = $text[$i + 1]
                    if ($e -match '[0-9]') {
                        $j = $i + 1; $digits = ''
                        while ($j -lt $n -and $digits.Length -lt 3 -and $text[$j] -match '[0-9]') { $digits += $text[$j]; $j++ }
                        $bytes.Add([byte]([int]$digits -band 0xFF)); $i = $j; continue
                    }
                    $map = @{ 'n' = 10; 't' = 9; 'r' = 13; 'a' = 7; 'b' = 8; 'f' = 12; 'v' = 11 }
                    $key = [string]$e
                    if ($map.ContainsKey($key)) { $bytes.Add([byte]$map[$key]) }
                    elseif ($e -eq "`n") { $bytes.Add([byte]10); [void]$code.Append("`n"); $line++ }
                    else { foreach ($b in [Text.Encoding]::UTF8.GetBytes($key)) { $bytes.Add($b) } }
                    $i += 2; continue
                }
                if ([char]::IsHighSurrogate($c) -and $i + 1 -lt $n) {
                    foreach ($b in [Text.Encoding]::UTF8.GetBytes($text.Substring($i, 2))) { $bytes.Add($b) }
                    $i += 2; continue
                }
                foreach ($b in [Text.Encoding]::UTF8.GetBytes([string]$c)) { $bytes.Add($b) }
                $i++
            }
            $i++   # the closing quote
            $strings.Add([pscustomobject]@{ Line = $start; Value = [Text.Encoding]::UTF8.GetString($bytes.ToArray()) })
            [void]$code.Append('"@' + ($strings.Count - 1) + '"')
            continue
        }
        if ($ch -eq '[') {
            $lvl = LongLevel $i
            if ($lvl -ge 0) {
                $open = $i + 2 + $lvl
                $close = ']' + ('=' * $lvl) + ']'
                $end = $text.IndexOf($close, $open, [StringComparison]::Ordinal)
                if ($end -lt 0) { $end = $n }
                $body = $text.Substring($open, $end - $open)
                if ($body.StartsWith("`r`n")) { $body = $body.Substring(2) } elseif ($body.StartsWith("`n")) { $body = $body.Substring(1) }
                $strings.Add([pscustomobject]@{ Line = $line; Value = $body.Replace("`r", '') })
                [void]$code.Append('"@' + ($strings.Count - 1) + '"')
                foreach ($c in $text.Substring($i, [Math]::Min($n, $end + $close.Length) - $i).ToCharArray()) {
                    if ($c -eq "`n") { [void]$code.Append("`n"); $line++ }
                }
                $i = [Math]::Min($n, $end + $close.Length)
                continue
            }
        }
        if ($ch -eq "`n") { $line++ }
        [void]$code.Append($ch)
        $i++
    }
    return [pscustomobject]@{ Code = $code.ToString(); Strings = $strings }
}


# The index just past the bracket that closes the one at $open ("{" or "("),
# in scanned code (strings are placeholders, so brackets inside them are gone).
function Find-Close([string]$code, [int]$open) {
    $depth = 0
    for ($j = $open; $j -lt $code.Length; $j++) {
        $c = $code[$j]
        if ($c -eq '{' -or $c -eq '(') { $depth++ }
        elseif ($c -eq '}' -or $c -eq ')') { $depth--; if ($depth -eq 0) { return $j + 1 } }
    }
    return $code.Length
}

function LineAt([string]$code, [int]$index) {
    return ([regex]::Matches($code.Substring(0, $index), "`n").Count + 1)
}

# Name.FIELD = "value" constants in one scanned file.
function Get-Constants($scan) {
    $map = @{}
    foreach ($m in [regex]::Matches($scan.Code, '(?<![\w.])([A-Za-z_]\w*\.[A-Za-z_]\w*)\s*=\s*"@(\d+)"')) {
        $map[$m.Groups[1].Value] = $scan.Strings[[int]$m.Groups[2].Value].Value
    }
    return $map
}

# The key named by `key = <...>` text: a string, or a constant from $consts.
function Get-KeysIn([string]$region, $scan, $consts) {
    $keys = @()
    foreach ($m in [regex]::Matches($region, '\bkey\s*=\s*(?:"@(\d+)"|([A-Za-z_]\w*\.[A-Za-z_]\w*))')) {
        if ($m.Groups[1].Success) { $keys += $scan.Strings[[int]$m.Groups[1].Value].Value }
        elseif ($consts.ContainsKey($m.Groups[2].Value)) { $keys += $consts[$m.Groups[2].Value] }
    }
    return $keys
}

$problems = New-Object System.Collections.Generic.List[string]
$notes = New-Object System.Collections.Generic.List[string]

# ---- the model's rows
$model = Get-LuaScan ([IO.File]::ReadAllText($modelPath, [Text.Encoding]::UTF8))
$rowsAt = [regex]::Match($model.Code, '\bROWS\s*=\s*\{')
if (-not $rowsAt.Success) {
    Write-Output "zflow-settings-lint: ZFlow/Settings/Model.lua has no ROWS = { ... } table"
    exit 2
}
$open = $rowsAt.Index + $rowsAt.Length - 1
$close = Find-Close $model.Code $open
$known = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$seenAt = @{}
$j = $open + 1
$modelRows = 0
while ($j -lt $close - 1) {
    $c = $model.Code[$j]
    if ($c -eq '{') {
        $end = Find-Close $model.Code $j
        $entry = $model.Code.Substring($j, $end - $j)
        $line = LineAt $model.Code $j
        $modelRows++
        $km = [regex]::Match($entry, '\bkey\s*=\s*"@(\d+)"')
        $key = $null
        if ($km.Success) { $key = $model.Strings[[int]$km.Groups[1].Value].Value }
        $label = $key
        if (-not $label) { $label = '(no key)'; $problems.Add(("ZFlow/Settings/Model.lua:{0}: ROWFIELDS: a row with no key" -f $line)) }
        if ($entry -notmatch '\btype\s*=') { $problems.Add(("ZFlow/Settings/Model.lua:{0}: ROWFIELDS: row '{1}' has no type" -f $line, $label)) }
        if ($entry -notmatch '\bdefault\s*=') { $problems.Add(("ZFlow/Settings/Model.lua:{0}: ROWFIELDS: row '{1}' has no default" -f $line, $label)) }
        if ($key) {
            if ($seenAt.ContainsKey($key)) {
                $problems.Add(("ZFlow/Settings/Model.lua:{0}: DUPKEY: '{1}' is already a row at line {2}" -f $line, $key, $seenAt[$key]))
            } else {
                $seenAt[$key] = $line
                [void]$known.Add($key)
            }
        }
        $j = $end
        continue
    }
    $j++
}

# ---- every file: scan once; collect run-time rows from add-on code
$files = @(Get-ChildItem -LiteralPath $zflow -Recurse -File -Filter *.lua |
    Sort-Object { $_.FullName.Substring($zflow.Length + 1).Replace('\', '/') })
$scans = @{}
$declared = 0
foreach ($f in $files) {
    $rel = $f.FullName.Substring($zflow.Length + 1).Replace('\', '/')
    $scan = Get-LuaScan ([IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8))
    $consts = Get-Constants $scan
    $scans[$rel] = @{ Scan = $scan; Consts = $consts }
    if ($rel.StartsWith('Tests/')) { continue }
    foreach ($m in [regex]::Matches($scan.Code, ':\s*Setting\s*[\({]|\bsettings\s*=\s*\{')) {
        $at = $m.Index + $m.Length - 1
        $region = $scan.Code.Substring($at, (Find-Close $scan.Code $at) - $at)
        foreach ($k in (Get-KeysIn $region $scan $consts)) { if ($known.Add($k)) { $declared++ } }
    }
}

# ---- the gets
$checked = 0
foreach ($rel in ($scans.Keys | Sort-Object)) {
    $scan = $scans[$rel].Scan
    $consts = $scans[$rel].Consts
    $isTest = $rel.StartsWith('Tests/')
    $own = $null
    if ($isTest) {
        $own = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach ($k in (Get-KeysIn $scan.Code $scan $consts)) { [void]$own.Add($k) }
    }
    foreach ($m in [regex]::Matches($scan.Code, '\bsettings\s*:\s*get\s*\(\s*([^)]*?)\s*\)')) {
        $arg = $m.Groups[1].Value
        $line = LineAt $scan.Code $m.Index
        $key = $null
        $sm = [regex]::Match($arg, '^"@(\d+)"$')
        if ($sm.Success) { $key = $scan.Strings[[int]$sm.Groups[1].Value].Value }
        elseif ($consts.ContainsKey($arg)) { $key = $consts[$arg] }
        if ($null -eq $key) {
            $notes.Add(("ZFlow/{0}:{1}: NOTE: settings:get({2}) not checked (the key is not a string or a same-file constant)" -f $rel, $line, $arg))
            continue
        }
        $checked++
        if ($known.Contains($key)) { continue }
        if ($isTest -and $own.Contains($key)) { continue }
        # A test that compares the get to nil reads an unknown key on purpose.
        $after = $scan.Code.Substring($m.Index + $m.Length)
        if ($isTest -and $after -match '^\s*,\s*nil\b') {
            $notes.Add(("ZFlow/{0}:{1}: NOTE: settings:get('{2}') is a test probe for a key that is not a row (compared to nil)" -f $rel, $line, $key))
            continue
        }
        $where = 'not a row in Settings/Model.lua or a declared row'
        if ($isTest) { $where += ', and this test file does not declare it' }
        $problems.Add(("ZFlow/{0}:{1}: UNKNOWNKEY: settings:get('{2}'): {3}" -f $rel, $line, $key, $where))
    }
}

foreach ($p in $problems) { Write-Output $p }
foreach ($n in $notes) { Write-Output $n }
$summary = "{0} model row(s), {1} declared row(s), {2} get(s) checked, {3} not checked" -f $modelRows, $declared, $checked, $notes.Count
if ($problems.Count -gt 0) {
    Write-Output ("zflow-settings-lint: {0} problem(s); {1}" -f $problems.Count, $summary)
    exit 1
}
Write-Output ("zflow-settings-lint: clean; {0}" -f $summary)
exit 0
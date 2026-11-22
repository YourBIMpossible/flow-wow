<#
.SYNOPSIS
  Z-Flow text check (F-A). Reads every ZFlow/**/*.lua except ZFlow/Tests/**
  and fails on user-facing strings that break the price and chat rules:

    F085   the F-085 fallback is written any way but the allowed forms (LEDGER
           113 Decision 2), em dash (U+2014) always, no spaces around it:
             "price unknown<em dash>check vendor"     an item's price
             "price unknown<em dash>check trainer"    a training cost
             "<n> prices unknown<em dash>check vendor" / "... trainer"   a count line
           Flagged: a string with "price unknown" / "prices unknown", or
           "unknown - check vendor|trainer|merchant" with any dash or colon,
           that contains none of the allowed texts. So the hyphen form,
           "unknown - check trainer" without "price" and a bare
           "price unknown" all fail. A count line may also be built by
           concatenation: a string that is exactly "unknown<em dash>check vendor"
           or "... trainer" (leading spaces allowed) passes when it is the
           right operand of "..", as in n .. " prices " .. "unknown<em dash>check vendor".
           On its own it fails.
           (A lone "s" joined after a duration is seconds, see PRICE.)
    PRICE  a price that is not labelled: a money figure in a string ("12s 40c",
           "5g", "3c", or a %d/%s format followed by g or c), unless the same
           string says "estimate"; or coin text built by concatenating "g", "s"
           or "c". ZFlow/Items/Prices.lua is exempt: it is the one place that
           builds coin text and labels it (Prices.Text: observed, "about ...
           (estimate)", or unknown). A lone "5s" is read as seconds, not money,
           and so is a lone "s" joined after a duration (whole(f.ended -
           f.started) .. "s"). An "s" piece still counts as silver when the
           same line also joins "g" or "c", or when it follows a variable
           named s or silver.
    PRINT  an empty string handed to the chat print: print(""), print('')
           print([[]]) or print() with no argument, on any receiver
           (client.print, c.print, print).

  Comments are not user text and are skipped. Strings are read as Lua 5.1
  reads them, so "\226\128\148" is the em dash. Pure PowerShell (Windows
  PowerShell 5.1 or later); no Lua needed.

.USAGE
  powershell -ExecutionPolicy Bypass -File tools\zflow-text.ps1 [-Root path]

  -Root  the folder that holds ZFlow/ (default: this checkout).
  Exit code 0 = clean, 1 = a problem above, 2 = could not run.
  Fixtures: tools\fixtures\zflow-text\run.ps1.
#>
param([string]$Root)
$ErrorActionPreference = 'Stop'

if (-not $Root) { $Root = Join-Path $PSScriptRoot '..' }
$zflow = Join-Path $Root 'ZFlow'
if (-not (Test-Path -LiteralPath $zflow -PathType Container)) {
    Write-Output "zflow-text: no ZFlow folder under '$Root'"
    exit 2
}
$zflow = (Resolve-Path -LiteralPath $zflow).Path

$EM = [string][char]0x2014
$ALLOWED = @(
    ('price unknown' + $EM + 'check vendor'),
    ('price unknown' + $EM + 'check trainer'),
    ('prices unknown' + $EM + 'check vendor'),
    ('prices unknown' + $EM + 'check trainer')
)
# The tail of a count line built by concatenation (n .. " prices " .. "unknown<em dash>check vendor"),
# allowed only as the right operand of "..".
$FRAGMENTS = @(
    ('unknown' + $EM + 'check vendor'),
    ('unknown' + $EM + 'check trainer')
)
function Test-Allowed([string]$v) {
    foreach ($a in $ALLOWED) { if ($v.IndexOf($a, [StringComparison]::Ordinal) -ge 0) { return $true } }
    return $false
}

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

function Show([string]$s) {
    # Name dashes in ASCII: a default Windows console prints U+2014 and U+2013 as "-", which would
    # make a correct string look like the hyphen form the rule rejects.
    $t = $s.Replace("`n", '\n').Replace([string][char]0x2014, '<U+2014>').Replace([string][char]0x2013, '<U+2013>')
    if ($t.Length -gt 80) { $t = $t.Substring(0, 77) + '...' }
    return '"' + $t + '"'
}

# -------------------------------------------------------------------- rules
$reFallback = '(?i)\bprices?\s+unknown\b|unknown\s*[-:\u2013\u2014]+\s*check\s+(vendor|trainer|merchant)\b'
$reFigure = '(?<![\w.])\d+\s?([gsc])(?!\w)'
$reFormat = '%[ds]\s?[gc](?!\w)'
$reCoinPiece = '^\s?[gsc]\s?$'
$reConcat = '\.\.\s*"@(\d+)"'
$rePrint = '(?<![\w])print\s*\(\s*(?:"@(\d+)")?\s*\)'

$problems = New-Object System.Collections.Generic.List[string]
$files = @(Get-ChildItem -LiteralPath $zflow -Recurse -File -Filter *.lua |
    Where-Object { -not $_.FullName.Substring($zflow.Length + 1).Replace('\', '/').StartsWith('Tests/') } |
    Sort-Object { $_.FullName.Substring($zflow.Length + 1).Replace('\', '/') })

foreach ($f in $files) {
    $rel = $f.FullName.Substring($zflow.Length + 1).Replace('\', '/')
    $scan = Get-LuaScan ([IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8))
    $where = 'ZFlow/' + $rel
    $isPrices = ($rel -eq 'Items/Prices.lua')

    # Strings that are the right operand of "..": the tail of a built count line.
    $tails = @{}
    foreach ($m in [regex]::Matches($scan.Code, $reConcat)) { $tails[[int]$m.Groups[1].Value] = $true }

    for ($si = 0; $si -lt $scan.Strings.Count; $si++) {
        $s = $scan.Strings[$si]
        $v = $s.Value
        # n .. " prices " .. "unknown<em dash>check vendor": the shown line is an allowed count line.
        $countTail = $tails.ContainsKey($si) -and ($FRAGMENTS -contains $v.TrimStart(' '))
        if ($v -match $reFallback -and -not (Test-Allowed $v) -and -not $countTail) {
            $problems.Add(("{0}:{1}: F085: use 'price unknown{2}check vendor', 'price unknown{2}check trainer' or a count line '<n> prices unknown{2}check ...' ({2} = em dash, no spaces): {3}" -f $where, $s.Line, '<U+2014>', (Show $v)))
        }
        if (-not $isPrices -and $v -notmatch '(?i)estimate') {
            $money = $false
            $figures = [regex]::Matches($v, $reFigure)
            foreach ($m in $figures) { if ($m.Groups[1].Value -ne 's') { $money = $true } }
            if ($figures.Count -ge 2) { $money = $true }
            if ($v -match $reFormat) { $money = $true }
            if ($money) {
                $problems.Add(("{0}:{1}: PRICE: a money figure with no label; show prices through Prices.Text: {2}" -f $where, $s.Line, (Show $v)))
            }
        }
    }

    $lines = $scan.Code.Split("`n")
    for ($k = 0; $k -lt $lines.Length; $k++) {
        $ln = $lines[$k]
        if (-not $isPrices) {
            # The coin pieces this line joins: a "g" or "c" piece makes it coin text, and so does an
            # "s" piece in a line that also joins "g" or "c". A lone "s" joined after anything else
            # (a duration: whole(f.ended - f.started) .. "s") is seconds, unless what it follows is a
            # variable named s or silver.
            $pieces = @([regex]::Matches($ln, $reConcat) | ForEach-Object {
                    [pscustomobject]@{ M = $_; V = $scan.Strings[[int]$_.Groups[1].Value].Value }
                })
            $coinLine = @($pieces | Where-Object { $_.V -match $reCoinPiece -and $_.V.Trim() -ne 's' }).Count -gt 0
            foreach ($piece in $pieces) {
                $v = $piece.V
                $isCoin = $v -match $reCoinPiece
                if ($isCoin -and $v.Trim() -eq 's' -and -not $coinLine) {
                    $left = $ln.Substring(0, $piece.M.Index).TrimEnd()
                    $isCoin = $left -match '(?i)(?<![\w.:])(s|silver)$'
                }
                if ($isCoin) {
                    $problems.Add(("{0}:{1}: PRICE: coin text built outside Items/Prices.lua; use Prices.Text: .. {2}" -f $where, ($k + 1), (Show $v)))
                }
            }
        }
        foreach ($m in [regex]::Matches($ln, $rePrint)) {
            $before = $ln.Substring(0, $m.Index)
            if ($before -match '\bfunction\s+[\w.:]*$') { continue }   # a definition, not a call
            $empty = $true
            if ($m.Groups[1].Success) { $empty = ($scan.Strings[[int]$m.Groups[1].Value].Value -eq '') }
            if ($empty) {
                $problems.Add(("{0}:{1}: PRINT: an empty string to the chat print" -f $where, ($k + 1)))
            }
        }
    }
}

foreach ($p in $problems) { Write-Output $p }
if ($problems.Count -gt 0) {
    Write-Output ("zflow-text: {0} problem(s) in {1} file(s) read" -f $problems.Count, $files.Count)
    exit 1
}
Write-Output ("zflow-text: clean ({0} file(s) read)" -f $files.Count)
exit 0

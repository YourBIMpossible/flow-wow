<#
  Shared by tools/zflow-read-diag.ps1 and tools/zflow-saved-size.ps1.
  Dot-source it. Reads a saved-variables file as the game writes it (plain
  Lua data: Name = { ... } with strings, numbers, true, false, nil and
  nested tables) into PowerShell values. Nothing is run as Lua, and the
  file is only read.

  A table becomes a [pscustomobject] with:
    Keys   the keys in file order (a [int] for [3] = and for a value with
           no key, a [string] for ["name"] =)
    Map    a hashtable from key to value ("s:name" for a string key,
           "n:3" for a number key; use Get-ZSaved, not Map, to read)
    Start, End   where the table is in the text, to size it
  Any other value is a [string], [double], [bool] or $null.
#>

function New-ZSavedTable([int]$Start) {
    return [pscustomobject]@{ IsZTable = $true; Keys = (New-Object System.Collections.ArrayList); Map = @{}; Start = $Start; End = $Start }
}

function Test-ZSavedTable($v) {
    return ($null -ne $v) -and ($v -is [pscustomobject]) -and ($v.PSObject.Properties.Name -contains 'IsZTable')
}

function Get-ZSavedSlot($key) {
    if ($key -is [string]) { return 's:' + $key }
    return 'n:' + ([string][int]$key)
}

# The value at a path of keys below a table, or $null when any step is not there.
function Get-ZSaved($table) {
    $at = $table
    foreach ($key in $args) {
        if (-not (Test-ZSavedTable $at)) { return $null }
        $slot = Get-ZSavedSlot $key
        if (-not $at.Map.ContainsKey($slot)) { return $null }
        $at = $at.Map[$slot]
    }
    return $at
}

# How many entries 1..n a table holds with no gap.
function Get-ZSavedLength($table) {
    if (-not (Test-ZSavedTable $table)) { return 0 }
    $n = 0
    while ($table.Map.ContainsKey('n:' + ([string]($n + 1)))) { $n++ }
    return $n
}

# The entries 1..n of a table, in order.
function Get-ZSavedList($table) {
    $out = @()
    $n = Get-ZSavedLength $table
    for ($i = 1; $i -le $n; $i++) { $out += , $table.Map['n:' + ([string]$i)] }
    return , $out
}

function ConvertFrom-ZSavedString([string]$raw) {
    $sb = New-Object System.Text.StringBuilder
    $i = 0
    while ($i -lt $raw.Length) {
        $ch = $raw[$i]
        if ($ch -eq '\' -and ($i + 1) -lt $raw.Length) {
            $next = $raw[$i + 1]
            if ($next -eq 'n') { [void]$sb.Append("`n"); $i += 2; continue }
            if ($next -eq 'r') { [void]$sb.Append("`r"); $i += 2; continue }
            if ($next -eq 't') { [void]$sb.Append("`t"); $i += 2; continue }
            if ([char]::IsDigit($next)) {
                $j = $i + 1
                $digits = ''
                while ($j -lt $raw.Length -and $digits.Length -lt 3 -and [char]::IsDigit($raw[$j])) { $digits += $raw[$j]; $j++ }
                [void]$sb.Append([char][int]$digits)
                $i = $j
                continue
            }
            [void]$sb.Append($next)
            $i += 2
            continue
        }
        [void]$sb.Append($ch)
        $i++
    }
    return $sb.ToString()
}

# Reads the whole text. Returns a hashtable from each top-level name to its
# value. Throws with the place in the text when it is not plain saved data.
function Read-ZSavedText([string]$Text) {
    $pattern = '\G(?:\s+|--[^\n]*)*(?:(?<str>"(?:[^"\\]|\\.)*")|(?<punct>[{}=,;\[\]])|(?<word>[^\s{}=,;\[\]"]+))'
    $rx = New-Object System.Text.RegularExpressions.Regex($pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $tokens = New-Object System.Collections.ArrayList
    $m = $rx.Match($Text, 0)
    $last = 0
    while ($m.Success) {
        if ($m.Groups['str'].Success) {
            $g = $m.Groups['str']
            [void]$tokens.Add(@{ Kind = 'str'; Text = $g.Value.Substring(1, $g.Length - 2); At = $g.Index; End = $g.Index + $g.Length })
        } elseif ($m.Groups['punct'].Success) {
            $g = $m.Groups['punct']
            [void]$tokens.Add(@{ Kind = 'punct'; Text = $g.Value; At = $g.Index; End = $g.Index + $g.Length })
        } else {
            $g = $m.Groups['word']
            [void]$tokens.Add(@{ Kind = 'word'; Text = $g.Value; At = $g.Index; End = $g.Index + $g.Length })
        }
        $last = $m.Index + $m.Length
        $m = $rx.Match($Text, $last)
    }
    if ($Text.Substring($last).Trim() -ne '' -and $Text.Substring($last) -notmatch '^(?:\s+|--[^\n]*)*$') {
        throw "not saved data at character $last"
    }

    $state = @{ Pos = 0 }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture

    function Is-Punct($tok, [string]$what) { return ($null -ne $tok) -and $tok.Kind -eq 'punct' -and $tok.Text -eq $what }

    function Read-Value {
        if ($state.Pos -ge $tokens.Count) { throw 'the file ends where a value should be' }
        $tok = $tokens[$state.Pos]
        if ($tok.Kind -eq 'str') { $state.Pos++; return (ConvertFrom-ZSavedString $tok.Text) }
        if ($tok.Kind -eq 'word') {
            $state.Pos++
            if ($tok.Text -eq 'true') { return $true }
            if ($tok.Text -eq 'false') { return $false }
            if ($tok.Text -eq 'nil') { return $null }
            $num = 0.0
            if ([double]::TryParse($tok.Text, [System.Globalization.NumberStyles]::Float, $inv, [ref]$num)) { return $num }
            if ($tok.Text -match '^-?(inf|nan|1\.#INF|1\.#IND)') { return [double]::NaN }
            throw "not a value at character $($tok.At): $($tok.Text)"
        }
        if (-not (Is-Punct $tok '{')) { throw "not a value at character $($tok.At): $($tok.Text)" }
        $table = New-ZSavedTable $tok.At
        $state.Pos++
        $next = 1
        while ($true) {
            if ($state.Pos -ge $tokens.Count) { throw "the table opened at character $($table.Start) is not closed" }
            $tok = $tokens[$state.Pos]
            if (Is-Punct $tok '}') { $table.End = $tok.End; $state.Pos++; break }
            $key = $null
            $after = $null
            if (($state.Pos + 1) -lt $tokens.Count) { $after = $tokens[$state.Pos + 1] }
            if (Is-Punct $tok '[') {
                $ktok = $tokens[$state.Pos + 1]
                if ($ktok.Kind -eq 'str') { $key = ConvertFrom-ZSavedString $ktok.Text }
                else { $key = [int][double]::Parse($ktok.Text, $inv) }
                if (-not (Is-Punct $tokens[$state.Pos + 2] ']') -or -not (Is-Punct $tokens[$state.Pos + 3] '=')) {
                    throw "not a key at character $($tok.At)"
                }
                $state.Pos += 4
            } elseif ($tok.Kind -eq 'word' -and (Is-Punct $after '=')) {
                $key = [string]$tok.Text
                $state.Pos += 2
            } else {
                $key = $next
                $next++
            }
            $value = Read-Value
            $slot = Get-ZSavedSlot $key
            if (-not $table.Map.ContainsKey($slot)) { [void]$table.Keys.Add($key) }
            $table.Map[$slot] = $value
            $tok = $null
            if ($state.Pos -lt $tokens.Count) { $tok = $tokens[$state.Pos] }
            if ((Is-Punct $tok ',') -or (Is-Punct $tok ';')) { $state.Pos++ }
        }
        return $table
    }

    $top = @{}
    while ($state.Pos -lt $tokens.Count) {
        $name = $tokens[$state.Pos]
        if ($name.Kind -ne 'word' -or -not (Is-Punct $tokens[$state.Pos + 1] '=')) {
            throw "not a saved name at character $($name.At): $($name.Text)"
        }
        $state.Pos += 2
        $top[$name.Text] = Read-Value
    }
    return $top
}

# Reads a saved-variables file. The file is opened for reading only.
function Read-ZSavedFile([string]$Path) {
    $text = [System.IO.File]::ReadAllText($Path)
    return Read-ZSavedText $text
}

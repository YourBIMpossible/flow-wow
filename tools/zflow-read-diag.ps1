<#
.SYNOPSIS
  Prints what Z-Flow's diagnostics saved (F-H), from the account's ZFlow.lua
  saved-variables file. tools/read-diag.ps1 reads Flow's file; this reads
  ZFlowDB.

  For the file: its path and write time, the start count, how many
  snapshots were taken and how many are kept, and the client build the
  names table is of. Then, for each character seen in the kept snapshots:
  the starts it was seen in, the snapshot reasons, the recorded errors, the
  kernel phase, and the shape probes that failed. Then the saved layout.

  It prints on this machine only. It never copies or changes the file, and
  it prints no money, bag or position value: the reads of a snapshot are
  not printed at all, and no value of a probe that answered.

.USAGE
  powershell -ExecutionPolicy Bypass -File tools\zflow-read-diag.ps1 [-File path]
      [-WowDir path] [-Account name] [-MaxErrors 20]

  -File       the ZFlow.lua to read. Without it the file is looked for under
              -WowDir (or FLOW_WOW_DIR, or the usual folders) for -Account
              (or FLOW_WOW_ACCOUNT, or the account written last).
  -MaxErrors  how many recorded errors to print for a character.
  Exit code 0 = printed, 1 = no file or no diagnostics in it, 2 = the file
  is not readable as saved data.
  Fixtures: tools\fixtures\zflow-read-diag\run.ps1.
#>
param(
    [string]$File,
    [string]$WowDir,
    [string]$Account,
    [int]$MaxErrors = 20
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'zflow-saved.ps1')

if (-not $File) {
    . (Join-Path $PSScriptRoot 'Common.ps1')
    if (-not $WowDir) { $WowDir = Find-WowDir }
    if (-not $WowDir) { Write-Output 'zflow-read-diag: no game folder found. Pass -File or -WowDir, or set FLOW_WOW_DIR.'; exit 1 }
    if (-not $Account) { $Account = $env:FLOW_WOW_ACCOUNT }
    if (-not $Account) {
        $newest = Get-ChildItem (Join-Path $WowDir 'WTF\Account\*\SavedVariables\ZFlow.lua') -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($newest) { $Account = $newest.Directory.Parent.Name }
    }
    if (-not $Account) { Write-Output "zflow-read-diag: no ZFlow.lua under $WowDir yet. Reload in game first, or pass -Account."; exit 1 }
    $File = Join-Path $WowDir "WTF\Account\$Account\SavedVariables\ZFlow.lua"
}
if (-not (Test-Path -LiteralPath $File -PathType Leaf)) {
    Write-Output "zflow-read-diag: no saved data at $File"
    exit 1
}
$info = Get-Item -LiteralPath $File
Write-Output ("File: {0}" -f $info.FullName)
Write-Output ("Written: {0} ({1} bytes)" -f $info.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'), $info.Length)

try {
    $top = Read-ZSavedFile $info.FullName
} catch {
    Write-Output ("zflow-read-diag: not readable as saved data: {0}" -f $_.Exception.Message)
    exit 2
}
$db = $top['ZFlowDB']
if (-not (Test-ZSavedTable $db)) { Write-Output 'zflow-read-diag: no ZFlowDB in the file.'; exit 1 }
$diag = Get-ZSaved $db 'diag'
if (-not (Test-ZSavedTable $diag)) { Write-Output 'No diagnostics saved yet (log in and reload first).'; exit 1 }

function Format-Plain($v) {
    if ($null -eq $v) { return 'unknown' }
    if ($v -is [bool]) { if ($v) { return 'true' } else { return 'false' } }
    if ($v -is [double]) {
        if ($v -eq [math]::Floor($v) -and [math]::Abs($v) -lt 1e15) { return ([long]$v).ToString() }
        return $v.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }
    return ([string]$v -replace '\s+', ' ')
}

$snaps = Get-ZSavedList (Get-ZSaved $diag 'snaps')
Write-Output ("Starts: {0}" -f (Format-Plain (Get-ZSaved $diag 'starts')))
Write-Output ("Snapshots: {0} taken, {1} kept" -f (Format-Plain (Get-ZSaved $diag 'count')), $snaps.Count)
$build = Get-ZSaved $diag 'names' 'build'
if ($null -ne $build) { Write-Output ("Names table: build {0}" -f (Format-Plain $build)) }
else { Write-Output 'Names table: not saved' }
$inSnap = 0
foreach ($s in $snaps) { if (Test-ZSavedTable (Get-ZSaved $s 'names')) { $inSnap++ } }
if ($inSnap -gt 0) { Write-Output ("!! {0} kept snapshot(s) still hold their own names table (written by a build before the cap)" -f $inSnap) }

# The kept snapshots by character, in the order first seen.
$order = New-Object System.Collections.ArrayList
$by = @{}
foreach ($s in $snaps) {
    $name = Get-ZSaved $s 'timing' 'character'
    $realm = Get-ZSaved $s 'timing' 'realm'
    $who = 'unknown character'
    if ($name -is [string] -and $name -ne '') {
        $who = $name
        if ($realm -is [string] -and $realm -ne '') { $who = "$name - $realm" }
    }
    if (-not $by.ContainsKey($who)) { $by[$who] = New-Object System.Collections.ArrayList; [void]$order.Add($who) }
    [void]$by[$who].Add($s)
}
if ($order.Count -eq 0) { Write-Output ''; Write-Output 'No snapshot is kept.' }

foreach ($who in $order) {
    $list = $by[$who]
    Write-Output ''
    Write-Output ("=== {0} ===" -f $who)

    $starts = New-Object System.Collections.ArrayList
    foreach ($s in $list) {
        $n = Format-Plain (Get-ZSaved $s 'timing' 'start')
        if (-not $starts.Contains($n)) { [void]$starts.Add($n) }
    }
    Write-Output ("Starts seen in the kept snapshots: {0} ({1})" -f $starts.Count, ($starts -join ', '))

    $reasons = @($list | ForEach-Object { Format-Plain (Get-ZSaved $_ 'why') })
    Write-Output ("Snapshot reasons ({0}): {1}" -f $reasons.Count, ($reasons -join ', '))

    # Errors: each start keeps one list, written with every snapshot of that
    # start, so the newest snapshot of each start has all of it.
    $newestOf = @{}
    $startOrder = New-Object System.Collections.ArrayList
    foreach ($s in $list) {
        $n = Format-Plain (Get-ZSaved $s 'timing' 'start')
        if (-not $newestOf.ContainsKey($n)) { [void]$startOrder.Add($n) }
        $newestOf[$n] = $s
    }
    $errors = New-Object System.Collections.ArrayList
    foreach ($n in $startOrder) {
        foreach ($e in (Get-ZSavedList (Get-ZSaved $newestOf[$n] 'timing' 'errors'))) {
            [void]$errors.Add(@{ Start = $n; Row = $e })
        }
    }
    Write-Output ("Recorded errors: {0}" -f $errors.Count)
    $shown = 0
    foreach ($e in $errors) {
        if ($shown -ge $MaxErrors) { Write-Output ("  ... {0} more not printed (-MaxErrors)" -f ($errors.Count - $shown)); break }
        $mark = '  '
        if ((Get-ZSaved $e.Row 'ours') -eq $true) { $mark = '!!' }
        Write-Output ("{0} start {1}, phase {2}, x{3}: {4}" -f $mark, $e.Start, (Format-Plain (Get-ZSaved $e.Row 'phase')),
            (Format-Plain (Get-ZSaved $e.Row 'count')), (Format-Plain (Get-ZSaved $e.Row 'text')))
        $shown++
    }

    $latest = $list[$list.Count - 1]
    $kernel = Get-ZSaved $latest 'kernel'
    $line = "Kernel phase: {0}" -f (Format-Plain (Get-ZSaved $kernel 'phase'))
    if ((Get-ZSaved $kernel 'paused') -eq $true) { $line += (" (paused: {0})" -f (Format-Plain (Get-ZSaved $kernel 'pauseText'))) }
    Write-Output ($line + (" [newest snapshot: {0}]" -f (Format-Plain (Get-ZSaved $latest 'why'))))
    $problems = Get-ZSavedList (Get-ZSaved $kernel 'problems')
    Write-Output ("Kernel problems: {0}" -f $problems.Count)
    foreach ($p in $problems) {
        Write-Output ("   {0} / {1}, x{2}: {3}" -f (Format-Plain (Get-ZSaved $p 'kind')), (Format-Plain (Get-ZSaved $p 'owner')),
            (Format-Plain (Get-ZSaved $p 'count')), (Format-Plain (Get-ZSaved $p 'text')))
    }

    # Failed probes: only the name and what the client said. A probe that
    # answered is not printed, so no game value is.
    $shapes = Get-ZSaved $latest 'shapes'
    $failed = @()
    if (Test-ZSavedTable $shapes) {
        foreach ($key in ($shapes.Keys | Sort-Object { [string]$_ })) {
            $row = Get-ZSaved $shapes $key
            if ((Get-ZSaved $row 'ok') -eq $false) {
                $said = Get-ZSaved $row 'values' 'v1'
                if ($said -isnot [string]) { $said = 'no text' }
                $failed += ("   {0}: {1}" -f $key, (Format-Plain $said))
            }
        }
    }
    Write-Output ("Failed shape probes: {0}" -f $failed.Count)
    $failed | ForEach-Object { Write-Output $_ }
}

function Write-Layout($value, [string]$path) {
    if (Test-ZSavedTable $value) {
        $n = Get-ZSavedLength $value
        $flat = ($n -gt 0 -and $n -eq $value.Keys.Count)
        if ($flat) { foreach ($x in (Get-ZSavedList $value)) { if (Test-ZSavedTable $x) { $flat = $false } } }
        if ($flat) {
            $items = Get-ZSavedList $value
            Write-Output ("   {0} = {1}" -f $path, (($items | ForEach-Object { Format-Plain $_ }) -join ', '))
            return
        }
        foreach ($key in ($value.Keys | Sort-Object { [string]$_ })) {
            $child = [string]$key
            if ($path -ne '') { $child = "$path.$key" }
            Write-Layout (Get-ZSaved $value $key) $child
        }
        return
    }
    Write-Output ("   {0} = {1}" -f $path, (Format-Plain $value))
}

# The window kit's login probe (UI/KitProbe.lua): per row of the parts list
# (ZFlow/UI/Kit/Parts.lua, read as text for each row's kind and name), what
# the client said. Names and answers only; no game value.
Write-Output ''
Write-Output '=== Kit probe ==='
$probeRows = Get-ZSaved $diag 'kitProbe' 'rows'
if (Test-ZSavedTable $probeRows) {
    Write-Output ("   asked at uptime {0}, client {1}" -f (Format-Plain (Get-ZSaved $diag 'kitProbe' 'at')), (Format-Plain (Get-ZSaved $diag 'kitProbe' 'interface')))
    $partInfo = @{}
    $partOrder = New-Object System.Collections.ArrayList
    $partsFile = Join-Path $PSScriptRoot '..\ZFlow\UI\Kit\Parts.lua'
    if (Test-Path -LiteralPath $partsFile -PathType Leaf) {
        foreach ($line in (Get-Content -LiteralPath $partsFile)) {
            if ($line -match '^\s*\{ id = "([^"]+)", kind = "([^"]+)", name = "([^"]+)"') {
                $partInfo[$Matches[1]] = @{ Kind = $Matches[2]; Name = ($Matches[3] -replace '\\\\', '\') }
                [void]$partOrder.Add($Matches[1])
            }
        }
    }
    foreach ($key in ($probeRows.Keys | Sort-Object { [string]$_ })) {
        if ($key -ne 'EJ_LOADED' -and -not $partInfo.ContainsKey([string]$key)) { [void]$partOrder.Add([string]$key) }
    }
    $works = 0; $missing = 0; $unsure = 0; $unknown = 0
    foreach ($id in $partOrder) {
        $said = Get-ZSaved $probeRows $id
        $kind = '?'; $name = '?'
        if ($partInfo.ContainsKey($id)) { $kind = $partInfo[$id].Kind; $name = $partInfo[$id].Name }
        if ($said -isnot [string]) { $said = 'not asked' }
        if ($said -eq 'not asked') { $unknown++ }
        elseif ($said -eq 'works' -or $said.StartsWith('works ')) { $works++ }
        elseif ($said -eq 'made, not confirmed') { $unsure++ }
        else { $missing++ }
        Write-Output ("   {0}  {1}  {2}: {3}" -f $id, $kind, $name, (Format-Plain $said))
    }
    Write-Output ("   Encounter Journal add-on loaded: {0}" -f (Format-Plain (Get-ZSaved $probeRows 'EJ_LOADED')))
    Write-Output ("   works {0}, missing {1}, not confirmed {2}, not asked {3}" -f $works, $missing, $unsure, $unknown)
} else { Write-Output '   none saved (log in once out of combat, then reload or log out)' }

# What each kit window drew, part by part (lead section 319): "first" is the
# game's own template, "fallback" the kit's plain form.
Write-Output ''
Write-Output '=== Kit parts drawn ==='
$kitDrawn = Get-ZSaved $diag 'kitDrawn'
if ((Test-ZSavedTable $kitDrawn) -and $kitDrawn.Keys.Count -gt 0) {
    foreach ($win in ($kitDrawn.Keys | Sort-Object { [string]$_ })) {
        $parts = Get-ZSaved $kitDrawn $win
        if (-not (Test-ZSavedTable $parts)) { continue }
        $own = @(); $plain = @()
        foreach ($part in ($parts.Keys | Sort-Object { [string]$_ })) {
            if ((Get-ZSaved $parts $part) -eq 'first') { $own += [string]$part } else { $plain += [string]$part }
        }
        Write-Output ("   {0}: game's own: {1}; plain fallback: {2}" -f (Format-Plain $win), (Format-Plain ($own -join ', ')), (Format-Plain ($plain -join ', ')))
    }
} else { Write-Output '   none saved (no kit window was opened)' }

# The sell list's first grey item and the rule applied to it (lead section
# 340; ZFlow/UI/SellList.lua saves diag.sellGrey at each listing).
Write-Output ''
Write-Output '=== Sell list: first grey item ==='
$sellGrey = Get-ZSaved $diag 'sellGrey'
if (Test-ZSavedTable $sellGrey) {
    $greyItem = Get-ZSaved $sellGrey 'item'
    $greyWhy = Get-ZSaved $sellGrey 'why'
    if ($null -eq $greyItem) { $greyItem = '(none)' }
    $greyLine = "   {0}: {1}" -f (Format-Plain $greyItem), (Format-Plain (Get-ZSaved $sellGrey 'rule'))
    if ($null -ne $greyWhy) { $greyLine += (" ({0})" -f (Format-Plain $greyWhy)) }
    Write-Output $greyLine
    Write-Output ("   listing: {0}" -f (Format-Plain (Get-ZSaved $sellGrey 'counts')))
} else { Write-Output '   none saved (no merchant window was opened)' }

Write-Output ''
Write-Output '=== Layout (saved for the account) ==='
$layout = Get-ZSaved $db 'layout'
if ((Test-ZSavedTable $layout) -and $layout.Keys.Count -gt 0) { Write-Layout $layout '' }
else { Write-Output '   none saved' }
exit 0

<#
.SYNOPSIS
  Fixture check for tools/offline/zflow-sanitize.lua (Lead section 188).
  Every name in these files is made up.

  test.lua    the engine on made-up captures: every kind of name replaced,
              the same name the same made-up one, free text replaced, the
              ZFlow capture (capture/ZFlow.lua and capture/ZFlowChar.lua in
              one run) left with no made-up real name, unknown fields, wrong
              types, unknown globals and text that is not saved data refused.
  The command line, on copies in a new temp folder:
    written     both files of the capture: exit 0, both outputs written, no
                made-up real name in either, the captures the same bytes
    exists      an <out> that exists: exit 2, the file not touched
    same        an <out> that is a capture: exit 2
    refused     a capture with a field the schema does not know: exit 1,
                nothing written, the value not printed
    broken      a file cut off part way: exit 2, nothing written
    odd         three arguments: exit 2
    charOnly    the character file alone: exit 0, no made-up real name in
                any spelling
    allRefusals --all-refusals on a capture with two refusals: exit 1, two
                refuse lines, nothing written, no value printed; on the
                capture itself: exit 0

.USAGE
  powershell -ExecutionPolicy Bypass -File tools\fixtures\zflow-sanitize\run.ps1

  Exit code 0 = every case as expected, 1 = not so, or no Lua 5.1 found.
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\zflow-common.ps1')
$lua = Get-ZFlowLua 'zflow-sanitize fixtures'
$tool = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\offline\zflow-sanitize.lua')).Path
$bad = 0

& $lua (Join-Path $PSScriptRoot 'test.lua')
if ($LASTEXITCODE -ne 0) { $bad++ }

$names = @('Aldwynne', 'Mossvale', 'Brannoch', 'Cinder-Reach', 'Kestrelle', 'Fenwick')
# Every spelling: lower case, spaces, hyphens and punctuation removed.
function Get-Folded([string]$s) { return ($s.ToLowerInvariant() -replace '[\s\p{P}\p{S}\p{Cc}]', '') }
$work = Join-Path ([System.IO.Path]::GetTempPath()) ('zflow-sanitize-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $account = Join-Path $work 'ZFlow.lua'
    $char = Join-Path $work 'ZFlowChar.lua'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'capture\ZFlow.lua') -Destination $account
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'capture\ZFlowChar.lua') -Destination $char

    function Invoke-Tool([string[]]$argv) {
        # The tool's refusals go to stderr; under 'Stop' that would end the run.
        $ErrorActionPreference = 'Continue'
        $out = (& $lua $tool @argv 2>&1 | ForEach-Object { "$_" } | Out-String)
        return [pscustomobject]@{ Out = $out; Code = $LASTEXITCODE }
    }
    function Report([string]$name, $r, [int]$code, [string[]]$why) {
        if ($r.Code -ne $code) { $why += ("wanted exit {0}" -f $code) }
        if ($why.Count -eq 0) { Write-Output ("PASS cli {0} (exit {1})" -f $name, $r.Code); return }
        Write-Output ("FAIL cli {0}: {1} (exit {2})" -f $name, ($why -join '; '), $r.Code)
        Write-Output ($r.Out.TrimEnd())
        $script:bad++
    }

    # written
    $before = @((Get-FileHash -LiteralPath $account).Hash, (Get-FileHash -LiteralPath $char).Hash)
    $outA = Join-Path $work 'out-ZFlow.lua'
    $outC = Join-Path $work 'out-ZFlowChar.lua'
    $r = Invoke-Tool @($account, $outA, $char, $outC)
    $why = @()
    foreach ($o in @($outA, $outC)) {
        if (-not (Test-Path -LiteralPath $o)) { $why += ("not written: {0}" -f (Split-Path $o -Leaf)); continue }
        $text = [System.IO.File]::ReadAllText($o)
        $folded = Get-Folded $text
        foreach ($n in $names) { if ($folded.Contains((Get-Folded $n))) { $why += ("a real name left in {0}" -f (Split-Path $o -Leaf)) } }
        if (-not $text.Contains('Character')) { $why += ("no made-up name in {0}" -f (Split-Path $o -Leaf)) }
    }
    $after = @((Get-FileHash -LiteralPath $account).Hash, (Get-FileHash -LiteralPath $char).Hash)
    if (($before -join ',') -ne ($after -join ',')) { $why += 'a capture changed' }
    Report 'written' $r 0 $why

    # charOnly: the character file alone
    $outCo = Join-Path $work 'out-charOnly.lua'
    $r = Invoke-Tool @($char, $outCo)
    $why = @()
    if (-not (Test-Path -LiteralPath $outCo)) { $why += 'not written' }
    else {
        $folded = Get-Folded ([System.IO.File]::ReadAllText($outCo))
        foreach ($n in $names) { if ($folded.Contains((Get-Folded $n))) { $why += 'a real name left' } }
    }
    Report 'charOnly' $r 0 $why

    # exists
    $stampHash = (Get-FileHash -LiteralPath $outA).Hash
    $r = Invoke-Tool @($account, $outA)
    $why = @()
    if ((Get-FileHash -LiteralPath $outA).Hash -ne $stampHash) { $why += 'the existing out was overwritten' }
    Report 'exists' $r 2 $why

    # same
    $r = Invoke-Tool @($account, $account)
    $why = @()
    if ((Get-FileHash -LiteralPath $account).Hash -ne $before[0]) { $why += 'the capture changed' }
    Report 'same' $r 2 $why

    # refused
    $odd = Join-Path $work 'odd.lua'
    $text = [System.IO.File]::ReadAllText($account).Replace('["schema"] = 1,', ('["schema"] = 1,' + "`n" + '["guildRoster"] = { "Fenwick", },'))
    [System.IO.File]::WriteAllText($odd, $text)
    $outR = Join-Path $work 'out-odd.lua'
    $r = Invoke-Tool @($odd, $outR)
    $why = @()
    if (Test-Path -LiteralPath $outR) { $why += 'written' }
    if ($r.Out.Contains('Fenwick')) { $why += 'the value printed' }
    Report 'refused' $r 1 $why

    # allRefusals
    $odd2 = Join-Path $work 'odd2.lua'
    [System.IO.File]::WriteAllText($odd2, $text + "`nOtherAddonDB = { [`"owner`"] = `"Fenwick`", }`n")
    $before2 = @(Get-ChildItem -LiteralPath $work).Count
    $r = Invoke-Tool @('--all-refusals', $odd2, $char)
    $why = @()
    $lines = @($r.Out -split "`r?`n" | Where-Object { $_ -like 'zflow-sanitize: refuse: *' })
    if ($lines.Count -ne 2) { $why += ("refuse lines: {0}" -f $lines.Count) }
    if ($r.Out.Contains('Fenwick')) { $why += 'a value printed' }
    if (@(Get-ChildItem -LiteralPath $work).Count -ne $before2) { $why += 'a file written' }
    Report 'allRefusals' $r 1 $why
    $r = Invoke-Tool @('--all-refusals', $account, $char)
    Report 'allRefusals none' $r 0 @()

    # broken
    $cut = Join-Path $work 'cut.lua'
    $whole = [System.IO.File]::ReadAllText($account)
    [System.IO.File]::WriteAllText($cut, $whole.Substring(0, [int]($whole.Length / 2)))
    $outB = Join-Path $work 'out-cut.lua'
    $r = Invoke-Tool @($cut, $outB)
    $why = @()
    if (Test-Path -LiteralPath $outB) { $why += 'written' }
    Report 'broken' $r 2 $why

    # odd
    $r = Invoke-Tool @($account, (Join-Path $work 'x.lua'), $char)
    Report 'odd' $r 2 @()
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force
}

if ($bad -eq 0) { Write-Output 'All zflow-sanitize cases passed.'; exit 0 }
Write-Output ("{0} zflow-sanitize check(s) failed." -f $bad)
exit 1

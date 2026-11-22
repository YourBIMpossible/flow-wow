<#
.SYNOPSIS
  Fixture check for tools/zflow-coverage.ps1 (F-B). Runs the tool on each case
  folder below (each holds its own ZFlow/ tree, and optionally a
  not-loaded.txt passed as -NotLoaded) in Windows PowerShell and checks the
  exit code, and for a failing case that the rule's tag is in the output.

.USAGE
  powershell -ExecutionPolicy Bypass -File tools\fixtures\zflow-coverage\run.ps1

  Exit code 0 = every case as expected, 1 = not so.
#>
$ErrorActionPreference = 'Stop'
$tool = Join-Path $PSScriptRoot '..\..\zflow-coverage.ps1'
$cases = @(
    @{ Name = 'pass';          Exit = 0 },
    @{ Name = 'unlisted-fail'; Exit = 1; Tag = 'UNLISTED' },
    @{ Name = 'missing-fail';  Exit = 1; Tag = 'MISSING' },
    @{ Name = 'case-fail';     Exit = 1; Tag = 'MISSING' },
    @{ Name = 'notloaded-stale-fail';  Exit = 1; Tag = 'NOTLOADED' },
    @{ Name = 'notloaded-listed-fail'; Exit = 1; Tag = 'NOTLOADED' },
    @{ Name = 'badlist';               Exit = 2; List = 'no-such-list.txt'; Has = 'no not-loaded list' }
)
$bad = 0
foreach ($c in $cases) {
    $dir = Join-Path $PSScriptRoot $c.Name
    if (-not (Test-Path -LiteralPath $tool)) {
        Write-Output ("FAIL {0}: tools/zflow-coverage.ps1 does not exist" -f $c.Name)
        $bad++
        continue
    }
    $toolArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $tool, '-Root', $dir)
    $list = Join-Path $dir 'not-loaded.txt'
    if ($c.List) { $toolArgs += @('-NotLoaded', (Join-Path $dir $c.List)) }
    elseif (Test-Path -LiteralPath $list) { $toolArgs += @('-NotLoaded', $list) }
    $out = (& powershell.exe @toolArgs 2>&1 | Out-String)
    $code = $LASTEXITCODE
    $ok = ($code -eq $c.Exit)
    if ($ok -and $c.Tag) { $ok = ($out -match (': ' + $c.Tag + ': ')) }
    if ($ok -and $c.Has) { $ok = ($out.IndexOf($c.Has, [StringComparison]::Ordinal) -ge 0) }
    if ($ok) {
        Write-Output ("PASS {0} (exit {1})" -f $c.Name, $code)
    } else {
        Write-Output ("FAIL {0}: exit {1}, wanted {2}{3}" -f $c.Name, $code, $c.Exit, $(if ($c.Tag) { " with " + $c.Tag } else { "" }))
        Write-Output ($out.TrimEnd())
        $bad++
    }
}
Write-Output ("zflow-coverage fixtures: {0} case(s), {1} not as expected" -f $cases.Count, $bad)
if ($bad -gt 0) { exit 1 }
exit 0

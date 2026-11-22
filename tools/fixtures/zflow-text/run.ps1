<#
.SYNOPSIS
  Fixture check for tools/zflow-text.ps1 (F-A). Runs the tool on each case
  folder below (each holds its own ZFlow/ tree) in Windows PowerShell and
  checks the exit code, and for a failing case that the rule's tag is in
  the output.

.USAGE
  powershell -ExecutionPolicy Bypass -File tools\fixtures\zflow-text\run.ps1

  Exit code 0 = every case as expected, 1 = not so.
#>
$ErrorActionPreference = 'Stop'
$tool = Join-Path $PSScriptRoot '..\..\zflow-text.ps1'
$cases = @(
    @{ Name = 'f085-pass';        Exit = 0 },
    @{ Name = 'f085-fail';        Exit = 1; Tag = 'F085' },
    @{ Name = 'price-pass';       Exit = 0 },
    @{ Name = 'price-fail';       Exit = 1; Tag = 'PRICE' },
    @{ Name = 'price-build-fail'; Exit = 1; Tag = 'PRICE' },
    @{ Name = 'print-pass';       Exit = 0 },
    @{ Name = 'print-fail';       Exit = 1; Tag = 'PRINT' }
)
$bad = 0
foreach ($c in $cases) {
    $dir = Join-Path $PSScriptRoot $c.Name
    if (-not (Test-Path -LiteralPath $tool)) {
        Write-Output ("FAIL {0}: tools/zflow-text.ps1 does not exist" -f $c.Name)
        $bad++
        continue
    }
    $out = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tool -Root $dir 2>&1 | Out-String)
    $code = $LASTEXITCODE
    $ok = ($code -eq $c.Exit)
    if ($ok -and $c.Tag) { $ok = ($out -match (': ' + $c.Tag + ': ')) }
    if ($ok) {
        Write-Output ("PASS {0} (exit {1})" -f $c.Name, $code)
    } else {
        Write-Output ("FAIL {0}: exit {1}, wanted {2}{3}" -f $c.Name, $code, $c.Exit, $(if ($c.Tag) { " with " + $c.Tag } else { "" }))
        Write-Output ($out.TrimEnd())
        $bad++
    }
}
Write-Output ("zflow-text fixtures: {0} case(s), {1} not as expected" -f $cases.Count, $bad)
if ($bad -gt 0) { exit 1 }
exit 0

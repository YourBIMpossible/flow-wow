<#
.SYNOPSIS
  Runs Z-Flow's tests outside the game with Lua 5.1 and the fake client
  (ZFlow/Core/ClientFake.lua). Loads every file in ZFlow/manifest.lua, then
  every ZFlow/Tests/**/*.lua. Each test is PASS, FAIL (a check did not hold,
  or the test made no check) or ERROR. tools/offline/zflow-run.lua's header
  has the exact rules. A PASS here is not a test in the game.

.USAGE
  powershell -ExecutionPolicy Bypass -File tools\zflow-tests.ps1 [-Root path] [-Filter text] [-Verbose]

  Exit code 0 = every file loaded, at least one test ran, no FAIL or ERROR;
  1 = not so; 2 = the runner could not run or did not finish.
#>
[CmdletBinding()]
param(
    [string]$Root,
    [string]$Filter
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'zflow-common.ps1')
$repo = Get-ZFlowRoot 'zflow-tests' $Root
$lua = Get-ZFlowLua 'zflow-tests'
Write-Output "zflow-tests: $lua; add-on $repo"

$list = New-ZFlowFileList $repo -TestsOnly
try {
    $luaArgs = @((Join-Path $PSScriptRoot 'offline/zflow-run.lua'), $repo, $list)
    if ($PSBoundParameters.ContainsKey('Verbose')) { $luaArgs += '--verbose' }
    if ($Filter) { $luaArgs += @('--filter', $Filter) }
    # The driver's last line must be "zflow: done, exit <n>", with <n> its exit
    # code: anything else (a crash, an early exit) is a broken run, never a pass.
    $last = ''
    & $lua @luaArgs 2>&1 | ForEach-Object { $line = "$_"; Write-Output $line; if ($line -ne '') { $last = $line } }
    $code = $LASTEXITCODE
} finally {
    Remove-Item -LiteralPath $list -ErrorAction SilentlyContinue
}
if ($last -notmatch '^zflow: done, exit (\d+)$' -or [int]$Matches[1] -ne $code) {
    Write-Output "zflow-tests: the driver didn't finish (exit $code, last line '$last'): the run is broken, not passed"
    exit 2
}
exit $code

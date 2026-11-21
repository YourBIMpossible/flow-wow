<#
.SYNOPSIS
  Runs Flow's registered tests outside the game, with Lua 5.1 and the fixtures
  of tools/offline/stubs.lua. Each test is PASS, FAIL, ERROR, or SKIP (it
  touched something only the game client has; the first such name is shown).
  A PASS here is Flow's own Lua on made-up inputs: not a gameplay test, and not
  a substitute for /flow test in the game.

.USAGE
  powershell -ExecutionPolicy Bypass -File tools\run-tests.ps1 [-Filter text] [-Verbose] [-ListModules] [-NoKnown]
  pwsh -File tools/run-tests.ps1                  # the CI job, on Linux

  Lua 5.1 is found in this order: $env:FLOW_LUA, then lua5.1 / lua51 on PATH,
  then %USERPROFILE%\tools\lua51\lua5.1.exe. (Lua 5.1 only: the game runs 5.1.)
  Known failures on the base branch are listed in tools/offline/known-failures.txt;
  -NoKnown counts them like any other failure.

  Exit code 0 = no new FAIL or ERROR, 1 = some, 2 = the runner couldn't run.
#>
[CmdletBinding()]
param(
    [string]$Filter,
    [switch]$ListModules,
    [switch]$NoKnown
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Find-Lua {
    if ($env:FLOW_LUA) {
        if (Test-Path -LiteralPath $env:FLOW_LUA) { return $env:FLOW_LUA }
        throw "FLOW_LUA is set to '$($env:FLOW_LUA)', which doesn't exist"
    }
    foreach ($name in 'lua5.1', 'lua51') {
        $cmd = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) { return $cmd.Source }
    }
    if ($env:USERPROFILE) {
        $p = Join-Path $env:USERPROFILE 'tools\lua51\lua5.1.exe'
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

$lua = Find-Lua
if (-not $lua) {
    Write-Output "run-tests: no Lua 5.1 found (set FLOW_LUA, or put lua5.1 on PATH)"
    exit 2
}
$version = (& $lua -e 'io.write(_VERSION)' | Out-String).Trim()   # stdout only: -v writes to stderr
if ($version -notmatch 'Lua 5\.1') {
    Write-Output "run-tests: $lua is '$version', not Lua 5.1 (the game's Lua)"
    exit 2
}
Write-Output "run-tests: $version ($lua)"

$luaArgs = @((Join-Path $root 'tools/offline/run.lua'), $root)
if ($PSBoundParameters.ContainsKey('Verbose')) { $luaArgs += '--verbose' }
if ($ListModules) { $luaArgs += '--list-modules' }
if ($Filter) { $luaArgs += @('--filter', $Filter) }
if (-not $NoKnown) { $luaArgs += @('--known', (Join-Path $root 'tools/offline/known-failures.txt')) }

& $lua @luaArgs
exit $LASTEXITCODE

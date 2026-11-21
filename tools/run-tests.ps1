<#
.SYNOPSIS
  Runs Flow's registered tests outside the game, with Lua 5.1 and the fixtures
  of tools/offline/stubs.lua. Each test is PASS, FAIL, ERROR, SKIP (it
  touched something only the game client has; the first such name is shown),
  or SKIP-FAIL (a check failed before it touched the client: listed and counted,
  failing the run with -Strict). tools/offline/run.lua's header has the exact rules.
  A PASS here is Flow's own Lua on made-up inputs: not a gameplay test, and not
  a substitute for /flow test in the game.

.USAGE
  powershell -ExecutionPolicy Bypass -File tools\run-tests.ps1 [-Root path] [-Filter text] [-Verbose] [-ListModules] [-NoKnown] [-Known file] [-Strict]
  pwsh -File tools/run-tests.ps1                  # the CI job, on Linux

  -Root: the add-on checkout to test (default: the one this script is in). The
  runner (tools/offline/run.lua, stubs.lua) is always this script's own, so
  another worktree needs no tools/offline of its own.
  -Known: the known-failures list (default: <Root>/tools/offline/known-failures.txt
  if it exists, else none, so every failure counts).
  -Strict: a SKIP-FAIL (a check failed before the test touched the client)
  fails the run too; without it, SKIP-FAILs are listed and counted only.

  Lua 5.1 is found in this order: $env:FLOW_LUA, then lua5.1 / lua51 on PATH,
  then %USERPROFILE%\tools\lua51\lua5.1.exe. (Lua 5.1 only: the game runs 5.1.)
  Known failures on the base branch are listed in tools/offline/known-failures.txt;
  -NoKnown counts them like any other failure.

  Exit code 0 = every file loaded, no FAIL or ERROR (or SKIP-FAIL, with -Strict) outside the known
  list, every known name exists, at least one test ran; 1 = not so; 2 = the runner
  couldn't run or didn't finish (its last line "offline: done, exit <n>" missing).
#>
[CmdletBinding()]
param(
    [string]$Root,
    [string]$Filter,
    [string]$Known,
    [switch]$ListModules,
    [switch]$NoKnown,
    [switch]$Strict
)
$ErrorActionPreference = 'Stop'
$runner = (Resolve-Path (Join-Path $PSScriptRoot 'offline')).Path
if (-not $Root) { $Root = Join-Path $PSScriptRoot '..' }
if (-not (Test-Path -LiteralPath (Join-Path $Root 'Flow.toc'))) {
    Write-Output "run-tests: no Flow.toc under '$Root'"
    exit 2
}
$root = (Resolve-Path -LiteralPath $Root).Path

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

Write-Output "run-tests: add-on $root; runner $runner"

$luaArgs = @((Join-Path $runner 'run.lua'), $root)
if ($PSBoundParameters.ContainsKey('Verbose')) { $luaArgs += '--verbose' }
if ($ListModules) { $luaArgs += '--list-modules' }
if ($Filter) { $luaArgs += @('--filter', $Filter) }
if ($Strict) { $luaArgs += '--strict' }
if (-not $NoKnown) {
    if (-not $Known) {
        $default = Join-Path $root 'tools/offline/known-failures.txt'
        if (Test-Path -LiteralPath $default) { $Known = $default }
    }
    if ($Known) {
        if (-not (Test-Path -LiteralPath $Known)) { Write-Output "run-tests: no known-failures file '$Known'"; exit 2 }
        Write-Output "run-tests: known failures from $Known"
        $luaArgs += @('--known', $Known)
    } else { Write-Output "run-tests: no known-failures list in the add-on tree: every failure counts" }
}

# The driver's last line must be "offline: done, exit <n>", with <n> its exit code:
# anything else (a crash, an early exit) is a broken run, never a pass.
$last = ''
& $lua @luaArgs | ForEach-Object { Write-Output $_; if ($_ -ne '') { $last = $_ } }
$code = $LASTEXITCODE
if ($last -notmatch '^offline: done, exit (\d+)$' -or [int]$Matches[1] -ne $code) {
    Write-Output "run-tests: the driver didn't finish (exit $code, last line '$last'): the run is broken, not passed"
    exit 2
}
exit $code

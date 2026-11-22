<#
.SYNOPSIS
  Runs every Z-Flow check once (F-E) and says, per check, whether it passed:
  the six lead checks (lint, check-structure, run-tests, zflow-structure,
  zflow-toc -Check, zflow-tests) and zflow-text, zflow-coverage and
  zflow-settings-lint. Each check runs as its own Windows PowerShell process
  from -Root, with its whole output written to a log in -LogDir.

  One line per check, then a summary:
    PASS     <check>  exit 0
    FAIL     <check>  exit <n>        any exit code but 0
    NOT RUN  <check>  why             no Lua 5.1 / no luacheck / tools/<check>.ps1 missing

  A check that did not run is never a pass. lint needs luacheck; run-tests,
  zflow-structure, zflow-toc and zflow-tests need Lua 5.1. Both are found as
  the checks themselves find them: Lua via $env:FLOW_LUA, lua5.1 / lua51 on
  PATH, then %USERPROFILE%\tools\lua51\lua5.1.exe; luacheck via
  $env:FLOW_LUACHECK, luacheck on PATH, then
  %USERPROFILE%\tools\luacheck\luacheck.exe. -LuaPath / -LuacheckPath name
  them instead (and are passed on as FLOW_LUA / FLOW_LUACHECK); -NoLua runs
  as if neither were installed.

.USAGE
  powershell -ExecutionPolicy Bypass -File tools\zflow-check-all.ps1 [-Root path] [-LogDir folder]
      [-LuaPath file] [-LuacheckPath file] [-NoLua]

  -Root    the checkout to check (default: this one). The checks are its own tools/*.ps1.
  -LogDir  where the logs go: <n>-<check>.log per check, plus summary.txt
           (default: a new folder under %TEMP%, printed at the end).
  Exit code 0 = every check passed; 1 = a check failed; 2 = none failed but
  at least one did not run (not a pass), or the runner could not start.
#>
param(
    [string]$Root,
    [string]$LogDir,
    [string]$LuaPath,
    [string]$LuacheckPath,
    [switch]$NoLua
)
$ErrorActionPreference = 'Stop'

if (-not $Root) { $Root = Join-Path $PSScriptRoot '..' }
if (-not (Test-Path -LiteralPath (Join-Path $Root 'tools') -PathType Container)) {
    Write-Output "zflow-check-all: no tools folder under '$Root'"
    exit 2
}
$Root = (Resolve-Path -LiteralPath $Root).Path
if (-not $LogDir) {
    $LogDir = Join-Path ([IO.Path]::GetTempPath()) ('zflow-check-all-' + (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'))
}
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogDir = (Resolve-Path -LiteralPath $LogDir).Path

function Find-Tool([string]$given, [string]$envName, [string[]]$names, [string]$fallback) {
    if ($NoLua) { return $null }
    if ($given) { if (Test-Path -LiteralPath $given -PathType Leaf) { return (Resolve-Path -LiteralPath $given).Path } else { return $null } }
    $fromEnv = [Environment]::GetEnvironmentVariable($envName)
    if ($fromEnv -and (Test-Path -LiteralPath $fromEnv -PathType Leaf)) { return $fromEnv }
    foreach ($n in $names) {
        $cmd = Get-Command $n -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) { return $cmd.Source }
    }
    if ($env:USERPROFILE) {
        $p = Join-Path $env:USERPROFILE $fallback
        if (Test-Path -LiteralPath $p -PathType Leaf) { return $p }
    }
    return $null
}
$lua = Find-Tool $LuaPath 'FLOW_LUA' @('lua5.1', 'lua51') 'tools\lua51\lua5.1.exe'
$luacheck = Find-Tool $LuacheckPath 'FLOW_LUACHECK' @('luacheck') 'tools\luacheck\luacheck.exe'

# name, script, arguments, what it needs
$checks = @(
    @{ Name = 'lint';                Script = 'lint.ps1';                Args = @();                         Needs = 'luacheck' },
    @{ Name = 'check-structure';     Script = 'check-structure.ps1';     Args = @('-Root', $Root);           Needs = $null },
    @{ Name = 'run-tests';           Script = 'run-tests.ps1';           Args = @('-Root', $Root);           Needs = 'lua' },
    @{ Name = 'zflow-structure';     Script = 'zflow-structure.ps1';     Args = @('-Root', $Root);           Needs = 'lua' },
    @{ Name = 'zflow-toc';           Script = 'zflow-toc.ps1';           Args = @('-Root', $Root, '-Check'); Needs = 'lua' },
    @{ Name = 'zflow-tests';         Script = 'zflow-tests.ps1';         Args = @('-Root', $Root);           Needs = 'lua' },
    @{ Name = 'zflow-text';          Script = 'zflow-text.ps1';          Args = @('-Root', $Root);           Needs = $null },
    @{ Name = 'zflow-coverage';      Script = 'zflow-coverage.ps1';      Args = @('-Root', $Root);           Needs = $null },
    @{ Name = 'zflow-settings-lint'; Script = 'zflow-settings-lint.ps1'; Args = @('-Root', $Root);           Needs = $null }
)

$lines = New-Object System.Collections.Generic.List[string]
$passed = 0; $failed = 0; $notRun = 0
$saveLua = $env:FLOW_LUA; $saveLuacheck = $env:FLOW_LUACHECK
if ($lua) { $env:FLOW_LUA = $lua }
if ($luacheck) { $env:FLOW_LUACHECK = $luacheck }
Push-Location -LiteralPath $Root
try {
    for ($i = 0; $i -lt $checks.Count; $i++) {
        $c = $checks[$i]
        $script = Join-Path $Root ('tools\' + $c.Script)
        $log = Join-Path $LogDir ('{0}-{1}.log' -f ($i + 1), $c.Name)
        $why = $null
        if (-not (Test-Path -LiteralPath $script -PathType Leaf)) { $why = 'not run (tools/' + $c.Script + ' missing)' }
        elseif ($c.Needs -eq 'lua' -and -not $lua) { $why = 'not run (no Lua)' }
        elseif ($c.Needs -eq 'luacheck' -and -not $luacheck) { $why = 'not run (no luacheck)' }
        if ($why) {
            [IO.File]::WriteAllText($log, $why + "`r`n")
            $lines.Add(('NOT RUN  {0,-20} {1}' -f $c.Name, $why))
            $notRun++
            continue
        }
        $psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script) + $c.Args
        $out = (& powershell.exe @psArgs 2>&1 | Out-String)
        $code = $LASTEXITCODE
        [IO.File]::WriteAllText($log, ("> tools/{0} {1}`r`n{2}`r`nexit {3}`r`n" -f $c.Script, ($c.Args -join ' '), $out.TrimEnd(), $code))
        if ($code -eq 0) {
            $lines.Add(('PASS     {0,-20} exit 0' -f $c.Name)); $passed++
        } else {
            $lines.Add(('FAIL     {0,-20} exit {1}' -f $c.Name, $code)); $failed++
        }
    }
} finally {
    Pop-Location
    $env:FLOW_LUA = $saveLua; $env:FLOW_LUACHECK = $saveLuacheck
}

$verdict = 'all passed'
$exit = 0
if ($failed -gt 0) { $verdict = 'FAILED'; $exit = 1 }
elseif ($notRun -gt 0) { $verdict = 'INCOMPLETE: a check that did not run is not a pass'; $exit = 2 }
$summary = ('zflow-check-all: {0} check(s): {1} passed, {2} failed, {3} not run; {4}. Logs: {5}' -f $checks.Count, $passed, $failed, $notRun, $verdict, $LogDir)
$lines.Add($summary)
foreach ($l in $lines) { Write-Output $l }
[IO.File]::WriteAllLines((Join-Path $LogDir 'summary.txt'), [string[]]$lines)
exit $exit

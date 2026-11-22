<#
.SYNOPSIS
  Writes ZFlow/ZFlow.toc from ZFlow/manifest.lua (load order, interface,
  version) and ZFlow/Core/Identity.lua (title, saved-variable names). Files
  marked dev in the manifest and test files are never listed.

.USAGE
  powershell -ExecutionPolicy Bypass -File tools\zflow-toc.ps1 [-Root path] [-Check]

  -Check writes nothing: exit 1 when the TOC on disk is missing or out of date.
  Exit code 0 = written (or current), 1 = -Check found it stale, 2 = could not run.
#>
param(
    [string]$Root,
    [switch]$Check
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'zflow-common.ps1')
$repo = Get-ZFlowRoot 'zflow-toc' $Root
$lua = Get-ZFlowLua 'zflow-toc'
$luaArgs = @((Join-Path $PSScriptRoot 'offline/zflow-toc.lua'), $repo)
if ($Check) { $luaArgs += '--check' }
& $lua @luaArgs
exit $LASTEXITCODE

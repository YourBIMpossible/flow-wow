# fixture stub: stands in for tools/run-tests.ps1 and exits 0
param([string]$Root, [switch]$Check, [string[]]$Paths)
Write-Output "stub run-tests root=$Root check=$Check lua=$env:FLOW_LUA"
exit 0

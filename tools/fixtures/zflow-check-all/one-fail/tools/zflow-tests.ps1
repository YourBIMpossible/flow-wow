# fixture stub: stands in for tools/zflow-tests.ps1 and exits 0
param([string]$Root, [switch]$Check, [string[]]$Paths)
Write-Output "stub zflow-tests root=$Root check=$Check lua=$env:FLOW_LUA"
exit 0

# fixture stub: stands in for tools/zflow-structure.ps1 and exits 0
param([string]$Root, [switch]$Check, [string[]]$Paths)
Write-Output "stub zflow-structure root=$Root check=$Check lua=$env:FLOW_LUA"
exit 0

# fixture stub: stands in for tools/zflow-text.ps1 and exits 0
param([string]$Root, [switch]$Check, [string[]]$Paths)
Write-Output "stub zflow-text root=$Root check=$Check lua=$env:FLOW_LUA"
exit 0

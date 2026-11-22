# fixture stub: stands in for tools/check-structure.ps1 and exits 0
param([string]$Root, [switch]$Check, [string[]]$Paths)
Write-Output "stub check-structure root=$Root check=$Check lua=$env:FLOW_LUA"
exit 0

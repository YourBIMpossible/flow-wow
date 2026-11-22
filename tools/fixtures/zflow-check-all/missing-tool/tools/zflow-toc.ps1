# fixture stub: stands in for tools/zflow-toc.ps1 and exits 0
param([string]$Root, [switch]$Check, [string[]]$Paths)
Write-Output "stub zflow-toc root=$Root check=$Check lua=$env:FLOW_LUA"
exit 0

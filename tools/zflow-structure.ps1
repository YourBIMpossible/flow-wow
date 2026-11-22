<#
.SYNOPSIS
  Z-Flow structure check. Fails when:
    1. ZFlow/manifest.lua lists a file that does not exist (or differs in case);
    2. a .lua file under ZFlow/ (outside Tests/) is not in the manifest, or a
       test file is;
    3. an identity string ("ZFlow", "Z-Flow", "/zflow", "ZFLOW") is a string
       constant anywhere but ZFlow/Core/Identity.lua (Tests/ and manifest.lua
       excepted);
    4. a file other than ZFlow/Core/Client.lua reads or writes a global that
       is not plain Lua 5.1 (the client's API, print, _G ...);
    5. ZFlow/ZFlow.toc is not what tools/zflow-toc.ps1 would write.
  tools/offline/zflow-structure.lua's header has the exact rules.

.USAGE
  powershell -ExecutionPolicy Bypass -File tools\zflow-structure.ps1 [-Root path]

  Exit code 0 = clean, 1 = a problem above, 2 = could not run.
#>
param([string]$Root)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'zflow-common.ps1')
$repo = Get-ZFlowRoot 'zflow-structure' $Root
$lua = Get-ZFlowLua 'zflow-structure'

$list = New-ZFlowFileList $repo
try {
    & $lua (Join-Path $PSScriptRoot 'offline/zflow-structure.lua') $repo $list
    $structure = $LASTEXITCODE
} finally {
    Remove-Item -LiteralPath $list -ErrorAction SilentlyContinue
}
& $lua (Join-Path $PSScriptRoot 'offline/zflow-toc.lua') $repo '--check'
$toc = $LASTEXITCODE

if ($structure -ge 2 -or $toc -ge 2) { exit 2 }
if ($structure -ne 0 -or $toc -ne 0) {
    if ($structure -eq 0) { "ZFLOW STRUCTURE FAILED: the TOC is not current." }
    exit 1
}
exit 0

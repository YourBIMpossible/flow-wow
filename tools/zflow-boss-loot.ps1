<#
.SYNOPSIS
  Writes ZFlow/Nav/BossLootData.lua: which items each dungeon and raid boss
  can drop, as ids only, from a local AllTheThings checkout (MIT licence).
  The checkout is read, never copied or committed. Build time only; nothing
  here runs in the game.

.USAGE
  powershell -ExecutionPolicy Bypass -File tools\zflow-boss-loot.ps1 -Att <AllTheThings checkout>
      [-Out file] [-Build 1.60.1] [-Commit sha] [-Root path]

  -Att     the checkout; its ".contrib/.db/forever/dungeons & raids/*.lua" files are read
           (or, with -Files, exactly the files of that folder)
  -Files   a folder of instance files to read instead (the tests' fixture)
  -Out     the file to write (default ZFlow/Nav/BossLootData.lua)
  -Commit  the AllTheThings commit to record (default: read with git from -Att)
  Exit code 0 = written, 1 = a file could not be read, 2 = could not run.
#>
param(
    [string]$Att,
    [string]$Files,
    [string]$Out,
    [string]$Build = '1.60.1',
    [string]$Commit,
    [string]$Root
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'zflow-common.ps1')
$repo = Get-ZFlowRoot 'zflow-boss-loot' $Root
$lua = Get-ZFlowLua 'zflow-boss-loot'
if (-not $Files) {
    if (-not $Att) {
        Write-Output 'zflow-boss-loot: give -Att <AllTheThings checkout> or -Files <folder>'
        exit 2
    }
    $Files = Join-Path $Att '.contrib/.db/forever/dungeons & raids'
    if (-not $Commit) {
        $Commit = (& git -C $Att rev-parse HEAD 2>$null | Out-String).Trim()
    }
}
if (-not (Test-Path -LiteralPath $Files)) {
    Write-Output "zflow-boss-loot: no folder '$Files'"
    exit 2
}
if (-not $Commit) {
    Write-Output 'zflow-boss-loot: the AllTheThings commit is not known; give -Commit'
    exit 2
}
if (-not $Out) { $Out = Join-Path $repo 'ZFlow/Nav/BossLootData.lua' }
$list = [System.IO.Path]::GetTempFileName()
try {
    $paths = Get-ChildItem -LiteralPath $Files -Filter '*.lua' -File | Sort-Object Name | ForEach-Object { $_.FullName }
    [System.IO.File]::WriteAllLines($list, [string[]]$paths, (New-Object System.Text.UTF8Encoding($false)))
    & $lua (Join-Path $PSScriptRoot 'offline/zflow-boss-loot.lua') $Out $Commit $Build $list
    exit $LASTEXITCODE
} finally {
    Remove-Item -LiteralPath $list -ErrorAction SilentlyContinue
}

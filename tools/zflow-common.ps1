<#
  Shared by tools/zflow-tests.ps1, zflow-toc.ps1 and zflow-structure.ps1.
  Dot-source it. Lua 5.1 is found exactly as tools/run-tests.ps1 finds it:
  $env:FLOW_LUA, then lua5.1 / lua51 on PATH, then
  %USERPROFILE%\tools\lua51\lua5.1.exe.
#>

function Find-ZFlowLua {
    if ($env:FLOW_LUA) {
        if (Test-Path -LiteralPath $env:FLOW_LUA) { return $env:FLOW_LUA }
        throw "FLOW_LUA is set to '$($env:FLOW_LUA)', which doesn't exist"
    }
    foreach ($name in 'lua5.1', 'lua51') {
        $cmd = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) { return $cmd.Source }
    }
    if ($env:USERPROFILE) {
        $p = Join-Path $env:USERPROFILE 'tools\lua51\lua5.1.exe'
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

# Returns the Lua 5.1 path, or writes why not and exits 2.
function Get-ZFlowLua([string]$Tool) {
    $lua = Find-ZFlowLua
    if (-not $lua) {
        Write-Output "${Tool}: no Lua 5.1 found (set FLOW_LUA, or put lua5.1 on PATH)"
        exit 2
    }
    $version = (& $lua -e 'io.write(_VERSION)' | Out-String).Trim()
    if ($version -notmatch 'Lua 5\.1') {
        Write-Output "${Tool}: $lua is '$version', not Lua 5.1 (the game's Lua)"
        exit 2
    }
    return $lua
}

# The repo root to work on: -Root, or the checkout this script is in. Exits 2
# when it has no ZFlow/manifest.lua.
function Get-ZFlowRoot([string]$Tool, [string]$Root) {
    if (-not $Root) { $Root = Join-Path $PSScriptRoot '..' }
    if (-not (Test-Path -LiteralPath (Join-Path $Root 'ZFlow/manifest.lua'))) {
        Write-Output "${Tool}: no ZFlow/manifest.lua under '$Root'"
        exit 2
    }
    return (Resolve-Path -LiteralPath $Root).Path
}

# Writes the .lua files under ZFlow/ (all, or only Tests/) to a temporary
# list file, relative to ZFlow/ with forward slashes, sorted. Returns its path.
function New-ZFlowFileList([string]$RepoRoot, [switch]$TestsOnly) {
    $base = (Resolve-Path -LiteralPath (Join-Path $RepoRoot 'ZFlow')).Path
    $from = $base
    if ($TestsOnly) { $from = Join-Path $base 'Tests' }
    $rels = @()
    if (Test-Path -LiteralPath $from) {
        $rels = @(Get-ChildItem -LiteralPath $from -Recurse -File -Filter *.lua |
            ForEach-Object { $_.FullName.Substring($base.Length + 1).Replace('\', '/') })
    }
    [Array]::Sort($rels, [StringComparer]::Ordinal)
    $list = [IO.Path]::GetTempFileName()
    [IO.File]::WriteAllLines($list, [string[]]$rels)
    return $list
}

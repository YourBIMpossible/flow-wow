# Finds texture paths with single backslashes ("Interface\Icons\X"): in Lua
# "\I" silently becomes "I" and the texture is blank. Run before committing.
# (The pattern is a regex: \\ is one backslash. It used to be \[, which
# matched a literal "[" and so never found anything.)
$bad = Get-ChildItem -Path (Join-Path $PSScriptRoot '..') -Recurse -Filter *.lua |
    Select-String -Pattern '"Interface\\[A-Za-z]'
if ($bad) { $bad | ForEach-Object { "$($_.Path):$($_.LineNumber): $($_.Line.Trim())" }; exit 1 }
"texture paths OK"

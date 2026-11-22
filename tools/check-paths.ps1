# Finds texture paths with single backslashes ("Interface\Icons\X"): in Lua
# "\I" silently becomes "I" and the texture is blank. Run before committing.
# It finds a single backslash anywhere in a quoted string that starts with
# Interface, in double or single quotes: "Interface\\Icons\X" as well as
# "Interface\Icons\\X". Not found: a path put together from pieces
# ("Interface\\Icons" .. "\X"), and one that doesn't start with Interface.
# (The pattern is a regex: \\ is one backslash, \\\\ two. (?!\\) = not
# followed by another.)
$bad = Get-ChildItem -Path (Join-Path $PSScriptRoot '..') -Recurse -Filter *.lua |
    Select-String -Pattern '["'']Interface(?:\\\\[^"''\\]*)*\\(?!\\)'
if ($bad) { $bad | ForEach-Object { "$($_.Path):$($_.LineNumber): $($_.Line.Trim())" }; exit 1 }
"texture paths OK"

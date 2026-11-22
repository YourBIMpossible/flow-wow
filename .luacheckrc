-- luacheck config for Flow (WoW: Forever, Lua 5.1). Run: tools\lint.ps1
-- (from the add-on's root: the list below is read from a path under it).
-- What's flagged:
--   * reading a global that is not Lua 5.1's, not Flow's and not one of the
--     game's that tools/offline/client-globals.txt lists: a typo
--     (UnitLevle), a missing "ns." (Distance for ns.Distance), or a local
--     used before it's declared. A new game API gets one line in that list.
--   * setting ANY global Flow doesn't mean to (a missing "local")
--   * unused variables and values, shadowing, unreachable code
std = "lua51"
max_line_length = false
codes = true
exclude_files = { "dist/**", "tools/fixtures/**" }   -- release staging copies; check-tool fixtures (deliberately bad Lua)

ignore = {
    "143/[A-Z].*",   -- reading fields of WoW API tables (C_Map.Foo, string.bar...)
    "212",           -- unused argument (event handlers get more than they use)
    "213",           -- unused loop variable
    "542",           -- empty if branch
    "431", "432",    -- a nested function reusing an outer name (common, and harmless here)
}

-- The game's globals Flow reads: one name per line in
-- tools/offline/client-globals.txt, which the offline test runner reads too
-- (tools/offline/stubs.lua). "#" lines are comments; "_G:" lines are names
-- only ever looked up through _G, which luacheck doesn't follow.
do
    local list = "tools/offline/client-globals.txt"
    local fh = io.open(list, "r")
    if not fh then error("can't read " .. list .. ": run luacheck from the add-on's root (tools/lint.ps1 does)") end
    local names = {}
    for l in fh:lines() do
        l = l:gsub("\r$", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if l:match("^[%a_][%w_]*$") then names[#names + 1] = l end
    end
    fh:close()
    read_globals = names
end

-- Globals Flow sets on purpose (slash commands, key binding names, saved
-- variables) and Blizzard tables it adds its own entries to.
globals = {
    "FlowDB", "FlowCharDB",
    "SLASH_FLOW1", "SLASH_FLOW2", "SLASH_FLOWWAY1",
    "BINDING_HEADER_FLOW",
    "SlashCmdList", "StaticPopupDialogs", "UISpecialFrames",
    "Questie",   -- Modules/Setup.lua switches one of Questie's own options (its db.profile)
}

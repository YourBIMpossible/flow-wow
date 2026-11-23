local _, ns = ...
-- G54 help on the whole add-on loaded on a fake client (lead sections 226,
-- 236): every word any module registers on the slash command has its own
-- non-empty line of help; the help word lists them all, a page at a time;
-- help <word> prints that word's line; a word registered after login is
-- listed; a help entry that is not text is shown as missing, never an error.
-- Offline: the fake client, not the game. Made-up names only.
local tests = {}

local function boot()
    local c = ns.make.fakeClient({ env = {
        UnitName = function() return "Zarkon" end,
        GetRealmName = function() return "Stormrage" end,
        GetBuildInfo = function() return "1.16.1", "7777" end,
    } })
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFacing(0)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, {})
    c.setVersion("0.1.0")
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function said(c, rest)
    local before = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = before + 1, #c.printed do out[#out + 1] = c.printed[i] end
    return out
end

-- Every word that can run, a to z.
local function problemCount(addon)
    local n = 0
    for _, p in ipairs(addon.problems:list()) do n = n + (p.count or 1) end
    return n
end

local function wordsOf(addon)
    local words = {}
    for word, fn in pairs(addon.diag.commands) do
        if type(word) == "string" and type(fn) == "function" then words[#words + 1] = word end
    end
    table.sort(words)
    return words
end

-- The word a help line is for, or nil when the line is not a word's line.
local function wordOfLine(line)
    local head = ns.id.title .. ": " .. ns.id.slash .. " "
    if line:sub(1, #head) ~= head then return nil end
    return line:sub(#head + 1):match("^(%S+) %- ")
end

tests["help words: every registered word has a non-empty line of help"] = function(t)
    local _, addon = boot()
    local words = wordsOf(addon)
    t.ok(#words >= 10, "the whole add-on registered too few words: " .. #words)
    local missing = {}
    for _, word in ipairs(words) do
        local said = addon.diag.help[word]
        if type(said) ~= "string" or said:match("^%s*$") then missing[#missing + 1] = word end
    end
    t.eq(table.concat(missing, ", "), "", "words without help")
end

tests["help words: the pages list every word once, no page longer than the cap"] = function(t)
    local c, addon = boot()
    local cap = ns.Diag and ns.Diag.HELP_PAGE
    t.eq(type(cap), "number", "there is no page cap")
    if type(cap) ~= "number" then return end
    local words = wordsOf(addon)
    local seen, pages = {}, math.ceil(#words / cap)
    for p = 1, pages do
        local lines = said(c, p == 1 and "help" or ("help " .. p))
        local n = 0
        for i = 1, #lines do
            local word = wordOfLine(lines[i])
            if word then
                n = n + 1
                seen[word] = (seen[word] or 0) + 1
            end
        end
        t.ok(n <= cap, "page " .. p .. " has " .. n .. " words")
        if p < pages then
            t.ok(lines[#lines]:find(ns.id.slash .. " help " .. (p + 1), 1, true) ~= nil,
                "page " .. p .. " does not point at the next: " .. lines[#lines])
        end
    end
    for _, word in ipairs(words) do t.eq(seen[word], 1, word .. " is not listed once") end
end

tests["help words: help <word> prints that word's line only"] = function(t)
    local c, addon = boot()
    for _, word in ipairs(wordsOf(addon)) do
        local lines = said(c, "help " .. word:upper())
        t.eq(#lines, 1, word .. " is not one line")
        t.eq(wordOfLine(lines[1] or ""), word, "the line is not " .. word .. "'s: " .. tostring(lines[1]))
    end
    -- Lead section 362: rewritten. A word that is not known listed the
    -- first page; it is now searched for, and one line says nothing has it.
    local none = said(c, "help nosuchword")
    t.eq(#none, 1, "a text no help has is not one line")
    t.ok(none[1]:find('no help has "nosuchword"', 1, true) ~= nil, tostring(none[1]))
    t.ok(none[1]:find(ns.id.slash .. " help", 1, true) ~= nil, "it does not point at help")
end

tests["help words: a word registered after login is listed; non-text help is missing, no error"] = function(t)
    local c, addon = boot()
    c.advance(60, 20)
    addon.diag.commands.zzlate = function() end
    addon.diag.help.zzlate = { "not", "text" }
    local problems = problemCount(addon)
    local lines = said(c, "help zzlate")
    t.eq(lines, { ns.id.title .. ": " .. ns.id.slash .. " zzlate - " .. ns.Diag.NO_HELP })
    local found = false
    local p = 1
    while true do
        local page = said(c, p == 1 and "help" or ("help " .. p))
        for i = 1, #page do
            if wordOfLine(page[i]) == "zzlate" then found = true end
        end
        if found or not page[#page]:find(ns.id.slash .. " help " .. (p + 1), 1, true) then break end
        p = p + 1
    end
    t.ok(found, "the late word is not on any page")
    t.eq(problemCount(addon), problems, "help raised")
end

return tests

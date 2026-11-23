-- The help word of the slash command (G54): every word registered in the
-- one command table is listed, one line each, and a word that is not known
-- is answered with the line that points at help. No game client is involved.
local _, ns = ...

local function start()
    local c = ns.make.fakeClient()
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, d
end

-- What the slash command printed for rest, as a list of lines.
local function said(c, rest)
    local before = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = before + 1, #c.printed do out[#out + 1] = c.printed[i] end
    return out
end

-- How many of the lines are the line of this word: the slash command, the
-- word, then the dash that starts its description.
local function linesFor(lines, word)
    local n = 0
    local head = ns.id.title .. ": " .. ns.id.slash .. " " .. word .. " - "
    for i = 1, #lines do
        if lines[i]:sub(1, #head) == head then n = n + 1 end
    end
    return n
end

return {
    ["help lines: one line for each word, in a-z order, with what it does"] = function(t)
        local function f() end
        local lines = ns.Diag.HelpLines({ zebra = f, apple = f, mid = f },
            { zebra = "last one", apple = "first one", mid = "in between" }, "/x")
        t.eq(lines, {
            "commands (3):",
            "/x apple - first one",
            "/x mid - in between",
            "/x zebra - last one",
        })
    end,

    ["help lines: a word with no description is still listed, and says so"] = function(t)
        local function f() end
        local lines = ns.Diag.HelpLines({ bare = f, blank = f, odd = f }, { blank = "", odd = 7 }, "/x")
        t.eq(lines, {
            "commands (3):",
            "/x bare - " .. ns.Diag.NO_HELP,
            "/x blank - " .. ns.Diag.NO_HELP,
            "/x odd - " .. ns.Diag.NO_HELP,
        })
        t.ok(type(ns.Diag.NO_HELP) == "string" and ns.Diag.NO_HELP ~= "", "the stand-in text is empty")
    end,

    ["help lines: only a word that can run is listed, and a description alone lists nothing"] = function(t)
        local function f() end
        local lines = ns.Diag.HelpLines({ real = f, broken = "not a function", [4] = f },
            { real = "runs", ghost = "described but never registered" }, "/x")
        t.eq(lines, { "commands (1):", "/x real - runs" })
        t.eq(ns.Diag.HelpLines({}, {}, "/x"), { "commands (0):" })
        t.eq(ns.Diag.HelpLines(nil, nil, "/x"), { "commands (0):" })
    end,

    ["help lines: a description is one line: a line break in it is a space"] = function(t)
        local function f() end
        local lines = ns.Diag.HelpLines({ a = f }, { a = "first\nsecond\r\nthird" }, "/x")
        t.eq(#lines, 2)
        t.eq(lines[2], "/x a - first second third")
    end,

    ["slash help: every registered word appears, one line each"] = function(t)
        local _, c, d = start()
        t.eq(type(d.help), "table", "there is no table for the descriptions")
        local lines = said(c, "help")
        local count = 0
        for word, fn in pairs(d.commands) do
            if type(word) == "string" and type(fn) == "function" then
                count = count + 1
                t.eq(linesFor(lines, word), 1, word .. " does not have one line of its own")
            end
        end
        t.ok(count >= 3, "diag, import and help are not all registered: " .. count)
        t.eq(#lines, count + 1, "there is a line that is neither the heading nor a word")
        t.eq(lines[1], ns.id.title .. ": commands (" .. count .. "):")
    end,

    ["slash help: diag, import and help are words in the one table, each described"] = function(t)
        local _, c, d = start()
        t.eq(type(d.help), "table", "there is no table for the descriptions")
        for _, word in ipairs({ "diag", "import", "help" }) do
            t.eq(type(d.commands[word]), "function", word .. " is not registered")
            t.ok(type(d.help[word]) == "string" and d.help[word] ~= "", word .. " has no description")
        end
        t.ok(d.help.diag:find("diag clear", 1, true) ~= nil, "the diag line does not say how to clear: " .. d.help.diag)
        local lines = said(c, "help")
        for i = 1, #lines do
            t.ok(lines[i]:find(ns.Diag.NO_HELP, 1, true) == nil, "a built-in word has no description: " .. lines[i])
        end
    end,

    ["slash help: a word added later is listed without touching the help"] = function(t)
        local _, c, d = start()
        t.eq(type(d.help), "table", "there is no table for the descriptions")
        local before = #said(c, "help")
        d.commands.later = function() end
        d.help.later = "added after start"
        d.commands.silent = function() end
        local lines = said(c, "help")
        t.eq(#lines, before + 2)
        t.eq(linesFor(lines, "later"), 1)
        t.eq(linesFor(lines, "silent"), 1)
        local found = false
        for i = 1, #lines do
            if lines[i] == ns.id.title .. ": " .. ns.id.slash .. " later - added after start" then found = true end
        end
        t.ok(found, "the later word is not listed with its description")
        d.commands.later = nil
        t.eq(linesFor(said(c, "help"), "later"), 0, "a word that was taken away is still listed")
    end,

    ["slash help: the word is read whatever its case and spacing, and changes nothing saved"] = function(t)
        local _, c = start()
        local plain = said(c, "help")
        t.ok(#plain > 1, "help listed nothing")
        t.eq(said(c, "  HELP  "), plain)
        -- Lead section 362: rewritten. A text after help that is no command
        -- was answered with page 1; it is now searched for
        -- (Tests/Core/DiagHelpSearchTests.lua).
        t.eq(said(c, "Help 1"), plain)
        local snaps = c.saved(ns.id.accountDB).diag.count
        said(c, "help")
        t.eq(c.saved(ns.id.accountDB).diag.count, snaps, "help took a snapshot")
    end,

    ["slash: a word that is not known prints the help line"] = function(t)
        local _, c = start()
        for _, rest in ipairs({ "nosuchword", "nosuchword with more", "", "   " }) do
            local lines = said(c, rest)
            t.eq(#lines, 1, "[" .. rest .. "] is not answered in one line")
            t.ok(lines[1]:find(ns.id.slash .. " help", 1, true) ~= nil,
                "[" .. rest .. "] does not point at help: " .. lines[1])
            t.ok(lines[1]:find("running", 1, true) ~= nil, "[" .. rest .. "] lost the state: " .. lines[1])
        end
    end,

    ["slash: diag still runs as a word of the table, and clear still forgets"] = function(t)
        local _, c, d = start()
        t.eq(type(d.commands.diag), "function", "diag is not a word of the table")
        local before = c.saved(ns.id.accountDB).diag.count
        local lines = said(c, "diag")
        t.eq(c.saved(ns.id.accountDB).diag.count, before + 1)
        t.ok(lines[1]:find("snapshot " .. (before + 1), 1, true) ~= nil, lines[1])
        said(c, "diag clear")
        t.eq(c.saved(ns.id.accountDB).diag, nil)
    end,

    ["slash help: the setting word comes with its description"] = function(t)
        local k, c, d = start()
        t.eq(type(d.help), "table", "there is no table for the descriptions")
        ns.SettingsSlash.Start(k, d)
        t.ok(type(d.help[ns.SettingsSlash.WORD]) == "string" and d.help[ns.SettingsSlash.WORD] ~= "",
            "the setting word has no description")
        local lines = said(c, "help")
        t.eq(linesFor(lines, ns.SettingsSlash.WORD), 1)
        for i = 1, #lines do
            t.ok(lines[i]:find(ns.Diag.NO_HELP, 1, true) == nil, "a word has no description: " .. lines[i])
        end
    end,

    ["slash help: no line spells the predecessor's name"] = function(t)
        local k, c, d = start()
        ns.SettingsSlash.Start(k, d)
        local lines = said(c, "help")
        t.ok(#lines > 1, "help listed nothing")
        for i = 1, #lines do
            local rest = lines[i]:gsub(ns.id.title, ""):gsub(ns.id.slash, "")
            t.ok(rest:find("Flow", 1, true) == nil and rest:find("flow", 1, true) == nil, lines[i])
        end
    end,
}

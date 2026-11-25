local _, ns = ...
-- Core/SelfTest.lua (parity row F-04; lead section 660): the self-test word
-- asks the client each guarded read once and says pass, fail or missing.
-- Hand-built clients and the fake. Offline only: not tested in game.
local tests = {}
local S = ns.SelfTest

local function boom() error("the client refused") end

tests["self-test: a read that answers is a pass, one that says nothing is a pass with no answer"] = function(t)
    local rows, counts = S.Run({ money = function() return 12 end, zone = function() return nil end },
        { "money", "zone" })
    t.eq(rows, { { name = "money", result = "pass", answered = true },
                 { name = "zone", result = "pass", answered = false } })
    t.eq(counts, { pass = 2, fail = 0, missing = 0, silent = 1 })
    local falsy = S.Run({ dead = function() return false end }, { "dead" })
    t.eq(falsy[1].answered, true, "a plain false is an answer")
end

tests["self-test: a read that raises is a fail with its reason, cut short"] = function(t)
    local rows, counts = S.Run({ money = boom }, { "money" })
    t.eq(rows[1].result, "fail")
    t.ok(rows[1].why:find("the client refused", 1, true) ~= nil, rows[1].why)
    t.eq(counts.fail, 1)
    local long = S.Run({ money = function() error(string.rep("x", 500)) end }, { "money" })
    t.ok(#long[1].why <= S.WHY_MAX, "no longer than the cap")
end

tests["self-test: a read the client does not have is missing"] = function(t)
    local rows, counts = S.Run({ money = 5 }, { "money", "zone" })
    t.eq(rows[1].result, "missing", "not a function")
    t.eq(rows[2].result, "missing")
    t.eq(counts, { pass = 0, fail = 0, missing = 2, silent = 0 })
    local none = S.Run(nil, { "money" })
    t.eq(none[1].result, "missing", "no client at all")
end

tests["self-test: each read is asked once, with nothing handed in"] = function(t)
    local asked, args = 0, nil
    S.Run({ money = function(...) asked = asked + 1; args = select("#", ...) return 1 end }, { "money" })
    t.eq(asked, 1)
    t.eq(args, 0, "nothing is handed to a read")
end

tests["self-test: the lines are a head with the counts, then a line for each read, and no answer in them"] = function(t)
    local rows, counts = S.Run({ money = function() return 987654 end, zone = function() return nil end,
        facing = boom }, { "money", "zone", "facing", "level" })
    local lines = S.Lines(rows, counts)
    t.eq(lines[1], S.HEAD:format(2, 1, 1, 1))
    t.eq(lines[2], "  money: pass")
    t.eq(lines[3], "  zone: pass, no answer now")
    t.ok(lines[4]:find("  facing: fail (", 1, true) == 1, lines[4])
    t.eq(lines[5], "  level: missing")
    t.eq(#lines, 5)
    t.eq(table.concat(lines, "\n"):find("987654", 1, true), nil, "the answer itself is never printed")
    t.eq(S.Lines(nil), {})
end

-- The list is of reads only: nothing in it opens, sets, binds, buys, casts
-- or writes. Fails if an acting name is ever added.
tests["self-test: the list holds reads only, each once, and the fake client has every one"] = function(t)
    local c = ns.make.fakeClient()
    local seen = {}
    for _, name in ipairs(S.READS) do
        t.eq(seen[name], nil, "once: " .. name)
        seen[name] = true
        t.eq(type(c[name]), "function", "a read of the client: " .. name)
        for _, verb in ipairs({ "^set", "^show", "^open", "^watch", "^craft", "^equip", "^clear",
            "^save", "^stop", "^restart", "^override", "^sell", "^print", "^fire" }) do
            t.eq(name:find(verb), nil, name .. " is no read")
        end
        -- A listener's name starts with "on" and a capital; onTaxi is the one read that does.
        t.ok(name == "onTaxi" or name:find("^on%u") == nil, name .. " is no listener")
    end
    t.ok(#S.READS >= 20, "a real list")
end

tests["self-test: on the fake client no read raises and none is missing"] = function(t)
    local c = ns.make.fakeClient()
    local _, counts = S.Run(c)
    t.eq(counts.fail, 0)
    t.eq(counts.missing, 0)
    t.eq(counts.pass, #S.READS)
end

-- Fails before: there is no such word.
tests["self-test: the word prints the head under the title and a line for each read, and changes nothing"] = function(t)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    local k = ns.Kernel({}, c)
    local diag = ns.Diag.Start(k)
    local api = S.Declare(k, diag)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    t.eq(type(diag.commands[S.WORD]), "function", "the word is there")
    t.eq(diag.help[S.WORD], S.HELP)
    c.setCombat(true)
    c.printed = {}
    diag.commands[S.WORD]("")
    t.eq(#c.printed, #S.READS + 1, "in a fight too: it only reads")
    t.ok(c.printed[1]:find(k.id.title .. ": self-test: ", 1, true) == 1, c.printed[1])
    t.ok(c.printed[2]:find("  now: ", 1, true) == 1, c.printed[2])
    local rows, counts = api.Run()
    t.eq(#rows, #S.READS)
    t.eq(counts.fail, 0)
    t.eq(k.problems:count(), 0)
    t.eq(type(ns.selfTest), "table", "the addon's own is declared")
end

-- Lead section 671 (Twin's review): an identity with no title still gets a
-- head line, under the add-on's own name.
tests["self-test: with no title in the identity the head line names the add-on"] = function(t)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    local k = ns.Kernel({}, c)
    local diag = ns.Diag.Start(k)
    S.Declare(k, diag)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    local real = k.id
    k.id = { addon = real.addon }
    c.printed = {}
    local ok = pcall(diag.commands[S.WORD], "")
    k.id = real
    t.eq(ok, true, "no error")
    t.ok(c.printed[1] ~= nil and c.printed[1]:find(S.TITLE .. ": self-test: ", 1, true) == 1, tostring(c.printed[1]))
end

return tests

-- The slash dispatcher runs a command word under a pcall: a word that
-- raises is one "diag" problem naming the word and one printed line, and
-- the addon goes on. No game client is involved.
local _, ns = ...

local function start()
    local c = ns.make.fakeClient({ env = {} })
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("VARIABLES_LOADED")
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, d
end

return {
    ["command guard: a word that raises is one diag problem and one line"] = function(t)
        local k, c, d = start()
        d.commands.boom = function() error("it broke") end
        local before = #c.printed
        local ran, err = pcall(c.slashes[ns.id.slash], "boom now")
        t.ok(ran, tostring(err))
        t.eq(#c.printed, before + 1, "one line")
        t.eq(c.printed[#c.printed], ns.id.title .. ": the boom command failed; it is kept as a problem.")
        local p = k.problems:list("diag")
        t.eq(#p, 1)
        t.eq(p[1].owner, "boom", "the problem names the word")
        t.ok(tostring(p[1].text):find("it broke", 1, true), tostring(p[1].text))
    end,

    ["command guard: the slash command still works after a word raised"] = function(t)
        local k, c, d = start()
        local calls = 0
        d.commands.boom = function()
            calls = calls + 1
            error("it broke")
        end
        t.ok(pcall(c.slashes[ns.id.slash], "boom"), "first")
        t.ok(pcall(c.slashes[ns.id.slash], "boom"), "second")
        t.eq(calls, 2, "the word is tried each time it is typed")
        local p = k.problems:list("diag")
        t.eq(#p, 1, "the same problem is counted, not listed twice")
        t.eq(p[1].count, 2)
        local before = #c.printed
        c.slashes[ns.id.slash]("")
        t.eq(#c.printed, before + 1, "the help line")
        t.ok(c.printed[#c.printed]:find(ns.id.slash .. " diag", 1, true), c.printed[#c.printed])
    end,

    ["command guard: a word that does not raise runs as before"] = function(t)
        local k, c, d = start()
        local got, times = nil, 0
        d.commands.fine = function(rest)
            got, times = rest, times + 1
            c.print("fine ran")
            return "ignored"
        end
        local before = #c.printed
        c.slashes[ns.id.slash]("  FINE  Some Words  ")
        t.eq(times, 1)
        t.eq(got, "some words", "lower-cased and trimmed, as before")
        t.eq(#c.printed, before + 1, "only the word's own line")
        t.eq(c.printed[#c.printed], "fine ran")
        t.eq(#k.problems:list("diag"), 0, "no problem")
    end,

    ["command guard: a raise that is not a string is still one problem and one line"] = function(t)
        local k, c, d = start()
        d.commands.odd = function() error({ code = 7 }) end
        local before = #c.printed
        local ran, err = pcall(c.slashes[ns.id.slash], "odd")
        t.ok(ran, tostring(err))
        t.eq(#c.printed, before + 1)
        local p = k.problems:list("diag")
        t.eq(#p, 1)
        t.eq(p[1].owner, "odd")
    end,
}

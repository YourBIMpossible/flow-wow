-- Lead section 818.3: a slash word gets the rest of the line lower-cased,
-- as before, and the rest as typed as a second argument, so a reply can
-- name what the player wrote. A word that reads only its first argument
-- behaves exactly as before. No game client is involved.
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
    ["diag raw rest: split gives the word, the rest lower-cased, and the rest as typed"] = function(t)
        t.eq({ ns.Diag.Split("Places Forget Nobody Here") }, { "places", "forget nobody here", "Forget Nobody Here" })
        t.eq({ ns.Diag.Split("  hidden   show 1  ") }, { "hidden", "show 1", "show 1" })
        t.eq({ ns.Diag.Split("help") }, { "help", "", "" })
        t.eq({ ns.Diag.Split("   ") }, { nil, nil, nil })
    end,

    ["diag raw rest: a word gets both; the first is as before"] = function(t)
        local _, c, d = start()
        local got
        d.commands.echo = function(more, raw) got = { more, raw } end
        c.slashes[ns.id.slash]("ECHO Nobody Here")
        t.eq(got, { "nobody here", "Nobody Here" })
        local one
        d.commands.plain = function(...) one = select("#", ...) end
        c.slashes[ns.id.slash]("plain Thing")
        t.eq(one, 2, "the raw text is an extra argument; a word that reads one is unchanged")
    end,

    ["diag raw rest: a word that only starts with diag keeps its raw rest too"] = function(t)
        local _, c, d = start()
        local got
        d.commands.diag = function(more, raw) got = { more, raw } end
        c.slashes[ns.id.slash]("diagClear Now")
        t.eq(got, { "clear now", "Clear Now" })
    end,
}

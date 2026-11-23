-- The player's own waypoint on the arrows (G35), over the fake client:
-- "/way x y [label]" and "<slash> way x y [label]" set it, "clear" takes it
-- away, it is the quest step while it is set, and it is cleared on arrival.
-- It is kept per character at Nav/Waypoint.lua's scope and path. No game
-- client is involved. Not seen in game.
local _, ns = ...

local A, N = ns.Arrow, ns.Nav
local W = N.Waypoint

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFacing(0)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local a = A.Start(k, d)
    k:Boot()
    if opts.login ~= false then
        c.fire("ADDON_LOADED", ns.id.addon)
        c.fire("PLAYER_LOGIN")
        c.fire("PLAYER_ENTERING_WORLD")
    end
    return k, c, a, d
end

local function last(c) return c.printed[#c.printed] or "" end
local function way(c, text) c.slashes["/way"](text) end
local function saved(k)
    local nav = k.store:get(W.SCOPE, W.PATH)
    return type(nav) == "table" and nav.waypoint or nil
end
local function has(text, part) return text:find(part, 1, true) ~= nil end

return {
    ["way: the place as it is said, percents with one decimal, then the label"] = function(t)
        t.eq(W.Text({ map = 1411, x = 0.452, y = 0.618 }), "45.2, 61.8")
        t.eq(W.Text({ map = 1411, x = 0.5, y = 0.3, label = "Bank" }), "50.0, 30.0 Bank")
        t.eq(W.Text({ map = 1411, x = 0, y = 1 }), "0.0, 100.0")
        t.eq(W.Text(nil), nil)
        t.eq(W.Text({ map = 1411, x = "a", y = 0.3 }), nil, "not a waypoint: nothing is said for it")
    end,

    ["way: /way x y sets it, the quest arrow points at it, and it is said"] = function(t)
        local k, c = start()
        t.ok(type(c.slashes["/way"]) == "function", "the command is there")
        if type(c.slashes["/way"]) ~= "function" then return end
        way(c, "50 30")
        local q = c.arrows[1]
        t.eq(q.shown, true)
        t.eq(q.lines, { N.WAYPOINT_LABEL, "100 yd N" })
        t.eq(saved(k), { map = 1411, x = 0.5, y = 0.3 })
        t.ok(has(last(c), "waypoint set: 50.0, 30.0"), last(c))
        t.ok(has(last(c), ns.id.title), "said under the addon's title")
        t.eq(k.problems:count(), 0)
    end,

    ["way: a label typed after /way is kept in its own capitals"] = function(t)
        local k, c = start()
        if type(c.slashes["/way"]) ~= "function" then t.ok(false, "no /way") return end
        way(c, "50 30 Bank Vault")
        t.eq(c.arrows[1].lines, { "Bank Vault", "100 yd N" })
        t.eq(saved(k).label, "Bank Vault")
    end,

    ["way: the word after the addon's own command sets it too"] = function(t)
        local k, c = start()
        c.slashes[ns.id.slash]("way 50 30")
        t.eq(saved(k), { map = 1411, x = 0.5, y = 0.3 })
        t.eq(c.arrows[1].lines, { N.WAYPOINT_LABEL, "100 yd N" })
    end,

    ["way: text that is turned down says why and changes nothing"] = function(t)
        local k, c = start()
        if type(c.slashes["/way"]) ~= "function" then t.ok(false, "no /way") return end
        way(c, "50 30 Bank")
        way(c, "50,2 30")
        t.ok(has(last(c), W.REASON.comma), last(c))
        t.ok(has(last(c), "nothing changed"), last(c))
        t.eq(saved(k), { map = 1411, x = 0.5, y = 0.3, label = "Bank" }, "the one that was set stays")
        way(c, "150 30")
        t.ok(has(last(c), "x is outside 0 to 100"), last(c))
        way(c, "50")
        t.ok(has(last(c), W.REASON.usage), last(c))
        t.eq(c.arrows[1].lines, { "Bank", "100 yd N" })
    end,

    ["way: the map the player is on is not known, so none is set"] = function(t)
        local k, c = start()
        if type(c.slashes["/way"]) ~= "function" then t.ok(false, "no /way") return end
        c.setPosition(nil)
        way(c, "50 30")
        t.ok(has(last(c), W.REASON.map), last(c))
        t.eq(saved(k), nil)
    end,

    ["way: clear takes it away, and says so; with none set it says that"] = function(t)
        local k, c = start()
        if type(c.slashes["/way"]) ~= "function" then t.ok(false, "no /way") return end
        way(c, "50 30")
        way(c, "clear")
        t.eq(saved(k), nil)
        t.eq(c.arrows[1].lines, { A.NO_QUEST }, "no step: the quest arrow says why (lead section 294 item 5)")
        t.ok(has(last(c), "waypoint cleared"), last(c))
        way(c, "Clear")
        t.ok(has(last(c), W.REASON.unset), last(c))
        c.slashes[ns.id.slash]("way clear")
        t.ok(has(last(c), W.REASON.unset), last(c))
    end,

    ["way: with nothing after it, the waypoint that is set is said, else how to set one"] = function(t)
        local _, c = start()
        if type(c.slashes["/way"]) ~= "function" then t.ok(false, "no /way") return end
        way(c, "")
        t.ok(has(last(c), "/way x y"), last(c))
        t.ok(not has(last(c), "waypoint:"), "none is set")
        way(c, "50 30 Bank")
        way(c, "  ")
        t.ok(has(last(c), "waypoint: 50.0, 30.0 Bank"), last(c))
    end,

    ["way: looking makes no saved table"] = function(t)
        local k, c, a = start()
        a.relayout()
        if type(c.slashes["/way"]) == "function" then
            way(c, "")
            way(c, "clear")
        end
        t.eq(k.store:get(W.SCOPE, W.PATH), nil)
    end,

    ["way: it wins over the pin on the game's map while it is set"] = function(t)
        local _, c, a = start()
        if type(c.slashes["/way"]) ~= "function" then t.ok(false, "no /way") return end
        c.setWaypoint(1411, 0.5, 0.1)
        a.relayout()
        t.eq(c.arrows[1].lines, { N.WAYPOINT_LABEL, "200 yd N" }, "the pin")
        way(c, "50 30 Mine")
        t.eq(c.arrows[1].lines, { "Mine", "100 yd N" })
        way(c, "clear")
        t.eq(c.arrows[1].lines, { N.WAYPOINT_LABEL, "200 yd N" }, "the pin again")
    end,

    ["way: a guide that was set still wins whole"] = function(t)
        local _, c, a = start()
        if type(c.slashes["/way"]) ~= "function" then t.ok(false, "no /way") return end
        way(c, "50 30 Mine")
        a.setGuide(function() return { quest = { place = { cont = 1, map = 1411, x = 0.5, y = 0.4 }, label = "Kill boars" } } end)
        t.eq(c.arrows[1].lines, { "Kill boars", "50 yd N" })
    end,

    ["way: on arrival it is cleared and that is said once"] = function(t)
        local k, c, a = start()
        if type(c.slashes["/way"]) ~= "function" then t.ok(false, "no /way") return end
        way(c, "50 30")
        c.setPosition(1411, 0.5, 0.33)
        a.relayout()
        t.eq(saved(k), { map = 1411, x = 0.5, y = 0.3 }, "15 yd: not there yet")
        local before = #c.printed
        c.setPosition(1411, 0.5, 0.31)
        a.relayout()
        t.eq(saved(k), nil, "5 yd: there")
        t.eq(#c.printed, before + 1)
        t.ok(has(last(c), "waypoint reached"), last(c))
        t.eq(c.arrows[1].lines, { A.NO_QUEST }, "no step: the quest arrow says why (lead section 294 item 5)")
        a.relayout()
        t.eq(#c.printed, before + 1, "said once")
    end,

    ["way: set where the player stands, it is reached at once"] = function(t)
        local k, c = start()
        if type(c.slashes["/way"]) ~= "function" then t.ok(false, "no /way") return end
        way(c, "50 50")
        t.eq(saved(k), nil)
        t.ok(has(c.printed[#c.printed - 1] or "", "waypoint reached") or has(last(c), "waypoint reached"),
            "it is said")
    end,

    ["way: a distance that is not known clears nothing"] = function(t)
        local k, c, a = start()
        if type(c.slashes["/way"]) ~= "function" then t.ok(false, "no /way") return end
        way(c, "50 30")
        c.setPosition(1412, 0.5, 0.3)
        a.relayout()
        t.eq(saved(k), { map = 1411, x = 0.5, y = 0.3 }, "another map, its size not known")
    end,

    ["way: while the player is dead the corpse is the step, and reaching it clears no waypoint"] = function(t)
        local k, c, a = start()
        if type(c.slashes["/way"]) ~= "function" then t.ok(false, "no /way") return end
        way(c, "50 10")
        c.setDead(true)
        c.setGhost(true)
        c.setCorpse(1411, 0.5, 0.5)
        a.relayout()
        t.eq(c.arrows[1].lines[1], A.CORPSE_LABEL)
        t.eq(saved(k), { map = 1411, x = 0.5, y = 0.1 }, "the corpse is near, the waypoint is not")
    end,

    ["way: before the login nothing is set and it is said"] = function(t)
        local k, c = start({ login = false })
        if type(c.slashes["/way"]) ~= "function" then t.ok(false, "no /way") return end
        way(c, "50 30")
        t.eq(saved(k), nil)
        t.ok(has(last(c), "login"), last(c))
    end,

    ["way: a saved waypoint that cannot be used is no step, and clear removes it"] = function(t)
        local k, c, a = start()
        if type(c.slashes["/way"]) ~= "function" then t.ok(false, "no /way") return end
        k.store:set(W.SCOPE, W.PATH, { waypoint = { map = 1411, x = 7, y = 0.3 } })
        a.relayout()
        t.eq(c.arrows[1].lines, { A.NO_QUEST }, "no step: the quest arrow says why (lead section 294 item 5)")
        t.eq(k.problems:count(), 0)
        way(c, "clear")
        t.eq(saved(k), nil)
        t.ok(has(last(c), "waypoint cleared"), last(c))
    end,
}

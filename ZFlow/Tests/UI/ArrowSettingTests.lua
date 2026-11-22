-- The arrows' saved layout as a setting row (WOW-SETTINGS-TABLE-ROWS): the
-- row reads and writes layout.arrows, where the arrows always kept it.
local _, ns = ...

local A = ns.Arrow
local MISSING = "Arrow.SETTING is missing"

-- opts: saved, direct (started without the module).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    local saved = opts.saved or {}
    if type(saved.layout) ~= "table" then saved.layout = {} end
    if saved.layout.arrowIntroSeen == nil then saved.layout.arrowIntroSeen = true end
    c.setSaved(ns.id.accountDB, saved)
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFacing(0)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local a
    if opts.direct then a = A.Start(k, d) else a = A.Declare(k, d) end
    k:Boot()
    return k, c, a
end

local function login(c)
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
end

local function direct(k) return k.store:get("account", "layout.arrows") end

local function step()
    return { quest = { map = 1411, x = 0.5, y = 0.4, lines = { "Go north" } } }
end

-- Counts the calls of k.settings[name] for the arrows' row.
local function counted(k, name)
    local box, real = { n = 0 }, k.settings[name]
    k.settings[name] = function(self, key, ...)
        if key == A.SETTING then box.n = box.n + 1 end
        return real(self, key, ...)
    end
    return box
end

return {
    ["arrow setting: the row is declared with the module, at layout.arrows"] = function(t)
        if type(A.SETTING) ~= "string" then t.ok(false, MISSING) return end
        local k = start()
        local row = k.settings:row(A.SETTING)
        t.ok(row ~= nil, "declared before the login")
        if not row then return end
        t.eq({ row.scope, row.type, row.path, row.default }, { "account", "table", "layout.arrows", nil })
        t.eq(A.PATH, "layout.arrows")
        t.ok(type(row.label) == "string" and row.label ~= "", "it has a label")
        t.eq(row.label:find("Flow", 1, true), nil)
        t.eq(k.problems:count(), 0)
    end,

    ["arrow setting: the row answers what the direct read answers"] = function(t)
        if type(A.SETTING) ~= "string" then t.ok(false, MISSING) return end
        local k, c, a = start()
        login(c)
        a.setGuide(step)
        t.eq(direct(k), nil)
        t.eq(k.settings:get(A.SETTING), nil, "nothing saved: nil, as the direct read")
        c.arrows[1].drag({ "TOP", "TOP", 0, -40 })
        t.ok(type(direct(k)) == "table", "the drag saved a layout")
        t.ok(k.settings:get(A.SETTING) == direct(k), "the same table")
        t.eq(k.settings:get(A.SETTING).points.quest, { "TOP", "TOP", 0, -40 })
        t.ok(A.Saved(k).arrows == direct(k), "and Arrow.Saved gives it")
        c.saved(ns.id.accountDB).layout.arrows = "junk"
        t.eq({ k.settings:get(A.SETTING), A.Saved(k).arrows }, { nil, nil }, "no table: nil from both")
        t.eq(k.store:get("account", "settings.arrow"), nil, "nothing is kept under settings")
    end,

    ["arrow setting: a layout saved before is read through the row"] = function(t)
        if type(A.SETTING) ~= "string" then t.ok(false, MISSING) return end
        local saved = { layout = { arrows = { points = { quest = { "TOP", "TOP", 30, -60 } } } } }
        local k, c, a = start({ saved = saved })
        login(c)
        a.setGuide(step)
        t.ok(k.settings:get(A.SETTING) == saved.layout.arrows)
        t.eq(c.arrows[1].point, { "TOP", "TOP", 30, -60 }, "and the arrow is placed by it")
    end,

    ["arrow setting: the arrows read and write through the row"] = function(t)
        if type(A.SETTING) ~= "string" then t.ok(false, MISSING) return end
        local k, c, a = start()
        local gets, sets = counted(k, "get"), counted(k, "set")
        login(c)
        a.setGuide(step)
        t.ok(gets.n > 0, "the layout is read through the row")
        t.eq(sets.n, 0, "nothing is written by a layout")
        c.arrows[1].drag({ "TOP", "TOP", 0, -40 })
        t.eq(sets.n, 1, "a drag is one write through the row")
        t.eq(direct(k).points.quest, { "TOP", "TOP", 0, -40 })
        t.eq(k.problems:count(), 0)
    end,

    ["arrow setting: a value set through the row places the arrow, and a reset puts it back"] = function(t)
        if type(A.SETTING) ~= "string" then t.ok(false, MISSING) return end
        local k, c, a = start()
        login(c)
        a.setGuide(step)
        local q = c.arrows[1]
        local at = { q.point[1], q.point[2], q.point[3], q.point[4] }
        t.eq(k.settings:set(A.SETTING, { points = { quest = { "TOP", "TOP", 30, -60 } } }), true)
        a.relayout()
        t.eq(q.point, { "TOP", "TOP", 30, -60 })
        t.eq(k.settings:reset(A.SETTING), 1)
        t.eq(direct(k), nil, "the saved layout is gone")
        a.relayout()
        t.eq(q.point, at, "back where it stood with nothing saved")
    end,

    ["arrow setting: arrows started directly have the row too, once"] = function(t)
        if type(A.SETTING) ~= "string" then t.ok(false, MISSING) return end
        local k, c, a = start({ direct = true })
        login(c)
        a.setGuide(step)
        t.ok(k.settings:row(A.SETTING) ~= nil)
        c.arrows[1].drag({ "TOP", "TOP", 0, -40 })
        t.ok(k.settings:get(A.SETTING) == direct(k))
        A.Saved(k)
        t.eq(k.problems:count("setting"), 0, "asked for again, it is not declared twice")
    end,

    ["arrow setting: a write the store refuses is one arrow problem, as before"] = function(t)
        if type(A.SETTING) ~= "string" then t.ok(false, MISSING) return end
        local k, c, a = start()
        login(c)
        a.setGuide(step)
        k.store.blocked.account = "the saved data is newer than this version"
        c.arrows[1].drag({ "TOP", "TOP", 0, -40 })
        t.eq(direct(k), nil)
        local p = k.problems:list("arrow")
        t.eq({ #p, p[1] and p[1].owner, p[1] and p[1].text },
            { 1, "save", "the saved data is newer than this version" })
    end,
}

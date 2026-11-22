-- The arrows as a declared module: nothing before the load, nothing beside
-- the predecessor, the same arrows once started, and off for good when the
-- kernel switches the module off. Over the fake client; no game client.
local _, ns = ...

local A = ns.Arrow

-- opts: saved, predecessor (the load guard pauses), direct (the arrows
-- started without the module, as Tests/UI/ArrowTests.lua starts them).
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
    if opts.predecessor then c.setLoaded(ns.id.predecessor, true) end
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local a
    if opts.direct then a = A.Start(k, d) else a = A.Declare(k, d) end
    k:Boot()
    return k, c, a, d
end

local function login(c)
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
end

local function savedArrows(c)
    local layout = c.saved(ns.id.accountDB).layout
    return type(layout) == "table" and layout.arrows or nil
end

-- A quest step north of the player, on the map the player is on.
local function step()
    return { quest = { place = { cont = 1, map = 1411, x = 0.5, y = 0.3 }, label = "Kill boars" } }
end

-- A guide that counts how often it is asked, and fails while box.fail is set.
local function counted(box)
    box.asked = 0
    return function()
        box.asked = box.asked + 1
        if box.fail then error("guide broke") end
        return step()
    end
end

-- What a player would see of one arrow.
local function seen(arrow)
    return { shown = arrow.shown, lines = arrow.lines, textPoint = arrow.textPoint }
end

-- How much of the module the kernel has run: handlers, ticks and its start.
local function work(k)
    local row = k.meter:report()[A.NAME]
    return row and row.calls or 0
end

local MISSING = "Arrow.Declare is missing"

return {
    ["module: declared by name; nothing is made or run before the load"] = function(t)
        if type(A.Declare) ~= "function" then t.ok(false, MISSING) return end
        local k, c, a, d = start()
        t.eq(k:ModuleState(A.NAME), "declared")
        t.eq(#c.arrows, 0, "no frame before the load guard has decided")
        t.eq(d.commands.arrow, nil, "no command word yet")
        t.eq(c.ticking(), false)
        t.eq(a.state(), { ready = false, demo = false, near = false })
        t.eq(a.handles, nil)
        local box = {}
        a.setGuide(counted(box))
        a.relayout()
        c.fire("PLAYER_ENTERING_WORLD")
        t.eq(box.asked, 0, "the event is not the module's yet")
        t.eq(#c.arrows, 0)
        t.eq(work(k), 0)
    end,

    ["module: started at the load, with its frames, its event, its tick and its command"] = function(t)
        if type(A.Declare) ~= "function" then t.ok(false, MISSING) return end
        local k, c, a, d = start()
        login(c)
        t.eq({ k:ModuleState(A.NAME) }, { "started" })
        t.eq(k.problems:count(), 0)
        t.eq(#c.arrows, 2)
        t.eq(a.handles and a.handles.quest, c.arrows[1])
        t.eq(c.ticking(), true)
        t.ok(type(d.commands.arrow) == "function", "the command word")
        t.eq(a.state().ready, true)

        local box = {}
        a.setGuide(counted(box))
        local asked, ran = box.asked, work(k)
        c.fire("PLAYER_ENTERING_WORLD")
        t.eq(box.asked, asked + 1, "the event lays the arrows out")
        t.eq(work(k), ran + 1, "as a handler of the module")
        ran = work(k)
        local draws = c.arrows[1].draws
        c.advance(0.1, 4)
        t.eq(c.arrows[1].draws, draws + 4, "drawn on every frame")
        t.eq(work(k), ran + 4, "as work of the module")
    end,

    ["module: a guide set before the load is the guide once started"] = function(t)
        if type(A.Declare) ~= "function" then t.ok(false, MISSING) return end
        local _, c, a = start()
        a.setGuide(step)
        login(c)
        t.eq(c.arrows[1].shown, true)
        t.eq(c.arrows[1].lines[1], "Kill boars")
    end,

    ["module: beside the predecessor it makes no frame and registers nothing"] = function(t)
        if type(A.Declare) ~= "function" then t.ok(false, MISSING) return end
        -- The same paused kernel without the arrows: what is listened to anyway.
        local bare = ns.make.fakeClient()
        bare.setLoaded(ns.id.predecessor, true)
        local kb = ns.Kernel({}, bare)
        ns.Diag.Start(kb)
        kb:Boot()
        login(bare)

        local k, c, a, d = start({ predecessor = true })
        local box = {}
        a.setGuide(counted(box))
        login(c)
        c.advance(1, 10)
        c.fire("PLAYER_ENTERING_WORLD")
        t.eq(k.paused, true)
        t.eq(#c.arrows, 0, "no arrow frame")
        t.eq(c.events(), bare.events(), "no event of its own")
        t.eq(c.ticking(), bare.ticking(), "no tick of its own")
        t.eq(d.commands.arrow, nil, "no command word")
        t.eq(k:ModuleState(A.NAME), "declared")
        a.relayout()
        t.eq(box.asked, 0, "nothing of it ran")
        t.eq(work(k), 0)
        t.eq(#c.arrows, 0)
        t.eq(a.state(), { ready = false, demo = false, near = false })
        t.eq(savedArrows(c), nil)
    end,

    ["module: switched off after its errors, the frames hide and every handler stops"] = function(t)
        if type(A.Declare) ~= "function" then t.ok(false, MISSING) return end
        local k, c, a, d = start()
        login(c)
        local box = {}
        a.setGuide(counted(box))
        local q, p = c.arrows[1], c.arrows[2]
        t.eq(q.shown, true, "a step to point at")

        box.fail = true
        c.fire("PLAYER_ENTERING_WORLD")
        c.fire("PLAYER_ENTERING_WORLD")
        t.eq(k:ModuleState(A.NAME), "started", "two errors")
        t.eq(q.shown, false, "after an error the arrow is off the screen, not frozen on it")
        box.fail = false
        c.fire("PLAYER_ENTERING_WORLD")
        t.eq(q.shown, true, "and back with the next good layout")

        box.fail = true
        for _ = 3, ns.FAULT_LIMIT do c.fire("PLAYER_ENTERING_WORLD") end
        local state, reason = k:ModuleState(A.NAME)
        t.eq(state, "off")
        t.ok(type(reason) == "string" and reason:find("guide broke", 1, true) ~= nil, "the reason is the last error")
        t.eq({ q.shown, p.shown }, { false, false }, "the frames are hidden")
        t.eq(a.state().view, nil)

        -- Nothing brings them back, and nothing of the module runs.
        box.fail = false
        local asked, ran, draws = box.asked, work(k), q.draws
        c.fire("PLAYER_ENTERING_WORLD")
        c.advance(1, 10)
        t.eq(box.asked, asked, "its event handler is gone")
        t.eq(work(k), ran, "the kernel runs nothing of it")
        t.eq(q.draws, draws, "no frame work")
        t.eq(q.shown, false)
        a.setGuide(step)
        a.relayout()
        t.eq(q.shown, false, "a guide does not show it")
        local said = #c.printed
        d.commands.arrow("demo")
        t.eq({ q.shown, p.shown }, { false, false }, "the demo does not show it")
        t.eq(a.state().demo, false)
        t.eq(#c.printed, said + 1, "the command says so")
        t.ok((c.printed[#c.printed] or ""):find("switched off", 1, true) ~= nil, "in words")
        d.commands.arrow("separate")
        t.eq(savedArrows(c), nil, "and saves nothing")
    end,

    ["module: the same arrows, lines, places and saved layout as started directly"] = function(t)
        if type(A.Declare) ~= "function" then t.ok(false, MISSING) return end
        local function run(direct)
            local _, c, a, d = start({ direct = direct })
            login(c)
            local out = {}
            local function note()
                out[#out + 1] = { seen(c.arrows[1]), seen(c.arrows[2]), a.state(), savedArrows(c) or "none" }
            end
            note()
            a.setGuide(step)
            c.advance(1, 10)
            note()
            d.commands.arrow("demo")
            c.advance(1, 10)
            note()
            d.commands.arrow("separate")
            d.commands.arrow("hide prof")
            d.commands.arrow("text quest")
            note()
            d.commands.arrow("near")
            c.advance(0.5, 5)
            note()
            d.commands.arrow("reset")
            d.commands.arrow("demo")
            c.advance(0.5, 5)
            note()
            out.draws = { c.arrows[1].draws, c.arrows[2].draws }
            out.printed = c.printed
            return out
        end
        local module, direct = run(false), run(true)
        t.eq(#module, 6)
        for i = 1, #direct do
            t.eq(module[i], direct[i], "step " .. i)
        end
        t.eq(module.draws, direct.draws, "drawn on every frame, as before")
        t.eq(module.printed, direct.printed)
    end,

    ["module: a saved layout is restored, and a switch is saved, where they always were"] = function(t)
        if type(A.Declare) ~= "function" then t.ok(false, MISSING) return end
        local saved = { layout = { arrows = { mode = "separate", hidden = { prof = true },
            points = { quest = { "TOP", "TOP", 0, -40 } } } } }
        local _, c, a, d = start({ saved = saved })
        login(c)
        d.commands.arrow("demo")
        t.eq(c.arrows[1].shown, true)
        t.eq(c.arrows[2].shown, false, "hidden as saved")
        t.eq(a.state().view.prof.shown, false)
        t.eq(savedArrows(c).mode, "separate")
        d.commands.arrow("hide prof")
        t.eq(c.arrows[2].shown, true)
        t.eq(savedArrows(c).hidden, nil, "the switch is saved at the same place")
        t.eq(savedArrows(c).points.quest, { "TOP", "TOP", 0, -40 })
    end,

    ["module: a frame error is still one problem of the arrow, hidden at once"] = function(t)
        if type(A.Declare) ~= "function" then t.ok(false, MISSING) return end
        local k, c, a, d = start()
        login(c)
        d.commands.arrow("demo")
        local q = c.arrows[1]
        q.draw = function() error("boom") end
        c.advance(0.1, 5)
        t.eq(k.problems:count(), 1)
        t.eq(k.problems:count("arrow"), 1)
        t.eq({ q.shown, c.arrows[2].shown }, { false, false })
        t.eq(a.state().view, nil)
        t.eq(k:ModuleState(A.NAME), "started", "the arrow stops itself at its first frame error")
    end,

    ["module: the intro plays once and is saved as seen at its first frame"] = function(t)
        if type(A.Declare) ~= "function" then t.ok(false, MISSING) return end
        local _, c, a = start({ saved = { layout = { arrowIntroSeen = false } } })
        login(c)
        t.eq(a.state().view.quest.mode, "intro")
        t.eq(c.saved(ns.id.accountDB).layout.arrowIntroSeen, false, "no frame yet")
        c.advance(0.01, 1)
        t.eq(c.saved(ns.id.accountDB).layout.arrowIntroSeen, true)
        c.advance(A.INTRO_SECONDS + 1, 10)
        t.eq(c.arrows[1].shown, false, "over")
    end,

    ["module: a second declaration is refused and the first goes on"] = function(t)
        if type(A.Declare) ~= "function" then t.ok(false, MISSING) return end
        local k, c, a, d = start()
        local again = A.Declare(k, d)
        login(c)
        t.eq(#c.arrows, 2, "one pair of arrows")
        t.eq(k.problems:count("module"), 1)
        t.eq(again.state(), { ready = false, demo = false, near = false })
        t.eq(again.handles, nil)
        t.eq(a.state().ready, true)
    end,
}

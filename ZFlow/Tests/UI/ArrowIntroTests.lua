-- The arrows' intro over the fake client: shown once, at the first login of
-- an install that has not seen it, then saved as seen. And the player's own
-- map waypoint as the quest step while no guide is set. No game client is
-- involved.
local _, ns = ...

local A, N = ns.Arrow, ns.Nav

-- The player in the middle of map 1411 (1000 by 500 yards), facing north.
-- opts.saved: the account's saved table (nil: a fresh install).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    if opts.saved then c.setSaved(ns.id.accountDB, opts.saved) end
    c.setScreen(1024, 768)
    if opts.noFrames then c.setFrames(false) end
    if not opts.nowhere then
        c.setZone(1, 1411)
        c.setFacing(0)
        c.setPosition(1411, 0.5, 0.5)
        c.setMapSize(1411, 1000, 500)
    end
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local a = A.Start(k, d)
    k:Boot()
    return c, a, k, d
end

local function login(c)
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
end

-- The first frame after the loading screen: the intro's clock starts here.
local function firstFrame(c) c.advance(0.01, 1) end

local function seen(c)
    if not c.savedExists(ns.id.accountDB) then return nil end
    local layout = c.saved(ns.id.accountDB).layout
    return type(layout) == "table" and layout.arrowIntroSeen or nil
end

local function seenSaved() return { layout = { arrowIntroSeen = true } } end

local function boars()
    return { quest = { place = { cont = 1, map = 1411, x = 0.5, y = 0.3 }, label = "Kill boars" } }
end

return {
    -- ------------------------------------------------------------ the intro
    ["the saved path and the length of the intro"] = function(t)
        t.eq(A.INTRO_PATH, "layout.arrowIntroSeen")
        t.ok(type(A.INTRO_SECONDS) == "number" and A.INTRO_SECONDS > 0, "a length in seconds")
    end,

    ["fresh install: nothing shown or saved before login"] = function(t)
        local c = start()
        t.eq(c.arrows[1].shown, false)
        t.eq(seen(c), nil)
    end,

    ["fresh install: the intro is on the quest arrow once in the world; seen is saved at the first frame (MR2-1)"] = function(t)
        local c, a = start()
        login(c)
        local q, p = c.arrows[1], c.arrows[2]
        t.eq(q.shown, true)
        t.eq(p.shown, false, "the needle is not part of the intro")
        t.eq(q.lines, { ns.id.title })
        t.eq(a.state().view.quest.mode, "intro")
        t.eq(seen(c), nil, "no frame has been drawn yet: not seen")
        firstFrame(c)
        t.eq(seen(c), true)
    end,

    ["before the world is entered: no intro, nothing saved, whatever frames are drawn (MR2-1)"] = function(t)
        local c, a = start()
        c.fire("ADDON_LOADED", ns.id.addon)
        c.fire("PLAYER_LOGIN")
        t.eq(c.arrows[1].shown, false, "login alone is not the world")
        c.advance(A.INTRO_SECONDS * 2, 12)
        t.eq(c.arrows[1].shown, false)
        t.eq(seen(c), nil)
        c.fire("PLAYER_ENTERING_WORLD")
        t.eq(a.state().view.quest.mode, "intro", "the whole intro is still to come")
        firstFrame(c)
        c.advance(A.INTRO_SECONDS - 0.5, 10)
        t.eq(a.state().view.quest.mode, "intro")
        t.eq(seen(c), true)
    end,

    ["the clock starts at the first frame, not at the event: time under the loading screen is not counted (MR2-1)"] = function(t)
        local c, a = start()
        local now, under = c.now, 0
        c.now = function() return now() + under end
        login(c)
        under = A.INTRO_SECONDS * 10        -- the loading screen: time passes, no frame is drawn
        t.eq(seen(c), nil)
        firstFrame(c)
        t.eq(c.arrows[1].shown, true)
        t.eq(a.state().view.quest.mode, "intro")
        c.advance(A.INTRO_SECONDS - 0.5, 10)
        t.eq(a.state().view.quest.mode, "intro", "its full length, from the first frame")
        c.advance(1, 10)
        t.eq(c.arrows[1].shown, false)
    end,

    ["a second loading screen while the intro plays neither restarts nor replays it"] = function(t)
        local c, a = start()
        login(c)
        firstFrame(c)
        c.advance(A.INTRO_SECONDS - 1, 10)
        c.fire("PLAYER_ENTERING_WORLD")
        t.eq(a.state().view.quest.mode, "intro")
        c.advance(1.5, 10)
        t.eq(c.arrows[1].shown, false, "it ended by the clock it started with")
    end,

    ["a clock that is no number at the first frame: the intro is dropped and not saved"] = function(t)
        local c = start()
        login(c)
        c.now = function() return nil end
        c.advance(1, 4)
        t.eq(c.arrows[1].shown, false)
        t.eq(seen(c), nil)
    end,

    ["the intro ends after its length; with no guide the arrows hide"] = function(t)
        local c, a = start()
        login(c)
        firstFrame(c)
        c.advance(A.INTRO_SECONDS - 0.5, 10)
        t.eq(c.arrows[1].shown, true, "still playing")
        t.eq(a.state().view.quest.mode, "intro")
        c.advance(1, 10)
        t.eq(c.arrows[1].shown, false)
        t.eq(a.state().view, nil)
        c.advance(60, 10)
        t.eq(c.arrows[1].shown, false, "it does not come back")
    end,

    ["shown once: an install that has seen it gets no intro"] = function(t)
        local c = start()
        login(c)
        firstFrame(c)
        local c2, a2 = start({ saved = c.saved(ns.id.accountDB) })
        login(c2)
        t.eq(c2.arrows[1].shown, false)
        t.eq(a2.state().view, nil)
        c2.advance(1, 4)
        t.eq(c2.arrows[1].shown, false)
        t.eq(seen(c2), true)
    end,

    ["shown once: another loading screen in the same session does not replay it"] = function(t)
        local c = start()
        login(c)
        c.advance(A.INTRO_SECONDS + 1, 10)
        c.fire("PLAYER_ENTERING_WORLD")
        t.eq(c.arrows[1].shown, false)
        c.advance(1, 4)
        t.eq(c.arrows[1].shown, false)
    end,

    ["only a saved plain true counts as seen"] = function(t)
        local c = start({ saved = { layout = { arrowIntroSeen = "yes" } } })
        login(c)
        t.eq(c.arrows[1].shown, true)
        firstFrame(c)
        t.eq(seen(c), true)
    end,

    ["the intro plays over a guide, then the guide's step shows"] = function(t)
        local c, a = start()
        local guide = boars()
        a.setGuide(function() return guide end)
        login(c)
        local q = c.arrows[1]
        t.eq(q.lines, { ns.id.title })
        t.eq(a.state().view.quest.mode, "intro")
        c.advance(A.INTRO_SECONDS + 0.5, 10)
        t.eq(q.shown, true)
        t.eq(q.lines, { "Kill boars", "100 yd" })
        t.eq(a.state().view.quest.mode, "arrow")
        t.eq(guide, boars(), "the guide handed in is left alone")
    end,

    ["the intro needs no position"] = function(t)
        local c, a = start({ nowhere = true })
        login(c)
        t.eq(c.arrows[1].shown, true)
        t.eq(a.state().view.quest.mode, "intro")
    end,

    ["the intro is not faded and has no unknown-direction line"] = function(t)
        local c, a = start({ nowhere = true })
        login(c)
        local q = c.arrows[1]
        t.eq(q.lines, { ns.id.title })
        t.eq(q.faded, a.state().view.quest.alpha, "the view's own alpha, not the lost fade")
    end,

    ["a client without frames: no intro, nothing saved"] = function(t)
        local c, a = start({ noFrames = true })
        login(c)
        t.eq(a.handles, nil)
        t.eq(seen(c), nil)
    end,

    ["the demo over an unseen intro: the demo shows, and its frames do not mark the intro seen (MR2-7)"] = function(t)
        local c, a, _, d = start({ saved = { layout = {} } })
        login(c)
        t.eq(seen(c), nil, "unseen: no frame yet")
        d.commands.arrow("demo")
        t.eq(a.state().view.quest.mode, "arrow")
        c.advance(A.INTRO_SECONDS * 2, 12)
        t.eq(seen(c), nil, "the demo's frames are not the intro's")
        d.commands.arrow("demo")
        t.eq(a.state().view.quest.mode, "intro", "the intro was never on a frame: it is still to come")
        firstFrame(c)
        t.eq(seen(c), true)
    end,

    -- ------------------------------------------- GuideSource's intro argument
    ["GuideSource: the intro argument is N.ArrowGate's intro"] = function(t)
        local c = start({ saved = seenSaved() })
        login(c)
        local intro = { title = "Hello" }
        local src = A.GuideSource(c, {}, boars(), intro)
        t.eq(src.view.gate, N.ArrowGate(true, true, true, true, false))
        t.eq(src.view.gate, "intro")
        t.eq(src.lines.quest, { "Hello" })
        t.eq(src.turns.quest, 0, "upright")
        c.setPosition(nil)
        t.eq(A.GuideSource(c, {}, boars(), intro).view.gate, N.ArrowGate(true, true, true, false, false))
        c.setDead(true)
        t.eq(A.GuideSource(c, {}, boars(), intro).view.gate, N.ArrowGate(true, true, true, false, true))
    end,

    ["GuideSource: without the intro argument nothing changes"] = function(t)
        local c = start({ saved = seenSaved() })
        login(c)
        local src = A.GuideSource(c, {}, boars())
        t.eq(src.view.gate, "open")
        t.eq(src.lines.quest, { "Kill boars", "100 yd" })
        t.eq(A.GuideSource(c, {}, boars(), false).view.gate, "open")
    end,

    ["GuideSource: the guide's own gate wins over the intro"] = function(t)
        local c = start({ saved = seenSaved() })
        login(c)
        local guide = boars()
        guide.view = { gate = "open" }
        local src = A.GuideSource(c, {}, guide, { title = "Hello" })
        t.eq(src.view.gate, "open")
        t.eq(src.lines.quest, { "Kill boars", "100 yd" })
    end,

    ["GuideSource: an intro with no title has no line"] = function(t)
        local c = start({ saved = seenSaved() })
        login(c)
        local src = A.GuideSource(c, {}, {}, {})
        t.eq(src.view.gate, "intro")
        t.eq(src.lines.quest, {})
    end,

    -- ---------------------------------------------------------- the waypoint
    ["no guide, no waypoint: nothing to point at"] = function(t)
        local c, a = start({ saved = seenSaved() })
        login(c)
        t.eq(c.arrows[1].shown, false)
        t.eq(a.state().view, nil)
    end,

    ["no guide: the player's waypoint is the quest step"] = function(t)
        local c, a = start({ saved = seenSaved() })
        c.setWaypoint(1411, 0.3, 0.5)          -- 200 yards west
        login(c)
        local q = c.arrows[1]
        t.eq(q.shown, true)
        t.eq(q.lines, { "Waypoint", "200 yd" })
        t.eq(a.state().view.quest.mode, "arrow")
        t.eq(c.arrows[2].shown, false, "a waypoint is no profession step")
    end,

    ["the waypoint is picked up, moved and cleared while playing"] = function(t)
        local c = start({ saved = seenSaved() })
        login(c)
        local q = c.arrows[1]
        t.eq(q.shown, false)
        c.setWaypoint(1411, 0.3, 0.5)
        c.advance(A.RELAYOUT * 2, 2)
        t.eq(q.lines, { "Waypoint", "200 yd" })
        c.setWaypoint(1411, 0.5, 0.3)          -- 100 yards north
        c.advance(A.RELAYOUT * 2, 2)
        t.eq(q.lines, { "Waypoint", "100 yd" })
        c.setWaypoint(nil)
        c.advance(A.RELAYOUT * 2, 2)
        t.eq(q.shown, false)
    end,

    ["a guide replaces the waypoint; taking the guide away brings it back"] = function(t)
        local c, a = start({ saved = seenSaved() })
        c.setWaypoint(1411, 0.3, 0.5)
        login(c)
        local q = c.arrows[1]
        t.eq(q.lines, { "Waypoint", "200 yd" })
        local guide = boars()
        a.setGuide(function() return guide end)
        t.eq(q.lines, { "Kill boars", "100 yd" })
        a.setGuide(nil)
        t.eq(q.lines, { "Waypoint", "200 yd" })
    end,

    ["an explicit guide wins even when it has no step"] = function(t)
        local c, a = start({ saved = seenSaved() })
        c.setWaypoint(1411, 0.3, 0.5)
        login(c)
        a.setGuide(function() return {} end)
        t.eq(c.arrows[1].shown, false, "a guide with no quest step")
        a.setGuide(function() return nil end)
        t.eq(c.arrows[1].shown, false, "a guide that answers nothing")
        t.eq(a.state().view, nil)
    end,

    ["dead with a waypoint and no guide: the corpse, not the waypoint"] = function(t)
        local c = start({ saved = seenSaved() })
        c.setWaypoint(1411, 0.3, 0.5)
        c.setDead(true)
        c.setCorpse(1411, 0.5, 0.3)
        login(c)
        t.eq(c.arrows[1].lines, { "Corpse", "100 yd" })
    end,

    ["a client with no waypoint read, or one that fails: nothing shown"] = function(t)
        local c, a = start({ saved = seenSaved() })
        c.setWaypoint(1411, 0.3, 0.5)
        c.waypoint = nil
        login(c)
        t.eq(c.arrows[1].shown, false)
        c.waypoint = function() error("the client refused") end
        a.relayout()
        t.eq(c.arrows[1].shown, false)
        t.eq(a.state().view, nil)
    end,

    ["the intro plays first, then the waypoint shows"] = function(t)
        local c = start()
        c.setWaypoint(1411, 0.3, 0.5)
        login(c)
        local q = c.arrows[1]
        t.eq(q.lines, { ns.id.title })
        c.advance(A.INTRO_SECONDS + 0.5, 10)
        t.eq(q.lines, { "Waypoint", "200 yd" })
    end,

    -- ------------------------------------------- the corpse's place (Plexy R5)
    ["the real client's corpse place is always on the player's own map (R5)"] = function(t)
        local env = { here = 1411 }
        local asked = {}
        env.C_Map = { GetBestMapForUnit = function() return env.here end }
        env.C_DeathInfo = { GetCorpseMapPosition = function(map)
            asked[#asked + 1] = map
            return { x = 0.25, y = 0.75, uiMapID = 9999, map = 9999 }
        end }
        local c = ns.make.client(env)
        t.eq(c.corpse(), { map = 1411, x = 0.25, y = 0.75 })
        env.here = 1412
        t.eq(c.corpse(), { map = 1412, x = 0.25, y = 0.75 }, "the map asked for, not one the answer names")
        t.eq(asked, { 1411, 1412 }, "only the player's map is asked about")
        env.here = nil
        t.eq(c.corpse(), nil, "no map for the player: no place")
        t.eq(#asked, 2, "and nothing is asked")
    end,

    ["a corpse place is built only from a place the corpse read gives (R5)"] = function(t)
        local c = start({ saved = seenSaved() })
        login(c)
        c.setDead(true)
        c.setGhost(true)
        c.setCorpse(1411, 0.5, 0.3)
        local src = A.GuideSource(c, {}, {})
        t.ok(type(src.view.quest.distance) == "number", "a place on the player's map: a distance")
        t.ok(src.turns.quest ~= nil, "and a turn")
        local none = { false, "nil", "a string", 7, true, {}, { map = 1411 }, { x = 0.5, y = 0.3 },
                       { map = 1411, x = "left", y = 0.3 } }
        for i = 1, #none do
            local answer = none[i]
            c.corpse = function()
                if answer == "nil" then return nil end
                return answer
            end
            src = A.GuideSource(c, {}, {})
            t.eq(src.view.quest.distance, nil, "no place, no distance: answer " .. i)
            t.eq(src.turns.quest, nil, "no turn: answer " .. i)
        end
        c.corpse = function() error("the client refused") end
        t.eq(A.GuideSource(c, {}, {}).view.quest.distance, nil, "a failing read")
        c.corpse = nil
        t.eq(A.GuideSource(c, {}, {}).view.quest.distance, nil, "no read")
    end,

    -- A pin of what happens, not a wish: the intro is not held back for a
    -- save that fails, so it plays again next session.
    ["the save fails: the intro plays, one problem is recorded, and it is not seen (IT2)"] = function(t)
        local c, a, k = start()
        login(c)
        k.store.blocked.account = "the disk refused"
        t.eq(k.problems:count(), 0)
        firstFrame(c)
        t.eq(c.arrows[1].shown, true, "it plays")
        t.eq(a.state().view.quest.mode, "intro")
        t.eq(k.problems:count(), 1, "the failed save is one problem")
        t.eq(seen(c), nil, "not saved as seen")
        c.advance(A.INTRO_SECONDS - 0.5, 10)
        t.eq(a.state().view.quest.mode, "intro", "its full length")
        t.eq(k.problems:count(), 1, "said once, not every frame")
        c.advance(1, 10)
        t.eq(c.arrows[1].shown, false, "and it ends")
        t.eq(seen(c), nil)
        t.eq(k.problems:count(), 1)
    end,
}

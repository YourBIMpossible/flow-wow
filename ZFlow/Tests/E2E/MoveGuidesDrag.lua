local _, ns = ...
-- The alignment guides (S29, UI/MoveGuides.lua) on the whole add-on loaded
-- on a fake client, through their real entry: the game moving and dropping
-- a frame the guides watch (c.moveFrame / c.dropFrame stand in for the
-- Ctrl-drag on screen). What the player sees: a line at the middle of the
-- screen or along the other arrow while the frame is near it, gone on
-- drop, and the frame settling onto it. The guides save nothing: the drop
-- answers a nudge and the add-on's saved data is not written. Unknown
-- data: a frame that is not there at login (found by the retry), a
-- dragged box that is not a box, and the setting off. Not tested in game.
local tests = {}

local G = ns.MoveGuides
local ICON = ns.id.framePrefix .. "RotationIcon"
local ARROW = ns.id.framePrefix .. "QuestArrow"
local PROF = ns.id.framePrefix .. "ProfArrow"

local function start(rects)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setScreen(1000, 600)
    for name, r in pairs(rects or {}) do c.setFrameRect(name, r) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for key, value in pairs(v) do out[key] = copy(value) end
    return out
end

local function lastShow(c)
    local all = c.guideShows()
    return all[#all]
end

tests["move guides: near the middle a line shows, near the other arrow a line runs along both, the drop settles"] = function(t)
    local c, addon = start({
        [ICON] = { l = 600, r = 640, b = 100, t = 140 },
        [ARROW] = { l = 700, r = 740, b = 315, t = 355 },
    })
    t.eq(addon.settings:get(G.SETTING), true, "on by default")
    t.ok(c.watched(ICON), "the guides watch the rotation icon")
    t.ok(c.watched(ARROW), "and the quest arrow")
    local account = copy(c.saved(ns.id.accountDB))

    -- The icon's middle at x = 498: two pixels off the screen's middle.
    c.moveFrame(ICON, { l = 478, r = 518, b = 200, t = 240 })
    t.eq(c.guidesUp(), true, "a line is up")
    local s = lastShow(c)
    t.eq({ s[1], s[2], s[3] }, { 500, 0, 600 }, "a line down the middle of the screen")
    t.eq(s[4], nil, "no line across")
    local dx, dy = c.dropFrame(ICON, { l = 478, r = 518, b = 200, t = 240 })
    t.eq({ dx, dy }, { 2, 0 }, "let go: it settles on the middle")
    t.eq(c.guidesUp(), false, "the line goes on drop")

    -- The icon's middle at y = 330, five below the arrow's middle (335).
    local shows = #c.guideShows()
    c.moveFrame(ICON, { l = 100, r = 140, b = 310, t = 350 })
    t.eq(#c.guideShows(), shows + 1, "a line shown")
    s = lastShow(c)
    t.eq(s[1], nil, "no line down")
    t.eq({ s[4], s[5], s[6] }, { 335, 100 - G.REACH, 740 + G.REACH }, "a line across from the icon to past the arrow")
    dx, dy = c.dropFrame(ICON, { l = 100, r = 140, b = 310, t = 350 })
    t.eq({ dx, dy }, { 0, 5 }, "let go: it settles on the arrow's middle")

    -- Far from anything: no line.
    c.moveFrame(ICON, { l = 200, r = 240, b = 50, t = 90 })
    t.eq(c.guidesUp(), false, "nothing near: no line")
    t.eq(c.saved(ns.id.accountDB), account, "the guides saved nothing")
end

tests["move guides: unknown data: a frame made late, a box that is not a box, the setting off"] = function(t)
    local c, addon = start({ [ICON] = { l = 600, r = 640, b = 100, t = 140 } })
    t.eq(c.watched(PROF), false, "no profession arrow at login: not watched")
    c.setFrameRect(PROF, { l = 300, r = 340, b = 400, t = 440 })
    c.advance(G.RETRY + 1, 10)
    t.eq(c.watched(PROF), true, "made later: found by the retry")

    local shows = #c.guideShows()
    c.moveFrame(ICON, { l = 0 / 0, r = 518, b = 200, t = 240 })
    t.eq(#c.guideShows(), shows, "a box with no number: no line")
    t.eq(c.guidesUp(), false)
    t.eq({ c.dropFrame(ICON, { l = "left", r = 518, b = 200, t = 240 }) }, { 0, 0 }, "and no nudge")
    t.eq({ c.dropFrame(ICON, nil) }, { 0, 0 }, "no box at all: no nudge")

    addon.settings:set(G.SETTING, false)
    c.moveFrame(ICON, { l = 478, r = 518, b = 200, t = 240 })
    t.eq(#c.guideShows(), shows, "switched off: no line even at the middle")
    t.eq(c.guidesUp(), false)
    t.eq({ c.dropFrame(ICON, { l = 478, r = 518, b = 200, t = 240 }) }, { 0, 0 }, "switched off: no nudge")
end

return tests

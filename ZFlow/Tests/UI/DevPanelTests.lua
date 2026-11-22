-- The dev panel over the fake client: what it says, where it stands, what
-- it saves, and that a paused addon or a client without frames is handled.
-- No game client is involved.
local _, ns = ...

local P = ns.DevPanel
local PATH = "devPanel" -- under the account table's layout

-- opts: saved (the account table to start from), screen = { w, h },
-- predecessor (pause the addon), noFrames, noDiag.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    if opts.saved then c.setSaved(ns.id.accountDB, opts.saved) end
    if opts.screen then c.setScreen(opts.screen[1], opts.screen[2]) end
    if opts.predecessor then c.setLoaded(ns.id.predecessor, true) end
    if opts.noFrames then c.setFrames(false) end
    local k = ns.Kernel({}, c)
    local d = (not opts.noDiag) and ns.Diag.Start(k) or nil
    local p = P.Start(k, d)
    k:Boot()
    return k, c, p, d
end

local function login(c)
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
end

local function savedPanel(c)
    local layout = c.saved(ns.id.accountDB).layout
    return type(layout) == "table" and layout[PATH] or nil
end

local function has(lines, text)
    for i = 1, #lines do
        if lines[i]:find(text, 1, true) then return true end
    end
    return false
end

return {
    ["first run: hidden until login, then shown at the default point, nothing saved"] = function(t)
        local _, c, p = start({ screen = { 1024, 768 } })
        t.eq(#c.panels, 1)
        t.eq(c.panels[1].spec, { name = ns.id.framePrefix .. "DevPanel", width = P.WIDTH, height = P.HEIGHT })
        t.eq(p.panel.shown, false)
        t.eq(p.panel.point, nil, "no place before saved data is in")
        t.eq(c.savedExists(ns.id.accountDB), false, "nothing is read or written before login")
        login(c)
        t.eq(p.panel.shown, true)
        t.eq(p.panel.point, P.DEFAULT_POINT)
        t.eq(savedPanel(c), nil, "showing it at the default saves nothing")
    end,

    ["drag: the new point is saved and the next start restores it"] = function(t)
        local _, c, p = start({ screen = { 1024, 768 } })
        login(c)
        p.panel.drag({ "CENTER", "CENTER", 30, -40 })
        t.eq(savedPanel(c), { point = { "CENTER", "CENTER", 30, -40 } })
        local _, c2, p2 = start({ screen = { 1024, 768 }, saved = c.saved(ns.id.accountDB) })
        login(c2)
        t.eq(p2.panel.point, { "CENTER", "CENTER", 30, -40 })
        t.eq(p2.panel.shown, true)
    end,

    ["drag: a drop off the screen is saved back on it"] = function(t)
        local _, c, p = start({ screen = { 1024, 768 } })
        login(c)
        p.panel.drag({ "BOTTOMLEFT", "BOTTOMLEFT", -90, 5000 })
        t.eq(savedPanel(c).point, { "BOTTOMLEFT", "BOTTOMLEFT", 0, 768 - P.HEIGHT })
        t.eq(p.panel.point, { "BOTTOMLEFT", "BOTTOMLEFT", 0, 768 - P.HEIGHT })
    end,

    ["drag: a point the client reports badly is not saved"] = function(t)
        local _, c, p = start({ screen = { 1024, 768 } })
        login(c)
        p.panel.drag({ "NOWHERE", "CENTER", 1, 1 })
        p.panel.drag({ "CENTER", "CENTER", 0 / 0, 1 })
        t.eq(savedPanel(c), nil)
    end,

    ["drag: before login nothing is saved"] = function(t)
        local _, c, p = start({ screen = { 1024, 768 } })
        p.panel.drag({ "CENTER", "CENTER", 30, -40 })
        t.eq(c.savedExists(ns.id.accountDB), false)
    end,

    ["restore: a saved point off the screen is clamped, the saved data is left alone"] = function(t)
        local db = { layout = { [PATH] = { point = { "TOPLEFT", "TOPLEFT", 5000, -5000 } } } }
        local _, c, p = start({ screen = { 1024, 768 }, saved = db })
        login(c)
        t.eq(p.panel.point, { "TOPLEFT", "TOPLEFT", 1024 - P.WIDTH, -(768 - P.HEIGHT) })
        t.eq(savedPanel(c).point, { "TOPLEFT", "TOPLEFT", 5000, -5000 })
    end,

    ["restore: an unknown screen size leaves the point as saved"] = function(t)
        local db = { layout = { [PATH] = { point = { "TOPLEFT", "TOPLEFT", 5000, -5000 } } } }
        local _, c, p = start({ saved = db })
        login(c)
        t.eq(p.panel.point, { "TOPLEFT", "TOPLEFT", 5000, -5000 })
        p.panel.drag({ "CENTER", "CENTER", 9000, 0 })
        t.eq(savedPanel(c).point, { "CENTER", "CENTER", 9000, 0 }, "a drag is saved unclamped too")
    end,

    ["restore: unusable saved data reads as the default"] = function(t)
        local db = { layout = { [PATH] = { point = { "TOP", "TOP", "left", 1 }, hidden = "yes" } } }
        local _, c, p = start({ screen = { 1024, 768 }, saved = db })
        login(c)
        t.eq(p.panel.point, P.DEFAULT_POINT)
        t.eq(p.panel.shown, true)
        local _, c2, p2 = start({ saved = { layout = { [PATH] = 7 } } })
        login(c2)
        t.eq(p2.panel.point, P.DEFAULT_POINT)
    end,

    ["slash: panel hides and shows, saved, and a hidden panel stays hidden next start"] = function(t)
        local _, c, p = start({ screen = { 1024, 768 } })
        login(c)
        local run = c.slashes[ns.id.slash]
        run("panel")
        t.eq(p.panel.shown, false)
        t.eq(savedPanel(c), { hidden = true })
        t.ok(c.printed[#c.printed]:find("hidden", 1, true), c.printed[#c.printed])
        local _, c2, p2 = start({ saved = c.saved(ns.id.accountDB) })
        login(c2)
        t.eq(p2.panel.shown, false)
        run(" PANEL ")
        t.eq(p.panel.shown, true)
        t.eq(savedPanel(c), nil, "shown at the default is the default: nothing kept")
    end,

    ["slash: panel reset goes back to the default point and keeps hidden"] = function(t)
        local _, c, p = start({ screen = { 1024, 768 } })
        login(c)
        local run = c.slashes[ns.id.slash]
        p.panel.drag({ "CENTER", "CENTER", 30, -40 })
        run("panel")
        t.eq(savedPanel(c), { point = { "CENTER", "CENTER", 30, -40 }, hidden = true })
        run("panel reset")
        t.eq(p.panel.point, P.DEFAULT_POINT)
        t.eq(savedPanel(c), { hidden = true })
        t.eq(p.panel.shown, false)
    end,

    ["slash: an unknown word after panel changes nothing; diag still works"] = function(t)
        local _, c, p = start()
        login(c)
        local run = c.slashes[ns.id.slash]
        run("panel sideways")
        t.eq(p.panel.shown, true)
        t.eq(savedPanel(c), nil)
        run("diag")
        t.eq(c.saved(ns.id.accountDB).diag.count, 2)
    end,

    ["slash: before login the panel is not toggled or saved"] = function(t)
        local _, c, p = start()
        c.slashes[ns.id.slash]("panel")
        t.eq(p.panel.shown, false)
        t.eq(c.savedExists(ns.id.accountDB), false)
    end,

    ["paused: the panel is shown and says why; its place is still kept"] = function(t)
        local k, c, p = start({ predecessor = true, screen = { 1024, 768 } })
        login(c)
        t.eq(k.paused, true)
        t.eq(p.panel.shown, true)
        t.ok(has(p.panel.lines, "Paused: " .. k.pausePanel.text), table.concat(p.panel.lines, " | "))
        p.panel.drag({ "CENTER", "CENTER", 5, 5 })
        t.eq(savedPanel(c).point, { "CENTER", "CENTER", 5, 5 })
        t.eq(c.savedExists(ns.id.predecessorDB), false, "the predecessor's data is never touched")
        t.eq(k.store.opened, false, "the paused addon still opens no store")
    end,

    ["no frames: no error, nothing saved, the slash says so"] = function(t)
        local k, c, p = start({ noFrames = true })
        t.eq(p.panel, nil)
        login(c)
        c.setCombat(true)
        c.advance(10, 5)
        p.refresh()
        c.slashes[ns.id.slash]("panel")
        t.ok(c.printed[#c.printed]:find("cannot draw", 1, true), c.printed[#c.printed])
        c.slashes[ns.id.slash]("panel reset")
        t.eq(savedPanel(c), nil)
        t.eq(k.problems:count(), 0)
        t.eq(c.ticking(), false)
    end,

    ["lines: title and version, state, error and snapshot counts, combat"] = function(t)
        local k, c, p, d = start()
        c.setVersion("0.1.0")
        c.raise("a.lua:1: boom")
        c.raise("a.lua:1: boom")
        c.raise("b.lua:2: bang")
        login(c)
        d.snapshot("again")
        t.eq(P.Lines(k, d), { ns.id.title .. " 0.1.0", "State: running", "Lua errors: 2 (3 times)",
            "Snapshots: 2", "Problems: 0", "Out of combat" })
        t.eq(p.panel.lines[3], "Lua errors: 2 (3 times)")
        c.setCombat(true)
        t.eq(p.panel.lines[#p.panel.lines], "In combat", "combat starting rewrites the text at once")
    end,

    ["lines: an unknown version is left out; without diag there are no counts"] = function(t)
        local k, c, p = start({ noDiag = true })
        login(c)
        t.eq(P.Lines(k, nil), { ns.id.title, "State: running", "Problems: 0", "Out of combat" })
        t.eq(p.panel.lines[1], ns.id.title)
        t.eq(c.slashes[ns.id.slash], nil, "without the collector there is no slash command to extend")
    end,

    ["refresh: the text follows new errors on the slow tick, and not while hidden"] = function(t)
        local _, c, p = start()
        login(c)
        t.eq(p.panel.lines[3], "Lua errors: 0")
        c.raise("late.lua:9: oops")
        c.advance(0.5, 5)
        t.eq(p.panel.lines[3], "Lua errors: 0", "not before the refresh interval")
        c.advance(0.6, 6)
        t.eq(p.panel.lines[3], "Lua errors: 1")
        c.advance(8, 8)
        c.slashes[ns.id.slash]("panel")
        t.eq(c.ticking(), false, "a hidden panel costs nothing per frame, once the settled snapshot is taken")
        c.slashes[ns.id.slash]("panel")
        t.eq(c.ticking(), true)
    end,

    ["real client: an environment with no frames gives no panel and no screen"] = function(t)
        local c = ns.make.client({})
        t.eq(c.panel({ width = 10, height = 10 }), nil)
        t.eq(c.screen(), nil)
        t.eq(c.version("Anything"), nil)
        local broken = ns.make.client({ CreateFrame = function() error("no") end, UIParent = {} })
        t.eq(broken.panel({}), nil)
        t.eq(broken.screen(), nil)
    end,

    ["real client: a frame with no methods at all still gives a harmless handle"] = function(t)
        local c = ns.make.client({ CreateFrame = function() return {} end })
        local h = c.panel({ width = 10, height = 10 })
        t.eq(type(h), "table")
        h.setLines({ "a", "b" })
        h.place({ "CENTER", "CENTER", 0, 0 })
        h.show(true)
        h.onMoved(function() end)
    end,

    ["real client: the panel drives the frame and reports a drag as plain data"] = function(t)
        local made = {}
        local function widget()
            local w = { calls = {} }
            return setmetatable(w, { __index = function(_, name)
                return function(_, ...) w.calls[#w.calls + 1] = { name, ... } end
            end })
        end
        local env = { UIParent = { GetWidth = function() return 1024 end, GetHeight = function() return 768 end } }
        local frame = { scripts = {}, points = {}, shown = true }
        function frame:Hide() self.shown = false end
        function frame:Show() self.shown = true end
        function frame:SetWidth(w) self.w = w end
        function frame:SetHeight(h) self.h = h end
        function frame:SetScript(name, fn) self.scripts[name] = fn end
        function frame:ClearAllPoints() self.points = {} end
        function frame:SetPoint(a, rel, r, x, y) self.points[#self.points + 1] = { a, rel, r, x, y } end
        function frame:GetPoint() return "TOPLEFT", nil, "TOPLEFT", 12, -34 end
        function frame:StartMoving() self.moving = true end
        function frame:StopMovingOrSizing() self.moving = false end
        function frame:CreateFontString() made.text = widget() return made.text end
        function env.CreateFrame(kind, name, parent)
            made.args = { kind, name, parent }
            return frame
        end
        local c = ns.make.client(env)
        t.eq({ c.screen() }, { 1024, 768 })
        local h = c.panel({ name = "TestPanel", width = 250, height = 84 })
        t.eq(made.args, { "Frame", "TestPanel", env.UIParent })
        t.eq({ frame.w, frame.h, frame.shown }, { 250, 84, false }, "no SetSize: width and height are set apart")
        h.setLines({ "one", "two" })
        local last = made.text.calls[#made.text.calls]
        t.eq(last, { "SetText", "one\ntwo" })
        h.place({ "CENTER", "CENTER", 3, 4 })
        t.eq(frame.points, { { "CENTER", env.UIParent, "CENTER", 3, 4 } })
        h.show(true)
        t.eq(frame.shown, true)
        local got
        h.onMoved(function(point) got = point end)
        -- Called with no arguments and with the frame: the handlers use neither.
        frame.scripts.OnDragStart()
        t.eq(frame.moving, true)
        frame.scripts.OnDragStop(frame)
        t.eq(frame.moving, false)
        t.eq(got, { "TOPLEFT", "TOPLEFT", 12, -34 })
        frame.GetPoint = nil
        function frame:GetLeft() return 100 end
        function frame:GetBottom() return 200 end
        frame.scripts.OnDragStop()
        t.eq(got, { "BOTTOMLEFT", "BOTTOMLEFT", 100, 200 }, "no GetPoint: the left and bottom edge is used")
        frame.GetLeft = nil
        got = nil
        frame.scripts.OnDragStop()
        t.eq(got, nil, "a client that will not say where the frame is reports no move")
    end,
}

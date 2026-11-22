-- What a click, a right click and the pointer over an arrow do (inventory
-- rows 42, 45 to 50; LEDGER 65 AM5, AM10): the menu with Restack and Reset,
-- the style rows, the tooltip, and the needle's own click and hover. Over
-- the fake client; no game client. h.click, h.hover and h.choose are the
-- fake's controls: what the player's hand does.
local _, ns = ...

local A = ns.Arrow
local N = ns.Nav

-- opts: saved (the account table), lines = false (the client draws no
-- lines), demo = false (no demo: no arrow has a step).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    local saved = opts.saved or {}
    if type(saved.layout) ~= "table" then saved.layout = {} end
    saved.layout.arrowIntroSeen = true
    c.setSaved(ns.id.accountDB, saved)
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFacing(0)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    if opts.lines == false and type(c.setLines) == "function" then c.setLines(false) end
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local a = A.Declare(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    if opts.demo ~= false then
        d.commands.arrow("demo")
        c.advance(0.1, 2)
    end
    return k, c, a, d
end

-- The saved layout as the arrows read it.
local function saved(k)
    return N.ArrowSaved({ arrows = k.settings:get(A.SETTING) })
end

local function row(items, key)
    for i = 1, #(items or {}) do
        if items[i].key == key then return items[i] end
    end
    return nil
end

local function hasLine(lines, text)
    for i = 1, #(lines or {}) do
        if tostring(lines[i]):find(text, 1, true) then return true end
    end
    return false
end

-- The tests below need the fake's hand; without it each fails here.
local function has(t, c)
    local q, p = c.arrows[1], c.arrows[2]
    local ok = q ~= nil and p ~= nil and type(q.click) == "function" and type(q.hover) == "function"
        and type(q.choose) == "function" and type(p.click) == "function"
    t.ok(ok, "the fake arrows can be clicked, hovered and chosen from")
    return ok
end

return {
    ["right click: the menu opens with Restack, Reset and the style rows"] = function(t)
        local k, c = start()
        if not has(t, c) then return end
        local q = c.arrows[1]
        t.eq(q.menuItems, nil, "no menu before the click")
        q.click("right")
        t.ok(type(q.menuItems) == "table", "the menu is open on the quest arrow")
        t.ok(row(q.menuItems, "restack") ~= nil, "Restack")
        t.ok(row(q.menuItems, "reset") ~= nil, "Reset")
        for _, key in ipairs({ "modern", "3d", "flat" }) do
            t.ok(row(q.menuItems, "style." .. key) ~= nil, "style " .. key)
        end
        t.eq(row(q.menuItems, "style.modern").checked, true, "the style in use is marked")
        t.eq(k.problems:count(), 0)
    end,

    ["right click: choosing Separate, then Restack, moves the saved mode both ways (AM10)"] = function(t)
        local k, c = start()
        if not has(t, c) then return end
        local q = c.arrows[1]
        q.click("right")
        t.eq(row(q.menuItems, "restack").disabled, true, "already stacked")
        q.choose("separate")
        t.eq(saved(k).mode, "separate")
        t.eq(q.menuItems, nil, "a choice closes the menu")
        q.click("right")
        t.ok(not row(q.menuItems, "restack").disabled, "Restack is offered once they are apart")
        q.choose("restack")
        t.eq(saved(k).mode, "stacked")
        t.eq(k.problems:count(), 0)
    end,

    ["right click: Reset puts a moved arrow back"] = function(t)
        local k, c = start()
        if not has(t, c) then return end
        local q = c.arrows[1]
        q.drag({ "CENTER", "CENTER", 200, 100 })
        t.ok(saved(k).points.quest ~= nil, "the drag was saved")
        q.click("right")
        q.choose("reset")
        t.eq(saved(k).points.quest, nil, "no saved place: the first one again")
        t.eq(saved(k).mode, "stacked")
        t.eq(k.problems:count(), 0)
    end,

    ["right click: the text row turns the arrow's text off and on"] = function(t)
        local k, c = start()
        if not has(t, c) then return end
        local q = c.arrows[1]
        t.ok(#q.lines > 0, "text to begin with")
        q.click("right")
        t.eq(row(q.menuItems, "text.quest").checked, true)
        q.choose("text.quest")
        t.eq(saved(k).text.quest, false)
        t.ok(not hasLine(q.lines, "Demo: north"), "the quest lines are gone")
        q.click("right")
        t.eq(row(q.menuItems, "text.quest").checked, false, "the tick follows what is saved")
        q.choose("text.quest")
        t.eq(saved(k).text.quest, nil)
        t.ok(hasLine(q.lines, "Demo: north"), "and back")
        t.eq(k.problems:count(), 0)
    end,

    ["right click: the show row hides the needle and shows it again"] = function(t)
        local k, c = start()
        if not has(t, c) then return end
        local q, p = c.arrows[1], c.arrows[2]
        t.eq(p.shown, true)
        q.click("right")
        q.choose("show.prof")
        t.eq(saved(k).hidden.prof, true)
        t.eq(p.shown, false)
        q.click("right")
        t.eq(row(q.menuItems, "show.prof").checked, false)
        q.choose("show.prof")
        t.eq(saved(k).hidden.prof, nil)
        t.eq(p.shown, true)
        t.eq(k.problems:count(), 0)
    end,

    ["right click: a style row changes the style drawn"] = function(t)
        local k, c, a = start()
        if not has(t, c) then return end
        local q = c.arrows[1]
        q.click("right")
        q.choose("style.flat")
        t.eq(a.style(), "flat")
        t.eq(k.store:get("account", "layout.arrowStyle"), "flat")
        q.click("right")
        t.eq(row(q.menuItems, "style.flat").checked, true)
        t.eq(row(q.menuItems, "style.modern").checked, false)
        t.eq(k.problems:count(), 0)
    end,

    ["right click: a client that draws no lines keeps the modern arrow"] = function(t)
        local k, c, a = start({ lines = false })
        if not has(t, c) then return end
        local q = c.arrows[1]
        q.click("right")
        t.eq(row(q.menuItems, "style.flat").disabled, true)
        q.choose("style.flat")
        t.eq(a.style(), "modern")
        t.eq(k.store:get("account", "layout.arrowStyle"), nil, "nothing saved")
        t.eq(k.problems:count(), 0)
    end,

    ["right click: a key the menu does not have changes nothing"] = function(t)
        local k, c = start()
        if not has(t, c) then return end
        local q = c.arrows[1]
        local before = k.settings:get(A.SETTING)
        q.click("right")
        q.choose("cast")
        q.click("right")
        q.choose(nil)
        t.eq(k.settings:get(A.SETTING), before)
        t.eq(k.problems:count(), 0)
    end,

    ["left click: with no drawer, nothing visible happens"] = function(t)
        local k, c = start()
        if not has(t, c) then return end
        local q = c.arrows[1]
        local before, printed, draws = k.settings:get(A.SETTING), #c.printed, q.draws
        q.click("left")
        t.eq(q.menuItems, nil, "no menu")
        t.eq(#c.printed, printed, "nothing said")
        t.eq(k.settings:get(A.SETTING), before, "nothing saved")
        t.eq(q.shown, true, "the arrow stays")
        t.eq(q.draws, draws, "nothing redrawn")
        t.eq(k.problems:count(), 0)
    end,

    ["left click: a drawer that was set is opened for the arrow clicked"] = function(t)
        local k, c, a = start({ saved = { layout = { arrows = { mode = "separate" } } } })
        if not has(t, c) then return end
        t.ok(type(a.setDrawer) == "function", "the arrows take a drawer")
        if type(a.setDrawer) ~= "function" then return end
        local opened = {}
        a.setDrawer(function(key) opened[#opened + 1] = key end)
        c.arrows[1].click("left")
        c.arrows[2].click("left")
        c.arrows[1].click("right")
        t.eq(opened, { "quest", "prof" }, "a left click each, the right click opens no drawer")
        a.setDrawer(nil)
        c.arrows[1].click("left")
        t.eq(#opened, 2, "taken away again")
        t.eq(k.problems:count(), 0)
    end,

    ["left click: a drawer that breaks is the arrows' problem, and the arrows stay"] = function(t)
        local k, c, a = start()
        if not has(t, c) then return end
        if type(a.setDrawer) ~= "function" then
            t.ok(false, "the arrows take a drawer")
            return
        end
        a.setDrawer(function() error("drawer broke") end)
        t.ok(pcall(c.arrows[1].click, "left"), "the error is not thrown at the client")
        t.eq(k.problems:count("arrow"), 1)
        t.eq(c.arrows[1].shown, true)
        t.eq(k:ModuleState(A.NAME), "started")
    end,

    ["a button that is neither left nor right does nothing"] = function(t)
        local k, c = start()
        if not has(t, c) then return end
        local q = c.arrows[1]
        q.click("middle")
        q.click(nil)
        t.eq(q.menuItems, nil)
        t.eq(k.problems:count(), 0)
    end,

    ["hover: the tooltip names the arrow, gives its lines and the hint; leaving takes it away"] = function(t)
        local k, c = start({ saved = { layout = { arrows = { mode = "separate" } } } })
        if not has(t, c) then return end
        local q = c.arrows[1]
        t.eq(q.tipLines, nil, "no tooltip before the pointer is there")
        q.hover(true)
        t.ok(type(q.tipLines) == "table", "a tooltip")
        if type(q.tipLines) ~= "table" then return end
        t.eq(q.tipLines[1], "Quest arrow")
        t.ok(hasLine(q.tipLines, "Demo: north"), "the step's lines")
        t.ok(not hasLine(q.tipLines, "Demo: east"), "not the needle's when they are apart")
        t.ok(hasLine(q.tipLines, "Right-click"), "the hint")
        t.ok(not hasLine(q.tipLines, "Click: details"), "no drawer is promised while there is none")
        q.hover(false)
        t.eq(q.tipLines, nil)
        t.eq(k.problems:count(), 0)
    end,

    ["hover: stacked, the quest arrow's tooltip carries the needle's lines"] = function(t)
        local k, c = start()
        if not has(t, c) then return end
        local q = c.arrows[1]
        t.eq(c.arrows[2].under, true, "the needle is under the quest arrow and takes no mouse")
        q.hover(true)
        t.ok(hasLine(q.tipLines, "Demo: north"))
        t.ok(hasLine(q.tipLines, "Profession arrow"))
        t.ok(hasLine(q.tipLines, "Demo: east"))
        t.eq(k.problems:count(), 0)
    end,

    ["hover: the tooltip still gives the lines of an arrow whose text is off"] = function(t)
        local k, c = start({ saved = { layout = { arrows = { text = { quest = false } } } } })
        if not has(t, c) then return end
        local q = c.arrows[1]
        t.ok(not hasLine(q.lines, "Demo: north"), "no text by the arrow")
        q.hover(true)
        t.ok(hasLine(q.tipLines, "Demo: north"), "but in the tooltip")
        t.eq(k.problems:count(), 0)
    end,

    ["hover: a drawer that was set is promised in the hint"] = function(t)
        local _, c, a = start()
        if not has(t, c) then return end
        if type(a.setDrawer) ~= "function" then
            t.ok(false, "the arrows take a drawer")
            return
        end
        a.setDrawer(function() end)
        c.arrows[1].hover(true)
        t.ok(hasLine(c.arrows[1].tipLines, "Click: details"))
    end,

    ["needle: apart from the quest arrow it has its own menu and tooltip"] = function(t)
        local k, c = start({ saved = { layout = { arrows = { mode = "separate" } } } })
        if not has(t, c) then return end
        local q, p = c.arrows[1], c.arrows[2]
        t.eq(p.under, false, "the needle takes the mouse")
        p.hover(true)
        t.ok(type(p.tipLines) == "table", "a tooltip on the needle")
        if type(p.tipLines) == "table" then
            t.eq(p.tipLines[1], "Profession arrow")
            t.ok(hasLine(p.tipLines, "Demo: east"))
            t.ok(not hasLine(p.tipLines, "Demo: north"))
        end
        t.eq(q.tipLines, nil, "none on the quest arrow")
        p.hover(false)
        t.eq(p.tipLines, nil)
        p.click("right")
        t.ok(type(p.menuItems) == "table", "the menu opens on the needle")
        t.eq(q.menuItems, nil)
        p.choose("restack")
        t.eq(saved(k).mode, "stacked", "the needle's menu restacks them")
        t.eq(k.problems:count(), 0)
    end,

    ["a click opens a menu and closes the tooltip under it"] = function(t)
        local _, c = start()
        if not has(t, c) then return end
        local q = c.arrows[1]
        q.hover(true)
        q.click("right")
        t.eq(q.tipLines, nil, "the tooltip is not left over the menu")
        t.ok(type(q.menuItems) == "table")
    end,

    ["switched off: a click or the pointer does nothing"] = function(t)
        local k, c = start()
        if not has(t, c) then return end
        local q = c.arrows[1]
        k:SwitchOff(A.NAME, "test")
        local problems = k.problems:count()
        q.click("right")
        q.click("left")
        q.hover(true)
        t.eq(q.menuItems, nil)
        t.eq(q.tipLines, nil)
        t.eq(k.problems:count(), problems, "and nothing new goes wrong")
    end,

    ["the arrows answer menu and tip for whoever asks"] = function(t)
        local _, c, a = start()
        if not has(t, c) then return end
        t.ok(type(a.menu) == "function" and type(a.tip) == "function", "menu and tip")
        if type(a.menu) ~= "function" or type(a.tip) ~= "function" then return end
        t.ok(row(a.menu(), "restack") ~= nil)
        t.eq(a.tip("quest")[1], "Quest arrow")
        t.eq(a.tip("pet"), nil)
    end,

    ["on a kernel that never starts the arrows, menu, tip and drawer are safe"] = function(t)
        local c = ns.make.fakeClient()
        local k = ns.Kernel({}, c)
        local d = ns.Diag.Start(k)
        local a = A.Declare(k, d)
        t.ok(type(a.menu) == "function" and type(a.tip) == "function" and type(a.setDrawer) == "function",
            "menu, tip and setDrawer")
        if type(a.menu) ~= "function" or type(a.tip) ~= "function" or type(a.setDrawer) ~= "function" then return end
        t.ok(type(a.menu()) == "table")
        t.eq(a.tip("quest"), nil, "no arrow, no tooltip")
        t.ok(pcall(a.setDrawer, function() end))
        t.eq(#c.arrows, 0)
    end,
}

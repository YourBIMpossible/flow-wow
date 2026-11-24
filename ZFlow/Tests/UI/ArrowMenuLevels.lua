-- Menus in short levels (lead section 239, row N57): the arrows' menu is a
-- tree, shown one level at a time, and no level of any menu holds more than
-- Topics.MENU_MAX rows. The tree and its levels are UI/ArrowMenu.lua's; the
-- clicks go through the fake client's arrow. Fake client; not tested in game.
local _, ns = ...

local M = ns.ArrowMenu
local A = ns.Arrow
local T = ns.Settings and ns.Settings.Topics

-- Every menu the add-on has, by name: the rows of its whole tree for a
-- state. There is one today, opened by a right click on either arrow and
-- by the world-map button. A new menu is added here.
local MENUS = {
    arrow = function(state) return M.Items(state) end,
}

local function state(over)
    -- feedback: the feedback is reachable (paused by lead section 284; on here).
    local s = { stacked = true, hidden = {}, text = {}, styles = A.Styles("modern"), canShapes = true, feedback = true }
    for key, v in pairs(over or {}) do s[key] = v end
    return s
end

local function rowAt(items, key)
    for _, r in ipairs(items or {}) do
        if r.key == key then return r end
    end
    return nil
end

local function has(t)
    local ok = type(T) == "table" and type(M.Level) == "function" and type(M.Counts) == "function"
    t.ok(ok, "the topics list and ArrowMenu's Level and Counts are there")
    return ok
end

local function start()
    -- The feedback row needs the feedback reachable: paused by lead section
    -- 284, on here through the fake client internal switch and declared.
    local c = ns.make.fakeClient({ internal = { feedback = true } })
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFacing(0)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local a = A.Declare(k, d)
    ns.Feedback.Declare(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    d.commands.arrow("demo")
    c.advance(0.1, 2)
    return k, c, a
end

return {
    -- Fails before: ArrowMenu.Counts is absent; the menu was one flat list
    -- that grew with every style and arrow (12 rows with three styles).
    ["menu size: no level of any menu holds more than the fixed number of rows"] = function(t)
        if not has(t) then return end
        t.ok(T.MENU_MAX <= 10, "the number is 10 or less: " .. tostring(T.MENU_MAX))
        local states = { state(), state({ stacked = false }), state({ canShapes = false }),
            state({ hidden = { quest = true, prof = true }, text = { quest = false, prof = false } }) }
        for name, build in pairs(MENUS) do
            for s = 1, #states do
                local levels = M.Counts(build(states[s]))
                t.ok(#levels >= 2, name .. " has a top level and at least one submenu")
                for _, level in ipairs(levels) do
                    t.ok(level.rows <= T.MENU_MAX,
                        name .. " / " .. level.path .. ": " .. level.rows .. " rows, the most is " .. T.MENU_MAX)
                    t.ok(level.rows >= 1, name .. " / " .. level.path .. " is not empty")
                end
            end
        end
    end,

    -- The check above can fail: a level one row too long is counted as such.
    ["menu size: a level that is too long is counted as too long"] = function(t)
        if not has(t) then return end
        local long = {}
        for i = 1, T.MENU_MAX + 1 do long[i] = { key = "row" .. i, text = "Row " .. i } end
        t.eq(M.Counts(long), { { path = "top", rows = T.MENU_MAX + 1 } })
        local styles = {}
        for i = 1, T.MENU_MAX do styles[i] = { key = "s" .. i, label = "Style " .. i, on = i == 1 } end
        local over
        for _, level in ipairs(M.Counts(M.Items(state({ styles = styles })))) do
            if level.path == "style" then over = level.rows end
        end
        t.eq(over, T.MENU_MAX + 2, "ten styles, their heading and the way back: over, and the size test would say so")
    end,

    -- Fails before: the top level held every row (Restack, Separate, ...).
    ["menu: the top level is a few headings and the settings rows; each heading holds its own short list"] = function(t)
        if not has(t) then return end
        local items = M.Items(state())
        local top = M.Level(items)
        local keys = {}
        for i, r in ipairs(top) do keys[i] = r.sep and "-" or r.key end
        t.eq(keys, { "step", "layout", "show", "style", "dungeons", "-", "settings.travel", "settings", "feedback" })
        t.eq(rowAt(top, "dungeons").text, T.MENU.dungeons, "lead section 318: the Dungeon Quests window")
        t.eq(M.Action("dungeons", state()), { window = "dungeonWindow" })
        t.eq(rowAt(top, "feedback").text, T.MENU.feedback, "row N73: the feedback window")
        t.eq(rowAt(top, "layout").text, T.MENU.layout .. M.MORE)
        t.eq(rowAt(top, "layout").more, true)
        t.eq(rowAt(top, "settings").more, nil, "the settings row opens the page, not a level")
        t.eq(rowAt(top, "settings.travel").text, T.Find("travel").name .. T.MENU.topicSettings,
            "named from the same list as the settings page")
        t.eq(rowAt(top, "restack"), nil, "a submenu's row is not on the top level")

        local layout = M.Level(items, { "layout" })
        keys = {}
        for i, r in ipairs(layout) do keys[i] = r.title and "#" .. r.text or r.key end
        t.eq(keys, { "#" .. T.MENU.layout, "restack", "separate", "reset", M.BACK })
        local show = M.Level(items, { "show" })
        t.eq(#show, 9, "Professions tick (lead section 382), Buttons and Flow windows (lead section 387 R3)")
        t.eq(rowAt(show, "show.prof").checked, true)
        local style = M.Level(items, { "style" })
        t.eq(rowAt(style, "style.modern").checked, true)
        t.eq(rowAt(style, "style.modern").radio, true)
        t.eq(#M.Level(items, { "nosuch" }), #top, "a path that leads nowhere is the top level")
    end,

    -- Fails before: ArrowMenu.Action knows no level and no settings row.
    ["action: a heading opens its level, back opens the top, a settings row asks for the page"] = function(t)
        if not has(t) then return end
        t.eq(M.Action("layout", state()), { open = "layout" })
        t.eq(M.Action("show", state()), { open = "show" })
        t.eq(M.Action("style", state()), { open = "style" })
        t.eq(M.Action("style", state({ styles = {} })), nil, "no styles: no such level")
        t.eq(M.Action(M.BACK, state()), { open = false })
        t.eq(M.Action("settings.travel", state()), { settings = "travel" })
        t.eq(M.Action("settings", state()), { settings = true })
        t.eq(M.Action("settings.nosuch", state()), nil)
        t.eq(M.Action("feedback", state()), { feedback = true })
        t.eq(M.Action("settings.travel.arrow", state()), nil, "a topic, not a section")
        -- A leaf asks what it always asked.
        t.eq(M.Action("reset", state()), { op = "reset" })
        t.eq(M.Action("style.flat", state()), { style = "flat" })
    end,

    -- Fails before: Core/ClientFake.lua's arrow has no enter / pickRow, and
    -- UI/Arrow.lua shows no level.
    ["menu on the arrow: a right click opens the top level, a heading its level, a row there is chosen"] = function(t)
        if not has(t) then return end
        local k, c = start()
        local q = c.arrows[1]
        t.ok(type(q.enter) == "function" and type(q.pickRow) == "function", "the fake arrow has submenu rows")
        if type(q.enter) ~= "function" then return end
        q.click("right")
        t.eq(#q.menuItems, 9, "the step row (lead section 387), seven rows and the Dungeon quests row (lead section 318)")
        t.eq(q.menuDepth, 0)
        t.eq(q.pickRow("separate"), false, "not offered on the top level")
        t.eq(q.enter("settings"), false, "not a submenu row")
        q.click("right")
        t.eq(q.enter("layout"), true)
        t.eq(q.menuDepth, 1)
        t.eq(q.menuItems[1], { title = true, text = T.MENU.layout })
        t.eq(q.pickRow("restack"), false, "greyed while stacked: not taken")
        t.eq(q.pickRow("separate"), true)
        t.eq(q.menuItems, nil, "a choice closes the menu")
        t.eq(ns.Nav.ArrowSaved({ arrows = k.settings:get(A.SETTING) }).mode, "separate")
        -- And back.
        q.click("right")
        t.eq(q.enter("show"), true)
        t.eq(q.pickRow(M.BACK), true)
        t.eq(#q.menuItems, 9, "the top level again (with the step row, lead section 387, and the Dungeon quests row, lead section 318)")
        t.ok(rowAt(q.menuItems, "layout") ~= nil)
        t.eq(k.problems:count(), 0)
    end,

    -- Fails before: no settings row in the menu.
    ["menu on the arrow: the settings row with no settings page says so and changes nothing"] = function(t)
        if not has(t) then return end
        local k, c = start()
        local q = c.arrows[1]
        if type(q.pickRow) ~= "function" then
            t.ok(false, "the fake arrow has no pickRow")
            return
        end
        local before = k.settings:get(A.SETTING)
        local n = #c.printed
        q.click("right")
        t.eq(q.pickRow("settings.travel"), true)
        t.eq(#c.printed, n + 1, "one line: this kernel has no settings page declared")
        t.eq(k.settings:get(A.SETTING), before)
        t.eq(k.problems:count(), 0)
    end,
}

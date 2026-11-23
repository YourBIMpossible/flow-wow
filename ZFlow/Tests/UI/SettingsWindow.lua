-- The settings window as the kit draws it (UI/SettingsWindow.lua; lead
-- sections 285 item 3 and 303): the tree handed to client.kitWindow, and
-- the player's clicks on it played by the fake client's kit controls
-- (kitClick, kitSelect, kitType). A real kernel on the fake client;
-- hand-made rows only. No frame is looked at. Not tested in game.
local _, ns = ...

local O = ns.SettingsOptions
local W = ns.SettingsWindow
local T = ns.Settings.Topics

local function start()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    k:Setting({ key = "test.flag", scope = "account", type = "bool", default = true, label = "A flag",
        help = "What the flag does.", group = "advanced" })
    k:Setting({ key = "test.mode", scope = "char", type = "choice", choices = { "low", "high" }, default = "low",
        label = "A mode", group = "advanced" })
    k:Setting({ key = "test.count", scope = "account", type = "number", min = 1, max = 3, default = 2,
        label = "A count", group = "advanced" })
    k:Setting({ key = "test.held", scope = "account", type = "bool", default = true, label = "Held back",
        group = "advanced", requires = function() return false, "not while testing" end })
    k:Setting({ key = "sell.list", scope = "account", type = "bool", default = true, label = "Show the sell list",
        group = "bags", synonyms = { "junk" } })
    ns.SettingsPanel.Declare(k, d)
    local api = O.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api
end

local function window(c) return (c.kitWindows() or {})[W.ID] end

-- The words of every part of that kind, in drawing order.
local function texts(c, kind)
    local out = {}
    local w = window(c)
    for _, part in ipairs(w and w.parts or {}) do
        if part.kind == kind then out[#out + 1] = part.text end
    end
    return out
end

local function count(c, kind)
    local n = 0
    local w = window(c)
    for _, part in ipairs(w and w.parts or {}) do
        if part.kind == kind then n = n + 1 end
    end
    return n
end

local function topicAt(c, id)
    for i, topic in ipairs(c.optionsLayout().topics) do
        if topic.id == id then return i end
    end
    return nil
end

return {
    ["settings window: one kit window, 760 by 520, the topic list at the left and one scroll of rows"] = function(t)
        local _, c, api = start()
        t.eq(window(c), nil, "nothing is made before it is asked for")
        t.eq(api.open({ topic = "advanced" }), true)
        local w = window(c)
        t.ok(w ~= nil, "the window is a kit window")
        if not w then return end
        t.eq({ w.shown, w.width, w.height }, { true, W.WIDTH, W.HEIGHT })
        t.eq({ W.WIDTH, W.HEIGHT }, { 760, 520 })
        t.eq({ w.parts[1].kind, w.parts[2].kind, w.parts[3].kind }, { "header", "topicList", "scroll" })
        t.eq(w.parts[1].text, "2 topics", "the header says how many topics")
        t.eq({ count(c, "header"), count(c, "topicList"), count(c, "scroll"), count(c, "footer") }, { 1, 1, 1, 0 },
            "one of each, and no footer: there is no Save button")
        t.eq(texts(c, "section"), { T.Find("advanced").name }, "the topic's name is the one heading of a small topic")
        t.eq(texts(c, "row"), { "A flag", "A mode", "A count", "Held back" })
        t.eq({ count(c, "checkbox"), count(c, "choice"), count(c, "number") }, { 2, 1, 1 })
    end,

    ["settings window: a click on a check box, a choice and a number each change the setting at once"] = function(t)
        local k, c, api = start()
        api.open({ topic = "advanced" })
        t.eq(c.kitClick(W.ID, "test.flag"), true)
        t.eq(k.settings:get("test.flag"), false, "no Save: it is set by the click")
        t.eq(c.kitClick(W.ID, "test.flag"), true)
        t.eq(k.settings:get("test.flag"), true, "the redrawn box turns it back")
        t.eq(c.kitSelect(W.ID, "test.mode", 2), true)
        t.eq(k.settings:get("test.mode"), "high")
        t.eq(c.kitChange(W.ID, "test.count", 3), true)
        t.eq(k.settings:get("test.count"), 3)
        t.eq(c.kitChange(W.ID, "test.count", 9), false, "outside its limits: the control does not take it")
        t.eq(k.settings:get("test.count"), 3)
    end,

    ["settings window: a row that cannot be set is drawn, and its control takes no click"] = function(t)
        local k, c, api = start()
        api.open({ topic = "advanced" })
        t.eq(c.kitClick(W.ID, "test.held"), false, "greyed")
        t.eq(k.settings:get("test.held"), true)
        local tree = W.Tree(O.Rows(k), function() end, function() end, select(3, O.Rows(k)))
        local held
        ns.Kit.Each(tree, function(part)
            if part.kind == "row" and part.label == "Held back" then held = part end
        end)
        t.ok(held ~= nil, "the row is in the tree")
        if not held then return end
        t.eq(held.enabled, false)
        t.eq(held.reason, ns.SettingsPage.NOT_NOW, "with the reason")
        t.ok(type(held.tooltip) == "string" and held.tooltip:find(O.SAVED_FOR .. "account", 1, true) ~= nil,
            "who it is saved for is in the tooltip: " .. tostring(held.tooltip))
        t.ok(tostring(held.description):find(O.SAVED_FOR, 1, true) == nil, "not on the row")
    end,

    ["settings window: choosing a topic in the list swaps the rows; the search shows hits of every topic under their topics"] = function(t)
        local _, c, api = start()
        api.open()
        t.eq(c.kitSelect(W.ID, W.TOPICS, topicAt(c, "bags")), true)
        t.eq(texts(c, "row"), { "Show the sell list" })
        t.eq(texts(c, "section"), { T.Find("bags").name })
        t.eq(c.kitSelect(W.ID, W.TOPICS, topicAt(c, "advanced")), true)
        t.eq(c.kitType(W.ID, W.HEADER, "junk "), true)
        t.eq(c.optionsLayout().search.value, "junk", "the search is the words")
        t.eq(c.optionsLayout().typed, "junk ", "the box keeps what was typed, the space too")
        t.eq(texts(c, "row"), { "Show the sell list" }, "a row of another topic")
        t.eq(texts(c, "section"), { T.Find("bags").name }, "under its topic's name")
        t.eq(texts(c, "header"), { "1" .. O.FOUND .. '"junk"' }, "the header says what was found")
        t.eq(c.kitClick(W.ID, "sell.list"), true, "a hit is changed where it stands")
        t.eq(c.kitType(W.ID, W.HEADER, ""), true)
        t.eq(texts(c, "section"), { T.Find("advanced").name }, "cleared: the topic shown before")
        t.eq(c.optionsLayout().topic, "advanced")
    end,

    ["settings window: a search that finds nothing says what was searched and how to clear it"] = function(t)
        local _, c, api = start()
        api.open()
        t.eq(c.kitType(W.ID, W.HEADER, "dragons"), true)
        t.eq(count(c, "row"), 0)
        t.eq(texts(c, "empty"), { ns.SettingsPage.NoMatch("dragons") })
        local how
        for _, r in ipairs(c.optionsRows()) do
            if r.kind == "note" then how = r.how end
        end
        t.eq(how, O.NO_MATCH_HOW)
        t.ok(O.NO_MATCH_HOW:find("Clear the search", 1, true) ~= nil, O.NO_MATCH_HOW)
    end,

    ["settings window: the player closing it is seen, and the next ask shows it again where it was"] = function(t)
        local k, c, api = start()
        api.open()
        t.eq(c.kitSelect(W.ID, W.TOPICS, topicAt(c, "bags")), true)
        t.eq(c.kitClose(W.ID), true)
        t.eq(c.optionsShown(), false)
        t.eq(k.settings:set("sell.list", false), true, "a change while it is closed draws nothing and raises nothing")
        t.eq(api.open(), true)
        t.eq(window(c).shown, true)
        t.eq(texts(c, "row"), { "Show the sell list" }, "the topic it was at")
    end,

    ["settings window: moving it saves its place for the account, and a reload puts it there"] = function(t)
        local k, c, api = start()
        api.open()
        t.eq(c.kitDrag(W.ID, { "TOPLEFT", "TOPLEFT", 40, -60 }), true)
        t.eq(k.store:get("account", O.PLACE_PATH), { point = { "TOPLEFT", "TOPLEFT", 40, -60 } })
        local c2 = ns.make.fakeClient()
        c2.setSaved(ns.id.accountDB, c.saved(ns.id.accountDB))
        c2.setSaved(ns.id.charDB, c.saved(ns.id.charDB))
        local k2 = ns.Kernel({}, c2)
        k2:Setting({ key = "sell.list", scope = "account", type = "bool", default = true, label = "Show the sell list",
            group = "bags" })
        local api2 = O.Declare(k2)
        k2:Boot()
        c2.fire("ADDON_LOADED", ns.id.addon)
        c2.fire("PLAYER_LOGIN")
        c2.fire("PLAYER_ENTERING_WORLD")
        t.eq(api2.open(), true)
        t.eq((c2.kitWindows()[W.ID] or {}).point, { "TOPLEFT", "TOPLEFT", 40, -60 })
    end,

    ["settings window: a client that cannot make a kit window gets no window, and open says so by answering false"] = function(t)
        local _, c, api = start()
        c.setKitFails(1)
        t.eq(api.open(), false)
        t.eq(c.optionsShown(), false)
        t.eq(c.optionsRows(), nil, "nothing is kept of a draw that made no window")
        t.eq(api.open(), true, "the next ask makes it")
        t.eq(window(c).shown, true)
    end,
}

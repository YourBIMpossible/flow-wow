-- The settings in two panes (lead section 285 item 3): what
-- UI/SettingsOptions.lua hands the client to draw. The topics are a list
-- beside the rows, the search stands apart, and the pane holds one topic's
-- rows or the search's hits. A real kernel on the fake client; hand-made
-- rows only. No frame is looked at here: this is the model.
local _, ns = ...

local O = ns.SettingsOptions
local P = ns.SettingsPage
local T = ns.Settings.Topics

local LONG = "Shows a list beside the merchant window with every item you might sell and what each "
    .. "would bring, sorted by price, and never sells anything for you."

-- account, char: the saved tables (a second kernel on the same ones is the
-- same player after a reload).
local function start(account, char)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, account or {})
    c.setSaved(ns.id.charDB, char or {})
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    for i = 1, 6 do
        k:Setting({ key = "way.arrow" .. i, scope = "account", type = "bool", default = true,
            label = "Arrow " .. i, group = "travel.arrow" })
    end
    for i = 1, 5 do
        k:Setting({ key = "way.route" .. i, scope = "account", type = "bool", default = true,
            label = "Route " .. i, group = "travel.route" })
    end
    k:Setting({ key = "gear.tip", scope = "account", type = "bool", default = true,
        label = "Gear verdict", group = "gear" })
    k:Setting({ key = "loot.note", scope = "account", type = "bool", default = true,
        label = "Note grey loot", group = "gear.loot" })
    k:Setting({ key = "sell.list", scope = "account", type = "bool", default = true,
        label = "Show the sell list", help = LONG, group = "bags", synonyms = { "junk" } })
    k:Setting({ key = "bank.list", scope = "char", type = "bool", default = true,
        label = "Show the bank list", help = "Short help.", group = "bags" })
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c
end

local function keysOf(rows)
    local out = {}
    for _, r in ipairs(rows or {}) do
        if r.key ~= nil then out[#out + 1] = r.key end
    end
    return out
end

local function rowOf(rows, key)
    for _, r in ipairs(rows or {}) do
        if r.key == key then return r end
    end
    return nil
end

local function textsOf(rows, kind)
    local out = {}
    for _, r in ipairs(rows or {}) do
        if r.kind == kind then out[#out + 1] = r.text end
    end
    return out
end

local function holds(list, text)
    for _, v in ipairs(type(list) == "table" and list or {}) do
        if v == text then return true end
    end
    return false
end

-- "travel*", "gear", ...: the list beside the pane, the one shown starred.
local function listed(layout)
    local out = {}
    for i, topic in ipairs(layout.topics or {}) do
        local name = topic.id
        if topic.on then name = name .. "*" end
        out[i] = name
    end
    return out
end

return {
    -- Fails before: rows[1] is { kind = "search", ... } and rows[2] the
    -- "topics" row; O.Rows hands back no third value.
    ["layout: the pane holds one topic's rows; the search and the topic list stand beside it, not in it"] = function(t)
        local k = start()
        local rows, page, layout = O.Rows(k)
        t.eq(rows[1], { kind = "group", text = T.Find("travel").name }, "the pane starts at the topic's name")
        t.eq(#textsOf(rows, "search") + #textsOf(rows, "topics"), 0, "no search row, no topic buttons in the pane")
        t.eq(page.mode, "topic")
        t.eq(type(layout), "table", "the list and the search are handed over beside the rows")
        if type(layout) ~= "table" then return end
        t.eq(listed(layout), { "travel*", "gear", "bags" }, "the topics in the list's order, the one shown marked")
        t.eq(layout.topic, "travel")
        t.eq(layout.search, { label = O.SEARCH, value = "", clear = O.CLEAR })
        t.eq(layout.title, ns.id.title .. tostring(O.WINDOW))
        t.eq(#keysOf(rows), 11, "every row of the topic shown")

        t.eq(P.Goto(k, "bags"), true)
        rows, page, layout = O.Rows(k)
        t.eq(keysOf(rows), { "sell.list", "bank.list" }, "choosing a topic swaps the rows")
        t.eq(listed(layout), { "travel", "gear", "bags*" })
        t.eq(layout.topic, "bags")
        t.eq(page.topic.id, "bags")
    end,

    -- Fails before: a hit's line reads "Saved for account - Bags, Vendors
    -- and Bank".
    ["layout: a search replaces the pane; each hit names its topic; clearing it shows the last topic again"] = function(t)
        local k = start()
        P.Goto(k, "gear")
        P.Find(k, "junk")
        local rows, page, layout = O.Rows(k)
        t.eq(page.mode, "search")
        t.eq(keysOf(rows), { "sell.list" })
        local hit = rowOf(rows, "sell.list")
        t.eq(hit.under, T.Find("bags").name, "the line under a hit is its topic")
        t.eq({ hit.topic, hit.topicName, hit.jump }, { "bags", T.Find("bags").name, "bags" })
        t.eq(rows[1].kind, "group", "the pane's heading says what was found")
        P.Find(k, "grey")
        rows = O.Rows(k)
        local _, loot = T.Find("gear.loot")
        t.eq(rowOf(rows, "loot.note").under, T.Find("gear").name .. ", " .. loot.name, "and its section")
        if type(layout) == "table" then
            t.eq(layout.search.value, "junk")
            t.eq(layout.topic, nil, "no topic is on during a search")
            t.eq(listed(layout), { "travel", "gear", "bags" })
        else
            t.ok(false, "no layout was handed over")
        end
        P.Find(k, "")
        rows = O.Rows(k)
        t.eq(rows[1], { kind = "group", text = T.Find("gear").name }, "back at the last topic")
    end,

    -- Fails before: the row's line under it is "Saved for account" and the
    -- row has no tip.
    ["layout: who a setting is saved for is in the row's tooltip, not on the row"] = function(t)
        local k = start()
        P.Goto(k, "bags")
        local rows = O.Rows(k)
        local sell, bank = rowOf(rows, "sell.list"), rowOf(rows, "bank.list")
        t.eq(sell.under, nil, "nothing about saving under the row")
        t.eq(bank.under, nil)
        t.ok(holds(sell.tip, O.SAVED_FOR .. "account"), "the tooltip says it is the account's")
        t.ok(holds(bank.tip, O.SAVED_FOR .. "this character"), "or this character's")
        t.eq({ sell.scope, bank.scope }, { "account", "character" }, "the scope is still on the row for a reader")
    end,

    -- Fails before: a row has no desc (the whole description was drawn,
    -- wrapped over as many lines as it took).
    ["layout: the description is one short line; the whole of it is in the tooltip"] = function(t)
        local k = start()
        P.Goto(k, "bags")
        local rows = O.Rows(k)
        local sell, bank = rowOf(rows, "sell.list"), rowOf(rows, "bank.list")
        t.eq(bank.desc, "Short help.", "a short one is shown whole")
        t.eq(type(sell.desc), "string", "a long one has a short line too")
        if type(sell.desc) ~= "string" then return end
        t.ok(#sell.desc <= O.DESC_MAX, "no longer than one line: " .. #sell.desc)
        t.eq(sell.desc:sub(-3), "...", "cut, and it shows")
        t.eq(LONG:sub(1, #sell.desc - 3), sell.desc:sub(1, -4), "the start of the description, nothing made up")
        t.eq(sell.help, LONG, "the whole description is still the row's")
        t.eq(sell.tip[1], LONG, "and it leads the tooltip")
        t.eq(rowOf(O.Rows(k), "bank.list").tip[1], "Short help.")
    end,

    -- Fails before: every section that holds a row was headed, whatever
    -- the topic's size (the two-row topic below had one heading).
    ["layout: a topic of more than ten rows has section headings; a small one has none"] = function(t)
        local k = start()
        local rows = O.Rows(k)
        local _, arrow = T.Find("travel.arrow")
        local _, route = T.Find("travel.route")
        t.eq(textsOf(rows, "section"), { arrow.name, route.name }, "eleven rows: headed by section")
        P.Goto(k, "gear")
        rows = O.Rows(k)
        t.eq(keysOf(rows), { "gear.tip", "loot.note" }, "the rows are all there")
        t.eq(textsOf(rows, "section"), {}, "two rows: no heading")
    end,

    -- Fails before: no layout, so no list of topics to walk.
    ["layout: every declared row is reached exactly once by walking the topic list"] = function(t)
        local k = start()
        local _, _, layout = O.Rows(k)
        t.eq(type(layout), "table", "the topic list to walk")
        if type(layout) ~= "table" then return end
        local seen = {}
        for _, topic in ipairs(layout.topics) do
            t.eq(P.Goto(k, topic.id), true, topic.id)
            for _, key in ipairs(keysOf((O.Rows(k)))) do seen[key] = (seen[key] or 0) + 1 end
        end
        local n, bad = 0, {}
        for row in k.settings:each() do
            n = n + 1
            if seen[row.key] ~= 1 then bad[#bad + 1] = row.key .. " x" .. tostring(seen[row.key]) end
        end
        t.eq(n, 15)
        t.eq(table.concat(bad, ", "), "", "rows not reached once")
    end,

    -- Fails before: where the player was is kept only while the kernel is
    -- (the second kernel shows the first topic, "travel").
    ["layout: the last topic is saved for the account and is the one shown after a reload"] = function(t)
        local k, c = start()
        t.eq(P.Page(k).topic.id, "travel", "the first topic by default")
        t.eq(P.Goto(k, "bags"), true)
        local k2 = start(c.saved(ns.id.accountDB), c.saved(ns.id.charDB))
        t.eq(P.Page(k2).topic.id, "bags", "the same topic after the reload")
        local rows, _, layout = O.Rows(k2)
        t.eq(keysOf(rows), { "sell.list", "bank.list" })
        t.eq(type(layout) == "table" and layout.topic, "bags")
        -- A saved topic that is no longer in the list is not shown.
        local c3 = ns.make.fakeClient()
        c3.setSaved(ns.id.accountDB, { layout = { settingsTopic = "nosuch" } })
        c3.setSaved(ns.id.charDB, {})
        local k3 = ns.Kernel({}, c3)
        k3:Setting({ key = "sell.list", scope = "account", type = "bool", default = true,
            label = "Show the sell list", group = "bags" })
        k3:Boot()
        c3.fire("ADDON_LOADED", ns.id.addon)
        c3.fire("PLAYER_LOGIN")
        t.eq(P.Page(k3).mode, "topic")
        t.eq(P.Page(k3).topic.id, "bags", "a saved topic that is not in the list: the first one")
    end,
}

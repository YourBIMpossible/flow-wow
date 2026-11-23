-- Settings by topic, with search (lead sections 238 and 239, row N56 with
-- SETTINGS-UX-01): the page model (UI/SettingsPage.lua), the Options page
-- (UI/SettingsOptions.lua), the text page and the slash word
-- (UI/SettingsPanel.lua), on a real kernel over the fake client. Hand-made
-- rows only. Fake client; not tested in game.
local _, ns = ...

local P = ns.SettingsPage
local O = ns.SettingsOptions
local SP = ns.SettingsPanel
local T = ns.Settings and ns.Settings.Topics

local ROWS = {
    { key = "sell.list", scope = "account", type = "bool", default = true, label = "Show the sell list",
      help = "A list of what you might sell.", group = "bags", synonyms = { "junk", "vendor" } },
    { key = "bank.list", scope = "account", type = "bool", default = true, label = "Show the bank list",
      help = "Beside the bank window.", group = "bags" },
    { key = "arrow.look", scope = "account", type = "choice", choices = { "modern", "flat" }, default = "modern",
      label = "Arrow style", group = "travel.arrow", synonyms = { "waypoint" } },
    { key = "arrow.size", scope = "account", type = "number", default = 5, min = 1, max = 10,
      label = "Arrow size", group = "travel.arrow" },
    { key = "way.zone", scope = "account", type = "bool", default = true, label = "Finish this zone first",
      group = "travel.route" },
    { key = "food.offer", scope = "char", type = "bool", default = true, label = "Suggest Well Fed food",
      help = "Out of a fight.", group = "buffs", synonyms = { "eat", "buffs" } },
    { key = "food.cafe", scope = "char", type = "bool", default = false, label = "Caf\195\169 stops", group = "buffs" },
    { key = "food.drink", scope = "char", type = "bool", default = true, label = "Drink too", group = "buffs",
      needs = "food.offer",
      requires = function(settings) return settings:get("food.offer") == true, "turn the food offer on first" end },
}

-- opts: noPage (a client with no Options page), rows (instead of ROWS).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    if opts.noPage then c.setOptionsPage(false) end
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    for _, row in ipairs(opts.rows or ROWS) do
        local copy = {}
        for field, value in pairs(row) do copy[field] = value end
        k:Setting(copy)
    end
    SP.Declare(k, d)
    O.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c
end

local function slash(c, rest) c.slashes[ns.id.slash](rest) end

local function keysOf(entries)
    local out = {}
    for i, e in ipairs(entries or {}) do out[i] = e.key end
    return out
end

-- The keys of the setting rows the Options page drew, top to bottom.
local function drawn(c)
    local out = {}
    for _, r in ipairs(c.optionsRows() or {}) do
        if r.key ~= nil then out[#out + 1] = r.key end
    end
    return out
end

local function drawnRow(c, key)
    for _, r in ipairs(c.optionsRows() or {}) do
        if r.key == key then return r end
    end
    return nil
end

-- Since the settings window (lead section 285 item 3) the search and the
-- topics stand beside the rows: "search" and "topics" are read from the
-- window's layout (value; topics), every other kind from the rows.
local function ofKind(c, kind)
    if kind == "search" or kind == "topics" then
        local layout
        if type(c.optionsLayout) == "function" then layout = c.optionsLayout() end
        if type(layout) ~= "table" then return nil end
        if kind == "search" then return layout.search end
        return layout
    end
    for _, r in ipairs(c.optionsRows() or {}) do
        if r.kind == kind then return r end
    end
    return nil
end

local function tipHolds(r, text)
    for _, line in ipairs(type(r) == "table" and type(r.tip) == "table" and r.tip or {}) do
        if tostring(line):find(text, 1, true) ~= nil then return true end
    end
    return false
end

local function panelOf(c)
    for _, p in ipairs(c.panels) do
        if type(p.spec) == "table" and p.spec.name == ns.id.framePrefix .. "Settings" then return p end
    end
    return nil
end

local function lineWith(lines, text)
    for _, l in ipairs(lines or {}) do
        if tostring(l):find(text, 1, true) then return tostring(l) end
    end
    return nil
end

local function has(t)
    local ok = type(T) == "table" and type(P.Page) == "function" and type(P.Search) == "function"
        and type(P.Goto) == "function" and type(P.Find) == "function"
    t.ok(ok, "the topics list and the page's Page, Search, Goto and Find are there")
    return ok
end

return {
    -- Fails before: UI/SettingsPage.lua has no Page / Goto (one list of
    -- groups under headings, in the order declared).
    ["topics: choosing a topic shows that topic's settings only, under its sections"] = function(t)
        if not has(t) then return end
        local k = start()
        local page = P.Page(k)
        t.eq(page.mode, "topic")
        t.eq(page.topic.id, "travel", "the first listed topic that holds a row")
        local names = {}
        for i, topic in ipairs(page.topics) do names[i] = topic.id .. (topic.on and "*" or "") end
        t.eq(names, { "travel*", "buffs", "bags" }, "topics in the list's order, the one shown marked")
        t.eq(keysOf(page.topic.rows), { "arrow.look", "arrow.size", "way.zone" })
        t.eq(#page.topic.sections, 2)
        t.eq(page.topic.sections[1].name, T.Find("travel.arrow") and select(2, T.Find("travel.arrow")).name)
        t.eq(keysOf(page.topic.sections[1].rows), { "arrow.look", "arrow.size" })
        t.eq(keysOf(page.topic.sections[2].rows), { "way.zone" })

        t.eq(P.Goto(k, "bags"), true)
        page = P.Page(k)
        t.eq(page.topic.id, "bags")
        t.eq(keysOf(page.topic.rows), { "sell.list", "bank.list" }, "only this topic's rows")
        t.eq(P.Goto(k, "nosuch"), false, "no such topic")
        t.eq(P.Page(k).topic.id, "bags", "and nothing moved")
    end,

    -- Fails before: SettingsOptions.Rows draws every group one under the
    -- other (kind "group" rows only; no "topics" row, no nav).
    ["topics: the Options page draws the search, the topic buttons and one topic's controls"] = function(t)
        if not has(t) then return end
        local _, c = start()
        slash(c, "settings")
        t.eq(c.optionsOpened(), 1)
        -- Changed for the window (lead section 285 item 3). It asserted the
        -- search at rows[1], the topics at rows[2], the name at rows[3] and
        -- a section heading at rows[4]; a topic of three rows has no
        -- section heading now.
        local rows = c.optionsRows()
        t.eq(ofKind(c, "search").value, "")
        t.eq(#ofKind(c, "topics").topics, 3)
        t.eq(rows[1], { kind = "group", text = T.Find("travel").name })
        t.eq(rows[2].key, "arrow.look", "a small topic has no section heading")
        t.eq(drawn(c), { "arrow.look", "arrow.size", "way.zone" })
        t.eq(c.optionsNav("topic", "buffs"), true)
        t.eq(drawn(c), { "food.offer", "food.cafe", "food.drink" }, "the other topics' rows are not drawn")
        t.eq(ofKind(c, "group").text, T.Find("buffs").name)
        for _, topic in ipairs(ofKind(c, "topics").topics) do
            t.eq(topic.on, topic.id == "buffs", topic.id)
        end
    end,

    -- Fails before: there is no search (SettingsPage.Search is nil).
    ["search: it runs over every topic, not the chosen one"] = function(t)
        if not has(t) then return end
        local k = start()
        P.Goto(k, "bags")
        t.eq(P.Find(k, "arrow"), true)
        local page = P.Page(k)
        t.eq(page.mode, "search")
        t.eq(page.query, "arrow")
        t.eq(keysOf(page.results), { "arrow.look", "arrow.size" }, "rows of another topic")
        for _, topic in ipairs(page.topics) do t.eq(topic.on, false, "no topic is marked during a search") end
        t.eq(keysOf(P.Search(k, "list").results), { "sell.list", "bank.list" })
        t.eq(keysOf(P.Search(k, "first").results), { "way.zone" })
    end,

    -- Fails before: no search; Topics.Fold is absent.
    ["search: capitals and accents do not matter"] = function(t)
        if not has(t) then return end
        local k = start()
        t.eq(keysOf(P.Search(k, "ARROW STYLE").results), { "arrow.look" })
        t.eq(keysOf(P.Search(k, "arrow style").results), { "arrow.look" })
        t.eq(keysOf(P.Search(k, "cafe").results), { "food.cafe" }, "typed without the accent")
        t.eq(keysOf(P.Search(k, "CAF\195\137").results), { "food.cafe" }, "typed in capitals, with it")
        t.eq(keysOf(P.Search(k, "Well FED").results), { "food.offer" })
    end,

    -- Fails before: no search; a row's synonyms are read by nothing.
    ["search: synonyms, topic names and section names find a row; no key is needed"] = function(t)
        if not has(t) then return end
        local k = start()
        t.eq(keysOf(P.Search(k, "junk").results), { "sell.list" }, "a synonym")
        t.eq(keysOf(P.Search(k, "waypoint").results), { "arrow.look" }, "a synonym")
        t.eq(keysOf(P.Search(k, "eat").results), { "food.offer" }, "a synonym")
        t.eq(keysOf(P.Search(k, "recovery").results), { "food.offer", "food.cafe", "food.drink" }, "a topic's name")
        t.eq(keysOf(P.Search(k, "vendors").results), { "sell.list", "bank.list" }, "a topic's name")
        t.eq(keysOf(P.Search(k, "the way there").results), { "way.zone" }, "a section's name")
        t.eq(keysOf(P.Search(k, "window").results), { "bank.list" }, "the description")
    end,

    -- Fails before: no search, so no empty search and no line for no match.
    ["search: an empty search is browsing; no match gives a useful line"] = function(t)
        if not has(t) then return end
        local k, c = start()
        t.eq(P.Search(k, ""), nil)
        t.eq(P.Search(k, "   "), nil)
        t.eq(P.Search(k, " ,.- "), nil, "nothing but punctuation is no search")
        t.eq(P.Search(k, nil), nil)
        t.eq(P.Find(k, "   "), false)
        t.eq(P.Page(k).mode, "topic")

        local found = P.Search(k, "  dragons ")
        t.eq(found.results, {})
        t.eq(found.query, "dragons")
        t.eq(found.none, P.NoMatch("dragons"))
        t.ok(found.none:find("dragons", 1, true) ~= nil and found.none:find("topic", 1, true) ~= nil,
            "it says what was searched and what to do next: " .. found.none)

        slash(c, "settings")
        c.optionsNav("search", "dragons")
        t.eq(drawn(c), {}, "no setting row is drawn")
        t.eq(ofKind(c, "note").text, P.NoMatch("dragons"))
        t.eq(ofKind(c, "search").value, "dragons", "the box keeps what was typed")
        t.eq(#ofKind(c, "topics").topics, 3, "the topics are still there to pick")
    end,

    -- Fails before: no search state; SettingsPage.Find is nil.
    ["search: clearing it restores the topic that was shown"] = function(t)
        if not has(t) then return end
        local _, c = start()
        slash(c, "settings")
        c.optionsNav("topic", "bags")
        c.optionsNav("search", "arrow")
        t.eq(drawn(c), { "arrow.look", "arrow.size" })
        c.optionsNav("search", "")
        t.eq(ofKind(c, "search").value, "")
        t.eq(ofKind(c, "group").text, T.Find("bags").name)
        t.eq(drawn(c), { "sell.list", "bank.list" })
    end,

    -- Fails before: an entry has no topicName and no scope; no result rows.
    ["search: a result shows its topic and whether it is the account's or the character's"] = function(t)
        if not has(t) then return end
        local k, c = start()
        local found = P.Search(k, "list food")
        t.eq(found.results, {}, "both words must be found in one row")
        found = P.Search(k, "show")
        t.eq(keysOf(found.results), { "sell.list", "bank.list" })
        t.eq(found.results[1].topicName, T.Find("bags").name)
        t.eq(found.results[1].scope, "account")
        local eat = P.Search(k, "eat").results[1]
        t.eq({ eat.topic, eat.topicName, eat.scope, eat.savedFor },
            { "buffs", T.Find("buffs").name, "character", "this character" })
        local look = P.Search(k, "waypoint").results[1]
        t.eq({ look.topic, look.section, look.sectionName }, { "travel", "arrow", select(2, T.Find("travel.arrow")).name })

        slash(c, "settings eat")
        local r = drawnRow(c, "food.offer")
        t.ok(r ~= nil, "the result is drawn")
        -- Changed for the window: who it is saved for was in r.under; it
        -- is in the row's tooltip now.
        t.ok(r.under:find(T.Find("buffs").name, 1, true) ~= nil, "its topic: " .. r.under)
        t.ok(tipHolds(r, "this character"), "who it is saved for, in the tooltip")
        t.eq(r.jump, "buffs")
        -- In a topic the scope is still on each row; the topic is the heading.
        c.optionsNav("topic", "bags")
        r = drawnRow(c, "sell.list")
        t.eq(r.under, nil, "nothing under a row of a topic")
        t.ok(tipHolds(r, "account"), "saved for the account, in the tooltip")
        t.eq(r.scope, "account")
        t.eq(r.jump, nil, "nothing to jump to from its own topic")
    end,

    -- Fails before: no result rows and no nav on the Options page.
    ["search: a result can be jumped to; the topic opens and the search ends"] = function(t)
        if not has(t) then return end
        local k, c = start()
        slash(c, "settings junk")
        local r = drawnRow(c, "sell.list")
        t.eq(c.optionsNav("topic", r.jump), true)
        t.eq(P.State(k).query, nil)
        t.eq(ofKind(c, "group").text, T.Find("bags").name)
        t.eq(drawn(c), { "sell.list", "bank.list" })
    end,

    -- Fails before: no search results to change; with them, both must call
    -- SettingsPage.Set (UI/SettingsOptions.lua act).
    ["one path: a result and a topic row are changed by the same checked Set"] = function(t)
        if not has(t) then return end
        local k, c = start()
        local real, calls = P.Set, {}
        P.Set = function(kk, key, value)
            calls[#calls + 1] = key .. "=" .. tostring(value)
            return real(kk, key, value)
        end
        local ok, err = pcall(function()
            slash(c, "settings")
            c.optionsNav("topic", "travel")
            t.eq((c.optionsAct("arrow.size", 7)), true, "from the topic")
            t.eq(c.optionsAct("arrow.size", 99), false, "outside its limits: refused from the topic")
            c.optionsNav("search", "arrow size")
            t.eq(drawn(c), { "arrow.size" })
            t.eq(drawnRow(c, "arrow.size").value, 7)
            t.eq(drawnRow(c, "arrow.size").kind, "slider", "the same control as in its topic")
            t.eq({ drawnRow(c, "arrow.size").min, drawnRow(c, "arrow.size").max }, { 1, 10 })
            t.eq((c.optionsAct("arrow.size", 3)), true, "from the result")
            t.eq(drawnRow(c, "arrow.size").value, 3, "the result shows the new value, the search still on")
            t.eq(c.optionsAct("arrow.size", 99), false, "refused from the result the same way")
            t.eq(c.optionsAct("arrow.look", "round"), false, "not one of its choices")
        end)
        P.Set = real
        t.ok(ok, tostring(err))
        t.eq(calls, { "arrow.size=7", "arrow.size=99", "arrow.size=3", "arrow.size=99", "arrow.look=round" })
        t.eq(k.settings:get("arrow.size"), 3)
        t.eq(k.settings:get("arrow.look"), "modern")
        t.eq(c.saved(ns.id.accountDB).settings.arrow.size, 3, "saved where it always was")
    end,

    -- Fails before: no search; an entry has no `because`.
    ["requires: a row whose requires is unmet is in the results, greyed, saying why and what it depends on"] = function(t)
        if not has(t) then return end
        local k, c = start()
        t.eq(k.settings:set("food.offer", false), true)
        local found = P.Search(k, "drink")
        t.eq(keysOf(found.results), { "food.drink" }, "not hidden")
        local e = found.results[1]
        t.eq(e.available, false)
        t.eq(e.settable, false)
        t.eq(e.why, P.NOT_NOW)
        t.ok(e.because:find('"Suggest Well Fed food"', 1, true) ~= nil, "the row it depends on: " .. e.because)
        t.ok(e.because:find(T.Find("buffs").name, 1, true) ~= nil, "and where that one is: " .. e.because)
        t.ok(e.because:find("turn the food offer on first", 1, true) ~= nil, "and what requires said: " .. e.because)

        slash(c, "settings drink")
        local r = drawnRow(c, "food.drink")
        t.ok(r ~= nil, "drawn on the Options page")
        t.eq(r.settable, false)
        t.eq(r.why, P.NOT_NOW)
        t.ok(r.under:find(e.because, 1, true) ~= nil, r.under)
        t.eq(c.optionsAct("food.drink", false), false, "and it cannot be changed")
        t.eq(k.settings:get("food.drink"), true)
        -- In its topic too.
        c.optionsNav("topic", "buffs")
        t.eq(drawnRow(c, "food.drink").settable, false)
        -- Met again: it can be set, and says nothing.
        t.eq((c.optionsAct("food.offer", true)), true)
        r = drawnRow(c, "food.drink")
        t.eq({ r.settable, r.why }, { true, nil })
        t.eq(P.Search(k, "drink").results[1].because, nil)
    end,

    -- Fails before: no topics and no search to find it by.
    ["discovery: a row declared later is on its topic's page and in the search, with no list to keep"] = function(t)
        if not has(t) then return end
        local k, c = start()
        slash(c, "settings")
        t.eq(P.Search(k, "nets").results, {})
        t.ok(k:Setting({ key = "craft.nets", scope = "char", type = "bool", default = false,
            label = "Mend nets at dusk", help = "A made-up row.", group = "professions", synonyms = { "trawl" } }) ~= nil)
        -- By navigation: its topic is now one of the topics, and holds it.
        local page = P.Page(k)
        local names = {}
        for i, topic in ipairs(page.topics) do names[i] = topic.id end
        t.eq(names, { "travel", "buffs", "bags", "professions" })
        t.eq(c.optionsNav("topic", "professions"), true)
        t.eq(drawn(c), { "craft.nets" })
        -- By search: label, synonym, topic name.
        t.eq(keysOf(P.Search(k, "nets").results), { "craft.nets" })
        t.eq(keysOf(P.Search(k, "trawl").results), { "craft.nets" })
        t.eq(keysOf(P.Search(k, "crafting").results), { "craft.nets" })
        c.optionsNav("search", "trawl")
        t.eq(drawn(c), { "craft.nets" })
        t.eq((c.optionsAct("craft.nets", true)), true)
        t.eq(c.saved(ns.id.charDB).settings.craft.nets, true)
        -- A change made another way shows on the open page for it too.
        t.eq(k.settings:set("craft.nets", false), true)
        t.eq(drawnRow(c, "craft.nets").value, false)
    end,

    -- Fails before: a row with no group stood under "Other".
    ["unfiled: a row that names no listed topic is still shown, apart, never under Other"] = function(t)
        if not has(t) then return end
        local k = start({ rows = {
            { key = "a.one", scope = "account", type = "bool", default = true, label = "One", group = "bags" },
            { key = "a.two", scope = "account", type = "bool", default = true, label = "Two" },
            { key = "a.three", scope = "account", type = "bool", default = true, label = "Three", group = "Other" },
        } })
        local view = P.View(k)
        t.eq(#view.topics, 2)
        t.eq(view.topics[2].id, T.UNFILED.id)
        t.eq(keysOf(view.topics[2].rows), { "a.two", "a.three" })
        t.eq(P.GROUP_OTHER, nil)
        t.eq(keysOf(P.Search(k, "three").results), { "a.three" }, "and it is still found")
    end,

    -- Fails before: the word knows only a key and a value.
    ["slash: settings <words> searches, settings topic <name> shows a topic, a key still changes one"] = function(t)
        if not has(t) then return end
        local k, c = start()
        slash(c, "settings junk")
        t.eq(c.optionsOpened(), 1, "the page opens with the search")
        t.eq(P.State(k).query, "junk")
        t.eq(drawn(c), { "sell.list" })
        slash(c, "settings topic buffs and recovery")
        t.eq(P.State(k).topic, "buffs")
        t.eq(P.State(k).query, nil)
        t.eq(drawn(c), { "food.offer", "food.cafe", "food.drink" })
        slash(c, "settings well fed")
        t.eq(drawn(c), { "food.offer" })
        slash(c, "settings topic")
        t.eq(P.State(k).query, nil, "topic alone ends the search")
        t.eq(drawn(c), { "food.offer", "food.cafe", "food.drink" })
        local n = #c.printed
        slash(c, "settings topic dragons")
        t.ok(lineWith({ c.printed[n + 1] }, SP.NO_TOPIC) ~= nil, "said: " .. tostring(c.printed[n + 1]))
        t.eq(P.State(k).topic, "buffs", "and nothing moved")
        -- A key is still a key.
        slash(c, "settings sell.list off")
        t.eq(k.settings:get("sell.list"), false)
        t.eq(P.State(k).query, nil, "a change is not a search")
    end,

    -- Fails before: the text page lists every group, one under the other.
    ["text page: the topics, then the chosen topic's rows with scope and key; a search lists results with their topic"] = function(t)
        if not has(t) then return end
        local k, c = start({ noPage = true })
        slash(c, "settings")
        local p = panelOf(c)
        t.eq(p.shown, true)
        t.eq(p.lines, SP.Lines(k))
        t.ok(lineWith(p.lines, "> " .. T.Find("travel").name .. " (3)") ~= nil, "the topic shown is marked")
        t.ok(lineWith(p.lines, "  " .. T.Find("bags").name .. " (2)") ~= nil, "the others are listed with their count")
        t.ok(lineWith(p.lines, "Arrow style: modern  (account)  [arrow.look]") ~= nil, "a row: value, scope, key")
        t.eq(lineWith(p.lines, "sell.list"), nil, "another topic's rows are not on the page")
        slash(c, "settings topic bags")
        t.eq(p.shown, true, "still open")
        t.ok(lineWith(p.lines, "[sell.list]") ~= nil)
        t.eq(lineWith(p.lines, "arrow.look"), nil)
        slash(c, "settings eat")
        t.ok(lineWith(p.lines, SP.SEARCH .. "eat") ~= nil)
        t.ok(lineWith(p.lines, "Suggest Well Fed food: on  (character; " .. T.Find("buffs").name .. ")  [food.offer]") ~= nil,
            "a result: value, scope, topic, key: " .. table.concat(p.lines, " / "))
        slash(c, "settings dragons")
        t.ok(lineWith(p.lines, P.NoMatch("dragons")) ~= nil, "no match says so")
        -- A result is changed the one way a typed change goes, and the page follows.
        slash(c, "settings eat")
        slash(c, "settings food.offer off")
        t.eq(k.settings:get("food.offer"), false)
        t.ok(lineWith(p.lines, "Suggest Well Fed food: off") ~= nil, "the open results show it")
        -- An unmet requires is said on its line.
        slash(c, "settings drink")
        local line = lineWith(p.lines, "[food.drink]")
        t.ok(line and line:find(SP.NOT_NOW, 1, true) ~= nil and line:find("depends on", 1, true) ~= nil, tostring(line))
        for _, l in ipairs(p.lines) do t.ok(not l:find("Flow", 1, true), "no name spelled out: " .. l) end
    end,

    -- Fails before: SettingsPanel.Lines lists every row; no cap is needed.
    ["text page: a search with many results is cut short, saying how many more"] = function(t)
        if not has(t) then return end
        local rows = {}
        for i = 1, SP.MAX_RESULTS + 4 do
            rows[i] = { key = "many.n" .. i, scope = "account", type = "bool", default = true,
                label = "Lantern " .. i, group = "advanced" }
        end
        local k, c = start({ noPage = true, rows = rows })
        slash(c, "settings lantern")
        local p = panelOf(c)
        local n = 0
        for _, l in ipairs(p.lines) do
            if l:find("[many.n", 1, true) then n = n + 1 end
        end
        t.eq(n, SP.MAX_RESULTS)
        t.ok(lineWith(p.lines, "4" .. SP.MORE) ~= nil, "and the rest are counted")
        t.eq(#P.Search(k, "lantern").results, SP.MAX_RESULTS + 4, "the search itself holds them all")
    end,

    -- Row N57 (lead section 249 item 2): descriptions on the text page.
    -- Fails before: SettingsPanel.Lines printed no help.
    ["text page: each row's description stands under it, wrapped and cut at a fixed number of lines"] = function(t)
        if not has(t) then return end
        local long = string.rep("word ", 60)
        local k, c = start({ noPage = true, rows = {
            { key = "a.one", scope = "account", type = "bool", default = true, label = "One",
              help = "A short description.", group = "bags" },
            { key = "a.two", scope = "account", type = "bool", default = true, label = "Two", group = "bags" },
            { key = "a.three", scope = "account", type = "bool", default = true, label = "Three", help = long, group = "bags" },
        } })
        slash(c, "settings")
        local lines = panelOf(c).lines
        local at = {}
        for i, l in ipairs(lines) do
            if l:find("[a.one]", 1, true) then at.one = i end
            if l:find("[a.two]", 1, true) then at.two = i end
            if l:find("[a.three]", 1, true) then at.three = i end
        end
        t.ok(at.one and at.two and at.three, "the three rows")
        if not (at.one and at.two and at.three) then return end
        t.ok(type(SP.WRAP) == "number" and type(SP.HELP_LINES) == "number", "the wrap and the cap are constants")
        if type(SP.WRAP) ~= "number" then return end
        t.eq(lines[at.one + 1], SP.HELP_INDENT .. "A short description.")
        t.eq(at.two, at.one + 2, "one line of help, then the next row")
        t.eq(at.three, at.two + 1, "a row with no description has no line under it")
        local helps = 0
        for i = at.three + 1, #lines do
            if lines[i]:sub(1, #SP.HELP_INDENT + 4) == SP.HELP_INDENT .. "word" then
                helps = helps + 1
                t.ok(#lines[i] <= #SP.HELP_INDENT + SP.WRAP + 3, "a wrapped line is short: " .. #lines[i])
            end
        end
        t.eq(helps, SP.HELP_LINES, "cut at the fixed number of lines")
        t.eq(lines[at.three + SP.HELP_LINES]:sub(-3), "...", "and the cut is shown")
        -- In search results too.
        slash(c, "settings one")
        lines = panelOf(c).lines
        t.ok(lineWith(lines, SP.HELP_INDENT .. "A short description.") ~= nil, "a result has its description")
        t.ok(SP.Tallest(k) >= #SP.Lines(k) - 6, "the panel is made tall enough for them")
    end,

    -- Fails before: SettingsSlash.Run listed every row in one flat list.
    ["slash setting: with no argument the rows are listed under their topics, in the list's order"] = function(t)
        if not has(t) then return end
        local k = start()
        local lines = ns.SettingsSlash.Run(k, "")
        local at = {}
        for i, l in ipairs(lines) do
            for _, id in ipairs({ "travel", "buffs", "bags" }) do
                if l == T.Find(id).name .. ":" then at[id] = i end
            end
            for _, row in ipairs(ROWS) do
                if l:find(row.key .. " = ", 1, true) == 1 then at[row.key] = i end
            end
        end
        t.ok(at.travel and at.buffs and at.bags, "a heading for each topic that holds a row")
        if not (at.travel and at.buffs and at.bags) then return end
        t.ok(at.travel < at.buffs and at.buffs < at.bags, "topics in the list's order, not the order declared")
        for _, row in ipairs(ROWS) do t.ok(at[row.key] ~= nil, row.key .. " is listed, as before") end
        t.ok(at.travel < at["arrow.look"] and at["way.zone"] < at.buffs, "the travel rows under Travel")
        t.ok(at.buffs < at["food.offer"] and at["food.drink"] < at.bags, "the buffs rows under Buffs")
        t.ok(at.bags < at["sell.list"] and at.bags < at["bank.list"], "the bags rows under Bags")
        t.eq(#lines, 1 + 3 + #ROWS, "the first line, three headings, and one line a row")
        t.ok(lines[1]:find(ns.id.slash, 1, true) ~= nil, "the first line still says how to change one")
    end,
}

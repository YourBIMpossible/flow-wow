local _, ns = ...
-- The settings window (lead section 285 item 3), on the whole add-on
-- loaded on a fake client and entered the way the player enters: the slash
-- word, the button on the add-on's entry in the game's Options, the arrow
-- menu and a click on the info bar. One window: the topics down the left,
-- one topic's rows (or the search's hits) on the right. Per lead section
-- 236: a reload in the middle (a second add-on from the saved data) and a
-- draw that raises, then recovers. Offline: the fake client's window, not
-- the game's. Not tested in game.
local tests = {}

local T = ns.Settings and ns.Settings.Topics

-- opts: account, char (saved tables), before(c), arrows (place the player
-- so the arrows can show).
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    local account = opts.account or {}
    if opts.arrows then
        if type(account.layout) ~= "table" then account.layout = {} end
        account.layout.arrowIntroSeen = true
        c.setZone(1, 1411)
        c.setFacing(0)
        c.setPosition(1411, 0.5, 0.5)
        c.setMapSize(1411, 1000, 500)
    end
    c.setScreen(1024, 768)
    c.setSaved(ns.id.accountDB, account)
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setLockdown(false)
    if type(c.setBindings) == "function" then c.setBindings({}) end
    if opts.before then opts.before(c) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

-- The same player after a reload: a second add-on from what was saved.
local function reload(c)
    return boot({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
end

local function slash(c, rest) c.slashes[ns.id.slash](rest) end

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

local function count(c, kind)
    local n = 0
    for _, r in ipairs(c.optionsRows() or {}) do
        if r.kind == kind then n = n + 1 end
    end
    return n
end

-- The pane's heading: the topic shown, or what a search found.
local function heading(c)
    for _, r in ipairs(c.optionsRows() or {}) do
        if r.kind == "group" then return r.text end
    end
    return nil
end

local function holds(list, text)
    for _, v in ipairs(type(list) == "table" and list or {}) do
        if v == text then return true end
    end
    return false
end

local function panelOf(c, name)
    for _, p in ipairs(c.panels) do
        if type(p.spec) == "table" and p.spec.name == ns.id.framePrefix .. name then return p end
    end
    return nil
end

-- The fake window's own reads: what stands beside the rows, the add-on's
-- entry in the game's Options, and a draw that raises.
local function ready(t, c)
    local ok = type(c.optionsLayout) == "function" and type(c.optionsEntry) == "function"
        and type(c.optionsEntryPress) == "function" and type(c.setSettingsDrawFault) == "function"
    t.ok(ok, "the fake client has the settings window: its layout, the Options entry and a draw fault")
    return ok
end

-- Fails before: the first thing drawn is the search row, then the row of
-- ten topic buttons; the fake has no optionsLayout.
tests["settings layout: a default boot and the slash word show the window, the ten topics down the side and the first topic's rows only"] = function(t)
    local c, addon = boot()
    slash(c, "settings")
    t.eq(c.optionsOpened(), 1, "the slash word opens it")
    local rows = c.optionsRows() or {}
    t.eq(rows[1], { kind = "group", text = T.LIST[1].name }, "the pane starts at the first topic's name")
    t.eq(count(c, "search") + count(c, "topics"), 0, "no search row and no block of topic buttons in the pane")
    if not ready(t, c) then return end
    local layout = c.optionsLayout()
    t.eq(layout.title, ns.id.title .. tostring(addon.SettingsOptions.WINDOW), "the window's title")
    local names, want, on = {}, {}, {}
    for i, topic in ipairs(layout.topics) do
        names[i] = topic.name
        if topic.on then on[#on + 1] = topic.id end
    end
    for i, topic in ipairs(T.LIST) do want[i] = topic.name end
    t.eq(names, want, "every topic, in the list's order")
    t.eq(on, { T.LIST[1].id }, "one is on: the first")
    t.eq(layout.topic, T.LIST[1].id)
    t.eq(layout.search, { label = addon.SettingsOptions.SEARCH, value = "", clear = addon.SettingsOptions.CLEAR })
    local keys = drawn(c)
    t.ok(#keys > 0, "rows are drawn")
    for _, key in ipairs(keys) do
        t.eq(drawnRow(c, key).topic, T.LIST[1].id, key .. " is of the topic shown")
    end
    t.ok(#keys < addon.SettingsPage.Page(addon).count, "one topic, not the whole list")
end

-- Fails before: after choosing a topic the first thing drawn is still the
-- search row (rows[1].text is nil).
tests["settings layout: choosing a topic in the list swaps the rows and moves the mark"] = function(t)
    local c = boot()
    slash(c, "settings")
    local before = drawn(c)
    t.eq(c.optionsNav("topic", "bags"), true)
    local keys = drawn(c)
    table.sort(keys)
    t.eq(keys, { "bank.list", "items.haveCount", "repair.costLine", "repair.warnBelow", "vendor.list" })
    t.eq((c.optionsRows() or {})[1], { kind = "group", text = T.Find("bags").name }, "the pane's heading is the topic")
    for _, key in ipairs(before) do t.eq(drawnRow(c, key), nil, key .. " of the first topic is gone") end
    if not ready(t, c) then return end
    local on = {}
    for _, topic in ipairs(c.optionsLayout().topics) do
        if topic.on then on[#on + 1] = topic.id end
    end
    t.eq(on, { "bags" })
    t.eq(c.optionsLayout().topic, "bags")
    t.eq(#c.optionsLayout().topics, #T.LIST, "the list is still whole")
end

-- Fails before: a hit's line reads "Saved for account - Bags, Vendors and
-- Bank".
tests["settings layout: a search replaces the rows, every hit names its topic, and clearing it shows the last topic"] = function(t)
    local c = boot()
    slash(c, "settings")
    c.optionsNav("topic", "bags")
    c.optionsNav("search", "junk")
    local sell, note = drawnRow(c, "vendor.list"), drawnRow(c, "loot.junkNote")
    t.ok(sell ~= nil and note ~= nil, "hits from two topics")
    if not (sell and note) then return end
    local _, loot = T.Find("gear.loot")
    t.eq(sell.under, T.Find("bags").name, "the hit names its topic")
    t.eq(note.under, T.Find("gear").name .. ", " .. loot.name, "and its section")
    for _, key in ipairs(drawn(c)) do
        local r = drawnRow(c, key)
        t.ok(type(r.topicName) == "string" and type(r.under) == "string"
            and r.under:find(r.topicName, 1, true) == 1, key .. " names its topic")
    end
    t.eq({ sell.kind, sell.value, sell.settable }, { "toggle", true, true }, "the same control as in its topic")
    if ready(t, c) then
        t.eq(c.optionsLayout().search.value, "junk", "the box keeps what was typed")
        t.eq(c.optionsLayout().topic, nil, "no topic is on during a search")
        t.eq(#c.optionsLayout().topics, #T.LIST, "the list is still there to pick from")
    end
    c.optionsNav("search", "")
    t.eq((c.optionsRows() or {})[1], { kind = "group", text = T.Find("bags").name }, "back at the last topic")
    t.eq(drawnRow(c, "loot.junkNote"), nil)
end

-- Fails before: no optionsLayout on the fake, so no list to walk.
tests["settings layout: every row of the add-on, and each key row, is reached exactly once by walking the topic list"] = function(t)
    local c, addon = boot()
    slash(c, "settings")
    if not ready(t, c) then return end
    local seen, unreachable = {}, {}
    for _, topic in ipairs(c.optionsLayout().topics) do
        t.eq(c.optionsNav("topic", topic.id), true, topic.id)
        for _, key in ipairs(drawn(c)) do seen[key] = (seen[key] or 0) + 1 end
        -- Twin F2: each settable row is drawn with a control, or greyed
        -- with a reason; never enabled with nothing to change it.
        local settable = {}
        for _, r in ipairs(c.optionsRows() or {}) do
            if r.settable == true and r.label ~= nil then settable[tostring(r.label)] = true end
        end
        local tree = ns.SettingsWindow.Tree(c.optionsRows() or {}, function() end, function() end,
            c.optionsLayout())
        ns.Kit.Each(tree, function(part)
            if part.kind == "row" and settable[tostring(part.label)] and part.control == nil
                and not (part.enabled == false and type(part.reason) == "string" and part.reason ~= "") then
                unreachable[#unreachable + 1] = topic.id .. ": " .. tostring(part.label)
            end
        end)
    end
    local n, bad = 0, {}
    for row in addon.settings:each() do
        n = n + 1
        if seen[row.key] ~= 1 then bad[#bad + 1] = row.key .. " x" .. tostring(seen[row.key]) end
    end
    for _, slot in ipairs(addon.SettingsKeys.SLOTS) do
        if seen[slot.key] ~= 1 then bad[#bad + 1] = slot.key .. " x" .. tostring(seen[slot.key]) end
    end
    table.sort(bad)
    t.ok(n >= 40, "the add-on's rows were walked: " .. n)
    t.eq(table.concat(bad, ", "), "", "rows not reached exactly once")
    t.eq(table.concat(unreachable, ", "), "", "settable rows drawn with no control and no reason")
end

-- Fails before: where the player was is not saved; after the reload the
-- heading is the first topic's ("General and Appearance").
tests["settings layout reload: the last topic chosen is the one shown after a reload"] = function(t)
    local c = boot()
    slash(c, "settings")
    t.eq(heading(c), T.LIST[1].name, "a new player starts at the first topic")
    t.eq(c.optionsNav("topic", "gear"), true)
    c.optionsNav("search", "sell")
    local c2 = reload(c)
    slash(c2, "settings")
    t.eq(heading(c2), T.Find("gear").name, "the topic chosen before the reload")
    t.ok(drawnRow(c2, "gear.tooltip") ~= nil, "with its rows")
    t.eq(drawnRow(c2, "vendor.list"), nil, "the search is not carried over")
end

-- Fails before: a key row is kind "actions" and an unset key reads "not set".
tests["settings layout keys: a key row is a bind button that reads Not Bound, then the key once one is caught"] = function(t)
    local c, addon = boot()
    slash(c, "settings")
    c.optionsNav("topic", "combat")
    local r = drawnRow(c, "keys.rotation")
    t.ok(r ~= nil, "the key row is drawn")
    if not r then return end
    t.eq({ r.kind, r.shown }, { "bind", "Not Bound" })
    t.eq(r.bound, false)
    t.eq(c.optionsNav("action", r.actions[1].key), true, "a press on the bind button")
    t.eq(c.keyCaptureOpen(), true, "the overlay waits for a key")
    t.eq(c.pressKey("G"), true)
    r = drawnRow(c, "keys.rotation")
    t.eq({ r.kind, r.shown, r.bound }, { "bind", "G", true })
    t.eq(c.bindingMap()["G"], "CLICK " .. ns.id.framePrefix .. addon.SettingsKeys.BUTTON .. ":LeftButton")
    t.eq(drawnRow(c, "keys.rotation2").shown, "Not Bound", "the second key is still unset")
end

-- Fails before: the line under vendor.list is "Saved for account" and the
-- row has no tip.
tests["settings layout: who a setting is saved for is in its tooltip, not on the row"] = function(t)
    local c, addon = boot()
    slash(c, "settings")
    c.optionsNav("topic", "bags")
    local saved = addon.SettingsOptions.SAVED_FOR
    for _, key in ipairs(drawn(c)) do
        local r = drawnRow(c, key)
        for _, field in ipairs({ "label", "under", "desc" }) do
            t.ok(type(r[field]) ~= "string" or r[field]:find(saved, 1, true) == nil,
                key .. "." .. field .. " says nothing about saving: " .. tostring(r[field]))
        end
    end
    local sell = drawnRow(c, "vendor.list")
    t.eq(sell.under, nil)
    t.ok(holds(sell.tip, saved .. "account"), "the tooltip says so")
    t.eq(type(sell.desc), "string", "one short line of description")
    t.ok(type(sell.desc) == "string" and #sell.desc <= addon.SettingsOptions.DESC_MAX, "no longer than one line")
    t.eq(type(sell.tip) == "table" and sell.tip[1], sell.help, "the whole description leads the tooltip")
end

-- Holds before for the large topics (every section was headed); after, a
-- topic of ten rows or fewer has no heading at all.
tests["settings layout: section headings stand only in a topic of more than ten rows; Combat has them"] = function(t)
    local c, addon = boot()
    slash(c, "settings")
    if not ready(t, c) then return end
    local over = addon.SettingsOptions.SECTIONS_OVER
    t.eq(over, 10)
    for _, topic in ipairs(c.optionsLayout().topics) do
        c.optionsNav("topic", topic.id)
        local n, sections = #drawn(c), count(c, "section")
        if n <= 10 then
            t.eq(sections, 0, topic.id .. ": " .. n .. " rows, no heading")
        end
        if topic.id == "combat" then
            t.ok(n > 10, "Combat is a large topic: " .. n)
            t.ok(sections >= 2, "and is headed by section: " .. sections)
        end
    end
end

-- Fails before: the fake has no optionsEntry; the game's Options held the
-- whole page.
tests["settings layout entrances: the Options entry's button, the slash word, the arrow menu and the info bar all open the one window"] = function(t)
    local c, addon = boot({ arrows = true })
    if not ready(t, c) then return end
    local entry = c.optionsEntry()
    t.ok(type(entry) == "table", "the add-on has its entry in the game's Options")
    if type(entry) ~= "table" then return end
    t.eq(entry.title, ns.id.title)
    t.eq(c.optionsEntryShow(), true, "the player opens the entry")
    local buttons = {}
    for _, r in ipairs(entry.rows or {}) do
        t.eq(r.key, nil, "no setting stands on the game's panel")
        for _, action in ipairs(r.actions or {}) do buttons[#buttons + 1] = action end
    end
    t.eq(#buttons, 1, "one button")
    if #buttons ~= 1 then return end
    t.eq(buttons[1].label, "Open " .. ns.id.title .. " settings")
    t.eq(c.optionsOpened(), 0, "looking at the entry opens nothing")
    t.eq(c.optionsEntryPress(buttons[1].key), true)
    t.eq({ c.optionsOpened(), c.optionsShown() }, { 1, true }, "the button opens the window")
    t.eq(heading(c), T.LIST[1].name)

    c.optionsHide()
    slash(c, "settings")
    t.eq({ c.optionsOpened(), c.optionsShown() }, { 2, true }, "the slash word")

    c.optionsHide()
    slash(c, "arrow demo")
    c.advance(0.1, 2)
    local q = c.arrows[1]
    t.ok(q ~= nil and type(q.pickRow) == "function", "the arrow has its menu")
    if not (q and type(q.pickRow) == "function") then return end
    q.click("right")
    t.eq(q.pickRow("settings.travel"), true)
    t.eq({ c.optionsOpened(), c.optionsShown() }, { 3, true }, "the arrow menu's topic row")
    t.eq(heading(c), T.Find("travel").name, "at its topic")

    c.optionsHide()
    t.eq(addon.settings:set("infoBar.shown", true), true)
    local bar = type(c.infoBars) == "table" and c.infoBars[1] or nil
    t.ok(bar ~= nil, "the info bar is made")
    if not bar then return end
    bar.click("LeftButton")
    t.eq({ c.optionsOpened(), c.optionsShown() }, { 4, true }, "a click on the info bar")
    t.eq(c.optionsPagesMade(), 1, "one window, made once, for every way in")
    t.eq(c.optionsLayout().title, ns.id.title .. tostring(addon.SettingsOptions.WINDOW))
end

-- Fails before: the fake has no optionsEntry. The slash word's refusal is
-- as it was.
tests["settings layout in combat: the window is not opened from the slash word or the Options entry, and a change is refused"] = function(t)
    local c, addon = boot()
    if not ready(t, c) then return end
    local O = addon.SettingsOptions
    slash(c, "settings")
    c.optionsNav("topic", "bags")
    -- boot() pins the lock (setLockdown(false)), so the fight moves it too,
    -- as the game's lock follows a fight.
    c.setCombat(true)
    c.setLockdown(true)
    t.eq(c.optionsAct("vendor.list", false), false, "no change in a fight")
    t.eq(addon.settings:get("vendor.list"), true)
    t.eq(c.optionsStatus(), O.IN_COMBAT)
    c.optionsHide()
    local opened = c.optionsOpened()
    slash(c, "settings")
    t.eq(c.optionsOpened(), opened, "the slash word does not open it")
    local p = panelOf(c, "Settings")
    t.ok(p ~= nil and p.shown == true, "the text page is shown instead, as before")
    c.optionsEntryShow()
    local key
    for _, r in ipairs(c.optionsEntry().rows or {}) do
        for _, action in ipairs(r.actions or {}) do key = action.key end
    end
    t.eq(c.optionsEntryPress(key), false, "nor does the entry's button")
    t.eq(c.optionsOpened(), opened)
    t.eq(c.optionsEntry().status, O.LOCKED, "and the entry says why")
    c.setCombat(false)
    c.setLockdown(false)
    t.eq(c.optionsEntryPress(key), true)
    t.eq(c.optionsOpened(), opened + 1, "after the fight it opens")
    t.eq(heading(c), T.Find("bags").name, "where the player was")
end

-- Section 236, an ask that raises then recovers: the window's draw.
-- Fails before: the fake has no setSettingsDrawFault; a draw that raised
-- went up through the slash word.
-- The fault count was 2 when this was written before the kit: the game's
-- Options page was drawn twice an open (once by its show, once by the
-- open). The kit window is drawn once an open, so two faults would also
-- fail the second ask, which this case expects to draw. One draw raises.
tests["settings layout recovery: a draw that raises is listed, the text page takes over, and the next open draws"] = function(t)
    local c, addon = boot()
    if not ready(t, c) then return end
    local problems = addon.problems:count()
    c.setSettingsDrawFault(1)
    local ok = pcall(slash, c, "settings")
    t.eq(ok, true, "the slash word does not raise")
    t.ok(addon.problems:count() > problems, "the failed draw is listed as a problem")
    t.eq(c.optionsShown(), false, "an empty window is not left open")
    t.eq(c.optionsRows(), nil, "nothing was drawn")
    local p = panelOf(c, "Settings")
    t.ok(p ~= nil and p.shown == true, "the text page is shown instead")
    slash(c, "settings")
    t.eq(c.optionsShown(), true, "the next ask opens the window")
    t.eq(heading(c), T.LIST[1].name, "and draws it")
    t.eq((c.optionsAct("vendor.list", false)), true, "and a change works")
    t.eq(addon.settings:get("vendor.list"), false)
end

return tests

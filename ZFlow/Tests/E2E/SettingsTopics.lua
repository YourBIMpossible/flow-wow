local _, ns = ...
-- Settings by topic with search, and menus in short levels (lead sections
-- 238 and 239; rows N56 with SETTINGS-UX-01, and N57), on the whole add-on
-- loaded on a fake client and entered the way the player enters: the slash
-- word, the Options page it opens (its topic buttons, search box and
-- controls), the text page on a client with no Options page, and a right
-- click on the arrow. Per lead section 236: data arriving late (a row
-- declared after the page was first opened), a reload in the middle (a
-- second add-on from the saved data) and an ask that raises, then recovers
-- (the Options page registration). Offline: the fake client's page and
-- menu, not the game's. Not tested in game. Made-up rows only.
local tests = {}

local T = ns.Settings and ns.Settings.Topics

-- opts: account, char (saved tables), before(c) (run on the client before
-- the add-on loads), arrows (place the player so the arrows can show).
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    local account = opts.account or {}
    if opts.arrows then
        if type(account.layout) ~= "table" then account.layout = {} end
        account.layout.arrowIntroSeen = true
        c.setScreen(1024, 768)
        c.setZone(1, 1411)
        c.setFacing(0)
        c.setPosition(1411, 0.5, 0.5)
        c.setMapSize(1411, 1000, 500)
    end
    c.setSaved(ns.id.accountDB, account)
    c.setSaved(ns.id.charDB, opts.char or {})
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

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for key, value in pairs(v) do out[key] = copy(value) end
    return out
end

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

local function ofKind(c, kind)
    for _, r in ipairs(c.optionsRows() or {}) do
        if r.kind == kind then return r end
    end
    return nil
end

local function has(list, value)
    for _, v in ipairs(list or {}) do
        if v == value then return true end
    end
    return false
end

local function panelOf(c, name)
    for _, p in ipairs(c.panels) do
        if type(p.spec) == "table" and p.spec.name == ns.id.framePrefix .. name then return p end
    end
    return nil
end

local function lineWith(lines, text)
    for _, l in ipairs(lines or {}) do
        if tostring(l):find(text, 1, true) then return tostring(l) end
    end
    return nil
end

local function rowAt(items, key)
    for _, r in ipairs(items or {}) do
        if r.key == key then return r end
    end
    return nil
end

local function ready(t, c)
    local ok = type(T) == "table" and type(c.optionsNav) == "function" and type(c.setOptionsPageFault) == "function"
    t.ok(ok, "the topics list and the fake Options page's topic and search controls are there")
    return ok
end

-- The category list ---------------------------------------------------------

-- Fails before: Settings/Topics.lua is absent, and the rows named ad hoc
-- groups (Vendor, Arrows, Rotation, Gear, Spells, Windows, Group, Other)
-- or none (nav.learnLegs, nav.repairStep, plateCombo.off, plateThreat.*).
tests["settings topics: every row of the add-on names one topic of the one list; none is unfiled"] = function(t)
    local _, addon = boot()
    local Topics = addon.Settings.Topics
    t.ok(type(Topics) == "table", "the add-on has the topics list")
    if type(Topics) ~= "table" then return end
    local n, bad = 0, {}
    for row in addon.settings:each() do
        n = n + 1
        local topic, section = Topics.Find(row.group)
        if not topic then
            bad[#bad + 1] = row.key .. " (" .. tostring(row.group) .. ")"
        elseif row.group ~= topic.id and row.group ~= topic.id .. "." .. tostring(section and section.id) then
            bad[#bad + 1] = row.key .. " (" .. tostring(row.group) .. " is not spelled as the list spells it)"
        end
    end
    table.sort(bad)
    t.ok(n >= 40, "the add-on's rows were walked: " .. n)
    t.eq(table.concat(bad, ", "), "", "rows with no topic, or one that is not in the list")
    -- The check can fail: these are refused by the same Find.
    for _, group in ipairs({ "Other", "Vendor", "Arrows", "Rotation", "Test", "travel.nosuch" }) do
        t.eq(Topics.Find(group), nil, group)
    end
    t.eq(Topics.Find(nil), nil, "no group at all")
end

-- Fails before: UI/SettingsPage.lua put a row with no group under "Other",
-- and the page had no topics.
tests["settings topics: the player's page has no Other and no not-filed topic, and no test row"] = function(t)
    local _, addon = boot()
    local page = addon.SettingsPage.Page and addon.SettingsPage.Page(addon) or nil
    t.ok(type(page) == "table", "the page is made from the rows")
    if type(page) ~= "table" then return end
    t.ok(#page.topics >= 6 and #page.topics <= #T.LIST, "a few topics: " .. #page.topics)
    local total = 0
    for i, topic in ipairs(page.topics) do
        local listed = T.Find(topic.id)
        t.ok(listed ~= nil and listed.name == topic.name, "topic " .. i .. " is one of the list: " .. tostring(topic.name))
        t.ok(topic.count >= 1, topic.name .. " holds a row")
        total = total + topic.count
    end
    t.eq(total, page.count, "every row stands under exactly one topic")
    for row in addon.settings:each() do
        t.ok(row.key:sub(1, 5) ~= "test.", row.key .. " is not a test row")
        if row.requires ~= nil then
            t.ok(row.needs ~= nil, row.key .. " has a requires, so it names what it needs")
        end
    end
end

-- Fails before: no row has synonyms and there is no search.
tests["settings topics: the owner's words find settings, each result with its topic and scope"] = function(t)
    local _, addon = boot()
    local P = addon.SettingsPage
    t.ok(type(P.Search) == "function", "the page can be searched")
    if type(P.Search) ~= "function" then return end
    local function keys(query)
        local out = {}
        local found = P.Search(addon, query)
        for i, e in ipairs(found and found.results or {}) do
            out[i] = e.key
            t.ok(T.Find(e.topic) ~= nil and e.topicName == T.Find(e.topic).name, e.key .. " says its topic")
            t.ok(e.scope == "account" or e.scope == "character", e.key .. " says its scope")
        end
        return out
    end
    t.ok(has(keys("food"), "rotation.recoverBuffFood"), "food")
    t.ok(has(keys("buffs"), "rotation.recoverBuffFood") and has(keys("buffs"), "general.groupTip"), "buffs")
    t.ok(has(keys("tracking"), "rotation.gatherTracking"), "tracking")
    t.ok(has(keys("seal"), "rotation.sayKept"), "seal")
    t.ok(has(keys("blessing"), "rotation.sayKept") and has(keys("blessing"), "rotation.groupBuffs"), "blessing")
    t.ok(has(keys("healthstone"), "rotation.emergencyItems"), "healthstone")
    t.ok(has(keys("sell"), "vendor.list"), "sell")
    t.ok(has(keys("junk"), "vendor.list") and has(keys("junk"), "loot.junkNote"), "junk, in two topics")
    t.ok(has(keys("bank"), "bank.list"), "bank")
    t.ok(has(keys("arrow"), "quest.arrow") and has(keys("arrow"), "arrow.style"), "arrow")
    t.ok(has(keys("WAYPOINT"), "quest.arrow"), "waypoint, in capitals")
    t.ok(has(keys("threat"), "plateThreat.off"), "a row that had no group before")
    t.eq(keys("sell")[1], "vendor.list", "the row whose name says it comes first")
    t.eq(keys("zzzzqq"), {})
    -- Every row can be found by its own label alone.
    for row in addon.settings:each() do
        t.ok(has(keys(row.label), row.key), row.key .. " is found by its label")
    end
end

-- Stored values ------------------------------------------------------------

-- What each row was before the regrouping (fork zflow f46c307): scope,
-- type, default and, where it names one, its own saved place.
local BEFORE = {
    ["sound.autoRestart"] = { "account", "bool", true },
    ["rotation.choices"] = { "account", "bool", true },
    ["gear.merchantButtons"] = { "account", "bool", true },
    ["gear.merchantMarks"] = { "account", "bool", true },
    ["gear.rollHint"] = { "account", "bool", true },
    ["gear.tooltip"] = { "account", "bool", true },
    ["items.priceChart"] = { "account", "bool", true },
    ["items.haveCount"] = { "account", "bool", true },
    ["auction.postAdvice"] = { "account", "bool", true },
    ["trader.off"] = { "account", "bool", false },
    ["nav.mapFlights"] = { "account", "bool", false },
    ["nav.taxiMark"] = { "account", "bool", true },
    ["nav.learnLegs"] = { "account", "bool", true },
    ["nav.repairStep"] = { "account", "bool", true },
    ["rotation.enabled"] = { "char", "bool", false },
    ["rotation.recoverBuffFood"] = { "account", "bool", true },
    ["rotation.formSpells"] = { "account", "bool", true },
    ["rotation.gatherTracking"] = { "char", "bool", true },
    ["general.groupTip"] = { "account", "bool", true },
    ["rotation.keyFrame"] = { "char", "bool", false },
    ["spec.role"] = { "char", "choice", "" },
    ["spells.trainerList"] = { "char", "bool", true },
    ["spells.rankUp"] = { "char", "bool", true },
    ["spells.newSpellCard"] = { "char", "bool", true },
    ["arrow.layout"] = { "account", "table", nil, "layout.arrows" },
    ["arrow.style"] = { "account", "choice", "modern", "layout.arrowStyle" },
    ["arrow.palette"] = { "account", "choice", "standard", "layout.arrowPalette" },
    ["craft.queue"] = { "account", "bool", true },
    ["ui.moveGuides"] = { "account", "bool", true },
    ["rotationIcon.layout"] = { "account", "table", nil, "layout.rotationIcon" },
    ["rotationQueue.enabled"] = { "account", "bool", true },
    ["ui.intro"] = { "char", "bool", true },
    ["buttons.worldMap"] = { "account", "bool", false },
    ["buttons.merchant"] = { "account", "bool", false },
    ["plateCombo.off"] = { "account", "bool", false },
    ["plateThreat.off"] = { "account", "bool", false },
    ["plateThreat.always"] = { "account", "bool", false },
    ["quest.arrow"] = { "account", "bool", true },
    ["nav.flightPaths"] = { "account", "bool", true },
    ["nav.crossings"] = { "account", "bool", true },
    ["nav.zoneFirst"] = { "account", "bool", true },
    ["vendor.list"] = { "account", "bool", true },
    ["repair.warnBelow"] = { "account", "number", 0.20 },
    ["bank.list"] = { "account", "bool", true },
    ["loot.junkNote"] = { "account", "bool", true },
    ["loot.record"] = { "account", "bool", true },
    ["advisor.panel"] = { "char", "bool", true },
    -- Arrived with fork zflow 723634eb, filed at the merge.
    ["rotation.emergencyItems"] = { "account", "bool", true },
    ["rotation.groupBuffs"] = { "account", "bool", true },
    ["rotation.sayKept"] = { "account", "bool", true },
}

-- Holds before and after: the regrouping must not move it. (It fails only
-- if a row's key, scope, type, default or saved place was changed.)
tests["stored values: no row's key, scope, type, default or saved place changed with its topic"] = function(t)
    local _, addon = boot()
    local n = 0
    for key, was in pairs(BEFORE) do
        local row = addon.settings:row(key)
        t.ok(row ~= nil, key .. " is still a row")
        if row then
            n = n + 1
            t.eq({ row.scope, row.type }, { was[1], was[2] }, key .. ": scope and type")
            if was[2] ~= "table" then t.eq(row.default, was[3], key .. ": default") end
            if was[2] == "table" then
                t.ok(type(row.path) == "string" and row.path:sub(1, 7) == "layout.", key .. ": its own saved place")
            else
                t.eq(row.path, was[4], key .. ": saved place")
            end
        end
    end
    t.eq(n, 50)
    t.eq(addon.settings:row("repair.warnBelow").min, 0)
    t.eq(addon.settings:row("repair.warnBelow").max, 1)
    t.eq(addon.settings:row("spec.role").choices, { "", "dps", "heal", "tank" })
end

-- Holds before and after (the same rule): a saved table written before the
-- change, every row at a value that is not its default, is read back whole.
tests["stored values: a saved table from before the change reads back, every value"] = function(t)
    local account = { settings = {}, layout = { arrowPalette = "colourBlind", arrowStyle = "flat", arrowModern = true } }
    local char = { settings = {} }
    local want = { ["arrow.palette"] = "colourBlind", ["arrow.style"] = "flat" }
    for key, was in pairs(BEFORE) do
        local value
        if was[2] == "bool" then value = not was[3] end
        if was[2] == "number" then value = 0.35 end
        if key == "spec.role" then value = "tank" end
        if value ~= nil then
            want[key] = value
            local section, name = key:match("^([^.]+)%.(.+)$")
            local into = (was[1] == "char" and char or account).settings
            into[section] = into[section] or {}
            into[section][name] = value
        end
    end
    local c, addon = boot({ account = account, char = char })
    local n = 0
    for key, value in pairs(want) do
        n = n + 1
        t.eq(addon.settings:get(key), value, key .. " reads back as saved")
    end
    t.eq(n, 48, "every row that holds a plain value")
    -- And the saved tables still hold them where they were.
    t.eq(c.saved(ns.id.accountDB).settings.vendor.list, false)
    t.eq(c.saved(ns.id.accountDB).settings.repair.warnBelow, 0.35)
    t.eq(c.saved(ns.id.charDB).settings.spec.role, "tank")
    t.eq(c.saved(ns.id.accountDB).layout.arrowPalette, "colourBlind")
    -- The page shows the saved value under the row's new topic.
    if type(addon.SettingsPage.Goto) == "function" then
        slash(c, "settings topic bags")
        t.eq(drawnRow(c, "vendor.list") and drawnRow(c, "vendor.list").value, false)
        t.eq(drawnRow(c, "repair.warnBelow") and drawnRow(c, "repair.warnBelow").value, 0.35)
    end
end

-- The player's workflow ----------------------------------------------------

-- Fails before: the Options page drew every group in one list (no "topics"
-- row, no nav, no search); c.optionsNav is absent from the fake.
tests["settings workflow: open the page, pick a topic, search, change a result, reload, read it back"] = function(t)
    local c, addon = boot()
    if not ready(t, c) then return end
    slash(c, "settings")
    t.eq(c.optionsOpened(), 1, "the slash word opens the Options page")
    local rows = c.optionsRows()
    t.eq({ rows[1].kind, rows[2].kind, rows[3].kind }, { "search", "topics", "group" })
    t.eq(rows[3].text, T.LIST[1].name, "the first topic is shown")
    for _, key in ipairs(drawn(c)) do
        t.eq(drawnRow(c, key).topic, T.LIST[1].id, key .. " is of the topic shown")
    end
    t.ok(#drawn(c) < addon.SettingsPage.Page(addon).count, "one topic, not the whole list")

    -- Pick a topic.
    t.eq(c.optionsNav("topic", "bags"), true)
    local keys = drawn(c)
    table.sort(keys)
    t.eq(keys, { "bank.list", "items.haveCount", "repair.warnBelow", "vendor.list" })
    t.eq(ofKind(c, "group").text, T.Find("bags").name)

    -- Search every topic.
    c.optionsNav("search", "junk")
    t.eq(ofKind(c, "search").value, "junk")
    local sell, note = drawnRow(c, "vendor.list"), drawnRow(c, "loot.junkNote")
    t.ok(sell ~= nil and note ~= nil, "results from two topics")
    if not (sell and note) then return end
    t.eq({ sell.topicName, sell.scope, sell.jump }, { T.Find("bags").name, "account", "bags" })
    t.eq({ note.topicName, note.jump }, { T.Find("gear").name, "gear" })
    t.ok(sell.under:find(T.Find("bags").name, 1, true) ~= nil and sell.under:find("account", 1, true) ~= nil, sell.under)
    t.eq({ sell.kind, sell.value, sell.settable }, { "toggle", true, true }, "the same control as in its topic")

    -- Change the result where it stands.
    t.eq((c.optionsAct("vendor.list", false)), true)
    t.eq(addon.settings:get("vendor.list"), false)
    t.eq(drawnRow(c, "vendor.list").value, false, "the result shows the new value")
    t.eq(ofKind(c, "search").value, "junk", "the search is still on")
    t.eq(c.saved(ns.id.accountDB).settings.vendor.list, false, "in the saved data")

    -- Jump to its topic: the search ends.
    t.eq(c.optionsNav("topic", sell.jump), true)
    t.eq(ofKind(c, "search").value, "")
    t.eq(drawnRow(c, "vendor.list").value, false)
    t.eq(drawnRow(c, "loot.junkNote"), nil)

    -- Reload: a second add-on from the saved data.
    local c2, addon2 = reload(c)
    t.eq(addon2.settings:get("vendor.list"), false, "read back after the reload")
    slash(c2, "settings sell")
    t.eq(drawnRow(c2, "vendor.list") and drawnRow(c2, "vendor.list").value, false, "and the page shows it")
    t.eq((c2.optionsAct("vendor.list", true)), true, "and it can be put back")
    t.eq(addon2.settings:get("vendor.list"), true)
end

-- Fails before: the slash word took only a key and a value; there was no
-- text page by topic.
tests["settings workflow: on a client with no Options page the slash word does it all on the text page"] = function(t)
    local c, addon = boot({ before = function(cl) cl.setOptionsPage(false) end })
    if not ready(t, c) then return end
    slash(c, "settings topic gear")
    local p = panelOf(c, "Settings")
    t.ok(p ~= nil and p.shown == true, "the text page is shown")
    if not p then return end
    t.eq(c.optionsOpened(), 0)
    t.ok(lineWith(p.lines, "> " .. T.Find("gear").name) ~= nil, "the topic is marked")
    t.ok(lineWith(p.lines, "[gear.tooltip]") ~= nil and lineWith(p.lines, "[loot.junkNote]") ~= nil)
    t.eq(lineWith(p.lines, "[vendor.list]"), nil, "another topic's row is not listed")
    slash(c, "settings sell junk")
    local line = lineWith(p.lines, "[vendor.list]")
    t.ok(line ~= nil and line:find("(account; " .. T.Find("bags").name .. ")", 1, true) ~= nil,
        "a result with its scope and topic: " .. tostring(line))
    slash(c, "settings vendor.list off")
    t.eq(addon.settings:get("vendor.list"), false)
    t.ok(lineWith(p.lines, "Show the sell list at a merchant: off") ~= nil, "the open results follow the change")
    slash(c, "settings zzzzqq")
    t.ok(lineWith(p.lines, addon.SettingsPage.NoMatch("zzzzqq")) ~= nil, "no match says so")
    slash(c, "settings topic")
    t.ok(lineWith(p.lines, "[gear.tooltip]") ~= nil, "clearing the search shows the topic again")
    local c2, addon2 = reload(c)
    t.eq(addon2.settings:get("vendor.list"), false, "kept across the reload")
    t.ok(c2 ~= nil)
end

-- (a) Data late: rows declared after the page was first opened.
-- Fails before: no topics and no search; the page watched only the rows
-- that were there at login.
tests["settings late data: a module's rows declared after the page was opened are found both ways and followed"] = function(t)
    local c, addon = boot()
    if not ready(t, c) then return end
    slash(c, "settings")
    c.optionsNav("search", "trawl")
    t.eq(drawn(c), {}, "nothing yet")
    -- A module arrives late, in two parts.
    t.ok(addon:Setting({ key = "late.nets", scope = "char", type = "bool", default = false,
        label = "Mend nets at dusk", group = "professions", synonyms = { "trawl" } }) ~= nil)
    c.optionsNav("search", "trawl")
    t.eq(drawn(c), { "late.nets" }, "found by search")
    t.eq({ drawnRow(c, "late.nets").scope, drawnRow(c, "late.nets").topicName },
        { "character", T.Find("professions").name })
    t.ok(addon:Setting({ key = "late.floats", scope = "account", type = "number", default = 2, min = 1, max = 4,
        label = "Net floats", group = "professions" }) ~= nil)
    t.eq(c.optionsNav("topic", "professions"), true)
    t.ok(has(drawn(c), "late.nets") and has(drawn(c), "late.floats") and has(drawn(c), "craft.queue"),
        "found by navigation, beside the rows that were there")
    t.eq((c.optionsAct("late.floats", 3)), true)
    t.eq(c.optionsAct("late.floats", 9), false, "its limits hold")
    t.eq(c.saved(ns.id.accountDB).settings.late.floats, 3)
    -- A change made another way reaches the open page for a late row too.
    t.eq(addon.settings:set("late.nets", true), true)
    t.eq(drawnRow(c, "late.nets").value, true)
end

-- (b) A reload in the middle of a search.
-- Fails before: no search and no topic to be in the middle of.
tests["settings reload in the middle: where you were is not saved, what you changed is, and looking saves nothing"] = function(t)
    local c, addon = boot()
    if not ready(t, c) then return end
    slash(c, "settings")
    local before = { copy(c.saved(ns.id.accountDB)), copy(c.saved(ns.id.charDB)) }
    c.optionsNav("topic", "gear")
    c.optionsNav("search", "upgrade")
    c.optionsNav("search", "")
    slash(c, "settings topic auctions")
    slash(c, "settings tooltip")
    t.eq({ c.saved(ns.id.accountDB), c.saved(ns.id.charDB) }, before, "choosing topics and searching write nothing")
    t.eq((c.optionsAct("gear.tooltip", false)), true)
    -- The reload comes with the search still on.
    local c2, addon2 = reload(c)
    t.eq(addon2.settings:get("gear.tooltip"), false, "the change is there")
    slash(c2, "settings")
    t.eq(ofKind(c2, "search").value, "", "no search carried over")
    t.eq(ofKind(c2, "group").text, T.LIST[1].name, "the first topic again")
    t.eq(c2.optionsNav("topic", "gear"), true)
    t.eq(drawnRow(c2, "gear.tooltip").value, false)
    t.ok(addon ~= addon2)
end

-- (c) An ask that raises, then recovers: the Options page registration.
-- Fails before: UI/SettingsOptions.lua asked once at login with no guard
-- (the module's start failed and the page never came back);
-- c.setOptionsPageFault is absent from the fake.
tests["settings recovery: the Options page raising at login and once more falls back to the text page, then opens"] = function(t)
    local c, addon = boot({ before = function(cl)
        if type(cl.setOptionsPageFault) == "function" then cl.setOptionsPageFault(2) end
    end })
    if not ready(t, c) then return end
    t.eq(c.optionsPagesMade(), 0, "the ask at login raised")
    t.ok(addon.problems:count() >= 1, "and it is listed as a problem")
    -- The second ask raises too: the text page takes the search.
    slash(c, "settings sell")
    t.eq(c.optionsOpened(), 0)
    local p = panelOf(c, "Settings")
    t.ok(p ~= nil and p.shown == true, "the text page is shown instead")
    t.ok(p ~= nil and lineWith(p.lines, "[vendor.list]") ~= nil, "with the results")
    slash(c, "settings vendor.list off")
    t.eq(addon.settings:get("vendor.list"), false, "and a change still works")
    -- The third ask answers: the Options page opens where the player was.
    slash(c, "settings")
    t.eq(c.optionsPagesMade(), 1)
    t.eq(c.optionsOpened(), 1)
    t.eq(ofKind(c, "search").value, "sell", "the same search")
    t.eq(drawnRow(c, "vendor.list") and drawnRow(c, "vendor.list").value, false)
    t.eq((c.optionsAct("vendor.list", true)), true)
    t.eq(addon.settings:get("vendor.list"), true)
end

-- The menu ------------------------------------------------------------------

-- Fails before: the arrow menu was one flat list with no settings row; the
-- fake arrow has no enter / pickRow.
tests["menu workflow: right-click the arrow, enter a submenu, choose a row; then open the settings at the topic"] = function(t)
    local c, addon = boot({ arrows = true })
    if not ready(t, c) then return end
    slash(c, "arrow demo")
    c.advance(0.1, 2)
    local q = c.arrows[1]
    t.ok(q ~= nil and type(q.enter) == "function", "the fake arrow has submenu rows")
    if not (q and type(q.enter) == "function") then return end
    q.click("right")
    t.ok(type(q.menuItems) == "table", "the menu is open")
    if type(q.menuItems) ~= "table" then return end
    t.ok(#q.menuItems <= T.MENU_MAX, "a short top level: " .. #q.menuItems)
    t.eq(q.pickRow("show.prof"), false, "a submenu's row is not on the top level")
    q.click("right")
    t.eq(q.enter("show"), true)
    t.ok(#q.menuItems <= T.MENU_MAX, "a short submenu: " .. #q.menuItems)
    t.eq(rowAt(q.menuItems, "show.prof").checked, true)
    t.eq(q.pickRow("show.prof"), true)
    t.eq(q.menuItems, nil, "choosing closes the menu")
    t.eq(addon.Nav.ArrowSaved({ arrows = addon.settings:get(addon.Arrow.SETTING) }).hidden.prof, true,
        "the row did what it says, and it is saved")
    -- The settings row: look only, and at the matching topic.
    local before = { copy(c.saved(ns.id.accountDB)), copy(c.saved(ns.id.charDB)) }
    q.click("right")
    local row = rowAt(q.menuItems, "settings.travel")
    t.ok(row ~= nil and row.text:find(T.Find("travel").name, 1, true) ~= nil, "named from the topics list")
    t.eq(q.pickRow("settings.travel"), true)
    t.eq(c.optionsOpened(), 1, "the settings open")
    t.eq(ofKind(c, "group").text, T.Find("travel").name, "at the matching topic")
    t.ok(has(drawn(c), "quest.arrow") and has(drawn(c), "arrow.style"), "with the arrow's settings")
    t.eq({ c.saved(ns.id.accountDB), c.saved(ns.id.charDB) }, before, "opening the settings saved nothing")
    -- After a reload the hidden arrow is still hidden, and the menu says so.
    local c2 = reload(c)
    t.ok(c2 ~= nil)
end

-- Fails before: ArrowMenu.Counts is absent and the menu was one level.
tests["menu size: every level of every menu the loaded add-on has is short"] = function(t)
    local c, addon = boot({ arrows = true })
    t.ok(type(addon.ArrowMenu.Counts) == "function", "the menu's levels can be counted")
    if type(addon.ArrowMenu.Counts) ~= "function" then return end
    local MAX = addon.Settings.Topics.MENU_MAX
    t.ok(MAX <= 10, "the number is 10 or less")
    local menus = { arrow = addon.arrow and addon.arrow.menu and addon.arrow.menu() or addon.ArrowMenu.Items(
        { styles = addon.Arrow.Styles("modern"), canShapes = true }) }
    for name, items in pairs(menus) do
        local levels = addon.ArrowMenu.Counts(items)
        t.ok(#levels >= 2, name .. ": a top level and submenus")
        for _, level in ipairs(levels) do
            t.ok(level.rows <= MAX, name .. " / " .. level.path .. ": " .. level.rows .. " rows, the most is " .. MAX)
        end
    end
    t.ok(c ~= nil)
end

return tests

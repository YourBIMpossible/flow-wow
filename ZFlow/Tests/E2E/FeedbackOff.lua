local _, ns = ...
-- Lead section 284: in-game feedback (row N73) is paused by owner decision
-- of 2026-11-23. Its code stays, but a player cannot reach it: one internal
-- switch, off by default, that is not a setting (no settings row, no hit in
-- the settings search, nothing in saved data or an imported profile). With
-- it off there is no slash word, help line, settings row, settings search
-- hit, arrow menu row or module, and no feedback work runs. Nothing saved
-- is deleted. Only the fake client can turn the switch on, for the tests:
-- ns.make.fakeClient({ internal = { feedback = true } }). Whole add-on on a
-- fake client, made-up names only. Not tested in game.
local tests = {}

local KEY = "feedback.diagnostics"
local WORDS = { "feedback", "bug", "report", "problem", "idea", "suggest" }

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for key, value in pairs(v) do out[key] = copy(value) end
    return out
end

-- opts: account (saved table), on (the internal switch on the fake).
local function boot(opts)
    opts = opts or {}
    local spec = { env = {
        UnitName = function() return "Zarkon" end,
        GetRealmName = function() return "Stormrage" end,
        GetBuildInfo = function() return "1.16.1", "7777" end,
    } }
    if opts.on then spec.internal = { feedback = true } end
    local c = ns.make.fakeClient(spec)
    local account = opts.account or {}
    if type(account.layout) ~= "table" then account.layout = {} end
    account.layout.arrowIntroSeen = true
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFacing(0)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    c.setSaved(ns.id.accountDB, account)
    c.setSaved(ns.id.charDB, {})
    c.setVersion("0.1.0")
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function slash(c, rest) c.slashes[ns.id.slash](rest) end

local function window(c)
    for _, p in ipairs(c.rowPanels or {}) do
        if type(p.spec) == "table" and p.spec.name == ns.id.framePrefix .. "Feedback" then return p end
    end
    return nil
end

local function saidSince(c, from, text)
    local printed = c.printed or {}
    for i = from + 1, #printed do
        if tostring(printed[i]):lower():find(text, 1, true) then return true end
    end
    return false
end

-- Every way in, tried as the player would. -> { way = reached }
local function reach(c, addon)
    local got = {}
    got.module = addon.use("feedback") ~= nil
    local diag = addon.diag or {}
    got.help = type(diag.help) == "table" and diag.help.feedback ~= nil
    got.word = type(diag.commands) == "table" and diag.commands.feedback ~= nil
    local from = #(c.printed or {})
    slash(c, "feedback")
    got.slash = window(c) ~= nil or saidSince(c, from, "feedback is not ready")
    got.row = addon.settings:row(KEY) ~= nil
    local hit = false
    for _, word in ipairs(WORDS) do
        local found = addon.SettingsPage.Search(addon, word)
        for _, e in ipairs(found and found.results or {}) do
            if e.key == KEY then hit = true end
        end
    end
    got.search = hit
    slash(c, "settings feedback")
    local onPage = false
    for _, r in ipairs(c.optionsRows() or {}) do
        if r.key == KEY then onPage = true end
    end
    got.page = onPage
    slash(c, "arrow demo")
    c.advance(0.1, 2)
    local q = c.arrows[1]
    local inMenu = false
    if q then
        q.click("right")
        inMenu = q.pickRow("feedback") == true
    end
    got.menu = inMenu
    got.window = window(c) ~= nil
    return got
end

local NONE = { module = false, help = false, word = false, slash = false, row = false, search = false,
               page = false, menu = false, window = false }
local ALL = { module = true, help = true, word = true, slash = true, row = true, search = true,
              page = true, menu = true, window = true }

-- Fails before: the slash word, the settings row, the search and the arrow
-- menu all reach the feedback window on a default boot.
tests["feedback off: a default profile has no way in, no window and no feedback work"] = function(t)
    local c, addon = boot()
    t.eq(reach(c, addon), NONE, "no slash word, help line, settings row, search hit, menu row or module")
    c.advance(30, 60)
    t.eq(window(c), nil, "nothing made later either")
    local Menu = addon.ArrowMenu
    t.eq(Menu.Action(Menu.FEEDBACK, {}), nil, "a menu state without feedback has no feedback action")
end

-- Fails before: the import applies the feedback setting, and the boots
-- show every way in.
tests["feedback off: an imported profile or saved data with the setting on cannot turn it on"] = function(t)
    local c, addon = boot()
    local text = table.concat({ "ZFLOW-EXPORT:1", "account:" .. KEY .. "=bool:1", "END:1" }, ";")
    local plan = addon.settingsShare.importText(text)
    t.ok(plan ~= nil, "the text is read")
    t.eq(plan and #plan.changes, 0, "it changes nothing")
    t.eq(plan and #plan.skipped, 1, "the feedback part is skipped: no such setting")
    addon.settingsShare.confirm()
    t.eq(reach(c, addon), NONE, "after the import: still no way in")

    local saved = { settings = { feedback = { diagnostics = true } } }
    local c2, addon2 = boot({ account = copy(saved) })
    t.eq(reach(c2, addon2), NONE, "saved data with the setting on: still no way in")

    local c3, addon3 = boot({ account = copy(saved), on = true })
    t.eq(addon3.settings:get(KEY), true, "guard: the saved value is the real setting, read when on")
    t.eq(reach(c3, addon3), ALL, "guard: with the switch on the fake, every way in is there")
end

-- Fails before: with the switch absent the off boot shows the row.
tests["feedback off: saved feedback data is kept through an off boot and a reload"] = function(t)
    local saved = { settings = { feedback = { diagnostics = true } } }
    local c, addon = boot({ account = copy(saved) })
    t.eq(addon.settings:row(KEY), nil, "off: no row")
    local after = c.saved(ns.id.accountDB)
    t.eq(after.settings and after.settings.feedback, saved.settings.feedback, "off: the saved value is not deleted")
    local c2 = boot({ account = copy(after) })
    local after2 = c2.saved(ns.id.accountDB)
    t.eq(after2.settings and after2.settings.feedback, saved.settings.feedback, "nor by a reload")
    local _, addon3 = boot({ account = copy(after2), on = true })
    t.eq(addon3.settings:get(KEY), true, "on again: the value is there")
end

-- Fails before: the settings search finds the feedback row. The switch
-- itself is no setting either: no row key holds the word.
tests["feedback off: the switch is in no setting, row or search"] = function(t)
    local _, addon = boot()
    local named = {}
    for row in addon.settings:each() do
        if row.key:lower():find("feedback", 1, true) then named[#named + 1] = row.key end
    end
    t.eq(named, {}, "no settings row names feedback")
    local found = addon.SettingsPage.Search(addon, "feedback")
    local keys = {}
    for _, e in ipairs(found and found.results or {}) do
        if type(e.key) == "string" and e.key:lower():find("feedback", 1, true) then keys[#keys + 1] = e.key end
    end
    t.eq(keys, {}, "the settings search finds no feedback row")
end

return tests

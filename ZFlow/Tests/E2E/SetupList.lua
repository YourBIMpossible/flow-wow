-- The setup checklist (G53, UI/SetupList.lua), end to end on the whole
-- add-on loaded on a fake client: opened by its word, a tick sets the
-- setting and nothing else does, the game's own options are only read,
-- and it opens by itself once, after the welcome. Not tested in game.
local _, ns = ...
local tests = {}

-- Rows another file declares (UI/GameOptions.lua), named here once.
local ZOOM, CHAT = "game.cameraZoom", "game.chatTimes"

local function S() return ns.SetupList end

local function boot(char, game)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, char or {})
    c.putGameSetting("cameraDistanceMaxZoomFactor", "1.9")
    c.putGameSetting("showTimestamps", "none")
    for name, v in pairs(game or {}) do c.putGameSetting(name, v) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(2, 10)
    return c, addon
end

local function open(c)
    c.slashes[ns.id.slash](S().WORD)
    return c.kitWindows()[S().ID]
end

local function part(rec, key)
    for _, p in ipairs(rec and rec.parts or {}) do
        if p.key == key then return p end
    end
end

tests["setup: a first login does not open it over the welcome; the word does"] = function(t)
    local c, addon = boot()
    t.eq(c.kitWindows()[S().ID], nil, "not at the first login")
    t.eq(addon.store:get("char", S().SHOWN_PATH), nil)
    local rec = open(c)
    t.ok(rec ~= nil and rec.shown == true, "the word opens it")
    t.eq(addon.diag.help[S().WORD], S().HELP)
    t.eq(addon.store:get("char", S().SHOWN_PATH), nil, "the word leaves the mark alone")
    for _, pr in ipairs(addon.problems:list()) do
        t.ok(pr.kind ~= S().NAME and pr.owner ~= S().NAME, "no problem of its own")
    end
end

tests["setup: a tick sets the setting, an untick sets it back, nothing is ticked for you"] = function(t)
    local c, addon = boot()
    local writes = #c.gameSettingWrites
    local rec = open(c)
    for _, key in ipairs(S().TICKS) do
        local box = part(rec, key)
        t.ok(box ~= nil and box.kind == "checkbox", "a tick box for " .. key)
        t.eq(addon.settings:get(key), false, key .. " starts unticked")
        t.eq(S().Ticks(addon.settings, { key })[1].on, false)
    end
    t.eq(#c.gameSettingWrites, writes, "opening it writes nothing to the game")
    t.eq(c.kitClick(S().ID, "game.chatTimes"), true)
    t.eq(addon.settings:get(CHAT), true)
    t.eq(addon.settings:get(ZOOM), false, "only the one ticked")
    t.eq(S().Ticks(addon.settings, { "game.chatTimes" })[1].on, true, "the box reads the setting")
    t.eq(c.kitClick(S().ID, "game.chatTimes"), true)
    t.eq(addon.settings:get(CHAT), false)
end

tests["setup: the game's own options are read, said on or off, and never written"] = function(t)
    local c = boot(nil, { autoLootDefault = "1", instantQuestText = "0" })
    local writes = #c.gameSettingWrites
    local rec = open(c)
    local on, off = part(rec, "game.1"), part(rec, "game.2")
    t.eq(on and on.text, "Auto loot")
    t.eq(off and off.text, "Instant quest text")
    local rows = S().Game(c, S().GAME)
    t.eq(#rows, 2)
    t.eq(rows[1].on, true)
    t.eq(rows[2].on, false)
    t.eq(rows[2].how, S().HOW:format("Instant Quest Text"), "off: where to turn it on")
    t.eq(part(rec, "game.3"), nil, "an option the game does not say is left out")
    t.eq(#c.gameSettingWrites, writes)
end

tests["setup: pure rows; no setting row and no game answer give an empty list"] = function(t)
    t.eq(S().Ticks(nil, S().TICKS), {})
    t.eq(S().Game({}, S().GAME), {})
    local settings = { row = function(_, key)
        if key == "a" then return { type = "bool", label = "A", help = "About a" } end
        if key == "n" then return { type = "number", label = "N" } end
    end, get = function() return true end }
    t.eq(S().Ticks(settings, { "a", "n", "gone" }), { { key = "a", label = "A", help = "About a", on = true } })
    local client = { gameSetting = function(name) if name == "x" then return "0" end end }
    local rows = S().Game(client, { { setting = "x", on = "1", name = "X", find = "X", why = "Why." },
        { setting = "y", on = "1", name = "Y", find = "Y", why = "Why." } })
    t.eq(#rows, 1)
    t.eq(rows[1].on, false)
    t.eq(rows[1].how, S().HOW:format("X"))
end

tests["setup: it opens by itself once, at a login after the welcome was closed"] = function(t)
    local seen = { state = { intro = { seen = true } } }
    local c, addon = boot(seen)
    t.eq(addon.store:get("char", ns.Intro.SEEN_PATH), true, "the welcome was closed before")
    local rec = c.kitWindows()[S().ID]
    t.ok(rec ~= nil and rec.shown == true, "open at this login")
    t.eq(addon.store:get("char", S().SHOWN_PATH), true)
    t.eq(addon.settings:get(CHAT), false, "still nothing ticked")
    local again = boot({ state = { intro = { seen = true }, setupList = { shown = true } } })
    t.eq(again.kitWindows()[S().ID], nil, "not a second time")
end

tests["setup: the setting off keeps it shut at login; its place is kept"] = function(t)
    local c, addon = boot({ state = { intro = { seen = true } }, settings = { ["ui.setupList"] = false } })
    if addon.settings:get(S().SETTING) == false then
        t.eq(c.kitWindows()[S().ID], nil, "off: not at login")
    end
    open(c)
    local at = { "TOPLEFT", "TOPLEFT", 30, -40 }
    t.eq(c.kitDrag(S().ID, at, 560, 480), true)
    t.eq(addon.store:get("account", S().PATH), { point = at, width = 560, height = 480 })
    addon.setupList.Close()
    t.eq(addon.setupList.Shown(), false)
end

return tests

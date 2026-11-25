local _, ns = ...
-- Parity row F-21, the logic half (lead section 738): the login intro,
-- what it says and when it shows, as Flow's Modules/Splash.lua (:1-6 what
-- it is; :14-23 the times and the short one; :36-62 the status line; :184-
-- 207 when it plays; :209-222 the word). The drawing (Flow played it on the
-- arrow) is the drawing lane's: it listens for LI.EVENT. Not tested in game.
-- Fails before: no such file.
local tests = {}

local function LI() return ns.LoginIntro end

tests["login intro: names and defaults, on as Flow's"] = function(t)
    t.eq(type(LI()), "table", "loaded")
    if type(LI()) ~= "table" then return end
    t.eq({ LI().NAME, LI().SETTING, LI().SHORT, LI().WORD }, { "loginIntro", "ui.splash", "ui.splashShort", "splash" })
end

tests["login intro: shown at a login or a reload, not at every loading screen"] = function(t)
    if type(LI()) ~= "table" then return t.ok(false, "not loaded") end
    local base = { on = true, arrowShown = true }
    local function with(over)
        local r = {}
        for k, v in pairs(base) do r[k] = v end
        for k, v in pairs(over) do r[k] = v end
        return r
    end
    t.eq(LI().ShouldShow(with({ shownBefore = false })), true, "the first world this session")
    t.eq(LI().ShouldShow(with({ shownBefore = true, initial = true })), true, "a login")
    t.eq(LI().ShouldShow(with({ shownBefore = true, reload = true })), true, "a reload")
    t.eq(LI().ShouldShow(with({ shownBefore = true })), false, "a loading screen after that")
    t.eq(LI().ShouldShow(with({ on = false, initial = true })), false, "switched off")
    t.eq(LI().ShouldShow(with({ arrowShown = false, initial = true })), false,
        "a new player whose arrow is not shown yet (Flow: Reveal)")
end

tests["login intro: the status line says what there is to work with"] = function(t)
    if type(LI()) ~= "table" then return t.ok(false, "not loaded") end
    t.eq(LI().QuestWords(true, true), "Questie linked")
    t.eq(LI().QuestWords(false, true), "Questie starting up")
    t.eq(LI().QuestWords(false, false), "no quest database")
    t.eq(LI().Status({ spells = 12, linked = true, installed = true, steps = 5 }),
        "12 spells  ·  Questie linked  ·  5 steps planned")
    t.eq(LI().Status({ linked = false, installed = false, steps = 0 }), "no quest database", "no count not read, no 0 steps")
    t.eq(LI().Title({ title = "Z-Flow" }, "1.2.3"), "Z-Flow 1.2.3")
    t.eq(LI().Title({ title = "Z-Flow" }, nil), "Z-Flow")
end

tests["login intro: the long one spins, the short one does not"] = function(t)
    if type(LI()) ~= "table" then return t.ok(false, "not loaded") end
    t.eq({ LI().Times(false) }, { 3.2, 1.4, true })
    t.eq({ LI().Times(true) }, { 1.0, 0.6, false })
end

local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local api = LI().Declare(k, d)
    local seen = {}
    k:Boot()
    k.bus:on("test", LI().EVENT, function(v) seen[#seen + 1] = v end)
    if opts.off then k.settings:set(LI().SETTING, false) end
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    return c, k, api, seen, d
end

tests["login intro module: plays once at login with its words; a later loading screen does not"] = function(t)
    if type(LI()) ~= "table" then return t.ok(false, "not loaded") end
    local c, _, api, seen = boot()
    c.fire("PLAYER_ENTERING_WORLD", true, false)
    t.eq(#seen, 1, "at login")
    t.ok(type(seen[1]) == "table" and type(seen[1].title) == "string" and type(seen[1].status) == "string", "its words")
    t.eq(seen[1] and { seen[1].show, seen[1].tail, seen[1].spins }, { 3.2, 1.4, true })
    c.fire("PLAYER_ENTERING_WORLD", false, false)
    t.eq(#seen, 1, "not at a loading screen")
    c.fire("PLAYER_ENTERING_WORLD", false, true)
    t.eq(#seen, 2, "at a reload")
    t.eq(api.Shows(), 2)
end

tests["login intro module: off, nothing at login; the word plays it anyway and switches it"] = function(t)
    if type(LI()) ~= "table" then return t.ok(false, "not loaded") end
    local c, k, _, seen, d = boot({ off = true })
    c.fire("PLAYER_ENTERING_WORLD", true, false)
    t.eq(#seen, 0, "off")
    d.commands[LI().WORD]("")
    t.eq(#seen, 1, "the word plays it")
    d.commands[LI().WORD]("on")
    t.eq(k.settings:get(LI().SETTING), true)
    d.commands[LI().WORD]("short on")
    t.eq(k.settings:get(LI().SHORT), true)
    d.commands[LI().WORD]("")
    t.eq(seen[2] and seen[2].spins, false, "the short one")
end

return tests

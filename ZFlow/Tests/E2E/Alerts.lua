local _, ns = ...
-- N68 (research order 8, row 13), section 236 whole-add-on scenarios for
-- the alerts: through the real add-on, the login events, the setting and a
-- reload. The prompt used is the Attune one (an optional add-on loaded
-- after login brings a new Advisor prompt). Fake client, made-up data; not
-- tested in game.
local tests = {}

local MAP = 1429
local AT = "Attune"
local PROGRESS = {
    { id = 1, name = "Molten Core", percent = 100 },
    { id = 2, name = "Onyxia", percent = 40 },
}
local LINE = "Attunements under way: Onyxia 40%."

local function A() return ns.Alerts end

-- opts.attune: Attune is there at login. opts.account, opts.char: saved
-- tables (a reload). opts.on: alerts turned on after login. opts.kinds:
-- { kind = false }.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setClass("PALADIN"); c.setFaction("Alliance"); c.setLevel(60); c.setDead(false)
    c.setPosition(MAP, 0.5, 0.5)
    if opts.attune then c.setLoaded(AT, true); c.setAttuneProgress(PROGRESS) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    if opts.on then addon.settings:set(A().SETTING, true) end
    for kind, v in pairs(opts.kinds or {}) do addon.settings:set(A().KindKey(kind), v) end
    c.advance(A().SETTLE + 5, 20)
    c.setTarget({ exists = false }); c.setCombat(false)
    c.advance(1, 2)
    return c, addon
end

local function attuneLate(c)
    c.setAttuneProgress(PROGRESS); c.setLoaded(AT, true)
    c.fire("ADDON_LOADED", AT)
end

local function said(c, from, text)
    local want = ns.id.title .. ": " .. text
    local n = 0
    for i = from, #c.printed do
        if tostring(c.printed[i]) == want then n = n + 1 end
    end
    return n
end

tests["alerts 236: on, Attune loaded after login: the new prompt is said once in chat"] = function(t)
    if not A() then t.ok(false, "ns.Alerts"); return end
    local c = start({ on = true })
    local from = #c.printed + 1
    attuneLate(c)
    t.eq(said(c, from, LINE), 1)
end

tests["alerts 236: off by default: the same prompt says nothing in chat"] = function(t)
    if not A() then t.ok(false, "ns.Alerts"); return end
    local c = start()
    local from = #c.printed + 1
    attuneLate(c)
    t.eq(said(c, from, LINE), 0)
end

tests["alerts 236: on, the attunement kind off: nothing said"] = function(t)
    if not A() then t.ok(false, "ns.Alerts"); return end
    local c = start({ on = true, kinds = { attune = false } })
    local from = #c.printed + 1
    attuneLate(c)
    t.eq(said(c, from, LINE), 0)
end

tests["alerts 236: on, Attune there at login: the prompt at login is not said"] = function(t)
    if not A() then t.ok(false, "ns.Alerts"); return end
    local c = start({ on = true, attune = true })
    t.eq(said(c, 1, LINE), 0)
end

tests["alerts 236: reload: the setting is kept for the account; the next new prompt is said"] = function(t)
    if not A() then t.ok(false, "ns.Alerts"); return end
    local c = start({ on = true })
    local account, char = c.saved(ns.id.accountDB), c.saved(ns.id.charDB)
    local c2, addon2 = start({ account = account, char = char })
    t.eq(addon2.settings:get(A().SETTING), true, "still on after the reload")
    local from = #c2.printed + 1
    attuneLate(c2)
    t.eq(said(c2, from, LINE), 1)
end

return tests

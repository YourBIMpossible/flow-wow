-- Tests for ZFlow/UI/Lite.lua (G57 lite mode): the perf.lite row switches
-- the extra modules in Lite.OFF off before they are wired, so they never
-- listen, tick or draw; nothing else changes and no game setting is set.
local _, ns = ...

local L = ns.Lite

local function start(account)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, account or {})
    c.setSaved(ns.id.charDB, {})
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    k:Module({ name = "plateThreat", start = function() end })
    k:Module({ name = "needsPlate", needs = { "plateThreat" }, start = function() end })
    k:Module({ name = "core", start = function() end })
    local api = L.Start(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api
end

local function said(c, rest)
    local before = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = before + 1, #c.printed do out[#out + 1] = c.printed[i]:sub(#ns.id.title + 3) end
    return out
end

local tests = {}

tests["lite: the row is perf.lite, account, off by default, under settings.perf.lite"] = function(t)
    local k = start()
    local row = k.settings:row(L.SETTING)
    t.eq(L.SETTING, "perf.lite")
    t.ok(row ~= nil, "the row is declared")
    t.eq(row and row.scope, "account")
    t.eq(row and row.type, "bool")
    t.eq(row and row.default, false)
    t.eq(L.WORD, "lite")
end

tests["lite: off, every module starts"] = function(t)
    local k = start()
    t.eq(k:ModuleState("plateThreat"), "started")
    t.eq(k:ModuleState("needsPlate"), "started")
    t.eq(k:ModuleState("core"), "started")
end

tests["lite: on, the listed modules and what needs them stay off; the rest start"] = function(t)
    local k = start({ settings = { perf = { lite = true } } })
    local state, reason = k:ModuleState("plateThreat")
    t.eq(state, "off")
    t.eq(reason, L.REASON)
    t.eq(k:ModuleState("needsPlate"), "off")
    t.eq(k:ModuleState("core"), "started")
end

tests["lite: the list names only add-on modules; a name not declared is skipped"] = function(t)
    t.ok(#L.OFF > 0)
    local k = start({ settings = { perf = { lite = true } } })
    t.eq(k:ModuleState("plateCombo"), nil, "not declared here: nothing happens")
    t.eq(k:ModuleState("core"), "started")
end

tests["lite: Lite.Lines says on or off and what it turns off"] = function(t)
    local on = L.Lines(true, { "plateThreat" }, "/x")
    t.eq(on[1], "Lite mode is on: 1 extra feature is off (plateThreat).")
    t.eq(on[2], "Type /x lite off, then /reload, to turn them back on.")
    local off = L.Lines(false, {}, "/x")
    t.eq(off[1], "Lite mode is off: every feature runs.")
    t.eq(off[2], "Type /x lite on, then /reload, to turn off the extras when the game feels slow.")
end

tests["lite: the word sets the row and asks for a reload; it changes nothing else"] = function(t)
    local k, c = start()
    local out = said(c, "lite on")
    t.eq(k.settings:get(L.SETTING), true)
    t.eq(out[1], L.RELOAD)
    t.eq(k:ModuleState("plateThreat"), "started", "takes effect at the next load")
    out = said(c, "lite off")
    t.eq(k.settings:get(L.SETTING), false)
    out = said(c, "lite")
    t.eq(out[1], "Lite mode is off: every feature runs.")
end

return tests

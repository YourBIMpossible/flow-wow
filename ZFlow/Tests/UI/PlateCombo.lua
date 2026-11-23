-- Tests for ZFlow/UI/PlateCombo.lua (S8, lead section 178;
-- WoW/from-lazy/RESEARCH-S8.md): your combo points as a bar under your
-- target's nameplate, for a rogue or a druid in Cat Form with a live enemy
-- targeted. Look only. A count the game hides goes straight onto the bar
-- from the client (the display sink, option A); the module hears only
-- "hidden". A count not known is never drawn as 0. Over the fake client;
-- every name and number is made up. Not tested in game.
local _, ns = ...

local PC = ns.PlateCombo
local tests = {}

local LIVE = { exists = true, hostile = true, dead = false }

-- ---------------------------------------------------------------- pure

tests["plate combo: the names, words and numbers agreed"] = function(t)
    t.eq({ PC.NAME, PC.WORD, PC.OFF, PC.TICK, PC.MAX }, { "plateCombo", "combo", "plateCombo.off", 0.2, 5 })
    t.eq(PC.COLOR, { 1.00, 0.96, 0.41 })
    t.eq(PC.CAT, { "Cat Form" })
end

tests["plate combo uses: a rogue, or a druid in Cat Form"] = function(t)
    t.eq(PC.Uses("ROGUE", nil), true)
    t.eq(PC.Uses("DRUID", true), true)
    t.eq(PC.Uses("DRUID", false), false)
    t.eq(PC.Uses("DRUID", nil), false, "the form not known")
    t.eq(PC.Uses("WARRIOR", true), false)
    t.eq(PC.Uses(nil, true), false, "the class not known")
end

tests["plate combo wanted: on, a class that uses them, a live enemy targeted"] = function(t)
    t.eq(PC.Wanted(true, "ROGUE", nil, LIVE), true)
    t.eq(PC.Wanted(false, "ROGUE", nil, LIVE), false, "off")
    t.eq(PC.Wanted(true, "PRIEST", nil, LIVE), false)
    t.eq(PC.Wanted(true, "ROGUE", nil, { exists = false }), false, "no target")
    t.eq(PC.Wanted(true, "ROGUE", nil, nil), false, "the target not known")
    t.eq(PC.Wanted(true, "ROGUE", nil, { exists = true, hostile = false, dead = false }), false, "a friend")
    t.eq(PC.Wanted(true, "ROGUE", nil, { exists = true, dead = false }), false, "hostile not known")
    t.eq(PC.Wanted(true, "ROGUE", nil, { exists = true, hostile = true, dead = true }), false, "dead")
    t.eq(PC.Wanted(true, "ROGUE", nil, { exists = true, hostile = true }), true,
        "dead not known: as legacy Flow, not taken as dead")
end

tests["plate combo fill: the most clamped to 1..10, 5 when not known; an unknown count stays unknown"] = function(t)
    t.eq({ PC.Fill(3, 5) }, { 3, 5 })
    t.eq({ PC.Fill(0, 5) }, { 0, 5 }, "a 0 the game gave")
    t.eq({ PC.Fill(7, 5) }, { 5, 5 })
    t.eq({ PC.Fill(-1, 5) }, { 0, 5 })
    t.eq({ PC.Fill(2, nil) }, { 2, 5 })
    t.eq({ PC.Fill(2, "x") }, { 2, 5 })
    t.eq({ PC.Fill(2, 12) }, { 2, 10 })
    t.eq({ PC.Fill(2, 0) }, { 1, 1 })
    t.eq({ PC.Fill(nil, 5) }, { nil, 5 }, "not known: never 0")
    t.eq({ PC.Fill("3", 5) }, { nil, 5 })
end

tests["plate combo colour: the game's own, else the copy of it"] = function(t)
    t.eq({ PC.BarColor({ r = 0.9, g = 0.8, b = 0.1 }) }, { 0.9, 0.8, 0.1 })
    t.eq({ PC.BarColor(nil) }, { 1.00, 0.96, 0.41 })
    t.eq({ PC.BarColor({ r = 1, g = 1 }) }, { 1.00, 0.96, 0.41 })
end

-- ---------------------------------------------------------------- module

-- opts: class ("ROGUE"), target (LIVE), plate ("health"; false: none),
-- points (3; false: not known; "hidden": the game hides it), max (5).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setClass(opts.class or "ROGUE")
    c.setTarget(opts.target or LIVE)
    if opts.plate ~= false then c.setPlate("target", opts.plate or "health") end
    local points = opts.points
    if points == nil then points = 3 end
    if points == "hidden" then points = c.SECRET end
    if points ~= false then c.setCombo(points, opts.max or 5) end
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local api = PC.Declare(k, d)
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
    for i = before + 1, #c.printed do out[#out + 1] = c.printed[i] end
    return table.concat(out, "\n")
end

tests["plate combo module: started, its setting on by default"] = function(t)
    local k = start()
    t.eq((k:ModuleState(PC.NAME)), "started")
    t.eq(k.settings:get(PC.OFF), false)
    local row = ns.Settings.Model.Default():row(PC.OFF)
    t.ok(row ~= nil, "plateCombo.off is a row of the settings model")
    t.eq(row and { row.type, row.default }, { "bool", false })
    t.eq(k.settings:row(PC.OFF) and k.settings:row(PC.OFF).scope, "account")
end

tests["plate combo module: a rogue's points under the target's health bar"] = function(t)
    local k, c, api = start()
    local bar = c.comboBars[1]
    t.ok(bar ~= nil, "a bar")
    if not bar then return end
    t.eq({ bar.shown, bar.hung, bar.under, bar.max, bar.value }, { true, "target", "health", 5, 3 })
    t.eq(bar.rgb, PC.COLOR, "the copy of the game's colour when the game does not say")
    t.eq(#c.comboBars, 1, "one bar")
    t.eq(api.status().last, "shown")
    t.eq(k.problems:count(), 0)
end

tests["plate combo module: looked at every 0.2 seconds, and when your power changes"] = function(t)
    local _, c = start()
    local bar = c.comboBars[1]
    c.setCombo(4, 5)
    c.advance(0.1, 1)
    t.eq(bar.value, 3, "not yet")
    c.advance(0.1, 1)
    t.eq(bar.value, 4, "0.2 seconds on")
    c.setCombo(5, 5)
    c.fire("UNIT_POWER_UPDATE", "player")
    t.eq(bar.value, 5, "at once on your power")
    c.setCombo(1, 5)
    c.fire("UNIT_POWER_UPDATE", "target")
    t.eq(bar.value, 5, "another unit's power is not yours")
end

tests["plate combo module: a count not known is not drawn, never as 0"] = function(t)
    local k, c, api = start({ points = false })
    local bar = c.comboBars[1]
    t.ok(bar ~= nil, "the bar is made")
    if not bar then return end
    t.eq(bar.shown, false)
    t.eq(bar.value, nil, "no made-up 0")
    t.eq(api.status().last, "unknown")
    c.setCombo(2, 5)
    c.advance(0.2, 1)
    t.eq({ bar.shown, bar.value }, { true, 2 }, "shown once it is known")
    t.eq(k.problems:count(), 0)
end

tests["plate combo module: a count the game hides goes onto the bar from the client"] = function(t)
    local k, c, api = start({ points = "hidden" })
    local bar = c.comboBars[1]
    t.ok(bar ~= nil, "a bar")
    if not bar then return end
    t.eq(bar.shown, true)
    t.ok(rawequal(bar.value, c.SECRET), "the client set the hidden value on the bar")
    t.eq(bar.max, 5, "the sections from the plain most")
    t.eq(api.status().last, "hidden")
    t.eq(api.status().points, nil, "the module holds no count")
    c.advance(1, 5)
    t.ok(rawequal(bar.value, c.SECRET), "still the game's own value after the looks")
    t.eq(k.problems:count(), 0, "the module did nothing with the value (it would have raised)")
    t.ok(said(c, PC.WORD):find("last combo read: hidden by the game", 1, true) ~= nil)
end

tests["plate combo module: a druid only in Cat Form"] = function(t)
    local _, c = start({ class = "DRUID" })
    t.eq(#c.comboBars, 0, "no form known: no bar")
    c.setUnitBuffs("player", { { name = "Cat Form" } })
    c.fire("UPDATE_SHAPESHIFT_FORM")
    local bar = c.comboBars[1]
    t.ok(bar ~= nil and bar.shown and bar.value == 3, "in Cat Form")
    c.setUnitBuffs("player", { { name = "Bear Form" } })
    c.fire("UPDATE_SHAPESHIFT_FORM")
    t.eq(bar.shown, false, "out of Cat Form")
end

tests["plate combo module: a class without them gets no bar and no looks"] = function(t)
    local _, c, api = start({ class = "WARRIOR" })
    c.advance(1, 5)
    c.fire("UNIT_POWER_UPDATE", "player")
    t.eq(#c.comboBars, 0)
    t.eq(api.status().uses, false)
    t.eq(api.status().wanted, false)
end

tests["plate combo module: a friend, a dead one or no target puts it away and stops looking"] = function(t)
    local _, c = start()
    local bar = c.comboBars[1]
    c.setTarget({ exists = true, hostile = false, dead = false })
    c.fire("PLAYER_TARGET_CHANGED")
    t.eq(bar.shown, false)
    local reads = bar.reads
    c.advance(1, 5)
    t.eq(bar.reads, reads, "no looks while it is not wanted")
    c.setTarget(LIVE)
    c.fire("PLAYER_TARGET_CHANGED")
    t.eq(bar.shown, true, "an enemy again")
    c.setTarget({ exists = true, hostile = true, dead = true })
    c.fire("PLAYER_TARGET_CHANGED")
    t.eq(bar.shown, false, "dead")
    c.setTarget({ exists = false })
    c.fire("PLAYER_TARGET_CHANGED")
    t.eq(bar.shown, false, "no target")
end

tests["plate combo module: no plate for the target yet, shown when it comes into view"] = function(t)
    local _, c, api = start({ plate = false })
    local bar = c.comboBars[1]
    t.ok(bar ~= nil, "the bar is made")
    if not bar then return end
    t.eq(bar.shown, false)
    t.eq(api.status().under, nil)
    c.setPlate("target", "health")
    c.addPlate("nameplate4")
    t.eq({ bar.shown, bar.under }, { true, "health" }, "a plate came into view")
end

tests["plate combo module: under the power bar when the plate shows one"] = function(t)
    local _, c = start({ plate = "power" })
    t.eq(c.comboBars[1].under, "power")
end

tests["plate combo module: the game's colour, and the most it says"] = function(t)
    local _, c = start({ max = 12 })
    local bar = c.comboBars[1]
    t.eq(bar.max, 10, "at most 10 sections")
    c.setComboColor(0.9, 0.8, 0.1)
    c.setCombo(3, nil)
    c.advance(0.2, 1)
    t.eq(bar.rgb, { 0.9, 0.8, 0.1 })
    t.eq(bar.max, 5, "the most not known: 5")
end

tests["plate combo module: off puts the bar away"] = function(t)
    local k, c = start()
    local bar = c.comboBars[1]
    k.settings:set(PC.OFF, true)
    c.advance(0.2, 1)
    t.eq(bar.shown, false)
end

tests["plate combo module: the word says the state and the last read"] = function(t)
    local k, c = start()
    local text = said(c, PC.WORD)
    t.ok(text:find(ns.id.title .. ": combo points on the nameplate: on; your class uses them now: yes; wanted now: yes; shown: yes; hung under: health", 1, true) ~= nil, text)
    t.ok(text:find("last combo read: shown (3 of 5)", 1, true) ~= nil, text)
    text = said(c, PC.WORD .. " off")
    t.eq(k.settings:get(PC.OFF), true)
    t.eq(c.comboBars[1].shown, false)
    t.ok(text:find("combo points on the nameplate: off", 1, true) ~= nil, text)
    said(c, PC.WORD .. " on")
    t.eq(k.settings:get(PC.OFF), false)
    t.eq(c.comboBars[1].shown, true, "on again: shown at once")
    local _, c2 = start({ points = false })
    t.ok(said(c2, PC.WORD):find("last combo read: not known", 1, true) ~= nil)
    t.eq(k.problems:count(), 0)
end

tests["plate combo: look only - nothing casts, clicks, targets or writes a CVar"] = function(t)
    local _, c, api = start()
    local function clean(tbl, what)
        for name in pairs(tbl) do
            local n = tostring(name):lower()
            for _, bad in ipairs({ "cast", "click", "target", "press", "secure", "cvar" }) do
                t.ok(not n:find(bad, 1, true), what .. " has an acting name: " .. n)
            end
        end
    end
    clean(PC, "the module table")
    clean(api, "the api")
    t.eq(#c.secureButtons, 0, "no secure button made")
    t.eq(c.comboBars[1].hung, "target", "hung under your target's plate: read, never chosen")
end

return tests

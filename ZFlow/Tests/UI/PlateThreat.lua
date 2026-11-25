-- Tests for ZFlow/UI/PlateThreat.lua (S8, lead section 178;
-- WoW/from-lazy/RESEARCH-S8.md): your threat share on each enemy nameplate,
-- in a fight, in a group or with a pet out. Own share only: no party unit is
-- read. Look only. A share the game hides is written by the client (the
-- display sink, option A); the module hears only "hidden" and never holds
-- the value. Over the fake client; every name and number is made up. Not
-- tested in game.
local _, ns = ...

local PT = ns.PlateThreat
local tests = {}

-- ---------------------------------------------------------------- pure

tests["plate threat: the names, words and numbers agreed"] = function(t)
    t.eq({ PT.NAME, PT.WORD, PT.OFF, PT.ALWAYS, PT.ROLE, PT.TICK },
        { "plateThreat", "threat", "plateThreat.off", "plateThreat.always", "spec.role", 0.5 })
    t.eq({ PT.MID, PT.HIGH, PT.OVER }, { 50, 90, 100 })
    t.eq(PT.BEAR, { "Bear Form", "Dire Bear Form" })
    t.eq(PT.WORDS, { shown = "shown", hidden = "hidden by the game", unknown = "not known" })
end

tests["plate threat band: calm < 50 <= mid < 90 <= high < 100 <= over"] = function(t)
    t.eq(PT.Band(0), "calm")
    t.eq(PT.Band(49.9), "calm")
    t.eq(PT.Band(50), "mid")
    t.eq(PT.Band(89.9), "mid")
    t.eq(PT.Band(90), "high")
    t.eq(PT.Band(99.9), "high")
    t.eq(PT.Band(100), "over")
    t.eq(PT.Band(250), "over")
    t.eq(PT.Band(nil), nil)
    t.eq(PT.Band("85"), nil)
end

tests["plate threat state: each status, tanking and not"] = function(t)
    t.eq({ PT.State(3, true), PT.State(2, true), PT.State(1, true), PT.State(0, true) },
        { "safe", "losing", "pulling", "lost" })
    t.eq({ PT.State(3, false), PT.State(2, false), PT.State(1, false), PT.State(0, false) },
        { "danger", "danger", "pulling", "low" })
    t.eq(PT.State(nil, true), "hidden", "a status not known")
    t.eq(PT.State(nil, false), "hidden")
end

tests["plate threat look: tanking by state, else by the share's band; over flashes"] = function(t)
    t.eq({ PT.Look("losing", 85, true) }, { "losing", false }, "tanking: the state")
    t.eq({ PT.Look("safe", 130, true) }, { "safe", false })
    t.eq({ PT.Look("danger", 85, false) }, { "mid", false }, "not tanking: the band")
    t.eq({ PT.Look("low", 20, false) }, { "calm", false })
    t.eq({ PT.Look("danger", 95, false) }, { "high", false })
    t.eq({ PT.Look("danger", 120, false) }, { "over", true }, "over pulses")
    t.eq({ PT.Look("danger", nil, false) }, { "danger", false }, "a share not known: the state")
    t.eq({ PT.Look("hidden", nil, false) }, { "hidden", false })
    for key in pairs({ over = 1, high = 1, mid = 1, calm = 1, safe = 1, losing = 1, pulling = 1, lost = 1,
        danger = 1, low = 1, hidden = 1 }) do
        t.eq(#(PT.COLORS[key] or {}), 3, "a colour for " .. key)
    end
    t.eq(PT.COLORS.hidden, { 1, 1, 1 }, "hidden: white")
end

tests["plate threat text: a whole share, rounded; nothing when not known"] = function(t)
    t.eq(PT.Text(85), "85%")
    t.eq(PT.Text(85.4), "85%")
    t.eq(PT.Text(85.5), "86%")
    t.eq(PT.Text(0), "0%")
    t.eq(PT.Text(130.2), "130%")
    t.eq(PT.Text(nil), "")
    t.eq(PT.Text("85"), "")
end

tests["plate threat wanted: on, and in a group, with a pet, or always"] = function(t)
    t.eq(PT.Wanted(true, false, true, false), true, "a group")
    t.eq(PT.Wanted(true, false, false, true), true, "a pet")
    t.eq(PT.Wanted(true, true, false, false), true, "always")
    t.eq(PT.Wanted(true, false, false, false), false, "alone")
    t.eq(PT.Wanted(true, false, nil, nil), false, "not known is not in a group")
    t.eq(PT.Wanted(false, true, true, true), false, "off")
    t.eq(PT.Wanted(nil, true, true, true), false)
end

tests["plate threat tanking: the tank role or a bear; a role not known is not tank"] = function(t)
    t.eq(PT.Tanking("tank", nil), true)
    t.eq(PT.Tanking("dps", true), true, "a bear")
    t.eq(PT.Tanking("", true), true)
    t.eq(PT.Tanking("dps", false), false)
    t.eq(PT.Tanking("heal", nil), false)
    t.eq(PT.Tanking("", nil), false, "no role chosen")
    t.eq(PT.Tanking(nil, nil), false, "a role not known")
end

-- ---------------------------------------------------------------- module

-- opts.alone: not in a group (the read left not known).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    k:Setting({ key = PT.ROLE, scope = "char", type = "string", default = "", label = "Your role" })
    local api = PT.Declare(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    if not opts.alone then c.setGrouped(true) end
    return k, c, api
end

local function labelOf(c, unit)
    for i = #c.plateLabels, 1, -1 do
        if c.plateLabels[i].unit == unit then return c.plateLabels[i] end
    end
    return nil
end

local function enemy(c, unit, status, pct)
    c.setCanAttack(unit, true)
    c.setThreat(unit, status, pct)
    c.addPlate(unit)
end

local function said(c, rest)
    local before = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = before + 1, #c.printed do out[#out + 1] = c.printed[i] end
    return table.concat(out, "\n")
end

tests["plate threat module: started, with its two settings off by default"] = function(t)
    local k = start()
    t.eq((k:ModuleState(PT.NAME)), "started")
    t.eq(k.problems:count(), 0)
    t.eq({ k.settings:get(PT.OFF), k.settings:get(PT.ALWAYS) }, { false, false })
    local model = ns.Settings.Model.Default()
    for _, key in ipairs({ PT.OFF, PT.ALWAYS }) do
        local row = model:row(key)
        t.ok(row ~= nil, key .. " is a row of the settings model")
        t.eq(row and { row.type, row.default }, { "bool", false }, key)
        t.eq(k.settings:row(key) and k.settings:row(key).scope, "account", key .. " is an account setting")
    end
end

tests["plate threat module: out of a fight nothing is read or drawn"] = function(t)
    local k, c = start()
    enemy(c, "nameplate1", 3, 85)
    c.advance(2, 4)
    t.eq(#c.plateLabels, 0, "no label made out of a fight")
    t.eq(k.problems:count(), 0)
end

tests["plate threat module: in a fight, your share at the right of each enemy plate"] = function(t)
    local k, c, api = start()
    enemy(c, "nameplate1", 3, 85)
    c.setCombat(true)
    local l = labelOf(c, "nameplate1")
    t.ok(l ~= nil, "a label on the plate")
    if not l then return end
    t.eq({ l.shown, l.says }, { true, "85%" })
    t.eq(l.rgb, PT.COLORS.mid, "not tanking: coloured by the band")
    t.eq(api.status().last, "shown")
    enemy(c, "nameplate2", 1, 30)
    local second = labelOf(c, "nameplate2")
    t.ok(second ~= nil and second.shown and second.says == "30%", "a plate that comes in during the fight")
    t.eq(second and second.rgb, PT.COLORS.calm)
    t.eq(k.problems:count(), 0)
end

tests["plate threat module: looked at again every half second while the fight lasts"] = function(t)
    local _, c = start()
    enemy(c, "nameplate1", 3, 85)
    c.setCombat(true)
    local l = labelOf(c, "nameplate1")
    c.setThreat("nameplate1", 3, 95)
    c.advance(0.4, 1)
    t.eq(l.says, "85%", "not yet")
    c.advance(0.1, 1)
    t.eq(l.says, "95%", "half a second on")
    t.eq(l.rgb, PT.COLORS.high)
    c.setThreat("nameplate1", 3, 40)
    c.fire("UNIT_THREAT_LIST_UPDATE", "nameplate1")
    t.eq(l.says, "40%", "the game's threat event looks at once")
end

tests["plate threat module: the fight ends, every label hides and the looks stop"] = function(t)
    local _, c, api = start()
    enemy(c, "nameplate1", 3, 85)
    c.setCombat(true)
    local l = labelOf(c, "nameplate1")
    c.setCombat(false)
    t.eq(l.shown, false)
    t.eq(api.status().fighting, false)
    local reads = l.reads
    c.setThreat("nameplate1", 3, 99)
    c.advance(2, 4)
    c.fire("UNIT_THREAT_LIST_UPDATE", "nameplate1")
    t.eq(l.reads, reads, "nothing read out of the fight")
    t.eq(l.shown, false)
end

tests["plate threat module: a plate you cannot attack, or may not, gets nothing"] = function(t)
    local _, c = start()
    c.setThreat("nameplate1", 3, 85)
    c.setCanAttack("nameplate1", false)
    c.addPlate("nameplate1")
    c.setThreat("nameplate2", 3, 85)
    c.addPlate("nameplate2")
    c.setCombat(true)
    t.eq(#c.plateLabels, 0, "friendly, and not known: no label")
end

tests["plate threat module: alone with no pet nothing shows; a pet, a group or always does"] = function(t)
    local _, c = start({ alone = true })
    enemy(c, "nameplate1", 3, 85)
    c.setCombat(true)
    t.eq(#c.plateLabels, 0, "alone, everything is on you")
    c.setGuid("pet", "Pet-0-1")
    c.fire("UNIT_THREAT_LIST_UPDATE", "nameplate1")
    local l = labelOf(c, "nameplate1")
    t.ok(l ~= nil and l.shown, "a pet out")
    local k2, c2 = start({ alone = true })
    enemy(c2, "nameplate1", 3, 85)
    k2.settings:set(PT.ALWAYS, true)
    c2.setCombat(true)
    t.ok(labelOf(c2, "nameplate1") ~= nil and labelOf(c2, "nameplate1").shown, "always")
end

tests["plate threat module: a share the game hides is drawn by the client, never handled here"] = function(t)
    local k, c, api = start()
    enemy(c, "nameplate1", 3, c.SECRET)
    c.setCombat(true)
    local l = labelOf(c, "nameplate1")
    t.ok(l ~= nil, "a label")
    if not l then return end
    t.eq(l.shown, true)
    t.ok(rawequal(l.says, c.SECRET), "the client wrote the hidden value onto the label")
    t.eq(l.format, "%.0f%%")
    t.eq(l.rgb, PT.COLORS.danger, "coloured by the plain status")
    t.eq(api.status().last, "hidden")
    c.advance(1, 4)
    t.ok(rawequal(l.says, c.SECRET), "still the game's own value after the looks")
    t.eq(k.problems:count(), 0, "the module did nothing with the value (it would have raised)")
    c.setThreat("nameplate1", c.SECRET, c.SECRET)
    c.advance(0.5, 1)
    t.eq(l.rgb, PT.COLORS.hidden, "the status hidden too: white")
    t.eq(k.problems:count(), 0)
end

tests["plate threat module: not on its threat list, or not known: the label hides"] = function(t)
    local _, c, api = start()
    enemy(c, "nameplate1", 3, 85)
    c.setCombat(true)
    local l = labelOf(c, "nameplate1")
    c.setThreat("nameplate1")
    c.advance(0.5, 1)
    t.eq(l.shown, false)
    t.eq(api.status().last, "unknown")
    t.ok(l.says == "85%", "no 0 written in its place")
end

tests["plate threat module: a plate that goes takes its label with it"] = function(t)
    local _, c, api = start()
    enemy(c, "nameplate1", 3, 85)
    c.setCombat(true)
    local l = labelOf(c, "nameplate1")
    t.eq(api.status().inView, 1)
    c.removePlate("nameplate1")
    t.eq(l.shown, false)
    t.eq(api.status().inView, 0)
    local reads = l.reads
    c.advance(1, 2)
    t.eq(l.reads, reads, "not read after it went")
end

tests["plate threat module: off hides every label"] = function(t)
    local k, c = start()
    enemy(c, "nameplate1", 3, 85)
    c.setCombat(true)
    local l = labelOf(c, "nameplate1")
    k.settings:set(PT.OFF, true)
    c.advance(0.5, 1)
    t.eq(l.shown, false)
end

tests["plate threat module: tanking by role or as a bear, the tank colours"] = function(t)
    local k, c, api = start()
    k.settings:set(PT.ROLE, "tank")
    enemy(c, "nameplate1", 2, 98)
    c.setCombat(true)
    local l = labelOf(c, "nameplate1")
    t.eq(api.status().tanking, true)
    t.eq(l.rgb, PT.COLORS.losing, "on you, someone has more: you're losing it")
    k.settings:set(PT.ROLE, "dps")
    c.setUnitBuffs("player", { { name = "Dire Bear Form" } })
    c.setThreat("nameplate1", 3, 100)
    c.advance(0.5, 1)
    t.eq(api.status().tanking, true, "a bear")
    t.eq(l.rgb, PT.COLORS.safe)
    c.setUnitBuffs("player", nil)
    c.advance(0.5, 1)
    t.eq(api.status().tanking, false, "the form not known: not tanking")
    t.eq(l.rgb, PT.COLORS.over, "by the band again")
end

tests["plate threat module: over a hundred pulses; back under, it stands still"] = function(t)
    local _, c = start()
    enemy(c, "nameplate1", 3, 120)
    c.setCombat(true)
    local l = labelOf(c, "nameplate1")
    t.eq(l.rgb, PT.COLORS.over)
    t.ok(type(l.alphaNow) == "number", "the pulse sets how bright it is")
    c.setThreat("nameplate1", 3, 80)
    c.advance(0.5, 1)
    t.eq(l.alphaNow, 1, "steady again")
    t.eq(l.rgb, PT.COLORS.mid)
end

tests["plate threat module: the word says the state and the last read"] = function(t)
    local k, c = start()
    enemy(c, "nameplate1", 3, c.SECRET)
    c.setCombat(true)
    local text = said(c, PT.WORD)
    t.ok(text:find(ns.id.title .. ": threat on nameplates: on; wanted now: yes; you are not tanking; in a fight: yes", 1, true) ~= nil, text)
    t.ok(text:find("1 nameplate(s) in view, 1 with a number", 1, true) ~= nil, text)
    t.ok(text:find("last threat read: hidden by the game", 1, true) ~= nil, text)
    t.ok(text:find("in a group: yes", 1, true) ~= nil, text)
    text = said(c, PT.WORD .. " off")
    t.eq(k.settings:get(PT.OFF), true)
    t.ok(text:find("threat on nameplates: off", 1, true) ~= nil, text)
    t.eq(labelOf(c, "nameplate1").shown, false)
    said(c, PT.WORD .. " on")
    t.eq(k.settings:get(PT.OFF), false)
    t.eq(k.problems:count(), 0)
end

tests["plate threat module: the word before any read says none yet"] = function(t)
    local _, c = start()
    local text = said(c, PT.WORD)
    t.ok(text:find("last threat read: none yet", 1, true) ~= nil, text)
    t.ok(text:find("0 nameplate(s) in view", 1, true) ~= nil, text)
end

tests["plate threat: only you, your pet and enemy nameplates are asked about"] = function(t)
    local _, c = start()
    local seen = {}
    for _, name in ipairs({ "canAttack", "plateLabel", "unitBuff", "guid", "unitInfo" }) do
        local real = c[name]
        c[name] = function(unit, ...)
            seen[#seen + 1] = tostring(unit)
            return real(unit, ...)
        end
    end
    enemy(c, "nameplate1", 3, 85)
    c.setCombat(true)
    c.advance(1, 2)
    t.ok(#seen > 0, "something was asked")
    for _, unit in ipairs(seen) do
        t.ok(unit == "player" or unit == "pet" or unit:find("^nameplate%d+$") ~= nil, "asked about " .. unit)
    end
end

tests["plate threat: look only - nothing casts, clicks, targets or writes a CVar"] = function(t)
    local _, c, api = start()
    local function clean(tbl, what)
        for name in pairs(tbl) do
            local n = tostring(name):lower()
            for _, bad in ipairs({ "cast", "click", "target", "press", "secure", "cvar" }) do
                t.ok(not n:find(bad, 1, true), what .. " has an acting name: " .. n)
            end
        end
    end
    clean(PT, "the module table")
    clean(api, "the api")
    enemy(c, "nameplate1", 3, 85)
    c.setCombat(true)
    t.eq(#c.secureButtons, 0, "no secure button made")
end

-- D-32 (lead sections 720 and 727), as Flow's Modules/Pulse.lua (:34, one
-- driver for everything that pulses): where the kernel has the shared
-- pulse (Rotation/Pulse.lua), an over-a-hundred label pulses in that one
-- set, so one frame listener drives the rotation icon and the plates. The
-- look is unchanged. Fails before: the plates made a set of their own.
tests["plate threat module: the pulse is the shared one where the kernel has it"] = function(t)
    local c = ns.make.fakeClient()
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    c.setGrouped(true)
    c.advance(1, 2)
    local shared = addon.use(ns.Pulse.NAME)
    t.eq(type(shared and shared.count), "function", "the shared pulse is reachable")
    if not (shared and type(shared.count) == "function") then return end
    enemy(c, "nameplate1", 3, 120)
    c.setCombat(true)
    c.advance(0.5, 1)
    t.eq(shared.count(), 1, "the label pulses in the shared set")
    local l = labelOf(c, "nameplate1")
    t.ok(l and type(l.alphaNow) == "number", "it pulses")
    c.setThreat("nameplate1", 3, 80)
    c.advance(0.5, 1)
    t.eq(shared.count(), 0, "back under: out of the set")
    t.eq(l and l.alphaNow, 1, "steady again")
end

return tests

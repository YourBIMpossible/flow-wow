local _, ns = ...

-- Tests for ZFlow/Items/Repair.lua (L6-C, S6): the repair warning. Pure
-- parts over made-up readings and places; the module over the fake client.
--
-- Durability comes through client.durability(), a CLIENT NEED the lead adds
-- to Core/Client.lua and Core/ClientFake.lua. Until the fake has its setter
-- (setDurability), these tests put the read on the fake directly, in the
-- same shape. Nothing here repairs, buys or clicks anything.

local R = ns.Repair
local tests = {}

local function has(lines, text)
    for _, l in ipairs(lines or {}) do
        if l == text then return true end
    end
    return false
end

-- ---------------------------------------------------------------- Worst
-- Ported from Flow's Modules/Items/Repair.lua:13-37 (R.THRESHOLD, R.Worst, R.Low).

tests["repair: the default threshold is Flow's 20%"] = function(t)
    t.eq(R.THRESHOLD, 0.20)
end

tests["repair: nothing read, or nothing with durability, is no warning"] = function(t)
    t.eq(R.Worst(nil), nil, "not read: unknown, never 'fine' or 'low'")
    t.eq(R.Worst({}), nil, "nothing worn with durability")
    t.eq(R.Worst({ [1] = { cur = 0, max = 0 }, [5] = { cur = nil, max = nil } }), nil, "no maximum: skipped")
end

tests["repair: the most worn item, and how many are under the threshold"] = function(t)
    local w = R.Worst({ [1] = { cur = 30, max = 60 }, [5] = { cur = 10, max = 100 }, [7] = { cur = 15, max = 100 } })
    t.eq(w.slot, 5, "the most worn")
    t.eq(w.pct, 0.10, "its share")
    t.eq(w.low, 2, "two under 20%")
    t.eq(R.Worst({ [1] = { cur = 30, max = 60 } }, 0.6).low, 1, "a threshold given counts against it")
end

tests["repair: readings in the wrong shape are skipped, never guessed"] = function(t)
    local w = R.Worst({ [1] = "x", [2] = { cur = -1, max = 10 }, [3] = { cur = 5, max = 0 / 0 },
                        [4] = { cur = 20, max = 10 }, [5] = { cur = 9, max = 10 } })
    t.eq(w.slot, 5, "only the readable one")
    t.eq(w.pct, 0.9)
end

tests["repair: Low only on a known share under the threshold"] = function(t)
    t.eq(R.Low(nil, 0.2), false, "unknown is never a warning")
    t.eq(R.Low(0.19, 0.2), true)
    t.eq(R.Low(0.2, 0.2), false, "at the threshold: not under it")
    t.eq(R.Low(0.1, nil), true, "no threshold given: the default")
end

-- ---------------------------------------------------------------- Vendor

local NPCS = {
    ["Smith Far"] = { map = 1411, x = 0.9, y = 0.9, roles = { repair = true }, factions = { Horde = true }, seen = 100 },
    ["Smith Near"] = { map = 1411, x = 0.5, y = 0.5, roles = { repair = true }, factions = { Horde = true }, seen = 50 },
    ["Smith Other"] = { map = 1412, x = 0.5, y = 0.5, roles = { repair = true }, factions = { Horde = true }, seen = 300 },
    ["Trainer"] = { map = 1411, x = 0.45, y = 0.45, roles = { trainer = true }, factions = { Horde = true } },
    ["Smith Alliance"] = { map = 1411, x = 0.45, y = 0.45, roles = { repair = true }, factions = { Alliance = true } },
}
local function here(extra)
    local h = { position = { map = 1411, x = 0.48, y = 0.48 }, faction = "Horde",
                mapSize = function() return { w = 1000, h = 1000 } end }
    for k, v in pairs(extra or {}) do h[k] = v end
    return h
end

tests["repair: the nearest known repair vendor of your faction on your map"] = function(t)
    local v = R.Vendor(NPCS, here())
    t.eq(v.name, "Smith Near", "the nearest repairer; the trainer and the other faction's are not")
    t.eq(v.onMap, true)
end

tests["repair: off your map, the most recently seen repair vendor"] = function(t)
    local v = R.Vendor(NPCS, here({ position = { map = 9999, x = 0.1, y = 0.1 } }))
    t.eq(v.name, "Smith Other")
    t.eq(v.onMap, false)
end

tests["repair: no known repair vendor, or no faction known, is none"] = function(t)
    t.eq(R.Vendor(nil, here()), nil, "no places saved")
    t.eq(R.Vendor({ ["Trainer"] = NPCS["Trainer"] }, here()), nil, "no repairer known")
    t.eq(R.Vendor(NPCS, here({ faction = nil })), nil, "faction not known: no target")
end

tests["repair: the guide step goes to the vendor, labelled"] = function(t)
    local v = R.Vendor(NPCS, here({ zone = { cont = 1 } }))
    local step = R.Step(v, here({ zone = { cont = 1 } }))
    t.eq(step.label, "Repair at Smith Near")
    t.eq(step.place, { cont = 1, map = 1411, x = 0.5, y = 0.5 })
    t.eq(step.radius, R.NEAR)
    t.eq(R.Step(nil, here()), nil, "no vendor: no step, text only")
    local long = { name = string.rep("x", 60), map = 1, x = 0.1, y = 0.1, onMap = false }
    t.eq(R.Step(long, here()).label, nil, "a label over the waypoint limit is left out, never cut")
end

-- ---------------------------------------------------------------- words

tests["repair: the warning names the share and the vendor"] = function(t)
    local lines = R.Lines({ pct = 0.15, slot = 5, low = 1 }, 0.2, { name = "Smith Near" })
    t.ok(has(lines, "An item you wear is at 15% durability."), "the share")
    t.ok(has(lines, "Repair at Smith Near."), "where")
end

tests["repair: more than one low item is counted"] = function(t)
    local lines = R.Lines({ pct = 0.05, slot = 1, low = 3 }, 0.2, nil)
    t.ok(has(lines, "An item you wear is at 5% durability (3 items under 20%)."), "counted")
    t.ok(has(lines, R.NO_VENDOR), "no vendor known: text only")
end

tests["repair: nothing low gives no lines"] = function(t)
    t.eq(R.Lines({ pct = 0.5, slot = 1, low = 0 }, 0.2, nil), {}, "above the threshold")
    t.eq(R.Lines(nil, 0.2, nil), {}, "not known")
end

-- ---------------------------------------------------------------- module

local function setDurability(c, readings)
    if type(c.setDurability) == "function" then return c.setDurability(readings) end
    c.durability = function()
        if readings == nil then return nil end
        local out = {}
        for slot, r in pairs(readings) do out[slot] = { cur = r.cur, max = r.max } end
        return out
    end
end

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.saved or {})
    setDurability(c, opts.durability)
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    if opts.threshold ~= nil then
        k:Setting({ key = R.SETTING, scope = "account", type = "number", min = 0, max = 1, default = 0.20,
                    label = "Warn when gear durability is below" })
    end
    local api = R.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    if opts.threshold ~= nil then k.settings:set(R.SETTING, opts.threshold) end
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api
end

local function printedWith(c, part)
    local n = 0
    for _, p in ipairs(c.printed) do
        if p:find(part, 1, true) then n = n + 1 end
    end
    return n
end

tests["repair module: low gear warns once in chat, and the warning is kept"] = function(t)
    local k, c, api = start({ durability = { [5] = { cur = 10, max = 100 } } })
    t.eq((k:ModuleState(R.NAME)), "started")
    t.eq(printedWith(c, "10% durability"), 1, "one chat line at login")
    t.ok(has(api.current().lines, "An item you wear is at 10% durability."), "kept for the guide")
    c.fire(R.EVENT)
    t.eq(printedWith(c, "10% durability"), 1, "not said again while still low")
    t.eq(R.SETTING, "repair.warnBelow", "the settings row's name")
end

tests["repair module: repaired gear clears the warning, and a new drop warns again"] = function(t)
    local _, c, api = start({ durability = { [5] = { cur = 10, max = 100 } } })
    setDurability(c, { [5] = { cur = 100, max = 100 } })
    c.fire(R.EVENT)
    t.eq(api.current(), nil, "no warning")
    setDurability(c, { [5] = { cur = 5, max = 100 } })
    c.fire(R.EVENT)
    t.eq(printedWith(c, "5% durability"), 1, "warned again")
end

tests["repair module: durability not read says nothing"] = function(t)
    local _, c, api = start({ durability = nil })
    c.fire(R.EVENT)
    t.eq(#c.printed, 0, "no line")
    t.eq(api.current(), nil, "nothing kept")
end

tests["repair module: the threshold comes from the setting row when there is one"] = function(t)
    local _, c = start({ durability = { [5] = { cur = 30, max = 100 } }, threshold = 0.5 })
    t.eq(printedWith(c, "30% durability"), 1, "under 50%: warned")
    local _, c2 = start({ durability = { [5] = { cur = 30, max = 100 } } })
    t.eq(#c2.printed, 0, "no row: the default 20%, and 30% is fine")
end

tests["repair module: a known repair vendor gives a guide step"] = function(t)
    local saved = { learned = { places = { npcs = {
        ["Smith Near"] = { map = 1411, x = 0.5, y = 0.5, roles = { repair = true }, factions = { Horde = true } } } } } }
    local _, c, api = start({ durability = { [5] = { cur = 10, max = 100 } }, saved = saved })
    c.setZone(1, 1411)
    c.setPosition(1411, 0.4, 0.4)
    c.setFaction("Horde")
    c.fire(R.EVENT)
    local cur = api.current()
    t.ok(cur and cur.step and cur.step.label == "Repair at Smith Near", "the step")
    t.ok(has(cur.lines, "Repair at Smith Near."), "and the line")
end

tests["repair: look only - nothing repairs, buys or clicks"] = function(t)
    for name in pairs(R) do
        local n = tostring(name):lower()
        t.ok(not (n:find("^repair$") or n:find("buy") or n:find("click") or n:find("auto")), "no acting function: " .. n)
    end
end

return tests

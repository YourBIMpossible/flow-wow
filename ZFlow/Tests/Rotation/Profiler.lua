local _, ns = ...
-- Parity row D-29 (lead sections 720, 721 and 732; plan
-- reports/wow/zflow-d29-profiler-plan.md, Lazy's CHANGES in): the fight
-- profiler. From Rotation/Fights.lua's own records it finds the spells you
-- cast more in your best fights than your worst, and hands that as the
-- bias to ns.Choose's adaptive groups. As Flow's Modules/Fight/
-- Profiler.lua (Analyze, Relearn, Bias). Pure parts and a module case
-- over the fake client. Not tested in game. Fails before: no such file.
local tests = {}

local function PR() return ns.Profiler end

-- A closed fight record as Fights.lua keeps one. dealt: { [spell] = hits }.
local function fight(at, dur, total, hits, opts)
    opts = opts or {}
    local spells, n = {}, 0
    for name, h in pairs(hits or {}) do
        spells[name] = { total = h * 10, hits = h }
        n = n + h
    end
    return {
        open = false, started = at, ended = at + dur,
        dealt = { total = total, hits = n, unread = opts.unread or 0, over = 0, spells = spells },
        healed = { total = opts.healed or 0, hits = 0, unread = 0, over = opts.over or 0, spells = {} },
        taken = { total = 0, hits = 0, unread = 0, over = 0, spells = {} },
        received = { total = 0, hits = 0, unread = 0, over = 0, spells = {} },
        group = false, elite = false,
    }
end

tests["profiler: the names and numbers agreed"] = function(t)
    t.eq(type(PR()), "table", "loaded")
    if type(PR()) ~= "table" then return end
    t.eq({ PR().NAME, PR().SETTING, PR().PATH, PR().WORD }, { "profiler", "rotation.learn", "profiler.fights", "profiler" })
    t.eq({ PR().KEEP, PR().MIN_DURATION, PR().MIN_SAMPLES, PR().LEVEL_SPAN }, { 100, 6, 6, 3 })
    t.eq({ PR().MIN_BIAS, PR().MIN_RATE }, { 0.25, 0.5 })
end

tests["profiler row: a usable fight becomes a compact row; anything unread or short does not"] = function(t)
    if type(PR()) ~= "table" then return t.ok(false, "not loaded") end
    local row = PR().Row(fight(100, 20, 400, { Wrath = 4, Moonfire = 2 }), "dps", 12)
    t.eq(row, { kind = "solo", role = "dps", level = 12, dur = 20, v = 20, hits = { Wrath = 4, Moonfire = 2 } })
    local heal = PR().Row(fight(100, 10, 0, {}, { healed = 300, over = 100 }), "heal", 12)
    t.eq(heal and heal.v, 20, "healing done without overhealing, a second")
    t.eq(PR().Row(fight(100, 5, 400, {}), "dps", 12), nil, "under 6 seconds")
    t.eq(PR().Row(fight(100, 20, 400, {}, { unread = 1 }), "dps", 12), nil, "an amount not read")
    t.eq(PR().Row(fight(100, 20, 400, {}), "tank", 12), nil, "a tank: no measure (no threat read)")
    t.eq(PR().Row(fight(100, 20, 400, {}), nil, 12), nil, "no role chosen")
    local f = fight(100, 20, 400, {})
    f.group = nil
    t.eq(PR().Row(f, "dps", 12), nil, "a kind not known")
    f = fight(100, 20, 400, {})
    f.open = true
    t.eq(PR().Row(f, "dps", 12), nil, "still open")
end

-- Six fights: Wrath often in the three best, Moonfire often in the worst.
local function rows(n)
    local out = {}
    for i = 1, n do
        local good = i <= math.floor(n / 2)
        local hits = good and { Wrath = 6, Moonfire = 1 } or { Wrath = 1, Moonfire = 6 }
        out[#out + 1] = { kind = "solo", role = "dps", level = 12, dur = 60, v = good and (100 + i) or i, hits = hits }
    end
    return out
end

tests["profiler bias: leans to what the best fights cast; away from what the worst did"] = function(t)
    if type(PR()) ~= "table" then return t.ok(false, "not loaded") end
    local b = PR().Bias(rows(6), "solo", "dps", 12)
    t.ok(type(b) == "table", "learned")
    t.ok(b and b.Wrath and b.Wrath > 0.25, "Wrath leans in")
    t.ok(b and b.Moonfire and b.Moonfire < -0.25, "Moonfire leans away")
    t.ok(b and b.Wrath <= 1 and b.Moonfire >= -1, "kept within -1..1")
end

tests["profiler bias: fewer than six fights, another bucket, or far levels learn nothing"] = function(t)
    if type(PR()) ~= "table" then return t.ok(false, "not loaded") end
    t.eq(PR().Bias(rows(5), "solo", "dps", 12), nil, "five fights")
    t.eq(PR().Bias(rows(6), "elite", "dps", 12), nil, "another kind")
    t.eq(PR().Bias(rows(6), "solo", "heal", 12), nil, "another role")
    t.eq(PR().Bias(rows(6), "solo", "dps", 16), nil, "more than 3 levels away")
    t.ok(PR().Bias(rows(6), "solo", "dps", 15) ~= nil, "3 levels away still counts")
end

tests["profiler bias: weak leanings are left out (Flow's 0.25, and 0.5 a minute)"] = function(t)
    if type(PR()) ~= "table" then return t.ok(false, "not loaded") end
    local list = rows(6)
    for i, r in ipairs(list) do
        r.hits.Rare = (i <= 3) and 0.4 or 0.2          -- under 0.5 a minute both ways
        r.hits.Even = 5                                 -- the same in both
    end
    local b = PR().Bias(list, "solo", "dps", 12)
    t.eq(b and b.Rare, nil, "too rare to count")
    t.eq(b and b.Even, nil, "no difference")
end

tests["profiler bias: the third is at least two fights"] = function(t)
    if type(PR()) ~= "table" then return t.ok(false, "not loaded") end
    t.eq(PR().Third(6), 2)
    t.eq(PR().Third(9), 3)
    t.eq(PR().Third(7), 2)
end

tests["profiler keep: newest first, at most KEEP"] = function(t)
    if type(PR()) ~= "table" then return t.ok(false, "not loaded") end
    local list = {}
    for i = 1, PR().KEEP + 5 do list = PR().Keep(list, { v = i }) end
    t.eq(#list, PR().KEEP)
    t.eq(list[1].v, PR().KEEP + 5, "the newest first")
    t.eq(list[#list].v, 6, "the oldest dropped")
end

tests["profiler module: a fight that ends is kept, the bias is learned, and reset clears it"] = function(t)
    if type(PR()) ~= "table" then return t.ok(false, "not loaded") end
    local c = ns.make.fakeClient()
    c.setLevel(12)
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local list = {}
    local api = PR().Declare(k, d, function() return list end)
    k:Setting({ key = "spec.role", scope = "char", type = "string", default = "dps", label = "Your role" })
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    for i = 1, 6 do
        local good = i <= 3
        local hits = good and { Wrath = 6, Moonfire = 1 } or { Wrath = 1, Moonfire = 6 }
        table.insert(list, 1, fight(i * 100, 60, good and 6000 or 600, hits))
        c.fire("PLAYER_REGEN_ENABLED")
        c.advance(PR().WAIT + 0.1, 1)
    end
    t.eq(#(k.store:get("char", PR().PATH) or {}), 6, "six rows kept")
    local b = api.Bias("solo", "dps")
    t.ok(b and b.Wrath and b.Wrath > 0, "learned")
    c.fire("PLAYER_REGEN_ENABLED")
    c.advance(PR().WAIT + 0.1, 1)
    t.eq(#(k.store:get("char", PR().PATH) or {}), 6, "the same fight is not kept twice")
    k.settings:set(PR().SETTING, false)
    t.eq(api.Bias("solo", "dps"), nil, "off: no bias")
    k.settings:set(PR().SETTING, true)
    d.commands[PR().WORD]("reset")
    t.eq(#(k.store:get("char", PR().PATH) or {}), 0, "reset: no rows")
    t.eq(api.Bias("solo", "dps"), nil, "reset: no bias")
end

tests["profiler: the driver step passes the bias to the choice (Driver.lua work)"] = function(t)
    local D = ns.RotationDriver
    t.eq(type(D.BiasFor), "function")
    if type(D.BiasFor) ~= "function" then return end
    t.eq(D.BiasFor(nil, {}, "dps"), nil, "no profiler: none")
    local seen
    local prof = { Bias = function(kind, role) seen = { kind, role } return { Wrath = 0.5 } end }
    t.eq(D.BiasFor(prof, { grouped = function() return false end, targetRank = function() return "normal" end }, "dps"),
        { Wrath = 0.5 })
    t.eq(seen, { "solo", "dps" })
    D.BiasFor(prof, { grouped = function() return true end }, "dps")
    t.eq(seen, { "group", "dps" }, "in a group")
    D.BiasFor(prof, { grouped = function() return false end, targetRank = function() return "elite" end }, "dps")
    t.eq(seen, { "elite", "dps" }, "an elite targeted")
    seen = nil
    t.eq(D.BiasFor(prof, { grouped = function() return nil end }, "dps"), nil, "not known whether grouped: none")
    t.eq(seen, nil)
end

return tests

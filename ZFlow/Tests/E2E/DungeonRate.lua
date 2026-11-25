-- "About N times your questing XP per hour" (FLOW-PARITY B-54, lead section
-- 496 item 3), on the whole add-on loaded on a fake client. Both rates are
-- measured: the questing one from XP gained outside dungeons, the run's
-- from XP gained inside it over its timed length (B-56). When either is not
-- known nothing is said. Section 236: an XP read that raises inside a run;
-- a reload. A made-up Questie; no quest data of any add-on. Offline: the
-- reads are the fake client's, not the game's. Not tested in game.
local _, ns = ...
local tests = {}

local MAP, DM = 1436, 1581
local RATE_LINE = "  Your last run: about 2.0 times your questing XP per hour"

local function questie()
    local quests = {
        [101] = { Id = 101, name = "Red Silk", level = 18, requiredLevel = 14, zoneOrSort = DM,
            Starts = { NPC = { 501 } } },
    }
    local npcs = { [501] = { name = "Gryan", friendlyToFaction = "A", spawns = { [40] = { { 30, 40 } } } } }
    local db = { QuestPointers = { [101] = true } }
    function db.GetQuest(id) return quests[id] end
    function db.GetNPC(id) return npcs[id] end
    function db.QueryQuestSingle(id, field)
        local q = quests[id]
        if not q then return nil end
        if field == "questLevel" then return q.level end
        return q[field]
    end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [40] = MAP })[area] end
    function zones:GetDungeons()
        return { [DM] = { "The Deadmines", {}, nil, { { 40, 42.5, 71.8 } } } }
    end
    return db, zones
end

-- A player outside a dungeon at clock `clock`, who has been in a dungeon
-- before (so XP is measured from login). opts: char (saved ahead), fresh
-- (true: a character that never was in one and never asked).
local function boot(clock, opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    local char = opts.char
    if not char and not opts.fresh then char = { dungeon = { measure = true } } end
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, char or {})
    c.setClass("WARRIOR"); c.setRaceId(1); c.setFaction("Alliance"); c.setLevel(18)
    c.setQuestDone(101, false)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 0)
    c.setQuestLog({})
    c.setClock(clock)
    c.setXp({ cur = 1000, max = 100000, rested = 0 })
    c.setInstance({ inside = false, kind = "none" })
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(3, 30)
    return c, addon, addon.problems:count()
end

-- The XP bar moves by `xp` at clock `clock`.
local function gain(c, clock, xp)
    local now = c.xp()
    c.setClock(clock)
    c.setXp({ cur = now.cur + xp, max = now.max, rested = 0 })
    c.fire("PLAYER_XP_UPDATE", "player")
end

-- Twenty minutes of questing from clock `from`: 500 XP every 5 minutes,
-- which is 6000 XP per hour (the first reading only starts the clock).
local function quested(c, from)
    for i = 1, 4 do gain(c, from + i * 300, 500) end
    return from + 1200
end

local function walkIn(c, clock)
    c.setClock(clock)
    c.setInstance({ inside = true, kind = "party" })
    c.setInstanceName("The Deadmines")
    c.fire("PLAYER_ENTERING_WORLD")
    c.advance(3, 30)
end

-- Leaves at `clock`, and stays out long enough for the run to end.
local function walkOut(c, clock)
    c.setClock(clock)
    c.setInstance({ inside = false, kind = "none" })
    c.fire("PLAYER_ENTERING_WORLD")
    c.advance(1, 5)
    c.setClock(clock + ns.DungeonVisit.GRACE + 1)
    c.fire("ZONE_CHANGED_NEW_AREA")
    c.advance(1, 5)
    return clock + ns.DungeonVisit.GRACE + 1
end

local function typed(c, rest)
    local from = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = from + 1, #c.printed do out[#out + 1] = tostring(c.printed[i]) end
    return out
end

-- The word, asked until the quests are read (the first ask starts the read).
local function asked(c, rest)
    typed(c, rest)
    c.advance(3, 30)
    return typed(c, rest)
end

local function has(lines, text)
    for _, line in ipairs(lines) do
        if line == text then return true end
    end
    return false
end

local function anyRate(lines)
    for _, line in ipairs(lines) do
        if line:find("questing XP per hour", 1, true) then return true end
    end
    return false
end

-- A measured run: 30 minutes inside from `at`, 6000 XP: 12000 XP per hour.
local function ran(c, at)
    walkIn(c, at)
    gain(c, at + 900, 6000)
    return walkOut(c, at + 1800)
end

-- Red on a8fc438f: no rate is measured and neither word says the line.
tests["dungeon rate: both rates measured - the plan and the summary say about N times"] = function(t)
    local c, addon, base = boot(1000)
    local now = quested(c, 1000)
    now = ran(c, now)
    t.eq(addon.store:get("char", "dungeon.runXp"), { ["The Deadmines"] = 6000 }, "the run's XP is kept with its time")
    t.ok(has(asked(c, "dungeons the deadmines"), RATE_LINE), "after the planned stops")
    walkIn(c, now + 10)
    t.ok(has(typed(c, "dungeon"), RATE_LINE), "in the summary inside")
    t.eq(addon.problems:count(), base, "no new problem")
end

-- When either rate is not known, nothing is said.
tests["dungeon rate: no questing rate measured, or too little of it, says nothing"] = function(t)
    local c, addon = boot(1000)
    ran(c, 1000)
    t.eq(addon.store:get("char", "dungeon.runXp"), { ["The Deadmines"] = 6000 }, "the run is measured")
    t.eq(anyRate(asked(c, "dungeons the deadmines")), false, "no questing XP measured: nothing")
    local c2 = boot(1000)
    gain(c2, 1300, 500); gain(c2, 1600, 500)
    ran(c2, 1600)
    t.eq(anyRate(asked(c2, "dungeons the deadmines")), false, "five minutes of questing is not a rate: nothing")
end

-- Section 236: a read that raises, then recovers. Red on a8fc438f for its
-- last check (the next run's line is never said).
tests["dungeon rate: an XP read that raises inside a run leaves that run's XP not known"] = function(t)
    local c, addon = boot(1000)
    local now = quested(c, 1000)
    walkIn(c, now)
    local real = c.xp
    c.xp = function() error("no xp (test)") end
    c.fire("PLAYER_XP_UPDATE", "player")
    c.xp = real
    gain(c, now + 600, 6000)
    gain(c, now + 900, 100)
    now = walkOut(c, now + 1800)
    t.eq(addon.store:get("char", "dungeon.times"), { ["The Deadmines"] = 1800 }, "the run is still timed")
    t.eq(addon.store:get("char", "dungeon.runXp"), nil, "but its XP is not known")
    t.eq(anyRate(asked(c, "dungeons the deadmines")), false, "so nothing is said")
    ran(c, now + 10)
    t.ok(has(asked(c, "dungeons the deadmines"), RATE_LINE), "the next run, read all the way, is said")
end

-- Section 236: a reload. Red on a8fc438f: nothing is kept to say.
tests["dungeon rate: both rates are kept over a reload"] = function(t)
    local c = boot(1000)
    local now = ran(c, quested(c, 1000))
    local c2, addon2, base2 = boot(now + 20, { char = c.saved(ns.id.charDB) })
    t.ok(has(asked(c2, "dungeons the deadmines"), RATE_LINE), "said after the reload")
    t.eq(addon2.problems:count(), base2, "no new problem")
end

-- White's run (lead section 539): for a character that never was in a
-- dungeon and never asked, this module reads no XP and listens to no XP
-- event. Twin, lead section 550 (F1): the check is on this module's own
-- measuring. The whole client's listeners cannot be asked, because the
-- info bar, shown by default, listens to PLAYER_XP_UPDATE for its own row.
-- Red on 63f99da0: XP was measured from login for every character.
tests["dungeon rate: this module measures no XP until the character enters a dungeon or asks"] = function(t)
    local function measuring(addon)
        local visit = addon.use("dungeonVisit")
        return type(visit) == "table" and type(visit.Measuring) == "function" and visit.Measuring()
    end
    local c, addon = boot(1000, { fresh = true })
    c.advance(30, 60)
    gain(c, 1300, 500)
    t.eq(measuring(addon), false, "a fresh character: not measuring")
    t.eq(addon.store:get("char", "dungeon.xpSamples"), nil, "and nothing is sampled")
    t.eq(addon.store:get("char", "dungeon.measure"), nil, "nothing is kept")
    walkIn(c, 1400)
    t.eq(measuring(addon), true, "in a dungeon: measured from now on")
    t.eq(addon.store:get("char", "dungeon.measure"), true, "kept for the next login")
    walkOut(c, 1500)
    local at = 1500 + ns.DungeonVisit.GRACE + 1
    gain(c, at + 300, 500)
    gain(c, at + 600, 500)
    local samples = addon.store:get("char", "dungeon.xpSamples")
    t.eq(type(samples) == "table" and #samples, 2, "and XP gained outside is sampled now")
    local c2, addon2 = boot(2000, { fresh = true })
    typed(c2, "dungeon")
    t.eq(measuring(addon2), true, "asking the dungeon word starts it too")
    local c3, addon3 = boot(3000, { char = c.saved(ns.id.charDB) })
    t.eq(c3 ~= nil and measuring(addon3), true, "after a reload it is measured from login")
end

-- Red on a8fc438f: there is no V.Gain (the call raises).
tests["dungeon rate: the sums, pure"] = function(t)
    local V = ns.DungeonVisit
    t.eq(V.Gain({ cur = 100, max = 1000, level = 5 }, { cur = 350, level = 5 }), 250)
    t.eq(V.Gain({ cur = 900, max = 1000, level = 5 }, { cur = 50, level = 6 }), 150, "over a level")
    t.eq(V.Gain({ cur = 900, max = 1000, level = 5 }, { cur = 50, level = 7 }), nil, "two levels: not known")
    t.eq(V.Gain(nil, { cur = 50, level = 6 }), nil, "no earlier reading")
    t.eq(V.Gain({ cur = 900, level = 5 }, { cur = 50, level = 6 }), nil, "no size of the old level")
    local samples = { { t = 100, xp = 9 }, { t = 400, xp = 300 }, { t = 5000, xp = 600 } }
    t.eq(V.RateFrom(samples, 5000), 3600, "a long gap counts as ten minutes; the first reading starts the clock")
    t.eq(V.RateFrom({ samples[1], samples[2] }, 400), nil, "five minutes is not a rate")
    t.eq(V.RateFrom(samples, 5000 + V.RATE_SPAN + 1), nil, "older than two hours: not known")
    t.eq(V.RateFrom(samples, nil), nil)
    t.eq(V.Ratio(6000, 1800, 6000), 2)
    t.eq(V.Ratio(nil, 1800, 6000), nil, "the run's XP not known")
    t.eq(V.Ratio(6000, nil, 6000), nil, "the run's time not known")
    t.eq(V.Ratio(6000, 1800, nil), nil, "the questing rate not known")
    t.eq(V.Ratio(0, 1800, 6000), nil)
    t.eq(V.RunXp({ xp = 500 }), 500)
    t.eq(V.RunXp({ xp = 500, noXp = true }), nil, "a reading was missed")
    local ended = { V.Step({ name = "A", t = 100, left = 500, xp = 70 }, "B", 600) }
    t.eq(ended, { { name = "B", t = 600 }, true, "A", 400, 70 }, "a run that ends hands on its XP")
end

return tests

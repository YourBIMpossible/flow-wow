local _, ns = ...
-- FLOW-PARITY B-52, "Get ready on the way", end to end on the whole add-on
-- loaded on a fake client: Plan the run in the Dungeon Quests window puts
-- the get-ready steps before the run (training due, a bank the player has
-- seen), the arrow walks them first, and the player does each. The first
-- two tests are lane B's (route-b 464899f6, moved out at 5764176b), on this
-- file's own stand-in. Section 236: a bank seen after the first plan.
-- Made-up quests, people and places. Offline: the reads are the fake
-- client's, not the game's. Look only: nothing trains, repairs or banks.
local tests = {}

local MAP, DM = 1436, 1581
local NEW = { "Charge", "Rend", "Hamstring", "Thunder Clap" }

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

-- opts: char, account (saved ahead), train (true: class spells to learn),
-- durability (the gear's readings; nil: not read)
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {}); c.setSaved(ns.id.charDB, opts.char or {})
    c.setClass("WARRIOR"); c.setRaceId(1); c.setFaction("Alliance"); c.setLevel(18)
    c.setQuestDone(101, false)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 0)
    if opts.durability then c.setDurability(opts.durability) end
    if opts.train then
        for i, name in ipairs(NEW) do
            c.setSpellId(name, 100 + i)
            c.setSpell(100 + i, { known = false })
        end
    end
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog({})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    c.slashes[ns.id.slash]("dungeons")
    c.advance(2, 20)
    return c, addon, addon.problems:count()
end

local function first(c)
    local a = c.arrows[1]
    return a and a.lines and a.lines[1]
end

local function plan(c)
    local picked = c.kitSelect("dungeons", "dungeons", 1)
    local clicked = c.kitClick("dungeons", "planRun")
    c.advance(1, 5)
    return picked == true and clicked == true
end

local function bankOf()
    return { name = "Teller", map = MAP, x = 0.6, y = 0.5, kinds = { banker = true } }
end

-- Lane B's test. Red on b0c50277: the run starts at the giver, so the first
-- line is the Red Silk one, not "Get ready: Bank".
tests["dungeon ready: a seen bank is a get-ready step before the run"] = function(t)
    local c, addon, base = boot({ char = { learned = { places = { services = { b1 = bankOf() } } } } })
    t.ok(plan(c), "the button is there and live")
    t.eq(first(c), "Get ready: Bank", "the bank first")
    c.setPosition(MAP, 0.6, 0.5)
    c.advance(2, 20)
    local line = first(c)
    t.ok(line ~= nil and line:find("Red Silk", 1, true) ~= nil, "then the run: " .. tostring(line))
    t.eq(addon.problems:count(), base, "no new problem")
end

-- Lane B's test. Red on b0c50277: there is no R.Ready (the call raises).
tests["dungeon ready: get-ready steps, pure"] = function(t)
    local R = ns.DungeonRead
    t.eq(R.Ready(nil, nil, nil), {})
    local steps = R.Ready({ label = "Class trainer: Ander", place = { map = MAP, x = 0.1, y = 0.2 } },
        { label = "Repair: Smith", place = { map = MAP, x = 0.3, y = 0.4 } },
        { kind = "banker", name = "Teller", map = MAP, x = 0.6, y = 0.5 })
    t.eq(#steps, 3)
    t.eq(steps[1].label, "Get ready: Train"); t.eq(steps[1].detail, "Class trainer: Ander")
    t.eq(steps[2].label, "Get ready: Sell and repair")
    t.eq(steps[3].label, "Get ready: Bank"); t.eq(steps[3].detail, "Teller")
    t.eq(steps[3].place, { map = MAP, x = 0.6, y = 0.5 })
    t.eq(#R.Ready({ label = "No place" }, nil, nil), 0, "a step with no place is left out")
    t.eq(#R.Ready("no", 5, { name = "No map", x = 0.1, y = 0.2 }), 0, "what is not a step is left out")
end

-- Training due at a class trainer the player has opened comes before the
-- bank. Red on b0c50277: the first line is the Red Silk one.
tests["dungeon ready: training due comes first, then the bank, then the run"] = function(t)
    local trainer = { roles = { classTrainer = true }, classes = { WARRIOR = true }, map = MAP, x = 0.45, y = 0.5 }
    local c, addon, base = boot({ train = true,
        account = { learned = { places = { npcs = { Ander = trainer } } } },
        char = { learned = { places = { services = { b1 = bankOf() } } } } })
    t.ok(plan(c), "the button is there and live")
    t.eq(first(c), "Get ready: Train", "training first")
    c.setPosition(MAP, 0.45, 0.5)
    c.advance(2, 20)
    t.eq(first(c), "Get ready: Bank", "then the bank")
    c.setPosition(MAP, 0.6, 0.5)
    c.advance(2, 20)
    local line = first(c)
    t.ok(line ~= nil and line:find("Red Silk", 1, true) ~= nil, "then the run: " .. tostring(line))
    t.eq(addon.problems:count(), base, "no new problem")
end

-- Nothing to get ready for: the run is as it was.
tests["dungeon ready: with nothing seen the run starts at the giver"] = function(t)
    local c, addon, base = boot()
    t.ok(plan(c), "the button is there and live")
    local line = first(c)
    t.ok(line ~= nil and line:find("Red Silk", 1, true) ~= nil, tostring(line))
    t.eq(addon.problems:count(), base, "no new problem")
end

-- Section 236, data arriving late: a bank seen after the first plan is in
-- the next one. Red on b0c50277: the second plan starts at the giver too.
tests["dungeon ready: a bank seen after the first plan is in the next plan"] = function(t)
    local c, addon, base = boot()
    t.ok(plan(c), "planned once")
    local line = first(c)
    t.ok(line ~= nil and line:find("Red Silk", 1, true) ~= nil, "no bank seen yet: " .. tostring(line))
    t.eq(addon.store:set("char", "learned.places.services", { b1 = bankOf() }), true, "the bank is saved")
    t.ok(plan(c), "planned again")
    t.eq(first(c), "Get ready: Bank", "the bank first now")
    t.eq(addon.problems:count(), base, "no new problem")
end

-- Lead section 493: due, but no place known: a words-only row in the
-- route's left list, not nothing.
local function leftRow(addon, label)
    local trip = addon.use(ns.Nav.TripRoute.NAME)
    local view = type(trip) == "table" and type(trip.View) == "function" and trip.View() or {}
    for _, row in ipairs(type(view.left) == "table" and view.left or {}) do
        if row.label == label then return row end
    end
    return nil
end

-- Red on bc68d9fa: R.Ready gives no second answer (left is nil).
tests["dungeon ready: due with no place known gives words-only rows, pure"] = function(t)
    local R = ns.DungeonRead
    local steps, left = R.Ready({ label = "Class trainer", count = 2 }, nil, nil, true)
    t.eq(#steps, 0, "no place: no step for the arrow")
    t.eq(left, { { label = "Get ready: Train", why = R.READY_NO_TRAINER },
                 { label = "Get ready: Sell and repair", why = R.READY_NO_REPAIR } })
    local steps2, left2 = R.Ready({ label = "Class trainer: Ander", place = { map = MAP, x = 0.1, y = 0.2 } },
        { label = "Repair: Smith", place = { map = MAP, x = 0.3, y = 0.4 } }, nil, true)
    t.eq(#steps2, 2)
    t.eq(left2, {}, "a place known: a step, no words-only row")
    local _, left3 = R.Ready(nil, nil, nil, false)
    t.eq(left3, {}, "nothing due: nothing said")
end

-- Red on bc68d9fa: the left list has no such row (leftRow is nil).
tests["dungeon ready: training due with no trainer place is a words-only row in the left list"] = function(t)
    local c, addon, base = boot({ train = true })
    t.ok(plan(c), "the button is there and live")
    local row = leftRow(addon, "Get ready: Train")
    t.ok(row ~= nil, "the row is in the left list")
    t.eq(row and row.why, ns.DungeonRead.READY_NO_TRAINER)
    local line = first(c)
    t.ok(line ~= nil and line:find("Red Silk", 1, true) ~= nil, "the arrow starts at the run: " .. tostring(line))
    t.eq(leftRow(addon, "Get ready: Sell and repair"), nil, "the gear is fine: no repair row")
    t.eq(addon.problems:count(), base, "no new problem")
end

-- Red on bc68d9fa: the left list has no such row.
tests["dungeon ready: low gear with no repair place is a words-only row; a seen one is a step"] = function(t)
    local low = { [5] = { cur = 5, max = 100 } }
    local c, addon, base = boot({ durability = low })
    t.ok(plan(c), "the button is there and live")
    local row = leftRow(addon, "Get ready: Sell and repair")
    t.ok(row ~= nil, "the row is in the left list")
    t.eq(row and row.why, ns.DungeonRead.READY_NO_REPAIR)
    t.eq(addon.problems:count(), base, "no new problem")
    -- With a repairer seen (a reload later, say) it is a step, not a row.
    local smith = { name = "Smith", map = MAP, x = 0.55, y = 0.5, kinds = { repair = true }, seen = 10, n = 1 }
    local c2, addon2 = boot({ durability = low, char = { learned = { places = { services = { s1 = smith } } } } })
    t.ok(plan(c2), "planned with the repairer seen")
    t.eq(first(c2), "Get ready: Sell and repair", "a step the arrow walks")
    t.eq(leftRow(addon2, "Get ready: Sell and repair"), nil, "and no words-only row")
end

return tests

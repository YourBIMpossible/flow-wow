-- Import.FromFlow and Import.Merge over hand-built, invented Flow data.
-- No real saved data is read anywhere: every table below is made up.
local _, ns = ...

local Import = ns.Import
local copy = ns.make.deepCopy
local NAN = 0 / 0

local function emptyAccount(record)
    return {
        schema = 1, settings = {}, layout = {}, imports = { record },
        learned = { places = {}, flights = {}, prices = {}, facts = {}, fights = {} },
    }
end

local function emptyChar()
    return { schema = 1, settings = {}, layout = {}, learned = {}, state = {} }
end

-- A realistic account table as Flow leaves it with one character logged out.
local function fullDb()
    return {
        charSplit = 3,
        migrations = {},
        places = {
            ["Mara Stonehand"] = { map = 1412, x = 0.42, y = 0.61, kind = "vendor", roles = { repair = true }, seen = 1700000000, n = 4 },
            ["Old Tobb"] = { map = 1411, x = 0.5, y = 0.5, kind = "trainer" },
        },
        placesNot = { ["Old Tobb"] = { repair = true } },
        mailboxes = { { map = 1412, x = 0.4, y = 0.6 }, { map = 1411, x = 0.1, y = 0.2 } },
        learnedSpots = { [101] = { [1] = { { map = 1412, x = 0.3, y = 0.3, n = 2, at = 1700000100 } } } },
        flightTimes = { ["Stonegate>Rivermouth"] = 142.5 },
        flightRate = 31.5,
        prices = { [2589] = 13, [4306] = 150 },
        facts = { spells = { [116] = true }, lacks = { [118] = true }, first = { [116] = 4 } },
        deathReports = { { at = 1700000200, by = "Gravel Lurker", level = 12 } },
        deathNext = 2,
        hearth = { binds = { stonegate = "The Split Keg" }, off = false },
        sell = { enabled = true, junkAll = true, autoJunk = true, autoAll = false, autoRepair = true, repairWarn = 0.3 },
        nav = {
            enabled = true,
            arrowStyle = "modern",
            arrowModern = true,
            point = { "TOP", "TOP", 0, -120 },
            arrows = {
                mode = "separate",
                points = { quest = { "CENTER", "CENTER", -40, 12 }, professions = { "TOP", "TOP", 80, -90 } },
                hidden = { professions = true },
                text = { quest = false },
            },
            cardPoint = { "LEFT", "LEFT", 20, 0 },
            kinds = { quest = true, professions = false },
            waypoint = { map = 1412, x = 0.25, y = 0.75 },
            entrances = { { cont = 1, wx = -4012.5, wy = 220.25, map = 1412 } },
            gates = { { cont = 1, wx = -10.5, wy = 33, a = 1411, b = 1412 } },
            taxiTrip = { from = "Stonegate", at = 1700000300 },
        },
        ah = { prices = { ["Emberfall-Alliance"] = { [2589] = 40 } }, watch = { [4306] = { name = "Silk Cloth", max = 900 } }, lastScan = 1700000400 },
        rotation = { enabled = true, panicPct = 35, point = { "CENTER", "CENTER", 0, -200 }, debug = true },
        quests = { enabled = true, autoAccept = false, drops = { [101] = { [2589] = 3 } } },
        settings = { tipsBeside = true },
        colorblind = false,
        diag = { log = { "line one", "line two" } },
        chat = { nextId = 9 },
        setup = { done = true },
    }
end

-- The same character's parked values, as Flow writes them at logout.
local function fullCharDb()
    return {
        adopted = { ["nav.hidden"] = true },
        data = {
            ["nav.hidden"] = { ["q:101"] = true },
            ["nav.selectedKey"] = "q:101",
            ["sell.never"] = { [4306] = true },
            ["sell.mine"] = { [2589] = "keep" },
            flights = { Stonegate = { cont = 1, wx = -4000.5, wy = 210 }, Rivermouth = { cont = 1, wx = 150, wy = -3300.25 } },
            flightTalked = { Stonegate = true },
            trainer = { npc = "Old Tobb", services = { [116] = 100 }, seenAt = 1700000500 },
            spec = { role = "tank" },
            profiler = { fights = { { mob = "Gravel Lurker", secs = 14 } }, bias = { aoe = 0.2 }, report = { "derived" } },
            crafting = {
                Tailoring = { rank = 80, seenAt = 1700000600, recipes = { [2963] = true } },
                drops = { [2589] = { kills = 20, got = 31 } },
                active = "Tailoring",
            },
            ["quests.notOffered"] = { [205] = true },
            paladinSeal = "Righteousness",
        },
    }
end

local function droppedFor(result, key)
    for _, entry in ipairs(result.dropped) do
        if entry.key == key then return entry end
    end
    return nil
end

return {
    ["import: nil input gives empty data in the new shape and an import record"] = function(t)
        local result = Import.FromFlow(nil, nil)
        t.eq(result.ok, true)
        t.eq(result.dropped, {})
        t.eq(result.record.source, "Flow")
        t.eq(result.record.sourceVersion, 0)
        t.eq(result.record.importer, Import.flowImporterVersion)
        t.eq(result.account, emptyAccount(result.record))
        t.eq(result.char, emptyChar())
        t.eq(result.record.counts.places, 0)
        t.eq(result.record.vendorChoices, {})
    end,

    ["import: empty tables behave like nil"] = function(t)
        local result = Import.FromFlow({}, {})
        t.eq(result.ok, true)
        t.eq(result.account, emptyAccount(result.record))
        t.eq(result.char, emptyChar())
        t.eq(result.dropped, {})
    end,

    ["import: learned places, flights, prices, facts and fights survive"] = function(t)
        local result = Import.FromFlow(fullDb(), fullCharDb())
        t.eq(result.ok, true)
        local learned = result.account.learned
        t.eq(learned.places.npcs["Mara Stonehand"],
            { map = 1412, x = 0.42, y = 0.61, kind = "vendor", roles = { repair = true }, seen = 1700000000, n = 4 })
        t.eq(learned.places.npcs["Old Tobb"].kind, "trainer")
        t.eq(learned.places.notRoles, { ["Old Tobb"] = { repair = true } })
        t.eq(learned.places.mailboxes, { { map = 1412, x = 0.4, y = 0.6 }, { map = 1411, x = 0.1, y = 0.2 } })
        t.eq(learned.places.questSpots[101][1][1], { map = 1412, x = 0.3, y = 0.3, n = 2, at = 1700000100 })
        t.eq(learned.places.innBinds, { stonegate = "The Split Keg" })
        t.eq(learned.places.entrances, { { cont = 1, wx = -4012.5, wy = 220.25, map = 1412 } })
        t.eq(learned.places.gates[1].b, 1412)
        t.eq(learned.flights.times, { ["Stonegate>Rivermouth"] = 142.5 })
        t.eq(learned.flights.rate, 31.5)
        t.eq(learned.prices.vendor, { [2589] = 13, [4306] = 150 })
        t.eq(learned.prices.auction, { ["Emberfall-Alliance"] = { [2589] = 40 } })
        t.eq(learned.facts.spells, { [116] = true })
        t.eq(learned.facts.lacks, { [118] = true })
        t.eq(learned.facts.questDrops, { [101] = { [2589] = 3 } })
        t.eq(learned.fights.deaths, { { at = 1700000200, by = "Gravel Lurker", level = 12 } })
    end,

    ["import: the character's parked values land in the character data"] = function(t)
        local result = Import.FromFlow(fullDb(), fullCharDb())
        local char = result.char
        t.eq(char.learned.flights.nodes.Rivermouth, { cont = 1, wx = 150, wy = -3300.25 }, "world coordinates may be negative")
        t.eq(char.learned.flights.talked, { Stonegate = true })
        t.eq(char.learned.facts.trainer, { npc = "Old Tobb", services = { [116] = 100 }, seenAt = 1700000500 })
        t.eq(char.learned.facts.recipes, { Tailoring = { rank = 80, seenAt = 1700000600, recipes = { [2963] = true } } })
        t.eq(char.learned.facts.craftDrops, { [2589] = { kills = 20, got = 31 } })
        t.eq(char.learned.facts.notOffered, { [205] = true })
        t.eq(char.learned.fights.records, { { mob = "Gravel Lurker", secs = 14 } })
        t.eq(char.learned.fights.bias, { aoe = 0.2 })
        t.eq(char.settings.nav.hidden, { ["q:101"] = true })
        t.eq(char.settings.sell.never, { [4306] = true })
        t.eq(char.settings.sell.mine, { [2589] = "keep" })
        t.eq(char.settings.spec.role, "tank")
        t.eq(char.settings.paladin.seal, "Righteousness")
        t.eq(char.state.nav.selectedKey, "q:101")
        t.eq(char.state.crafting.active, "Tailoring")
        t.eq(result.account.learned.flights.nodes, nil, "flight points are the character's")
    end,

    ["import: settings and arrow positions land per account"] = function(t)
        local result = Import.FromFlow(fullDb(), fullCharDb())
        local account = result.account
        t.eq(account.layout.arrows, {
            point = { "TOP", "TOP", 0, -120 },
            mode = "separate",
            points = { quest = { "CENTER", "CENTER", -40, 12 }, professions = { "TOP", "TOP", 80, -90 } },
            hidden = { professions = true },
            text = { quest = false },
        })
        t.eq(result.char.layout, {}, "no arrow position is per character")
        t.eq(account.layout.nav.card, { "LEFT", "LEFT", 20, 0 })
        t.eq(account.layout.rotation.frame, { "CENTER", "CENTER", 0, -200 })
        t.eq(account.settings.nav.enabled, true)
        t.eq(account.settings.nav.arrowStyle, "modern")
        t.eq(account.settings.nav.kinds, { quest = true, professions = false })
        t.eq(account.settings.nav.waypoint, { map = 1412, x = 0.25, y = 0.75 })
        t.eq(account.settings.rotation.panicPct, 35)
        t.eq(account.settings.quests.autoAccept, false)
        t.eq(account.settings.general.tipsBeside, true)
        t.eq(account.settings.general.colorblind, false)
        t.eq(account.settings.hearth.off, false)
        t.eq(account.settings.auction.watch, { [4306] = { name = "Silk Cloth", max = 900 } })
    end,

    ["import: caches, bookkeeping and diagnostics are listed as dropped with a reason"] = function(t)
        local result = Import.FromFlow(fullDb(), fullCharDb())
        for _, key in ipairs({ "charSplit", "migrations", "deathNext", "diag", "chat", "setup", "nav.arrowModern",
            "nav.taxiTrip", "ah.lastScan", "rotation.debug", "FlowCharDB.adopted", "FlowCharDB.data.profiler.report" }) do
            local entry = droppedFor(result, key)
            t.ok(entry and entry.why == "dropped", key .. " is listed as dropped")
            t.ok(entry and type(entry.reason) == "string" and entry.reason ~= "", key .. " has a reason")
        end
        t.eq(result.account.settings.rotation.debug, nil)
        t.eq(result.account.settings.nav.taxiTrip, nil)
        t.eq(result.record.counts.unknown, 0, "the full fixture has no unknown key")
        t.eq(result.record.counts.malformed, 0, "the full fixture has no malformed value")
    end,

    ["import: the record counts each category"] = function(t)
        local result = Import.FromFlow(fullDb(), fullCharDb())
        local counts = result.record.counts
        t.eq(counts.prices, 3, "two vendor prices and one realm of auction prices")
        t.eq(counts.dropped, 12)
        t.ok(counts.places > 0 and counts.flights > 0 and counts.facts > 0 and counts.fights > 0, "every learned category counted")
        t.ok(counts.settings > 0 and counts.layout > 0 and counts.state > 0, "settings, layout and state counted")
        t.eq(result.account.imports, { result.record }, "the record is ready for the imports list")
        t.eq(#result.dropped, counts.dropped + counts.unknown + counts.malformed + counts.superseded)
    end,

    ["import: unknown keys are listed, never imported and never fatal"] = function(t)
        local db = fullDb()
        db.futureThing = { a = 1 }
        db.sell.futureKnob = 7
        db[42] = "numbered"
        db["sell.autoJunk"] = true
        local charDb = fullCharDb()
        charDb.extra = true
        charDb.data["nav.futureField"] = 1
        charDb.data.futureSection = {}
        local result = Import.FromFlow(db, charDb)
        t.eq(result.ok, true)
        for _, key in ipairs({ "futureThing", "sell.futureKnob", "42", "sell.autoJunk", "FlowCharDB.extra",
            "FlowCharDB.data.nav.futureField", "FlowCharDB.data.futureSection" }) do
            local found = false
            for _, entry in ipairs(result.dropped) do
                if entry.key == key and entry.why == "unknown" then found = true end
            end
            t.ok(found, key .. " is listed as unknown")
        end
        t.eq(result.record.counts.unknown, 7)
        t.eq(result.account.settings.sell.futureKnob, nil)
        t.eq(result.account.futureThing, nil)
    end,

    ["import: malformed values are dropped with a reason and nothing crashes"] = function(t)
        local loop = {}
        loop.self = loop
        local db = {
            places = {
                Good = { map = 1, x = 0.5, y = 0.5 },
                Negative = { map = 1, x = -0.2, y = 0.5 },
                TooFar = { map = 1, x = 0.5, y = 1.5 },
                NotANumber = { map = 1, x = NAN, y = 0.5 },
                NoMap = { x = 0.5, y = 0.5 },
                Wrong = "a string",
                [7] = { map = 1, x = 0.5, y = 0.5 },
            },
            mailboxes = { { map = 1, x = 0.1, y = 0.1 }, { map = 1, x = -1, y = 0.1 }, { map = 1, x = 0.3, y = 0.3 } },
            prices = { [10] = 5, [11] = -4, [12] = NAN, [13] = "ten", name = 3, [-2] = 1 },
            flightTimes = { ["A>B"] = 60, ["B>C"] = 0, ["C>D"] = math.huge, [5] = 10 },
            flightRate = -3,
            learnedSpots = "nonsense",
            facts = { spells = { [1] = true, [2] = function() end }, lacks = 12, first = loop },
            sell = { autoJunk = "yes", autoRepair = 1, enabled = "on" },
            nav = {
                point = { "TOP", "TOP", NAN, 5 },
                cardPoint = "TOP",
                arrows = { mode = "sideways", points = { quest = { "TOP" }, professions = { "TOP", "TOP", 1, 2 } }, hidden = 5, extra = 1 },
                waypoint = { map = 1, x = 2, y = 0.5 },
                pathAlpha = NAN,
            },
            rotation = "broken",
            hearth = 5,
        }
        local charDb = {
            data = {
                flights = { Good = { cont = 1, wx = -5, wy = 5 }, Bad = { cont = 1, wx = "west", wy = 5 }, Inf = { wx = math.huge, wy = 1 } },
                trainer = 99,
            },
        }
        local before, beforeChar = copy(db), copy(charDb)
        local result = Import.FromFlow(db, charDb)
        t.eq(result.ok, true)
        t.eq(result.account.learned.places.npcs, { Good = { map = 1, x = 0.5, y = 0.5 } })
        t.eq(result.account.learned.places.mailboxes, { { map = 1, x = 0.1, y = 0.1 }, { map = 1, x = 0.3, y = 0.3 } })
        t.eq(result.account.learned.prices.vendor, { [10] = 5 })
        t.eq(result.account.learned.flights.times, { ["A>B"] = 60 })
        t.eq(result.account.learned.flights.rate, nil)
        t.eq(result.account.learned.places.questSpots, nil)
        t.eq(result.account.learned.facts, { spells = { [1] = true } }, "a table left empty by the checks is not written")
        t.eq(result.account.settings.sell, nil, "a vendor choice that is not true or false is not a choice")
        t.eq(result.account.layout.arrows, { points = { professions = { "TOP", "TOP", 1, 2 } } })
        t.eq(result.account.layout.nav, nil)
        t.eq(result.account.settings.nav, nil)
        t.eq(result.account.settings.rotation, nil)
        t.eq(result.char.learned.flights.nodes, { Good = { cont = 1, wx = -5, wy = 5 } })
        t.eq(result.char.learned.facts, nil)
        for _, key in ipairs({ "places.Negative", "places.TooFar", "places.NotANumber", "places.NoMap", "places.Wrong",
            "places.7", "mailboxes.2", "prices.11", "prices.12", "prices.13", "prices.name", "prices.-2",
            "flightTimes.B>C", "flightTimes.C>D", "flightTimes.5", "flightRate", "learnedSpots", "facts.spells.2",
            "facts.lacks", "facts.first.self", "sell.autoJunk", "sell.autoRepair", "sell.enabled", "nav.point",
            "nav.cardPoint", "nav.arrows.mode", "nav.arrows.points.quest", "nav.arrows.hidden", "nav.arrows.extra",
            "nav.waypoint", "nav.pathAlpha", "rotation", "hearth", "FlowCharDB.data.flights.Bad",
            "FlowCharDB.data.flights.Inf", "FlowCharDB.data.trainer" }) do
            local entry = droppedFor(result, key)
            t.ok(entry and entry.why == "malformed" and entry.reason ~= "", key .. " is listed as malformed with a reason")
        end
        t.eq(droppedFor(result, "places.Negative").reason, "a coordinate outside the map (0 to 1)")
        t.eq(result.record.counts.malformed, 36)
        -- NaN is never equal to itself, so compare the inputs with NaN taken out.
        db.places.NotANumber.x, before.places.NotANumber.x = nil, nil
        db.prices[12], before.prices[12] = nil, nil
        db.nav.point[3], before.nav.point[3] = nil, nil
        db.nav.pathAlpha, before.nav.pathAlpha = nil, nil
        db.facts.first, before.facts.first = nil, nil
        t.eq(db, before, "the malformed account input is unchanged")
        t.eq(charDb, beforeChar, "the malformed character input is unchanged")
    end,

    ["import: a character table that is not a table is reported, the account still imports"] = function(t)
        local result = Import.FromFlow({ prices = { [10] = 5 } }, "garbage")
        t.eq(result.ok, true)
        t.eq(result.account.learned.prices.vendor, { [10] = 5 })
        t.eq(droppedFor(result, "FlowCharDB").why, "malformed")
    end,

    ["import: an account table that is not a table is refused"] = function(t)
        local result = Import.FromFlow("garbage", nil)
        t.eq(result.ok, false)
        t.ok(type(result.reason) == "string" and result.reason ~= "", "says why")
        t.eq(result.account, nil)
        t.eq(result.char, nil)
    end,

    ["vendor: explicit choices on are preserved"] = function(t)
        local result = Import.FromFlow({ sell = { autoJunk = true, autoAll = true, autoRepair = true, autoCleanup = true, vendorUnpriced = true } }, nil)
        t.eq(result.account.settings.sell,
            { autoJunk = true, autoAll = true, autoRepair = true, autoCleanup = true, vendorUnpriced = true })
        t.eq(result.record.vendorChoices, {
            ["sell.autoJunk"] = true, ["sell.autoAll"] = true, ["sell.autoRepair"] = true,
            ["sell.autoCleanup"] = true, ["sell.vendorUnpriced"] = true,
        })
        t.eq(result.record.vendorSameAsFlowDefault, { ["sell.autoJunk"] = true, ["sell.autoRepair"] = true },
            "a stored true that Flow itself writes at load is flagged, not hidden")
    end,

    ["vendor: explicit choices off are preserved"] = function(t)
        local result = Import.FromFlow({ sell = { autoJunk = false, autoAll = false, autoRepair = false } }, nil)
        t.eq(result.account.settings.sell, { autoJunk = false, autoAll = false, autoRepair = false })
        t.eq(result.record.vendorChoices,
            { ["sell.autoJunk"] = false, ["sell.autoAll"] = false, ["sell.autoRepair"] = false })
        t.eq(result.record.vendorSameAsFlowDefault, { ["sell.autoAll"] = true })
    end,

    ["vendor: an absent choice stays absent, so the automation stays off"] = function(t)
        local result = Import.FromFlow({ sell = { repairWarn = 0.25 }, nav = { enabled = true } }, nil)
        t.eq(result.account.settings.sell, { repairWarn = 0.25 })
        t.eq(result.record.vendorChoices, {})
        local bare = Import.FromFlow({ nav = { enabled = true } }, nil)
        t.eq(bare.account.settings.sell, nil)
        t.eq(bare.record.vendorChoices, {})
    end,

    ["import: twice from the same input gives the same output"] = function(t)
        local db, charDb = fullDb(), fullCharDb()
        db.futureThing = 1
        db.places.Bad = { map = 1, x = -1, y = 0 }
        local first = Import.FromFlow(db, charDb)
        local second = Import.FromFlow(db, charDb)
        t.eq(first, second)
        t.ok(first.account ~= second.account and first.char ~= second.char, "each call returns new tables")
        t.eq(Import.FromFlow(fullDb(), fullCharDb()), Import.FromFlow(fullDb(), fullCharDb()), "equal inputs, equal outputs")
    end,

    ["import: the input tables are not changed and not shared with the output"] = function(t)
        local db, charDb = fullDb(), fullCharDb()
        db.futureThing = { deep = { 1, 2, 3 } }
        local before, beforeChar = copy(db), copy(charDb)
        local result = Import.FromFlow(db, charDb)
        t.eq(db, before)
        t.eq(charDb, beforeChar)
        result.account.learned.places.npcs["Mara Stonehand"].x = 0.99
        result.account.layout.arrows.point[3] = 500
        result.char.learned.flights.nodes.Stonegate.wx = 1
        result.char.settings.sell.never[4306] = nil
        t.eq(db, before, "writing to the result does not reach the account input")
        t.eq(charDb, beforeChar, "writing to the result does not reach the character input")
    end,

    ["import: a live per-character value wins over the parked copy"] = function(t)
        local db = { flights = { Live = { cont = 1, wx = 1, wy = 2 } }, nav = { hidden = { live = true } } }
        local charDb = { data = { flights = { Parked = { cont = 1, wx = 3, wy = 4 } }, ["nav.hidden"] = { parked = true } } }
        local result = Import.FromFlow(db, charDb)
        t.eq(result.char.learned.flights.nodes, { Live = { cont = 1, wx = 1, wy = 2 } })
        t.eq(result.char.settings.nav.hidden, { live = true })
        t.eq(droppedFor(result, "FlowCharDB.data.flights").why, "superseded")
        t.eq(droppedFor(result, "FlowCharDB.data.nav.hidden").why, "superseded")
        t.eq(result.record.counts.superseded, 2)
    end,

    ["import: a newer Flow data version is refused cleanly, with the reason"] = function(t)
        local db = fullDb()
        db.version = Import.flowKnownVersion + 1
        local before = copy(db)
        local result = Import.FromFlow(db, fullCharDb())
        t.eq(result.ok, false)
        t.eq(result.account, nil)
        t.eq(result.char, nil)
        t.eq(result.dropped, {})
        t.ok(result.reason:find("version " .. db.version, 1, true), "the reason names the version found")
        t.ok(result.reason:find("nothing was imported", 1, true), "the reason says nothing was imported")
        t.eq(result.record.sourceVersion, db.version)
        t.eq(result.record.refused, result.reason)
        t.eq(db, before)
    end,

    ["import: a version that is not a version number is refused"] = function(t)
        for _, version in ipairs({ "two", -1, 0.5, true }) do
            local result = Import.FromFlow({ version = version, prices = { [10] = 5 } }, nil)
            t.eq(result.ok, false, tostring(version) .. " is refused")
            t.eq(result.account, nil)
        end
        local known = Import.FromFlow({ version = 0, prices = { [10] = 5 } }, nil)
        t.eq(known.ok, true)
        t.eq(known.record.sourceVersion, 0)
        t.eq(droppedFor(known, "version"), nil, "the version is read, not dropped")
    end,

    ["mapping: every row maps to a named path or is dropped with a reason"] = function(t)
        local roots = {
            account = { settings = true, layout = true, learned = true },
            char = { settings = true, layout = true, learned = true, state = true },
        }
        local categories = { places = true, flights = true, prices = true, facts = true, fights = true }
        local seen, mapped, left = {}, 0, 0
        for _, row in ipairs(Import.flowMap) do
            local key = row[1]
            t.ok(type(key) == "string" and not seen[key], tostring(key) .. " has one row")
            seen[key] = true
            local ways = (row.to and 1 or 0) + (row.drop and 1 or 0) + (row.meta and 1 or 0)
            t.eq(ways, 1, key .. " is mapped, dropped or read as the version: exactly one")
            if row.to then
                mapped = mapped + 1
                local first, second = row.to:match("^([^.]+)%.([^.]+)")
                t.ok(roots[row.char and "char" or "account"][first], key .. " lands in a table of its scope")
                t.ok(first ~= "learned" or categories[second], key .. " lands in a fixed learned category")
            elseif row.drop then
                left = left + 1
                t.ok(type(row.drop) == "string" and row.drop ~= "", key .. " says why it is dropped")
            end
            if row.vendor then t.eq(row.as, "bool", key .. " is a yes-or-no choice") end
        end
        t.ok(mapped > 0 and left > 0, "the mapping has both kinds of row")
    end,

    ["merge: empty existing data takes the whole import"] = function(t)
        local imported = Import.FromFlow(fullDb(), fullCharDb())
        local snapshot = copy(imported)
        for _, existing in ipairs({ false, true }) do
            local account, char, report
            if existing then
                account, char, report = Import.Merge(emptyAccount(), emptyChar(), imported)
            else
                account, char, report = Import.Merge(nil, nil, imported)
            end
            t.eq(report.ok, true)
            t.eq(account.settings, imported.account.settings)
            t.eq(account.layout, imported.account.layout)
            t.eq(account.learned, imported.account.learned)
            t.eq(char.settings, imported.char.settings)
            t.eq(char.learned, imported.char.learned)
            t.eq(char.state, imported.char.state)
            t.eq(account.schema, 1)
            t.eq(char.schema, 1)
            t.eq(report.kept, {})
            t.eq(report.skipped, {})
            t.ok(#report.added > 0, "everything was added")
            t.eq(#account.imports, 1)
            t.eq(account.imports[1].source, "Flow")
            t.eq(account.imports[1].merge, { added = #report.added, kept = 0, skipped = 0 })
            t.ok(account.learned ~= imported.account.learned, "the merged data shares no table with the import")
        end
        t.eq(imported, snapshot, "the import result is unchanged")
    end,

    ["merge: a value the player already has is never overwritten"] = function(t)
        local imported = Import.FromFlow(fullDb(), fullCharDb())
        local account = emptyAccount()
        account.imports = {}
        account.settings.sell = { autoJunk = false, repairWarn = 0.3 }
        account.settings.nav = { arrowStyle = "flat" }
        account.layout.arrows = { point = { "BOTTOM", "BOTTOM", 0, 90 } }
        account.learned.places.npcs = { ["Mara Stonehand"] = { map = 1412, x = 0.1, y = 0.1, n = 9 }, ["Wren Dell"] = { map = 3, x = 0.2, y = 0.2 } }
        account.learned.prices.vendor = { [2589] = 99 }
        account.learned.places.mailboxes = { { map = 9, x = 0.9, y = 0.9 } }
        local char = emptyChar()
        char.settings.spec = { role = "healer" }
        char.learned.flights = { nodes = { Stonegate = { cont = 1, wx = 7, wy = 7 } } }
        local beforeAccount, beforeChar, beforeImport = copy(account), copy(char), copy(imported)

        local newAccount, newChar, report = Import.Merge(account, char, imported)
        t.eq(report.ok, true)
        t.eq(newAccount.settings.sell.autoJunk, false, "the player's off stays off")
        t.eq(newAccount.settings.sell.autoRepair, true, "an absent choice is filled in")
        t.eq(newAccount.settings.nav.arrowStyle, "flat")
        t.eq(newAccount.settings.nav.enabled, true)
        t.eq(newAccount.layout.arrows.point, { "BOTTOM", "BOTTOM", 0, 90 }, "a position is kept whole, never mixed")
        t.eq(newAccount.layout.arrows.mode, "separate")
        t.eq(newAccount.learned.places.npcs["Mara Stonehand"], { map = 1412, x = 0.1, y = 0.1, n = 9, kind = "vendor", roles = { repair = true }, seen = 1700000000 })
        t.eq(newAccount.learned.places.npcs["Wren Dell"], { map = 3, x = 0.2, y = 0.2 })
        t.eq(newAccount.learned.places.npcs["Old Tobb"].kind, "trainer")
        t.eq(newAccount.learned.prices.vendor, { [2589] = 99, [4306] = 150 })
        t.eq(newAccount.learned.places.mailboxes, { { map = 9, x = 0.9, y = 0.9 } }, "a list is kept whole")
        t.eq(newChar.settings.spec.role, "healer")
        t.eq(newChar.learned.flights.nodes.Stonegate, { cont = 1, wx = 7, wy = 7 })
        t.eq(newChar.learned.flights.nodes.Rivermouth, { cont = 1, wx = 150, wy = -3300.25 })

        local kept, skipped, added = {}, {}, {}
        for _, path in ipairs(report.kept) do kept[path] = true end
        for _, entry in ipairs(report.skipped) do skipped[entry.path] = entry.reason end
        for _, path in ipairs(report.added) do added[path] = true end
        t.ok(kept["account.settings.sell.autoJunk"], "kept: the vendor choice")
        t.ok(kept["account.layout.arrows.point"], "kept: the arrow position")
        t.ok(kept["account.learned.prices.vendor.2589"], "kept: the price")
        t.ok(kept["account.learned.places.mailboxes"], "kept: the mailbox list")
        t.ok(kept["char.settings.spec.role"], "kept: the role")
        t.ok(kept["char.learned.flights.nodes.Stonegate.wx"], "kept: the flight point")
        t.ok(added["account.settings.sell.autoRepair"], "added: the absent vendor choice")
        t.ok(added["account.learned.prices.vendor.4306"], "added: the new price")
        t.ok(added["account.learned.places.npcs.Old Tobb"], "added: the new place")
        t.eq(skipped["account.settings.sell.repairWarn"], "the same value is already there")
        t.ok(skipped["account.settings.sell.autoJunk"], "skipped lists every imported value that was not written")
        t.ok(not kept["account.settings.sell.repairWarn"], "an equal value is not a conflict")
        t.eq(report.counts, { added = #report.added, kept = #report.kept, skipped = #report.skipped })
        t.eq(#newAccount.imports, 1)

        t.eq(account, beforeAccount, "the existing account data is unchanged")
        t.eq(char, beforeChar, "the existing character data is unchanged")
        t.eq(imported, beforeImport, "the import result is unchanged")
    end,

    ["merge: a value still at its default gives way to the import"] = function(t)
        local imported = Import.FromFlow({ sell = { autoRepair = true, autoJunk = true }, nav = { arrowStyle = "modern" } }, { data = { spec = { role = "tank" } } })
        local account = emptyAccount()
        account.settings.sell = { autoRepair = false, autoJunk = false }
        account.settings.nav = { arrowStyle = "flat" }
        local char = emptyChar()
        char.settings.spec = { role = "damage" }
        local defaults = {
            account = { settings = { sell = { autoRepair = false }, nav = { arrowStyle = "3d" } } },
            char = { settings = { spec = { role = "damage" } } },
        }
        local newAccount, newChar, report = Import.Merge(account, char, imported, defaults)
        t.eq(newAccount.settings.sell.autoRepair, true, "still the default: the import is used")
        t.eq(newAccount.settings.sell.autoJunk, false, "no default given: the existing value is kept")
        t.eq(newAccount.settings.nav.arrowStyle, "flat", "not the default: the player changed it, so it is kept")
        t.eq(newChar.settings.spec.role, "tank")
        t.eq(report.counts.kept, 2)
        local without = Import.Merge(account, char, imported)
        t.eq(without.settings.sell.autoRepair, false, "without defaults nothing existing is replaced")
    end,

    ["merge: merging the same import twice adds nothing the second time"] = function(t)
        local imported = Import.FromFlow(fullDb(), fullCharDb())
        local account, char = Import.Merge(nil, nil, imported)
        local again, againChar, report = Import.Merge(account, char, imported)
        t.eq(report.added, {})
        t.eq(report.kept, {})
        t.eq(again.settings, account.settings)
        t.eq(again.learned, account.learned)
        t.eq(againChar, char)
        t.eq(#again.imports, 2, "each merge is recorded")
    end,

    ["merge: a refused or missing import merges nothing"] = function(t)
        local account = emptyAccount()
        account.imports = {}
        account.settings.sell = { autoJunk = false }
        local refused = Import.FromFlow({ version = 99, sell = { autoJunk = true } }, nil)
        for _, imported in ipairs({ refused, false }) do
            local newAccount, newChar, report = Import.Merge(account, emptyChar(), imported or nil)
            t.eq(report.ok, false)
            t.ok(report.reason:find("nothing was merged", 1, true), "says nothing was merged")
            t.eq(newAccount, account)
            t.ok(newAccount ~= account, "still a new table")
            t.eq(newChar, emptyChar())
            t.eq(report.added, {})
        end
    end,

    ["merge: existing data in a newer schema is left alone"] = function(t)
        local imported = Import.FromFlow(fullDb(), fullCharDb())
        local account = emptyAccount()
        account.schema = 2
        local newAccount, _, report = Import.Merge(account, emptyChar(), imported)
        t.eq(report.ok, false)
        t.ok(report.reason:find("schema 2", 1, true), "the reason names the schema found")
        t.eq(newAccount, account)
        local broken = emptyAccount()
        broken.learned = "gone"
        local _, _, second = Import.Merge(broken, emptyChar(), imported)
        t.eq(second.ok, false)
    end,
}

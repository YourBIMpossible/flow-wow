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
        legacyShared = { trainer = { npc = "Old Tobb" }, ["nav.hidden"] = { ["q:7"] = true } },
        buffButton = {
            enabled = true, key = "F", key2 = "SHIFT-F", dock = true, dockScale = 0.8,
            point = { "CENTER", "BOTTOMLEFT", 640, 220 }, scale = 1.1, always = true, care = false, keepOnMain = true,
        },
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
            -- Flow keeps the quest arrow's place here, and only the other
            -- arrows' places under arrows.points (Modules/Nav/Arrows.lua:387-391).
            point = { "TOP", "TOP", 0, -120 },
            arrows = {
                mode = "separate",
                points = { professions = { "TOP", "TOP", 80, -90 } },
                hidden = { professions = true },
                text = { quest = false },
            },
            profArrowText = false,
            mode = "optimal",
            professions = false,
            cardPoint = { "LEFT", "LEFT", 20, 0 },
            kinds = { quest = true, professions = false },
            waypoint = { map = 1412, x = 0.25, y = 0.75 },
            entrances = { { cont = 1, wx = -4012.5, wy = 220.25, map = 1412 } },
            gates = { { cont = 1, wx = -10.5, wy = 33, a = 1411, b = 1412 } },
            taxiTrip = { from = "Stonegate", at = 1700000300 },
            wayTips = 2,
        },
        ah = {
            prices = { ["Emberfall-Alliance"] = { [2589] = 40 } }, watch = { [4306] = { name = "Silk Cloth", max = 900 } },
            lastScan = 1700000400, chartPoint = { "CENTER", "BOTTOMLEFT", 300, 500 }, chartClick = false,
        },
        rotation = {
            enabled = true, panicPct = 35, point = { "CENTER", "CENTER", 0, -200 }, scale = 1.2, debug = true,
            recoverBandage = false, recoverFood = true, recoverBuffFood = false, recoverHeal = true, bandageRank = "low",
        },
        bonus = { enabled = true, spoken = false },
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
            prof = {
                chosen = { "Tailoring", "Enchanting" },
                point = { "CENTER", "BOTTOMLEFT", 400, 300 },
                suggestKey = "Tailoring+Enchanting",
            },
            ["autopush.seen"] = { [1] = true },
            ["autopush.bars"] = { bear = 2 },
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
        local arrows = {
            mode = "separate",
            points = { quest = { "TOP", "TOP", 0, -120 }, prof = { "TOP", "TOP", 80, -90 } },
            hidden = { prof = true },
            text = { quest = false, prof = false },
        }
        t.eq(account.layout.arrows, arrows)
        -- The reader itself (Nav/ArrowLayout.lua) finds every part of it.
        t.eq(ns.Nav.ArrowSaved(account.layout), arrows, "Z-Flow reads back what was imported")
        t.eq(account.settings.nav.profArrowText, nil, "the profession arrow's text choice is layout, not a setting")
        t.eq(result.char.layout.arrows, nil, "no arrow position is per character")
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
        -- Each key with the words its true reason must carry: a reason that
        -- belongs to another kind of key fails here.
        local expected = {
            ["charSplit"] = "bookkeeping",
            ["migrations"] = "bookkeeping",
            ["deathNext"] = "bookkeeping",
            ["nav.arrowModern"] = "bookkeeping",
            ["FlowCharDB.adopted"] = "bookkeeping",
            ["FlowCharDB.data.prof.suggestKey"] = "bookkeeping",
            ["diag"] = "diagnostic",
            ["rotation.debug"] = "diagnostic",
            ["ah.lastScan"] = "a cache",
            ["nav.taxiTrip"] = "one play session",
            ["nav.wayTips"] = "one-time notice",
            ["chat"] = "chat bridge",
            ["setup"] = "first-run progress",
            ["FlowCharDB.data.profiler.report"] = "built from the fight records",
            ["FlowCharDB.data.autopush.seen"] = "action bar moves",
            ["FlowCharDB.data.autopush.bars"] = "action bar moves",
            ["legacyShared.nav.hidden"] = "already took its share",
            ["legacyShared.trainer"] = "nothing was imported from here",
        }
        local checked = 0
        for key, words in pairs(expected) do
            local entry = droppedFor(result, key)
            t.ok(entry and entry.why == "dropped", key .. " is listed as dropped")
            t.ok(entry and entry.reason:find(words, 1, true), key .. ": the reason says " .. words)
            checked = checked + 1
        end
        -- Every dropped entry of the fixture is in the list above or in the
        -- nav.mode and nav.professions check below: none passes unread.
        t.eq(checked + 2, result.record.counts.dropped, "every dropped key of the fixture has its reason checked")
        t.eq(result.account.settings.rotation.debug, nil)
        t.eq(result.account.settings.nav.taxiTrip, nil)
        for _, key in ipairs({ "nav.mode", "nav.professions" }) do
            local entry = droppedFor(result, key)
            t.ok(entry and entry.why == "dropped", key .. " is listed as dropped")
            local reason = entry and entry.reason or ""
            t.ok(reason:find("nav.kinds", 1, true), key .. ": the reason names the key that carries the choice")
            t.ok(not reason:find("no longer reads", 1, true), key .. ": Flow still reads it; the reason does not say otherwise")
        end
        t.eq(result.record.counts.unknown, 0, "the full fixture has no unknown key")
        t.eq(result.record.counts.malformed, 0, "the full fixture has no malformed value")
    end,

    ["import: the record counts each category"] = function(t)
        local result = Import.FromFlow(fullDb(), fullCharDb())
        local counts = result.record.counts
        t.eq(counts.prices, 3, "two vendor prices and one realm of auction prices")
        t.eq(counts.dropped, 20)
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
        t.eq(result.account.layout.arrows, { points = { prof = { "TOP", "TOP", 1, 2 } } })
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

    ["vendor: a stored on is listed for the player to confirm, and is not switched on"] = function(t)
        local result = Import.FromFlow({ sell = { autoJunk = true, autoAll = true, autoRepair = true, autoCleanup = true, vendorUnpriced = true } }, nil)
        t.eq(result.account.settings.sell, nil, "no automation is on in the imported settings")
        t.eq(result.vendorToConfirm, {
            { key = "sell.autoAll", to = "settings.sell.autoAll", sameAsFlowDefault = false },
            { key = "sell.autoCleanup", to = "settings.sell.autoCleanup", sameAsFlowDefault = false },
            { key = "sell.autoJunk", to = "settings.sell.autoJunk", sameAsFlowDefault = true },
            { key = "sell.autoRepair", to = "settings.sell.autoRepair", sameAsFlowDefault = true },
            { key = "sell.vendorUnpriced", to = "settings.sell.vendorUnpriced", sameAsFlowDefault = false },
        }, "every automation it would switch on, in a fixed order")
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
        t.eq(result.vendorToConfirm, {}, "an off needs no confirmation")
    end,

    ["vendor: merge switches an automation on only when the player confirmed that one"] = function(t)
        local imported = Import.FromFlow({ sell = { autoJunk = true, autoRepair = true, autoAll = true, repairWarn = 0.25 } }, nil)
        local snapshot = copy(imported)

        local account, _, report = Import.Merge(nil, nil, imported)
        t.eq(account.settings.sell, { repairWarn = 0.25 }, "no confirmation: every automation stays off")
        t.eq(report.vendorLeftOff, { "sell.autoAll", "sell.autoJunk", "sell.autoRepair" })
        t.eq(report.vendorConfirmed, {})
        local skipped = {}
        for _, entry in ipairs(report.skipped) do skipped[entry.path] = entry.reason end
        for _, name in ipairs({ "autoAll", "autoJunk", "autoRepair" }) do
            local reason = skipped["account.settings.sell." .. name]
            t.ok(type(reason) == "string" and reason:find("confirm", 1, true), name .. " is listed as skipped: not confirmed")
        end
        t.eq(account.imports[1].vendorConfirmed, {}, "the record says none was confirmed")

        local one, _, oneReport = Import.Merge(nil, nil, imported, nil, { ["sell.autoRepair"] = true })
        t.eq(one.settings.sell, { autoRepair = true, repairWarn = 0.25 }, "only the confirmed one is on")
        t.eq(oneReport.vendorConfirmed, { "sell.autoRepair" })
        t.eq(oneReport.vendorLeftOff, { "sell.autoAll", "sell.autoJunk" })
        t.eq(one.imports[1].vendorConfirmed, { ["sell.autoRepair"] = true })

        local loose = Import.Merge(nil, nil, imported, nil, { ["sell.autoRepair"] = "yes", ["sell.autoJunk"] = 1, ["sell.autoCleanup"] = true })
        t.eq(loose.settings.sell, { repairWarn = 0.25 },
            "only true confirms, and confirming one the import did not find on switches nothing on")

        local own = emptyAccount()
        own.imports = {}
        own.settings.sell = { autoRepair = false }
        local kept = Import.Merge(own, nil, imported, nil, { ["sell.autoRepair"] = true })
        t.eq(kept.settings.sell.autoRepair, false, "confirmed, but the player's own off is never overwritten")
        t.eq(imported, snapshot, "the import result is unchanged")
    end,

    ["vendor: an on written straight into the imported settings is still gated"] = function(t)
        local imported = Import.FromFlow({ sell = { repairWarn = 0.25 } }, nil)
        imported.account.settings.sell.autoJunk = true    -- not through the list
        imported.account.settings.sell.autoAll = false
        local account, _, report = Import.Merge(nil, nil, imported)
        t.eq(account.settings.sell, { autoAll = false, repairWarn = 0.25 }, "not confirmed: left off")
        t.eq(report.vendorLeftOff, { "sell.autoJunk" })
        local only = Import.FromFlow(nil, nil)
        only.account.settings.sell = { autoRepair = true }
        local bare = Import.Merge(nil, nil, only)
        t.eq(bare.settings.sell, nil, "no empty table is left where the automation was")
        local yes = Import.Merge(nil, nil, imported, nil, { ["sell.autoJunk"] = true })
        t.eq(yes.settings.sell.autoJunk, true, "confirmed: on")
    end,

    ["arrows: the quest arrow's place is nav.point; a place under arrows.points.quest is listed, not used"] = function(t)
        local result = Import.FromFlow({ nav = {
            point = { "TOP", "TOP", 0, -120 },
            arrows = { points = { quest = { "CENTER", "CENTER", -40, 12 } } },
        } }, nil)
        t.eq(result.account.layout.arrows, { points = { quest = { "TOP", "TOP", 0, -120 } } })
        local entry = droppedFor(result, "nav.arrows.points.quest")
        t.ok(entry and entry.why == "dropped", "the place Flow never reads is listed as dropped")
        t.ok(entry and entry.reason:find("nav.point", 1, true), "and the reason names where Flow keeps it")
        local alone = Import.FromFlow({ nav = { arrows = { points = { quest = { "CENTER", "CENTER", -40, 12 } } } } }, nil)
        t.eq(alone.account.layout.arrows, nil, "with no nav.point Flow shows the default place, so nothing is written")
        t.ok(droppedFor(alone, "nav.arrows.points.quest"), "still listed")
    end,

    ["arrows: Flow's professions arrow becomes Z-Flow's prof in places, hidden and text"] = function(t)
        local result = Import.FromFlow({ nav = { arrows = {
            mode = "stacked",
            points = { professions = { "LEFT", "LEFT", 5, 6 } },
            hidden = { professions = true, quest = false },
            text = { professions = false, quest = true },
        } } }, nil)
        t.eq(result.account.layout.arrows, {
            mode = "stacked",
            points = { prof = { "LEFT", "LEFT", 5, 6 } },
            hidden = { prof = true, quest = false },
            text = { prof = false, quest = true },
        })
        t.eq(result.record.counts.malformed, 0)
        t.eq(ns.Nav.ArrowSaved(result.account.layout),
            { mode = "stacked", points = { prof = { "LEFT", "LEFT", 5, 6 } }, hidden = { prof = true }, text = { prof = false } })
    end,

    ["arrows: an arrow Z-Flow does not have is left out with a reason"] = function(t)
        local result = Import.FromFlow({ nav = { arrows = {
            points = { pet = { "TOP", "TOP", 1, 2 } }, hidden = { pet = true }, text = { pet = false },
        } } }, nil)
        t.eq(result.account.layout.arrows, nil)
        for _, key in ipairs({ "nav.arrows.points.pet", "nav.arrows.hidden.pet", "nav.arrows.text.pet" }) do
            local entry = droppedFor(result, key)
            t.ok(entry and entry.reason ~= "", key .. " is listed with a reason")
        end
    end,

    ["arrows: nav.profArrowText is the profession arrow's text, unless the arrow has its own choice"] = function(t)
        local off = Import.FromFlow({ nav = { profArrowText = false } }, nil)
        t.eq(off.account.layout.arrows, { text = { prof = false } })
        t.eq(off.account.settings.nav, nil)
        t.eq(ns.Nav.ArrowSaved(off.account.layout).text, { prof = false }, "Z-Flow reads it as text off")
        local on = Import.FromFlow({ nav = { profArrowText = true } }, nil)
        t.eq(on.account.layout.arrows, { text = { prof = true } })
        -- Flow: arrows.text[key] wins when set (Modules/Nav/Arrows.lua:243-245).
        local own = Import.FromFlow({ nav = { profArrowText = false, arrows = { text = { professions = true } } } }, nil)
        t.eq(own.account.layout.arrows, { text = { prof = true } }, "the arrow's own choice wins, as in Flow")
        local entry = droppedFor(own, "nav.profArrowText")
        t.ok(entry and entry.why == "superseded", "the older key is listed as superseded")
        local broken = Import.FromFlow({ nav = { profArrowText = "no" } }, nil)
        t.eq(broken.account.layout.arrows, nil)
        t.ok(droppedFor(broken, "nav.profArrowText").why == "malformed", "not true or false: malformed")
    end,

    ["settings: the speech toggle bonus.spoken is kept"] = function(t)
        for _, spoken in ipairs({ true, false }) do
            local result = Import.FromFlow({ bonus = { enabled = true, spoken = spoken } }, nil)
            t.eq(result.account.settings.bonus, { enabled = true, spoken = spoken })
            t.eq(droppedFor(result, "bonus.spoken"), nil, "not listed as left behind")
        end
    end,

    ["settings: the rotation recovery choices are kept"] = function(t)
        local result = Import.FromFlow({ rotation = {
            recoverBandage = false, recoverFood = false, recoverBuffFood = true, recoverHeal = false, bandageRank = "low",
        } }, nil)
        t.eq(result.account.settings.rotation,
            { recoverBandage = false, recoverFood = false, recoverBuffFood = true, recoverHeal = false, bandageRank = "low" })
        t.eq(result.record.counts.unknown, 0, "none of them is an unknown key")
        t.eq(result.dropped, {})
    end,

    ["dropped: nav.mode and nav.professions say truly why"] = function(t)
        -- Beside nav.kinds they are its older saved names, kept in step by Flow
        -- (Modules/Nav/Nav.lua:1372, 1386, 1445-1446).
        local beside = Import.FromFlow({ nav = { kinds = { quest = true }, mode = "quests", professions = true } }, nil)
        -- Without nav.kinds they are the only record of the choice (Nav.lua:4983).
        local alone = Import.FromFlow({ nav = { mode = "quests", professions = true } }, nil)
        for _, key in ipairs({ "nav.mode", "nav.professions" }) do
            local a, b = droppedFor(beside, key), droppedFor(alone, key)
            t.ok(a and a.why == "dropped" and b and b.why == "dropped", key .. " is listed as dropped both times")
            t.ok(a.reason:find("nav.kinds", 1, true) and a.reason:find("imported", 1, true),
                key .. " beside nav.kinds: the choice is imported from there")
            t.ok(b.reason:find("not carried over", 1, true), key .. " alone: says the choice is not carried over")
            t.ok(a.reason ~= b.reason, key .. ": two cases, two reasons")
            t.ok(not a.reason:find("no longer reads", 1, true) and not b.reason:find("no longer reads", 1, true),
                key .. ": Flow still reads it")
        end
        t.eq(alone.account.settings.nav, nil, "nothing is made up from them")
    end,

    ["vendor: an absent choice stays absent, so the automation stays off"] = function(t)
        local result = Import.FromFlow({ sell = { repairWarn = 0.25 }, nav = { enabled = true } }, nil)
        t.eq(result.account.settings.sell, { repairWarn = 0.25 })
        t.eq(result.record.vendorChoices, {})
        t.eq(result.vendorToConfirm, {})
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
        result.account.layout.arrows.points.quest[3] = 500
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

    ["import: the companion button's choices, keys and place are kept"] = function(t)
        local result = Import.FromFlow(fullDb(), fullCharDb())
        t.eq(result.account.settings.buffButton,
            { enabled = true, key = "F", key2 = "SHIFT-F", dock = true, always = true, care = false, keepOnMain = true })
        t.eq(result.account.layout.buffButton, { frame = { "CENTER", "BOTTOMLEFT", 640, 220 }, scale = 1.1, dockScale = 0.8 })
        t.eq(droppedFor(result, "buffButton"), nil, "the section is not listed as left behind")
        t.eq(droppedFor(result, "buffButton.key"), nil, "nor is a key binding")
    end,

    ["import: window sizes and the chart's place and click choice are kept"] = function(t)
        local result = Import.FromFlow(fullDb(), fullCharDb())
        t.eq(result.account.layout.rotation, { frame = { "CENTER", "CENTER", 0, -200 }, scale = 1.2 })
        t.eq(result.account.layout.auction.chart, { "CENTER", "BOTTOMLEFT", 300, 500 })
        t.eq(result.account.settings.auction.chartClick, false, "a chart click switched off stays off")
        local bad = Import.FromFlow({ rotation = { scale = 0 }, buffButton = { scale = "big", dockScale = -1 } }, nil)
        t.eq(bad.account.layout, {}, "a size that is not above zero is not kept")
        for _, key in ipairs({ "rotation.scale", "buffButton.scale", "buffButton.dockScale" }) do
            local entry = droppedFor(bad, key)
            t.ok(entry and entry.why == "malformed", key .. " is listed as malformed")
        end
    end,

    ["import: the professions window's place is the character's"] = function(t)
        local result = Import.FromFlow(fullDb(), fullCharDb())
        t.eq(result.char.layout.prof, { frame = { "CENTER", "BOTTOMLEFT", 400, 300 } })
        t.eq(result.char.settings.prof.chosen, { "Tailoring", "Enchanting" })
        t.eq(result.account.layout.prof, nil, "not the account's")
        t.eq(result.char.settings.prof.suggestKey, nil, "the suggestion stamp is not a choice")
        local _, char = Import.Merge(nil, nil, result)
        t.eq(char.layout.prof, { frame = { "CENTER", "BOTTOMLEFT", 400, 300 } }, "merge carries the character's layout")
    end,

    ["import: a parked field of a section left behind whole is dropped, not unknown"] = function(t)
        local result = Import.FromFlow({}, { data = {
            ["autopush.seen"] = { [1] = true }, ["autopush.bars"] = { bear = 2 }, ["autopush.moved"] = { [3] = 12 },
            ["nav.futureField"] = 1, ["futureSection.field"] = 1,
        } })
        for _, name in ipairs({ "seen", "bars", "moved" }) do
            local entry = droppedFor(result, "FlowCharDB.data.autopush." .. name)
            t.ok(entry and entry.why == "dropped", "autopush." .. name .. " is listed as dropped")
            t.ok(entry and entry.reason:find("action bar moves", 1, true), "autopush." .. name .. " carries the section's reason")
        end
        t.eq(result.record.counts.dropped, 3)
        local future = droppedFor(result, "FlowCharDB.data.nav.futureField")
        t.eq(future and future.why, "unknown", "a section with no whole-section drop row gives no cover")
        local other = droppedFor(result, "FlowCharDB.data.futureSection.field")
        t.eq(other and other.why, "unknown")
        t.eq(result.record.counts.unknown, 2)
    end,

    ["import: parked pre-split data is listed path by path and never imported"] = function(t)
        local db = { legacyShared = { trainer = { npc = "Old Tobb" }, ["nav.hidden"] = { ["q:7"] = true }, spec = { role = "heal" } } }
        local result = Import.FromFlow(db, { adopted = { ["nav.hidden"] = true, trainer = false } })
        local taken = droppedFor(result, "legacyShared.nav.hidden")
        t.ok(taken and taken.why == "dropped" and taken.reason:find("already took its share", 1, true),
            "a path this character adopted says its share comes from the character's data")
        for _, path in ipairs({ "trainer", "spec" }) do
            local entry = droppedFor(result, "legacyShared." .. path)
            t.ok(entry and entry.why == "dropped" and entry.reason:find("nothing was imported from here", 1, true),
                path .. " says it was not imported")
            t.ok(entry and not entry.reason:find("already took", 1, true), path .. " does not claim it was adopted")
        end
        t.eq(droppedFor(result, "legacyShared"), nil, "the entries are per path")
        t.eq(result.char, emptyChar(), "nothing parked reaches the character")
        t.eq(result.account, emptyAccount(result.record), "nor the account")

        local empty = droppedFor(Import.FromFlow({ legacyShared = {} }, nil), "legacyShared")
        t.ok(empty and empty.why == "dropped" and empty.reason:find("nothing is parked", 1, true), "an empty parking place says so")
        local wrong = droppedFor(Import.FromFlow({ legacyShared = 5 }, nil), "legacyShared")
        t.eq(wrong and wrong.why, "malformed")
        local noChar = droppedFor(Import.FromFlow(db, nil), "legacyShared.nav.hidden")
        t.ok(noChar and noChar.reason:find("nothing was imported from here", 1, true),
            "with no character data nothing counts as adopted")
    end,

    ["import: the tip counter Flow keeps in nav.wayTips is dropped as a notice flag"] = function(t)
        -- Flow writes it at Modules/Nav/Waypoint.lua:90-91.
        local result = Import.FromFlow({ nav = { wayTips = 2 } }, nil)
        local entry = droppedFor(result, "nav.wayTips")
        t.ok(entry and entry.why == "dropped" and entry.reason:find("one-time notice", 1, true))
        t.eq(result.account.settings, {})
    end,

    ["import: selling values equal to what Flow writes at load are marked as not proven choices"] = function(t)
        local found = { sell = { enabled = true, junkAll = true, autoJunk = true, autoAll = true, autoRepair = false } }
        local result = Import.FromFlow(found, nil)
        t.eq(result.record.sameAsFlowDefault, { ["sell.enabled"] = true, ["sell.junkAll"] = true, ["sell.autoJunk"] = true })
        t.eq(result.account.settings.sell.enabled, true, "the value is still imported")
        t.eq(result.account.settings.sell.junkAll, true)
        local changed = Import.FromFlow({ sell = { enabled = false, junkAll = false } }, nil)
        t.eq(changed.record.sameAsFlowDefault, {}, "a value Flow would not write by itself is the player's")
        t.eq(changed.account.settings.sell, { enabled = false, junkAll = false })
        t.eq(Import.FromFlow(nil, nil).record.sameAsFlowDefault, {})
    end,

    ["mapping: the Flow keys the WOW-20 review found missing each have the row expected"] = function(t)
        -- Flow key -> where it lands ("char:" = the character's data), or
        -- false when it is left behind on purpose. Read from Flow's source;
        -- the file and line for each is in the importer's header and rows.
        local expected = {
            ["buffButton.enabled"] = "settings.buffButton.enabled",
            ["buffButton.key"] = "settings.buffButton.key",
            ["buffButton.key2"] = "settings.buffButton.key2",
            ["buffButton.dock"] = "settings.buffButton.dock",
            ["buffButton.dockScale"] = "layout.buffButton.dockScale",
            ["buffButton.point"] = "layout.buffButton.frame",
            ["buffButton.scale"] = "layout.buffButton.scale",
            ["buffButton.always"] = "settings.buffButton.always",
            ["buffButton.care"] = "settings.buffButton.care",
            ["buffButton.keepOnMain"] = "settings.buffButton.keepOnMain",
            ["rotation.scale"] = "layout.rotation.scale",
            ["ah.chartPoint"] = "layout.auction.chart",
            ["ah.chartClick"] = "settings.auction.chartClick",
            ["prof.point"] = "char:layout.prof.frame",
            ["prof.suggestKey"] = false,
            ["nav.wayTips"] = false,
            ["legacyShared"] = false,
            ["autopush"] = false,
        }
        local rows = {}
        for _, row in ipairs(Import.flowMap) do rows[row[1]] = row end
        for key, to in pairs(expected) do
            local row = rows[key]
            t.ok(row, key .. " has a row")
            if row and to then
                t.eq((row.char and "char:" or "") .. tostring(row.to), to, key .. " lands where expected")
            elseif row then
                t.ok(row.drop and not row.to, key .. " is left behind on purpose")
            end
        end
        for _, key in ipairs({ "sell.enabled", "sell.junkAll", "sell.autoJunk", "sell.autoRepair" }) do
            t.eq(rows[key] and rows[key].flowDefault, true, key .. " is marked as a value Flow writes at load")
        end
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
            -- All of it but the two vendor automations Flow had on: nobody confirmed them.
            t.eq(report.vendorLeftOff, { "sell.autoJunk", "sell.autoRepair" })
            t.eq(#report.skipped, 2, "nothing else was skipped")
            for i, name in ipairs({ "autoJunk", "autoRepair" }) do
                t.eq(report.skipped[i].path, "account.settings.sell." .. name)
                t.ok(report.skipped[i].reason:find("confirm", 1, true), name .. ": skipped because it was not confirmed")
            end
            t.eq(account.settings.sell.autoJunk, nil, "and they are not on")
            t.eq(account.settings.sell.autoRepair, nil)
            t.ok(#report.added > 0, "everything else was added")
            t.eq(#account.imports, 1)
            t.eq(account.imports[1].source, "Flow")
            t.eq(account.imports[1].merge, { added = #report.added, kept = 0, skipped = 2 })
            t.ok(account.learned ~= imported.account.learned, "the merged data shares no table with the import")
        end
        t.eq(imported, snapshot, "the import result is unchanged")
    end,

    ["merge: a value the player already has is never overwritten"] = function(t)
        local imported = Import.FromFlow(fullDb(), fullCharDb())
        local account = emptyAccount()
        account.imports = {}
        account.settings.sell = { autoAll = true, repairWarn = 0.3 }
        account.settings.nav = { arrowStyle = "flat" }
        account.layout.arrows = { points = { quest = { "BOTTOM", "BOTTOM", 0, 90 } } }
        account.learned.places.npcs = { ["Mara Stonehand"] = { map = 1412, x = 0.1, y = 0.1, n = 9 }, ["Wren Dell"] = { map = 3, x = 0.2, y = 0.2 } }
        account.learned.prices.vendor = { [2589] = 99 }
        account.learned.places.mailboxes = { { map = 9, x = 0.9, y = 0.9 } }
        local char = emptyChar()
        char.settings.spec = { role = "healer" }
        char.learned.flights = { nodes = { Stonegate = { cont = 1, wx = 7, wy = 7 } } }
        local beforeAccount, beforeChar, beforeImport = copy(account), copy(char), copy(imported)

        local newAccount, newChar, report = Import.Merge(account, char, imported)
        t.eq(report.ok, true)
        t.eq(newAccount.settings.sell.autoAll, true, "the player's own choice stays")
        t.eq(newAccount.settings.sell.autoRepair, nil, "an absent automation is not filled in on: nobody confirmed it")
        t.eq(newAccount.settings.sell.autoJunk, nil, "nor is the other one")
        t.eq(newAccount.settings.nav.arrowStyle, "flat")
        t.eq(newAccount.settings.nav.enabled, true)
        t.eq(newAccount.layout.arrows.points.quest, { "BOTTOM", "BOTTOM", 0, 90 }, "a position is kept whole, never mixed")
        t.eq(newAccount.layout.arrows.points.prof, { "TOP", "TOP", 80, -90 }, "the arrow with no place yet gets the imported one")
        t.eq(newAccount.layout.arrows.mode, "separate")
        t.eq(ns.Nav.ArrowSaved(newAccount.layout).points.quest, { "BOTTOM", "BOTTOM", 0, 90 }, "and that is the place Z-Flow reads")
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
        t.ok(kept["account.settings.sell.autoAll"], "kept: the vendor choice")
        t.ok(kept["account.layout.arrows.points.quest"], "kept: the arrow position")
        t.ok(kept["account.learned.prices.vendor.2589"], "kept: the price")
        t.ok(kept["account.learned.places.mailboxes"], "kept: the mailbox list")
        t.ok(kept["char.settings.spec.role"], "kept: the role")
        t.ok(kept["char.learned.flights.nodes.Stonegate.wx"], "kept: the flight point")
        t.ok(not added["account.settings.sell.autoRepair"], "not added: the unconfirmed automation")
        t.ok(added["account.layout.arrows.points.prof"], "added: the other arrow's place")
        t.ok(added["account.learned.prices.vendor.4306"], "added: the new price")
        t.ok(added["account.learned.places.npcs.Old Tobb"], "added: the new place")
        t.eq(skipped["account.settings.sell.repairWarn"], "the same value is already there")
        t.ok(skipped["account.settings.sell.autoAll"], "skipped lists every imported value that was not written")
        t.ok(skipped["account.settings.sell.autoRepair"], "the unconfirmed automation among them")
        t.ok(not kept["account.settings.sell.repairWarn"], "an equal value is not a conflict")
        t.eq(report.counts, { added = #report.added, kept = #report.kept, skipped = #report.skipped })
        t.eq(#newAccount.imports, 1)

        t.eq(account, beforeAccount, "the existing account data is unchanged")
        t.eq(char, beforeChar, "the existing character data is unchanged")
        t.eq(imported, beforeImport, "the import result is unchanged")
    end,

    ["merge: a setting already stored is a choice and is kept, also at its default"] = function(t)
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
        local confirmed = { ["sell.autoRepair"] = true, ["sell.autoJunk"] = true }
        local unconfirmed = (Import.Merge(account, char, imported, defaults))
        t.eq(unconfirmed.settings.sell.autoRepair, false, "stored and not confirmed: it stays off")
        local newAccount, newChar, report = Import.Merge(account, char, imported, defaults, confirmed)
        t.eq(newAccount.settings.sell.autoRepair, false, "stored, equal to the default and confirmed: still the player's choice")
        t.eq(newAccount.settings.sell.autoJunk, false, "no default given: the existing value is kept")
        t.eq(newAccount.settings.nav.arrowStyle, "flat", "not the default: the player changed it, so it is kept")
        t.eq(newChar.settings.spec.role, "damage", "a character setting equal to the default is a choice too")
        t.eq(report.counts.kept, 4)
        local without, withoutChar = Import.Merge(account, char, imported, nil, confirmed)
        t.eq(without.settings, newAccount.settings, "the defaults given make no difference to settings")
        t.eq(withoutChar.settings, newChar.settings)
    end,

    ["merge: a layout value still at its default gives way to the import"] = function(t)
        local imported = Import.FromFlow({ buffButton = { scale = 1.5, dockScale = 0.8 } }, {})
        local account = emptyAccount()
        account.layout.buffButton = { scale = 1, dockScale = 1.2 }
        local defaults = { account = { layout = { buffButton = { scale = 1, dockScale = 1 } } } }
        local newAccount = (Import.Merge(account, emptyChar(), imported, defaults))
        t.eq(newAccount.layout.buffButton.scale, 1.5, "still the default: the import is used")
        t.eq(newAccount.layout.buffButton.dockScale, 1.2, "not the default: it is kept")
        local without = (Import.Merge(account, emptyChar(), imported))
        t.eq(without.layout.buffButton.scale, 1, "without defaults nothing existing is replaced")
    end,

    ["merge: a stored setting of the wrong type is no choice and gives way"] = function(t)
        local imported = Import.FromFlow({ buffButton = { enabled = true, dock = false } }, {})
        local account = emptyAccount()
        account.settings.buffButton = { enabled = "yes", dock = true }
        local newAccount, _, report = Import.Merge(account, emptyChar(), imported)
        t.eq(newAccount.settings.buffButton.enabled, true)
        t.eq(newAccount.settings.buffButton.dock, true, "a stored yes-or-no is a choice")
        t.eq(report.kept, { "account.settings.buffButton.dock" })
        t.eq(account.settings.buffButton, { enabled = "yes", dock = true }, "the existing data is unchanged")
    end,

    ["import: the stored record keeps what was left behind and what was adjusted"] = function(t)
        local result = Import.FromFlow({ buffButton = { scale = 9, enabled = "yes" }, rotation = { scale = 40 }, madeUp = 1 }, {})
        local stored = result.account.imports[1]
        t.ok(#result.adjusted >= 2, "the fixture adjusts fewer than two values")
        t.ok(#result.dropped >= 2, "the fixture leaves fewer than two values behind")
        t.eq(stored.adjusted, result.adjusted)
        t.eq(stored.dropped, result.dropped)
        t.ok(stored.adjusted ~= result.adjusted and stored.adjusted[1] ~= result.adjusted[1],
            "the stored adjusted list is the result's own table")
        t.ok(stored.dropped ~= result.dropped and stored.dropped[1] ~= result.dropped[1],
            "the stored dropped list is the result's own table")
        t.ok(stored.adjusted ~= result.record.adjusted, "the stored record shares a list with the result's record")
        local was = result.adjusted[1].to
        stored.adjusted[1].to = "changed"
        stored.dropped[1].reason = "changed"
        t.eq(result.adjusted[1].to, was)
        t.eq(result.record.adjusted[1].to, was)
        t.ok(result.dropped[1].reason ~= "changed", "changing the stored record changed the result")
    end,

    ["import: an import with nothing left behind stores two empty lists"] = function(t)
        local result = Import.FromFlow({}, {})
        t.eq(result.dropped, {})
        t.eq(result.account.imports[1].dropped, {})
        t.eq(result.account.imports[1].adjusted, {})
    end,

    ["merge: the record merged in keeps both lists as its own copies"] = function(t)
        local result = Import.FromFlow({ buffButton = { scale = 9, enabled = "yes" }, rotation = { scale = 40 }, madeUp = 1 }, {})
        local before = copy(result)
        local account = (Import.Merge(nil, nil, result))
        local stored = account.imports[#account.imports]
        t.eq(stored.adjusted, result.adjusted)
        t.eq(stored.dropped, result.dropped)
        t.ok(stored.adjusted ~= result.adjusted and stored.adjusted ~= result.record.adjusted,
            "the merged record shares its adjusted list")
        t.ok(stored.dropped ~= result.dropped and stored.dropped ~= result.record.dropped,
            "the merged record shares its dropped list")
        stored.adjusted[1].to = "changed"
        t.eq(result, before, "the import result is unchanged")
    end,

    ["merge: a result whose record has no lists still stores them from the result"] = function(t)
        local result = Import.FromFlow({ buffButton = { scale = 9 }, madeUp = 1 }, {})
        result.record.dropped, result.record.adjusted = nil, nil
        local account = (Import.Merge(nil, nil, result))
        local stored = account.imports[#account.imports]
        t.eq(stored.adjusted, result.adjusted)
        t.eq(stored.dropped, result.dropped)
        t.ok(stored.adjusted ~= result.adjusted, "the merged record shares its adjusted list")
    end,

    ["merge: a list that holds itself is stored without hanging"] = function(t)
        local result = Import.FromFlow({ buffButton = { scale = 9 } }, {})
        result.record.dropped, result.record.adjusted = nil, nil
        local loop = { key = "x" }
        loop.from = loop
        result.adjusted = { loop }
        local account = (Import.Merge(nil, nil, result))
        t.eq(account.imports[#account.imports].adjusted, { { key = "x" } })
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

    -- ------------------------------------------- merge asks the model
    ["merge: a stored number outside the model's bounds is no choice and gives way"] = function(t)
        local model, problems = ns.Settings.Model.New({
            { key = "nav.pathAlpha", type = "number", default = 1, bounds = { min = 0, max = 1 } },
            { key = "nav.mapLines", type = "bool", default = true },
        })
        t.eq(problems, {})
        local function flow()
            return Import.FromFlow({ nav = { pathAlpha = 0.5, mapLines = false } }, {})
        end
        t.eq(flow().account.settings.nav, { pathAlpha = 0.5, mapLines = false }, "the fixture did not reach the import")

        local account = emptyAccount()
        account.settings.nav = { pathAlpha = 7, mapLines = true }
        local out, _, report = Import.Merge(account, emptyChar(), flow(), nil, nil, model)
        t.eq(out.settings.nav.pathAlpha, 0.5, "a stored number the model refuses was kept as a choice")
        t.eq(out.settings.nav.mapLines, true, "a stored value that fits was replaced")
        local added = {}
        for _, at in ipairs(report.added) do added[at] = true end
        t.eq(added["account.settings.nav.pathAlpha"], true, "the replaced setting is not reported as added")
        t.eq(added["account.settings.nav.mapLines"], nil, "the kept setting is reported as added")
        t.eq(report.kept, { "account.settings.nav.mapLines" })
        t.eq(account.settings.nav, { pathAlpha = 7, mapLines = true }, "the existing data was changed")

        local inside = emptyAccount()
        inside.settings.nav = { pathAlpha = 0.25 }
        local kept = (Import.Merge(inside, emptyChar(), flow(), nil, nil, model))
        t.eq(kept.settings.nav.pathAlpha, 0.25, "a stored number inside the bounds is a choice")
    end,

    ["merge: an import value the model refuses does not replace a stored one"] = function(t)
        local model = (ns.Settings.Model.New({
            { key = "nav.pathAlpha", type = "bool", default = true },
        }))
        local account = emptyAccount()
        account.settings.nav = { pathAlpha = "yes" }
        local imported = Import.FromFlow({ nav = { pathAlpha = 9 } }, {})
        t.eq(imported.account.settings.nav.pathAlpha, 9, "the fixture did not reach the import")
        local out, _, report = Import.Merge(account, emptyChar(), imported, nil, nil, model)
        t.eq(out.settings.nav.pathAlpha, "yes", "one value the model refuses replaced another")
        t.eq(report.kept, { "account.settings.nav.pathAlpha" })
    end,

    ["merge: a setting the model has no row for still compares types"] = function(t)
        local model = (ns.Settings.Model.New({
            { key = "nav.pathAlpha", type = "number", default = 1, bounds = { min = 0, max = 1 } },
        }))
        local account = emptyAccount()
        account.settings.nav = { arrowStyle = 4, mapLines = true }
        local imported = Import.FromFlow({ nav = { arrowStyle = "modern", mapLines = false } }, {})
        local out = (Import.Merge(account, emptyChar(), imported, nil, nil, model))
        t.eq(out.settings.nav.arrowStyle, "modern", "a stored value of another type was kept")
        t.eq(out.settings.nav.mapLines, true, "a stored value of the same type was replaced")
        local odd = (Import.Merge(account, emptyChar(), imported, nil, nil, "not a model"))
        t.eq(odd.settings.nav.arrowStyle, "modern")
        t.eq(odd.settings.nav.mapLines, true, "something that is no model changed what is kept")
    end,

    -- ------------------------------------------- the stored record
    ["merge: a record that holds itself or a function is stored without them"] = function(t)
        local imported = Import.FromFlow({}, {})
        local record = { source = "Flow", importer = Import.flowImporterVersion, counts = { places = 0 } }
        record.again = record
        record.counts.back = record
        record.call = function() end
        imported.record = record
        local ok, account = pcall(Import.Merge, nil, nil, imported)
        t.ok(ok, "the merge raised: " .. tostring(account))
        if not ok then return end
        local stored = account.imports[#account.imports]
        t.eq(stored.source, "Flow")
        t.eq(stored.importer, Import.flowImporterVersion)
        t.eq(stored.counts.places, 0)
        t.eq(stored.again, nil, "the record still holds itself")
        t.eq(stored.counts.back, nil, "a table inside the record still holds the record")
        t.eq(stored.call, nil, "a function was stored")
        t.ok(stored ~= record, "the stored record is the caller's own table")
        t.eq(type(stored.merge), "table")
        t.eq(stored.vendorConfirmed, {})
    end,

    ["merge: numbers that are not finite are left out of the stored record"] = function(t)
        local imported = Import.FromFlow({}, {})
        imported.record = { source = "Flow", fine = 1.5, bad = NAN, big = math.huge, small = -math.huge }
        imported.dropped = { { key = "a", value = math.huge }, { key = "b", value = -math.huge }, { key = "c", value = NAN } }
        imported.adjusted = { { key = "d", from = math.huge, to = 2 } }
        local account = (Import.Merge(nil, nil, imported))
        local stored = account.imports[#account.imports]
        t.eq(stored.fine, 1.5)
        t.eq(stored.bad, nil, "a number that is not a number was stored")
        t.eq(stored.big, nil, "infinity was stored")
        t.eq(stored.small, nil, "minus infinity was stored")
        t.eq(stored.dropped, { { key = "a" }, { key = "b" }, { key = "c" } })
        t.eq(stored.adjusted, { { key = "d", to = 2 } })
    end,

    ["import: the importer version is 3"] = function(t)
        t.eq(Import.flowImporterVersion, 3, "the importer version moved; say why in the version notes and here")
        local result = Import.FromFlow({}, {})
        t.eq(result.record.importer, 3)
        local account = (Import.Merge(nil, nil, result))
        t.eq(account.imports[#account.imports].importer, 3, "the merged record lost its importer version")
    end,
}

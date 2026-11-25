local _, ns = ...
-- The place of a profession step in words (Nav/ProfStep.lua N.ProfPlace,
-- Nav/ProfFeed.lua F.PlaceFor, F.Placed, F.NoPlace): each step kind gets
-- the nearest KNOWN place, on the map the player is on and else in a
-- capital; with nothing known it gets none and a plain line says so; the
-- step's own words are kept. Pure: plain tables in. Made-up names and
-- places only. Not tested in game.
--
-- Red before the code: N.ProfPlace and the three feed functions are not
-- there, so every test here fails.
local N = ns.Nav
local tests = {}

local function PP() return N.ProfPlace end
local function F() return N.ProfFeed end

local function has(t)
    local ok = type(PP()) == "table" and type(PP().Of) == "function"
        and type(F().PlaceFor) == "function" and type(F().Placed) == "function"
        and type(F().NoPlace) == "function"
    t.ok(ok, "N.ProfPlace.Of and the feed's PlaceFor, Placed and NoPlace are there")
    return ok
end

-- Maps 1411 and 1412 are open country, 1454 and 1456 capitals on the
-- player's continent, 1453 a capital on the other one.
local CONT = { [1411] = 1, [1412] = 1, [1454] = 1, [1456] = 1, [1453] = 2 }
local CAPITALS = { [1453] = true, [1454] = true, [1456] = true }

local function known(more)
    local k = {
        here = { map = 1411, x = 0.5, y = 0.5, faction = "Horde" },
        capitals = CAPITALS,
        contOf = function(map) return CONT[map] end,
    }
    for key, v in pairs(more or {}) do k[key] = v end
    return k
end

local function trainer(map, x, prof, faction)
    return { map = map, x = x, y = 0.5, roles = { trainer = true }, trains = { [prof] = true },
             factions = { [faction or "Horde"] = true } }
end

local LEARN = { kind = "learn_recipe", text = "Learn a Tailoring recipe at a trainer" }
local TRAIN = { kind = "train_tier", text = "Train the next Tailoring rank at a trainer" }

tests["prof place: a trainer step gets the nearest known trainer of its profession on this map"] = function(t)
    if not has(t) then return end
    local k = known({ npcs = {
        ["Far Tess"] = trainer(1411, 0.9, "Tailoring"),
        ["Near Tess"] = trainer(1411, 0.6, "Tailoring"),
        ["Cook"] = trainer(1411, 0.51, "Cooking"),
        ["Other Side"] = trainer(1411, 0.52, "Tailoring", "Alliance"),
    } })
    t.eq(PP().Of(LEARN, "Tailoring", k), { map = 1411, x = 0.6, y = 0.5 }, "learn a recipe: the nearest tailor")
    t.eq(PP().Of(TRAIN, "Tailoring", k), { map = 1411, x = 0.6, y = 0.5 }, "train the next rank: the same")
    t.eq(PP().Of(LEARN, "Cooking", k), { map = 1411, x = 0.51, y = 0.5 }, "by profession")
    t.eq(PP().Of(LEARN, "Alchemy", k), nil, "no trainer of that profession known: no place")
    t.eq(PP().Of({ kind = "learn_recipe", npc = "Someone", text = "Learn it at Someone" }, "Tailoring", k), nil,
        "a step that names its trainer is not sent to another one")
    t.eq(LEARN.target, nil, "the step handed in is not changed")
end

tests["prof place: a trainer saved with no roles still counts, by what it trains"] = function(t)
    if not has(t) then return end
    local k = known({ npcs = { ["Tess"] = { map = 1411, x = 0.6, y = 0.5, trains = { Tailoring = true } } } })
    t.eq(PP().Of(LEARN, "Tailoring", k), { map = 1411, x = 0.6, y = 0.5 })
end

tests["prof place: with none on this map, a trainer in a capital on this continent"] = function(t)
    if not has(t) then return end
    local k = known({ npcs = {
        ["Across The Sea"] = trainer(1453, 0.5, "Tailoring"),
        ["Next Zone"] = trainer(1412, 0.5, "Tailoring"),
    } })
    t.eq(PP().Of(LEARN, "Tailoring", k), nil, "another continent's capital, or a zone that is no capital: no place")
    k.npcs["In Town"] = trainer(1454, 0.4, "Tailoring")
    t.eq(PP().Of(LEARN, "Tailoring", k), { map = 1454, x = 0.4, y = 0.5 }, "the capital on this continent")
    k.npcs["On The Bluff"] = trainer(1456, 0.3, "Tailoring")
    k.far = function(place) return place.map == 1456 and 100 or 900 end
    t.eq(PP().Of(LEARN, "Tailoring", k), { map = 1456, x = 0.3, y = 0.5 }, "of two capitals, the nearer")
    k.npcs["Here"] = trainer(1411, 0.9, "Tailoring")
    t.eq(PP().Of(LEARN, "Tailoring", k), { map = 1411, x = 0.9, y = 0.5 }, "one on this map comes first")
end

tests["prof place: a bank step gets the nearest known banker, an auction step the auctioneer"] = function(t)
    if not has(t) then return end
    local k = known({ services = {
        a = { map = 1411, x = 0.2, y = 0.5, kinds = { banker = true } },
        b = { map = 1411, x = 0.45, y = 0.5, kinds = { banker = true } },
        v = { map = 1411, x = 0.5, y = 0.5, kinds = { vendor = true } },
    } })
    local BANK = { kind = "take_bank", text = "Take 4 Test Bar from your bank, for Test Blade" }
    local AUCTION = { kind = "buy_auction", text = "Buy 4 Test Bar at the auction house" }
    t.eq(PP().Of(BANK, "Blacksmithing", k), { map = 1411, x = 0.45, y = 0.5 }, "the nearest banker, never the vendor")
    t.eq(PP().Of(AUCTION, "Blacksmithing", k), nil, "no auctioneer known: no place")
    -- An entry of the account's npcs whose roles say it (an imported one).
    k.npcs = {
        ["Auctioneer Test"] = { map = 1454, x = 0.55, y = 0.6, roles = { auction = true }, factions = { Horde = true } },
        ["Their Auctioneer"] = { map = 1411, x = 0.5, y = 0.5, roles = { auction = true }, factions = { Alliance = true } },
    }
    t.eq(PP().Of(AUCTION, "Blacksmithing", k), { map = 1454, x = 0.55, y = 0.6 },
        "the auctioneer in the capital, not the other faction's here")
    t.eq(PP().Of(BANK, "Blacksmithing", known({})), nil, "nothing saved: no place")
end

tests["prof place: a gathering step gets the nearest node of its own profession gathered here"] = function(t)
    if not has(t) then return end
    local k = known({ nodes = {
        { x = 0.3, y = 0.3, prof = "Herbalism" },
        { x = 0.4, y = 0.4, prof = "Mining" },
        { x = 0.8, y = 0.8, prof = "Mining" },
        { x = 0.5, y = 0.5 },
    } })
    local MINE = { kind = "gather_skill", gather = "Mining", text = "Mine any ore vein you find" }
    t.eq(PP().Of(MINE, "Mining", k), { map = 1411, x = 0.4, y = 0.4 }, "the first Mining node, nearest first")
    t.eq(PP().Of({ kind = "gather_skill", gather = "Fishing", text = "Fish" }, "Fishing", k), nil,
        "no node of that profession: no place")
    t.eq(PP().Of(MINE, "Mining", known({})), nil, "no node gathered: no place")
end

tests["prof place: a craft at an anvil gets one seen in a capital, only with none seen on this map"] = function(t)
    if not has(t) then return end
    local CRAFT = { kind = "craft", station = "anvil", text = "Make 2 Test Blade at an anvil" }
    local SMELT = { kind = "make_part", station = "forge", text = "Smelt 2 Test Bar at a forge" }
    local k = known({ stations = { { kind = "forge", map = 1454, x = 0.7, y = 0.3 },
                                   { kind = "anvil", map = 1453, x = 0.1, y = 0.1 },
                                   { kind = "fire", map = 1454, x = 0.2, y = 0.2 } } })
    t.eq(PP().Of(CRAFT, "Blacksmithing", k), { map = 1454, x = 0.7, y = 0.3 }, "a forge stands by an anvil")
    t.eq(PP().Of(SMELT, "Mining", k), { map = 1454, x = 0.7, y = 0.3 }, "the smelt: the forge")
    t.eq(PP().Of({ kind = "craft", station = "fire", text = "Cook 2 Test Stew at a fire" }, "Cooking", k), nil,
        "a fire is never looked for in a capital")
    t.eq(PP().Of({ kind = "craft", text = "Make 2 Test Bandage" }, "First Aid", k), nil, "a craft with no station")
    k.stations[#k.stations + 1] = { kind = "anvil", map = 1411, x = 0.5, y = 0.52 }
    t.eq(PP().Of(CRAFT, "Blacksmithing", k), nil, "one on this map is the plan's own step: no second place")
end

tests["prof place: unknown stays unknown"] = function(t)
    if not has(t) then return end
    local full = known({ npcs = { ["Tess"] = trainer(1411, 0.6, "Tailoring") } })
    for _, kind in ipairs({ "buy_vendor", "find_material", "open_window", "no_point", "gather", "buy_recipe" }) do
        t.eq(PP().Of({ kind = kind, text = "words" }, "Tailoring", full), nil, kind .. ": no place is looked for")
    end
    local lost = known({ npcs = full.npcs })
    lost.here = nil
    t.eq(PP().Of(LEARN, "Tailoring", lost), nil, "where the player is is not known: no place")
    lost.here = { map = 1411 }
    t.eq(PP().Of(LEARN, "Tailoring", lost), nil, "the map without the spot on it: no place")
    t.eq(PP().Of(LEARN, "Tailoring", nil), nil)
    t.eq(PP().Of(nil, "Tailoring", full), nil)
end

tests["prof feed: a pick in words asks for a place; one with its own, or held back, does not"] = function(t)
    if not has(t) then return end
    local asked = 0
    local function place(step, prof)
        asked = asked + 1
        if step.kind == "learn_recipe" and prof == "Tailoring" then return { map = 1411, x = 0.6, y = 0.5 } end
        return nil
    end
    t.eq(F().PlaceFor({ prof = "Tailoring", step = LEARN, rank = 4 }, place), { map = 1411, x = 0.6, y = 0.5 })
    t.eq(F().PlaceFor({ prof = "Cooking", step = LEARN, rank = 4 }, place), nil, "none known: none")
    t.eq(asked, 2)
    local own = { kind = "learn_recipe", text = "Learn it at Tess", target = { map = 1411, x = 0.1, y = 0.1 } }
    t.eq(F().PlaceFor({ prof = "Tailoring", step = own, rank = 2 }, place), nil, "the plan's own place stands")
    t.eq(F().PlaceFor({ prof = "Tailoring", step = LEARN, rank = 5, held = true }, place), nil, "held back: words")
    t.eq(F().PlaceFor({ prof = "Tailoring", rank = 6, text = "Open your Tailoring window once" }, place), nil)
    t.eq(asked, 2, "none of those three asked")
    t.eq(F().PlaceFor({ prof = "Tailoring", step = LEARN }, function() return { map = 1411, x = 7, y = 0.5 } end), nil,
        "an answer that is no place on a map is not used")
    t.eq(F().PlaceFor({ prof = "Tailoring", step = LEARN }, nil), nil)
end

tests["prof feed: a placed step keeps every word it had and gains only the place"] = function(t)
    if not has(t) then return end
    local step = { still = true, label = LEARN.text, lines = { LEARN.text, "Open your Cooking window once" } }
    local out = F().Placed(step, { map = 1454, x = 0.4, y = 0.5 }, 1)
    t.eq(out.lines, { LEARN.text, "Open your Cooking window once" }, "the same lines, in the same order")
    t.eq(out.label, LEARN.text)
    t.eq(out.place, { cont = 1, map = 1454, x = 0.4, y = 0.5 })
    t.eq(out.radius, N.PROF_NEAR)
    t.eq(out.still, nil, "it has somewhere to turn to")
    t.eq(step.place, nil, "the step handed in is not changed")
    t.eq(step.still, true)
    t.eq(F().Placed(step, nil, 1), step, "no place: the step as it was")
    t.eq(F().Placed(step, { map = 1454, x = 2, y = 0.5 }, 1), step, "not a place on a map: the step as it was")
    local has2 = { place = { map = 1411, x = 0.1, y = 0.1 }, label = "x" }
    t.eq(F().Placed(has2, { map = 1454, x = 0.4, y = 0.5 }, 1), has2, "a step with a place keeps its own")
end

tests["prof feed: with no place known a plain line says so, by the kind of place"] = function(t)
    if not has(t) then return end
    local W = F().NO_PLACE
    t.ok(type(W) == "table", "the words are there")
    if type(W) ~= "table" then return end
    local function note(kind, prof, more)
        local step = { kind = kind, text = "words" }
        for key, v in pairs(more or {}) do step[key] = v end
        return F().NoPlace({ prof = prof, step = step, rank = 4 })
    end
    t.eq(note("learn_recipe", "Tailoring"), W.trainer:format("Tailoring"))
    t.eq(note("train_tier", "Tailoring"), W.trainer:format("Tailoring"))
    t.eq(note("take_bank", "Tailoring"), W.banker)
    t.eq(note("buy_auction", "Tailoring"), W.auction)
    t.eq(note("gather_skill", "Mining"), W.node:format("Mining"))
    t.eq(note("gather_skill", "Skinning"), nil, "a profession with no nodes: no line about nodes")
    t.eq(note("craft", "Blacksmithing", { station = "anvil" }), nil, "a station step says what to look for itself")
    t.eq(note("buy_vendor", "Tailoring"), nil)
    t.eq(note("learn_recipe", "Tailoring", { target = { map = 1411, x = 0.1, y = 0.1 } }), nil, "it has a place")
    t.eq(F().NoPlace({ prof = "Tailoring", step = LEARN, held = true }), nil, "held back: its own words say where")
    t.eq(F().NoPlace({ prof = "Tailoring", rank = 6 }), nil)
    t.eq(F().NoPlace(nil), nil)
end

tests["prof feed: the no-place line comes right under the step's own words, before the other professions"] = function(t)
    if not has(t) then return end
    local result = F().Pick({
        names = { "Cooking", "Tailoring" },
        readings = { Cooking = { skill = 40, max = 75 }, Tailoring = { skill = 10, max = 75 } },
        plan = function(prof)
            if prof == "Tailoring" then return { LEARN } end
            return {}
        end,
    })
    t.eq(result.pick and result.pick.prof, "Tailoring")
    t.eq(result.pick and result.pick.rank, 4, "a step in words keeps its rank")
    local note = F().NoPlace(result.pick)
    local step = F().Step(result, note)
    t.eq(step.lines, { LEARN.text, F().NO_PLACE.trainer:format("Tailoring"), "Open your Cooking window once" })
    t.eq(step.place, nil, "and no place is made up")
    t.eq(step.still, true)
    t.eq(F().Step(result).lines, { LEARN.text, "Open your Cooking window once" }, "no line handed in: as before")
end

return tests

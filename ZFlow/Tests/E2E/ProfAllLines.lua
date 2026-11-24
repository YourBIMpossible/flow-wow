local _, ns = ...
-- Lead section 416 item 2: the profession needle covered one profession,
-- so a later profession at its cap got no word. The needle still points at
-- the one step picked across the professions; under the pick's own lines
-- comes one line for every other profession, naming its own current step
-- (the plan's words, or with no step its say line). A line over
-- N.Waypoint.LABEL_MAX bytes is said short by its kind, or left out, never
-- cut. Whole add-on loaded the way the game loads it (ns.offline.addon) on
-- a fake client, made-up places and names only. Look only. Not tested in
-- game.
--
-- Red before the code: only the pick's lines.
local tests = {}
local N = ns.Nav

-- opts: professions, skill (char profSkill), plan (a stand-in for the
-- planner's live read: { [profession] = { step, ... } }, nil: the real one),
-- npcs (account learned.places.npcs).
local function start(opts)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true },
        learned = opts.npcs and { places = { npcs = opts.npcs } } or nil })
    c.setSaved(ns.id.charDB, { learned = { facts = { profSkill = opts.skill } } })
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFacing(0)
    c.setFaction("Horde")
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    c.setMapCont(1411, 1)
    c.setProfessions(opts.professions)
    local addon = ns.offline.addon(c)
    if opts.plan then addon.profPlan = { plan = function(prof) return opts.plan[prof] end } end
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

tests["prof all lines: the pick, then one line for each other profession, a capped one too"] = function(t)
    local c = start({ professions = { "Alchemy", "Herbalism", "Tailoring" },
        skill = { Herbalism = { skill = 20, max = 75 }, Tailoring = { skill = 75, max = 75 } } })
    local p = c.arrows[2]
    t.eq(p and p.shown, true, "the profession frame is up")
    t.ok(N.ProfFeed.ALSO_SHORT ~= nil and N.ProfFeed.KIND_WORDS ~= nil, "the short form exists")
    -- Herbalism's herb line is picked (as before); Alchemy, not read, says
    -- to open its window; Tailoring's training line is 54 bytes, so it is
    -- said short by its kind.
    t.eq(p and p.lines, {
        "Pick any herb you find (Herbalism 20 of 75)",
        N.ProfFeed.OPEN:format("Alchemy"),
        (N.ProfFeed.ALSO_SHORT or "%s: %s"):format("Tailoring",
            N.ProfFeed.KIND_WORDS and N.ProfFeed.KIND_WORDS.train_tier or "?"),
    }, "the pick, then Alchemy and Tailoring by name")
    c.advance(0.1, 2)
    t.eq(p and type(p.drawn) == "table" and p.drawn.body, 0, "no needle: the pick has no place")
end

local FIRE = { kind = "go_station", text = "Cook 3 Test Fish at a fire", count = 3,
               target = { map = 1411, x = 0.45, y = 0.5 } }
local ORE = { kind = "gather", text = "Mine 4 Test Ore", count = 4,
              target = { map = 1411, x = 0.9, y = 0.5 } }
local TIER = { kind = "train_tier", text = "Train Zeta at Test Mentor" }

tests["prof all lines: a picked place keeps its needle; the others follow its label"] = function(t)
    local c = start({ professions = { "Cooking", "Mining", "Zeta" },
        skill = { Cooking = { skill = 40, max = 75 }, Mining = { skill = 60, max = 75 },
                  Zeta = { skill = 75, max = 75 } },
        plan = { Cooking = { FIRE }, Mining = { ORE }, Zeta = { TIER } } })
    local p = c.arrows[2]
    local l = p and p.lines or {}
    t.eq(l[1], FIRE.text, "the fire 50 yd away is picked, its label first")
    t.eq(l[2], ORE.text, "then Mining's own step")
    t.eq(l[3], TIER.text, "then the capped profession's training step")
    t.ok(type(l[4]) == "string" and l[4]:match("^50 yd") ~= nil, "then how far the pick is: " .. tostring(l[4]))
    c.advance(0.1, 2)
    t.ok(p and type(p.drawn) == "table" and p.drawn.body ~= 0, "the needle is drawn, at the pick")
end

-- Lead section 418 item 6: N.ProfChoose (Nav/ProfStep.lua) may pick the
-- older step (the trainer it knows) over the feed's training in words; the
-- other professions' lines follow that step too, none for the profession
-- it covers.
local TRAIN = { kind = "train_tier", text = "Train Cooking at Test Tutor" }
local PICK = { kind = "buy_vendor", text = "Buy 2 Test Picks" }

local function tutor(map)
    return { ["Test Tutor"] = { map = map, x = 0.7, y = 0.5, roles = { trainer = true },
        trains = { Cooking = true }, factions = { Horde = true }, id = 4711, seen = 90, n = 1 } }
end

local function older(map)
    local c = start({ professions = { "Alchemy", "Cooking", "Mining" },
        skill = { Cooking = { skill = 75, max = 75 }, Mining = { skill = 30, max = 75 } },
        plan = { Cooking = { TRAIN }, Mining = { PICK } }, npcs = tutor(map) })
    return c
end

tests["prof all lines: the older trainer step with a place, then the other professions"] = function(t)
    local c = older(1411)
    local p = c.arrows[2]
    local l = p and p.lines or {}
    t.eq(l[1], "Cooking trainer", "the older step: the trainer it knows")
    t.eq(l[2], N.ProfFeed.OPEN:format("Alchemy"), "then Alchemy, not read")
    t.eq(l[3], PICK.text, "then Mining's own step")
    for _, line in ipairs(l) do t.ok(line ~= TRAIN.text, "no line for Cooking, the step covers it") end
    t.ok(type(l[4]) == "string" and l[4]:match("^%d+ yd") ~= nil, "then how far the trainer is: " .. tostring(l[4]))
    c.advance(0.1, 2)
    t.ok(p and type(p.drawn) == "table" and p.drawn.body ~= 0, "the needle is drawn, at the trainer")
end

tests["prof all lines: the older trainer step in words, then the other professions"] = function(t)
    local c = older(1453)
    local p = c.arrows[2]
    t.eq(p and p.lines, {
        "Cooking trainer" .. N.PROF_OTHER_MAP,
        N.ProfFeed.OPEN:format("Alchemy"),
        PICK.text,
    }, "the trainer on another map, then Alchemy and Mining")
    c.advance(0.1, 2)
    t.eq(p and type(p.drawn) == "table" and p.drawn.body, 0, "no needle: the step has no place")
end

return tests

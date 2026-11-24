local _, ns = ...
-- Lead section 288 (zflow-prof-arrow, N25 widened): the profession needle
-- on any character with a profession, on by default. The next step by
-- priority: the trainer when capped; else the nearest known node of a
-- gathering profession; else the craft that gives a point, as one text line
-- under the arrow. Nothing to point at: one line that says why and how the
-- player supplies it. No profession: nothing. Whole add-on loaded the way
-- the game loads it (ns.offline.addon) on a fake client, made-up places and
-- names only. Look only. Not tested in game.
local tests = {}
local N = ns.Nav

-- opts: professions (client.professions names), skill (char profSkill),
-- book (char recipeBook), colours (char recipeColors), nodes (GatherMate2
-- rows on map 1411), npcs (account), account (the account saved table),
-- charSettings (the settings of the character), stations (the account's
-- learned.keyStations: { kind, map, x, y } rows).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    local account = opts.account or {}
    account.layout = account.layout or {}
    account.layout.arrowIntroSeen = true
    if opts.npcs then account.learned = { places = { npcs = opts.npcs } } end
    if opts.stations then
        account.learned = account.learned or {}
        account.learned.keyStations = opts.stations
    end
    c.setSaved(ns.id.accountDB, account)
    c.setSaved(ns.id.charDB, { settings = opts.charSettings, learned = {
        facts = { profSkill = opts.skill, recipeBook = opts.book },
        recipeColors = opts.colours,
    } })
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFacing(0)
    c.setFaction("Horde")
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    if opts.professions then c.setProfessions(opts.professions) end
    if opts.nodes then c.setGatherMateNodes(1411, opts.nodes) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function fmt(pattern, ...)
    if type(pattern) ~= "string" then return nil end
    return pattern:format(...)
end

-- Every line any shown arrow says.
local function said(c)
    local out = {}
    for _, h in ipairs(c.arrows or {}) do
        if h.shown then
            for _, line in ipairs(type(h.lines) == "table" and h.lines or {}) do out[#out + 1] = line end
        end
    end
    return out
end

-- The profession frame is up with exactly these lines and no needle.
local function textOnly(t, c, lines, what)
    local p = c.arrows[2]
    t.eq(p and p.shown, true, what .. ": the profession frame is up")
    t.eq(p and p.lines, lines, what .. ": its words")
    c.advance(0.1, 2)
    t.eq(p and type(p.drawn) == "table" and p.drawn.body, 0, what .. ": no needle")
end

local COPPER = { kind = "Mining", x = 0.6, y = 0.5, node = "Copper Vein" }
local FAR_COPPER = { kind = "Mining", x = 0.9, y = 0.9, node = "Copper Vein" }
local HERB = { kind = "Herb Gathering", x = 0.51, y = 0.5, node = "Peacebloom" }

-- Fails before: a fresh gathering character gets no needle and no word.
tests["prof needle: a fresh Mining character with no node source says why and how"] = function(t)
    local c = start({ professions = { "Mining" } })
    t.ok(N.PROF_WHY_GM_ABSENT ~= nil, "the line exists")
    textOnly(t, c, { fmt(N.PROF_WHY_GM_ABSENT, "Mining") }, "no GatherMate2")
end

-- Fails before: no needle to a known node.
tests["prof needle: a gathering profession points at the nearest known node of its kind"] = function(t)
    local c = start({ professions = { "Mining" }, nodes = { FAR_COPPER, HERB, COPPER } })
    local p = c.arrows[2]
    t.eq(p.shown, true, "the profession needle is up")
    t.eq(p.lines and p.lines[1], "Copper Vein", "the name of the node")
    t.eq(p.lines and p.lines[2], fmt(N.PROF_NODE_DETAIL, "Mining"), "what it is")
    t.ok(type(p.lines and p.lines[3]) == "string" and p.lines[3]:match("^100 yd") ~= nil,
        "the nearer vein, 100 yd away: " .. tostring(p.lines and p.lines[3]))
    c.advance(0.1, 2)
    t.ok(type(p.drawn) == "table" and p.drawn.body ~= 0, "the needle is drawn")
end

tests["prof needle: a node source turned off, or with no node of the kind here, says so"] = function(t)
    local c = start({ professions = { "Mining" }, nodes = { HERB },
        charSettings = { professions = { gatherMateNodes = false } } })
    textOnly(t, c, { fmt(N.PROF_WHY_GM_OFF, "Mining") }, "source off")
    local c2 = start({ professions = { "Mining" }, nodes = { HERB } })
    textOnly(t, c2, { fmt(N.PROF_WHY_NODE, "Mining") }, "no Mining node on this map")
end

-- Fails before: a fresh crafting character gets nothing.
tests["prof needle: a fresh Tailoring character is told to open the window once"] = function(t)
    local c = start({ professions = { "Tailoring" } })
    t.ok(N.PROF_WHY_READ ~= nil, "the line exists")
    textOnly(t, c, { fmt(N.PROF_WHY_READ, "Tailoring") }, "no reading")
end

local BOOK = {
    ["Bolt of Linen Cloth"] = { profession = "Tailoring" },
    ["Linen Bag"] = { profession = "Tailoring" },
    ["Rough Arrow"] = { profession = "Engineering" },
}

-- Fails before: the craft that gives a point is said only in the window.
tests["prof needle: a crafting profession says the craft that gives a point, as text"] = function(t)
    local c = start({ professions = { "Tailoring" }, skill = { Tailoring = { skill = 50, max = 75 } }, book = BOOK,
        colours = {
            ["Linen Bag"] = { medium = { lo = 45, hi = 55 } },
            ["Bolt of Linen Cloth"] = { optimal = { lo = 40, hi = 60 } },
            ["Rough Arrow"] = { optimal = { lo = 1, hi = 99 } },
        } })
    t.ok(N.PROF_CRAFT_SURE ~= nil, "the line exists")
    textOnly(t, c, { fmt(N.PROF_CRAFT_SURE, "Bolt of Linen Cloth", "Tailoring") }, "orange first")

    local c2 = start({ professions = { "Tailoring" }, skill = { Tailoring = { skill = 50, max = 75 } }, book = BOOK,
        colours = { ["Linen Bag"] = { medium = { lo = 45, hi = 55 } },
                    ["Bolt of Linen Cloth"] = { trivial = { lo = 40, hi = 60 } } } })
    textOnly(t, c2, { fmt(N.PROF_CRAFT_MAYBE, "Linen Bag", "Tailoring") }, "yellow when no orange")
end

tests["prof needle: a crafting profession with nothing that gives a point says why"] = function(t)
    local c = start({ professions = { "Tailoring" }, skill = { Tailoring = { skill = 50, max = 75 } }, book = BOOK,
        colours = { ["Bolt of Linen Cloth"] = { trivial = { lo = 40, hi = 60 } },
                    ["Linen Bag"] = { optimal = { lo = 10, hi = 20 }, trivial = { lo = 45, hi = 55 } } } })
    -- Lead section 421 point 2: "all grey" means every known recipe was
    -- seen grey, so Linen Bag is marked seen grey here.
    textOnly(t, c, { fmt(N.PROF_WHY_NO_POINT, "Tailoring", 50) }, "all grey at 50")
    local c2 = start({ professions = { "Tailoring" }, skill = { Tailoring = { skill = 50, max = 75 } } })
    textOnly(t, c2, { fmt(N.PROF_WHY_RECIPES, "Tailoring") }, "no recipe colours seen")
end

-- Lead section 421 point 2: a recipe last seen orange at 20 with the skill
-- now 50 was never seen grey, so it stays the step, worded as not
-- confirmed: the craft, then when it was last seen giving points and the
-- window to open. Fails before: "No known Tailoring recipe gives a point at 50".
tests["prof needle: a recipe last seen orange at 20, skill now 50, is the step, not confirmed"] = function(t)
    local c = start({ professions = { "Tailoring" }, skill = { Tailoring = { skill = 50, max = 75 } }, book = BOOK,
        colours = { ["Bolt of Linen Cloth"] = { trivial = { lo = 40, hi = 60 } },
                    ["Linen Bag"] = { optimal = { lo = 10, hi = 20 } } } })
    t.ok(N.PROF_CRAFT_STALE ~= nil and N.PROF_STALE_CHECK ~= nil, "the lines exist")
    textOnly(t, c, { fmt(N.PROF_CRAFT_STALE, "Linen Bag"), fmt(N.PROF_STALE_CHECK, 20, "Tailoring") },
        "last seen orange at 20, skill now 50")
end

-- Fails before: a capped profession with no trainer seen says nothing.
tests["prof needle: capped with no trainer known, or already visited, says why"] = function(t)
    local c = start({ skill = { Mining = { skill = 75, max = 75 } } })
    textOnly(t, c, { fmt(N.PROF_WHY_TRAINER, "Mining", 75, "Mining") }, "no trainer seen")
    local c2 = start({ skill = { Mining = { skill = 75, max = 75, visitedAtCap = 75 } } })
    textOnly(t, c2, { fmt(N.PROF_WHY_TRAIN, "Mining", 75) }, "visited at this cap")
end

-- Passes before for the trainer; fails before for the order with the rest.
tests["prof needle: the trainer when capped comes first, then a node, then a craft"] = function(t)
    local npcs = { ["Test Trainer"] = { map = 1411, x = 0.8, y = 0.5, trains = { Mining = true },
                                        factions = { Horde = true }, seen = 10 } }
    local colours = { ["Bolt of Linen Cloth"] = { optimal = { lo = 40, hi = 60 } } }
    local c = start({ professions = { "Mining", "Tailoring" }, npcs = npcs, nodes = { COPPER }, book = BOOK,
        colours = colours, skill = { Mining = { skill = 75, max = 75 }, Tailoring = { skill = 50, max = 75 } } })
    t.eq(c.arrows[2].lines and c.arrows[2].lines[1], "Mining trainer", "capped: the trainer")

    local c2 = start({ professions = { "Mining", "Tailoring" }, nodes = { COPPER }, book = BOOK, colours = colours,
        skill = { Mining = { skill = 30, max = 75 }, Tailoring = { skill = 50, max = 75 } } })
    -- The stack (sections 382, 388): the needle still takes the node before
    -- the craft; the lines are now the profession, then the whole step with
    -- the vein named in it.
    local l2 = c2.arrows[2].lines or {}
    t.eq(l2[1], "Mining", "not capped: the node before the craft")
    t.ok(type(l2[2]) == "string" and l2[2]:find("Copper Vein", 1, true) ~= nil,
        "the step names the vein: " .. tostring(l2[2]))
    c2.advance(0.1, 2)
    t.ok(type(c2.arrows[2].drawn) == "table" and c2.arrows[2].drawn.body ~= 0, "the needle is drawn")

    local c3 = start({ professions = { "Mining", "Tailoring" }, book = BOOK, colours = colours,
        skill = { Mining = { skill = 30, max = 75 }, Tailoring = { skill = 50, max = 75 } } })
    -- No node, and no cloth in the bags: the old line said "Make Bolt of
    -- Linen Cloth", a craft this character cannot make. The one step is now
    -- the point it can get: any ore vein. (With the materials in the bags
    -- the craft comes first: Tests/E2E/ProfFeedRealPlan.lua.)
    textOnly(t, c3, { "Mine any ore vein you find (Mining 30 of 75)" }, "no node, no materials: the vein")
end

-- Passes before: a guard that a character with no profession sees nothing.
tests["prof needle: no profession, or only weapon skills, shows nothing"] = function(t)
    for name, list in pairs({ none = false, skills = { "Swords", "Defense" } }) do
        local c = start({ professions = list or nil })
        t.eq(c.arrows[2] and c.arrows[2].shown, false, name .. ": no profession frame")
        t.eq(said(c), { ns.Arrow.NO_QUEST }, name .. ": no profession line; only the quest arrow says why (lead section 294 item 5)")
    end
end

-- Fails before: the why line the setting must also silence does not exist.
tests["prof needle: nav.profArrow off says nothing, even a why line; a saved non-boolean is on"] = function(t)
    local c = start({ professions = { "Mining" }, account = { settings = { nav = { profArrow = false } } } })
    t.eq(c.arrows[2] and c.arrows[2].shown, false, "off: no profession frame")
    t.eq(said(c), { ns.Arrow.NO_QUEST }, "off: no profession line; only the quest arrow says why (lead section 294 item 5)")
    t.ok(N.PROF_WHY_GM_ABSENT ~= nil, "the line exists")
    local c2 = start({ professions = { "Mining" }, account = { settings = { nav = { profArrow = "no" } } } })
    t.eq(c2.arrows[2] and c2.arrows[2].lines, { fmt(N.PROF_WHY_GM_ABSENT, "Mining") }, "not false: on")
end

-- Fails before: the line follows what the windows of the player save,
-- during play, with no reload.
tests["prof needle: a reading saved during play changes the line with no reload"] = function(t)
    local c, addon = start({ professions = { "Tailoring" }, book = BOOK,
        colours = { ["Bolt of Linen Cloth"] = { optimal = { lo = 40, hi = 60 } } } })
    t.ok(N.PROF_WHY_READ ~= nil and N.PROF_CRAFT_SURE ~= nil, "the lines exist")
    t.eq(c.arrows[2].lines, { fmt(N.PROF_WHY_READ, "Tailoring") }, "before: open the window")
    addon.store:set("char", "learned.facts.profSkill", { Tailoring = { skill = 50, max = 75 } })
    c.advance(2, 8)
    t.eq(c.arrows[2].lines, { fmt(N.PROF_CRAFT_SURE, "Bolt of Linen Cloth", "Tailoring") }, "after: the craft")
end

-- Mutation regressions (PN5, PN16, PN14): a capped profession gains no
-- point from a node or a craft, so with no trainer known it says why; and a
-- recipe of another profession is never offered as this one's craft.
tests["prof needle: a capped gatherer with a node near, and no trainer known, says why, not the node"] = function(t)
    local c = start({ professions = { "Mining" }, nodes = { COPPER }, skill = { Mining = { skill = 75, max = 75 } } })
    textOnly(t, c, { fmt(N.PROF_WHY_TRAINER, "Mining", 75, "Mining") }, "capped gatherer")
end

tests["prof needle: a capped crafter whose craft is orange, and no trainer known, says why, not the craft"] = function(t)
    local c = start({ professions = { "Tailoring" }, skill = { Tailoring = { skill = 75, max = 75 } }, book = BOOK,
        colours = { ["Bolt of Linen Cloth"] = { optimal = { lo = 40, hi = 90 } } } })
    textOnly(t, c, { fmt(N.PROF_WHY_TRAINER, "Tailoring", 75, "Tailoring") }, "capped crafter")
end

tests["prof needle: a recipe of another profession is not offered as the craft"] = function(t)
    local c = start({ professions = { "Tailoring" }, skill = { Tailoring = { skill = 50, max = 75 } }, book = BOOK,
        colours = { ["Rough Arrow"] = { optimal = { lo = 1, hi = 99 } },
                    ["Linen Bag"] = { trivial = { lo = 40, hi = 60 } } } })
    textOnly(t, c, { fmt(N.PROF_WHY_NO_POINT, "Tailoring", 50) }, "only an Engineering recipe gives a point")
end

-- Lead section 339 (zflow-prof-guide): with nothing to point at, the why
-- line covered only the first profession by name, so a capped profession
-- later in the alphabet got no word at all. Now one line per profession,
-- by name. Fails before: only the Alchemy line.
tests["prof guide: nothing to point at says one line for each profession, not only the first by name"] = function(t)
    local c = start({ professions = { "Alchemy", "Tailoring" },
        skill = { Alchemy = { skill = 10, max = 75 }, Tailoring = { skill = 75, max = 75 } } })
    textOnly(t, c, { fmt(N.PROF_WHY_RECIPES, "Alchemy"), fmt(N.PROF_WHY_TRAINER, "Tailoring", 75, "Tailoring") },
        "Alchemy with no recipe seen, Tailoring capped with no trainer known")
end

tests["prof guide: a gatherer with no node and a capped crafter each get their line"] = function(t)
    local c = start({ professions = { "Herbalism", "Tailoring" },
        skill = { Herbalism = { skill = 20, max = 75 }, Tailoring = { skill = 75, max = 75 } } })
    -- The stack (section 382): one step across the professions, the next
    -- point it can get. Herbs need no node source to be picked, so the line
    -- says to pick them; it no longer asks for a node add-on, and the capped
    -- profession (no point until trained) waits its turn.
    textOnly(t, c, { "Pick any herb you find (Herbalism 20 of 75)" },
        "Herbalism with no node known, Tailoring capped")
end

-- Lead section 341 (zflow-prof-guide): a craft step had no place, so a
-- crafter never got a needle. A craft of a profession that works at a
-- station now points at the nearest such station this account has seen on
-- the map. Fails before: text only, no needle.
local SMITH_BOOK = { ["Test Buckle"] = { profession = "Blacksmithing" } }
local SMITH_COLOURS = { ["Test Buckle"] = { optimal = { lo = 40, hi = 60 } } }

tests["prof guide: a craft that needs an anvil points the needle at the nearest anvil seen"] = function(t)
    local c = start({ professions = { "Blacksmithing" }, skill = { Blacksmithing = { skill = 50, max = 75 } },
        book = SMITH_BOOK, colours = SMITH_COLOURS,
        stations = { { kind = "anvil", map = 1411, x = 0.9, y = 0.9 }, { kind = "anvil", map = 1411, x = 0.6, y = 0.5 } } })
    local p = c.arrows[2]
    t.eq(p.shown, true, "the profession needle is up")
    t.eq(p.lines and p.lines[1], "Blacksmithing anvil", "where to go")
    t.eq(p.lines and p.lines[2], fmt(N.PROF_CRAFT_SURE, "Test Buckle", "Blacksmithing"), "what to make there")
    t.ok(type(p.lines and p.lines[3]) == "string" and p.lines[3]:match("^100 yd") ~= nil,
        "the nearer anvil, 100 yd away: " .. tostring(p.lines and p.lines[3]))
    c.advance(0.1, 2)
    t.ok(type(p.drawn) == "table" and p.drawn.body ~= 0, "the needle is drawn")
end

tests["prof guide: an anvil seen only on another map leaves the craft as text"] = function(t)
    local c = start({ professions = { "Blacksmithing" }, skill = { Blacksmithing = { skill = 50, max = 75 } },
        book = SMITH_BOOK, colours = SMITH_COLOURS, stations = { { kind = "anvil", map = 1412, x = 0.6, y = 0.5 } } })
    textOnly(t, c, { fmt(N.PROF_CRAFT_SURE, "Test Buckle", "Blacksmithing") }, "no anvil on this map")
end

-- The route: the nearest stop with a place is the next one. Fails before:
-- the trainer 300 yd away, whatever is nearer.
tests["prof guide: the nearest stop comes first: an anvil at 100 yd before a trainer at 300 yd"] = function(t)
    local npcs = { ["Test Trainer"] = { map = 1411, x = 0.8, y = 0.5, trains = { Mining = true },
                                        factions = { Horde = true }, seen = 10 } }
    local c = start({ professions = { "Blacksmithing", "Mining" }, npcs = npcs, book = SMITH_BOOK, colours = SMITH_COLOURS,
        skill = { Mining = { skill = 75, max = 75 }, Blacksmithing = { skill = 50, max = 75 } },
        stations = { { kind = "anvil", map = 1411, x = 0.6, y = 0.5 } } })
    t.eq(c.arrows[2].lines and c.arrows[2].lines[1], "Blacksmithing anvil", "the anvil is nearer")
    local c2 = start({ professions = { "Blacksmithing", "Mining" }, npcs = npcs, book = SMITH_BOOK, colours = SMITH_COLOURS,
        skill = { Mining = { skill = 75, max = 75 }, Blacksmithing = { skill = 50, max = 75 } },
        stations = { { kind = "anvil", map = 1411, x = 0.1, y = 0.5 } } })
    t.eq(c2.arrows[2].lines and c2.arrows[2].lines[1], "Mining trainer", "the trainer is nearer")
end

return tests

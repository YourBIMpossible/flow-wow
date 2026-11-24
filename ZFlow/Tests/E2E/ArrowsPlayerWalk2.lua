local _, ns = ...
-- Lead section 414, on top of section 413 (Tests/E2E/ArrowsPlayerWalk.lua):
-- the profession arrow walks the player through every next point.
--   (a) the skill has risen past the last skill at which the profession
--       window was seen: the arrow still names a step, without the window
--       being kept open;
--   (b) a craft step has a place: the anvil or forge the player crafted at
--       is saved when the craft succeeds (outside Rotation/, and not in the
--       list the key reads), and the needle points at the nearest one on
--       the map; with none known the step is in words and says what to
--       look for.
-- The whole add-on on a fake client; nothing of the profession is saved
-- ahead. Made-up recipes, items and places. Offline only: not tested in
-- game.
local tests = {}

local ORE, BAR, BELT_ITEM = 1, 2, 50
local HERE = 1411

local function ranks(c, smith, mining)
    c.setSkillRanks({ Blacksmithing = { rank = smith, max = 75 }, Mining = { rank = mining or 60, max = 75 } })
end

local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setScreen(1024, 768); c.setZone(1, HERE); c.setFacing(0); c.setFaction("Horde")
    c.setPosition(HERE, 0.5, 0.5); c.setMapSize(HERE, 1000, 500); c.setMapCont(HERE, 1)
    c.setItemInfo({ [ORE] = { name = "Test Ore" }, [BAR] = { name = "Test Bar" }, [BELT_ITEM] = { name = "Test Belt" } })
    c.setBagItems(opts.bags or {})
    c.setProfessions(opts.profs or { "Blacksmithing" })
    ranks(c, 50)
    local db = {}
    function db.GetQuest(id) if id == 303 then return { ObjectiveData = { { Type = "monster", Id = 9002 } } } end end
    function db.GetNPC(id) if id == 9002 then return { name = "Far Wolf", spawns = { [12] = { { 50, 30 } } } } end end
    local zones = {}
    function zones.GetUiMapIdByAreaId(a) return ({ [12] = HERE })[a] end
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog({ { id = 303, title = "Wolves", objectives = { { text = "Wolves slain: 0/4" } } } })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon, addon.problems:count()
end

local function window(c, prof, skill, recipes)
    local rows = {}
    for i, r in ipairs(recipes) do
        rows[i] = { id = r.id, name = r.name, learned = true, difficulty = r.colour }
        c.setRecipeSchematic(r.id, { makes = r.makes, yield = 1, mats = r.mats })
    end
    c.setRecipes({ profession = prof == "Mining" and 186 or 164, name = prof, skill = skill, max = 75, recipes = rows })
    c.fire("TRADE_SKILL_SHOW"); c.fire("TRADE_SKILL_LIST_UPDATE")
    c.advance(2, 8)
end

local function close(c)
    c.setRecipes(nil)
    c.fire("TRADE_SKILL_CLOSE")
    c.advance(1, 4)
end

local function belt(colour)
    return { id = 901, name = "Test Belt", colour = colour or "optimal", makes = BELT_ITEM, mats = { [BAR] = 2 } }
end
local SMELT = { id = 902, name = "Test Smelt", colour = "easy", makes = BAR, mats = { [ORE] = 1 } }

local function prof(c) return c.arrows[2] end
local function said(h) return table.concat(h and h.lines or {}, " | ") end
local function has(text, part) return text:find(part, 1, true) ~= nil end

-- The game says a craft of the player's finished.
local function crafted(c, id)
    c.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-test", id)
    c.advance(1, 4)
end

local function walk(c, x, y)
    c.setPosition(HERE, x, y)
    c.advance(2, 8)
end

-- (a) ------------------------------------------------------------------

tests["player walk 2a: the skill rose with the window shut: the craft is still the step, at the new skill"] = function(t)
    local c, addon, before = boot({ bags = { { item = BAR, count = 40 } } })
    window(c, "Blacksmithing", 50, { belt() })
    close(c)
    -- Five crafts later, the window never opened again: only the skill
    -- line moved.
    ranks(c, 55)
    c.advance(2, 8)
    local line = said(prof(c))
    t.ok(has(line, "Make ") and has(line, "Test Belt"), line)
    t.ok(has(line, "Blacksmithing 55 of 75"), "the skill the game has now: " .. line)
    t.ok(has(line, "last seen giving points at 50"), "and it says how old the colour is: " .. line)
    t.ok(not has(line, "Open your"), line)
    t.eq(addon.problems:count(), before)
end

tests["player walk 2a: a colour seen at the skill wins over one only seen lower"] = function(t)
    local c, addon, before = boot({ bags = { { item = BAR, count = 40 } } })
    local nail = { id = 903, name = "Test Nail", colour = "medium", makes = 51, mats = { [BAR] = 1 } }
    window(c, "Blacksmithing", 50, { belt() })
    window(c, "Blacksmithing", 55, { belt("easy"), nail })
    close(c)
    local line = said(prof(c))
    t.ok(has(line, "Test Nail"), "the one seen giving a point at 55: " .. line)
    t.ok(not has(line, "last seen"), line)
    t.eq(addon.problems:count(), before)
end

tests["player walk 2a: a recipe seen green or grey is never the step, however far the skill rose"] = function(t)
    local c, addon, before = boot({ bags = { { item = BAR, count = 40 } } })
    window(c, "Blacksmithing", 50, { belt() })
    window(c, "Blacksmithing", 60, { belt("easy") })
    close(c)
    ranks(c, 64)
    c.advance(2, 8)
    local line = said(prof(c))
    t.eq(prof(c).shown, true, "still a step")
    t.ok(not has(line, "Make "), "not a craft that stopped giving points: " .. line)
    t.eq(addon.problems:count(), before)
end

tests["player walk 2a: the skill reached the cap with the window shut: the trainer is the step"] = function(t)
    local c, addon, before = boot({ bags = { { item = BAR, count = 80 } } })
    window(c, "Blacksmithing", 50, { belt() })
    close(c)
    ranks(c, 75)
    c.advance(2, 8)
    local line = said(prof(c))
    t.ok(not has(line, "Make "), line)
    t.ok(has(line:lower(), "train"), line)
    t.eq(addon.problems:count(), before)
end

-- (b) ------------------------------------------------------------------

tests["player walk 2b: no anvil known: the craft in words, and what to look for"] = function(t)
    local c, addon, before = boot({ bags = { { item = BAR, count = 6 } } })
    window(c, "Blacksmithing", 50, { belt() })
    close(c)
    local p = prof(c)
    t.eq(p.drawn.body, 0, "no needle: no place is guessed")
    t.eq(p.lines[1], "Make 1 Test Belt at an anvil (Blacksmithing 50 of 75)")
    t.ok(has(said(p), "Look for an anvil"), said(p))
    t.eq(addon.problems:count(), before)
end

tests["player walk 2b: a craft that succeeds saves the anvil; from then on the needle points at it"] = function(t)
    local c, addon, before = boot({ bags = { { item = BAR, count = 6 } } })
    window(c, "Blacksmithing", 50, { belt() })
    crafted(c, 901)
    t.eq(addon.store:get("account", "learned.craftSpots"), { { kind = "anvil", map = HERE, x = 0.5, y = 0.5 } })
    t.eq(#(addon.store:get("account", "learned.keyStations") or {}), 0, "the key's own list gets nothing from this")
    c.setBagItems({ { item = BAR, count = 4 } })
    window(c, "Blacksmithing", 51, { belt() })
    close(c)
    -- A second craft on the same spot adds nothing.
    crafted(c, 901)
    t.eq(#addon.store:get("account", "learned.craftSpots"), 1)
    walk(c, 0.3, 0.5)
    local p = prof(c)
    t.eq(p.shown, true)
    t.ok(p.drawn.body ~= 0, "the needle is drawn")
    t.eq(p.lookIs, "needle")
    t.ok(has(said(p), "anvil"), said(p))
    t.ok(not has(said(p), "Look for"), "a place is known: " .. said(p))
    t.eq(addon.problems:count(), before)
end

tests["player walk 2b: a smelt that succeeds saves the forge; the smelt step points at it"] = function(t)
    local c, addon, before = boot({ bags = { { item = ORE, count = 6 } }, profs = { "Blacksmithing", "Mining" } })
    window(c, "Mining", 60, { SMELT })
    crafted(c, 902)
    close(c)
    t.eq(addon.store:get("account", "learned.craftSpots"), { { kind = "forge", map = HERE, x = 0.5, y = 0.5 } })
    window(c, "Blacksmithing", 50, { belt() })
    close(c)
    walk(c, 0.3, 0.5)
    local p = prof(c)
    t.ok(has(said(p), "Smelt 2 Test Bar at a forge"), said(p))
    t.ok(p.drawn.body ~= 0, "the needle points at the forge")
    t.eq(addon.problems:count(), before)
end

tests["player walk 2b: no forge known: the smelt in words, and what to look for"] = function(t)
    local c, addon, before = boot({ bags = { { item = ORE, count = 6 } }, profs = { "Blacksmithing", "Mining" } })
    window(c, "Mining", 60, { SMELT })
    close(c)
    window(c, "Blacksmithing", 50, { belt() })
    close(c)
    local p = prof(c)
    t.eq(p.lines[1], "Smelt 2 Test Bar at a forge, for Test Belt")
    t.ok(has(said(p), "Look for a forge"), said(p))
    t.eq(p.drawn.body, 0)
    t.eq(addon.problems:count(), before)
end

tests["player walk 2b: the nearest saved anvil on this map is the one pointed at"] = function(t)
    local c, addon, before = boot({ bags = { { item = BAR, count = 20 } } })
    window(c, "Blacksmithing", 50, { belt() })
    crafted(c, 901)
    walk(c, 0.9, 0.5)
    crafted(c, 901)
    t.eq(#addon.store:get("account", "learned.craftSpots"), 2)
    close(c)
    walk(c, 0.8, 0.5)
    local step = addon.profPlan.plan("Blacksmithing")[1]
    t.eq(step.kind, "go_station")
    t.eq(step.target, { map = HERE, x = 0.9, y = 0.5 })
    walk(c, 0.4, 0.5)
    t.eq(addon.profPlan.plan("Blacksmithing")[1].target, { map = HERE, x = 0.5, y = 0.5 })
    t.eq(addon.problems:count(), before)
end

tests["player walk 2b: a cast that is no recipe of the player's, or not the player's, saves nothing"] = function(t)
    local c, addon, before = boot({ bags = { { item = BAR, count = 6 } } })
    window(c, "Blacksmithing", 50, { belt() })
    close(c)
    crafted(c, 12345)
    c.fire("UNIT_SPELLCAST_SUCCEEDED", "target", "Cast-test", 901)
    c.advance(1, 4)
    t.eq(addon.store:get("account", "learned.craftSpots"), nil)
    t.eq(addon.problems:count(), before)
end

return tests

local _, ns = ...
-- Lead section 402 item 6 (Twin's finding, section 336): a second
-- profession gets guidance too, not only the first by name. Two professions
-- learned, books read empty: "/zflow prof plan" gives each its own next
-- step, and with the first by name done, the arrow's pick is the second.
-- Through the whole add-on on a fake client (ns.offline.addon); the real
-- planner feeds it. Not tested in game.
local tests = {}

-- skills: { [prof] = { skill, max } }
local function start(skills)
    local profs, readings = {}, {}
    for prof, r in pairs(skills) do
        profs[#profs + 1] = prof
        readings[prof] = { skill = r[1], max = r[2] }
    end
    table.sort(profs)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, { learned = { facts = { profSkill = readings, recipeBook = {} }, recipeColors = {} } })
    c.setScreen(1024, 768)
    c.setZone(1, 1411); c.setFaction("Horde"); c.setFacing(0)
    c.setPosition(1411, 0.5, 0.5); c.setMapSize(1411, 1000, 500); c.setMapCont(1411, 1)
    c.setBagItems({})
    c.setProfessions(profs)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function plan(c)
    c.printed = {}
    c.slashes[ns.id.slash]("prof plan")
    c.advance(1, 5)
    local out = {}
    for _, line in ipairs(c.printed) do out[#out + 1] = tostring(line) end
    return table.concat(out, "\n")
end

local function has(text, words)
    return text:find(words, 1, true) ~= nil
end

tests["prof two e2e: two crafts, empty books: each gets its own next step"] = function(t)
    local c = start({ Blacksmithing = { 10, 75 }, Tailoring = { 20, 75 } })
    local text = plan(c)
    t.ok(has(text, "Learn a Blacksmithing recipe at a trainer (Blacksmithing 10 of 75)"), "the first: " .. text)
    t.ok(has(text, "Learn a Tailoring recipe at a trainer (Tailoring 20 of 75)"), "the second too: " .. text)
end

tests["prof two e2e: a craft and a gathering one: both get a step"] = function(t)
    local c = start({ Mining = { 30, 75 }, Tailoring = { 20, 75 } })
    local text = plan(c)
    t.ok(has(text, "Mine any ore vein you find"), "Mining: " .. text)
    t.ok(has(text, "Learn a Tailoring recipe at a trainer"), "Tailoring: " .. text)
end

tests["prof two e2e: the first by name is done: the pick is the second"] = function(t)
    local c = start({ Blacksmithing = { 300, 300 }, Tailoring = { 20, 75 } })
    local text = plan(c)
    t.ok(has(text, "Next: Learn a Tailoring recipe"), "the pick moves on: " .. text)
end

return tests

local _, ns = ...
-- N72 (lead section 248 item 4): the pure parts of the macro icon search.
-- The words typed, the file name of an icon the client names by path, the
-- matcher (by spell or item name, by file name or keyword, one filter at a
-- time, each icon once), the slices it runs in (results capped per frame),
-- the index rows it keeps and the hint the box shows. Made-up names and
-- icons only. Not tested in game.
local tests = {}

local function MI() return ns.MacroIcons or {} end

local function call(name, ...)
    local fn = MI()[name]
    if type(fn) ~= "function" then return "no " .. name end
    return fn(...)
end

-- Runs a match job to its end; the icons found, and how many steps it took.
local function finish(job, cap, slice)
    local steps = 0
    while steps < 1000 do
        steps = steps + 1
        if call("Step", job, cap, slice) == true then break end
    end
    return job.out, steps
end

local ROWS = {
    { name = "Fireball", kind = "spell", icon = 101 },
    { name = "Frostbolt", kind = "spell", icon = 102 },
    { name = "Fire Oil", kind = "item", icon = 201 },
    { name = "Fire Ward", kind = "spell", icon = 101 },
}
local FIRE_FILE = "Interface\\Icons\\Spell_Fire_FlameBolt"
local FILES = { { file = "spell_fire_flamebolt", icon = FIRE_FILE }, { file = "inv_misc_gem_01", icon = "Interface\\Icons\\INV_Misc_Gem_01" } }

tests["macro icons: the words typed, in lower case, spaces at the ends taken off"] = function(t)
    t.eq(call("Norm", "  Fire Ball "), "fire ball")
    t.eq(call("Norm", "FROST"), "frost")
    t.eq(call("Norm", nil), "")
    t.eq(call("Norm", 5), "")
end

tests["macro icons: the file name of an icon named by path; a number has none"] = function(t)
    t.eq(call("FileName", "Interface\\Icons\\Spell_Fire_Fireball.blp"), "spell_fire_fireball")
    t.eq(call("FileName", "Interface/Icons/INV_Misc_QuestionMark"), "inv_misc_questionmark")
    t.eq(call("FileName", "INV_Misc_Gem_01"), "inv_misc_gem_01")
    t.eq(call("FileName", 135000), nil, "a file number has no name the client gives")
    t.eq(call("FileName", ""), nil)
end

tests["macro icons: All finds spell and item names, then file names, each icon once"] = function(t)
    local job = call("Matcher", "fire", "all", ROWS, FILES)
    t.ok(type(job) == "table", "a job")
    if type(job) ~= "table" then return end
    t.eq(finish(job, 50, 200), { 101, 201, FIRE_FILE }, "Fire Ward shares Fireball's icon: shown once")
end

tests["macro icons: Spells and Items find only their own names, never file names"] = function(t)
    local spells = call("Matcher", "fire", "spells", ROWS, FILES)
    local items = call("Matcher", "fire", "items", ROWS, FILES)
    if type(spells) ~= "table" or type(items) ~= "table" then t.ok(false, "jobs"); return end
    t.eq(finish(spells, 50, 200), { 101 })
    t.eq(finish(items, 50, 200), { 201 })
end

tests["macro icons: every word typed must be found, in any order; a keyword of a file name works"] = function(t)
    local job = call("Matcher", "bolt frost", "all", ROWS, FILES)
    if type(job) ~= "table" then t.ok(false, "a job"); return end
    t.eq(finish(job, 50, 200), { 102 })
    local gem = call("Matcher", "gem", "all", ROWS, FILES)
    t.eq(finish(gem, 50, 200), { "Interface\\Icons\\INV_Misc_Gem_01" })
    local none = call("Matcher", "plumtree", "all", ROWS, FILES)
    t.eq(finish(none, 50, 200), {})
end

tests["macro icons: an unknown filter is All"] = function(t)
    local job = call("Matcher", "fire", "nonsense", ROWS, FILES)
    if type(job) ~= "table" then t.ok(false, "a job"); return end
    t.eq(finish(job, 50, 200), { 101, 201, FIRE_FILE })
end

tests["macro icons: each step adds at most the cap of new matches"] = function(t)
    local rows = {}
    for i = 1, 120 do rows[i] = { name = "Fire " .. i, kind = "spell", icon = 1000 + i } end
    local job = call("Matcher", "fire", "all", rows, {})
    if type(job) ~= "table" then t.ok(false, "a job"); return end
    t.eq(call("Step", job, 50, 1000), false)
    t.eq(#job.out, 50)
    t.eq(call("Step", job, 50, 1000), false)
    t.eq(#job.out, 100)
    t.eq(call("Step", job, 50, 1000), true)
    t.eq(#job.out, 120)
end

tests["macro icons: each step looks at no more than the slice"] = function(t)
    local rows = {}
    for i = 1, 500 do rows[i] = { name = "Frost " .. i, kind = "spell", icon = i } end
    local job = call("Matcher", "fire", "all", rows, {})
    if type(job) ~= "table" then t.ok(false, "a job"); return end
    local out, steps = finish(job, 50, 200)
    t.eq(out, {})
    t.eq(steps, 3, "500 rows in slices of 200")
end

tests["macro icons: the index build runs its parts in order, a slice a step"] = function(t)
    local seen = {}
    local phases = {
        { n = 3, fn = function(i) seen[#seen + 1] = "a" .. i end },
        { n = 0, fn = function(i) seen[#seen + 1] = "skip" .. i end },
        { n = 2, fn = function(i) seen[#seen + 1] = "b" .. i end },
    }
    local run = call("Runner", phases)
    if type(run) ~= "table" then t.ok(false, "a runner"); return end
    t.eq(call("Run", run, 2), false)
    t.eq(seen, { "a1", "a2" })
    t.eq(call("Run", run, 2), false)
    t.eq(seen, { "a1", "a2", "a3", "b1" })
    t.eq(call("Run", run, 2), true)
    t.eq(seen, { "a1", "a2", "a3", "b1", "b2" })
end

tests["macro icons: an index row needs a name and an icon, and is kept once"] = function(t)
    local index = call("NewIndex")
    if type(index) ~= "table" then t.ok(false, "an index"); return end
    t.eq(call("AddRow", index, "Fireball", "spell", 101), true)
    t.eq(call("AddRow", index, "Fireball", "spell", 101), false, "the same row again")
    t.eq(call("AddRow", index, "Fireball", "item", 101), true, "an item of that name is its own row")
    t.eq(call("AddRow", index, "", "spell", 5), false)
    t.eq(call("AddRow", index, nil, "spell", 5), false)
    t.eq(call("AddRow", index, "Frost", "spell", 0), false)
    t.eq(call("AddRow", index, "Frost", "spell", ""), false)
    t.eq(call("AddRow", index, "Frost", "spell", "Interface\\Icons\\Frost"), true)
    t.eq(call("AddRow", index, "Frost", "pet", 7), false, "only spell and item rows")
    t.eq(#index.rows, 3)
    t.eq(call("AddFile", index, "Interface\\Icons\\Spell_Fire_Fireball"), true)
    t.eq(call("AddFile", index, "Interface\\Icons\\Spell_Fire_Fireball"), false, "once")
    t.eq(call("AddFile", index, 135000), false, "a file number has no name")
    t.eq(index.files, { { file = "spell_fire_fireball", icon = "Interface\\Icons\\Spell_Fire_Fireball" } })
end

tests["macro icons: the hint says searching, none, or how many"] = function(t)
    t.eq(call("Hint", 3, false), "Searching...")
    t.eq(call("Hint", 0, true), "No icon matches.")
    t.eq(call("Hint", 1, true), "1 match")
    t.eq(call("Hint", 12, true), "12 matches")
    for _, s in ipairs({ call("Hint", 0, true), call("Hint", 2, true), MI().LABEL or "" }) do
        t.ok(not tostring(s):find("Flow"), "no add-on name in the words")
    end
end

tests["macro icons: the filters, in order, and the frame budget"] = function(t)
    t.eq(MI().FILTERS, { "all", "spells", "items" })
    t.ok(type(MI().SLICE) == "number" and MI().SLICE > 0 and MI().SLICE <= 500, "a slice")
    t.ok(type(MI().CAP) == "number" and MI().CAP > 0 and MI().CAP <= 100, "a cap")
end

return tests

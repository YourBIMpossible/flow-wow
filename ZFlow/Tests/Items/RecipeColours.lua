local _, ns = ...
-- RecipeColours (Items/RecipeColours.lua, lead section 413): the colour a
-- recipe had in the player's own window, saved by the skill it was seen at.
-- Made-up recipes. Not tested in game.
local tests = {}
local R = ns.RecipeColours

local function store(start)
    local s = { data = { char = { [R.PATH] = start } }, sets = 0 }
    function s:get(scope, path) return self.data[scope][path] end
    function s:set(scope, path, v)
        self.data[scope][path] = v
        self.sets = self.sets + 1
        return true
    end
    return s
end

local function modern(skill, rows)
    return { recipes = function() return { profession = 164, name = "Blacksmithing", skill = skill, max = 75, recipes = rows } end }
end

tests["recipe colours: a colour is saved at the skill it was seen at, and widened"] = function(t)
    local saved = {}
    t.eq(R.Seen(saved, "Test Belt", "optimal", 50), true)
    t.eq(saved, { ["Test Belt"] = { optimal = { lo = 50, hi = 50 } } })
    t.eq(R.Seen(saved, "Test Belt", "optimal", 53), true)
    t.eq(R.Seen(saved, "Test Belt", "optimal", 48), true)
    t.eq(saved["Test Belt"].optimal, { lo = 48, hi = 53 })
    t.eq(R.Seen(saved, "Test Belt", "optimal", 50), false, "nothing new")
end

tests["recipe colours: an easier colour seen cuts the harder one short, and the other way"] = function(t)
    local saved = { ["Test Belt"] = { optimal = { lo = 50, hi = 60 }, easy = { lo = 70, hi = 80 } } }
    R.Seen(saved, "Test Belt", "medium", 58)
    t.eq(saved["Test Belt"].optimal, { lo = 50, hi = 57 }, "sure ends below the skill it was maybe at")
    t.eq(saved["Test Belt"].medium, { lo = 58, hi = 58 })
    R.Seen(saved, "Test Belt", "medium", 72)
    t.eq(saved["Test Belt"].easy, { lo = 73, hi = 80 }, "easy starts above it")
    R.Seen(saved, "Test Belt", "trivial", 40)
    t.eq(saved["Test Belt"].optimal, nil, "all of it was at or above: dropped")
    t.eq(saved["Test Belt"].medium, nil)
    t.eq(saved["Test Belt"].easy, nil)
    t.eq(saved["Test Belt"].trivial, { lo = 40, hi = 40 })
end

tests["recipe colours: what is not a colour, a name or a skill is not saved"] = function(t)
    local saved = {}
    t.eq(R.Seen(saved, "Test Belt", "purple", 50), false)
    t.eq(R.Seen(saved, "", "optimal", 50), false)
    t.eq(R.Seen(saved, "Test Belt", "optimal", 50.5), false)
    t.eq(R.Seen(saved, "Test Belt", "optimal", nil), false)
    t.eq(R.Seen(nil, "Test Belt", "optimal", 50), false)
    t.eq(saved, {})
end

tests["recipe colours: a window read saves the learned rows only, and once"] = function(t)
    local s = store(nil)
    local rows = {
        { id = 1, name = "Test Belt", learned = true, difficulty = "optimal" },
        { id = 2, name = "Test Helm", learned = false, difficulty = "optimal" },
        { id = 3, name = "Test Nail", learned = true },
    }
    local r = R.Read(modern(50, rows), s)
    t.eq(r.ok, true)
    t.eq(r.seen, 1)
    t.eq(s.data.char[R.PATH], { ["Test Belt"] = { optimal = { lo = 50, hi = 50 } } })
    t.eq(s.sets, 1)
    r = R.Read(modern(50, rows), s)
    t.eq(r.changed, false)
    t.eq(s.sets, 1, "nothing new: nothing written")
end

tests["recipe colours: the classic window is read when the modern one does not answer"] = function(t)
    local s = store({ ["Old One"] = { medium = { lo = 10, hi = 12 } } })
    local client = { tradeSkillRows = function()
        return { name = "Blacksmithing", skill = 51, max = 75, rows = { { index = 1, name = "Test Belt", difficulty = "medium" } } }
    end }
    t.eq(R.Read(client, s).ok, true)
    t.eq(s.data.char[R.PATH], { ["Old One"] = { medium = { lo = 10, hi = 12 } },
        ["Test Belt"] = { medium = { lo = 51, hi = 51 } } }, "what was saved is kept")
end

tests["recipe colours: no window, or no store: nothing, and a reason"] = function(t)
    local s = store(nil)
    local r = R.Read({}, s)
    t.eq(r.ok, false)
    t.eq(r.reason, "no profession window answered")
    t.eq(s.sets, 0)
    r = R.Read(modern(50, { { id = 1, name = "Test Belt", learned = true, difficulty = "optimal" } }), nil)
    t.eq(r.ok, false)
end

return tests

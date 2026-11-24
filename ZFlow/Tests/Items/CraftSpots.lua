local _, ns = ...
-- Items/CraftSpots.lua and Items/ProfPlan.lua's P.Readings (lead section
-- 414). Made-up recipes and places. Offline only: not tested in game.
local tests = {}
local CS = ns.CraftSpots

local function store(char, account)
    local s = { char = char or {}, account = account or {}, writes = 0 }
    function s:get(scope, path) return self[scope][path] end
    function s:set(scope, path, v) self[scope][path] = v; self.writes = self.writes + 1; return true end
    return s
end

local function client(pos, names)
    return {
        position = function() return pos end,
        spellName = function(id) return (names or {})[id] end,
    }
end

local BOOK = {
    ["Test Belt"] = { id = 901, profession = "Blacksmithing" },
    ["Test Smelt"] = { id = 902, profession = "Mining" },
    ["Test Stew"] = { profession = "Cooking" },
    ["Test Shirt"] = { id = 904, profession = "Tailoring" },
}

tests["craft spots: the station a profession's craft needs"] = function(t)
    t.eq(CS.Kind("Blacksmithing"), "anvil")
    t.eq(CS.Kind("Mining"), "forge")
    t.eq(CS.Kind("Cooking"), "fire")
    t.eq(CS.Kind("Tailoring"), nil)
    t.eq(CS.Kind(nil), nil)
end

tests["craft spots: a recipe is found by its id, else by the spell's name"] = function(t)
    t.eq(CS.Recipe(BOOK, 901, nil), BOOK["Test Belt"])
    t.eq(CS.Recipe(BOOK, 5, "Test Stew"), BOOK["Test Stew"])
    t.eq(CS.Recipe(BOOK, 5, "Other"), nil)
    t.eq(CS.Recipe(nil, 901, "Test Belt"), nil)
end

tests["craft spots: a place by a saved one of the same kind is the same place"] = function(t)
    local list = {}
    t.eq(CS.Add(list, "anvil", { map = 1, x = 0.5, y = 0.5 }), true)
    t.eq(CS.Add(list, "anvil", { map = 1, x = 0.502, y = 0.499 }), false)
    t.eq(CS.Add(list, "forge", { map = 1, x = 0.502, y = 0.499 }), true, "another kind")
    t.eq(CS.Add(list, "anvil", { map = 2, x = 0.5, y = 0.5 }), true, "another map")
    t.eq(CS.Add(list, "anvil", { map = 1, x = 0.6, y = 0.5 }), true)
    t.eq(#list, 4)
    t.eq(CS.Add(list, "anvil", nil), false)
    t.eq(CS.Add(list, "anvil", { map = 1, x = 2, y = 0.5 }), false, "not a place on a map")
    t.eq(CS.Add(list, "anvil", { x = 0.1, y = 0.1 }), false)
    t.eq(#list, 4)
end

tests["craft spots: past the most kept, the oldest goes"] = function(t)
    local list = {}
    for i = 1, CS.MAX + 1 do CS.Add(list, "anvil", { map = i, x = 0.5, y = 0.5 }) end
    t.eq(#list, CS.MAX)
    t.eq(list[1].map, 2)
    t.eq(list[#list].map, CS.MAX + 1)
end

tests["craft spots: a craft of the player's saves where they stood"] = function(t)
    local s = store({ [CS.BOOK_PATH] = BOOK })
    local r = CS.Seen(client({ map = 7, x = 0.25, y = 0.75 }), s, 901)
    t.eq(r.ok, true); t.eq(r.kind, "anvil"); t.eq(r.changed, true)
    t.eq(s.account[CS.PATH], { { kind = "anvil", map = 7, x = 0.25, y = 0.75 } })
    t.eq(s.account[CS.KEY_PATH], nil, "never the list the key reads")
    r = CS.Seen(client({ map = 7, x = 0.25, y = 0.75 }), s, 901)
    t.eq(r.changed, false)
    t.eq(s.writes, 1, "nothing new, nothing written")
    r = CS.Seen(client({ map = 7, x = 0.25, y = 0.75 }, { [77] = "Test Stew" }), s, 77)
    t.eq(r.kind, "fire")
    t.eq(#s.account[CS.PATH], 2)
end

tests["craft spots: nothing is saved for another spell, a craft with no station, or no place"] = function(t)
    local s = store({ [CS.BOOK_PATH] = BOOK })
    local here = client({ map = 7, x = 0.25, y = 0.75 })
    t.eq(CS.Seen(here, s, 5).ok, false)
    t.eq(CS.Seen(here, s, 904).ok, false)
    t.eq(CS.Seen(client(nil), s, 901).changed, false)
    t.eq(CS.Seen(here, store(), 901).ok, false, "no recipe book saved")
    t.eq(CS.Seen(nil, nil, 901).ok, false)
    t.eq(s.account[CS.PATH], nil)
    t.eq(s.writes, 0)
end

tests["craft spots: a save that fails is said, not counted"] = function(t)
    local s = store({ [CS.BOOK_PATH] = BOOK })
    function s:set() return false end
    local r = CS.Seen(client({ map = 7, x = 0.25, y = 0.75 }), s, 901)
    t.eq(r.ok, false); t.eq(r.changed, false)
end

tests["craft spots: the key's stations and these, as one list of copies"] = function(t)
    local key = { { kind = "anvil", map = 1, x = 0.1, y = 0.1 }, "junk" }
    local s = store(nil, { [CS.KEY_PATH] = key, [CS.PATH] = { { kind = "forge", map = 1, x = 0.2, y = 0.2 } } })
    local all = CS.All(s)
    t.eq(all, { { kind = "anvil", map = 1, x = 0.1, y = 0.1 }, { kind = "forge", map = 1, x = 0.2, y = 0.2 } })
    all[1].x = 0.9
    t.eq(key[1].x, 0.1, "the saved list is not written")
    t.eq(CS.All(store()), {})
    t.eq(CS.All(nil), {})
end

tests["prof readings: the game's skill line wins once it is past the saved reading"] = function(t)
    local P = ns.ProfPlan
    local saved = { Blacksmithing = { skill = 50, max = 75 }, Cooking = { skill = 10, max = 75 }, Herbalism = { skill = 30, max = 75 } }
    local c = { skillRanks = function() return {
        Blacksmithing = { rank = 55, max = 75 },
        Cooking = { rank = 5, max = 75 },
        Mining = { rank = 60, max = 75 },
    } end }
    local got = P.Readings(c, saved)
    t.eq(got.Blacksmithing, { skill = 55, max = 75 })
    t.eq(got.Cooking, { skill = 10, max = 75 }, "a line behind the saved reading is not believed")
    t.eq(got.Herbalism, { skill = 30, max = 75 }, "no line: the saved reading")
    t.eq(got.Mining, nil, "only professions with a saved reading")
    t.eq(saved.Blacksmithing.skill, 50, "the saved table is not written")
    t.eq(P.Readings(nil, saved), saved)
    t.eq(P.Readings(c, nil), nil)
    t.eq(P.Readings({ skillRanks = function() error("no") end }, saved), saved)
end

return tests

local _, ns = ...

-- Tests for ZFlow/Gear/SetRecipes.lua (Flow-parity C-41). Each test makes
-- its own fake client; the reads are set on that instance only.

local SR = ns.GearSetRecipes
local tests = {}

local function link(id, name)
    return "|cffffffff|Hitem:" .. id .. "::::::::1:::::::|h[" .. name .. "]|h|r"
end

local POLE = link(6256, "Fishing Pole")
local STRONG = link(6365, "Strong Fishing Pole")
local AXE = link(1000, "Bronze Axe")
local SHIRT = link(2000, "Plain Shirt")

-- The game's item class and subclass: weapon 2, subclass 20 a fishing pole.
local INFO = {
    [6256] = { name = "Fishing Pole", classID = 2, subclassID = 20 },
    [6365] = { name = "Strong Fishing Pole", classID = 2, subclassID = 20 },
    [1000] = { name = "Bronze Axe", classID = 2, subclassID = 0 },
    [2000] = { name = "Plain Shirt", classID = 4, subclassID = 0 },
}

local function client(worn, bags, info)
    local c = ns.make.fakeClient()
    for slot, l in pairs(worn or {}) do c.setWorn(slot, l) end
    if worn == nil then c.setWornUnread(true) end
    if bags ~= nil then c.setBagItems(bags) end
    c.setItemInfo(info or INFO)
    c.setSkillRanks({ Fishing = { rank = 1, max = 75 } })
    return c
end

local function fishing() return SR.Get("fishing") end

tests["set recipes: the fishing recipe is the main hand, read by the game's item class"] = function(t)
    local r = fishing()
    t.ok(r ~= nil)
    t.eq(r.name, "Fishing")
    t.eq(r.slots, { 16 })
    t.eq(SR.Get("nope"), nil)
    t.eq(SR.IsPiece(r, 16, INFO[6256]), true)
    t.eq(SR.IsPiece(r, 16, INFO[1000]), false)
    t.eq(SR.IsPiece(r, 16, INFO[2000]), false)
    t.eq(SR.IsPiece(r, 16, nil), nil, "not read stays unknown")
    t.eq(SR.IsPiece(r, 16, { name = "x" }), nil, "no class read stays unknown")
    t.eq(SR.IsPiece(r, 1, INFO[6256]), false, "not a slot of the recipe")
end

tests["set recipes: the name alone never makes a pole (no hand-made list)"] = function(t)
    t.eq(SR.IsPiece(fishing(), 16, { name = "Fishing Pole" }), nil)
    t.eq(SR.IsPiece(fishing(), 16, { name = "Fishing Pole", classID = 4, subclassID = 20 }), false)
end

tests["set recipes: the pole you wear wins over one in your bags"] = function(t)
    local c = client({ [16] = POLE }, { { item = STRONG, count = 1 } })
    local f = SR.For(fishing(), c)
    t.ok(f ~= nil)
    t.eq(f.slots[16].item, POLE)
    t.eq(f.slots[16].where, "worn")
    t.eq(f.complete, true)
    t.eq(f.skill, true)
    local s = SR.Swaps(fishing(), c)
    t.eq(#s.rows, 0)
    t.eq(s.wearing, true)
    t.eq(s.lines, { "You wear your Fishing set already." })
end

tests["set recipes: else the first pole in your bags, over what you wear"] = function(t)
    local c = client({ [16] = AXE }, { { item = SHIRT, count = 1 }, { item = POLE, count = 1 }, { item = STRONG, count = 1 } })
    local f = SR.For(fishing(), c)
    t.eq(f.slots[16].item, POLE)
    t.eq(f.slots[16].where, "bags")
    local s = SR.Swaps(fishing(), c)
    t.eq(#s.rows, 1)
    t.eq(s.rows[1].slot, 16)
    t.eq(s.rows[1].put, POLE)
    t.eq(s.rows[1].off, AXE)
    t.eq(s.rows[1].where, "bags")
    t.eq(s.rows[1].reason, "Fishing Pole is in your bags; it goes on in place of Bronze Axe.")
    t.eq(s.wearing, false)
    t.eq(s.lines, { "Fishing Pole is in your bags; it goes on in place of Bronze Axe." })
end

tests["set recipes: an empty main hand gives off = nil"] = function(t)
    local c = client({}, { { item = POLE, count = 1 } })
    -- The main hand read and empty (the fake answers "not known" until a
    -- slot is set; MyBuddy lane B, lead section 867.3).
    c.setWorn(16, false)
    local s = SR.Swaps(fishing(), c)
    t.ok(type(s) == "table", "a swap list")
    if type(s) ~= "table" then return end
    t.eq(s.rows[1].off, nil)
    t.eq(s.rows[1].reason, "Fishing Pole is in your bags; it goes on where nothing is worn now.")
end

tests["set recipes: no pole anywhere, all read: the slot is missing, said plainly"] = function(t)
    local c = client({ [16] = AXE }, { { item = SHIRT, count = 1 } })
    local f = SR.For(fishing(), c)
    t.eq(f.slots[16], nil)
    t.eq(f.missing, { 16 })
    t.eq(f.complete, false)
    local s = SR.Swaps(fishing(), c)
    t.eq(#s.rows, 0)
    t.eq(s.wearing, false)
    t.eq(s.lines, { "You carry no fishing pole, worn or in your bags." })
end

tests["set recipes: what you wear not read is not known"] = function(t)
    local c = client(nil, { { item = POLE, count = 1 } })
    local f, why = SR.For(fishing(), c)
    t.eq(f, nil)
    t.eq(why, SR.CANT_READ_WORN)
    local s, why2 = SR.Swaps(fishing(), c)
    t.eq(s, nil)
    t.eq(why2, "Can't read what you wear right now, so the set is not known.")
end

tests["set recipes: bags not read is not known"] = function(t)
    local c = client({ [16] = AXE }, nil)
    local f, why = SR.For(fishing(), c)
    t.eq(f, nil)
    t.eq(why, "Can't read your bags right now, so the set is not known.")
end

tests["set recipes: the worn item not read is not known, even with a pole in the bags"] = function(t)
    local info = { [6256] = INFO[6256] }
    local c = client({ [16] = AXE }, { { item = POLE, count = 1 } }, info)
    local f, why = SR.For(fishing(), c)
    t.eq(f, nil)
    t.eq(why, "Some of your items are not read yet, so the set is not known.")
end

tests["set recipes: no pole found but a bag item not read is not known, never 'none'"] = function(t)
    local info = { [1000] = INFO[1000] }
    local c = client({ [16] = AXE }, { { item = SHIRT, count = 1 } }, info)
    local f, why = SR.For(fishing(), c)
    t.eq(f, nil)
    t.eq(why, SR.NOT_ALL_READ)
end

tests["set recipes: a pole is found though another bag item is not read"] = function(t)
    local info = { [1000] = INFO[1000], [6256] = INFO[6256] }
    local c = client({ [16] = AXE }, { { item = SHIRT, count = 1 }, { item = POLE, count = 1 } }, info)
    local f = SR.For(fishing(), c)
    t.eq(f.slots[16].item, POLE)
end

tests["set recipes: the skill is read, not guessed"] = function(t)
    local c = client({ [16] = POLE }, {})
    c.setSkillRanks({ Mining = { rank = 1, max = 75 } })
    t.eq(SR.For(fishing(), c).skill, false)
    c.setSkillRanks(nil)
    t.eq(SR.For(fishing(), c).skill, nil)
end

tests["set recipes: no recipe or no client answers nil with a reason"] = function(t)
    local f, why = SR.For(nil, client({}, {}))
    t.eq(f, nil)
    t.eq(why, SR.NO_RECIPE)
    local f2, why2 = SR.For(fishing(), nil)
    t.eq(f2, nil)
    t.eq(why2, SR.CANT_READ_WORN)
end

tests["set recipes: a read that raises is not known, never an error"] = function(t)
    local c = client({ [16] = POLE }, {})
    c.wornLinks = function() error("test") end
    local f, why = SR.For(fishing(), c)
    t.eq(f, nil)
    t.eq(why, SR.CANT_READ_WORN)
end

tests["set recipes: nothing acts: no equip, no sale, nothing moved"] = function(t)
    local c = client({ [16] = AXE }, { { item = POLE, count = 1 } })
    SR.For(fishing(), c)
    SR.Swaps(fishing(), c)
    t.eq(c.equipCalls, 0)
    t.eq(#c.equips, 0)
    t.eq(#c.soldSlots, 0)
    t.eq(#c.bagItems(), 1)
end

tests["set recipes: the lines are plain"] = function(t)
    for _, text in ipairs({ SR.CANT_READ_WORN, SR.CANT_READ_BAGS, SR.NOT_ALL_READ, SR.NO_RECIPE }) do
        t.ok(not text:lower():find("flow", 1, true), text)
        t.ok(not text:find("[|%c]"), text)
    end
end

return tests

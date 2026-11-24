local _, ns = ...
-- KNOW lane, slice 2, the ACTING part (C-56 "Place all on bar"), end to end
-- on the whole add-on loaded on a fake client. A spell is placed only on
-- the player's own click on the button, only out of a fight, and never for
-- a spell that is skipped, on a bar or under a key. Offline: the placing is
-- the fake client's (c.placedSpells), not the game's. Not tested in game.
local tests = {}

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local function names(class)
    local out = {}
    local pack
    if type(ns.Packs) == "table" then pack = ns.Packs[class] end
    for name in pairs(type(pack) == "table" and type(pack.spells) == "table" and pack.spells or {}) do
        out[#out + 1] = name
    end
    table.sort(out)
    return out
end

-- The first spell is on bar slot 1, the second and third are on no bar,
-- the fourth is under a key. opts: class, combat, noPlace (the client has
-- no placing call).
local function boot(opts)
    opts = opts or {}
    local class = opts.class or "DRUID"
    local all = names(class)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setClass(class); c.setFaction("Alliance"); c.setLevel(20); c.setCombat(opts.combat == true)
    local ids = {}
    for i, name in ipairs(all) do
        ids[name] = 1000 + i
        c.setSpellId(name, 1000 + i)
        c.setSpell(1000 + i, { known = i <= 4 })
    end
    c.setActionSpells({ [all[1]] = 1 })
    c.setBindings({ { "F5", "SPELL " .. all[4] } })
    if opts.noPlace then c.placeSpell = nil end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon, addon.problems:count(), { a = all[2], b = all[3], ids = ids }
end

local function open(c)
    c.slashes[ns.id.slash]("spells")
    return c.kitWindows().spells
end

local function part(rec, key)
    for _, p in ipairs(rec and rec.parts or {}) do
        if p.key == key then return p end
    end
    return nil
end

local function said(c, text)
    for _, line in ipairs(c.printed) do
        if tostring(line) == text then return true end
    end
    return false
end

for _, class in ipairs(CLASSES) do
    -- Red before the acting commit: the window has no such button
    -- (c.kitClick answers false) and nothing is placed (#c.placedSpells is 0).
    tests["know 2 acting: " .. class .. " Place all on bar places the spells on no bar, on the click only"] = function(t)
        local c, addon, base, s = boot({ class = class })
        local rec = open(c)
        t.eq(#c.placedSpells, 0, "opening the window places nothing")
        t.ok(part(rec, "placeAll") ~= nil, "the button")
        t.eq(c.kitClick("spells", "placeAll"), true, "pressed")
        t.eq(c.placedSpells, { { id = s.ids[s.a], slot = 2 }, { id = s.ids[s.b], slot = 3 } })
        t.ok(said(c, ns.id.title .. ": 2 spells placed on your bars."), "one line says so")
        rec = c.kitWindows().spells
        t.eq(part(rec, "row." .. s.a), nil, "placed: no row left")
        t.eq(part(rec, "placeAll"), nil, "nothing left to place: no button")
        t.eq(addon.problems:count(), base, "no new problem")
    end
end

tests["know 2 acting: in a fight nothing is placed, and a line says so"] = function(t)
    local c = boot()
    open(c)
    c.setCombat(true)
    t.eq(c.kitClick("spells", "placeAll"), true, "pressed")
    t.eq(#c.placedSpells, 0)
    t.ok(said(c, ns.id.title .. ": you are in a fight: nothing was placed. Press it again after the fight."), "said")
end

tests["know 2 acting: a skipped spell is never placed"] = function(t)
    local c, _, _, s = boot()
    open(c)
    c.kitClick("spells", "skip." .. s.a)
    t.eq(c.kitClick("spells", "placeAll"), true, "pressed")
    t.eq(c.placedSpells, { { id = s.ids[s.b], slot = 2 } })
    t.ok(said(c, ns.id.title .. ": 1 spell placed on your bars."), "one line")
end

tests["know 2 acting: nothing is placed at login, at a level-up or when a spell is learned"] = function(t)
    local c = boot()
    c.fire("PLAYER_LEVEL_UP", 21)
    c.learnSpell({ id = 4242, name = "Test Spell", rank = "Rank 1" })
    c.advance(5, 20)
    t.eq(#c.placedSpells, 0)
end

tests["know 2 acting: a client with no placing call has no button; one that refuses says how many are left"] = function(t)
    local c = boot({ noPlace = true })
    t.eq(part(open(c), "placeAll"), nil, "no button")
    local c2 = boot()
    open(c2)
    c2.setPlaceRefuse("refused")
    t.eq(c2.kitClick("spells", "placeAll"), true, "pressed")
    t.eq(#c2.placedSpells, 0)
    t.ok(said(c2, ns.id.title .. ": 2 could not be placed: no empty slot, or the game refused."), "said")
end

return tests

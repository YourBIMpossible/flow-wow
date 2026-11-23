local _, ns = ...
-- A weapon master learned when met (G16 follow-up), on the whole add-on
-- loaded on a fake client. Opening a trainer window whose list is weapon
-- skills saves roles.weaponMaster on that npc's learned place; the weapon
-- master step then has a place on that map and the arrow a needle. A class
-- trainer is not marked. Per lead section 236: the trainer read late, the
-- trainer read raising, a reload in the middle. Look only: nothing trains.
-- Made-up npcs, places and items. Not tested in game.
local tests = {}

local STR = "ITEM_MOD_STRENGTH_SHORT"
local SWORD = "item:3101"
local MASTER, CLASS = "Test Weaponsmith", "Test Drillmaster"

local function weaponTrainer()
    return { npc = MASTER, services = {
        { name = "Swords", state = "available" }, { name = "Daggers", state = "available" } } }
end

local function classTrainer()
    return { npc = CLASS, services = { { name = "Battle Shout", rank = "Rank 2", state = "available" } } }
end

-- opts: account, char (saved tables), before(c).
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setClass("WARRIOR")
    c.setLevel(10)
    c.setFaction("Horde")
    c.setPosition(1454, 0.4, 0.5)
    c.setItem(SWORD, { kind = "INVTYPE_WEAPON", stats = { [STR] = 5 }, classID = 2, subclassID = 7,
                       minLevel = 1, unmet = { "Swords" } })
    c.setWorn(16, false); c.setWorn(17, false)
    c.setDualWield(false)
    c.setWeaponSkills({ "Axes", "Defense" })
    if opts.before then opts.before(c) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function reload(c, before)
    return boot({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB), before = before })
end

local function npc(c, name)
    local a = c.saved(ns.id.accountDB)
    local l = type(a) == "table" and a.learned
    local p = type(l) == "table" and l.places
    local n = type(p) == "table" and p.npcs
    if type(n) ~= "table" then return nil end
    return n[name]
end

local function role(c, name)
    local e = npc(c, name)
    if type(e) ~= "table" or type(e.roles) ~= "table" then return nil end
    return e.roles.weaponMaster
end

local function step(addon)
    local api = addon.use("weaponMasterStep")
    if type(api) ~= "table" or type(api.Step) ~= "function" then return nil end
    return api.Step()
end

local function open(c, trainer)
    c.setTrainer(trainer)
    c.fire("TRAINER_SHOW")
end

tests["weapon master seen: a weapon trainer's window saves the role, and the step points there"] = function(t)
    local c, addon = boot()
    open(c, weaponTrainer())
    t.eq(role(c, MASTER), true, "saved with the role")
    local e = npc(c, MASTER)
    t.eq(e and e.map, 1454)
    t.eq(e and e.x, 0.4)
    c.setPosition(1454, 0.9, 0.9)
    c.showItemTooltip(SWORD)
    local s = step(addon)
    t.eq(s and s.place, { map = 1454, x = 0.4, y = 0.5 }, "a place on that map: a needle")
    t.eq(s and s.label, "Weapon master: " .. MASTER)
end

tests["weapon master seen: a class trainer is not marked"] = function(t)
    local c, addon = boot()
    open(c, classTrainer())
    t.eq(role(c, CLASS), nil)
    c.showItemTooltip(SWORD)
    t.eq(step(addon) and step(addon).place, nil, "words only still")
end

tests["weapon master seen: the trainer read late - nothing, then saved"] = function(t)
    local c = boot()
    open(c, nil)
    t.eq(role(c, MASTER), nil, "no answer: nothing written")
    open(c, weaponTrainer())
    t.eq(role(c, MASTER), true)
end

tests["weapon master seen: the trainer read raising writes nothing and stops nothing"] = function(t)
    local c, addon = boot({ before = function(x)
        x.trainerFails = true
        local real = x.trainer
        x.trainer = function(...)
            if x.trainerFails then error("trainer read failed (test)") end
            return real(...)
        end
    end })
    open(c, weaponTrainer())
    t.eq(role(c, MASTER), nil)
    t.eq((addon:ModuleState("weaponMasterSeen")), "started", "the module goes on")
    c.trainerFails = false
    open(c, weaponTrainer())
    t.eq(role(c, MASTER), true, "the read recovers")
end

tests["weapon master seen: a reload keeps it"] = function(t)
    local c = boot()
    open(c, weaponTrainer())
    local c2, addon2 = reload(c)
    t.eq(role(c2, MASTER), true)
    c2.showItemTooltip(SWORD)
    local s = step(addon2)
    t.eq(s and s.place, { map = 1454, x = 0.4, y = 0.5 })
end

return tests

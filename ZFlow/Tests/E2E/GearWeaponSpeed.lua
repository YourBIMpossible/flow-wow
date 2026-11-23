local _, ns = ...
-- The weapon speed line with the class's preference (G15, lead section 275
-- item 3), on the whole add-on loaded on a fake client with the real class
-- packs, through the real tooltip entry point (c.showItemTooltip). The
-- paladin pack's weaponSpeed (ported from legacy Classes/Paladin/Data.lua:
-- 91-96) says each role's preferred speed and why; the tooltip names the
-- chosen role's, or every role's when none is chosen. Per lead section 236:
-- item data late, the gear read raising then recovering, a reload.
-- Regression: the roll hint is not made Unknown by the line. Every read
-- the verdict needs is set (class, level, weapon skills, dual wield, the
-- worn main hand 16 and off hand 17, the item's kind, stats, class,
-- subclass, level, the game's own marks and speed). Made-up items. Not
-- tested in game.
local tests = {}

local STR = "ITEM_MOD_STRENGTH_SHORT"
local MACE, LATE = "item:4201", "item:4202"
local DPS_WHY = "Seal and Judgement damage scales with damage per swing"
local FOR_DPS = "Speed 3.60 (slow); good for dps (" .. DPS_WHY .. ")"
local FOR_ALL = FOR_DPS .. "; heal prefers medium (speed barely matters; stats do)"
    .. "; tank prefers medium (steady swings for steady threat)"

local function mace()
    return { kind = "INVTYPE_2HWEAPON", stats = { [STR] = 12 }, classID = 2, subclassID = 5, minLevel = 1,
             unmet = {}, speed = 3.6 }
end

-- opts: role (spec.role saved), account, char (saved tables), prepare(c).
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    local char = opts.char or {}
    if opts.role then char.settings = { spec = { role = opts.role } } end
    c.setSaved(ns.id.charDB, char)
    c.setClass("PALADIN")
    c.setLevel(20)
    c.setDualWield(false)
    c.setWeaponSkills({ "Maces", "Two-Handed Maces", "Defense" })
    c.setItem(MACE, mace())
    c.setWorn(16, false)
    c.setWorn(17, false)
    if opts.prepare then opts.prepare(c) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function hover(c, link)
    local out = {}
    for _, a in ipairs(c.showItemTooltip(link)) do out[#out + 1] = a.text end
    return out
end

local function at(list, text)
    for i = 1, #list do
        if list[i] == text then return i end
    end
    return nil
end

tests["weapon speed e2e: the chosen role's preference and why, after the verdict"] = function(t)
    local c = boot({ role = "dps" })
    local lines = hover(c, MACE)
    local i = at(lines, FOR_DPS)
    t.ok(i ~= nil, "the dps speed line: " .. table.concat(lines, " | "))
    t.ok(i ~= nil and i > 1, "the verdict stays first")
    t.eq(at(lines, "Speed 3.60 (slow)"), nil, "not the bare line")
end

tests["weapon speed e2e: no role chosen - every role's preference"] = function(t)
    local c = boot()
    local lines = hover(c, MACE)
    t.ok(at(lines, FOR_ALL) ~= nil, "every role: " .. table.concat(lines, " | "))
end

tests["weapon speed e2e: item data late - the line appears once it is read"] = function(t)
    local c = boot({ role = "dps" })
    t.eq(at(hover(c, LATE), FOR_DPS), nil, "nothing while the item is not loaded")
    c.setItem(LATE, mace())
    local lines = hover(c, LATE)
    t.ok(at(lines, FOR_DPS) ~= nil, "once loaded: " .. table.concat(lines, " | "))
end

tests["weapon speed e2e: the gear read raising, then recovering"] = function(t)
    local c, addon = boot({ role = "dps" })
    local before = addon.gearTooltip.errors()
    local real = c.gear
    c.gear = function() error("gear read failed") end
    t.eq(at(hover(c, MACE), FOR_DPS), nil, "nothing added while the read raises")
    t.eq(addon.gearTooltip.errors(), before + 1, "counted")
    c.gear = real
    local lines = hover(c, MACE)
    t.ok(at(lines, FOR_DPS) ~= nil, "back once the read works: " .. table.concat(lines, " | "))
end

tests["weapon speed e2e: a reload keeps the chosen role's line"] = function(t)
    local c = boot({ role = "dps" })
    t.ok(at(hover(c, MACE), FOR_DPS) ~= nil, "before")
    local again = boot({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    local lines = hover(again, MACE)
    t.ok(at(lines, FOR_DPS) ~= nil, "after the reload: " .. table.concat(lines, " | "))
end

-- Regression: the line is "info", so the roll hint is never "Unknown" for it.
tests["weapon speed e2e: the roll hint is not made Unknown by the line"] = function(t)
    local c = boot({ role = "dps" })
    local shown = c.offerRoll(3, MACE)
    t.eq(#shown, 1, "one hint")
    t.eq(shown[1] and shown[1].text, "Upgrade", "an empty main hand: an upgrade")
end

return tests

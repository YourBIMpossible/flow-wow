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
--
-- Lead section 280: the same for every class. Each pack's weaponSpeed says
-- each role's speed, or that speed does not matter for it, and why; one
-- boot per class and role below hovers a weapon of that class and takes a
-- roll on it, with the ranged slot 18 read and empty too.
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

-- opts: role (spec.role saved), account, char (saved tables), prepare(c);
-- class (default the paladin), skills (the weapon skill lines known) and
-- items ({ [link] = item }) for another class.
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    local char = opts.char or {}
    if opts.role then char.settings = { spec = { role = opts.role } } end
    c.setSaved(ns.id.charDB, char)
    c.setClass(opts.class or "PALADIN")
    c.setLevel(20)
    c.setDualWield(false)
    c.setWeaponSkills(opts.skills or { "Maces", "Two-Handed Maces", "Defense" })
    c.setItem(MACE, mace())
    for link, item in pairs(opts.items or {}) do c.setItem(link, item) end
    c.setWorn(16, false)
    c.setWorn(17, false)
    c.setWorn(18, false)
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

-- Every class (lead section 280) ---------------------------------------------

local STA = "ITEM_MOD_STAMINA_SHORT"   -- every role of every pack has a weight for it
local THEIRS, SECOND = "item:4211", "item:4212"

-- A weapon by equip location, weapon subclass and speed.
local function arm(kind, subclassID, speed)
    return { kind = kind, stats = { [STA] = 12 }, classID = 2, subclassID = subclassID, minLevel = 1,
             unmet = {}, speed = speed }
end

local NO_SWING = "healing spells do not use the weapon's swing"
local SPELLS = "spells do the damage, not the weapon's swing"
local CAT = "in Cat Form your paws strike at the form's own speed, not the weapon's"
local BEAR = "in Bear Form your paws strike at the form's own speed, not the weapon's"
local function any(role, why) return "speed does not matter for " .. role .. " (stats do): " .. why end

-- class, the role chosen, the skill lines known, the weapon hovered and
-- rolled on (THEIRS) with its whole speed line, and a second weapon with
-- its line where the role has a part for another slot.
local CASES = {
    { class = "WARRIOR", role = "dps", skills = { "Two-Handed Swords", "Daggers", "Defense" },
      item = arm("INVTYPE_2HWEAPON", 8, 3.6),
      line = "Speed 3.60 (slow); good for dps (Mortal Strike, Whirlwind and Overpower hit for weapon damage,"
          .. " so a slow weapon hits harder for the same rage)",
      second = arm("INVTYPE_WEAPONOFFHAND", 15, 1.5),
      secondLine = "Speed 1.50 (fast); good for dps (more off hand swings bring rage more often)" },
    { class = "WARRIOR", role = "tank", skills = { "Swords", "Defense" },
      item = arm("INVTYPE_WEAPON", 7, 1.8),
      line = "Speed 1.80 (fast); good for tank (more swings to turn into Heroic Strike, so threat comes steadily)" },
    { class = "ROGUE", role = "dps", skills = { "Swords", "Daggers", "Defense" },
      item = arm("INVTYPE_WEAPON", 7, 2.8),
      line = "Speed 2.80 (medium); dps prefers slow (Sinister Strike and Backstab hit for weapon damage,"
          .. " so a slow main hand hits harder for the same energy)",
      second = arm("INVTYPE_WEAPONOFFHAND", 15, 1.5),
      secondLine = "Speed 1.50 (fast); good for dps"
          .. " (a fast off hand swings more often, so its poison lands more often)" },
    { class = "SHAMAN", role = "dps", skills = { "Two-Handed Maces", "Defense" },
      item = arm("INVTYPE_2HWEAPON", 5, 3.6),
      line = "Speed 3.60 (slow); good for dps (Windfury Weapon and Stormstrike hit for weapon damage,"
          .. " so a slow weapon makes each extra swing bigger)" },
    { class = "SHAMAN", role = "heal", skills = { "Two-Handed Maces", "Defense" },
      item = arm("INVTYPE_2HWEAPON", 5, 3.6),
      line = "Speed 3.60 (slow); " .. any("heal", NO_SWING) },
    { class = "HUNTER", role = "dps", skills = { "Bows", "Two-Handed Axes", "Defense" },
      item = arm("INVTYPE_RANGED", 2, 3.4),
      line = "Speed 3.40 (slow); good for dps (Aimed Shot and Multi-Shot hit for weapon damage,"
          .. " so a slow bow or gun hits harder per shot)",
      second = arm("INVTYPE_2HWEAPON", 1, 3.6),
      secondLine = "Speed 3.60 (slow); "
          .. any("dps", "shots do the damage; a melee weapon is carried for its stats") },
    { class = "DRUID", role = "dps", skills = { "Staves", "Defense" },
      item = arm("INVTYPE_2HWEAPON", 10, 3.0), line = "Speed 3.00 (medium); " .. any("dps", CAT) },
    { class = "DRUID", role = "tank", skills = { "Staves", "Defense" },
      item = arm("INVTYPE_2HWEAPON", 10, 3.0), line = "Speed 3.00 (medium); " .. any("tank", BEAR) },
    { class = "DRUID", role = "heal", skills = { "Staves", "Defense" },
      item = arm("INVTYPE_2HWEAPON", 10, 3.0), line = "Speed 3.00 (medium); " .. any("heal", NO_SWING) },
    { class = "MAGE", role = "dps", skills = { "Staves", "Defense" },
      item = arm("INVTYPE_2HWEAPON", 10, 3.0), line = "Speed 3.00 (medium); " .. any("dps", SPELLS) },
    { class = "PRIEST", role = "dps", skills = { "Staves", "Defense" },
      item = arm("INVTYPE_2HWEAPON", 10, 3.0), line = "Speed 3.00 (medium); " .. any("dps", SPELLS) },
    { class = "PRIEST", role = "heal", skills = { "Staves", "Defense" },
      item = arm("INVTYPE_2HWEAPON", 10, 3.0), line = "Speed 3.00 (medium); " .. any("heal", NO_SWING) },
    { class = "WARLOCK", role = "dps", skills = { "Staves", "Defense" },
      item = arm("INVTYPE_2HWEAPON", 10, 3.0), line = "Speed 3.00 (medium); " .. any("dps", SPELLS) },
}

for _, case in ipairs(CASES) do
    local who = case.class .. " " .. case.role
    tests["weapon speed e2e: " .. who .. " - the role's speed line and reason; the roll hint gives its word"] = function(t)
        local c = boot({ class = case.class, role = case.role, skills = case.skills,
                         items = { [THEIRS] = case.item, [SECOND] = case.second } })
        local lines = hover(c, THEIRS)
        local i = at(lines, case.line)
        t.ok(i ~= nil, who .. ": the speed line: " .. table.concat(lines, " | "))
        t.ok(i ~= nil and i > 1, who .. ": the verdict stays first")
        if case.second then
            lines = hover(c, SECOND)
            t.ok(at(lines, case.secondLine) ~= nil, who .. ": the second weapon: " .. table.concat(lines, " | "))
        end
        local shown = c.offerRoll(3, THEIRS)
        t.eq(#shown, 1, who .. ": one hint")
        t.eq(shown[1] and shown[1].text, "Upgrade", who .. ": empty hands and ranged slot: an upgrade")
    end
end

-- No role chosen: every role's entry, in name order.
tests["weapon speed e2e: a druid with no role chosen - every role's entry"] = function(t)
    local c = boot({ class = "DRUID", skills = { "Staves", "Defense" },
                     items = { [THEIRS] = arm("INVTYPE_2HWEAPON", 10, 3.0) } })
    local lines = hover(c, THEIRS)
    local all = "Speed 3.00 (medium); " .. any("dps", CAT) .. "; " .. any("heal", NO_SWING) .. "; " .. any("tank", BEAR)
    t.ok(at(lines, all) ~= nil, "every role: " .. table.concat(lines, " | "))
end

return tests

-- Lane W3 self-tests: role and talents, class behaviour, consumables.
-- Same harness as Modules/Tests.lua (ns:Register("test", ...)); they never
-- change your settings (anything they touch is put back).

local _, ns = ...

-- Puts obj[key] = value for the length of fn, then back (Flow's own tables only).
local function with(obj, key, value, fn)
    local old = obj[key]
    obj[key] = value
    local ok, err = pcall(fn)
    obj[key] = old
    if not ok then error(err, 0) end
end

ns:Register("test", "rotation: a class with no rotation gets the class-agnostic rules", function(t)
    -- F-063: Choose returned nil before healing, recovery, interrupts and dispels.
    local E = ns.rotation
    local fallback = ns:Get("rotation", E.NO_CLASS)
    t:ok(fallback and fallback.noClass, "the class-agnostic rules are registered")
    t:eq(fallback and #fallback.priority, 0, "with no class rules")
    with(E, "Definition", function() return nil end, function()
        t:eq(E:Rules(), fallback, "no class rotation: the class-agnostic rules")
    end)
    with(E, "Definition", function() return { priority = {} } end, function()
        t:ok(not E:Rules().noClass, "a class with a rotation: its own rules")
    end)
end)

ns:Register("test", "rotation: a class with no rotation still gets a potion when hurt in a fight", function(t)
    local E = ns.rotation
    local fallback = ns:Get("rotation", E.NO_CLASS)
    with(E, "Definition", function() return nil end, function()
        local seen
        local ctx = { inCombat = true, hostile = false, fightType = "normal" }
        with(E, "Context", function() return ctx end, function()
            with(E, "BreakFree", function() return nil end, function()
                with(E, "HealStep", function(_, _, def) seen = def return { label = "Healing Potion", kind = "emergency" } end, function()
                    local s
                    with(E, "lastCtx", E.lastCtx, function()
                        with(E, "lastEarlyLog", E.lastEarlyLog, function() s = E:Choose() end)
                    end)
                    t:eq(s and s.label, "Healing Potion", "no class rotation, hurt in a fight: the potion is still suggested")
                    t:eq(seen, fallback, "healing is asked with the class-agnostic rules")
                end)
            end)
        end)
    end)
end)

ns:Register("test", "spec: every druid tree gives a role (Balance, Feral Combat, Restoration)", function(t)
    -- F-059: #33 matched the tree name to a spec name, and only Restoration has one.
    local druid = ns:Get("class", "DRUID")
    local specs, roles = druid and druid.specs, ns.TREE_ROLES.DRUID
    t:ok(specs ~= nil, "druid class data is registered")
    local function tr(b, f, r)
        local names = ns.TALENT_TREES.DRUID
        return { { name = names[1], points = b }, { name = names[2], points = f }, { name = names[3], points = r } }
    end
    t:eq(ns.RoleFromTrees(specs, tr(11, 2, 0), roles), "dps", "most points in Balance: caster dps")
    t:eq(ns.RoleFromTrees(specs, tr(0, 12, 3), roles), "dps", "most in Feral Combat: melee dps (cat), never tank by talents")
    t:eq(ns.RoleFromTrees(specs, tr(1, 0, 9), roles), "heal", "most in Restoration: heal")
    t:eq(ns.RoleFromTrees(specs, tr(5, 5, 0), roles), nil, "a tie: nothing (the class's role)")
    t:eq(ns.RoleFromTrees(specs, tr(0, 0, 0), roles), nil, "no points yet: nothing")
    t:eq(ns.TREE_ROLES.PALADIN, nil, "paladin trees are all named after a spec: no extra map")
end)

ns:Register("test", "spec: a druid's chosen role beats Feral talents, which beat the class role", function(t)
    local druid = ns:Get("class", "DRUID")
    local feral = { { name = "Balance", points = 0 }, { name = "Feral Combat", points = 14 },
                    { name = "Restoration", points = 0 } }
    local talent = ns.RoleFromTrees(druid and druid.specs, feral, ns.TREE_ROLES.DRUID)
    local function both(chosen, tal) local r, s = ns.ResolveRole(chosen, tal, "dps") return r .. "/" .. s end
    t:eq(both("tank", talent), "tank/chosen", "chose Tank, Feral talents: Tank (Bear Form)")
    t:eq(both("heal", talent), "heal/chosen", "chose Heal, Feral talents: Heal")
    t:eq(both(nil, talent), "dps/talents", "Auto, Feral talents: DPS from talents")
    t:eq(both(nil, nil), "dps/class", "Auto, no talents: the class's role")
    t:ok(not ns.DruidWantsBear(both(nil, talent):match("^(%a+)"), true, false), "Auto Feral: no Bear Form asked for")
end)

ns:Register("test", "spec: /flow spec always says where your role came from", function(t)
    -- F-058: the role showed only when it differed from the recommended one.
    t:eq(ns.RoleSourceWords("chosen"), "your choice", "a role you chose")
    t:eq(ns.RoleSourceWords("talents"), "your talents", "a role from your talents")
    t:eq(ns.RoleSourceWords("class"), "your class's usual role", "no choice, no talents")
    t:eq(ns.RoleSourceWords(nil), "your class's usual role", "nothing known: the class's role")
end)

ns:Register("test", "rotation: dispel help follows your effective role and your form", function(t)
    -- F-077: a resto druid at the default dps role got none in a fight; a cat gets none (can't cast it).
    local E = ns.rotation
    local caster = true
    local def = { dispels = { canCast = function() return caster end,
                              { spell = "Remove Curse", types = { Curse = true } } } }
    local friend = { { unit = "party1", name = "Mo", kind = "dps" } }
    local function cursed(u) return u == "party1" and { Curse = "Curse of Weakness" } or {} end
    local s
    with(E, "GroupUnits", function() return { friend[1] } end, function()
        with(E, "Knows", function() return true end, function()
            with(E, "Ready", function() return true end, function()
                s = E:Dispel({ inCombat = true, role = "heal" }, def, 1, cursed)
                t:eq(s and s.spell, "Remove Curse", "healing (from your talents or your choice), a fight: your group's curse")
                t:eq(E:Dispel({ inCombat = true, role = "dps" }, def, 1, cursed), nil,
                    "dps in a fight: your attacks stay on the icon")
                s = E:Dispel({ inCombat = false, role = "dps" }, def, 1, cursed)
                t:eq(s and s.unit, "party1", "out of a fight: any role")
                caster = false
                t:eq(E:Dispel({ inCombat = false, role = "heal" }, def, 1, cursed), nil,
                    "in Cat or Bear Form: nothing (it can't be cast there)")
            end)
        end)
    end)
end)

ns:Register("test", "buff items: at a dungeon's entrance you get ready for the run", function(t)
    -- F-069: buff items came up only at kill / loot steps or just after a fight.
    local BI = ns.buffItems
    if not (BI and BI.Killing) then t:ok(false, "BuffItems.lua not loaded") return end
    local entrance = { key = "dungeon:dm:", kind = "waypoint" }
    local far = 1e9   -- long after any fight
    t:ok(BI.Killing({ goal = entrance, at = true }, far), "at the entrance: buff up")
    t:ok(not BI.Killing({ goal = entrance, at = false }, far), "still on the way there: not yet (it shows faded)")
    t:ok(not BI.Killing({ goal = { key = "user:wp", kind = "waypoint" }, at = true }, far), "any other waypoint: no")
    t:ok(BI.Killing({ goal = { key = "q:1", kind = "kill" }, at = true }, far), "a kill step: as before")
end)

ns:Register("test", "talents: a build for another role says so", function(t)
    -- F-060: "/flow spec heal" still got the Feral build, with nothing said.
    local T = ns.talents
    local druid = ns:Get("talentBuild", "DRUID")
    t:ok(T.BuildMismatch(druid, "heal"), "druid healing, Feral build: a mismatch")
    t:ok(not T.BuildMismatch(druid, "dps"), "druid dps: the build's own role")
    t:ok(not T.BuildMismatch(druid, "tank"), "druid tank: the Feral tree serves Bear too")
    t:ok(not T.BuildMismatch(nil, "heal"), "no build: nothing to say")
    t:ok(not T.BuildMismatch(druid, nil), "no role: nothing to say")
    local bld = { name = "Test", role = "dps", trees = { "A" }, order = { { "Claws", 1 } } }
    local nodes = { { name = "Claws", x = 100, y = 10, rank = 0, max = 1 } }
    t:ok(T.View(nodes, 0, bld, 10, "heal").what:find("no build for your role", 1, true) ~= nil,
        "the view says the build is for another role")
    t:ok(T.View(nodes, 0, bld, 10, "dps").what:find("no build for your role", 1, true) == nil,
        "and says nothing when it fits")
end)

ns:Register("test", "paladin: the class list has no guide-reported Forever rows; the trainer teaches them", function(t)
    -- prov-guides-2: Holy Strike, Seal of Fury, Consecration and Blessing of
    -- Kings had levels reported by guides and never checked in the game.
    local removed = { "Holy Strike", "Seal of Fury", "Consecration", "Blessing of Kings" }
    local list = ns:Get("classSpells", "PALADIN") or {}
    t:ok(#list > 10, "the paladin list is still there")
    local row = {}
    for _, s in ipairs(list) do
        row[s.spell] = s
        t:ok(not (s.note and s.note:find("Forever", 1, true)), s.spell .. ": no row marked as a Forever change")
    end
    local set = ns:ClassSpellSet("PALADIN")
    for _, name in ipairs(removed) do
        t:eq(row[name], nil, name .. ": no row, so no level is claimed for it")
        t:ok(set[name], name .. ": still a paladin's spell (the rotation casts it)")
    end
    t:ok(not set.Attack and not set["Auto Attack"], "Attack is still nobody's")
    -- A trainer's level for a spell with no row adds nothing to the list and moves no other row.
    local copy = {}
    for i, s in ipairs(list) do copy[i] = { spell = s.spell, level = s.listLevel or s.level, quest = s.quest, note = s.note } end
    local changed = ns.facts.FixLevels(copy, function(name) if name == "Holy Strike" then return 6, "yours" end end)
    t:eq(#changed, 0, "a learned level for Holy Strike changes no row of the list")
    t:eq(#copy, #list, "and adds none: the trainer's own line is what gets advised")
    -- The trainer's line for it: a new spell, not a "stronger rank".
    local T = ns.trainerAdvice
    t:eq(T.Improves(nil, false)[1], "New spell", "no row, not known: a new spell")
    t:eq(T.Improves(nil, true)[1], "Stronger rank", "no row, known: a later rank")
    t:eq(T.Improves({ improves = { "DPS" } }, false)[1], "DPS", "a row's own words win")
end)

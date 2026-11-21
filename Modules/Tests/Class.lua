-- Lane W3 self-tests: role and talents, class behaviour, consumables.
-- Same harness as Modules/Tests.lua (ns:Register("test", ...)); they never
-- change your settings (anything they touch is put back).

local _, ns = ...

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

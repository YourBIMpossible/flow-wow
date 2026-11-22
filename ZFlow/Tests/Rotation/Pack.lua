local _, ns = ...

-- ns.PackCheck: what it accepts and each thing it reports.

local function good()
    return {
        provenance = { author = "Flow", date = "2026-11-21", method = "written for the test", facts = "none" },
        roles = { dps = { name = "Test", evidence = "first guess" } },
        resources = { { name = "Mana", evidence = "first guess" } },
        maintain = { { spell = "Shield", seconds = 30, evidence = "first guess" } },
        lists = { default = { { spell = "Bolt", target = true, evidence = "first guess" } } },
        groups = {},
        heals = { self = { "Mend" }, hots = {}, lingers = {} },
        interrupts = { { spell = "Kick", evidence = "first guess" } },
        breakers = { { spell = "Slip", types = { ROOT = true }, evidence = "first guess" } },
        dispels = { { spell = "Cleanse", types = { Poison = true }, evidence = "first guess" } },
        keys = { none = { key = "Bolt", ctrl = { "Kick" } } },
        weights = { dps = { evidence = "first guess", values = { STAT = 1 } } },
        proficiency = { evidence = "first guess" },
        spells = {
            Bolt = { evidence = "first guess" }, Mend = { evidence = "first guess" }, Kick = { evidence = "first guess" },
            Slip = { evidence = "first guess" }, Cleanse = { evidence = "first guess" }, Shield = { evidence = "observed" },
        },
        talentBuilds = {},
        options = {},
    }
end

local function has(problems, text)
    for _, p in ipairs(problems) do
        if string.find(p, text, 1, true) then return true end
    end
    return false
end

return {
    ["a complete pack passes"] = function(t)
        local ok, problems = ns.PackCheck(good())
        t.eq(table.concat(problems, "; "), "", "no problems")
        t.eq(ok, true, "ok")
    end,

    ["not a table fails"] = function(t)
        local ok, problems = ns.PackCheck(nil)
        t.eq(ok, false, "nil")
        t.eq(#problems, 1, "one problem")
        ok = ns.PackCheck("druid")
        t.eq(ok, false, "a string")
    end,

    ["every missing key is reported"] = function(t)
        for _, key in ipairs(ns.Pack.KEYS) do
            if key ~= "provenance" then
                local pack = good()
                pack[key] = nil
                local ok, problems = ns.PackCheck(pack)
                t.eq(ok, false, key .. " missing fails")
                t.ok(has(problems, "missing key \"" .. key .. "\""), key .. " named")
            end
        end
        local ok, problems = ns.PackCheck({})
        t.eq(ok, false, "an empty pack")
        t.eq(#problems, #ns.Pack.KEYS, "one problem per key, the provenance block included")
    end,

    ["a missing provenance block is reported"] = function(t)
        local pack = good()
        pack.provenance = nil
        local ok, problems = ns.PackCheck(pack)
        t.eq(ok, false, "fails")
        t.ok(has(problems, "missing provenance block"), "named")
        pack = good()
        pack.provenance.method = nil
        ok, problems = ns.PackCheck(pack)
        t.eq(ok, false, "a block without its method fails")
        t.ok(has(problems, "no method"), "the part named")
    end,

    ["an unknown required spell is reported wherever it is named"] = function(t)
        local places = {
            function(p) p.lists.default[1].spell = "Nope" end,
            function(p) p.lists.aoe = { { spell = "Nope", evidence = "first guess" } } end,
            function(p) p.maintain[1].spell = "Nope" end,
            function(p) p.heals.self[1] = "Nope" end,
            function(p) p.heals.hots[1] = "Nope" end,
            function(p) p.heals.lingers.Nope = 10 end,
            function(p) p.interrupts[1].spell = "Nope" end,
            function(p) p.breakers[1].spell = "Nope" end,
            function(p) p.dispels[1].spell = "Nope" end,
            function(p) p.keys.none.key = "Nope" end,
            function(p) p.keys.none.ctrl[1] = "Nope" end,
            function(p) p.groups[1] = { spell = "Nope", evidence = "first guess" } end,
        }
        for i, change in ipairs(places) do
            local pack = good()
            change(pack)
            local ok, problems = ns.PackCheck(pack)
            t.eq(ok, false, "place " .. i .. " fails")
            t.ok(has(problems, "unknown required spell \"Nope\""), "place " .. i .. " names the spell")
        end
    end,

    ["a rule without a spell name is reported"] = function(t)
        local pack = good()
        pack.lists.default[1].spell = nil
        local ok, problems = ns.PackCheck(pack)
        t.eq(ok, false, "fails")
        t.ok(has(problems, "spell is not a name"), "named")
    end,

    ["evidence: missing, unknown and authored without a note"] = function(t)
        local pack = good()
        pack.spells.Bolt.evidence = nil
        local ok, problems = ns.PackCheck(pack)
        t.eq(ok, false, "a spell with no evidence class fails")
        t.ok(has(problems, "no evidence class"), "named")

        pack = good()
        pack.lists.default[1].evidence = "wowhead"
        ok, problems = ns.PackCheck(pack)
        t.eq(ok, false, "a class that is not one of the three fails")
        t.ok(has(problems, "unknown evidence class"), "named")

        pack = good()
        pack.lists.default[1].evidence = "authored"
        ok, problems = ns.PackCheck(pack)
        t.eq(ok, false, "authored without a note fails")
        t.ok(has(problems, "authored without a provenance note"), "named")
        pack.lists.default[1].provenance = "Authored by Flow for the test."
        ok = ns.PackCheck(pack)
        t.eq(ok, true, "with the note it passes")
    end,

    ["a group dispel entry is reported"] = function(t)
        local pack = good()
        pack.dispels[1].group = true
        local ok, problems = ns.PackCheck(pack)
        t.eq(ok, false, "group = true fails")
        t.ok(has(problems, "a group dispel entry"), "named")
        pack = good()
        pack.dispels[1].unit = "party1"
        ok = ns.PackCheck(pack)
        t.eq(ok, false, "a unit other than yourself fails")
    end,

    ["a when that is not a function is reported"] = function(t)
        local pack = good()
        pack.lists.default[1].when = true
        local ok, problems = ns.PackCheck(pack)
        t.eq(ok, false, "fails")
        t.ok(has(problems, "when is not a function"), "named")
    end,

    ["problems come back sorted, and the pack is not changed"] = function(t)
        local pack = good()
        pack.roles = nil
        pack.options = nil
        pack.keys = nil
        local _, problems = ns.PackCheck(pack)
        local sorted = {}
        for i, p in ipairs(problems) do sorted[i] = p end
        table.sort(sorted)
        t.eq(table.concat(problems, "|"), table.concat(sorted, "|"), "sorted")
        t.eq(pack.lists.default[1].spell, "Bolt", "the pack is as it was")
    end,
}

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
        weaponSpeed = { evidence = "first guess", dps = { prefer = "slow", why = "a reason in words" } },
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
    -- Section 242, DRUID-3: a talent in a build may carry the reason it is
    -- taken; a reason given must be words.
    ["a talent reason that is not words is reported"] = function(t)
        local pack = good()
        pack.talentBuilds = { { name = "Test build", role = "dps", evidence = "first guess", order = {
            { "Good Talent", 1, why = "A reason in words." },
            { "Empty Reason", 1, why = "" },
            { "Number Reason", 2, why = 5 },
            { "No Reason", 3 },
        } } }
        local ok, problems = ns.PackCheck(pack)
        t.eq(ok, false, "fails")
        t.ok(has(problems, "talentBuilds[1].order[2]: the reason is not words"), "an empty reason named")
        t.ok(has(problems, "talentBuilds[1].order[3]: the reason is not words"), "a number reason named")
        t.ok(not has(problems, "order[1]"), "a reason in words passes")
        t.ok(not has(problems, "order[4]"), "no reason is allowed")
    end,

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

    -- Lead section 280: every class says which weapon speed each of its
    -- roles likes, or that speed does not matter ("any"), and why.
    ["weaponSpeed is a required key"] = function(t)
        local listed = false
        for _, key in ipairs(ns.Pack.KEYS) do
            if key == "weaponSpeed" then listed = true end
        end
        t.eq(listed, true, "in ns.Pack.KEYS")
        local pack = good()
        pack.weaponSpeed = nil
        local ok, problems = ns.PackCheck(pack)
        t.eq(ok, false, "a pack without it fails")
        t.ok(has(problems, "missing key \"weaponSpeed\""), "named")
    end,

    ["a role with weights and no weapon speed entry is reported"] = function(t)
        local pack = good()
        pack.weights.tank = { evidence = "first guess", values = { STAT = 1 } }
        local ok, problems = ns.PackCheck(pack)
        t.eq(ok, false, "fails")
        t.ok(has(problems, "weaponSpeed.tank: no entry"), "the role named: " .. table.concat(problems, "; "))
        t.ok(not has(problems, "weaponSpeed.dps"), "the role with an entry passes")
    end,

    ["a weapon speed entry without a speed, a reason or an evidence class is reported"] = function(t)
        local pack = good()
        pack.weaponSpeed.dps.prefer = "heavy"
        local ok, problems = ns.PackCheck(pack)
        t.eq(ok, false, "a speed that is none of slow, medium, fast, any")
        t.ok(has(problems, "weaponSpeed.dps: no preferred speed"), "named")
        for _, why in ipairs({ false, "", 5 }) do
            pack = good()
            pack.weaponSpeed.dps.why = why or nil
            ok, problems = ns.PackCheck(pack)
            t.eq(ok, false, "why " .. tostring(why))
            t.ok(has(problems, "weaponSpeed.dps: no reason"), "named for " .. tostring(why))
        end
        pack = good()
        pack.weaponSpeed.evidence = nil
        ok, problems = ns.PackCheck(pack)
        t.eq(ok, false, "no evidence class")
        t.ok(has(problems, "weaponSpeed: no evidence class"), "named")
    end,

    ["speed that does not matter is an entry: any, with its reason"] = function(t)
        local pack = good()
        pack.weaponSpeed.dps = { prefer = "any", why = "spells do the damage" }
        local ok, problems = ns.PackCheck(pack)
        t.eq(table.concat(problems, "; "), "", "no problems")
        t.eq(ok, true, "ok")
    end,

    ["a ranged or off hand part of an entry needs its own speed and reason"] = function(t)
        local pack = good()
        pack.weaponSpeed.dps.ranged = { prefer = "slow", why = "a reason in words" }
        pack.weaponSpeed.dps.offhand = { prefer = "fast", why = "a reason in words" }
        local ok, problems = ns.PackCheck(pack)
        t.eq(table.concat(problems, "; "), "", "both parts given in full pass")
        t.eq(ok, true, "ok")
        pack.weaponSpeed.dps.ranged = { prefer = "slow" }
        pack.weaponSpeed.dps.offhand = "fast"
        ok, problems = ns.PackCheck(pack)
        t.eq(ok, false, "fails")
        t.ok(has(problems, "weaponSpeed.dps.ranged: no reason"), "the ranged part: " .. table.concat(problems, "; "))
        t.ok(has(problems, "weaponSpeed.dps.offhand: no entry"), "the off hand part")
    end,

    ["every class pack says a weapon speed, with its reason, for each role it has weights for"] = function(t)
        local speeds = { slow = true, medium = true, fast = true, any = true }
        local classes, lacking = {}, {}
        for class in pairs(ns.Packs) do classes[#classes + 1] = class end
        table.sort(classes)
        for _, class in ipairs(classes) do
            local pack = ns.Packs[class]
            local speedTable = pack.weaponSpeed
            if type(speedTable) ~= "table" then
                lacking[#lacking + 1] = class
            else
                t.eq(speedTable.evidence, "first guess", class .. ": the table's evidence class")
                for role in pairs(pack.weights) do
                    local entry = speedTable[role]
                    local at = class .. " " .. role
                    t.ok(type(entry) == "table", at .. ": an entry")
                    if type(entry) == "table" then
                        t.eq(speeds[entry.prefer], true, at .. ": a speed, or any")
                        t.ok(type(entry.why) == "string" and entry.why ~= "", at .. ": a reason")
                    end
                end
            end
        end
        t.eq(table.concat(lacking, ", "), "", "class packs with no weaponSpeed table")
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

    -- P-PARTY: the look-only wording (lead section 233): a pack's dispels
    -- are for you; your group's are only shown, from those same rows.
    ["a group dispel entry says the group's are only shown"] = function(t)
        local pack = good()
        pack.dispels[1].group = true
        local _, problems = ns.PackCheck(pack)
        t.ok(has(problems, "dispels[1]: a group dispel entry (a pack's dispels are your own; "
            .. "your group's are only shown, from the same rows, never cast)"), table.concat(problems, "; "))
    end,

    -- P-PARTY: the group rows (Rotation/Group.lua) and what PackCheck asks of them.
    ["group rows: a good row passes; who, aura, slot, numbers and a unit are checked"] = function(t)
        local pack = good()
        pack.groups = {
            { spell = "Shield", aura = { "Shield", "Greater Shield" }, who = "all", slot = "s", minutes = 5, rebuff = 30,
              when = function() return true end, evidence = "first guess" },
            { spell = "Shield", who = { "tank", "melee", "caster", "healer", "ranged", "WARRIOR", "DRUID" },
              evidence = "first guess" },
        }
        local ok, problems = ns.PackCheck(pack)
        t.eq(table.concat(problems, "; "), "", "no problems")
        t.eq(ok, true, "good rows pass")
        local bad = {
            { function(r) r.who = nil end, "groups[1]: who is not \"all\" or a list of kinds and classes" },
            { function(r) r.who = {} end, "groups[1]: who is not \"all\" or a list of kinds and classes" },
            { function(r) r.who = { "tank", "wizard" } end, "groups[1]: who[2] is not a kind or a class" },
            { function(r) r.aura = "Shield" end, "groups[1]: aura is not a list of buff names" },
            { function(r) r.aura = { "Shield", "" } end, "groups[1]: aura is not a list of buff names" },
            { function(r) r.slot = 3 end, "groups[1]: slot is not a name" },
            { function(r) r.minutes = "five" end, "groups[1]: minutes is not a number" },
            { function(r) r.rebuff = -1 end, "groups[1]: rebuff is not a number" },
            { function(r) r.unit = "party1" end, "groups[1]: names a unit; group rows are only shown, never cast on anyone" },
        }
        for i, case in ipairs(bad) do
            local p = good()
            p.groups = { { spell = "Shield", aura = { "Shield" }, who = "all", evidence = "first guess" } }
            case[1](p.groups[1])
            local okBad, got = ns.PackCheck(p)
            t.eq(okBad, false, "case " .. i .. " fails")
            t.ok(has(got, case[2]), "case " .. i .. ": " .. table.concat(got, "; "))
        end
    end,

    ["group rows: a pack still holding groupBuffs is told they are in groups now"] = function(t)
        local pack = good()
        pack.groupBuffs = {}
        local ok, problems = ns.PackCheck(pack)
        t.eq(ok, false, "fails")
        t.ok(has(problems, "groupBuffs: the group rows are in groups now"), "named")
    end,

    ["group rows: every class pack's rows pass"] = function(t)
        for class, pack in pairs(ns.Packs) do
            local ok, problems = ns.PackCheck(pack)
            t.eq(ok, true, class .. ": " .. table.concat(problems, "; "))
        end
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
        local function deepCopy(v)
            if type(v) ~= "table" then return v end
            local out = {}
            for k, x in pairs(v) do out[k] = deepCopy(x) end
            return out
        end
        local was = deepCopy(pack)
        local _, problems = ns.PackCheck(pack)
        t.eq(pack, was, "the whole pack is as it was: nothing written, added or taken")
        t.ok(#problems > 1, "more than one problem, so the order can be told")
        local sorted = {}
        for i, p in ipairs(problems) do sorted[i] = p end
        table.sort(sorted)
        t.eq(table.concat(problems, "|"), table.concat(sorted, "|"), "sorted")
        t.eq(pack.lists.default[1].spell, "Bolt", "the pack is as it was")
    end,

    -- G31: the levelling recommendation. A pack may have none; one given
    -- names one of the pack's roles, carries an evidence class and says why
    -- in words.
    ["a levelling row is optional, and a complete one passes"] = function(t)
        local pack = good()
        t.eq(pack.levelling, nil, "the good pack has none")
        t.eq(ns.PackCheck(pack), true, "none passes")
        pack.levelling = { role = "dps", why = { "A reason in words." }, evidence = "first guess" }
        local ok, problems = ns.PackCheck(pack)
        t.eq(table.concat(problems, "; "), "", "no problems")
        t.eq(ok, true, "ok")
    end,

    ["a levelling row that is wrong is reported, each fault by name"] = function(t)
        local function row() return { role = "dps", why = { "A reason in words." }, evidence = "first guess" } end
        local cases = {
            { function(p) p.levelling = "dps" end, "levelling: not a table" },
            { function(p) p.levelling.role = "tank" end, "levelling: the role is not one of the pack's roles" },
            { function(p) p.levelling.role = nil end, "levelling: the role is not one of the pack's roles" },
            { function(p) p.levelling.why = nil end, "levelling: no reason given" },
            { function(p) p.levelling.why = {} end, "levelling: no reason given" },
            { function(p) p.levelling.why = { "Words.", "" } end, "levelling.why[2]: the reason is not words" },
            { function(p) p.levelling.why = { 5 } end, "levelling.why[1]: the reason is not words" },
            { function(p) p.levelling.evidence = nil end, "levelling: no evidence class" },
            { function(p) p.levelling.evidence = "a guide" end, "levelling: unknown evidence class" },
        }
        for i, case in ipairs(cases) do
            local pack = good()
            pack.levelling = row()
            case[1](pack)
            local ok, problems = ns.PackCheck(pack)
            t.eq(ok, false, "case " .. i .. " fails")
            t.ok(has(problems, case[2]), "case " .. i .. " names it: " .. table.concat(problems, "; "))
        end
    end,
}

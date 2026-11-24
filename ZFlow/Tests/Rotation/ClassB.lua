local _, ns = ...

-- Lead section 242 (MAGE-3, MAGE-4, PRIEST-6): the shared crowd-control
-- step, the interrupt of a cast on a nameplate that is not your target,
-- and Fade on the threat read in a group. Every one is a suggestion shown:
-- the crowd-control and plate-cast steps are look-only (the key never casts
-- on a unit the add-on chose), Fade is cast on you. The two plate reads
-- (client.plateEnemies, client.plateCasts) come from the fake here; the real
-- reads are P-READS (Plexy). Made-up names only. Not tested in game.
local tests = {}

local R = ns.Rotation
local D = ns.RotationDriver

local function steps() return R._steps or {} end

local function snap(known, over)
    local s = { dead = false, inCombat = true, spells = {} }
    for _, name in ipairs(known or {}) do s.spells[name] = { known = true, onCooldown = false, inRange = true } end
    for k, v in pairs(over or {}) do s[k] = v end
    return s
end

local function mage()
    return {
        interrupts = { { spell = "Counterspell", evidence = "test" } },
        options = { crowdControl = { { spell = "Polymorph", creatures = { beast = true, humanoid = true } } } },
    }
end

local function priest()
    return {
        interrupts = { { spell = "Silence", evidence = "test" }, { spell = "Psychic Scream", near = true, evidence = "test" } },
        options = {
            crowdControl = { { spell = "Shackle Undead", creatures = { undead = true } } },
            threatDrop = { spell = "Fade" },
        },
    }
end

local TWO = {
    { unit = "nameplate1", name = "Gnoll", isTarget = true, creature = "Humanoid", controlled = false },
    { unit = "nameplate2", name = "Kobold", isTarget = false, creature = "Humanoid", controlled = false },
}

local function run(name, s, pack, prefs)
    local fn = steps()[name]
    if type(fn) ~= "function" then return nil, "no step " .. name end
    return fn(s, pack, prefs, nil, {})
end

tests["class b: the step order puts the plate cast after your own interrupt and crowd control before the list"] = function(t)
    t.eq(table.concat(R.STEPS, " "),
        "breakFree heal interrupt plateCast dispel engage threat cc list farOpener recover food track group")
end

-- MAGE-3 and PRIEST-6 Shackle --------------------------------------------

tests["class b cc: two enemies, the second a humanoid not held: Polymorph it, shown only"] = function(t)
    local s, why = run("cc", snap({ "Polymorph" }, { enemies = TWO }), mage())
    t.ok(type(s) == "table", "a suggestion: " .. tostring(why))
    if type(s) ~= "table" then return end
    t.eq(s.spell, "Polymorph")
    t.eq(s.look, true, "look-only: never put on the key")
    t.eq(s.unit, "nameplate2")
    t.eq(s.member, "Kobold", "the name for the live caption")
    t.eq(s.reason, "Polymorph the second enemy (focus or mouseover it)")
end

tests["class b cc: one enemy, your own target, or a type it does not work on: nothing"] = function(t)
    local one = { TWO[1] }
    t.eq((run("cc", snap({ "Polymorph" }, { enemies = one }), mage())), nil, "one enemy")
    local both = {
        { unit = "nameplate1", isTarget = true, creature = "Beast", controlled = false },
        { unit = "nameplate2", isTarget = true, creature = "Beast", controlled = false },
    }
    t.eq((run("cc", snap({ "Polymorph" }, { enemies = both }), mage())), nil, "only your target")
    local undead = {
        TWO[1],
        { unit = "nameplate2", isTarget = false, creature = "Undead", controlled = false },
    }
    t.eq((run("cc", snap({ "Polymorph" }, { enemies = undead }), mage())), nil, "Polymorph on undead: no")
    local s = run("cc", snap({ "Shackle Undead" }, { enemies = undead }), priest())
    t.eq(s and s.spell, "Shackle Undead", "Shackle on undead: yes")
    t.eq(s and s.look, true)
    t.eq((run("cc", snap({ "Shackle Undead" }, { enemies = TWO }), priest())), nil, "Shackle on a humanoid: no")
end

tests["class b cc: unknown stays unknown: type, held, plates, fight not read: nothing"] = function(t)
    local function second(over)
        local e = { unit = "nameplate2", isTarget = false, creature = "Humanoid", controlled = false }
        for k, v in pairs(over) do e[k] = v end
        return { TWO[1], e }
    end
    t.eq((run("cc", snap({ "Polymorph" }, { enemies = second({ creature = false }) }), mage())), nil, "type not read")
    local e = second({}); e[2].creature = nil
    t.eq((run("cc", snap({ "Polymorph" }, { enemies = e }), mage())), nil, "type nil")
    e = second({}); e[2].controlled = nil
    t.eq((run("cc", snap({ "Polymorph" }, { enemies = e }), mage())), nil, "held not read")
    t.eq((run("cc", snap({ "Polymorph" }, { enemies = second({ controlled = true }) }), mage())), nil, "already held")
    e = second({}); e[2].isTarget = nil
    t.eq((run("cc", snap({ "Polymorph" }, { enemies = e }), mage())), nil, "not known whether it is your target")
    local s, why = run("cc", snap({ "Polymorph" }, { enemies = nil }), mage())
    t.eq(s, nil); t.eq(why, "nameplates not read")
    local unread = snap({ "Polymorph" }, { enemies = TWO })
    unread.inCombat = nil
    s = run("cc", unread, mage())
    t.eq(s, nil, "fight not read")
    s = run("cc", snap({ "Polymorph" }, { enemies = TWO, inCombat = false }), mage())
    t.eq(s, nil, "out of a fight")
end

tests["class b cc: the spell must be known, ready and not switched off; no rule, no step"] = function(t)
    t.eq((run("cc", snap({}, { enemies = TWO }), mage())), nil, "not known")
    local s = snap({ "Polymorph" }, { enemies = TWO }); s.spells.Polymorph.onCooldown = true
    t.eq((run("cc", s, mage())), nil, "on cooldown")
    s = snap({ "Polymorph" }, { enemies = TWO }); s.spells.Polymorph.usable = false
    t.eq((run("cc", s, mage())), nil, "not usable")
    t.eq((run("cc", snap({ "Polymorph" }, { enemies = TWO }), mage(), { skip = { Polymorph = true } })), nil, "switched off")
    local none, why = run("cc", snap({ "Polymorph" }, { enemies = TWO }), { interrupts = {} })
    t.eq(none, nil); t.eq(why, "no crowd control")
    s = snap({ "Polymorph" }, { enemies = TWO }); s.spells.Polymorph.inRange = false
    t.eq((run("cc", s, mage()) or {}).spell, "Polymorph", "the range is to the other enemy, not your target: not asked")
end

-- MAGE-4 and the shared plate cast ------------------------------------------

local CASTS = {
    { unit = "nameplate3", name = "Shaman", spell = "Healing Wave", interruptible = true, isTarget = false },
}

tests["class b plate cast: another enemy casting something you can stop: Counterspell it, shown only"] = function(t)
    local s, why = run("plateCast", snap({ "Counterspell" }, { plateCasts = CASTS }), mage())
    t.ok(type(s) == "table", "a suggestion: " .. tostring(why))
    if type(s) ~= "table" then return end
    t.eq(s.spell, "Counterspell")
    t.eq(s.look, true)
    t.eq(s.unit, "nameplate3")
    t.eq(s.member, "Shaman")
    t.eq(s.reason, "Counterspell the enemy casting Healing Wave (focus or mouseover it)")
end

tests["class b plate cast: your own target, a cast that cannot be stopped, or one not read: nothing"] = function(t)
    local function cast(over)
        local c = { unit = "nameplate3", name = "Shaman", spell = "Healing Wave", interruptible = true, isTarget = false }
        for k, v in pairs(over) do c[k] = v end
        return { c }
    end
    t.eq((run("plateCast", snap({ "Counterspell" }, { plateCasts = cast({ isTarget = true }) }), mage())), nil, "your target: the interrupt step")
    t.eq((run("plateCast", snap({ "Counterspell" }, { plateCasts = cast({ interruptible = false }) }), mage())), nil, "cannot be stopped")
    local c = cast({}); c[1].interruptible = nil
    t.eq((run("plateCast", snap({ "Counterspell" }, { plateCasts = c }), mage())), nil, "stoppable not read (a secret)")
    c = cast({}); c[1].isTarget = nil
    t.eq((run("plateCast", snap({ "Counterspell" }, { plateCasts = c }), mage())), nil, "target not read")
    local s, why = run("plateCast", snap({ "Counterspell" }, { plateCasts = nil }), mage())
    t.eq(s, nil); t.eq(why, "plate casts not read")
    local unread = snap({ "Counterspell" }, { plateCasts = CASTS })
    unread.inCombat = nil
    t.eq((run("plateCast", unread, mage())), nil, "fight not read")
    t.eq((run("plateCast", snap({ "Counterspell" }, { plateCasts = {} }), mage())), nil, "nobody casting")
end

tests["class b plate cast: a near-only interrupt is not offered for a far enemy; the next one is"] = function(t)
    local s = run("plateCast", snap({ "Psychic Scream", "Silence" }, { plateCasts = CASTS }), priest())
    t.eq(s and s.spell, "Silence")
    s = run("plateCast", snap({ "Psychic Scream" }, { plateCasts = CASTS }), priest())
    t.eq(s, nil, "Psychic Scream reaches only what is near you")
end

tests["class b plate cast: the same rule serves Kick, Pummel in its stance, and Earth Shock"] = function(t)
    local rogue = { interrupts = { { spell = "Kick", evidence = "test" } } }
    t.eq((run("plateCast", snap({ "Kick" }, { plateCasts = CASTS }), rogue) or {}).spell, "Kick")
    local warrior = { interrupts = {
        { spell = "Pummel", forms = { ["Berserker Stance"] = true }, evidence = "test" },
        { spell = "Shield Bash", forms = { ["Battle Stance"] = true, ["Defensive Stance"] = true }, evidence = "test" },
    } }
    local s = run("plateCast", snap({ "Pummel", "Shield Bash" },
        { plateCasts = CASTS, formKnown = true, form = "Berserker Stance" }), warrior)
    t.eq(s and s.spell, "Pummel")
    s = run("plateCast", snap({ "Pummel", "Shield Bash" },
        { plateCasts = CASTS, formKnown = true, form = "Defensive Stance" }), warrior)
    t.eq(s and s.spell, "Shield Bash")
    s = run("plateCast", snap({ "Pummel", "Shield Bash" }, { plateCasts = CASTS }), warrior)
    t.eq(s, nil, "stance not read: no stance-bound interrupt")
    local shaman = { interrupts = { { spell = "Earth Shock", evidence = "test" } } }
    t.eq((run("plateCast", snap({ "Earth Shock" }, { plateCasts = CASTS }), shaman) or {}).spell, "Earth Shock")
    local cd = snap({ "Kick" }, { plateCasts = CASTS }); cd.spells.Kick.onCooldown = nil
    local none = run("plateCast", cd, rogue)
    t.eq(none, nil, "cooldown not read: not ready")
end

tests["class b plate cast: your own target casting goes to the interrupt step first"] = function(t)
    local s = ns.Choose(snap({ "Counterspell" }, {
        hostile = true, targetCasting = "Fireball", plateCasts = CASTS,
    }), mage())
    t.eq(s and s.step, "interrupt")
    t.eq(s and s.look, nil, "your own target: on the key")
end

-- PRIEST-6 Fade --------------------------------------------------------------

local ON_YOU = { { unit = "nameplate1", isTarget = true, threat = 3 } }

tests["class b threat: in a group, an enemy on you: Fade, on you"] = function(t)
    local s, why = run("threat", snap({ "Fade" }, { grouped = true, role = "heal", enemies = ON_YOU }), priest())
    t.ok(type(s) == "table", "a suggestion: " .. tostring(why))
    if type(s) ~= "table" then return end
    t.eq(s.spell, "Fade")
    t.eq(s.unit, "player")
    t.eq(s.kind, "buff")
    t.eq(s.look, nil, "Fade is cast on you: on the key")
    t.eq(s.reason, "Fade: an enemy is on you in a group")
end

-- Mutation found (threat >= 3 passed every case): threat 2, on you but
-- not securely, is on you too.
tests["class b threat: threat 2 is on you as well: Fade"] = function(t)
    local two = { { unit = "nameplate1", isTarget = true, threat = 2 } }
    local s = run("threat", snap({ "Fade" }, { grouped = true, role = "heal", enemies = two }), priest())
    t.eq(s and s.spell, "Fade")
end

tests["class b threat: alone, the tank, no threat, or not read: no Fade"] = function(t)
    t.eq((run("threat", snap({ "Fade" }, { grouped = false, enemies = ON_YOU }), priest())), nil, "alone")
    local s, why = run("threat", snap({ "Fade" }, { grouped = nil, enemies = ON_YOU }), priest())
    t.eq(s, nil); t.eq(why, "not known whether you are in a group")
    t.eq((run("threat", snap({ "Fade" }, { grouped = true, role = "tank", enemies = ON_YOU }), priest())), nil, "the tank")
    t.eq((run("threat", snap({ "Fade" }, { grouped = true, enemies = { { unit = "nameplate1", threat = 1 } } }), priest())), nil, "not on you")
    t.eq((run("threat", snap({ "Fade" }, { grouped = true, enemies = { { unit = "nameplate1" } } }), priest())), nil, "threat not read")
    t.eq((run("threat", snap({ "Fade" }, { grouped = true, enemies = nil }), priest())), nil, "plates not read")
    t.eq((run("threat", snap({ "Fade" }, { grouped = true, enemies = ON_YOU, inCombat = false }), priest())), nil, "out of a fight")
    t.eq((run("threat", snap({}, { grouped = true, enemies = ON_YOU }), priest())), nil, "Fade not known")
    t.eq((run("threat", snap({ "Fade" }, { grouped = true, enemies = ON_YOU }), mage())), nil, "no threat drop in the pack")
end

-- The snapshot and the reads ------------------------------------------------

tests["class b snapshot: the plate rows keep plain fields, need a unit, and stay nil when not read"] = function(t)
    local s = ns.SnapshotOf({
        enemies = { { unit = "nameplate1", name = "Gnoll", isTarget = false, creature = "Humanoid", controlled = false,
                      threat = 2, extra = {}, fn = function() end }, { name = "no unit" }, "junk" },
        plateCasts = { { unit = "nameplate2", spell = "Heal", interruptible = true, isTarget = false } },
    })
    t.eq(s.enemies, { { unit = "nameplate1", name = "Gnoll", isTarget = false, creature = "Humanoid", controlled = false, threat = 2 } })
    t.eq(s.plateCasts, { { unit = "nameplate2", spell = "Heal", interruptible = true, isTarget = false } })
    local empty = ns.SnapshotOf({})
    t.eq(empty.enemies, nil, "not read: nil, never an empty list")
    t.eq(empty.plateCasts, nil)
    t.eq(ns.SnapshotOf({ enemies = {} }).enemies, {}, "read, and none")
end

tests["class b driver: the two plate reads are asked of the client, and a read that raises is not known"] = function(t)
    local rows = { { unit = "nameplate1", isTarget = true } }
    local client = {
        plateEnemies = function() return rows end,
        plateCasts = function() return { { unit = "nameplate2", spell = "Heal", interruptible = true } } end,
    }
    local read = D.Read(client, {}, {}, nil)
    t.eq(read("enemies"), rows)
    t.eq(read("plateCasts"), { { unit = "nameplate2", spell = "Heal", interruptible = true } })
    local bad = D.Read({ plateEnemies = function() error("raised") end, plateCasts = function() return "x" end }, {}, {}, nil)
    t.eq(bad("enemies"), nil, "raised: not known")
    t.eq(bad("plateCasts"), nil, "not a list: not known")
    local none = D.Read({}, {}, {}, nil)
    t.eq(none("enemies"), nil, "no read: not known")
    t.eq(none("plateCasts"), nil)
end

tests["class b fake: the plate reads answer copies, nil until set"] = function(t)
    local c = ns.make.fakeClient()
    t.eq(c.plateEnemies and c.plateEnemies(), nil, "not set: nil")
    t.eq(c.plateCasts and c.plateCasts(), nil)
    if type(c.setPlateEnemies) ~= "function" or type(c.setPlateCasts) ~= "function" then
        t.ok(false, "the fake has the plate setters"); return
    end
    local list = { { unit = "nameplate1", creature = "Beast" } }
    c.setPlateEnemies(list)
    local got = c.plateEnemies()
    t.eq(got, list)
    got[1].creature = "changed"
    t.eq(c.plateEnemies()[1].creature, "Beast", "a copy")
    c.setPlateCasts({ { unit = "nameplate2", spell = "Heal" } })
    t.eq(c.plateCasts(), { { unit = "nameplate2", spell = "Heal" } })
    c.setPlateEnemies(nil)
    t.eq(c.plateEnemies(), nil)
end

-- The packs and the spell card ---------------------------------------------

tests["class b packs: Polymorph and Shackle as crowd control, Fade as the threat drop"] = function(t)
    local m, p = ns.Packs.MAGE, ns.Packs.PRIEST
    local mcc = m.options and m.options.crowdControl or {}
    t.eq(mcc[1] and mcc[1].spell, "Polymorph")
    t.eq(mcc[1] and mcc[1].creatures, { beast = true, humanoid = true })
    local pcc = p.options and p.options.crowdControl or {}
    t.eq(pcc[1] and pcc[1].spell, "Shackle Undead")
    t.eq(pcc[1] and pcc[1].creatures, { undead = true })
    t.eq(p.options and p.options.threatDrop, { spell = "Fade" })
    for _, name in ipairs({ "Shackle Undead", "Mind Soothe", "Mind Control", "Levitate" }) do
        t.ok(type(p.spells[name]) == "table", name .. " is in the Priest spells")
    end
end

tests["class b spell card: Mind Soothe, Mind Control and Levitate carry a tip; a spell with none gets none"] = function(t)
    local p = ns.Packs.PRIEST
    for _, name in ipairs({ "Mind Soothe", "Mind Control", "Levitate" }) do
        local card = ns.SpellCard.Build({ name = name, rank = "Rank 1" }, p)
        local lines = ns.SpellCard.Lines(card)
        t.eq(#lines, 2, name .. ": two lines")
        t.ok(tostring(lines[2]):find("^Tip: ") ~= nil, name .. ": " .. tostring(lines[2]))
        t.ok(not tostring(lines[2]):lower():find("rotation", 1, true), "no rotation claim")
        t.ok(not tostring(lines[2]):find("Flow", 1, true), "no add-on name")
    end
    local fade = ns.SpellCard.Lines(ns.SpellCard.Build({ name = "Fade" }, p))
    t.eq(fade, { "New spell: Fade" })
    local nopack = ns.SpellCard.Lines(ns.SpellCard.Build({ name = "Levitate" }))
    t.eq(nopack, { "New spell: Levitate" }, "no pack: no tip")
end

-- Lead section 280 (class parity) on section 242: every one of the nine
-- packs names its crowd control and its threat drop, or says in words why
-- it has none; no class has the step while the others are silent.

local NINE = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }

local function packOf(class)
    return type(ns.Packs) == "table" and ns.Packs[class] or nil
end

local function words(v) return type(v) == "string" and v:find("%a") ~= nil end

tests["class b parity: every pack names its crowd control, or says why it has none"] = function(t)
    for _, class in ipairs(NINE) do
        local pack = packOf(class)
        local opts = type(pack) == "table" and pack.options or nil
        local rules = type(opts) == "table" and opts.crowdControl or nil
        t.ok(type(rules) == "table", class .. ": options.crowdControl is stated")
        if type(rules) == "table" then
            if #rules == 0 then
                t.ok(words(rules.none), class .. ": no crowd control, and the reason is words")
            end
            for _, r in ipairs(rules) do
                t.ok(type(r.spell) == "string" and type(pack.spells) == "table" and pack.spells[r.spell] ~= nil,
                    class .. ": " .. tostring(r.spell) .. " is a spell of the pack")
                t.ok(type(r.creatures) == "table" and next(r.creatures) ~= nil, class .. ": the creatures it holds are named")
            end
        end
    end
end

tests["class b parity: every pack names its threat drop, or says why it has none"] = function(t)
    for _, class in ipairs(NINE) do
        local pack = packOf(class)
        local opts = type(pack) == "table" and pack.options or nil
        local drop = type(opts) == "table" and opts.threatDrop or nil
        t.ok(type(drop) == "table", class .. ": options.threatDrop is stated")
        if type(drop) == "table" then
            if drop.spell == nil then
                t.ok(words(drop.none), class .. ": no threat drop, and the reason is words")
            else
                t.ok(type(pack.spells) == "table" and pack.spells[drop.spell] ~= nil,
                    class .. ": " .. tostring(drop.spell) .. " is a spell of the pack")
            end
        end
    end
end

tests["class b parity: every talent in every build says why it is taken"] = function(t)
    for _, class in ipairs(NINE) do
        local pack = packOf(class)
        for i, build in ipairs(type(pack) == "table" and type(pack.talentBuilds) == "table" and pack.talentBuilds or {}) do
            for j, row in ipairs(type(build.order) == "table" and build.order or {}) do
                t.ok(words(row.why), string.format("%s build %d talent %d (%s): the reason is words", class, i, j, tostring(row[1])))
            end
        end
    end
end

tests["class b parity: a crowd control or threat drop that says none is no step"] = function(t)
    local none = {
        options = {
            crowdControl = { none = "no spell holds a second enemy" },
            threatDrop = { none = "no spell drops threat" },
        },
    }
    local onYou = { { unit = "nameplate1", isTarget = true, threat = 3 } }
    local s, why = run("cc", snap({}, { enemies = TWO }), none)
    t.eq(s, nil); t.eq(why, "no crowd control")
    s, why = run("threat", snap({}, { grouped = true, role = "dps", enemies = onYou }), none)
    t.eq(s, nil); t.eq(why, "no threat drop")
end

tests["class b parity: a threat drop tied to a form (Cower) waits for that form, read"] = function(t)
    local druid = { options = { threatDrop = { spell = "Cower", forms = { ["Cat Form"] = true } } } }
    local onYou = { { unit = "nameplate1", isTarget = true, threat = 3 } }
    local function at(form, known)
        return snap({ "Cower" }, { grouped = true, role = "dps", enemies = onYou, form = form, formKnown = known })
    end
    local s, why = run("threat", at("Cat Form", true), druid)
    t.eq(s and s.spell, "Cower", "in cat form: " .. tostring(why))
    t.eq(s and s.unit, "player")
    t.eq((run("threat", at("Bear Form", true), druid)), nil, "bear form: no Cower")
    t.eq((run("threat", at("none", true), druid)), nil, "caster form: no Cower")
    t.eq((run("threat", at(nil, false), druid)), nil, "form not read: no Cower")
end


-- CLASS-B-TALENTS (section 309, the section 280 follow-up of class b): each
-- of the nine classes has a levelling build, marked a first guess, three
-- trees named, a role the pack has, each talent once, one to five ranks, no
-- more than the 51 points of level 60, and a reason in words for each row.
tests["class b talents: every class has a levelling build, a first guess, each row with its reason"] = function(t)
    for _, class in ipairs(NINE) do
        local pack = packOf(class)
        local builds = type(pack) == "table" and type(pack.talentBuilds) == "table" and pack.talentBuilds or {}
        t.ok(#builds >= 1, class .. ": a talent build")
        local build = builds[1]
        if type(build) == "table" then
            t.eq(build.evidence, "first guess", class .. ": marked a first guess")
            t.ok(words(build.note), class .. ": a note says where it came from")
            t.ok(words(build.name), class .. ": the build has a name")
            t.ok(type(build.trees) == "table" and #build.trees == 3, class .. ": three trees")
            t.ok(type(pack.roles) == "table" and pack.roles[build.role] ~= nil, class .. ": a role the pack has")
            local order = type(build.order) == "table" and build.order or {}
            t.ok(#order >= 8, class .. ": at least eight talents")
            local seen, points = {}, 0
            for j, row in ipairs(order) do
                local name, ranks = row[1], row[2]
                t.ok(words(name), string.format("%s talent %d is named", class, j))
                t.ok(seen[name] == nil, string.format("%s talent %s is taken once", class, tostring(name)))
                seen[name] = true
                t.ok(type(ranks) == "number" and ranks >= 1 and ranks <= 5 and ranks % 1 == 0,
                    string.format("%s talent %s: one to five ranks", class, tostring(name)))
                points = points + (type(ranks) == "number" and ranks or 0)
                t.ok(words(row.why), string.format("%s talent %s: the reason is words", class, tostring(name)))
            end
            t.ok(points >= 1 and points <= 51, class .. ": no more than 51 points")
        end
    end
end
return tests

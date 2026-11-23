local _, ns = ...

-- P-PARTY (lead section 233): your group's buffs, and the curses and poisons
-- on them you could remove, suggested out of a fight (Rotation/Group.lua).
-- Look only: the suggestion names the party unit and the spell; the key
-- never casts it on anyone (Rotation/Cast.lua). The member's name is only in
-- `member`, for the live caption: never in a reason, a trace note or a diag
-- line. Made-up names, units and ids, test only. Not seen in game.

local R = ns.Rotation
local tests = {}

local MOTW, GOTW, THORNS = "Mark of the Wild", "Gift of the Wild", "Thorns"
local KINGS, MIGHT, WISDOM = "Blessing of Kings", "Blessing of Might", "Blessing of Wisdom"
local INTELLECT, BRILLIANCE = "Arcane Intellect", "Arcane Brilliance"
local FORTITUDE, PRAYER = "Power Word: Fortitude", "Prayer of Fortitude"
local ABOLISH, CURE, CURSE = "Abolish Poison", "Cure Poison", "Remove Curse"
local NAME, OTHER = "Fennimore", "Quillaby"   -- made up

local ALL = { MOTW, THORNS, KINGS, MIGHT, WISDOM, INTELLECT, FORTITUDE, ABOLISH, CURE, CURSE }

-- A member as the read hands it on: in reach of every spell, alive, online,
-- and with every buff up for ten minutes, unless `over` says otherwise
-- ("nil" leaves a field out).
local function member(unit, over)
    local m = { unit = unit, name = NAME, class = "WARRIOR", role = "NONE", kind = "melee",
                dead = false, connected = true, reach = {}, has = {} }
    for _, n in ipairs(ALL) do
        m.reach[n] = true
        m.has[n] = 600
    end
    for k, v in pairs(over or {}) do
        if v == "nil" then m[k] = nil else m[k] = v end
    end
    return m
end

-- The same member with these buffs set (false: missing; a number: seconds
-- left; "nil": not known).
local function missing(unit, has, over)
    local m = member(unit, over)
    for spell, v in pairs(has) do
        if v == "nil" then m.has[spell] = nil else m.has[spell] = v end
    end
    return m
end

-- Out of a fight, no enemy targeted, the setting on, every spell ready.
local function snap(party, over)
    local s = { dead = false, inCombat = false, hostile = false, groupOn = true, party = party, spells = {} }
    for _, n in ipairs(ALL) do s.spells[n] = { known = true, usable = true, onCooldown = false } end
    for k, v in pairs(over or {}) do
        if v == "nil" then s[k] = nil else s[k] = v end
    end
    return s
end

-- The druid's rows with no form rule (the form rule is the real pack's, below).
local function druidPack()
    return {
        groups = {
            { spell = MOTW, aura = { MOTW, GOTW }, who = "all", minutes = 30, rebuff = 60, evidence = "first guess" },
            { spell = THORNS, who = { "tank", "WARRIOR" }, minutes = 10, rebuff = 30, evidence = "first guess" },
        },
        dispels = {
            { spell = CURSE, types = { Curse = true }, evidence = "first guess" },
            { spell = ABOLISH, types = { Poison = true }, evidence = "first guess" },
            { spell = CURE, types = { Poison = true }, evidence = "first guess" },
        },
    }
end

local function choose(party, over, pack)
    return ns.Choose(snap(party, over), pack or druidPack())
end

local function lastNote(trace)
    local row = trace[#trace]
    return row and row.step, row and row.note
end

-- No row of the trace and no reason holds the made-up name.
local function nameFree(t, s, trace, label)
    if type(s) == "table" then
        t.ok(not tostring(s.reason):find(NAME, 1, true), label .. ": the reason has no name")
    end
    for _, row in ipairs(trace or {}) do
        t.ok(not tostring(row.note):find(NAME, 1, true), label .. ": no name in the " .. tostring(row.step) .. " row")
    end
end

-- ------------------------------------------------------------------ the pick

tests["group: a member missing Mark of the Wild: the unit and the spell, look only"] = function(t)
    local s, trace = choose({ missing("party1", { [MOTW] = false }) })
    t.ok(type(s) == "table", "a suggestion")
    if type(s) ~= "table" then return end
    t.eq({ s.spell, s.unit, s.member, s.look, s.kind, s.step },
        { MOTW, "party1", NAME, true, "group", "group" })
    t.ok(tostring(s.reason):find("party1", 1, true) ~= nil, "the reason names the unit: " .. tostring(s.reason))
    nameFree(t, s, trace, "pick")
    t.eq(trace[#trace].step, "group", "the group step answered")
    t.eq(trace[#trace].result, "pick")
end

tests["group: the step is the last one, after the gathering tracking"] = function(t)
    t.eq(R.STEPS[#R.STEPS], "group")
    t.eq(R.STEPS[#R.STEPS - 1], "track")
end

tests["group: nobody missing anything: nothing"] = function(t)
    local s, trace = choose({ member("party1"), member("party2", { class = "MAGE", kind = "caster" }) })
    t.eq(s, nil)
    local step, note = lastNote(trace)
    t.eq(step, "group")
    t.eq(note, "everyone has your buffs")
end

tests["group: running out (at or under the row's rebuff) counts as missing"] = function(t)
    local s = choose({ missing("party1", { [MOTW] = 60 }) })
    t.eq(s and s.spell, MOTW, "60 s left, rebuff 60: suggested")
    s = choose({ missing("party1", { [MOTW] = 61 }) })
    t.eq(s, nil, "61 s left: not yet")
    s = choose({ missing("party1", { [MOTW] = true }) })
    t.eq(s, nil, "up, time left not known: covered, not a guess that it runs out")
    s = choose({ missing("party1", { [MOTW] = math.huge }) })
    t.eq(s, nil, "up with no end: covered")
end

tests["group: dead, offline or out of reach: skipped, the next member gets it"] = function(t)
    local cases = {
        { "dead", { dead = true } },
        { "dead not known", { dead = "nil" } },
        { "offline", { connected = false } },
        { "out of reach", { reach = { [MOTW] = false, [THORNS] = false } } },
        { "reach not known", { reach = {} } },
    }
    for _, case in ipairs(cases) do
        local label, over = case[1], case[2]
        local s = choose({ missing("party1", { [MOTW] = false }, over) })
        t.eq(s, nil, label .. ": nothing")
        s = choose({ missing("party1", { [MOTW] = false }, over),
                     missing("party2", { [MOTW] = false }, { name = OTHER }) })
        t.eq(s and { s.unit, s.member } or nil, { "party2", OTHER }, label .. ": the next member")
    end
    local s = choose({ missing("party1", { [MOTW] = false }, { connected = "nil" }) })
    t.eq(s and s.unit, "party1", "online not known: in reach is enough, they are there")
end

tests["group: in a fight, a fight not known, an enemy targeted, resting, or switched off: nothing"] = function(t)
    local party = { missing("party1", { [MOTW] = false }) }
    t.ok(choose(party) ~= nil, "out of a fight: suggested, so this test can fail")
    local cases = {
        { "in a fight", { inCombat = true } },
        { "a fight not known", { inCombat = "nil" } },
        { "an enemy targeted", { hostile = true } },
        { "the target not known", { hostile = "nil" } },
        { "resting", { resting = true } },
        { "switched off", { groupOn = false } },
    }
    for _, case in ipairs(cases) do
        local s, trace = choose(party, case[2])
        t.eq(s, nil, case[1])
        nameFree(t, s, trace, case[1])
    end
    t.ok(choose(party, { groupOn = "nil" }) ~= nil, "the setting not read: on, as by default")
end

tests["group: not read gives nothing, never a guess"] = function(t)
    local s, trace = choose(nil)
    t.eq(s, nil, "the group not read")
    local step, note = lastNote(trace)
    t.eq(step, "group")
    t.eq(note, "your group not read")
    s, trace = choose({})
    t.eq(s, nil, "alone")
    t.eq(trace[#trace].note, "nobody in your group")
    s = choose({ missing("party1", { [MOTW] = "nil", [THORNS] = "nil" }) })
    t.eq(s, nil, "their buffs not known: not said to be missing")
    s = choose({ missing("party1", { [MOTW] = false }) }, { spells = {} })
    t.eq(s, nil, "your spells not read: nothing")
end

tests["group: a spell not known, switched off in prefs, or on cooldown is not suggested"] = function(t)
    local party = { missing("party1", { [MOTW] = false, [THORNS] = false }) }
    local s = ns.Choose(snap(party), druidPack(), { skip = { [MOTW] = true } })
    t.eq(s and s.spell, THORNS, "Mark skipped: Thorns")
    local over = snap(party)
    over.spells[MOTW].onCooldown = nil
    s = ns.Choose(over, druidPack())
    t.eq(s and s.spell, THORNS, "Mark's cooldown not read: Thorns")
    over.spells[THORNS].known = false
    t.eq(ns.Choose(over, druidPack()), nil, "neither")
end

-- ------------------------------------------------------- class need (legacy)

-- Flow's Classes/Paladin/Rotation.lua:408-419: Kings for a tank; Might for
-- melee; Wisdom for casters, healers and hunters; Kings for anyone else.
tests["group: a paladin's blessing by what the member does, one each"] = function(t)
    local pack = { groups = ns.Packs.PALADIN.groups, dispels = {} }
    local none = { [KINGS] = false, [MIGHT] = false, [WISDOM] = false }
    local cases = {
        { "a tank", { class = "WARRIOR", role = "TANK", kind = "tank" }, KINGS },
        { "a rogue", { class = "ROGUE", kind = "melee" }, MIGHT },
        { "a mage", { class = "MAGE", kind = "caster" }, WISDOM },
        { "a healer", { class = "PRIEST", role = "HEALER", kind = "healer" }, WISDOM },
        { "a hunter", { class = "HUNTER", kind = "ranged" }, WISDOM },
        { "a druid in no form read", { class = "DRUID", kind = "nil" }, KINGS },
    }
    for _, case in ipairs(cases) do
        local s = choose({ missing("party1", none, case[2]) }, nil, pack)
        t.eq(s and s.spell, case[3], case[1])
    end
    -- One blessing each: a rogue with Might up is not given Kings too.
    local s = choose({ missing("party1", { [KINGS] = false, [MIGHT] = 600, [WISDOM] = false },
        { class = "ROGUE", kind = "melee" }) }, nil, pack)
    t.eq(s, nil, "Might up: no second blessing")
    -- Might not known: the rogue's blessing is the next that fits, Kings.
    local over = snap({ missing("party1", none, { class = "ROGUE", kind = "melee" }) })
    over.spells[MIGHT].known = false
    s = ns.Choose(over, pack)
    t.eq(s and s.spell, KINGS, "Might not learned: Kings")
end

tests["group: a druid's Thorns for a tank or a warrior only; Mark for everyone"] = function(t)
    local s = choose({ missing("party1", { [THORNS] = false }, { class = "ROGUE", kind = "melee" }) })
    t.eq(s, nil, "a rogue: no Thorns")
    s = choose({ missing("party1", { [THORNS] = false }) })
    t.eq(s and s.spell, THORNS, "a warrior")
    s = choose({ missing("party1", { [THORNS] = false }, { class = "DRUID", role = "TANK", kind = "tank" }) })
    t.eq(s and s.spell, THORNS, "a tank")
    s = choose({ missing("party1", { [MOTW] = false }, { class = "ROGUE", kind = "melee" }) })
    t.eq(s and s.spell, MOTW, "Mark for anyone")
end

tests["group: the druid pack's rows want caster form"] = function(t)
    local pack = { groups = ns.Packs.DRUID.groups, dispels = {} }
    local party = { missing("party1", { [MOTW] = false }) }
    local s = choose(party, { formKnown = true }, pack)
    t.eq(s and s.spell, MOTW, "no form: Mark")
    s = choose(party, { formKnown = true, form = "Cat Form" }, pack)
    t.eq(s, nil, "in Cat Form: nothing")
    s = choose(party, { formKnown = "nil" }, pack)
    t.eq(s, nil, "form not read: nothing")
end

tests["group: arcane intellect for those who use mana; brilliance counts"] = function(t)
    local rows = ns.Packs.MAGE.groups
    t.eq(#rows, 1)
    t.eq(rows[1].spell, INTELLECT)
    t.eq(rows[1].aura, { INTELLECT, BRILLIANCE })
    local pack = { groups = rows, dispels = {} }
    local s = choose({ missing("party1", { [INTELLECT] = false }) }, nil, pack)
    t.eq(s, nil, "a warrior: no intellect")
    s = choose({ missing("party1", { [INTELLECT] = false }, { class = "PRIEST", kind = "caster" }) }, nil, pack)
    t.eq(s and s.spell, INTELLECT, "a priest")
    s = choose({ missing("party1", { [INTELLECT] = false }, { class = "HUNTER", kind = "ranged" }) }, nil, pack)
    t.eq(s and s.spell, INTELLECT, "a hunter")
end

tests["group: fortitude for everyone; prayer counts"] = function(t)
    local rows = ns.Packs.PRIEST.groups
    t.eq(#rows, 1)
    t.eq(rows[1].spell, FORTITUDE)
    t.eq(rows[1].aura, { FORTITUDE, PRAYER })
    t.eq(rows[1].who, "all")
    local s = choose({ missing("party1", { [FORTITUDE] = false }) }, nil, { groups = rows, dispels = {} })
    t.eq(s and s.spell, FORTITUDE, "a warrior")
end

-- ------------------------------------------------------------ group dispels

tests["group dispel: poison and curse on a member, from the pack's own rows"] = function(t)
    local s, trace = choose({ member("party1", { debuffTypes = { Poison = "Made-up Venom" } }) })
    t.eq(s and { s.spell, s.unit, s.member, s.look, s.kind } or nil, { ABOLISH, "party1", NAME, true, "group" })
    nameFree(t, s, trace, "poison")
    s = choose({ member("party1", { debuffTypes = { Curse = "Made-up Hex" } }) })
    t.eq(s and s.spell, CURSE, "a curse")
    local over = snap({ member("party1", { debuffTypes = { Poison = "Made-up Venom" } }) })
    over.spells[ABOLISH].known = false
    s = ns.Choose(over, druidPack())
    t.eq(s and s.spell, CURE, "Abolish not learned: Cure Poison")
    s = choose({ member("party1", { debuffTypes = { Disease = "Made-up Rot" } }) })
    t.eq(s, nil, "nothing of yours removes a disease")
end

tests["group dispel: before a missing buff; the tank first; types not read: none"] = function(t)
    local s = choose({ missing("party1", { [MOTW] = false }, { debuffTypes = { Poison = "Made-up Venom" } }) })
    t.eq(s and s.spell, ABOLISH, "the poison before the mark")
    s = choose({ member("party1", { debuffTypes = { Poison = "Made-up Venom" } }),
                 member("party2", { role = "TANK", kind = "tank", debuffTypes = { Curse = "Made-up Hex" } }) })
    t.eq(s and { s.spell, s.unit } or nil, { CURSE, "party2" }, "the tank first")
    s = choose({ missing("party1", { [MOTW] = false }, { debuffTypes = "nil" }) })
    t.eq(s and s.spell, MOTW, "debuffs not read: no dispel, the buff")
    s = choose({ member("party1", { debuffTypes = { Poison = "Made-up Venom" }, reach = {} }) })
    t.eq(s, nil, "the cure's reach not known: nothing")
    s = choose({ member("party1", { debuffTypes = { Poison = "Made-up Venom" } }) }, { inCombat = true })
    t.eq(s, nil, "in a fight: nothing")
end

-- ---------------------------------------------------------------- the read

local IDS = { [MOTW] = 1126, [THORNS] = 467, [ABOLISH] = 2893, [CURE] = 8946, [CURSE] = 2782 }

local function fake()
    local c = ns.make.fakeClient()
    c.setCombat(false)
    c.setParty({ { unit = "party1", name = NAME, class = "WARRIOR", role = "NONE", power = 1, dead = false, connected = true } })
    for _, id in pairs(IDS) do c.setReach("party1", id, true) end
    c.setUnitBuffs("party1", { { name = GOTW, left = 1800 } })
    c.setUnitDebuffs("party1", { Poison = "Made-up Venom" })
    return c
end

local function readParty(c, pack)
    return ns.PartyGroup.Read(c, "party", { pack = pack or druidPack(), ids = IDS })
end

tests["group read: each member with kind, reach, buffs and debuff types"] = function(t)
    local got = readParty(fake())
    t.ok(type(got) == "table" and #got == 1, "one member")
    if type(got) ~= "table" or not got[1] then return end
    local m = got[1]
    t.eq({ m.unit, m.name, m.class, m.kind, m.dead, m.connected }, { "party1", NAME, "WARRIOR", "melee", false, true })
    t.eq(m.reach[MOTW], true, "reach of Mark")
    t.eq(m.reach[ABOLISH], true, "reach of the cure")
    t.eq(m.has[MOTW], 1800, "Gift of the Wild counts as Mark")
    t.eq(m.has[THORNS], false, "no Thorns")
    t.eq(m.debuffTypes, { Poison = "Made-up Venom" })
end

tests["group read: not out of a fight, no such read, or not read: nil"] = function(t)
    local c = fake()
    c.setCombat(true)
    t.eq(readParty(c), nil, "in a fight: not read")
    c = fake()
    c.setParty(nil)
    t.eq(readParty(c), nil, "the client does not say")
    c = fake()
    c.party = nil
    t.eq(readParty(c), nil, "no such read")
    c = fake()
    c.setParty({})
    t.eq(readParty(c), {}, "read, and alone")
    c = fake()
    c.setUnitBuffs("party1", nil)
    c.setReach("party1", IDS[MOTW], nil)
    c.setUnitDebuffs("party1", nil)
    local got = readParty(c)
    local m = type(got) == "table" and got[1] or {}
    t.eq(m.has and m.has[MOTW], nil, "buffs not known: nil, never missing")
    t.eq(m.reach and m.reach[MOTW], nil, "reach not known: nil")
    t.eq(m.debuffTypes, nil, "debuffs not known: nil")
end

tests["group read: the snapshot keeps the list, copied"] = function(t)
    local got = readParty(fake())
    local s = ns.SnapshotOf({ party = got, groupOn = true })
    t.eq(s.groupOn, true)
    t.eq(s.party, got, "the same rows")
    t.ok(s.party ~= got, "a copy")
    t.eq(ns.SnapshotOf({ party = "x" }).party, nil, "not a list: not known")
end

-- ---------------------------------------------------- what the player reads

tests["group words: the caption names the member, live; the diag line does not"] = function(t)
    local view = { pack = true, lockdown = false, snapshot = { dead = false, inCombat = false },
        suggestion = { spell = MOTW, kind = "group", look = true, unit = "party1", member = NAME, step = "group" },
        why = { step = "group", result = "pick" } }
    t.eq(ns.RotationIcon.Words(view), MOTW .. " on " .. NAME)
    local line = ns.Diag.RotationLine("started", view, true)
    t.eq(line, "rotation: suggesting " .. MOTW .. " for party1 (group; look only, nothing cast).")
    t.ok(not tostring(line):find(NAME, 1, true), "no name in the diag line")
    view.suggestion.member = nil
    t.eq(ns.RotationIcon.Words(view), MOTW .. " on party1", "no name read: the unit")
    t.eq(ns.RotationIcon.Words({ suggestion = { spell = MOTW, kind = "buff" } }), nil, "your own buff: no caption")
    t.eq(ns.RotationIcon.Words(nil), nil)
end

tests["group words: the names the read asks are in the capture's name list"] = function(t)
    local listed = {}
    for _, name in ipairs(ns.Diag.NAMES) do listed[name] = true end
    for _, name in ipairs({ "UnitExists", "UnitName", "UnitClass", "UnitGroupRolesAssigned", "UnitPowerType",
        "UnitIsDead", "UnitIsConnected", "C_Spell.IsSpellInRange", "C_UnitAuras.GetAuraDataByIndex" }) do
        t.ok(listed[name] == true, name)
    end
    t.eq(ns.Diag.READ_WORDS.party, "your group")
    t.eq(ns.Diag.READ_WORDS.debuffTypes, "what is on you that you could remove")
end

tests["group: the setting row, on by default, where Flow's import puts it"] = function(t)
    t.eq(ns.PartyGroup.SETTING, "rotation.groupBuffs")
    -- The row is the module's own (as the gathering tracking's is), not one
    -- of Model.ROWS: read it from what the module declares.
    local spec
    ns.PartyGroup.Declare({ Module = function(_, m) spec = m end })
    local row = type(spec) == "table" and type(spec.settings) == "table" and spec.settings[1] or {}
    t.eq({ row.key, row.type, row.default, row.scope }, { ns.PartyGroup.SETTING, "bool", true, "account" })
    t.ok(type(row.label) == "string" and row.label ~= "" and type(row.help) == "string" and row.help ~= "", "label and help")
end

-- Lead section 243 item 2: the help says what the rows do; the priest's and
-- the paladin's dispels remove magic and disease too, not only curses and
-- poisons.
tests["group 243: the setting's help does not narrow the cures to curses and poisons"] = function(t)
    local spec
    ns.PartyGroup.Declare({ Module = function(_, m) spec = m end })
    local row = type(spec) == "table" and type(spec.settings) == "table" and spec.settings[1] or {}
    local help = tostring(row.help):lower()
    t.ok(not help:find("curse or poison", 1, true), "not only curses and poisons: " .. help)
    t.ok(help:find("remove", 1, true) ~= nil, "says something can be removed: " .. help)
    t.ok(help:find("casts nothing", 1, true) ~= nil, "and that it casts nothing: " .. help)
end

-- Lead section 243 item 1: the icon's mark says the key will not cast it.
tests["group 243: the icon's mark is look for a look-only suggestion"] = function(t)
    local I = ns.RotationIcon
    t.eq(I.Mark({ suggestion = { spell = MOTW, kind = "group", look = true, unit = "party1", step = "group" } }), "look")
    t.eq(I.Mark({ suggestion = { spell = MOTW, kind = "buff", step = "list" } }), nil, "your own buff: no mark")
    t.eq(I.Mark({ suggestion = { spell = "Wrath", step = "farOpener" } }), "far", "out of range: still far")
    t.eq(I.Mark({ suggestion = { spell = MOTW, look = false, step = "group" } }), nil, "look must be true")
end

-- Item 19 (lead section 247, N61 "no tank-first order"): your group's buffs
-- go tank first, then the healer, then everyone else in roster order, each
-- member's missing buff before the next member's. The role is what the
-- read gave (kind); a role not read is roster order, never a guess.
tests["group 19: the tank's missing buff first, wherever the tank is in the roster"] = function(t)
    local s = choose({
        missing("party1", { [MOTW] = false }, { class = "ROGUE", kind = "melee" }),
        member("party2", { class = "MAGE", kind = "caster", name = OTHER }),
        missing("party3", { [THORNS] = false }, { role = "TANK", kind = "tank", name = OTHER }),
    })
    t.eq(s and { s.spell, s.unit } or nil, { THORNS, "party3" }, "the tank's Thorns before the rogue's Mark")
end

tests["group 19: the healer before the rest; ties keep roster order"] = function(t)
    local s = choose({
        missing("party1", { [MOTW] = false }, { class = "ROGUE", kind = "melee" }),
        missing("party2", { [MOTW] = false }, { class = "PRIEST", role = "HEALER", kind = "healer", name = OTHER }),
    })
    t.eq(s and s.unit, "party2", "the healer first")
    s = choose({
        missing("party1", { [MOTW] = false }, { class = "ROGUE", kind = "melee" }),
        missing("party2", { [MOTW] = false }, { name = OTHER }),
    })
    t.eq(s and s.unit, "party1", "two of the same kind: roster order")
end

tests["group 19: role not read: roster order, never a guess"] = function(t)
    local s = choose({
        missing("party1", { [MOTW] = false }, { class = "ROGUE", kind = "melee", role = "nil" }),
        missing("party2", { [THORNS] = false }, { role = "nil", kind = "melee", name = OTHER }),
    })
    t.eq(s and { s.spell, s.unit } or nil, { MOTW, "party1" }, "a warrior with no role read is not taken for the tank")
end

tests["group: look only - nothing in it casts, targets or clicks"] = function(t)
    for name in pairs(ns.PartyGroup) do
        local n = tostring(name):lower()
        t.ok(not (n:find("cast") or n:find("target") or n:find("click") or n:find("press")),
            "no acting function: " .. n)
    end
end

return tests

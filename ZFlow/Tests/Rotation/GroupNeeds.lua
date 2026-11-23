local _, ns = ...

-- P-PARTY (lead section 354 item 3): who in your group needs what, with
-- the ones out of range said so, sorted by need (Rotation/Group.lua
-- G.Needs, G.NeedLine, and the group step's pick and note).
-- Look only: nothing here casts, targets or clicks. The member's name is
-- only in `member`, for a live line: never in a reason or a trace note.
-- Made-up names, units and ids, test only. Not seen in game.
--
-- Red before the code: ns.PartyGroup.Needs and NeedLine do not exist, the
-- step takes the tank's fading buff before another member's missing one,
-- and a member out of range leaves the note "everyone has your buffs".

local G = ns.PartyGroup
local tests = {}

local MOTW, THORNS = "Mark of the Wild", "Thorns"
local ABOLISH, CURSE = "Abolish Poison", "Remove Curse"
local NAME, OTHER = "Fennimore", "Quillaby"   -- made up
local ALL = { MOTW, THORNS, ABOLISH, CURSE }

-- A member as the read hands it on: in reach of every spell, alive, online,
-- every buff up for ten minutes, unless `over` says otherwise ("nil"
-- leaves a field out). has / reach: per spell, over the defaults.
local function member(unit, over, has, reach)
    local m = { unit = unit, name = NAME, class = "ROGUE", role = "NONE", kind = "melee",
                dead = false, connected = true, reach = {}, has = {} }
    for _, n in ipairs(ALL) do
        m.reach[n] = true
        m.has[n] = 600
    end
    for k, v in pairs(over or {}) do
        if v == "nil" then m[k] = nil else m[k] = v end
    end
    for spell, v in pairs(has or {}) do
        if v == "nil" then m.has[spell] = nil else m.has[spell] = v end
    end
    for spell, v in pairs(reach or {}) do
        if v == "nil" then m.reach[spell] = nil else m.reach[spell] = v end
    end
    return m
end

local function snap(party, over)
    local s = { dead = false, inCombat = false, hostile = false, groupOn = true, party = party, spells = {} }
    for _, n in ipairs(ALL) do s.spells[n] = { known = true, usable = true, onCooldown = false } end
    for k, v in pairs(over or {}) do
        if v == "nil" then s[k] = nil else s[k] = v end
    end
    return s
end

local function pack()
    return {
        groups = {
            { spell = MOTW, who = "all", minutes = 30, rebuff = 60, evidence = "first guess" },
            { spell = THORNS, who = { "tank", "WARRIOR" }, minutes = 10, rebuff = 30, evidence = "first guess" },
        },
        dispels = {
            { spell = CURSE, types = { Curse = true }, evidence = "first guess" },
            { spell = ABOLISH, types = { Poison = true }, evidence = "first guess" },
        },
    }
end

local function needs(party, over, prefs)
    if type(G.Needs) ~= "function" then return nil end
    return G.Needs(snap(party, over), pack(), prefs)
end

-- { spell, unit, need } of each, in order.
local function brief(list)
    local out = {}
    for i, n in ipairs(list or {}) do out[i] = { n.spell, n.unit, n.need } end
    return out
end

local function choose(party, over)
    return ns.Choose(snap(party, over), pack())
end

local function lastNote(trace)
    local row = trace[#trace]
    return row and row.step, row and row.note
end

-- ---------------------------------------------------------------- the list

tests["group needs: nobody needs anything: an empty list, nothing unsure"] = function(t)
    t.ok(type(G.Needs) == "function", "PartyGroup.Needs")
    local list, unsure = needs({ member("party1"), member("party2") })
    t.eq(list, {}, "empty")
    t.eq(unsure, false, "all read")
end

tests["group needs: a cure, then a missing buff, then one running out"] = function(t)
    local list = needs({
        member("party1", nil, { [MOTW] = 40 }),
        member("party2", { name = OTHER }, { [MOTW] = false }),
        member("party3", { debuffTypes = { Poison = "Made-up Venom" } }),
    })
    t.eq(brief(list), {
        { ABOLISH, "party3", "cure" },
        { MOTW, "party2", "missing" },
        { MOTW, "party1", "low" },
    })
    t.eq(list and list[1] and list[1].detail, "poison", "the cure says what it removes")
    t.eq(list and list[3] and list[3].left, 40, "running out says the seconds left")
    t.eq(list and list[2] and list[2].member, OTHER, "the name, for a live line")
end

tests["group needs: of the same need, the tank, the healer, then roster order"] = function(t)
    local list = needs({
        member("party1", nil, { [MOTW] = false }),
        member("party2", { role = "HEALER", kind = "healer" }, { [MOTW] = false }),
        member("party3", { role = "TANK", kind = "tank" }, { [MOTW] = false, [THORNS] = false }),
    })
    t.eq(brief(list), {
        { MOTW, "party3", "missing" },
        { THORNS, "party3", "missing" },
        { MOTW, "party2", "missing" },
        { MOTW, "party1", "missing" },
    })
end

tests["group needs: running out: the least time left first, then the tank"] = function(t)
    local list = needs({
        member("party1", nil, { [MOTW] = 10 }),
        member("party2", { role = "TANK", kind = "tank" }, { [MOTW] = 50 }),
        member("party3", nil, { [MOTW] = 50 }),
    })
    t.eq(brief(list), {
        { MOTW, "party1", "low" },
        { MOTW, "party2", "low" },
        { MOTW, "party3", "low" },
    })
end

tests["group needs: out of range is kept in its place and said so"] = function(t)
    local list, unsure = needs({
        member("party1", nil, { [MOTW] = false }, { [MOTW] = false }),
        member("party2", { name = OTHER }, { [MOTW] = 30 }),
    })
    t.eq(brief(list), { { MOTW, "party1", "missing" }, { MOTW, "party2", "low" } }, "by need, not by range")
    t.eq(list and list[1] and list[1].reach, false, "out of range")
    t.eq(list and list[2] and list[2].reach, true, "in range")
    t.eq(unsure, false)
    list = needs({ member("party1", { debuffTypes = { Curse = "Made-up Hex" } }, nil, { [CURSE] = false }) })
    t.eq(brief(list), { { CURSE, "party1", "cure" } }, "a cure out of range too")
    t.eq(list and list[1] and list[1].reach, false)
end

tests["group needs: not read is never a need; it is unsure"] = function(t)
    for _, case in ipairs({
        { "reach not known", member("party1", nil, { [MOTW] = false }, { [MOTW] = "nil" }) },
        { "buff not known", member("party1", nil, { [MOTW] = "nil" }) },
        { "dead not known", member("party1", { dead = "nil" }, { [MOTW] = false }) },
    }) do
        local list, unsure = needs({ case[2] })
        t.eq(list, {}, case[1] .. ": no need")
        t.eq(unsure, true, case[1] .. ": unsure")
    end
    local list, unsure = needs({ member("party1", { dead = true }, { [MOTW] = false }) })
    t.eq(list, {}, "dead: no need")
    t.eq(unsure, false, "and that is known")
    list = needs({ member("party1", { connected = false }, { [MOTW] = false }) })
    t.eq(list, {}, "offline: no need")
    list = needs({ member("party1", nil, { [MOTW] = true }) })
    t.eq(list, {}, "up with the time not known: covered")
end

tests["group needs: only what is yours to cast: known, not switched off, ready"] = function(t)
    local party = { member("party1", { class = "WARRIOR" }, { [MOTW] = false, [THORNS] = false }) }
    t.eq(brief(needs(party)), { { MOTW, "party1", "missing" }, { THORNS, "party1", "missing" } }, "both, so this test can fail")
    t.eq(brief(needs(party, { spells = { [MOTW] = { known = true, usable = true, onCooldown = false } } })),
        { { MOTW, "party1", "missing" } }, "Thorns not known")
    t.eq(brief(needs(party, nil, { skip = { [MOTW] = true } })), { { THORNS, "party1", "missing" } }, "Mark switched off")
    t.eq(brief(needs({ member("party1", nil, { [THORNS] = false }) })), {}, "Thorns is not for a rogue")
end

tests["group needs: one cure for one kind of harm: the first row of yours that removes it"] = function(t)
    local p = pack()
    p.dispels[#p.dispels + 1] = { spell = "Cure Poison", types = { Poison = true }, evidence = "first guess" }
    local s = snap({ member("party1", { debuffTypes = { Poison = "Made-up Venom" } }) })
    s.spells["Cure Poison"] = { known = true, usable = true, onCooldown = false }
    s.party[1].reach["Cure Poison"] = true
    local list = type(G.Needs) == "function" and G.Needs(s, p) or nil
    t.eq(brief(list), { { ABOLISH, "party1", "cure" } }, "not a line for each spell")
end

tests["group needs: no group, a group not read, or no pack: an empty list"] = function(t)
    t.ok(type(G.Needs) == "function", "PartyGroup.Needs")
    if type(G.Needs) ~= "function" then return end
    t.eq(G.Needs(snap({}), pack()), {}, "nobody")
    t.eq(G.Needs(snap("nil", { party = "nil" }), pack()), {}, "not read")
    t.eq(G.Needs(nil, pack()), {}, "no snapshot")
    t.eq(G.Needs(snap({ member("party1", nil, { [MOTW] = false }) }), nil), {}, "no pack")
    t.eq(G.Needs(snap({ 7, "x", { name = NAME } }), pack()), {}, "rows that are no members")
end

-- --------------------------------------------------------------- the words

tests["group needs: a line for each, with the unit, never the name"] = function(t)
    t.ok(type(G.NeedLine) == "function", "PartyGroup.NeedLine")
    if type(G.NeedLine) ~= "function" then return end
    local m = { spell = MOTW, unit = "party2", member = NAME, need = "missing", reach = true }
    t.eq(G.NeedLine(m), "Mark of the Wild for party2: missing")
    m.reach = false
    t.eq(G.NeedLine(m), "Mark of the Wild for party2: missing, out of range")
    t.eq(G.NeedLine({ spell = MOTW, unit = "party1", need = "low", left = 40, reach = true }),
        "Mark of the Wild for party1: running out")
    t.eq(G.NeedLine({ spell = ABOLISH, unit = "party3", need = "cure", detail = "poison", reach = true }),
        "Abolish Poison for party3: poison")
    t.eq(G.NeedLine({ spell = ABOLISH, unit = "party3", need = "cure", detail = "poison", reach = false }),
        "Abolish Poison for party3: poison, out of range")
    t.eq(G.NeedLine(nil), nil, "nothing for nothing")
    t.eq(G.NeedLine({ unit = "party1", need = "missing" }), nil, "no spell: no line")
end

-- ---------------------------------------------------------------- the step

tests["group needs step: a missing buff before the tank's fading one"] = function(t)
    local s = choose({
        member("party1", { role = "TANK", kind = "tank" }, { [MOTW] = 30 }),
        member("party2", { name = OTHER }, { [MOTW] = false }),
    })
    t.eq(s and { s.spell, s.unit, s.reason } or nil, { MOTW, "party2", "Mark of the Wild for party2: missing" })
    t.eq(s and s.look, true, "look only")
    t.eq(s and s.member, OTHER, "the name for the caption")
end

tests["group needs step: of those fading, the one with the least time left"] = function(t)
    local s = choose({
        member("party1", { role = "TANK", kind = "tank" }, { [MOTW] = 50 }),
        member("party2", { name = OTHER }, { [MOTW] = 10 }),
    })
    t.eq(s and { s.spell, s.unit, s.reason } or nil, { MOTW, "party2", "Mark of the Wild for party2: running out" })
end

tests["group needs step: the first need in range is the pick; one out of range is passed over"] = function(t)
    local s = choose({
        member("party1", nil, { [MOTW] = false }, { [MOTW] = false }),
        member("party2", { name = OTHER }, { [MOTW] = 30 }),
    })
    t.eq(s and { s.spell, s.unit } or nil, { MOTW, "party2" })
end

tests["group needs step: everyone in need out of range: nothing, and the note says who"] = function(t)
    local s, trace = choose({
        member("party1", nil, { [MOTW] = false }, { [MOTW] = false }),
        member("party2", { name = OTHER }, { [MOTW] = false }, { [MOTW] = false }),
    })
    t.eq(s, nil, "nothing to cast from here")
    local step, note = lastNote(trace)
    t.eq(step, "group")
    t.eq(note, "Mark of the Wild for party1: missing, out of range (and 1 more)")
    t.ok(not tostring(note):find(NAME, 1, true) and not tostring(note):find(OTHER, 1, true), "no name in the note")
    s, trace = choose({ member("party1", nil, { [MOTW] = false }, { [MOTW] = false }) })
    step, note = lastNote(trace)
    t.eq(note, "Mark of the Wild for party1: missing, out of range", "one: no count")
    t.eq(s, nil)
end

tests["group needs step: the old notes stand: all covered, and not known for some"] = function(t)
    local _, trace = choose({ member("party1") })
    local _, note = lastNote(trace)
    t.eq(note, "everyone has your buffs")
    _, trace = choose({ member("party1", nil, { [MOTW] = "nil" }) })
    _, note = lastNote(trace)
    t.eq(note, "your buffs on your group: not known for some")
end

return tests

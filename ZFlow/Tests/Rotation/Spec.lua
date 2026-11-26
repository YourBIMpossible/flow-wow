-- Tests for ZFlow/Rotation/Spec.lua (G31): the spec word, which names the
-- levelling spec a class pack recommends and why, then the role you chose;
-- and the line said once when you reach the level talents open at. Nothing
-- is read from talents and nothing is changed: unspent points wait for
-- probe ZP2. Not tested in game.
local _, ns = ...

local Sp = ns.RotationSpec
local Ro = ns.RotationRole
local tests = {}

local CLASS = "TESTCLASS"

-- A hand-written pack: two roles named, no healing part, damage recommended.
local function pack()
    return {
        roles = {
            dps = { name = "Claws", evidence = "test" },
            tank = { name = "Hide", evidence = "test" },
        },
        levelling = { role = "dps", why = { "Claws kill fast.", "Hide is for groups." }, evidence = "first guess" },
        spells = {},
        lists = { default = {} },
    }
end

local function joined(lines) return table.concat(lines, "\n") end

-- ------------------------------------------------------------------ names
tests["spec: names"] = function(t)
    t.eq(Sp.NAME, "rotationSpec")
    t.eq(Sp.WORD, "spec")
    t.eq(Sp.TALENT_LEVEL, 10)
    t.eq(type(Sp.HELP), "string")
    t.eq(type(Sp.UNLOCKED), "string")
    t.ok(Sp.UNLOCKED:find("talents unlocked", 1, true), "the level line says talents unlocked")
end

-- ------------------------------------------------------------ recommended
tests["spec: the recommendation is the pack's levelling row, with the role's own name"] = function(t)
    local rec = Sp.Recommended(pack())
    t.eq(rec.role, "dps")
    t.eq(rec.name, "Claws")
    t.eq(rec.why, { "Claws kill fast.", "Hide is for groups." })
end

tests["spec: no pack, no levelling row, or a role the pack does not name: no recommendation"] = function(t)
    t.eq(Sp.Recommended(nil), nil)
    local p = pack()
    p.levelling = nil
    t.eq(Sp.Recommended(p), nil)
    p = pack()
    p.levelling.role = "heal"
    t.eq(Sp.Recommended(p), nil, "a role with no part is never recommended")
    p = pack()
    p.levelling = "dps"
    t.eq(Sp.Recommended(p), nil)
end

tests["spec: reasons that are not words are left out"] = function(t)
    local p = pack()
    p.levelling.why = { "Kept.", "", 5, "Also kept." }
    t.eq(Sp.Recommended(p).why, { "Kept.", "Also kept." })
    p.levelling.why = nil
    t.eq(Sp.Recommended(p).why, {})
end

-- ------------------------------------------------------------------ lines
tests["spec: the lines name the spec, the role in words, each reason, then your role"] = function(t)
    local lines = Sp.Lines(pack(), "")
    t.eq(lines[1], "recommended levelling spec: Claws (damage).")
    t.eq(lines[2], "Claws kill fast.")
    t.eq(lines[3], "Hide is for groups.")
    t.eq(#lines, 4)
    t.ok(lines[4]:find("no role chosen", 1, true), "the last line is your role: " .. lines[4])
    t.ok(lines[4]:find(ns.id.slash .. " " .. Ro.WORD, 1, true), "and says how to choose one")
end

tests["spec: a role with no name of its own is named in words alone"] = function(t)
    local p = pack()
    p.roles.dps.name = nil
    t.eq(Sp.Lines(p, "")[1], "recommended levelling spec: damage.")
end

tests["spec: the chosen role is the recommended one"] = function(t)
    local lines = Sp.Lines(pack(), "dps")
    t.eq(lines[#lines], "your role is set to damage (Claws), the recommended one.")
end

tests["spec: another role is chosen: said plainly, never as a fault"] = function(t)
    local lines = Sp.Lines(pack(), "tank")
    local last = lines[#lines]
    t.ok(last:find("tanking (Hide)", 1, true), "names the chosen role: " .. last)
    t.ok(last:find("yours to choose", 1, true), "the choice stays the player's: " .. last)
end

tests["spec: a chosen role the pack has no part for"] = function(t)
    local lines = Sp.Lines(pack(), "heal")
    t.ok(lines[#lines]:find("no healing part", 1, true), lines[#lines])
end

tests["spec: a value that is no role counts as none chosen"] = function(t)
    t.eq(Sp.Lines(pack(), "healer"), Sp.Lines(pack(), ""))
    t.eq(Sp.Lines(pack(), nil), Sp.Lines(pack(), ""))
    t.eq(Sp.Lines(pack(), 3), Sp.Lines(pack(), ""))
end

tests["spec: no pack for the class is one line"] = function(t)
    local lines = Sp.Lines(nil, "tank")
    t.eq(#lines, 1)
    t.ok(lines[1]:find("no rotation for your class", 1, true), lines[1])
end

tests["spec: a pack with no recommendation says so, then your role"] = function(t)
    local p = pack()
    p.levelling = nil
    local lines = Sp.Lines(p, "tank")
    t.eq(#lines, 2)
    t.ok(lines[1]:find("no levelling spec is recommended", 1, true), lines[1])
    t.ok(lines[2]:find("tanking (Hide)", 1, true), lines[2])
end

tests["spec: no text spells the old name"] = function(t)
    local all = { Sp.HELP, Sp.UNLOCKED, Sp.NO_CLASS }
    for _, chosen in ipairs({ "", "dps", "heal", "tank" }) do
        all[#all + 1] = joined(Sp.Lines(pack(), chosen))
    end
    all[#all + 1] = joined(Sp.Lines(nil, ""))
    t.eq(joined(all):find("Flow", 1, true), nil)
end

-- ----------------------------------------------------------------- module
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setDead(false)
    c.setClass(opts.class or CLASS)
    local k = ns.Kernel({}, c)
    local diag = ns.Diag.Start(k)
    diag.help = diag.help or {}
    local packs = { [CLASS] = pack() }
    ns.RotationDriver.Declare(k, packs)
    Ro.Declare(k, diag, packs)
    local api = Sp.Declare(k, diag, packs)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api, diag
end

local function line(text) return ns.id.title .. ": " .. text end

-- What one run of the word printed.
local function run(c, diag, rest)
    local before = #c.printed
    diag.commands[Sp.WORD](rest)
    local out = {}
    for i = before + 1, #c.printed do out[#out + 1] = c.printed[i] end
    return out
end

tests["spec module: the word and its help are registered"] = function(t)
    local _, _, _, diag = start()
    t.eq(type(diag.commands[Sp.WORD]), "function")
    t.eq(diag.help[Sp.WORD], Sp.HELP)
end

tests["spec module: the word prints the lines, each with the title"] = function(t)
    local _, c, _, diag = start()
    local out = run(c, diag, "")
    local want = Sp.Lines(pack(), "")
    -- Then the line saying where the role comes from (D-new-7).
    t.eq(#out, #want + 1)
    for i = 1, #want do t.eq(out[i], line(want[i])) end
end

tests["spec module: it says nothing at login"] = function(t)
    local _, c = start()
    local hits = {}
    for _, said in ipairs(c.printed) do
        if tostring(said):find("levelling spec", 1, true) then hits[#hits + 1] = tostring(said) end
    end
    t.eq(hits, {}, "nothing of the spec is said at login")
end

tests["spec module: the word follows the role setting"] = function(t)
    local k, c, _, diag = start()
    k.settings:set(Ro.SETTING, "tank")
    local out = run(c, diag, "")
    t.eq(out[4], line(Sp.Lines(pack(), "tank")[4]))
    k.settings:set(Ro.SETTING, "dps")
    out = run(c, diag, "")
    t.eq(out[4], line("your role is set to damage (Claws), the recommended one."))
end

tests["spec module: the word changes no setting, whatever follows it"] = function(t)
    local k, c, _, diag = start()
    run(c, diag, "tank")
    t.eq(k.settings:get(Ro.SETTING), "", "spec tank sets nothing; role tank does")
end

tests["spec module: a class with no pack"] = function(t)
    local _, c, _, diag = start({ class = "OTHERCLASS" })
    t.eq(run(c, diag, ""), { line(Sp.Lines(nil, "")[1]) })
end

tests["spec module: the class not read yet, then read"] = function(t)
    local _, c, _, diag = start()
    c.setClass(nil)
    t.eq(run(c, diag, ""), { line(Sp.NO_CLASS) })
    c.setClass(CLASS)
    t.eq(run(c, diag, "")[1], line("recommended levelling spec: Claws (damage)."))
end

tests["spec module: the class read raising, then recovering"] = function(t)
    local _, c, _, diag = start()
    local real = c.class
    c.class = function() error("class read failed (test)") end
    t.eq(run(c, diag, ""), { line(Sp.NO_CLASS) })
    c.class = real
    t.eq(run(c, diag, "")[1], line("recommended levelling spec: Claws (damage)."))
end

tests["spec module: reaching the talent level says talents unlocked, then the lines"] = function(t)
    local _, c = start()
    local before = #c.printed
    c.fire("PLAYER_LEVEL_UP", Sp.TALENT_LEVEL)
    local want = Sp.Lines(pack(), "")
    -- Talents unlocked, the lines, then where the role comes from (D-new-7).
    t.eq(#c.printed - before, #want + 2)
    t.eq(c.printed[before + 1], line(Sp.UNLOCKED))
    for i = 1, #want do t.eq(c.printed[before + 1 + i], line(want[i])) end
    t.eq(c.printed[before + #want + 2], line(Sp.SourceLines(pack(), "", nil)[1]))
end

tests["spec module: any other level says nothing"] = function(t)
    local _, c = start()
    local before = #c.printed
    c.fire("PLAYER_LEVEL_UP", Sp.TALENT_LEVEL - 1)
    c.fire("PLAYER_LEVEL_UP", Sp.TALENT_LEVEL + 1)
    c.fire("PLAYER_LEVEL_UP", 60)
    t.eq(#c.printed, before)
end

tests["spec module: a level-up that names no level is never taken for the talent level"] = function(t)
    local _, c = start()
    c.setLevel(Sp.TALENT_LEVEL)
    local before = #c.printed
    c.fire("PLAYER_LEVEL_UP")
    c.fire("PLAYER_LEVEL_UP", "ten")
    t.eq(#c.printed, before, "the event's own level is the only one used")
end

tests["spec module: the talent level with no pack says only talents unlocked"] = function(t)
    local _, c = start({ class = "OTHERCLASS" })
    local before = #c.printed
    c.fire("PLAYER_LEVEL_UP", Sp.TALENT_LEVEL)
    t.eq(#c.printed - before, 1)
    t.eq(c.printed[#c.printed], line(Sp.UNLOCKED))
end

-- ------------------------------------------------ D-new-7: from talents
-- Talent trees as the client gives them: { name, points }. The tree names
-- match the pack's own role names; nothing about talents is written here.
local function trees(claws, hide)
    return { { name = "Claws", points = claws }, { name = "Hide", points = hide } }
end

tests["spec talents: the tree with the most points names the role"] = function(t)
    local role, tree = Sp.FromTalents(pack(), trees(5, 2))
    t.eq(role, "dps")
    t.eq(tree, "Claws")
    role = Sp.FromTalents(pack(), trees(1, 9))
    t.eq(role, "tank")
end

tests["spec talents: no points, a tie, no read or a tree the pack has no part for: nothing"] = function(t)
    t.eq(Sp.FromTalents(pack(), trees(0, 0)), nil)
    t.eq(Sp.FromTalents(pack(), trees(4, 4)), nil, "a tie names no role")
    t.eq(Sp.FromTalents(pack(), nil), nil)
    t.eq(Sp.FromTalents(nil, trees(3, 0)), nil)
    t.eq(Sp.FromTalents(pack(), { { name = "Fangs", points = 7 } }), nil)
    t.eq(Sp.FromTalents(pack(), { { name = 5, points = "x" } }), nil)
end

-- Real packs: the game's tree names, which are not the pack's role names
-- (review CHANGES-2). Names as GetTalentTabInfo gives them.
tests["spec talents: a real pack - a Warrior with 31 points in Fury reads damage"] = function(t)
    local warrior = ns.Packs.WARRIOR
    local role, tree, points = Sp.FromTalents(warrior, {
        { name = "Arms", points = 0 }, { name = "Fury", points = 31 }, { name = "Protection", points = 0 },
    })
    t.eq(role, "dps")
    t.eq(tree, "Fury")
    t.eq(points, 31)
    role = Sp.FromTalents(warrior, {
        { name = "Arms", points = 5 }, { name = "Fury", points = 0 }, { name = "Protection", points = 21 },
    })
    t.eq(role, "tank")
end

tests["spec talents: a real pack - 31 points in Feral reads damage, the tree that also tanks"] = function(t)
    local druid = ns.Packs.DRUID
    local role, tree, points = Sp.FromTalents(druid, {
        { name = "Balance", points = 0 }, { name = "Feral", points = 31 }, { name = "Restoration", points = 0 },
    })
    t.eq(role, "dps")
    t.eq(tree, "Feral")
    t.eq(points, 31)
    t.eq(Sp.FromTalents(druid, {
        { name = "Balance", points = 0 }, { name = "Feral", points = 5 }, { name = "Restoration", points = 21 },
    }), "heal")
end

tests["spec source: a tank role set with Feral talents gives no note"] = function(t)
    local druid = ns.Packs.DRUID
    local l = Sp.SourceLines(druid, "tank", {
        { name = "Balance", points = 0 }, { name = "Feral", points = 31 }, { name = "Restoration", points = 0 },
    })
    t.eq(#l, 1, "Feral is one of the tank trees: no note")
    t.ok(l[1]:find("your role setting", 1, true), l[1])
end

tests["spec source: points read that fit no one role never say none were read"] = function(t)
    local l = Sp.SourceLines(pack(), "", trees(4, 4))
    t.eq(#l, 1)
    t.ok(l[1]:find("no role set", 1, true), l[1])
    t.ok(not l[1]:find("no talent points read", 1, true), l[1])
    l = Sp.SourceLines(pack(), "", nil)
    t.ok(l[1]:find("no talent points read", 1, true), l[1])
end

tests["spec source: your setting wins, then talents, then the recommendation"] = function(t)
    local s = Sp.Source(pack(), "tank", trees(6, 0))
    t.eq(s.role, "tank")
    t.eq(s.from, "setting")
    t.eq(s.talents, "dps")
    s = Sp.Source(pack(), "", trees(0, 6))
    t.eq(s.role, "tank")
    t.eq(s.from, "talents")
    s = Sp.Source(pack(), "", nil)
    t.eq(s.role, "dps")
    t.eq(s.from, "default")
    local p = pack()
    p.levelling = nil
    s = Sp.Source(p, "", nil)
    t.eq(s.role, nil)
    t.eq(s.from, "default")
end

tests["spec source: the line names the role and where it came from"] = function(t)
    local l = Sp.SourceLines(pack(), "", trees(0, 6))
    t.eq(#l, 1)
    t.ok(l[1]:find("tanking (Hide)", 1, true), l[1])
    t.ok(l[1]:find("talents", 1, true), l[1])
    l = Sp.SourceLines(pack(), "tank", trees(0, 6))
    t.eq(#l, 1, "talents agree with the setting: no note")
    t.ok(l[1]:find("your role setting", 1, true), l[1])
    l = Sp.SourceLines(pack(), "", nil)
    t.eq(#l, 1)
    t.ok(l[1]:find("damage (Claws)", 1, true), l[1])
    t.ok(l[1]:find("no role set", 1, true), l[1])
end

tests["spec source: a note when the talents fit another role than the one set"] = function(t)
    local l = Sp.SourceLines(pack(), "tank", trees(8, 1))
    t.eq(#l, 2)
    t.ok(l[1]:find("tanking (Hide)", 1, true), l[1])
    t.ok(l[2]:find("damage (Claws)", 1, true), l[2])
    t.ok(l[2]:find("8 points", 1, true), l[2])
end

tests["spec module: the word ends with where the role comes from, read from talents"] = function(t)
    local _, c, _, diag = start()
    c.setTalentTrees(trees(0, 11))
    local out = run(c, diag, "")
    t.eq(out[#out], line(Sp.SourceLines(pack(), "", trees(0, 11))[1]))
end

tests["spec module: your setting wins over talents, and the note says so"] = function(t)
    local k, c, _, diag = start()
    c.setTalentTrees(trees(0, 11))
    k.settings:set(Ro.SETTING, "dps")
    local out = run(c, diag, "")
    local want = Sp.SourceLines(pack(), "dps", trees(0, 11))
    t.eq(#want, 2)
    t.eq(out[#out - 1], line(want[1]))
    t.eq(out[#out], line(want[2]))
    t.eq(k.settings:get(Ro.SETTING), "dps", "the word changes no setting")
end

tests["spec module: a talent read that raises is taken as not known"] = function(t)
    local _, c, _, diag = start()
    c.talentTrees = function() error("talent read failed (test)") end
    local out = run(c, diag, "")
    t.eq(out[#out], line(Sp.SourceLines(pack(), "", nil)[1]))
end

tests["fake client: talent trees are as set, copied"] = function(t)
    local c = ns.make.fakeClient()
    t.eq(c.talentTrees(), nil)
    local set = trees(2, 3)
    c.setTalentTrees(set)
    local got = c.talentTrees()
    t.eq(got, trees(2, 3))
    got[1].points = 99
    t.eq(c.talentTrees()[1].points, 2)
end

return tests

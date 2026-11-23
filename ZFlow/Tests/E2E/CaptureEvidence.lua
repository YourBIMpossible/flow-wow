local _, ns = ...

-- What a feature run on a capture proves (Core/CaptureEvidence.lua), and
-- the replay of recorded calls by their arguments (Capture.Env). Over the
-- whole add-on on the fake client a capture gives. Every capture here is
-- MADE UP. Three results are kept apart: verified on captured inputs,
-- verified with made-up inputs (each named), and not exercised. A run with
-- no Lua problem is a smoke test, never a verification. Offline only; not
-- tested in game.

local tests = {}
local Capture = ns.Capture
local Evidence = ns.CaptureEvidence

local function row(...)
    local n = select("#", ...)
    local r = { ok = true, n = n, types = {}, values = {} }
    for i = 1, n do
        local v = select(i, ...)
        r.types[i] = type(v)
        if v ~= nil then r.values["v" .. i] = v end
    end
    return r
end

-- A made-up capture with every identity and place read: a level 12 Horde
-- paladin in the middle of map 1411, on continent 1.
local function made()
    return {
        format = 1,
        account = {
            diag = {
                names = { build = "1.16.1 (9999)", names = {
                    GetBuildInfo = "function", UnitClass = "function", UnitLevel = "function",
                    UnitFactionGroup = "function", UnitHealthMax = "function",
                    ["C_Map.GetBestMapForUnit"] = "function", ["C_QuestLog.GetNumQuestLogEntries"] = "function",
                } },
                snaps = { {
                    why = "settled", at = 13,
                    reads = { money = 5000, position = { map = 1411, x = 0.5, y = 0.5 }, zone = { cont = 1, zone = 1411 },
                        mapSize = { w = 1000, h = 500 } },
                    shapes = {
                        build = row("1.16.1", "9999", "Nov 1 2026", 16001),
                        class = row("Paladin", "PALADIN", 2),
                        level = row(12),
                        faction = row("Horde", "Horde"),
                        healthMax = row(240),
                        bestMap = row(1411),
                        questEntries = { ok = false, n = 1, types = { "string" }, values = { v1 = "made-up error" } },
                        facing = row(0),
                        form = row(0),
                    },
                } },
            },
        },
    }
end

-- The whole add-on on the capture. prepare(c) makes up what the capture
-- does not hold, before the add-on starts. wrap(env), when given, changes
-- the replayed calls before the client is made.
local function boot(cap, prepare, wrap)
    local env, replay = Capture.Env(cap)
    if wrap then wrap(env) end
    local c = ns.make.fakeClient({ env = env })
    local report = Capture.Apply(c, cap)
    c.setScreen(1024, 768)
    if prepare then prepare(c) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon, report, replay
end

local function problemCount(addon)
    local n = 0
    for _, p in ipairs(addon.problems:list()) do n = n + (p.count or 1) end
    return n
end

-- A feature's words typed; what chat, the arrows and the panels said.
local function run(c, addon, name)
    local feature
    for _, f in ipairs(Capture.FEATURES) do if f.name == name then feature = f end end
    local before = problemCount(addon)
    for i = #c.printed, 1, -1 do c.printed[i] = nil end
    local lines = {}
    for _, words in ipairs(feature.words) do
        c.slashes[ns.id.slash](words)
        c.advance(2, 8)
        for _, a in ipairs(c.arrows or {}) do
            if a.shown then for _, line in ipairs(a.lines or {}) do lines[#lines + 1] = tostring(line) end end
        end
    end
    for _, line in ipairs(c.printed) do lines[#lines + 1] = tostring(line) end
    for _, p in ipairs(c.panels or {}) do
        if p.shown then for _, line in ipairs(p.lines or {}) do lines[#lines + 1] = tostring(line) end end
    end
    return lines, problemCount(addon) - before
end

local function judge(cap, name, prepare, synthetic)
    local c, addon, report = boot(cap, prepare)
    local lines, problems = run(c, addon, name)
    return Evidence.Judge(name, { cap = cap, report = report, lines = lines, problems = problems,
        synthetic = synthetic, addon = addon }), lines
end

local function has(list, name)
    for _, v in ipairs(list or {}) do if v == name then return true end end
    return false
end

local function anyHas(lines, words)
    for _, line in ipairs(lines or {}) do
        if tostring(line):find(words, 1, true) then return true end
    end
    return false
end

-- The requirement lists ------------------------------------------------------

tests["capture evidence: every feature run has a requirement list, and no other"] = function(t)
    local names = {}
    for _, f in ipairs(Capture.FEATURES) do
        names[f.name] = true
        local spec = Evidence.REQUIRES[f.name]
        t.ok(type(spec) == "table", f.name .. ": a list")
        if type(spec) == "table" then
            t.ok(type(spec.asserts) == "string" and spec.asserts ~= "", f.name .. ": says what a verified run shows")
            t.ok(type(spec.captured) == "table" and type(spec.outside) == "table", f.name .. ": captured and outside inputs")
            t.ok(spec.proves ~= nil or spec.idle ~= nil, f.name .. ": a way to tell it did nothing")
        end
    end
    for name in pairs(Evidence.REQUIRES) do t.ok(names[name], name .. ": a feature that is run") end
    -- A captured input is one the loader can give.
    local reads = { [Evidence.SNAPSHOT] = true, [Evidence.SAVED_SETTINGS] = true }
    for _, name in ipairs(Capture.READS) do reads[name] = true end
    for feature, spec in pairs(Evidence.REQUIRES) do
        for _, name in ipairs(spec.captured) do t.ok(reads[name], feature .. ": " .. name .. " is something a capture holds") end
        for _, name in ipairs(spec.outside) do t.ok(not reads[name], feature .. ": " .. name .. " is not something a capture holds") end
    end
    t.eq(Evidence.Judge("no such feature", { lines = { "a line" }, problems = 0 }).verified, false,
        "a feature with no list is never verified")
end

tests["capture evidence: the words for nothing-to-work-on are the modules' own"] = function(t)
    local Try = ns.Nav.Try
    local own = { Try.STRAIGHT, Try.NO_TRAVEL, Try.NO_FLIGHTS, Try.NOT_STARTED,
        Try.WHY["position unknown"], Try.WHY["continent unknown"] }
    for words in pairs(Evidence.REQUIRES.flights.idle) do
        t.ok(anyHas(own, words), "flights: the preview says: " .. words)
    end
    t.ok(Try.SAYS:find(Evidence.REQUIRES.flights.shows[1], 1, true) ~= nil, "flights: the line that shows a way")
    t.ok(Evidence.REQUIRES.banker.idle[ns.ItemPresent.BAGS_UNREAD] ~= nil, "banker: the bags-not-read words")
    -- The rotation and arrow words are built in place (Core/Diag.lua,
    -- UI/Arrow.lua): they are checked by what a run with nothing says.
    local _, lines = judge(made(), "rotation")
    t.ok(anyHas(lines, "rotation: switched off"), "rotation: the switched-off line")
    _, lines = judge(made(), "arrow")
    t.ok(anyHas(lines, "quest step from nothing"), "arrow: the no-step line")
    t.ok(anyHas(lines, "quest log: not read"), "arrow: the no-log line")
end

-- 1. Empty and insufficient captures ---------------------------------------------

tests["capture evidence: an empty capture verifies no feature"] = function(t)
    for _, cap in ipairs({
        { format = 1, account = {}, char = {} },
        { format = 1, account = { diag = { snaps = { {} } } }, char = {} },
    }) do
        local verdicts = {}
        for _, f in ipairs(Capture.FEATURES) do
            local v = judge(cap, f.name)
            verdicts[#verdicts + 1] = v
            t.eq(v.result, Evidence.NOT_EXERCISED, f.name)
            t.eq(v.verified, false, f.name .. ": not verified")
            t.eq(v.recorded, false, f.name .. ": not a recorded result")
            t.ok(#v.missing > 0, f.name .. ": what is missing is named")
            t.eq(v.smoke, true, f.name .. ": it ran with no Lua problem, and that is all")
        end
        t.eq(Evidence.Count(verdicts), { captured = 0, synthetic = 0, notExercised = 5, error = 0 })
        for _, line in ipairs(Evidence.Text(verdicts)) do
            t.ok(line:find("NOT exercised", 1, true) ~= nil, "the report says not exercised")
            t.ok(line:find(": verified", 1, true) == nil, "and never verified")
        end
    end
end

tests["capture evidence: a Lua problem is an error, not a verification"] = function(t)
    local v = Evidence.Judge("banker", { cap = made(), report = { set = {} }, lines = { "a list" }, problems = 1,
        synthetic = { "bag items" } })
    t.eq({ v.result, v.verified, v.smoke }, { Evidence.ERROR, false, false })
end

-- 2. Identity and place alone ----------------------------------------------------

tests["capture evidence: class, level, faction and place alone do not verify rotation or banker"] = function(t)
    local cap = made()
    local enough = Capture.Evidence(cap, Capture.Apply(ns.make.fakeClient(), cap))
    t.eq(enough, true, "the capture has every baseline read")

    local rotation = judge(cap, "rotation")
    t.eq({ rotation.result, rotation.verified }, { Evidence.NOT_EXERCISED, false })
    t.ok(has(rotation.missing, "known spells") and has(rotation.missing, "a target"), "rotation: no spells and no target")
    t.ok(has(rotation.missing, "the rotation setting on"), "rotation: it was switched off")
    t.ok(not has(rotation.missing, "class") and not has(rotation.missing, "level"), "rotation: the class and level were there")

    local banker = judge(cap, "banker")
    t.eq({ banker.result, banker.verified }, { Evidence.NOT_EXERCISED, false })
    t.eq(banker.missing, { "bag items" }, "banker: a capture holds no bag items")

    local arrow = judge(cap, "arrow")
    t.eq({ arrow.result, arrow.verified }, { Evidence.NOT_EXERCISED, false })
    t.ok(has(arrow.missing, "the quest log"), "arrow: no quest log")

    local settings = judge(cap, "settings")
    t.eq({ settings.result, settings.verified }, { Evidence.NOT_EXERCISED, false })
    t.eq(settings.missing, { Evidence.SAVED_SETTINGS }, "settings: none saved in this capture")
end

tests["capture evidence: saying a made-up input was given does not make an idle run a verification"] = function(t)
    -- The test claims spells and a target but supplies none: the run still
    -- says switched off, and that decides it.
    local v = judge(made(), "rotation", nil, { "known spells", "a target" })
    t.eq({ v.result, v.verified }, { Evidence.NOT_EXERCISED, false })
    v = judge(made(), "banker", nil, { "bag items" })
    t.eq({ v.result, v.verified }, { Evidence.NOT_EXERCISED, false })
end

-- 3. The flight preview ---------------------------------------------------------

local CORNERS = "the map's place in the world"
local function corners(c)
    c.setMapCorners(1411, { cont = 1, ox = 0, oy = 0, ex = 1000, ey = 0, sx = 0, sy = 500 })
end

tests["capture evidence: the flight preview is made-up inputs, never a recorded flight"] = function(t)
    -- On the capture alone the preview has no way to show.
    local alone = judge(made(), "flights")
    t.eq({ alone.result, alone.verified, alone.recorded }, { Evidence.NOT_EXERCISED, false, false })
    t.ok(has(alone.missing, CORNERS), "the capture does not say where the map lies")

    -- With the map's place made up, Travel gives a way for the made-up step.
    local v, lines = judge(made(), "flights", corners, { CORNERS })
    t.ok(anyHas(lines, "Preview: Travel says: "), "Travel gave a way")
    t.eq({ v.result, v.verified }, { Evidence.SYNTHETIC, true })
    t.eq(v.recorded, false, "a preview is not a flight taken in the game")
    t.ok(has(v.synthetic, CORNERS), "the made-up input of the test is named")
    t.ok(has(v.synthetic, "a made-up far quest step (preview command)"), "the made-up step of the preview is named")
    t.ok(has(v.synthetic, "a made-up flight point (preview command)"), "the made-up flight point of the preview is named")
    local text = Evidence.Text({ v })[1]
    t.ok(text:find("made-up inputs", 1, true) ~= nil, "the report says made-up")
    t.ok(text:find("not a recorded real-game result", 1, true) ~= nil, "the report says not recorded")
    t.ok(text:find("captured inputs", 1, true) == nil, "the report does not say captured")
    t.eq(Evidence.Count({ v }), { captured = 0, synthetic = 1, notExercised = 0, error = 0 })

    -- Even a run that names no made-up input cannot be a captured result:
    -- the preview command makes up its own step and flight point.
    local forced = Evidence.Judge("flights", { cap = made(), report = { set = { "position", "zone" } },
        lines = { "Preview: Travel says: Fly to somewhere." }, problems = 0, synthetic = { CORNERS } })
    t.ok(forced.result ~= Evidence.CAPTURED and forced.recorded == false, "never captured, never recorded")
end

-- 4. Argument-sensitive reads -----------------------------------------------------

tests["capture replay: a recorded answer is given only for the recorded arguments"] = function(t)
    local cap = made()
    local env, replay = Capture.Env(cap)
    local c = ns.make.fakeClient({ env = env })
    t.eq({ c.raw("UnitClass", "player") }, { true, "Paladin", "PALADIN", 2 }, "the player: as recorded")
    t.eq({ c.raw("UnitClass", "target") }, { true }, "another unit: no answer, not the answer for the player")
    t.eq({ c.raw("UnitClass", "party1") }, { true })
    t.eq({ c.raw("UnitClass") }, { true }, "no unit: no answer")
    t.eq({ c.raw("UnitClass", "player", "extra") }, { true }, "more arguments than recorded: no answer")
    t.eq({ c.raw("UnitLevel", "player") }, { true, 12 })
    t.eq({ c.raw("UnitLevel", "pet") }, { true }, "the level of a pet was never recorded")
    t.eq({ c.raw("UnitFactionGroup", "target") }, { true })
    t.eq({ c.raw("UnitHealthMax", "target") }, { true }, "the health of a target is not that of the player")
    t.eq({ c.raw("C_Map.GetBestMapForUnit", "player") }, { true, 1411 })
    t.eq({ c.raw("C_Map.GetBestMapForUnit", "party1") }, { true }, "the map of another unit was never recorded")
    -- A call recorded with no argument answers for no argument only: an
    -- item, a spell or an index was never asked.
    t.eq({ c.raw("GetBuildInfo") }, { true, "1.16.1", "9999", "Nov 1 2026", 16001 })
    t.eq({ c.raw("GetBuildInfo", 5) }, { true }, "an argument it was not recorded with")
    -- A recorded failure fails for the recorded arguments, and only those.
    t.eq({ c.raw("C_QuestLog.GetNumQuestLogEntries") }, { false, "made-up error" })
    t.eq({ c.raw("C_QuestLog.GetNumQuestLogEntries", 3) }, { true })
    -- What was asked and not answered is counted.
    t.eq(replay.UnitClass, { answered = 1, unanswered = 4 })
    t.eq(replay.UnitLevel, { answered = 1, unanswered = 1 })
    t.eq(replay["C_Map.GetBestMapForUnit"], { answered = 1, unanswered = 1 })
    t.eq(replay.GetBuildInfo, { answered = 1, unanswered = 1 })
end

-- The diag word on a booted add-on, and the recorded calls it asked:
-- asked (answered) and unanswered in all, and by[path] for each call.
local function diagAsks(c, replay)
    c.slashes[ns.id.slash]("diag")
    c.advance(2, 8)
    local asked, unanswered, by = 0, 0, {}
    for path, count in pairs(replay) do
        by[path] = { answered = count.answered, unanswered = count.unanswered }
        asked = asked + count.answered
        unanswered = unanswered + count.unanswered
    end
    return asked, unanswered, by
end

tests["capture replay: the recorded arguments are the ones the diag asks with"] = function(t)
    for key in pairs(Capture.ARGS) do
        t.ok(Capture.CALLS[key] ~= nil, key .. ": a recorded call")
    end
    -- The whole add-on on the capture: its diag asks every recorded call
    -- again. Had Capture.ARGS drifted from Core/Diag.lua, a call would go
    -- unanswered here.
    local c, _, _, replay = boot(made())
    local asked, unanswered, by = diagAsks(c, replay)
    t.ok(asked > 0, "the diag asked recorded calls")
    t.eq(unanswered, 0, "calls the diag made with arguments the loader does not hold (count)")
    for _, path in ipairs({ "UnitClass", "UnitLevel", "UnitFactionGroup", "UnitHealthMax", "C_Map.GetBestMapForUnit" }) do
        t.ok(by[path] and by[path].answered > 0, path .. ": asked with the recorded arguments")
    end
end

-- MyBuddy CE-01: what is counted is the diag word, not the whole boot.
tests["capture replay: an ask with other arguments before the diag word is not counted against it"] = function(t)
    -- Asked at boot, before the add-on starts and while it starts, with
    -- arguments the capture does not hold: another unit, a pet.
    local booting = { on = true }
    local c, _, _, replay = boot(made(), function(c0)
        c0.raw("UnitClass", "target")
        c0.raw("C_Map.GetBestMapForUnit", "party1")
    end, function(env)
        local real = env.UnitLevel
        env.UnitLevel = function(...)
            if booting.on then real("pet") end
            return real(...)
        end
    end)
    booting.on = false
    local before = 0
    for _, count in pairs(replay) do before = before + count.unanswered end
    t.ok(before >= 2, "the boot asked with other arguments: " .. before)
    local asked, unanswered = diagAsks(c, replay)
    t.ok(asked > 0, "the diag asked recorded calls")
    t.eq(unanswered, 0, "calls the diag word made with other arguments (count)")
end

tests["capture replay: a diag ask with other arguments is counted"] = function(t)
    -- The boot asks as recorded; then every UnitClass ask is for the target.
    local wrong = { on = false }
    local c, _, _, replay = boot(made(), nil, function(env)
        local real = env.UnitClass
        env.UnitClass = function(...)
            if wrong.on then return real("target") end
            return real(...)
        end
    end)
    wrong.on = true
    local _, unanswered, by = diagAsks(c, replay)
    t.ok(unanswered > 0, "the diag word asked with other arguments: " .. unanswered)
    t.ok(by.UnitClass ~= nil and by.UnitClass.unanswered > 0, "UnitClass: the wrong ask is counted")
end

-- 5. Enough evidence -------------------------------------------------------------

local SPELLS = {
    ["Devotion Aura"] = 465, ["Seal of Righteousness"] = 21084, ["Blessing of Might"] = 19740,
    ["Attack"] = 6603, ["Judgement"] = 20271,
}

tests["capture evidence: rotation with named made-up spells and target is verified as made-up, not captured"] = function(t)
    local cap = made()
    -- The rotation setting is saved state: a capture can hold it.
    cap.char = { settings = { rotation = { enabled = true } } }
    local v, lines = judge(cap, "rotation", function(c)
        c.setDead(false)
        for name, id in pairs(SPELLS) do
            c.setSpellId(name, id)
            c.setSpell(id, { known = true, usable = true })
            c.setSpellCooldown(id, false)
            c.setSpellTexture(id, "tex:" .. name)
        end
        c.setPlayerBuffs({})
        c.setTarget({ exists = true, hostile = true, dead = false })
        c.setInRange(true)
        c.setCombat(true)
    end, { "known spells", "a target" })
    local named = false
    for _, line in ipairs(lines) do
        if line:find("rotation: ", 1, true) then
            for name in pairs(SPELLS) do
                if line:find(name, 1, true) then named = true end
            end
        end
    end
    t.ok(named, "the rotation line names a spell to press")
    t.eq({ v.result, v.verified }, { Evidence.SYNTHETIC, true })
    t.eq(v.synthetic, { "known spells", "a target" }, "each made-up input is named")
    t.eq(v.recorded, false, "made-up spells and target: not a recorded result")
    t.eq(#v.missing, 0)
end

tests["capture evidence: a setting saved in the capture reads back: verified on captured inputs"] = function(t)
    local key = ns.Sound.SETTING
    local cap = made()
    local at = cap.account
    local segs = {}
    for seg in ("settings." .. key):gmatch("[^%.]+") do segs[#segs + 1] = seg end
    for i = 1, #segs - 1 do
        at[segs[i]] = at[segs[i]] or {}
        at = at[segs[i]]
    end
    at[segs[#segs]] = false   -- not the default (true)
    local c, addon, report = boot(cap)
    t.eq(addon.settings:row(key).default, true, "the saved value differs from the default")
    local lines, problems = run(c, addon, "settings")
    local v = Evidence.Judge("settings", { cap = cap, report = report, lines = lines, problems = problems, addon = addon })
    t.eq(addon.settings:get(key), false, "the add-on reads the saved value")
    t.eq({ v.result, v.verified, v.recorded }, { Evidence.CAPTURED, true, true })
    t.eq({ #v.synthetic, #v.missing }, { 0, 0 }, "nothing made up, nothing missing")
    t.eq(Evidence.Text({ v }), { "settings: verified on captured inputs" })
    -- One made-up input and it is no longer a captured result.
    local mixed = Evidence.Judge("settings", { cap = cap, report = report, lines = lines, problems = problems,
        addon = addon, synthetic = { "a made-up screen" } })
    t.eq({ mixed.result, mixed.recorded }, { Evidence.SYNTHETIC, false })
end

return tests

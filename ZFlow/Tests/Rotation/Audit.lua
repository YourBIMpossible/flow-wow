-- Tests for ZFlow/Rotation/Audit.lua (S10): the press audit. The pure
-- parts are checked against Flow 0.35.377 (Modules/Tests.lua, the audit
-- cases). Nothing in the client presses the audit yet, so the module cases
-- call api.press() themselves. Not tested in game.
local _, ns = ...

local Au = ns.Audit
local D = ns.RotationDriver
local tests = {}

local CLASS = "TESTCLASS"
local WRATH, MOONFIRE, THORNS = 5176, 8921, 467 -- test values, not client data

local function has(text, part) return type(text) == "string" and text:find(part, 1, true) ~= nil end

-- ------------------------------------------------------------------ pure
tests["press audit: names and the values taken from Flow"] = function(t)
    t.eq(Au.NAME, "pressAudit")
    t.eq(Au.WINDOW, 0.7)
    t.eq(Au.KEEP, 25)
    t.eq(Au.SHOT_EVERY, 20)
    t.eq(Au.SHOT_MAX, 8)
    t.eq(Au.EVENT, "UNIT_SPELLCAST_SENT")
end

tests["press audit agree: the same spell agrees, nothing to compare is not a disagreement"] = function(t)
    t.ok(Au.Agree("Wrath", "Wrath"), "icon and key the same")
    t.ok(not Au.Agree("Moonfire", "Wrath"), "icon Moonfire, key set to Wrath")
    t.ok(Au.Agree(nil, "Wrath"), "no icon")
    t.ok(Au.Agree("Wrath", nil), "key not known")
end

tests["press audit judge: the four outcomes"] = function(t)
    t.eq(Au.Judge({ icon = "Moonfire", set = "Moonfire" }, "Moonfire"), "ok")
    t.eq(Au.Judge({ icon = "Moonfire", set = "Wrath" }, "Wrath"), "key")
    t.eq(Au.Judge({ icon = "Moonfire", set = "Wrath" }, "Thorns"), "other")
    t.eq(Au.Judge({ icon = "Moonfire", set = "Wrath" }, nil), "nothing")
    t.eq(Au.Judge({ set = "Wrath" }, "Wrath"), "ok", "no icon shown: any cast is not a miss")
end

tests["press audit stamp: a clock time as text, nil when not known"] = function(t)
    t.eq(Au.Stamp(0), "00:00:00Z")
    t.eq(Au.Stamp(3661), "01:01:01Z")
    t.eq(Au.Stamp(86400 + 59), "00:00:59Z")
    t.eq(Au.Stamp(nil), nil)
    t.eq(Au.Stamp("12"), nil)
    t.eq(Au.Stamp(-1), nil)
end

tests["press audit line: one kept disagreement"] = function(t)
    local line = Au.Line({ at = "00:12:31Z", icon = "Moonfire", set = "Wrath", cast = "Wrath",
        combat = true, sinceFight = 0.3 })
    t.ok(has(line, "00:12:31Z icon Moonfire, key set to Wrath, cast Wrath"), line)
    t.ok(has(line, "in a fight for 0.3 s"), line)
    t.ok(has(Au.Line({ icon = "A", set = "B", combat = true }), "; in a fight"), "a fight of unknown length")
    t.ok(has(Au.Line({ icon = "A", set = "B", combat = false }), "not in a fight"), "no fight")
    t.ok(has(Au.Line({ icon = "A", set = "B" }), "fight not known"), "combat not read is not no fight")
    t.ok(has(Au.Line({ icon = "A", set = "B" }), "cast nothing"), "no cast")
    t.ok(has(Au.Line({ icon = "A", set = "B" }), "? icon A"), "no time")
    t.ok(has(Au.Line({ icon = "A", set = "B", shot = true }), "; screenshot"), "a screenshot")
end

tests["press audit report: nothing yet says so"] = function(t)
    t.eq(Au.Report({}), { "no key presses recorded yet." })
    t.eq(Au.Report(nil), { "no key presses recorded yet." })
end

tests["press audit report: the tally, the disagreements, newest first"] = function(t)
    local lines = Au.Report({ counts = { ok = 8, key = 1, nothing = 2 }, disagreed = 1,
        list = { { at = "00:00:01Z", icon = "Moonfire", set = "Wrath", cast = "Wrath", combat = false } } })
    t.ok(has(lines[1], "11 key presses: 8 cast what the icon showed, 1 cast the key's spell"), lines[1])
    t.ok(has(lines[1], "0 cast something else, 2 cast nothing"), lines[1])
    t.ok(has(lines[2], "disagreed at 1 press(es):"), lines[2])
    t.ok(has(lines[3], "icon Moonfire, key set to Wrath"), lines[3])
    t.eq(#lines, 3)
    local none = Au.Report({ counts = { ok = 2 } })
    t.ok(has(none[2], "disagreed at 0 press(es) (the key casts what the icon shows)."), none[2])
    t.eq(#none, 2)
end

tests["press audit report: at most the last twelve disagreements"] = function(t)
    local list = {}
    for i = 1, 20 do list[i] = { at = "n" .. i, icon = "A", set = "B" } end
    local lines = Au.Report({ counts = { key = 20 }, disagreed = 20, list = list })
    t.eq(#lines, 2 + Au.SHOWN)
    t.ok(has(lines[3], "n20 icon"), "newest first")
    t.ok(has(lines[#lines], "n9 icon"), "the twelfth from the end is last")
end

tests["press audit set: the key slot of the form's row"] = function(t)
    local plan = { states = { [0] = { key = "Wrath" }, [1] = { key = "Claw" }, [2] = {} } }
    t.eq(Au.Set(plan, 0), "Wrath")
    t.eq(Au.Set(plan, 1), "Claw")
    t.eq(Au.Set(plan, 2), nil, "a row with no key")
    t.eq(Au.Set(plan, 3), nil, "no row")
    t.eq(Au.Set(plan, nil), nil, "the form not read: not guessed as no form")
    t.eq(Au.Set(nil, 0), nil)
    t.eq(Au.Set({}, 0), nil)
end

tests["press audit cast: the sent spell by the name the press knows"] = function(t)
    local ids = { Wrath = WRATH, Moonfire = MOONFIRE }
    local function idOf(name) return ids[name] end
    local press = { icon = "Moonfire", set = "Wrath" }
    t.eq(Au.Cast(MOONFIRE, press, idOf), "Moonfire")
    t.eq(Au.Cast(WRATH, press, idOf), "Wrath")
    t.eq(Au.Cast(THORNS, press, idOf), "spell " .. THORNS)
    t.eq(Au.Cast(nil, press, idOf), nil, "no id: not known")
    t.eq(Au.Cast("x", press, idOf), nil)
    t.eq(Au.Cast(WRATH, press, nil), "spell " .. WRATH, "no id read")
    t.eq(Au.Cast(WRATH, press, function() error("boom") end), "spell " .. WRATH, "an id read that raises")
end

-- -------------------------------------------------------------- recorder
-- A recorder on a clock the test moves.
local function recorder(opts)
    opts = opts or {}
    local w = { t = 100, shots = 0, data = opts.data or {} }
    local ids = { Wrath = WRATH, Moonfire = MOONFIRE }
    w.rec = Au.New({
        data = w.data,
        now = function() return w.t end,
        stamp = function() return "12:00:00Z" end,
        shoot = opts.shoot ~= false and function()
            w.shots = w.shots + 1
            return true
        end or nil,
        idOf = function(name) return ids[name] end,
    })
    return w
end

tests["press audit recorder: a press where icon and key agree keeps no row"] = function(t)
    local w = recorder()
    t.eq(w.rec.press("Wrath", "Wrath", false), nil)
    w.rec.sent(WRATH)
    t.eq(w.data.counts, { ok = 1 })
    t.eq(#w.data.list, 0)
    t.eq(w.data.disagreed, nil)
    t.eq(w.rec.waiting(), false)
end

tests["press audit recorder: a disagreement is kept with what was cast"] = function(t)
    local w = recorder()
    local r = w.rec.press("Moonfire", "Wrath", true, 0.3)
    t.ok(type(r) == "table", "a row came back")
    t.eq(w.data.disagreed, 1)
    t.eq(w.data.list[1], r)
    t.eq(r.at, "12:00:00Z")
    t.eq(r.icon, "Moonfire")
    t.eq(r.set, "Wrath")
    t.eq(r.combat, true)
    t.eq(r.sinceFight, 0.3)
    t.eq(r.cast, nil, "nothing sent yet")
    w.t = w.t + 0.2
    w.rec.sent(WRATH)
    t.eq(r.cast, "Wrath")
    t.eq(w.data.counts, { key = 1 })
end

tests["press audit recorder: a cast of something else is other, by its id"] = function(t)
    local w = recorder()
    local r = w.rec.press("Moonfire", "Wrath", false)
    w.rec.sent(THORNS)
    t.eq(r.cast, "spell " .. THORNS)
    t.eq(w.data.counts, { other = 1 })
end

tests["press audit recorder: a cast later than the window is not this press's"] = function(t)
    local w = recorder()
    w.rec.press("Wrath", "Wrath", false)
    w.t = w.t + Au.WINDOW + 0.1
    w.rec.sent(WRATH)
    t.eq(w.data.counts, { nothing = 1 })
    t.eq(w.rec.waiting(), false)
end

tests["press audit recorder: a second press settles the first as nothing"] = function(t)
    local w = recorder()
    w.rec.press("Wrath", "Wrath", false)
    w.rec.press("Wrath", "Wrath", false)
    t.eq(w.data.counts, { nothing = 1 })
    w.rec.sent(WRATH)
    t.eq(w.data.counts, { nothing = 1, ok = 1 })
end

tests["press audit recorder: a cast with no press waiting counts nothing"] = function(t)
    local w = recorder()
    w.rec.sent(WRATH)
    t.eq(w.data.counts, {})
end

tests["press audit recorder: a sent spell with no id is nothing, never a guess"] = function(t)
    local w = recorder()
    local r = w.rec.press("Moonfire", "Wrath", false)
    w.rec.sent(nil)
    t.eq(r.cast, nil)
    t.eq(w.data.counts, { nothing = 1 })
end

tests["press audit recorder: at most KEEP disagreements, the oldest dropped"] = function(t)
    local w = recorder({ shoot = false })
    for i = 1, Au.KEEP + 5 do w.rec.press("Moonfire", "Wrath", false, i) end
    t.eq(#w.data.list, Au.KEEP)
    t.eq(w.data.list[1].sinceFight, 6)
    t.eq(w.data.list[Au.KEEP].sinceFight, Au.KEEP + 5)
    t.eq(w.data.disagreed, Au.KEEP + 5)
end

tests["press audit recorder: a screenshot at a disagreement, not more than one every 20 s"] = function(t)
    local w = recorder()
    local a = w.rec.press("Moonfire", "Wrath", false)
    t.eq(a.shot, true)
    w.t = w.t + 5
    local b = w.rec.press("Moonfire", "Wrath", false)
    t.eq(b.shot, nil)
    w.t = w.t + Au.SHOT_EVERY
    local c = w.rec.press("Moonfire", "Wrath", false)
    t.eq(c.shot, true)
    t.eq(w.shots, 2)
end

tests["press audit recorder: at most SHOT_MAX screenshots a session"] = function(t)
    local w = recorder()
    for _ = 1, Au.SHOT_MAX + 3 do
        w.rec.press("Moonfire", "Wrath", false)
        w.t = w.t + Au.SHOT_EVERY + 1
    end
    t.eq(w.shots, Au.SHOT_MAX)
end

tests["press audit recorder: screenshots switched off, or no screenshot in the client"] = function(t)
    local w = recorder({ data = { shots = false } })
    t.eq(w.rec.press("Moonfire", "Wrath", false).shot, nil)
    t.eq(w.shots, 0)
    local n = recorder({ shoot = false })
    t.eq(n.rec.press("Moonfire", "Wrath", false).shot, nil)
end

tests["press audit recorder: a mark keeps the note and what was held"] = function(t)
    local w = recorder({ shoot = false })
    local r = w.rec.mark("wrong spell", "Moonfire", "Wrath", true)
    t.eq(w.data.marks[1], r)
    t.eq(r.note, "wrong spell")
    t.eq(r.icon, "Moonfire")
    t.eq(r.set, "Wrath")
    t.eq(r.combat, true)
    t.eq(w.rec.mark("", nil, nil, nil).note, nil)
    local line = Au.MarkLine(r)
    t.ok(has(line, "12:00:00Z wrong spell | icon Moonfire | key set to Wrath | in a fight true"), line)
    t.ok(has(Au.MarkLine({}), "? (no note)"), "an empty mark")
end

tests["press audit recorder: reset clears the rows and keeps the screenshot choice"] = function(t)
    local w = recorder({ data = { shots = false } })
    w.rec.press("Moonfire", "Wrath", false)
    w.rec.mark("x")
    w.rec.reset()
    t.eq(w.data.list, {})
    t.eq(w.data.counts, {})
    t.eq(w.data.marks, {})
    t.eq(w.data.disagreed, nil)
    t.eq(w.data.shots, false)
    t.eq(w.rec.waiting(), false)
end

-- ---------------------------------------------------------------- module
local function pack()
    return {
        spells = { Wrath = { evidence = "test" }, Moonfire = { evidence = "test" } },
        lists = { default = {
            { spell = "Moonfire", target = true, reason = "Moonfire" },
            { spell = "Wrath", target = true, reason = "Wrath" },
        } },
        keys = { none = { key = "Wrath" } },
    }
end

-- The icon shows Moonfire (first in the list); the plain key is set to
-- Wrath: a disagreement at every press.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSpellId("Wrath", WRATH)
    c.setSpellId("Moonfire", MOONFIRE)
    c.setSpell(WRATH, { known = true, usable = true, noPower = false })
    c.setSpell(MOONFIRE, { known = true, usable = true, noPower = false })
    c.setSpellCooldown(WRATH, false)
    c.setSpellCooldown(MOONFIRE, false)
    c.setInRange(WRATH, true)
    c.setInRange(MOONFIRE, true)
    c.target = function() return { exists = true, hostile = true, dead = false } end
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setDead(false)
    c.setClass(CLASS)
    c.setClock(3661)
    if opts.form ~= false then c.setForm(0) end
    local k = ns.Kernel({}, c)
    local diag = { commands = {}, help = {} }
    D.Declare(k, { [CLASS] = pack() })
    local api = Au.Declare(k, diag)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    k.settings:set(D.SETTING, opts.rotation ~= false)
    return { k = k, c = c, api = api, diag = diag }
end

local function tick(c) c.advance(D.EVERY + 0.05, 1) end

tests["press audit module: the words are registered with their help"] = function(t)
    local w = start()
    t.eq(type(w.diag.commands[Au.WORD]), "function")
    t.eq(type(w.diag.commands[Au.MARK]), "function")
    t.eq(w.diag.help[Au.WORD], Au.HELP)
    t.eq(w.diag.help[Au.MARK], Au.MARK_HELP)
end

tests["press audit module: a press where the icon and the key disagree is kept"] = function(t)
    local w = start()
    tick(w.c)
    local r = w.api.press()
    t.ok(type(r) == "table", "a row came back")
    if type(r) ~= "table" then return end
    t.eq(r.icon, "Moonfire")
    t.eq(r.set, "Wrath")
    t.eq(r.combat, false)
    t.eq(r.at, "01:01:01Z")
    w.c.fire(Au.EVENT, "player", nil, nil, WRATH)
    t.eq(r.cast, "Wrath")
    local data = w.api.data()
    t.eq(data.counts, { key = 1 })
    t.eq(data.disagreed, 1)
    t.eq(w.k.store:get("char", Au.PATH), data)
    t.eq(w.k.problems:count(Au.NAME), 0)
end

tests["press audit module: a cast by another unit is not the player's"] = function(t)
    local w = start()
    tick(w.c)
    local r = w.api.press()
    w.c.fire(Au.EVENT, "target", nil, nil, WRATH)
    t.eq(r and r.cast, nil)
    t.eq(w.api.data().counts, {})
end

tests["press audit module: the form not read, the key is not known and nothing disagrees"] = function(t)
    local w = start({ form = false })
    tick(w.c)
    t.eq(w.api.press(), nil)
    w.c.fire(Au.EVENT, "player", nil, nil, MOONFIRE)
    t.eq(w.api.data().counts, { ok = 1 })
    t.eq(w.api.data().disagreed, nil)
end

tests["press audit module: in a fight the last plan is still what the key holds"] = function(t)
    local w = start()
    tick(w.c)
    w.c.setCombat(true)
    w.c.advance(2, 4)
    local r = w.api.press()
    t.ok(type(r) == "table", "a row came back")
    if type(r) ~= "table" then return end
    t.eq(r.set, "Wrath")
    t.eq(r.combat, true)
    t.ok(type(r.sinceFight) == "number" and math.abs(r.sinceFight - 2) < 1e-6,
        "two seconds into the fight, got " .. tostring(r.sinceFight))
end

tests["press audit module: the rotation off, a press has nothing to compare"] = function(t)
    local w = start({ rotation = false })
    w.c.advance(1, 4)
    t.eq(w.api.press(), nil)
    t.eq(w.api.data().disagreed, nil)
end

tests["press audit module: the word reports and resets"] = function(t)
    local w = start()
    tick(w.c)
    local run = w.diag.commands[Au.WORD]
    local n = #w.c.printed
    run("")
    t.ok(has(w.c.printed[#w.c.printed], "no key presses recorded yet."), tostring(w.c.printed[#w.c.printed]))
    t.ok(has(w.c.printed[n + 1], ns.id.title), "said under the addon's title")
    w.api.press()
    w.c.fire(Au.EVENT, "player", nil, nil, WRATH)
    run("")
    local all = table.concat(w.c.printed, "\n", n + 1)
    t.ok(has(all, "1 key presses: 0 cast what the icon showed, 1 cast the key's spell"), all)
    t.ok(has(all, "icon Moonfire, key set to Wrath, cast Wrath"), all)
    run("reset")
    t.eq(w.api.data().counts, {})
    t.eq(w.api.data().list, {})
end

tests["press audit module: mark keeps the note with the icon and the key"] = function(t)
    local w = start()
    tick(w.c)
    w.diag.commands[Au.MARK]("showed moonfire")
    local m = w.api.data().marks[1]
    t.ok(type(m) == "table", "a mark was kept")
    if type(m) ~= "table" then return end
    t.eq(m.note, "showed moonfire")
    t.eq(m.icon, "Moonfire")
    t.eq(m.set, "Wrath")
    t.eq(m.combat, false)
    t.ok(has(w.c.printed[#w.c.printed], "marked."), tostring(w.c.printed[#w.c.printed]))
end

tests["press audit module: it presses nothing and makes no frame"] = function(t)
    local w = start()
    local calls = 0
    for _, name in ipairs({ "secureButton", "icon", "panel" }) do
        local real = w.c[name]
        if type(real) == "function" then
            w.c[name] = function(...)
                calls = calls + 1
                return real(...)
            end
        end
    end
    tick(w.c)
    w.api.press()
    w.c.fire(Au.EVENT, "player", nil, nil, WRATH)
    w.diag.commands[Au.WORD]("")
    t.eq(calls, 0)
end

-- D-26 (lead section 738): the key's press reaches the audit through the
-- client's press read (client.onKeyPress, a CLIENT NEED; set on the fake
-- here), and screenshots are left out: an add-on offers none.
tests["press audit module: a press of the key is counted, through the client's press read"] = function(t)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    local pressed
    c.onKeyPress = function(fn)
        pressed = fn
        return function() pressed = nil end
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(1, 2)
    t.eq(type(pressed), "function", "the audit listens to the key's presses")
    if type(pressed) ~= "function" then return end
    pressed()
    pressed()
    local data = addon.pressAudit.data()
    local n = 0
    for _, v in pairs(type(data) == "table" and data.counts or {}) do n = n + v end
    t.eq(n, 1, "the first press is settled by the second")
end

tests["press audit words: no screenshots are offered"] = function(t)
    t.eq(ns.Audit.HELP:find("shot", 1, true), nil, tostring(ns.Audit.HELP))
    t.eq(ns.Audit.MARK_HELP:find("shot", 1, true), nil)
end

return tests

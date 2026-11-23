-- Tests for ZFlow/Fight/Choices.lua (S9): your casts against the advice.
-- The pure parts are checked against Flow 0.35.377 (Modules/Tests.lua,
-- "choices: your casts set beside Flow's advice"). The module cases fire
-- the cast events by hand on the fake client; that is not proof the game
-- sends them so. Not tested in game.
local _, ns = ...

local Ch = ns.Choices
local D = ns.RotationDriver
local tests = {}

local CLASS = "TESTCLASS"
local WRATH, MOONFIRE, THORNS, OTHER = 5176, 8921, 467, 999 -- test values, not client data

local function has(text, part) return type(text) == "string" and text:find(part, 1, true) ~= nil end
local function close(a, b) return type(a) == "number" and math.abs(a - b) < 0.001 end

-- ------------------------------------------------------------------ pure
tests["choices: names and the values taken from Flow"] = function(t)
    t.eq(Ch.NAME, "choices")
    t.eq(Ch.WORD, "choices")
    t.eq(Ch.PATH, "learned.fights.choices")
    t.eq(Ch.MAX, 60)
    t.eq(Ch.LOOKBACK, 0.3)
    t.eq(Ch.MIN_FIGHTS, 3)
    t.eq(Ch.START, "UNIT_SPELLCAST_START")
    t.eq(Ch.DONE, "UNIT_SPELLCAST_SUCCEEDED")
end

tests["choices kind: advice, key, own"] = function(t)
    t.eq(Ch.Kind("Wrath", "Wrath", "Wrath"), "advice", "cast what was advised")
    t.eq(Ch.Kind("Wrath", "Moonfire", "Wrath"), "key", "pressed the key while the advice was another spell")
    t.eq(Ch.Kind("Entangling Roots", "Wrath", "Wrath"), "own", "something else")
    t.eq(Ch.Kind("Healing Touch", nil, "Wrath"), "own", "nothing advised: your own choice too")
    t.eq(Ch.Kind("Wrath", "Moonfire", nil), "own", "key not known: not counted as the key")
end

tests["choices tags: the situation as short tags"] = function(t)
    local tags = table.concat(Ch.Tags({ opening = true, moving = true, onYou = 1, near = false, hurt = 12, mana = 0.2,
        targetHp = 0.9, attackers = 2, adviceRange = false, adviceCooldown = 4 }), ", ")
    for _, want in ipairs({ "opening cast", "moving", "enemy on you", "target far", "hurt", "low mana",
        "target healthy", "several enemies", "advice out of range", "advice on cooldown" }) do
        t.ok(has(tags, want), "tag: " .. want)
    end
    t.eq(#Ch.Tags({ onYou = 0.5 }), 0, "nothing known: no tags")
    t.eq(#Ch.Tags({}), 0)
    t.eq(#Ch.Tags(nil), 0)
    t.eq(Ch.Tags({ onYou = 0, near = true, targetHp = 0.1, shifted = true, targetCasting = true, adviceUsable = false }),
        { "target casting", "enemy not on you", "target close", "target nearly dead", "shapeshifted", "advice not usable" })
    t.eq(Ch.Tags({ adviceCooldown = true }), { "advice on cooldown" }, "a cooldown known only as yes")
    t.eq(Ch.Tags({ adviceCooldown = 1 }), {}, "a second left is not a cooldown")
    t.eq(Ch.Tags({ adviceCooldown = false, adviceRange = true, adviceUsable = true, hurt = 7 }), {})
end

tests["choices note: every cast counted, a choice adds up"] = function(t)
    local data = { list = {} }
    local none, kind = Ch.Note(data, "Wrath", "Wrath", "Wrath", {}, 1)
    t.eq(none, nil, "followed: counted, not a choice")
    t.eq(kind, "advice")
    local key
    for i = 1, 4 do
        key = Ch.Note(data, "Entangling Roots", "Wrath", "Wrath", i <= 3 and { "enemy on you", "moving" } or { "moving" }, 10 + i)
    end
    local keyKey, keyKind = Ch.Note(data, "Wrath", "Moonfire", "Wrath", { "opening cast" }, 20)
    t.eq(key, "own: Entangling Roots < Wrath")
    t.eq(keyKey, "key: Wrath < Moonfire")
    t.eq(keyKind, "key")
    t.eq(data.casts, 6, "every cast counted")
    t.eq(data.kinds, { advice = 1, key = 1, own = 4 })
    t.eq(data.list[key].n, 4, "the same choice adds up")
    t.eq(data.list[key].last, 14)
    t.eq(Ch.TagLine(data.list[key]), "moving 100%, enemy on you 75%", "its commonest situations")
    t.eq(Ch.Note({}, "Thorns", nil, nil, nil, nil), "own: Thorns < nothing", "an empty table is filled in")
end

tests["choices tag line: rare situations are left out"] = function(t)
    t.eq(Ch.TagLine({ n = 10, tags = { hurt = 2, moving = 3 } }), "moving 30%")
    t.eq(Ch.TagLine({ n = 4, tags = { a = 4, b = 4, c = 4, d = 4, e = 4 } }, 2), "a 100%, b 100%")
    t.eq(Ch.TagLine({ n = 1 }), "")
end

tests["choices trim: over the limit the rarest go, then the oldest"] = function(t)
    local data = { list = {} }
    for i = 1, 4 do Ch.Note(data, "Entangling Roots", "Wrath", "Wrath", {}, 10 + i) end
    Ch.Note(data, "Wrath", "Moonfire", "Wrath", {}, 20)
    for i = 1, 5 do Ch.Note(data, "Spell " .. i, "Wrath", "Wrath", {}, 30 + i) end
    t.eq(Ch.Trim(data, 10), 0, "under the limit: nothing dropped")
    t.eq(Ch.Trim(data, 3), 4, "over the limit: the rarest dropped")
    t.ok(data.list["own: Entangling Roots < Wrath"] ~= nil, "the common one stays")
    t.ok(data.list["own: Spell 5 < Wrath"] ~= nil, "of the equal ones the newest stay")
    t.ok(data.list["own: Spell 4 < Wrath"] ~= nil)
    t.ok(data.list["key: Wrath < Moonfire"] == nil, "the oldest of the equal ones went")
end

local function fightsWith(key)
    local fights = {}
    for _ = 1, 3 do fights[#fights + 1] = { type = "normal", duration = 20, v = 12, own = { [key] = 1 } } end
    for _ = 1, 4 do fights[#fights + 1] = { type = "normal", duration = 25, v = 10 } end
    fights[#fights + 1] = { type = "elite", duration = 90, v = 3 } -- another kind of fight: not compared
    return fights
end

tests["choices outcome: fights with a choice beside fights of the same type without it"] = function(t)
    local key = "own: Entangling Roots < Wrath"
    local fights = fightsWith(key)
    local o = Ch.Outcome(key, fights, function(f) return f.v end)
    t.ok(type(o) == "table", "a verdict")
    if type(o) ~= "table" then return end
    t.eq(o.with, 3)
    t.eq(o.without, 4, "the elite fight is not compared")
    t.ok(close(o.speedWith / o.speedWithout, 1.2), "20% faster with it")
    t.ok(close(o.secsWith, 20) and close(o.secsWithout, 25), "how long they lasted")
    t.eq(Ch.Outcome(key, { fights[1], fights[4] }, function(f) return f.v end), nil, "too few fights: no verdict")
    local noSpeed = Ch.Outcome(key, fights, function() return nil end)
    t.eq(noSpeed and noSpeed.speedWith, nil, "no kill speed known: none made up")
    t.ok(noSpeed and close(noSpeed.secsWith, 20), "the lengths are still compared")
end

tests["choices report: the shares, each choice with its situations and outcome"] = function(t)
    local data = { list = {} }
    Ch.Note(data, "Wrath", "Wrath", "Wrath", {}, 1)
    local key
    for i = 1, 4 do
        key = Ch.Note(data, "Entangling Roots", "Wrath", "Wrath", i <= 3 and { "enemy on you", "moving" } or { "moving" }, 10 + i)
    end
    Ch.Note(data, "Wrath", "Moonfire", "Wrath", { "opening cast" }, 20)
    local fights = fightsWith(key)
    local report = table.concat(Ch.Report(data, fights, function(f) return f.v end, "Flow"), "\n")
    t.ok(has(report, "6 casts in fights: 17% what Flow advised, 17% your key while it advised another spell, 67% your own choice"), report)
    t.ok(has(report, "Entangling Roots when Flow advised Wrath: 4x. Mostly: moving 100%, enemy on you 75%. Kill speed +20% in the 3 fights with it (4 without)"), report)
    t.ok(has(report, "  your own choices:"), report)
    t.ok(has(report, "  your key instead of the advice:"), report)
    t.ok(has(report, "Wrath when Flow advised Moonfire: 1x. Mostly: opening cast 100%"), report)
    local bySecs = table.concat(Ch.Report(data, fights, nil, "Flow"), "\n")
    t.ok(has(bySecs, "Fights with it lasted 20 s, without 25 s (3 and 4 fights)"), bySecs)
    t.ok(not has(bySecs, "Kill speed"), "no kill speed without a value")
    local plain = table.concat(Ch.Report(data, nil, nil, nil), "\n")
    t.ok(has(plain, "what the rotation advised"), plain)
end

tests["choices report: nothing recorded says so"] = function(t)
    t.eq(Ch.Report({ list = {} }, {}, nil, "Flow"), { "no casts recorded yet: fight a few mobs with the rotation on." })
    t.eq(#Ch.Report(nil, nil, nil, nil), 1)
end

tests["choices report: at most eight of a kind"] = function(t)
    local data = { list = {} }
    for i = 1, 10 do Ch.Note(data, "Spell " .. i, "Wrath", "Wrath", {}, i) end
    t.eq(#Ch.Report(data, {}, nil, "Flow"), 2 + Ch.SHOWN, "the shares, the heading and eight choices")
end

tests["choices advice back: an instant is judged against what showed when you pressed"] = function(t)
    t.eq(Ch.AdviceBack("Wrath", "Moonfire", 10.0, 10.1, 0.3), "Moonfire", "changed 0.1 s ago")
    t.eq(Ch.AdviceBack("Wrath", "Moonfire", 10.0, 11.0, 0.3), "Wrath", "changed a second ago")
    t.eq(Ch.AdviceBack("Wrath", nil, nil, 5, 0.3), "Wrath", "never changed")
    t.eq(Ch.AdviceBack("Wrath", "Moonfire", 10.0, nil, 0.3), "Wrath", "the time not known: the current advice")
    t.eq(Ch.AdviceBack("Wrath", nil, 10.0, 10.1, 0.3), nil, "nothing was advised a moment ago")
end

tests["choices key spell: the form's row of the plan, nil when not known"] = function(t)
    local plan = { states = { [0] = { key = "Wrath" }, [1] = { key = "Maul" }, [2] = { key = "" } } }
    t.eq(Ch.KeySpell(plan, 0), "Wrath")
    t.eq(Ch.KeySpell(plan, 1), "Maul")
    t.eq(Ch.KeySpell(plan, 2), nil, "an empty key")
    t.eq(Ch.KeySpell(plan, 3), nil, "no row")
    t.eq(Ch.KeySpell(plan, nil), nil, "form not read")
    t.eq(Ch.KeySpell(nil, 0), nil, "no plan")
end

tests["choices situation: from the snapshot, not known stays out"] = function(t)
    t.eq(Ch.Situation(nil, "Wrath", nil, true), { opening = true })
    t.eq(Ch.Situation({}, "Wrath", 0, false), { opening = false, shifted = false, targetCasting = false })
    local s = Ch.Situation({
        targetCasting = "Heal", targetOnYou = true, targetNear = false, hurt = 9,
        spells = { Wrath = { inRange = false, usable = false, onCooldown = true } },
    }, "Wrath", 1, false)
    t.eq(s, { opening = false, shifted = true, targetCasting = true, onYou = 1, near = false, hurt = 9,
        adviceRange = false, adviceUsable = false, adviceCooldown = true })
    local fine = Ch.Situation({ targetOnYou = false, spells = { Wrath = { inRange = true, usable = true, onCooldown = false } } },
        "Wrath", nil, false)
    t.eq(fine, { opening = false, targetCasting = false, onYou = 0 })
    t.eq(Ch.Situation({ spells = {} }, nil, nil, false), { opening = false, targetCasting = false }, "no advice")
end

tests["choices since: how long the tally has run"] = function(t)
    t.eq(Ch.Since(1000, 1000 + 3600), "today")
    t.eq(Ch.Since(1000, 1000 + 86400), "the last day")
    t.eq(Ch.Since(1000, 1000 + 86400 * 5 + 7), "the last 5 days")
    t.eq(Ch.Since(nil, 1000), nil)
    t.eq(Ch.Since(1000, nil), nil)
    t.eq(Ch.Since(2000, 1000), nil, "a clock that went back")
end

-- ---------------------------------------------------------------- module
-- The rotation suggests Moonfire (first in the list); the plain key is set
-- to Wrath. Thorns is a pack spell that is never suggested.
local function pack()
    return {
        spells = { Wrath = { evidence = "test" }, Moonfire = { evidence = "test" }, Thorns = { evidence = "test" } },
        lists = { default = {
            { spell = "Moonfire", target = true, reason = "Moonfire" },
            { spell = "Wrath", target = true, reason = "Wrath" },
        } },
        keys = { none = { key = "Wrath" } },
    }
end

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSpellId("Wrath", WRATH)
    c.setSpellId("Moonfire", MOONFIRE)
    c.setSpellId("Thorns", THORNS)
    for _, id in ipairs({ WRATH, MOONFIRE, THORNS }) do
        c.setSpell(id, { known = true, usable = true, noPower = false })
        c.setSpellCooldown(id, false)
        c.setInRange(id, true)
    end
    c.target = function() return { exists = true, hostile = true, dead = false } end
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setDead(false)
    c.setClass(CLASS)
    c.setClock(5000)
    if opts.form ~= false then c.setForm(0) end
    if opts.rank then c.setTargetRank(opts.rank) end
    local k = ns.Kernel({}, c)
    local diag = { commands = {}, help = {} }
    D.Declare(k, { [CLASS] = pack() })
    local api = Ch.Declare(k, diag, { [CLASS] = pack() })
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    if opts.rotation ~= false then k.settings:set(D.SETTING, true) end
    return { k = k, c = c, api = api, diag = diag }
end

local function tick(c) c.advance(D.EVERY + 0.05, 1) end

-- A fight with the rotation's view up before and in it. The advice first
-- showed at the first tick; the wait puts that change further back than
-- Ch.LOOKBACK, so an instant is judged against the advice showing now and
-- not against the nothing that showed before the first tick.
local function fight(w)
    tick(w.c)
    w.c.setCombat(true)
    tick(w.c)
    w.c.advance(Ch.LOOKBACK + 0.2, 1)
end

local function land(w, id, guid, unit) w.c.fire(Ch.DONE, unit or "player", guid, id) end

tests["choices module: the word is registered with its help"] = function(t)
    local w = start()
    t.eq(type(w.diag.commands[Ch.WORD]), "function")
    t.eq(w.diag.help[Ch.WORD], Ch.HELP)
    t.eq(w.k.problems:count(Ch.NAME), 0)
end

tests["choices module: casting the advice is counted and is no choice"] = function(t)
    local w = start()
    fight(w)
    land(w, MOONFIRE)
    local d = w.api.data()
    t.eq(d.casts, 1)
    t.eq(d.kinds, { advice = 1 })
    t.eq(d.list, {})
    t.eq(w.k.problems:count(Ch.NAME), 0)
end

tests["choices module: the key while another spell was advised"] = function(t)
    local w = start()
    fight(w)
    land(w, WRATH)
    local d = w.api.data()
    t.eq(d.kinds, { key = 1 })
    local rec = d.list["key: Wrath < Moonfire"]
    t.ok(type(rec) == "table", "the choice is kept")
    if type(rec) ~= "table" then return end
    t.eq(rec.n, 1)
    t.eq(rec.cast, "Wrath")
    t.eq(rec.advice, "Moonfire")
    t.eq(rec.last, 5000, "the clock when it was last seen")
    t.eq(rec.tags["opening cast"], 1, "the first cast of the fight")
    t.eq(rec.tags["shapeshifted"], nil, "no form")
end

tests["choices module: another pack spell is your own choice"] = function(t)
    local w = start()
    fight(w)
    land(w, MOONFIRE)
    land(w, THORNS)
    local d = w.api.data()
    t.eq(d.casts, 2)
    t.eq(d.kinds, { advice = 1, own = 1 })
    local rec = d.list["own: Thorns < Moonfire"]
    t.ok(type(rec) == "table" and rec.n == 1, "the choice is kept")
    t.eq(rec and rec.tags["opening cast"], nil, "not the first cast of the fight")
    t.eq(w.api.fight().own, { ["own: Thorns < Moonfire"] = 1 }, "the fight remembers it")
    t.eq(w.api.fight().casts, 2)
end

tests["choices module: the key not known, the key spell is your own choice"] = function(t)
    local w = start({ form = false })
    fight(w)
    land(w, WRATH)
    local d = w.api.data()
    t.eq(d.kinds, { own = 1 }, "not read is not counted as the key")
    t.ok(d.list["own: Wrath < Moonfire"] ~= nil)
end

tests["choices module: outside a fight nothing is counted"] = function(t)
    local w = start()
    tick(w.c)
    land(w, WRATH)
    t.eq(w.api.data().casts, nil)
    t.eq(w.api.fight(), nil)
end

tests["choices module: a cast by another unit is not counted"] = function(t)
    local w = start()
    fight(w)
    land(w, WRATH, nil, "target")
    land(w, WRATH, nil, "pet")
    t.eq(w.api.data().casts, nil)
end

tests["choices module: a spell that is not the pack's is not counted"] = function(t)
    local w = start()
    fight(w)
    land(w, OTHER)
    land(w, nil)
    land(w, "5176")
    t.eq(w.api.data().casts, nil)
end

tests["choices module: the rotation off, nothing is counted"] = function(t)
    local w = start({ rotation = false })
    fight(w)
    land(w, WRATH)
    t.eq(w.api.data().casts, nil, "no advice to set a cast beside")
end

tests["choices module: the setting off, nothing is counted"] = function(t)
    local w = start()
    w.k.settings:set(Ch.SETTING, false)
    fight(w)
    land(w, WRATH)
    t.eq(w.api.data().casts, nil)
    w.k.settings:set(Ch.SETTING, true)
    land(w, WRATH)
    t.eq(w.api.data().casts, 1, "switched on again it counts")
end

tests["choices module: a spell with a cast time is judged by the advice when it began"] = function(t)
    local w = start()
    fight(w)
    w.c.fire(Ch.START, "player", "cast-1", MOONFIRE)
    -- The advice moves on to Wrath while the cast runs.
    w.c.setSpell(MOONFIRE, { known = false, usable = false, noPower = false })
    tick(w.c)
    w.c.advance(1, 1)
    land(w, MOONFIRE, "cast-1")
    local d = w.api.data()
    t.eq(d.kinds, { advice = 1 }, "Moonfire was the advice when the cast began")
end

tests["choices module: an instant is judged against the advice a moment before it landed"] = function(t)
    local w = start()
    fight(w)
    w.c.setSpell(MOONFIRE, { known = false, usable = false, noPower = false })
    tick(w.c)
    land(w, MOONFIRE)
    t.eq(w.api.data().kinds, { advice = 1 }, "Moonfire still showed a moment before it landed")
    w.c.advance(1, 1)
    land(w, MOONFIRE)
    t.eq(w.api.data().kinds, { advice = 1, own = 1 }, "a second on, Wrath is the advice and Moonfire your own choice")
    t.ok(w.api.data().list["own: Moonfire < Wrath"] ~= nil)
end

tests["choices module: a cast begun by another unit is not remembered"] = function(t)
    local w = start()
    fight(w)
    w.c.fire(Ch.START, "target", "cast-9", WRATH)
    land(w, WRATH, "cast-9")
    t.eq(w.api.data().kinds, { key = 1 }, "judged as an instant of your own")
end

tests["choices module: the end of a fight keeps its choices, its length and the rank"] = function(t)
    local w = start({ rank = "elite" })
    fight(w)
    land(w, THORNS)
    w.c.advance(10, 1)
    w.c.setCombat(false)
    local d = w.api.data()
    t.eq(#d.fights, 1)
    local row = d.fights[1]
    t.eq(row.type, "elite")
    t.eq(row.own, { ["own: Thorns < Moonfire"] = 1 })
    t.ok(type(row.duration) == "number" and row.duration >= 10, "how long it lasted")
    t.eq(w.api.fight(), nil)
    land(w, THORNS)
    t.eq(d.casts, 1, "after the fight nothing is counted")
end

tests["choices module: a rank not read is not known, never normal"] = function(t)
    local w = start()
    fight(w)
    land(w, MOONFIRE)
    w.c.setCombat(false)
    local d = w.api.data()
    t.eq(#d.fights, 1)
    t.eq(d.fights[1].type, Ch.UNKNOWN_TYPE)
    t.eq(d.fights[1].own, {}, "a fight where the advice was followed")
end

tests["choices module: a fight with no counted cast is not kept"] = function(t)
    local w = start()
    fight(w)
    land(w, OTHER)
    w.c.setCombat(false)
    t.eq(w.api.data().fights, {})
end

tests["choices module: only so many fights are kept"] = function(t)
    local w = start()
    tick(w.c)
    for _ = 1, Ch.FIGHTS + 3 do
        w.c.setCombat(true)
        land(w, MOONFIRE)
        w.c.setCombat(false)
    end
    t.eq(#w.api.data().fights, Ch.FIGHTS)
    t.eq(w.api.data().casts, Ch.FIGHTS + 3)
end

tests["choices module: saved per character where the import puts it"] = function(t)
    local w = start()
    fight(w)
    land(w, WRATH)
    t.eq(w.k.store:get("char", Ch.PATH), w.api.data())
    t.eq(w.api.data().since, 5000, "counted from the first use")
end

tests["choices module: the word prints the tally under the title"] = function(t)
    local w = start()
    fight(w)
    land(w, WRATH)
    land(w, MOONFIRE)
    w.c.setClock(5000 + 86400 * 2)
    w.c.printed = {}
    w.diag.commands[Ch.WORD]("")
    local text = table.concat(w.c.printed, "\n")
    t.ok(has(text, w.k.id.title .. ": your casts against the advice (the last 2 days):"), text)
    t.ok(has(text, "2 casts in fights: 50% what " .. w.k.id.title .. " advised, 50% your key while it advised another spell, 0% your own choice"), text)
    t.ok(has(text, "Wrath when " .. w.k.id.title .. " advised Moonfire: 1x"), text)
end

tests["choices module: the word with nothing recorded says so"] = function(t)
    local w = start()
    w.c.printed = {}
    w.diag.commands[Ch.WORD]()
    local text = table.concat(w.c.printed, "\n")
    t.ok(has(text, "no casts recorded yet"), text)
end

tests["choices module: the word says when recording is off"] = function(t)
    local w = start()
    w.k.settings:set(Ch.SETTING, false)
    w.c.printed = {}
    w.diag.commands[Ch.WORD]("")
    t.ok(has(table.concat(w.c.printed, "\n"), "recording is switched off in the settings"))
end

tests["choices module: reset forgets the tally and the fights"] = function(t)
    local w = start()
    fight(w)
    land(w, WRATH)
    w.c.setCombat(false)
    w.c.setClock(6000)
    w.c.printed = {}
    w.diag.commands[Ch.WORD](" Reset ")
    local d = w.api.data()
    t.eq(d.casts, nil)
    t.eq(d.kinds, nil)
    t.eq(d.list, {})
    t.eq(d.fights, {})
    t.eq(d.since, 6000)
    t.ok(has(table.concat(w.c.printed, "\n"), "forgot your recorded choices"))
end

tests["choices module: a tally brought over from Flow is added to"] = function(t)
    local w = start()
    local saved = w.k.store:table("char", Ch.PATH)
    saved.casts, saved.kinds, saved.since = 10, { advice = 10 }, 100
    saved.list = {}
    fight(w)
    land(w, MOONFIRE)
    local d = w.api.data()
    t.eq(d.casts, 11)
    t.eq(d.kinds, { advice = 11 })
    t.eq(d.since, 100, "the first day is kept")
    t.eq(d.fights, {}, "the fight list is added when missing")
end

tests["choices module: an instant in the moment the advice first showed is judged against nothing"] = function(t)
    local w = start()
    tick(w.c)
    w.c.setCombat(true)
    land(w, MOONFIRE)
    t.eq(w.api.data().kinds, { own = 1 }, "nothing showed a moment before")
    t.ok(w.api.data().list["own: Moonfire < nothing"] ~= nil)
end

-- P-READS (lead section 248): the client hands a secret event argument on
-- as nil; the fake's fireSecret plays that.
tests["choices module: a secret cast id or spell id comes as nil; nothing breaks or is miscounted"] = function(t)
    local w = start()
    fight(w)
    w.c.fireSecret(Ch.START, "player", w.c.SECRET, MOONFIRE)
    w.c.fireSecret(Ch.DONE, "player", w.c.SECRET, MOONFIRE)
    t.eq(w.api.data().kinds, { advice = 1 }, "the spell known, the cast id not: judged as an instant")
    w.c.fireSecret(Ch.DONE, "player", "cast-2", w.c.SECRET)
    t.eq(w.api.data().casts, 1, "the spell not known: not counted")
    w.c.fireSecret(Ch.DONE, w.c.SECRET, "cast-3", WRATH)
    t.eq(w.api.data().casts, 1, "the unit not known: not counted")
    t.eq(w.k.problems:count(Ch.NAME), 0)
end

return tests

local _, ns = ...
-- N68 (research order 8, row 13): selective state-change alerts
-- (UI/Alerts.lua). A prompt that turns up on the advisor is a rule that
-- turned true; when the player has alerts on, and that kind of prompt on,
-- one chat line says it, with one sound if the player asked for that.
-- Nothing at login, nothing for a replaced text, nothing twice in a row
-- for the same prompt. Fake client and a fake prompt source; not tested in
-- game.
local tests = {}

local A = ns.Alerts

-- opts.on, opts.sound: the settings before the prompts come;
-- opts.kinds: { kind = false } to turn kinds off; opts.atStart: prompts
-- added while the add-on starts (login); opts.soundFail: why.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    if opts.soundFail and type(c.setAlertSound) == "function" then c.setAlertSound({ fail = opts.soundFail }) end
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    local advisor = ns.Advisor.Declare(k)
    A.Declare(k)
    k:Module({
        name = "fakePromptSource",
        needs = { ns.Advisor.NAME },
        start = function()
            for _, p in ipairs(opts.atStart or {}) do advisor.Add(p[1], p[2], 0) end
        end,
    })
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    if opts.on then k.settings:set(A.SETTING, true) end
    if opts.sound then k.settings:set(A.SOUND, true) end
    for kind, v in pairs(opts.kinds or {}) do k.settings:set(A.KindKey(kind), v) end
    return k, c, advisor
end

local function settle(c) c.advance(A.SETTLE + 1, 2) end

-- The lines said since index from, without the title.
local function lines(c, from)
    local out = {}
    local head = ns.id.title .. ": "
    for i = from or 1, #c.printed do
        local line = tostring(c.printed[i])
        if line:sub(1, #head) == head then out[#out + 1] = line:sub(#head + 1) end
    end
    return out
end

local function played(c)
    return type(c.alertsPlayed) == "function" and #c.alertsPlayed() or -1
end

tests["alerts: the kinds of prompt, by the id each source gives"] = function(t)
    if not A then t.ok(false, "ns.Alerts"); return end
    t.eq(A.KindOf("l6c.repair"), "repair")
    t.eq(A.KindOf("aps.trainer"), "trainer")
    t.eq(A.KindOf("aps.classQuest"), "trainer")
    t.eq(A.KindOf("aps.rankup.Fireball"), "trainer", "a rank-up prompt is a trainer prompt (AL-2)")
    t.eq(A.KindOf("aps.prof.Mining"), "professions")
    t.eq(A.KindOf("l6d.bank"), "bank")
    t.eq(A.KindOf("gear.merchant.3"), "vendor")
    t.eq(A.KindOf("setup.keys"), "setup")
    t.eq(A.KindOf("attune.progress"), "attune")
    t.eq(A.KindOf("someone.else"), "other", "an id no source here gives")
    t.eq(A.KindOf(nil), "other")
    t.eq(A.KindOf("aps.profx"), "other", "a prefix is matched whole")
    t.eq(A.KindOf("aps.trainerx"), "other", "a whole id is matched whole")
    t.eq(A.KindOf("aps.trainer.2"), "trainer", "a whole id with more parts")
end

tests["alerts: the rule says yes only when on, the kind on, after login and not said lately"] = function(t)
    if not A then t.ok(false, "ns.Alerts"); return end
    t.eq({ A.Decide(true, true, true, false) }, { true })
    t.eq({ A.Decide(false, true, true, false) }, { false, "off" })
    t.eq({ A.Decide(nil, true, true, false) }, { false, "off" }, "not set is off")
    t.eq({ A.Decide(true, false, true, false) }, { false, "kind off" })
    t.eq({ A.Decide(true, true, false, false) }, { false, "at login" })
    t.eq({ A.Decide(true, true, true, true) }, { false, "said lately" })
end

tests["alerts: the rows, off until the player turns them on, filed under general"] = function(t)
    if not A then t.ok(false, "ns.Alerts"); return end
    local k = start()
    local on, sound = k.settings:row(A.SETTING), k.settings:row(A.SOUND)
    t.ok(type(on) == "table" and type(sound) == "table", "both rows declared")
    if type(on) ~= "table" or type(sound) ~= "table" then return end
    t.eq(on.default, false, "alerts off by default")
    t.eq(sound.default, false, "the sound off by default")
    t.eq(on.group, "general")
    t.eq(sound.group, "general")
    t.ok(type(on.synonyms) == "table" and #on.synonyms > 0, "synonyms")
    for _, kind in ipairs(A.KINDS) do
        local row = k.settings:row(A.KindKey(kind.kind))
        t.ok(type(row) == "table", "a row for " .. kind.kind)
        if type(row) == "table" then
            t.eq(row.default, true, kind.kind .. " on, once alerts are on")
            t.eq(row.group, "general", kind.kind)
            t.ok(type(row.synonyms) == "table" and #row.synonyms > 0, kind.kind .. " synonyms")
        end
    end
    t.eq(A.KINDS[#A.KINDS].kind, "other", "every other prompt has a row too")
end

tests["alerts: off by default, a new prompt says nothing"] = function(t)
    if not A then t.ok(false, "ns.Alerts"); return end
    local _, c, advisor = start()
    settle(c)
    local from = #c.printed + 1
    advisor.Add("l6c.repair", "Repair at the next vendor.", 1)
    t.eq(lines(c, from), {}, "nothing said")
    t.eq(played(c), 0, "nothing played")
end

tests["alerts: on, a new prompt is said once; a replaced text is not new"] = function(t)
    if not A then t.ok(false, "ns.Alerts"); return end
    local _, c, advisor = start({ on = true })
    settle(c)
    local from = #c.printed + 1
    advisor.Add("l6c.repair", "Repair at the next vendor.", 1)
    t.eq(lines(c, from), { "Repair at the next vendor." }, "said once")
    advisor.Add("l6c.repair", "Repair now.", 1)
    t.eq(lines(c, from), { "Repair at the next vendor." }, "the replaced text is not said")
    t.eq(played(c), 0, "no sound: the sound setting is off")
end

tests["alerts: prompts there at login say nothing; one after login does"] = function(t)
    if not A then t.ok(false, "ns.Alerts"); return end
    local k, c, advisor = start({ atStart = { { "setup.keys", "Set your keys." } } })
    k.settings:set(A.SETTING, true)
    local from = #c.printed + 1
    advisor.Add("l6d.bank", "Bank your reagents.", 1)
    t.eq(lines(c, from), {}, "still at login: nothing said")
    settle(c)
    advisor.Add("l6c.repair", "Repair at the next vendor.", 1)
    t.eq(lines(c, from), { "Repair at the next vendor." }, "after login: said")
end

tests["alerts: the same prompt back again soon says nothing; after a while it does"] = function(t)
    if not A then t.ok(false, "ns.Alerts"); return end
    local _, c, advisor = start({ on = true })
    settle(c)
    local from = #c.printed + 1
    advisor.Add("l6c.repair", "Repair.", 1)
    advisor.Remove("l6c.repair")
    advisor.Add("l6c.repair", "Repair.", 1)
    t.eq(lines(c, from), { "Repair." }, "once")
    advisor.Add("l6d.bank", "Bank.", 1)
    t.eq(lines(c, from), { "Repair.", "Bank." }, "another prompt is not held back")
    c.advance(A.QUIET + 1, 2)
    advisor.Remove("l6c.repair")
    advisor.Add("l6c.repair", "Repair.", 1)
    t.eq(lines(c, from), { "Repair.", "Bank.", "Repair." }, "said again after a while")
end

tests["alerts: a kind turned off says nothing; the others still do"] = function(t)
    if not A then t.ok(false, "ns.Alerts"); return end
    local _, c, advisor = start({ on = true, kinds = { vendor = false } })
    settle(c)
    local from = #c.printed + 1
    advisor.Add("gear.merchant.1", "This vendor sells an upgrade.", 1)
    advisor.Add("someone.else", "Something new.", 1)
    t.eq(lines(c, from), { "Something new." })
end

tests["alerts: the sound on plays once with the line; off plays nothing"] = function(t)
    if not A then t.ok(false, "ns.Alerts"); return end
    local k, c, advisor = start({ on = true, sound = true })
    settle(c)
    advisor.Add("l6c.repair", "Repair.", 1)
    t.eq(played(c), 1, "one sound")
    advisor.Add("l6c.repair", "Repair now.", 1)
    t.eq(played(c), 1, "a replaced text plays nothing")
    k.settings:set(A.SOUND, false)
    advisor.Add("l6d.bank", "Bank.", 1)
    t.eq(played(c), 1, "the sound off: nothing more")
    k.settings:set(A.SETTING, false)
    k.settings:set(A.SOUND, true)
    advisor.Add("aps.trainer", "Train.", 1)
    t.eq(played(c), 1, "alerts off: no sound either")
end

tests["alerts: a sound the game cannot play is said once, and the lines go on"] = function(t)
    if not A then t.ok(false, "ns.Alerts"); return end
    local _, c, advisor = start({ on = true, sound = true, soundFail = "noCall" })
    settle(c)
    local from = #c.printed + 1
    advisor.Add("l6c.repair", "Repair.", 1)
    advisor.Add("l6d.bank", "Bank.", 1)
    t.eq(lines(c, from), { "Repair.", A.NO_SOUND .. " (the game has no call for it here).", "Bank." })
    t.eq(played(c), 0, "nothing played")
end

tests["alerts: switched off, nothing more is said"] = function(t)
    if not A then t.ok(false, "ns.Alerts"); return end
    local k, c, advisor = start({ on = true })
    settle(c)
    t.eq(k:SwitchOff(A.NAME, "test"), true)
    local from = #c.printed + 1
    advisor.Add("l6c.repair", "Repair.", 1)
    t.eq(lines(c, from), {})
end

tests["alerts: says and plays only; nothing acts in the game"] = function(t)
    if not A then t.ok(false, "ns.Alerts"); return end
    for name in pairs(A) do
        local n = tostring(name):lower()
        t.ok(not (n:find("sell") or n:find("buy") or n:find("click") or n:find("cast") or n:find("secure")
            or n:find("macro")), "no acting function: " .. n)
    end
end

return tests

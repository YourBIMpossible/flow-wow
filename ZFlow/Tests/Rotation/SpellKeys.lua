local _, ns = ...
-- N39, N26 and N27 (P-KEYS slice E), pure: the spells list (Bar, Key or
-- Skip per spell), the prefs it gives the chooser and the key plan, the
-- game-placed spell notice, and the bar a slot belongs to
-- (Rotation/SpellKeys.lua). Hand-made input; made-up spell ids. Not
-- tested in game.
local tests = {}

local function SK() return ns.SpellKeys end

local function ready(t, fn)
    local ok = type(SK()) == "table" and type(SK()[fn]) == "function"
    t.ok(ok, "Rotation/SpellKeys.lua gives SK." .. fn)
    return ok
end

tests["spells list: Skip and Bar split; skip is never suggested, both stay off the key"] = function(t)
    if not ready(t, "Prefs") then return end
    local choose, plan = SK().Prefs({ autoAttack = true, choices = { Judgement = "skip", Exorcism = "bar", ["Holy Light"] = "key" } })
    t.eq(choose.autoAttack, true)
    t.eq(choose.skip, { Judgement = true }, "only Skip is kept from the chooser")
    t.eq(plan.skip, { Judgement = true, Exorcism = true }, "Skip and Bar are kept off the key")
    t.eq(choose.bar, { Exorcism = true }, "Bar spells are named, to show them off the key")
end

tests["spells list: auto attack off goes to the chooser; the list off obeys no choice"] = function(t)
    if not ready(t, "Prefs") then return end
    local choose, plan = SK().Prefs({ autoAttack = false, listOff = true, choices = { Judgement = "skip" } })
    t.eq(choose.autoAttack, false)
    t.eq(choose.skip, {}, "list off: nothing skipped")
    t.eq(plan.skip, {}, "list off: nothing kept off the key")
end

tests["spells list: a choice is bar, key or skip; key is the default and clears the row"] = function(t)
    if not ready(t, "Set") then return end
    local choices = {}
    t.eq(SK().Set(choices, "Judgement", "skip"), true)
    t.eq(choices.Judgement, "skip")
    t.eq(SK().Set(choices, "Judgement", "BAR"), true, "any case")
    t.eq(choices.Judgement, "bar")
    t.eq(SK().Set(choices, "Judgement", "key"), true)
    t.eq(choices.Judgement, nil, "key is the default: no row kept")
    local ok, why = SK().Set(choices, "Judgement", "never")
    t.eq(ok, false, "not a choice")
    t.ok(type(why) == "string", "with a reason")
    t.eq(SK().Set(choices, "", "skip"), false, "no spell named")
end

tests["placed notice: the bar a slot is on, from the old map"] = function(t)
    if not ready(t, "BarOf") then return end
    local bar, n = SK().BarOf(1)
    t.eq(bar, "Action Bar 1"); t.eq(n, 1)
    bar, n = SK().BarOf(12)
    t.eq(bar, "Action Bar 1"); t.eq(n, 12)
    bar, n = SK().BarOf(25)
    t.eq(bar, "Right Bar"); t.eq(n, 1)
    bar, n = SK().BarOf(40)
    t.eq(bar, "Right Bar 2"); t.eq(n, 4)
    bar, n = SK().BarOf(49)
    t.eq(bar, "Bottom Right Bar"); t.eq(n, 1)
    bar, n = SK().BarOf(72)
    t.eq(bar, "Bottom Left Bar"); t.eq(n, 12)
    t.eq(SK().BarOf(13), nil, "a paged slot: not named")
    t.eq(SK().BarOf("3"), nil, "not a number")
end

tests["placed notice: the line names the spell and the place, or the id when the name is not read"] = function(t)
    if not ready(t, "Notice") then return end
    t.eq(SK().Notice("Devotion Aura", 465, 3), "the game put Devotion Aura on Action Bar 1, slot 3")
    t.eq(SK().Notice(nil, 465, 3), "the game put spell 465 on Action Bar 1, slot 3")
    t.eq(SK().Notice("Devotion Aura", 465, 13), "the game put Devotion Aura on your bars, slot 13")
    t.eq(SK().Notice("Devotion Aura", 465, nil), "the game put Devotion Aura on your bars")
end

tests["placed notice: the kept list holds the newest 40"] = function(t)
    if not ready(t, "Remember") then return end
    local list = {}
    for i = 1, 45 do SK().Remember(list, { id = i, slot = i }) end
    t.eq(#list, 40)
    t.eq(list[1].id, 6, "the oldest dropped")
    t.eq(list[40].id, 45)
    SK().Remember(list, "not a row")
    t.eq(#list, 40, "a bad row is not kept")
end

-- SE-3: the swing is read for every class, not only those whose pack has
-- an Attack row (Druid and Paladin). The id is asked of the client by name
-- (client.spellId) when the pack's ids do not have it. Made-up spell id.
local function swingClient(on)
    local c = ns.make.fakeClient()
    c.setSpellId("Attack", 6603)
    c.setCurrentSpell(6603, on)
    c.setLockdown(false)
    return c
end

tests["swing: read with no Attack row in the pack, through the client's spell id"] = function(t)
    local D = ns.RotationDriver
    local extra = { spellKeys = { keyOn = true } }
    t.eq(D.Read(swingClient(true), {}, {}, "dps", extra)("attacking"), true, "swinging")
    t.eq(D.Read(swingClient(false), {}, {}, "dps", extra)("attacking"), false, "not swinging")
    t.eq(D.Read(swingClient(false), {}, {}, "dps", extra)("canStartAttack"), true, "the key may start it")
    t.eq(D.Read(swingClient(true), {}, {}, "dps", extra)("canStartAttack"), false, "already swinging")
end

-- SE-4: the no-auto-attack list kept and the target's name not read: not
-- known (nil), never "gave up"; each such read is counted in extra.counts.
tests["gave up: a target name not read with the list kept is not known, and counted"] = function(t)
    local D = ns.RotationDriver
    local c = ns.make.fakeClient()
    c.setTargetName(nil)
    local counts = {}
    local extra = { spellKeys = { keyOn = true, noAttack = { Dummy = true } }, counts = counts }
    t.eq(D.Read(c, {}, {}, "dps", extra)("engageGaveUp"), nil, "not known")
    t.eq(counts.targetNameUnread, 1, "counted")
    c.targetName = function() error("not now") end
    t.eq(D.Read(c, {}, {}, "dps", extra)("engageGaveUp"), nil, "a read that raises: not known")
    t.eq(counts.targetNameUnread, 2)
    c.setTargetName("Dummy")
    c.targetName = nil
    t.eq(D.Read(c, {}, {}, "dps", extra)("engageGaveUp"), nil, "no read at all: not known")
    local c2 = ns.make.fakeClient()
    c2.setTargetName("Dummy")
    t.eq(D.Read(c2, {}, {}, "dps", extra)("engageGaveUp"), true, "listed and read: gave up")
    c2.setTargetName("Wolf")
    t.eq(D.Read(c2, {}, {}, "dps", extra)("engageGaveUp"), false, "read, not listed")
end

tests["swing: no id from the pack or the client is not known"] = function(t)
    local D = ns.RotationDriver
    local c = ns.make.fakeClient()
    c.setLockdown(false)
    t.eq(D.Read(c, {}, {}, "dps", { spellKeys = { keyOn = true } })("attacking"), nil)
end

return tests

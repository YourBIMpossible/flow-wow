local _, ns = ...

-- Tests for the "rotation" lines of the diag command (RD15, CD2, ST1, RG1,
-- RG2, DF1): the
-- line made from a driver view, one test for each row and the order of the
-- rows, then the lines as the slash command says them over the fake client.
-- Not tested in game.

local D = ns.RotationDriver
local R = ns.Rotation
local Diag = ns.Diag

local CLASS = "TESTCLASS"
local WRATH, MOONFIRE = 5176, 8921

-- A view as the driver holds it, out of a fight with one spell suggested.
-- `over` replaces whole fields ("nil" takes one away); why is made again
-- from what is left.
local function view(over)
    local v = {
        pack = true,
        snapshot = {
            dead = false, inCombat = false, stealthed = false,
            spells = {
                Wrath = { known = true, usable = true, noPower = false, onCooldown = false },
                Moonfire = { known = true, usable = true, noPower = false, onCooldown = false },
            },
        },
        suggestion = { spell = "Moonfire", reason = "Moonfire" },
        trace = { { step = "rotation", result = "pick", spell = "Moonfire", note = "Moonfire" } },
        lockdown = false,
        keys = { ok = true, ops = {} },
        unread = {}, missing = {}, passed = {},
    }
    for key, value in pairs(over or {}) do
        if value == "nil" then v[key] = nil else v[key] = value end
    end
    v.why = D.Why(v.snapshot, v.trace, v.keys, v.lockdown)
    return v
end

local function snap(over)
    local s = view().snapshot
    for key, value in pairs(over) do
        if value == "nil" then s[key] = nil else s[key] = value end
    end
    return s
end

local function refused(why)
    return { ok = false, refused = why, reason = ns.cast.REFUSED[why], ops = {} }
end

local function line(v, state, enabled)
    if type(Diag.RotationLine) ~= "function" then return "Diag.RotationLine is missing" end
    if enabled == nil then enabled = true end
    return Diag.RotationLine(state or "started", v, enabled)
end

local tests = {}

tests["rotation diag RD15: no line on a kernel without the driver"] = function(t)
    t.ok(type(Diag.RotationLine) == "function", "Diag.RotationLine exists")
    if type(Diag.RotationLine) ~= "function" then return end
    t.eq(Diag.RotationLine(nil, nil, true), nil)
end

tests["rotation diag RD15: not running names the module's state"] = function(t)
    t.eq(line(view(), "off"), "rotation: not running (off).")
    t.eq(line(nil, "failed"), "rotation: not running (failed).")
end

tests["rotation diag RD15: no view held is switched off, or no reading yet"] = function(t)
    t.eq(line(nil, "started", false), "rotation: switched off; nothing suggested.")
    t.eq(line(nil, "started", true), "rotation: no reading yet.")
end

tests["rotation diag RD15: no pack"] = function(t)
    t.eq(line({ pack = false, trace = {}, why = { pack = false } }),
        "rotation: class not known, or no spell list for it; nothing suggested.")
end

tests["rotation diag RD15: dead not known"] = function(t)
    local v = view({ snapshot = snap({ dead = "nil" }), suggestion = "nil",
        trace = { { step = "dead", result = "stop", note = "not known whether you are dead" } } })
    t.eq(line(v), "rotation: not known whether you are dead; nothing suggested.")
end

tests["rotation diag RD15: dead"] = function(t)
    local v = view({ snapshot = snap({ dead = true }), suggestion = "nil",
        trace = { { step = "dead", result = "stop", note = "dead" } } })
    t.eq(line(v), "rotation: dead; nothing suggested.")
end

tests["rotation diag RD15: a fight not known counts as a fight, as the chooser counts it"] = function(t)
    local s = snap({ inCombat = "nil" })
    t.eq(R.InFight(s), true, "the chooser's own answer for not known")
    t.eq(line(view({ snapshot = s })),
        "rotation: fight not known, counted as a fight; suggesting Moonfire (rotation).")
end

tests["rotation diag RD15: lockdown not known says the key refusal in its own words"] = function(t)
    local v = view({ lockdown = "nil", keys = refused("lockdownUnknown") })
    t.eq(v.why.reason, ns.cast.REFUSED.lockdownUnknown)
    t.eq(line(v), "rotation: not known whether you are in a fight (keys unchanged); "
        .. "suggesting Moonfire (rotation).")
end

tests["rotation diag RD15: lockdown says the key refusal in its own words"] = function(t)
    local v = view({ snapshot = snap({ inCombat = true }), lockdown = true, keys = refused("lockdown") })
    t.eq(line(v), "rotation: in a fight (keys unchanged); suggesting Moonfire (rotation).")
end

-- RG1 -------------------------------------------------------------------
-- A fight is when the suggestion matters most: none of the three fight
-- rows may end the line.

local NOTHING = { { step = "rotation", result = "skip", note = "nothing ready" } }

tests["rotation diag RG1: a fight not known still shows the suggestion, or why there is none"] = function(t)
    local s = snap({ inCombat = "nil" })
    t.eq(line(view({ snapshot = s })),
        "rotation: fight not known, counted as a fight; suggesting Moonfire (rotation).")
    t.eq(line(view({ snapshot = s, suggestion = "nil", trace = NOTHING })),
        "rotation: fight not known, counted as a fight; nothing to suggest (nothing ready).")
end

tests["rotation diag RG1: a fight not known with the keys held says both"] = function(t)
    local s = snap({ inCombat = "nil" })
    t.eq(line(view({ snapshot = s, lockdown = "nil", keys = refused("lockdownUnknown") })),
        "rotation: fight not known, counted as a fight (keys unchanged); suggesting Moonfire (rotation).")
    t.eq(line(view({ snapshot = s, lockdown = true, keys = refused("lockdown") })),
        "rotation: fight not known, counted as a fight (keys unchanged); suggesting Moonfire (rotation).")
end

tests["rotation diag RG1: lockdown not known still shows the suggestion, or why there is none"] = function(t)
    local over = { lockdown = "nil", keys = refused("lockdownUnknown") }
    t.eq(line(view(over)),
        "rotation: not known whether you are in a fight (keys unchanged); suggesting Moonfire (rotation).")
    over.suggestion, over.trace = "nil", NOTHING
    t.eq(line(view(over)),
        "rotation: not known whether you are in a fight (keys unchanged); nothing to suggest (nothing ready).")
end

tests["rotation diag RG1: in a fight still shows the suggestion, or why there is none"] = function(t)
    local over = { snapshot = snap({ inCombat = true }), lockdown = true, keys = refused("lockdown") }
    t.eq(line(view(over)), "rotation: in a fight (keys unchanged); suggesting Moonfire (rotation).")
    over.suggestion, over.trace = "nil", NOTHING
    t.eq(line(view(over)), "rotation: in a fight (keys unchanged); nothing to suggest (nothing ready).")
end

tests["rotation diag RG1: the fight clause comes before the suggestion and the spells not read, and a kept view still says so"] = function(t)
    local over = { snapshot = snap({ inCombat = true }), lockdown = true, keys = refused("lockdown"),
        unread = { "Wrath" } }
    t.eq(line(view(over)), "rotation: in a fight (keys unchanged); suggesting Moonfire (rotation)."
        .. " 1 spell not read; it is skipped.")
    over.unread = {}
    local v = view(over)
    v.stale = true
    t.eq(line(v), "rotation: in a fight (keys unchanged); suggesting Moonfire (rotation)."
        .. " An earlier reading: the last read failed.")
end

tests["rotation diag RG1: dead, no pack and no view are still the whole line in a fight"] = function(t)
    local over = { snapshot = snap({ inCombat = true, dead = true }), lockdown = true, keys = refused("lockdown"),
        suggestion = "nil", trace = { { step = "dead", result = "stop", note = "dead" } } }
    t.eq(line(view(over)), "rotation: dead; nothing suggested.")
    over.snapshot = snap({ inCombat = "nil", dead = "nil" })
    t.eq(line(view(over)), "rotation: not known whether you are dead; nothing suggested.")
    t.eq(line({ pack = false, trace = {}, why = { pack = false }, lockdown = true }),
        "rotation: class not known, or no spell list for it; nothing suggested.")
    t.eq(line(nil, "started", true), "rotation: no reading yet.")
end

tests["rotation diag RD15: spells not read are counted, after the suggestion"] = function(t)
    t.eq(line(view({ unread = { "Starfire", "Thorns" } })),
        "rotation: suggesting Moonfire (rotation). 2 spells not read; they are skipped.")
    t.eq(line(view({ unread = { "Thorns" } })),
        "rotation: suggesting Moonfire (rotation). 1 spell not read; it is skipped.")
    t.eq(line(view({ unread = { "Thorns" }, missing = "nil" })),
        "rotation: suggesting Moonfire (rotation). 1 spell not read; it is skipped.",
        "a view without the missing list: every spell not read is counted as not read")
end

-- C2 (RESEARCH-blockC): a low-level character knows a handful of the pack's
-- spells. The ones it has not learned have no id (view.missing); they must
-- not hide the suggestion or the reason there is none.
tests["rotation diag C2: spells not learned do not hide the suggestion"] = function(t)
    t.eq(line(view({ unread = { "Starfire", "Thorns" }, missing = { "Starfire", "Thorns" } })),
        "rotation: suggesting Moonfire (rotation). 2 spells not learned or not found by name; they are skipped.")
    t.eq(line(view({ unread = { "Thorns" }, missing = { "Thorns" } })),
        "rotation: suggesting Moonfire (rotation). 1 spell not learned or not found by name; it is skipped.")
end

tests["rotation diag C2: spells not learned do not hide why nothing is suggested"] = function(t)
    local v = view({ unread = { "Thorns" }, missing = { "Thorns" }, suggestion = "nil",
        trace = { { step = "rotation", result = "skip", note = "nothing ready" } } })
    t.eq(line(v), "rotation: nothing to suggest (nothing ready). 1 spell not learned or not found by name; it is skipped.")
    local over = { snapshot = snap({ inCombat = true }), lockdown = true, keys = refused("lockdown"),
        unread = { "Thorns" }, missing = { "Thorns" } }
    t.eq(line(view(over)), "rotation: in a fight (keys unchanged); suggesting Moonfire (rotation)."
        .. " 1 spell not learned or not found by name; it is skipped.")
end

tests["rotation diag C2: not learned and not read are counted apart, not learned first"] = function(t)
    t.eq(line(view({ unread = { "Starfire", "Thorns", "Wrath" }, missing = { "Starfire", "Thorns" } })),
        "rotation: suggesting Moonfire (rotation). 2 spells not learned or not found by name; they are skipped."
        .. " 1 spell not read; it is skipped.")
    t.eq(line(view({ unread = {}, missing = { "Thorns" } })), "rotation: suggesting Moonfire (rotation).",
        "a name in missing that is not unread is not counted")
    local v = view({ unread = { "Thorns" }, missing = { "Thorns" } })
    v.stale = true
    t.eq(line(v), "rotation: suggesting Moonfire (rotation). 1 spell not learned or not found by name;"
        .. " it is skipped. An earlier reading: the last read failed.", "the kept-view note comes last")
end

tests["rotation diag RD15: a suggestion names the spell and the step"] = function(t)
    t.eq(line(view()), "rotation: suggesting Moonfire (rotation).")
end

tests["rotation diag RD15: nothing to suggest gives the last trace note"] = function(t)
    local v = view({ suggestion = "nil",
        trace = { { step = "rotation", result = "skip", note = "nothing ready" } } })
    t.eq(line(v), "rotation: nothing to suggest (nothing ready).")
    v = view({ suggestion = "nil", trace = {} })
    t.eq(line(v), "rotation: nothing to suggest (no reason given).")
end

tests["rotation diag RD15: a view kept from an earlier tick says so"] = function(t)
    local v = view()
    v.stale = true
    t.eq(line(v), "rotation: suggesting Moonfire (rotation). An earlier reading: the last read failed.")
end

-- The order: each row wins over every row below it.
tests["rotation diag RD15: the first row that holds is the one said"] = function(t)
    local everything = {
        snapshot = snap({ dead = "nil", inCombat = "nil" }),
        lockdown = "nil", keys = refused("lockdownUnknown"),
        unread = { "Wrath" }, suggestion = "nil",
        trace = { { step = "dead", result = "stop", note = "not known whether you are dead" } },
    }
    local v = view(everything)
    t.eq(line(v, "off"), "rotation: not running (off).", "not running first")
    t.eq(line({ pack = false, trace = {}, why = { pack = false }, unread = { "Wrath" } }),
        "rotation: class not known, or no spell list for it; nothing suggested.", "then no pack")
    t.eq(line(v), "rotation: not known whether you are dead; nothing suggested.", "then dead not known")
    everything.snapshot = snap({ dead = true, inCombat = "nil" })
    t.eq(line(view(everything)), "rotation: dead; nothing suggested.", "then dead")
    everything.snapshot = snap({ inCombat = "nil" })
    everything.trace = { { step = "rotation", result = "skip", note = "nothing ready" } }
    local tail = " nothing to suggest (nothing ready). 1 spell not read; it is skipped."
    t.eq(line(view(everything)),
        "rotation: fight not known, counted as a fight (keys unchanged);" .. tail,
        "then the fight not known, as a clause")
    everything.snapshot = snap({ inCombat = true })
    t.eq(line(view(everything)),
        "rotation: not known whether you are in a fight (keys unchanged);" .. tail,
        "then lockdown not known, as a clause")
    everything.lockdown, everything.keys = true, refused("lockdown")
    t.eq(line(view(everything)), "rotation: in a fight (keys unchanged);" .. tail,
        "then lockdown, as a clause")
    everything.lockdown, everything.keys = false, { ok = true, ops = {} }
    everything.snapshot = snap({})
    t.eq(line(view(everything)), "rotation:" .. tail, "then the reason, and the spells not read after it")
end

-- CD2 -------------------------------------------------------------------

local function cooldownLine(v)
    if type(Diag.RotationCooldownLine) ~= "function" then return "Diag.RotationCooldownLine is missing" end
    return Diag.RotationCooldownLine(v)
end

local function spells(wrath, moonfire)
    return {
        Wrath = { known = true, usable = true, noPower = false, onCooldown = wrath },
        Moonfire = { known = true, usable = true, noPower = false, onCooldown = moonfire },
    }
end

tests["rotation diag CD2: one line when no cooldown was read and nothing can be cast"] = function(t)
    local v = view({ snapshot = snap({ spells = spells(nil, nil) }), suggestion = "nil" })
    t.eq(cooldownLine(v), "rotation: nothing can be chosen; 2 spells: " .. R.COOLDOWN_UNKNOWN .. ".")
    local one = spells(nil, nil)
    one.Moonfire.known = false
    v = view({ snapshot = snap({ spells = one }), suggestion = "nil" })
    t.eq(cooldownLine(v), "rotation: nothing can be chosen; 1 spell: " .. R.COOLDOWN_UNKNOWN .. ".",
        "a spell that is not known is not counted")
end

-- Three spells nobody read the cooldown of, and one that can be cast.
local function threeUnread()
    local rows = spells(nil, nil)
    rows.Starfire = { known = true, usable = true, noPower = false, onCooldown = nil }
    rows.Thorns = { known = true, usable = true, noPower = false, onCooldown = false }
    return rows
end

tests["rotation diag DF1: passed by is the driver's own list, not every spell with an unread cooldown"] = function(t)
    local s = snap({ spells = threeUnread() })
    t.eq(cooldownLine(view({ snapshot = s, passed = { "Moonfire" } })),
        "rotation: 1 spell passed by: " .. R.COOLDOWN_UNKNOWN .. ": Moonfire.")
    t.eq(cooldownLine(view({ snapshot = s, passed = { "Moonfire", "Wrath" } })),
        "rotation: 2 spells passed by: " .. R.COOLDOWN_UNKNOWN .. ": Moonfire, Wrath.")
end

tests["rotation diag DF1: no passed-by line when the driver passed nothing by"] = function(t)
    local s = snap({ spells = threeUnread() })
    t.eq(cooldownLine(view({ snapshot = s, passed = {} })), nil, "an empty list")
    t.eq(cooldownLine(view({ snapshot = s, passed = "nil" })), nil, "no list")
    t.eq(cooldownLine(view({ snapshot = s, passed = "Moonfire" })), nil, "not a list")
end

tests["rotation diag DF1: the list is said as the driver holds it, for a spell the snapshot reads as ready too"] = function(t)
    t.eq(cooldownLine(view({ passed = { "Wrath" } })),
        "rotation: 1 spell passed by: " .. R.COOLDOWN_UNKNOWN .. ": Wrath.")
end

tests["rotation diag DF1: with nothing to cast the old sentence stays, whatever was passed by"] = function(t)
    local v = view({ snapshot = snap({ spells = spells(nil, nil) }), suggestion = "nil", passed = { "Wrath" } })
    t.eq(cooldownLine(v), "rotation: nothing can be chosen; 2 spells: " .. R.COOLDOWN_UNKNOWN .. ".")
end

tests["rotation diag CD2: no line with every cooldown read, or with nothing to say it of"] = function(t)
    t.eq(cooldownLine(view()), nil, "every cooldown read")
    t.eq(cooldownLine(view({ snapshot = snap({ spells = spells(true, true) }) })), nil, "on cooldown is known")
    t.eq(cooldownLine(view({ snapshot = snap({ spells = {} }) })), nil, "no spell rows")
    t.eq(cooldownLine(view({ snapshot = snap({ spells = spells(nil, nil), dead = true }) })), nil, "dead")
    t.eq(cooldownLine({ pack = false, trace = {}, why = { pack = false } }), nil, "no pack")
    t.eq(cooldownLine(nil), nil, "no view")
end

-- ST1 -------------------------------------------------------------------

local function stealthLine(v)
    if type(Diag.RotationStealthLine) ~= "function" then return "Diag.RotationStealthLine is missing" end
    return Diag.RotationStealthLine(v)
end

tests["rotation diag ST1: stealth not known is said, and what it holds back"] = function(t)
    t.eq(stealthLine(view({ snapshot = snap({ stealthed = "nil" }) })),
        "rotation: not known whether you are stealthed; the attack is not started for you.")
end

tests["rotation diag ST1: stealth that was read is said as read"] = function(t)
    t.eq(stealthLine(view()), "rotation: not stealthed.")
    t.eq(stealthLine(view({ snapshot = snap({ stealthed = true }) })),
        "rotation: stealthed; the attack is not started for you.")
end

tests["rotation diag ST1: no stealth line when nothing is chosen anyway"] = function(t)
    t.eq(stealthLine(view({ snapshot = snap({ stealthed = "nil", dead = true }) })), nil, "dead")
    t.eq(stealthLine(view({ snapshot = snap({ dead = "nil" }) })), nil, "dead not known")
    t.eq(stealthLine({ pack = false, trace = {}, why = { pack = false } }), nil, "no pack")
    t.eq(stealthLine(nil), nil, "no view")
end

-- Through the slash command ----------------------------------------------

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

local function start(cooldown, extra)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setDead(false)
    c.setClass(CLASS)
    c.setSpellId("Wrath", WRATH)
    c.setSpellId("Moonfire", MOONFIRE)
    c.setSpell(WRATH, { known = true, usable = true, noPower = false })
    c.setSpell(MOONFIRE, { known = true, usable = true, noPower = false })
    c.setSpellCooldown(WRATH, cooldown)
    c.setSpellCooldown(MOONFIRE, cooldown)
    -- A living enemy targeted: since DRIVER-2 a list rule that needs a
    -- target is suggested only when the target is read as hostile.
    c.setTarget({ exists = true, hostile = true, dead = false })
    -- Since RANGE-UNKNOWN a range not read is not ready: both spells are
    -- read as in range, so the suggestion these tests name still stands.
    c.setInRange(WRATH, true)
    c.setInRange(MOONFIRE, true)
    local k = ns.Kernel({}, c)
    Diag.Start(k)
    local p = pack()
    -- extra: more pack spells, given no id (not learned yet).
    for _, name in ipairs(extra or {}) do p.spells[name] = { evidence = "test" } end
    D.Declare(k, { [CLASS] = p })
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c
end

local function said(c, text)
    local n = 0
    for i = 1, #c.printed do
        if c.printed[i]:find(text, 1, true) then n = n + 1 end
    end
    return n
end

-- Says the diag lines afresh and gives the count of lines holding `text`.
local function diag(c, text)
    for i = #c.printed, 1, -1 do c.printed[i] = nil end
    c.slashes[ns.id.slash]("diag")
    return said(c, text)
end

local function tick(c) c.advance(D.EVERY + 0.05, 1) end

tests["rotation diag RD15: the slash command says the driver's line"] = function(t)
    local k, c = start(false)
    local head = ns.id.title .. ": rotation: "
    t.eq(diag(c, head .. "switched off; nothing suggested."), 1, "off until switched on")
    t.eq(said(c, "rotation: "), 1, "one rotation line while nothing is held")
    k.settings:set(D.SETTING, true)
    t.eq(diag(c, head .. "no reading yet."), 1, "switched on, before the first tick")
    tick(c)
    t.eq(diag(c, head .. "suggesting Moonfire ("), 1, "a reading")
    c.setCombat(true)
    tick(c)
    t.eq(diag(c, head .. "in a fight (keys unchanged); suggesting Moonfire ("), 1,
        "in a fight the suggestion is still said")
    c.setCombat(false)
    c.setDead(true)
    tick(c)
    t.eq(diag(c, head .. "dead; nothing suggested."), 1)
    c.setClass(nil)
    tick(c)
    t.eq(diag(c, head .. "class not known, or no spell list for it; nothing suggested."), 1)
    k:SwitchOff(D.NAME, "test")
    t.eq(diag(c, head .. "not running (off)."), 1)
    t.eq(said(c, "rotation: "), 1, "and nothing else of the rotation")
end

tests["rotation diag C2: the slash command says the suggestion with spells not learned yet"] = function(t)
    local k, c = start(false, { "Starfire", "Thorns" })
    k.settings:set(D.SETTING, true)
    tick(c)
    local head = ns.id.title .. ": rotation: "
    t.eq(diag(c, head .. "suggesting Moonfire ("), 1, "the suggestion is said")
    t.eq(said(c, "). 2 spells not learned or not found by name; they are skipped."), 1, "after it, the count")
    t.eq(said(c, "not read;"), 0, "a spell not learned is not counted as not read")
end

tests["rotation diag ST1: the driver reads no stealth, and the slash command says so"] = function(t)
    local k, c = start(false)
    k.settings:set(D.SETTING, true)
    tick(c)
    t.eq(diag(c, ns.id.title .. ": rotation: not known whether you are stealthed; "
        .. "the attack is not started for you."), 1)
end

tests["rotation diag CD2: the slash command says when no cooldown was read"] = function(t)
    local k, c = start(nil)
    k.settings:set(D.SETTING, true)
    tick(c)
    t.eq(diag(c, ns.id.title .. ": rotation: nothing can be chosen; 2 spells: "
        .. R.COOLDOWN_UNKNOWN .. "."), 1)
    t.eq(said(c, "rotation: nothing to suggest ("), 1, "beside the driver's own line")
end

tests["rotation diag RD15: no rotation line on a kernel that has no driver"] = function(t)
    local c = ns.make.fakeClient()
    local k = ns.Kernel({}, c)
    Diag.Start(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    c.slashes[ns.id.slash]("diag")
    t.eq(said(c, "rotation"), 0)
    t.ok(#c.printed > 0, "the snapshot line is printed")
end

tests["rotation diag RD15: a driver that raises costs its lines only"] = function(t)
    local k, c = start(false)
    local got = k.use(D.NAME)
    t.ok(type(got) == "table" and type(got.View) == "function", "the driver answers View")
    if type(got) ~= "table" then return end
    got.View = function() error("view broke") end
    local before = k.problems:count("diag")
    local ok, err = pcall(c.slashes[ns.id.slash], "diag")
    t.ok(ok, "the command does not raise: " .. tostring(err))
    t.eq(said(c, ns.id.title .. ": the rotation line failed; it is kept as a problem."), 1)
    t.eq(said(c, "rotation: "), 0, "and no half line")
    t.eq(k.problems:count("diag"), before + 1, "one problem, not one for each line")
end

return tests

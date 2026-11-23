-- Group buff tooltip (S17): on another friendly player's tooltip, which of
-- your group buffs they have. Ported from Flow's Modules/Rotation/Tooltip.lua
-- (text only). Made-up units and buffs, test only. Nothing here casts,
-- targets or clicks. Not seen in game.
local _, ns = ...

local T = ns.GroupTip
local tests = {}

local MOTW, GOTW, THORNS = "Mark of the Wild", "Gift of the Wild", "Thorns"

local function pack()
    return {
        -- P-PARTY: one list, `groups` (it was `groupBuffs`).
        groups = {
            { spell = MOTW, aura = { MOTW, GOTW }, who = "all", evidence = "first guess" },
            { spell = THORNS, who = { "tank", "WARRIOR" }, evidence = "first guess" },
        },
    }
end

local function friend(over)
    local u = { exists = true, player = true, isSelf = false, friendly = true,
                class = "WARRIOR", role = "NONE", power = 1 }
    for key, v in pairs(over or {}) do
        if v == "nil" then u[key] = nil else u[key] = v end
    end
    return u
end

-- A druid who knows both buffs, hovering "mouseover".
local function client(unit, buffs)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setClass("DRUID")
    c.setSpellId(MOTW, 1126)
    c.setSpell(1126, { known = true })
    c.setSpellId(THORNS, 467)
    c.setSpell(467, { known = true })
    c.setUnit("mouseover", unit or friend())
    if buffs ~= false then c.setUnitBuffs("mouseover", buffs or {}) end
    return c
end

local function start(c, packs)
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    local api = T.Declare(k, packs or { DRUID = pack() })
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, api
end

-- ------------------------------------------------------------------ pure

tests["group tip: the names agreed"] = function(t)
    t.eq(T.NAME, "groupTip")
    t.eq(T.SETTING, "general.groupTip")
    t.eq(T.HEADER, "Your buffs for them:")
end

tests["group tip left: 0, negative, infinite and not-a-number say nothing"] = function(t)
    t.eq(T.Left(0), "")
    t.eq(T.Left(-5), "")
    t.eq(T.Left(math.huge), "")
    t.eq(T.Left(0 / 0), "")
    t.eq(T.Left(nil), "")
    t.eq(T.Left("60"), "")
end

tests["group tip left: 89 s is seconds, 90 s is minutes"] = function(t)
    t.eq(T.Left(89), " (89 s)")
    t.eq(T.Left(90), " (2 min)")
    t.eq(T.Left(120), " (2 min)")
    t.eq(T.Left(1800), " (30 min)")
    t.eq(T.Left(4.4), " (4 s)")
end

tests["group tip line: has it"] = function(t)
    local text, tone = T.Line(MOTW, true, 120, MOTW)
    t.eq(text, "Mark of the Wild: has it (2 min)")
    t.eq(tone, "has")
    text, tone = T.Line(MOTW, true, nil, nil)
    t.eq(text, "Mark of the Wild: has it")
    t.eq(tone, "has")
end

tests["group tip line: has another version names it"] = function(t)
    local text, tone = T.Line(MOTW, true, 30, GOTW)
    t.eq(text, "Mark of the Wild: has Gift of the Wild (30 s)")
    t.eq(tone, "other")
end

tests["group tip line: unknown says can't tell"] = function(t)
    local text, tone = T.Line(MOTW, nil)
    t.eq(text, "Mark of the Wild: can't tell (the game hides their buffs)")
    t.eq(tone, "hidden")
    t.ok(text ~= (T.Line(MOTW, false)), "not known is never said as missing")
end

tests["group tip line: false says MISSING"] = function(t)
    local text, tone = T.Line(MOTW, false)
    t.eq(text, "Mark of the Wild: MISSING")
    t.eq(tone, "missing")
end

tests["group tip kind: druid by power type; hunter ranged; unknown class is nil"] = function(t)
    t.eq(T.Kind("DRUID", "NONE", 1), "tank")
    t.eq(T.Kind("DRUID", "NONE", 3), "melee")
    t.eq(T.Kind("DRUID", "NONE", 0), "caster")
    t.eq(T.Kind("DRUID", "NONE", nil), nil, "a form not read is not guessed")
    t.eq(T.Kind("HUNTER", "NONE", 2), "ranged")
    t.eq(T.Kind("WARRIOR", nil, 1), "melee")
    t.eq(T.Kind("MAGE", nil, 0), "caster")
    t.eq(T.Kind(nil, nil, 1), nil)
    t.eq(T.Kind("GNOME", "NONE", 0), nil, "a class not listed is not called melee")
end

tests["group tip kind: the role chosen in the group comes first"] = function(t)
    t.eq(T.Kind("WARRIOR", "TANK", 1), "tank")
    t.eq(T.Kind("PRIEST", "HEALER", 0), "healer")
    t.eq(T.Kind("PRIEST", "DAMAGER", 0), "caster")
    t.eq(T.Kind(nil, "TANK", 1), nil, "no class, no kind")
end

tests["group tip lines: yourself, a non-player, an enemy, and a unit not known to be friendly all give nil"] = function(t)
    t.ok(T.Lines(client(), pack(), "mouseover") ~= nil, "the plain friend has lines")
    t.eq(T.Lines(client(friend({ isSelf = true })), pack(), "mouseover"), nil)
    t.eq(T.Lines(client(friend({ player = false })), pack(), "mouseover"), nil)
    t.eq(T.Lines(client(friend({ friendly = false })), pack(), "mouseover"), nil)
    t.eq(T.Lines(client(friend({ friendly = "nil" })), pack(), "mouseover"), nil)
    t.eq(T.Lines(client(friend({ isSelf = "nil" })), pack(), "mouseover"), nil)
    t.eq(T.Lines(client(friend({ player = "nil" })), pack(), "mouseover"), nil)
    t.eq(T.Lines(client(friend({ exists = false })), pack(), "mouseover"), nil)
end

tests["group tip lines: no unit, no pack, or a unit the client knows nothing of"] = function(t)
    local c = client()
    t.eq(T.Lines(c, pack(), nil), nil)
    t.eq(T.Lines(c, nil, "mouseover"), nil)
    t.eq(T.Lines(c, {}, "mouseover"), nil)
    t.eq(T.Lines(c, pack(), "party3"), nil)
end

tests["group tip lines: each rule that fits, in the order of the pack"] = function(t)
    local c = client(nil, { { name = THORNS, left = 45 } })
    t.eq(T.Lines(c, pack(), "mouseover"), {
        { text = "Mark of the Wild: MISSING", tone = "missing" },
        { text = "Thorns: has it (45 s)", tone = "has" },
    })
end

tests["group tip lines: a spell you do not know is left out"] = function(t)
    local c = client()
    c.setSpell(467, { known = false })
    t.eq(T.Lines(c, pack(), "mouseover"), { { text = "Mark of the Wild: MISSING", tone = "missing" } })
    c.setSpellId(MOTW, nil)
    t.eq(T.Lines(c, pack(), "mouseover"), nil, "none known: nothing to say")
end

tests["group tip lines: known not readable is left out, not shown as missing"] = function(t)
    local c = client()
    c.setSpell(1126, {})
    t.eq(T.Lines(c, pack(), "mouseover"), { { text = "Thorns: MISSING", tone = "missing" } })
end

tests["group tip lines: Thorns is offered to a tank and a warrior, not to a mage"] = function(t)
    local function spells(unit)
        local out = {}
        for _, l in ipairs(T.Lines(client(unit), pack(), "mouseover") or {}) do out[#out + 1] = l.text end
        return out
    end
    t.eq(spells(friend({ class = "WARRIOR" })), { "Mark of the Wild: MISSING", "Thorns: MISSING" })
    t.eq(spells(friend({ class = "PALADIN", role = "TANK" })), { "Mark of the Wild: MISSING", "Thorns: MISSING" })
    t.eq(spells(friend({ class = "DRUID", power = 1 })), { "Mark of the Wild: MISSING", "Thorns: MISSING" })
    t.eq(spells(friend({ class = "MAGE", power = 0 })), { "Mark of the Wild: MISSING" })
end

tests["group tip lines: a class not read leaves out the rules that are not for everyone"] = function(t)
    local lines = T.Lines(client(friend({ class = "nil" })), pack(), "mouseover")
    t.eq(lines, { { text = "Mark of the Wild: MISSING", tone = "missing" } })
end

tests["group tip lines: a hidden buff list gives can't tell for every rule"] = function(t)
    local lines = T.Lines(client(nil, false), pack(), "mouseover")
    t.eq(lines, {
        { text = "Mark of the Wild: can't tell (the game hides their buffs)", tone = "hidden" },
        { text = "Thorns: can't tell (the game hides their buffs)", tone = "hidden" },
    })
    lines = T.Lines(client(nil, { { name = false } }), pack(), "mouseover")
    t.eq(lines[1].tone, "hidden", "one buff that cannot be read hides the answer")
    t.eq(lines[2].tone, "hidden")
end

tests["group tip lines: Gift of the Wild counts as Mark of the Wild and is named"] = function(t)
    local c = client(nil, { { name = GOTW, left = 3000 } })
    local lines = T.Lines(c, pack(), "mouseover")
    t.eq(lines[1], { text = "Mark of the Wild: has Gift of the Wild (50 min)", tone = "other" })
end

tests["group tip lines: a buff with no end says no time"] = function(t)
    local c = client(nil, { { name = MOTW, left = math.huge } })
    t.eq(T.Lines(c, pack(), "mouseover")[1], { text = "Mark of the Wild: has it", tone = "has" })
end

tests["group tip lines: the pack is not changed"] = function(t)
    local p = pack()
    T.Lines(client(), p, "mouseover")
    t.eq(p, pack())
end

-- ---------------------------------------------------------------- module

tests["group tip module: header first, then one line per rule, colours by tone"] = function(t)
    local c = client(nil, { { name = GOTW, left = 120 } })
    local k, api = start(c)
    t.eq((k:ModuleState(T.NAME)), "started")
    t.eq(api.hooked(), true)
    t.eq(c.showUnitTooltip("mouseover"), {
        { text = "Your buffs for them:", r = 1, g = 0.82, b = 0.25 },
        { text = "  Mark of the Wild: has Gift of the Wild (2 min)", r = 0.45, g = 1, b = 0.45 },
        { text = "  Thorns: MISSING", r = 1, g = 0.35, b = 0.35 },
    })
    t.eq(k.use(T.NAME).Hooked(), true, "others ask by name")
end

tests["group tip module: what cannot be told is grey"] = function(t)
    local c = client(nil, false)
    start(c)
    local added = c.showUnitTooltip("mouseover")
    t.eq(added[2], { text = "  Mark of the Wild: can't tell (the game hides their buffs)", r = 0.7, g = 0.7, b = 0.7 })
end

tests["group tip module: setting off adds nothing"] = function(t)
    local c = client()
    local k = start(c)
    t.eq(k.settings:row(T.SETTING).type, "bool", "the module declares its own row")
    t.ok(#c.showUnitTooltip("mouseover") > 0, "on by default")
    k.settings:set(T.SETTING, false)
    t.eq(c.showUnitTooltip("mouseover"), {})
    k.settings:set(T.SETTING, true)
    t.ok(#c.showUnitTooltip("mouseover") > 0)
end

tests["group tip module: no hook on the client -> hooked() false, one problem, no error"] = function(t)
    local c = client()
    c.onUnitTooltip = nil
    local k, api = start(c)
    t.eq((k:ModuleState(T.NAME)), "started")
    t.eq(api.hooked(), false)
    t.eq(api.errors(), 0)
    t.eq(k.problems:count(T.NAME), 1)
end

tests["group tip module: a hook the client refuses is the same"] = function(t)
    local c = client()
    c.onUnitTooltip = function() return nil end
    local k, api = start(c)
    t.eq(api.hooked(), false)
    t.eq(k.problems:count(T.NAME), 1)
end

tests["group tip module: an error in Lines adds nothing to the tooltip and is counted once per distinct text"] = function(t)
    local c = client()
    local k, api = start(c)
    c.unitInfo = function() error("the client refused") end
    t.eq(c.showUnitTooltip("mouseover"), {})
    t.eq(api.errors(), 1)
    t.eq(k.problems:count(T.NAME), 1)
    t.eq(c.showUnitTooltip("mouseover"), {})
    t.eq(api.errors(), 2)
    t.eq(k.problems:count(T.NAME), 1, "the same error is one problem, not one per hover")
end

tests["group tip module: class with no groupBuffs adds no header"] = function(t)
    local c = client()
    start(c, { DRUID = {} })
    t.eq(c.showUnitTooltip("mouseover"), {})
    local c2 = client()
    c2.setClass("PALADIN")
    start(c2)
    t.eq(c2.showUnitTooltip("mouseover"), {}, "a class with no pack")
    local c3 = client()
    c3.setClass(nil)
    start(c3)
    t.eq(c3.showUnitTooltip("mouseover"), {}, "a class not known")
end

tests["group tip module: nobody to say it about adds no header"] = function(t)
    local c = client(friend({ player = false }))
    start(c)
    t.eq(c.showUnitTooltip("mouseover"), {})
end

tests["group tip: the druid pack names its group buffs, as first guesses"] = function(t)
    -- P-PARTY: one list, `groups`; groupBuffs is gone from every pack.
    local rows = ns.Packs.DRUID.groups
    t.eq(#rows, 2)
    t.eq(rows[1].spell, MOTW)
    t.eq(rows[1].aura, { MOTW, GOTW })
    t.eq(rows[1].who, "all")
    t.eq(rows[2].spell, THORNS)
    t.eq(rows[2].who, { "tank", "WARRIOR" })
    for i = 1, #rows do t.eq(rows[i].evidence, "first guess") end
    for class, p in pairs(ns.Packs) do t.eq(p.groupBuffs, nil, class .. ": no groupBuffs list") end
    t.eq(#ns.Packs.PALADIN.groups, 4, "the paladin's blessings, accepted in P-PARTY")
end

-- P-PARTY: the paladin's blessings share one slot, so a player is told of
-- one blessing: the first that fits them (a warrior tank: Kings).
tests["group tip: one blessing per player, the first that fits"] = function(t)
    local c = client(friend({ role = "TANK" }), { { name = "Blessing of Kings", left = 200 } })
    c.setClass("PALADIN")
    c.setSpellId("Blessing of Kings", 20217); c.setSpell(20217, { known = true })
    c.setSpellId("Blessing of Might", 19740); c.setSpell(19740, { known = true })
    c.setSpellId("Blessing of Wisdom", 19742); c.setSpell(19742, { known = true })
    start(c, { PALADIN = { groups = ns.Packs.PALADIN.groups } })
    local lines = c.showUnitTooltip("mouseover")
    local text = {}
    for i, l in ipairs(lines or {}) do text[i] = type(l) == "table" and l.text or tostring(l) end
    local joined = table.concat(text, " | ")
    t.ok(joined:find("Blessing of Kings: has it", 1, true) ~= nil, "Kings, for the tank: " .. joined)
    t.ok(not joined:find("Blessing of Might", 1, true), "no Might line: " .. joined)
    t.ok(not joined:find("Blessing of Wisdom", 1, true), "no Wisdom line: " .. joined)
    local _, kings = joined:gsub("Blessing of Kings", "")
    t.eq(kings, 1, "Kings once, not twice")
end

tests["group tip: the setting is in the model, on by default"] = function(t)
    local model = ns.Settings.Model.Default()
    t.eq(model:row(T.SETTING).type, "bool")
    t.eq(model:default(T.SETTING), true)
end

tests["group tip: look only - nothing casts, targets or clicks"] = function(t)
    for name in pairs(T) do
        local n = tostring(name):lower()
        t.ok(not (n:find("cast") or n:find("target") or n:find("click") or n:find("press")),
            "no acting function: " .. n)
    end
end

return tests

local _, ns = ...
-- N1, N2, N20 and N5 (P-KEYS slice D), pure: what the rotation key does
-- out of a fight on the player's own press (Rotation/KeyActions.lua):
-- fishing, a corpse, a crafting station, a better item from the bags.
-- Hand-made reads; made-up item ids, places and spells. Not tested in game.
local tests = {}

local function KA() return ns.KeyActions end

local POLE, MAIN, OFF, BETTER = 6256, 2488, 2129, 4321
local ALL = { fishing = true, corpse = true, station = true, upgrade = true }

local function ready(t)
    local ok = type(KA()) == "table" and type(KA().Pick) == "function"
    t.ok(ok, "Rotation/KeyActions.lua gives KA.Pick")
    return ok
end

-- Out of a fight, nothing targeted, every row on (fishing too), nothing to do.
local function base(over)
    local s = {
        inCombat = false, lockdown = false, on = {}, enemy = false, pole = false, poleBag = nil,
        channel = nil, known = {}, weapons = {}, worn = {}, bag = {}, corpse = nil,
        professions = {}, position = { map = 1411, x = 0.5, y = 0.5 }, stations = {},
        hasOre = false, window = nil, upgrade = nil,
    }
    for k, v in pairs(ALL) do s.on[k] = v end
    for k, v in pairs(over or {}) do s[k] = v end
    return s
end

local function fishing(over)
    local s = base({ poleBag = POLE, known = { Fishing = true }, weapons = { main = MAIN, off = OFF },
        worn = { main = MAIN, off = OFF }, bag = { [POLE] = true } })
    for k, v in pairs(over or {}) do s[k] = v end
    return s
end

local function stepOf(x)
    if type(x) ~= "table" then return nil end
    return x.step
end
local function field(x, name) if type(x) ~= "table" then return nil end return x[name] end

-- N1 ---------------------------------------------------------------------

tests["key actions: fishing on, no pole worn: the key equips the pole from the bags"] = function(t)
    if not ready(t) then return end
    local got = KA().Pick(fishing(), nil)
    t.eq(field(got, "itemId"), POLE)
    t.eq(stepOf(got), "fishing")
    t.eq(field(got, "look"), nil, "on the key")
end

tests["key actions: fishing on, the pole worn: the key casts Fishing on you"] = function(t)
    if not ready(t) then return end
    local got = KA().Pick(fishing({ pole = true, worn = { main = POLE, off = false } }), nil)
    t.eq(field(got, "spell"), "Fishing")
    t.eq(field(got, "unit"), "player")
end

tests["key actions: a fish on the line is shown, never put on the key (reeling in is the bobber click)"] = function(t)
    if not ready(t) then return end
    local got = KA().Pick(fishing({ pole = true, channel = "Fishing" }), nil)
    t.eq(field(got, "look"), true)
    t.eq(field(got, "spell"), nil)
end

tests["key actions: Fishing not known: no cast is offered"] = function(t)
    if not ready(t) then return end
    t.eq(KA().Pick(fishing({ pole = true, known = {} }), nil), nil)
end

tests["key actions: no pole in the bags and none worn: nothing"] = function(t)
    if not ready(t) then return end
    t.eq(KA().Pick(fishing({ poleBag = nil, bag = {} }), nil), nil)
end

tests["key actions: fishing row off: no pole, no cast"] = function(t)
    if not ready(t) then return end
    local s = fishing()
    s.on.fishing = false
    t.eq(KA().Pick(s, nil), nil)
end

tests["key actions: the pole worn and an enemy targeted: weapons back first, over any suggestion"] = function(t)
    if not ready(t) then return end
    local s = fishing({ pole = true, enemy = true, bag = { [MAIN] = true, [OFF] = true },
        worn = { main = POLE, off = false } })
    local got = KA().Pick(s, { spell = "Judgement", step = "engage" })
    t.eq(field(got, "itemId"), MAIN, "the main hand weapon")
    t.eq(stepOf(got), "weaponsBack")
end

tests["key actions: the main hand back, the off hand next"] = function(t)
    if not ready(t) then return end
    local s = fishing({ pole = false, bag = { [OFF] = true }, worn = { main = MAIN, off = false },
        weapons = { main = MAIN, off = OFF, pending = true } })
    s.on.fishing = false
    t.eq(field(KA().Pick(s, nil), "itemId"), OFF)
end

tests["key actions: fishing switched off with the pole on: weapons back only after the key put the pole on"] = function(t)
    if not ready(t) then return end
    local s = fishing({ pole = true, bag = { [MAIN] = true }, worn = { main = POLE, off = false },
        weapons = { main = MAIN, pending = true } })
    s.on.fishing = false
    t.eq(field(KA().Pick(s, nil), "itemId"), MAIN, "the key's own swap")
    s.weapons = { main = MAIN }
    t.eq(KA().Pick(s, nil), nil, "a pole you put on yourself is left alone")
end

tests["key actions: a weapon not in the bags is not offered"] = function(t)
    if not ready(t) then return end
    local s = fishing({ pole = true, enemy = true, bag = {}, worn = { main = POLE, off = false } })
    t.eq(KA().Pick(s, nil), nil)
end

-- N2 ---------------------------------------------------------------------

local function corpse(row, over)
    local s = base({ corpse = row, professions = { Skinning = true, Herbalism = true },
        known = { Skinning = true, ["Herb Gathering"] = true } })
    for k, v in pairs(over or {}) do s[k] = v end
    return s
end

tests["key actions: a corpse with loot on it is shown (looting is the corpse click), not put on the key"] = function(t)
    if not ready(t) then return end
    local got = KA().Pick(corpse({ exists = true, dead = true, player = false, lootable = true, needs = "Skinning" }), nil)
    t.eq(field(got, "look"), true)
    t.eq(stepOf(got), "loot")
end

tests["key actions: a looted skinnable corpse: the key skins it, on the target"] = function(t)
    if not ready(t) then return end
    local got = KA().Pick(corpse({ exists = true, dead = true, player = false, lootable = false, needs = "Skinning" }), nil)
    t.eq(field(got, "spell"), "Skinning")
    t.eq(field(got, "unit"), "target")
    t.eq(stepOf(got), "corpse")
end

tests["key actions: a corpse that needs Herbalism: Herb Gathering"] = function(t)
    if not ready(t) then return end
    local got = KA().Pick(corpse({ exists = true, dead = true, player = false, lootable = false, needs = "Herbalism" }), nil)
    t.eq(field(got, "spell"), "Herb Gathering")
end

tests["key actions: a profession you lack, a player's corpse, or a live target: nothing"] = function(t)
    if not ready(t) then return end
    t.eq(KA().Pick(corpse({ exists = true, dead = true, player = false, lootable = false, needs = "Mining" }), nil), nil)
    t.eq(KA().Pick(corpse({ exists = true, dead = true, player = true, lootable = false, needs = "Skinning" }), nil), nil)
    t.eq(KA().Pick(corpse({ exists = true, dead = false, player = false, lootable = false, needs = "Skinning" }), nil), nil)
end

-- N20 --------------------------------------------------------------------

local function near(kind)
    return { { map = 1411, x = 0.501, y = 0.5, kind = kind } }
end

local function station(over)
    local s = base({ known = { Smelting = true, Blacksmithing = true, Cooking = true },
        professions = { Mining = true, Blacksmithing = true, Cooking = true } })
    for k, v in pairs(over or {}) do s[k] = v end
    return s
end

tests["key actions: by a forge with ore, one press opens Smelting"] = function(t)
    if not ready(t) then return end
    local got = KA().Pick(station({ stations = near("forge"), hasOre = true }), nil)
    t.eq(field(got, "spell"), "Smelting")
    t.eq(stepOf(got), "station")
end

tests["key actions: by a forge with no ore, or an anvil: Blacksmithing; by a fire: Cooking"] = function(t)
    if not ready(t) then return end
    t.eq(field(KA().Pick(station({ stations = near("forge"), hasOre = false }), nil), "spell"), "Blacksmithing")
    t.eq(field(KA().Pick(station({ stations = near("anvil") }), nil), "spell"), "Blacksmithing")
    t.eq(field(KA().Pick(station({ stations = near("fire") }), nil), "spell"), "Cooking")
end

tests["key actions: far from any station, on another map, or the window already open: nothing"] = function(t)
    if not ready(t) then return end
    t.eq(KA().Pick(station({ stations = { { map = 1411, x = 0.6, y = 0.5, kind = "forge" } }, hasOre = true }), nil), nil)
    t.eq(KA().Pick(station({ stations = { { map = 1412, x = 0.5, y = 0.5, kind = "forge" } }, hasOre = true }), nil), nil)
    t.eq(KA().Pick(station({ stations = near("forge"), hasOre = true, window = "Smelting" }), nil), nil,
        "open: making the count is the craft bar's click")
end

tests["key actions: a station is learned once, near ones are not added twice, and the list is capped"] = function(t)
    if not ready(t) then return end
    local list = {}
    t.eq(KA().Learn(list, { map = 1411, x = 0.5, y = 0.5 }, "forge"), true)
    t.eq(KA().Learn(list, { map = 1411, x = 0.5005, y = 0.5 }, "forge"), false, "the same forge")
    t.eq(KA().Learn(list, { map = 1411, x = 0.5005, y = 0.5 }, "anvil"), true, "an anvil beside it")
    t.eq(KA().Learn(list, nil, "forge"), false, "no position")
    t.eq(KA().Learn(list, { map = 1411, x = 0.2, y = 0.2 }, nil), false, "no kind")
    t.eq(#list, 2)
    for i = 1, KA().STATIONS_MAX + 5 do KA().Learn(list, { map = 2000 + i, x = 0.5, y = 0.5 }, "fire") end
    t.eq(#list, KA().STATIONS_MAX, "capped; the oldest go first")
    t.eq(list[#list].map, 2000 + KA().STATIONS_MAX + 5)
end

tests["key actions: a station's kind from the tool's name"] = function(t)
    if not ready(t) then return end
    t.eq(KA().StationKind("Anvil"), "anvil")
    t.eq(KA().StationKind("Blacksmith Forge"), "forge")
    t.eq(KA().StationKind("Cooking Fire"), "fire")
    t.eq(KA().StationKind("Moonwell"), nil)
    t.eq(KA().StationKind(nil), nil)
end

-- N5 ---------------------------------------------------------------------

tests["key actions: a better item in the bags: the key equips it"] = function(t)
    if not ready(t) then return end
    local got = KA().Pick(base({ upgrade = { itemId = BETTER, text = "Upgrade for your head piece (+5, dps)", sure = true } }), nil)
    t.eq(field(got, "itemId"), BETTER)
    t.eq(stepOf(got), "upgrade")
end

-- §447 F1: buffs first; the key equips only a sure upgrade -----------------

tests["key actions F1: a class buff is never replaced by gear, even on a weak step"] = function(t)
    if not ready(t) then return end
    local s = base({ upgrade = { itemId = BETTER, text = "x", sure = true } })
    t.eq(KA().Pick(s, { spell = "Righteous Fury", kind = "buff", unit = "player" }), nil, "the buff stays")
    t.eq(KA().Pick(s, { spell = "Blessing of Might", kind = "buff", step = "group" }), nil, "a group buff stays")
end

tests["key actions F1: an upgrade that is not sure is advice only, never on the key"] = function(t)
    if not ready(t) then return end
    local got = KA().Pick(base({ upgrade = { itemId = BETTER, text = "Upgrade for your head piece (+1, dps)", sure = false } }), nil)
    t.eq(field(got, "look"), true, "look only")
    t.eq(field(got, "itemId"), nil, "nothing for the key to equip")
    t.eq(stepOf(got), "upgradeAdvice")
    t.ok(type(field(got, "reason")) == "string" and field(got, "reason"):find("Upgrade for your head piece", 1, true) ~= nil, "the verdict text is kept")
end

tests["key actions F1: advice does not replace a weak step"] = function(t)
    if not ready(t) then return end
    local s = base({ upgrade = { itemId = BETTER, text = "x", sure = false } })
    t.eq(KA().Pick(s, { spell = "Find Minerals", step = "track" }), nil)
end

tests["key actions F1: Sure needs a role, the game's yes, an upgrade and a clear gain"] = function(t)
    if not ready(t) then return end
    local function d(over)
        local x = { result = { verdict = "upgrade", delta = 5, against = 20 }, use = { can = true, source = "client" } }
        for k, v in pairs(over or {}) do x[k] = v end
        return x
    end
    t.eq(KA().Sure(d(), true), true, "25% better, usable, role set")
    t.eq(KA().Sure(d(), false), false, "no role chosen")
    t.eq(KA().Sure(d({ use = { can = true } }), true), false, "usable only by the pack's first guess")
    t.eq(KA().Sure(d({ use = { can = nil, source = "client" } }), true), false, "not read")
    t.eq(KA().Sure(d({ result = { verdict = "upgrade", delta = 1, against = 20 } }), true), false, "5%: not clear")
    t.eq(KA().Sure(d({ result = { verdict = "upgrade", delta = 3, against = 0 } }), true), true, "an empty slot")
    t.eq(KA().Sure(d({ result = { verdict = "same", delta = 0, against = 20 } }), true), false, "not an upgrade")
    t.eq(KA().Sure(nil, true), false)
end

-- The key's rules --------------------------------------------------------

tests["key actions: in a fight, in lockdown, or not known: nothing"] = function(t)
    if not ready(t) then return end
    local s = base({ upgrade = { itemId = BETTER, text = "x", sure = true } })
    s.inCombat = true
    t.eq(KA().Pick(s, nil), nil, "in a fight")
    s.inCombat, s.lockdown = false, true
    t.eq(KA().Pick(s, nil), nil, "lockdown")
    s.lockdown, s.inCombat = false, nil
    t.eq(KA().Pick(s, nil), nil, "not known")
end

tests["key actions: only a weak suggestion is replaced (food, tracking, group, or nothing)"] = function(t)
    if not ready(t) then return end
    local s = base({ upgrade = { itemId = BETTER, text = "x", sure = true } })
    t.eq(KA().Pick(s, { spell = "Blessing of Might", step = "list" }), nil, "the pack's own step stays")
    t.eq(field(KA().Pick(s, { spell = "Find Minerals", step = "track" }), "itemId"), BETTER, "tracking is replaced")
end

tests["key actions: each row off: that action is not offered"] = function(t)
    if not ready(t) then return end
    local s = base({ upgrade = { itemId = BETTER, text = "x", sure = true } })
    s.on.upgrade = false
    t.eq(KA().Pick(s, nil), nil)
    s = corpse({ exists = true, dead = true, player = false, lootable = false, needs = "Skinning" })
    s.on.corpse = false
    t.eq(KA().Pick(s, nil), nil)
    s = station({ stations = near("forge"), hasOre = true })
    s.on.station = false
    t.eq(KA().Pick(s, nil), nil)
end

tests["key actions: the key controls' fishing hook gives the fishing step"] = function(t)
    if not ready(t) then return end
    t.eq(field(ns.KeyControls.Fishing(fishing()), "itemId"), POLE)
end

return tests

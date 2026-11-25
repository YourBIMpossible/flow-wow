local _, ns = ...

-- Section 226, CF-30: Well Fed food. Out of a fight, with your buffs read
-- and no Well Fed among them, the best Well Fed food in your bags (by what
-- its buff is worth to your role) is the suggestion on the rotation icon and
-- key. Buff up, in a fight, or no such food in your bags: no food
-- suggestion. Made-up items, tooltip lines and textures; not tested in game.

local tests = {}
local D = ns.RotationDriver

local RIBS, FISH, BREAD, ROCK = 9001, 9002, 9003, 9004
-- Section 235 item 4: Strength, Stamina, Fishing, and a Well Fed food whose
-- tooltip names no stat.
local STRF, STAF, LURE, VAGUE = 9005, 9006, 9007, 9008
local LINES = {
    [RIBS] = { "Spiced Wolf Ribs", "Use: Restores 552 health over 21 sec. If you spend at least 10 seconds eating you will become well fed and gain 6 Stamina and Spirit for 15 min." },
    [FISH] = { "Smoked Sagefish", "Use: Restores 378 health over 21 sec. If you spend at least 10 seconds eating you will become well fed and gain 3 Mana every 5 seconds for 15 min." },
    [BREAD] = { "Plain Bread", "Use: Restores 243 health over 18 sec. Must remain seated while eating." },
    [ROCK] = { "Lava Rock" },
    [STRF] = { "Strength Stew", "Use: If you spend at least 10 seconds eating you will become well fed and gain 10 Strength for 15 min." },
    [STAF] = { "Stamina Stew", "Use: If you spend at least 10 seconds eating you will become well fed and gain 10 Stamina for 15 min." },
    [LURE] = { "Angler Bites", "Use: If you spend at least 10 seconds eating you will become well fed and gain 10 Fishing skill for 15 min." },
    [VAGUE] = { "Mystery Meat", "Use: If you spend at least 10 seconds eating you will become well fed for 15 min." },
}
local INFO = {
    [RIBS] = { name = "Spiced Wolf Ribs", classID = 0, subclassID = 5 },
    [FISH] = { name = "Smoked Sagefish", classID = 0, subclassID = 5 },
    [BREAD] = { name = "Plain Bread", classID = 0, subclassID = 5 },
    [ROCK] = { name = "Lava Rock", classID = 7, subclassID = 0 },
    [STRF] = { name = "Strength Stew", classID = 0, subclassID = 5 },
    [STAF] = { name = "Stamina Stew", classID = 0, subclassID = 5 },
    [LURE] = { name = "Angler Bites", classID = 0, subclassID = 5 },
    [VAGUE] = { name = "Mystery Meat", classID = 0, subclassID = 5 },
}

local MANA = { name = "Mana", forms = { "none" } }
local RAGE = { name = "Rage", forms = { "none" } }

-- Section 235 item 4: the test pack's stat weights, as a class pack's
-- (pack.weights[role].values). A dps values Stamina over Spirit and mana
-- regeneration; a healer mana regeneration first.
local WEIGHTS = {
    dps = { values = { ITEM_MOD_STAMINA_SHORT = 1, ITEM_MOD_SPIRIT_SHORT = 0.5,
                       ITEM_MOD_MANA_REGENERATION_SHORT = 1 } },
    heal = { values = { ITEM_MOD_STAMINA_SHORT = 0.3, ITEM_MOD_SPIRIT_SHORT = 0.4,
                        ITEM_MOD_MANA_REGENERATION_SHORT = 1.5 } },
    tank = { values = { ITEM_MOD_STAMINA_SHORT = 1 } },
}

local function pack(resource, weights)
    return {
        resources = { resource or MANA },
        weights = weights or WEIGHTS,
        roles = { dps = {}, heal = {}, tank = {} },
        spells = { Wrath = { evidence = "test" } },
        lists = { default = { { spell = "Wrath", target = true, reason = "Wrath" } } },
        keys = { none = { key = "Wrath" } },
    }
end

-- A fake client out of a fight, alive, not mounted, not on a flight path,
-- no target, with these items in the bags and these buffs (nil: buffs not
-- read).
local function client(items, buffs, inCombat)
    local c = ns.make.fakeClient()
    c.setDead(false)
    c.setMounted(false)
    c.setOnTaxi(false)
    if inCombat then c.setCombat(true) end
    c.setPlayerBuffs(buffs)
    local stacks = {}
    for _, id in ipairs(items or {}) do stacks[#stacks + 1] = { item = id, count = 3 } end
    c.setBagItems(stacks)
    c.setItemInfo(INFO)
    for id, lines in pairs(LINES) do c.setItemLines(id, lines) end
    c.setItemTexture(RIBS, "tex:ribs")
    return c
end

local function step(c, p, role)
    return D.Step(c, p or pack(), nil, nil, nil, role)
end

-- The pure part ---------------------------------------------------------------

tests["buff food: Well Fed food is told from plain food by its tooltip"] = function(t)
    t.eq(ns.BuffFood.IsBuffFood(LINES[RIBS]), true)
    t.eq(ns.BuffFood.IsBuffFood(LINES[BREAD]), false)
    t.eq(ns.BuffFood.IsBuffFood(nil), false)
end

tests["buff food: what the buff gives is read from the tooltip"] = function(t)
    t.eq(ns.BuffFood.Gain(LINES[RIBS]), { Stamina = 6, Spirit = 6 })
    t.eq(ns.BuffFood.Gain(LINES[FISH]), { mp5 = 3 })
    t.eq(ns.BuffFood.Gain(LINES[BREAD]), {})
end

tests["buff food: scored with the pack weights for the role (section 235)"] = function(t)
    local BF = ns.BuffFood
    t.eq(BF.Score({ Stamina = 6, Spirit = 6 }, WEIGHTS.dps.values), 9)
    t.eq(BF.Score({ mp5 = 3 }, WEIGHTS.heal.values), 4.5)
    t.eq(BF.Score({ mp5 = 3 }, WEIGHTS.tank.values), 0, "a stat the weights do not name: worth nothing")
    t.eq(BF.Score({}, WEIGHTS.dps.values), nil, "the tooltip does not say: not known")
    t.eq(BF.Score({ Stamina = 6 }, nil), nil, "no weights: not known")
end

tests["buff food: the fixed role tables, only for a pack with no weights"] = function(t)
    local BF = ns.BuffFood
    t.eq(BF.ScoreByRole({ Stamina = 6, Spirit = 6 }, "dps", true), 12)
    t.eq(BF.ScoreByRole({ mp5 = 3 }, "heal", true), 9)
    t.eq(BF.ScoreByRole({ mp5 = 3 }, "dps", false), 0)
    local bare = pack()
    bare.weights = nil
    t.eq(D.Read(client({ RIBS, FISH }, {}), bare, {}, "heal")("buffFood").name, "Smoked Sagefish",
        "no weights: the role table picks")
end

tests["buff food: every class pack has weights for each of its roles; none falls back (section 235)"] = function(t)
    local n = 0
    for class, p in pairs(ns.Packs or {}) do
        for role in pairs(type(p.roles) == "table" and p.roles or {}) do
            n = n + 1
            local w = type(p.weights) == "table" and p.weights[role] or nil
            t.ok(type(w) == "table" and type(w.values) == "table", class .. " " .. role .. " has weights")
        end
    end
    t.ok(n > 0, "the packs were read")
end

tests["buff food: the best is picked; worth nothing or not known is never picked (section 235)"] = function(t)
    local BF = ns.BuffFood
    t.eq(BF.Best({ { id = 2, score = 6 }, { id = 1, score = 12 } }).id, 1)
    t.eq(BF.Best({ { id = 5, score = 6 }, { id = 4, score = 6 } }).id, 4, "a tie: the lower id")
    t.eq(BF.Best({ { id = 3, score = nil }, { id = 2, score = 6 } }).id, 2, "not known: never picked")
    t.eq(BF.Best({ { id = 3, score = nil } }), nil, "only not known: none")
    t.eq(BF.Best({ { id = 3, score = 0 } }), nil, "worth nothing: none")
    t.eq(BF.Best({}), nil)
end

-- Section 235 item 4: each tooltip stat name, one test each, read and
-- weighed through the one name map.
local NAMED = {
    { "10 Stamina", "ITEM_MOD_STAMINA_SHORT" },
    { "10 Strength", "ITEM_MOD_STRENGTH_SHORT" },
    { "10 Agility", "ITEM_MOD_AGILITY_SHORT" },
    { "10 Intellect", "ITEM_MOD_INTELLECT_SHORT" },
    { "10 Spirit", "ITEM_MOD_SPIRIT_SHORT" },
    { "10 attack power", "ITEM_MOD_ATTACK_POWER_SHORT" },
    { "10 spell damage", "ITEM_MOD_SPELL_POWER_SHORT" },
    { "10 healing", "ITEM_MOD_SPELL_HEALING_DONE_SHORT" },
    { "10 Mana every 5 seconds", "ITEM_MOD_MANA_REGENERATION_SHORT" },
    { "10 health every 5 seconds", "ITEM_MOD_HEALTH_REGEN_SHORT" },
}
for _, row in ipairs(NAMED) do
    tests["buff food: the tooltip's " .. row[1] .. " is weighed as " .. row[2]] = function(t)
        local lines = { "x", "Use: If you spend at least 10 seconds eating you will become well fed and gain "
            .. row[1] .. " for 15 min." }
        t.eq(ns.BuffFood.Score(ns.BuffFood.Gain(lines), { [row[2]] = 1 }), 10)
    end
end

tests["buff food: a profession skill is an activity, not a fight stat"] = function(t)
    local BF = ns.BuffFood
    t.eq(BF.Activity(LINES[LURE]), { Fishing = 10 })
    t.eq(BF.Activity({ "x", "you will become well fed and increases your Fishing skill by 5 for 10 min." }),
        { Fishing = 5 })
    t.eq(BF.Activity(LINES[RIBS]), {})
    t.eq(BF.Gain(LINES[LURE]), {}, "no fight stat")
end

-- Acceptance (section 226, CF-30) ------------------------------------------------

tests["buff food CF-30: out of a fight, no Well Fed, food in bags: the best food is suggested on the icon and key"] = function(t)
    local c = client({ BREAD, FISH, RIBS, ROCK }, {})
    local v = step(c, pack(), "dps")
    t.ok(v.suggestion ~= nil, "a suggestion")
    if not v.suggestion then return end
    t.eq(v.suggestion.item, "Spiced Wolf Ribs", "the best food for a dps")
    t.eq(v.suggestion.itemId, RIBS)
    t.eq(v.suggestion.step, "food")
    t.eq(v.suggestion.spell, nil, "not a spell")
    local key = {}
    for _, r in ipairs(v.attrs.button) do key[r.attr] = r.value end
    -- Section 246 (N63-E): the item type, not a macro.
    t.eq(key.type, "item", "the key uses the item")
    t.eq(key.item, "item:" .. RIBS)
    t.eq(key.macrotext, nil, "no macro text")
    t.eq(key.spell, nil)
    t.eq(ns.RotationIcon.Item(v), RIBS, "the icon shows the item")
    t.eq(ns.RotationIcon.Texture(c, v), "tex:ribs", "with the item's own texture")
end

tests["buff food CF-30: the pick follows the role"] = function(t)
    local v = step(client({ RIBS, FISH }, {}), pack(), "heal")
    t.eq(v.suggestion and v.suggestion.item, "Smoked Sagefish", "a healer eats the mana food")
end

tests["buff food CF-30: Well Fed already on you: no food suggestion"] = function(t)
    local v = step(client({ RIBS }, { ["Well Fed"] = 600 }), pack(), "dps")
    t.eq(v.suggestion, nil)
end

tests["buff food CF-30: in a fight: no food suggestion"] = function(t)
    local v = step(client({ RIBS }, {}, true), pack(), "dps")
    t.ok(not (v.suggestion and v.suggestion.step == "food"), "no food in a fight")
end

tests["buff food CF-30: no Well Fed food in the bags: no food suggestion"] = function(t)
    t.eq(step(client({ BREAD, ROCK }, {}), pack(), "dps").suggestion, nil, "only plain food")
    t.eq(step(client({}, {}), pack(), "dps").suggestion, nil, "empty bags")
    t.eq(step(client({ FISH }, {}), pack(RAGE, { dps = { values = { ITEM_MOD_STAMINA_SHORT = 1 } } }), "dps").suggestion,
        nil, "mana food when the weights give mana nothing: worth nothing")
end

tests["buff food CF-30: your buffs not read: no food suggestion"] = function(t)
    t.eq(step(client({ RIBS }, nil), pack(), "dps").suggestion, nil, "not read is not \"no Well Fed\"")
end

tests["buff food: the driver's read is nil when the bags are not read, {} when they hold none"] = function(t)
    local c = client({ BREAD }, {})
    t.eq(D.Read(c, pack(), {}, "dps")("buffFood"), {})
    c.setBagItems(nil)
    t.eq(D.Read(c, pack(), {}, "dps")("buffFood"), nil)
    local c2 = client({ RIBS }, {})
    c2.setItemLines(RIBS, nil)
    t.eq(D.Read(c2, pack(), {}, "dps")("buffFood"), nil, "a food whose tooltip was not read: not known")
end

-- Section 235 item 4: the owner's cases --------------------------------------

local function foodOf(c, p, role)
    return D.Read(c, p, {}, role)("buffFood")
end

tests["buff food 235 (a): a Paladin dps with Strength and Stamina food: Strength"] = function(t)
    local p = ns.Packs.PALADIN
    local got = foodOf(client({ STAF, STRF }, {}), p, "dps")
    t.eq(got and got.name, "Strength Stew")
end

tests["buff food 235 (b): a tank: the pick follows the pack weights"] = function(t)
    local p = ns.Packs.PALADIN
    local w = p.weights.tank.values
    local str, sta = (w.ITEM_MOD_STRENGTH_SHORT or 0) * 10, (w.ITEM_MOD_STAMINA_SHORT or 0) * 10
    t.ok(str ~= sta, "the weights tell them apart")
    local want = sta > str and "Stamina Stew" or "Strength Stew"
    local got = foodOf(client({ STRF, STAF }, {}), p, "tank")
    t.eq(got and got.name, want)
    t.eq(got and got.score, math.max(str, sta), "scored from the weights")
end

tests["buff food 235 (c): only a fishing food and no pole: nothing"] = function(t)
    local c = client({ LURE }, {})
    c.setFishingPole(false)
    t.eq(foodOf(c, pack(), "dps"), {})
    t.eq(step(c, pack(), "dps").suggestion, nil)
    c.setFishingPole(nil)
    t.eq(step(c, pack(), "dps").suggestion, nil, "pole not known: not offered either")
end

tests["buff food 235 (d): a fishing food with a pole: the fishing food"] = function(t)
    local c = client({ RIBS, LURE }, {})
    c.setFishingPole(true)
    local v = step(c, pack(), "dps")
    t.eq(v.suggestion and v.suggestion.item, "Angler Bites")
    c.setFishingPole(false)
    t.eq(step(c, pack(), "dps").suggestion.item, "Spiced Wolf Ribs", "pole away: the fight food")
end

tests["buff food 235: with a pole, no fight food"] = function(t)
    local c = client({ RIBS, STAF }, {})
    c.setFishingPole(true)
    t.eq(foodOf(c, pack(), "dps"), {})
    t.eq(step(c, pack(), "dps").suggestion, nil)
end

tests["buff food 235: the kept pick follows the pole with no bag change"] = function(t)
    local c = client({ RIBS, LURE }, {})
    local food = { on = true }
    c.setFishingPole(false)
    t.eq(D.Read(c, pack(), {}, "dps", { food = food })("buffFood").name, "Spiced Wolf Ribs")
    c.setFishingPole(true)
    t.eq(D.Read(c, pack(), {}, "dps", { food = food })("buffFood").name, "Angler Bites")
end

tests["buff food 235 (e): a caster with only a Strength food: nothing"] = function(t)
    local p = ns.Packs.MAGE
    t.ok(((p.weights.dps.values.ITEM_MOD_STRENGTH_SHORT) or 0) <= 0, "the weights give Strength nothing")
    t.eq(foodOf(client({ STRF }, {}), p, "dps"), {})
end

tests["buff food 235 (f): a tooltip not read, or one that names no stat: nothing"] = function(t)
    local c = client({ STRF }, {})
    c.setItemLines(STRF, nil)
    t.eq(foodOf(c, pack(), "dps"), nil, "not read")
    t.eq(step(c, pack(), "dps").suggestion, nil)
    t.eq(foodOf(client({ VAGUE }, {}), pack(), "dps"), {}, "names no stat: never offered")
end

-- Section 229 (F-1): the driver in a kernel. The food is read out of a fight
-- only, and kept between bag changes (BAG_UPDATE_DELAYED). Fails before the
-- repair: every tick read the bags, in a fight too.

local KCLASS = "TESTCLASS"

-- The driver on a kernel, switched on, over client c; the bag reads are
-- counted. keys: the key frame (Rotation/KeyFrame.lua) on the same kernel,
-- switched on. Returns the api, the count so far, and the kernel.
local function running(c, keys)
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setClass(KCLASS)
    local reads, real = 0, c.bagItems
    c.bagItems = function(...)
        reads = reads + 1
        return real(...)
    end
    local k = ns.Kernel({}, c)
    local diag = ns.Diag.Start(k)
    local api = D.Declare(k, { [KCLASS] = pack() })
    if keys then ns.KeyFrame.Declare(k, diag) end
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    k.settings:set(D.SETTING, true)
    -- N8: the healing items read the bags too; switched off here so the
    -- count is the food's alone (theirs is held in Tests/Rotation/HealItems.lua).
    k.settings:set(D.HEAL, false)
    if keys then k.settings:set(ns.KeyFrame.SETTING, true) end
    return api, function() return reads end, k
end

local function tick(c) c.advance(D.EVERY + 0.05, 1) end

local function food(api)
    local v = api.view()
    local s = v and v.suggestion
    return s and s.step == "food" and s.item or nil
end

tests["buff food F-1: a tick in a fight reads no bags"] = function(t)
    local c = client({ RIBS }, {}, true)
    local api, reads = running(c)
    local from = reads()
    tick(c)
    t.ok(api.view() ~= nil, "the tick ran")
    t.eq(reads() - from, 0, "no bag read in a fight")
    tick(c)
    t.eq(reads() - from, 0, "nor on the next")
end

tests["buff food F-1: out of a fight the bags are read once, and again only after a bag change"] = function(t)
    local c = client({ RIBS }, {})
    local api, reads = running(c)
    local from = reads()
    tick(c)
    t.eq(food(api), "Spiced Wolf Ribs", "the food is suggested")
    t.eq(reads() - from, 1, "one bag read")
    tick(c)
    t.eq(reads() - from, 1, "a second tick with no bag event: no bag read")
    t.eq(food(api), "Spiced Wolf Ribs", "the food kept")
    c.setBagItems({ { item = BREAD, count = 3 } })
    c.fire("BAG_UPDATE_DELAYED")
    tick(c)
    t.eq(reads() - from, 2, "the bags changed: read again")
    t.eq(food(api), nil, "only plain food now: no food suggested")
end

tests["buff food F-1: a fight, then out of it with no bag change, reads the bags once"] = function(t)
    local c = client({ RIBS }, {}, true)
    local api, reads = running(c)
    local from = reads()
    tick(c)
    c.setCombat(false)
    tick(c)
    tick(c)
    t.eq(reads() - from, 1, "the first tick out of the fight reads, the next does not")
    t.eq(food(api), "Spiced Wolf Ribs")
end

tests["buff food F-1: a food not read is not kept; the next tick reads again"] = function(t)
    local c = client({ RIBS }, {})
    c.setItemLines(RIBS, nil)
    local api, reads = running(c)
    local from = reads()
    tick(c)
    t.eq(food(api), nil, "the tooltip not read: no food")
    c.setItemLines(RIBS, LINES[RIBS])
    tick(c)
    t.eq(reads() - from, 2, "not known is read again, with no bag event")
    t.eq(food(api), "Spiced Wolf Ribs", "once the tooltip is read")
end

-- BF-1 (section 230, MyBuddy) ---------------------------------------------------

-- The worry: the out-of-fight "/use item:" macro is still on the key at a
-- pull, so a press at the pull starts eating. The one secure button
-- (Rotation/KeyFrame.lua) is set from the key plan with no suggestion, so the
-- food macro never reaches it; the food is only in the view. This holds that
-- down: every value the button is ever given is recorded, out of a fight
-- with the food suggested and then in the fight.
tests["buff food BF-1: the food macro never reaches the secure button, before or at a pull"] = function(t)
    local c = client({ RIBS }, {})
    c.setSpellId("Wrath", 5176)
    c.setSpell(5176, { known = true, usable = true, noPower = false })
    c.setSpellCooldown(5176, false)
    local given, real = {}, c.secureButton
    c.secureButton = function(spec)
        local h = real(spec)
        if type(h) == "table" then
            local set = h.set
            h.set = function(attr, value)
                given[#given + 1] = { attr = attr, value = value }
                return set(attr, value)
            end
        end
        return h
    end
    local api = running(c, true)
    tick(c)
    t.eq(food(api), "Spiced Wolf Ribs", "the food is suggested out of a fight")
    t.eq(#c.secureButtons, 1, "the key frame made its button")
    local h = c.secureButtons[1]
    t.ok(h and h.attrs.type ~= "macro", "the button holds no macro")
    t.ok(h and h.attrs.macrotext == nil, "and no macro text")
    c.setCombat(true)
    tick(c)
    tick(c)
    for _, g in ipairs(given) do
        t.ok(not (type(g.value) == "string" and g.value:find("/use", 1, true)),
            "never given a /use macro: " .. tostring(g.attr) .. " = " .. tostring(g.value))
        -- Section 246 (N63-E): the food is the item type now; still never on
        -- the button.
        t.ok(g.value ~= "item:" .. RIBS, "never given the food: " .. tostring(g.attr))
        t.ok(g.value ~= "macro", "never a macro: " .. tostring(g.attr))
    end
    t.ok(#given > 0, "the button was set")
end

-- BF-2 (section 230, MyBuddy) ---------------------------------------------------

tests["buff food BF-2: eating or drinking: no food suggestion"] = function(t)
    t.eq(step(client({ RIBS }, { Food = 18 }), pack(), "dps").suggestion, nil, "eating")
    t.eq(step(client({ RIBS }, { Drink = 18 }), pack(), "dps").suggestion, nil, "drinking")
    t.eq(step(client({ RIBS }, { ["Food & Drink"] = 18 }), pack(), "dps").suggestion, nil, "both")
    -- Section 237 BF2-1: Flow's list (Engine.lua EATING) has Refreshment too.
    t.eq(step(client({ RIBS }, { Refreshment = 18 }), pack(), "dps").suggestion, nil, "refreshment")
    t.eq(ns.BuffFood.Eating({ Refreshment = 18 }), true)
    t.eq(ns.BuffFood.Eating({ Food = 18 }), true)
    t.eq(ns.BuffFood.Eating({ ["Power Word: Fortitude"] = 600 }), false)
    t.eq(ns.BuffFood.Eating(nil), nil, "buffs not read: not known")
end

tests["buff food BF-2: mounted, or mounted not known: no food suggestion"] = function(t)
    local c = client({ RIBS }, {})
    c.setMounted(true)
    t.eq(step(c, pack(), "dps").suggestion, nil, "mounted")
    c.setMounted(nil)
    t.eq(step(c, pack(), "dps").suggestion, nil, "not known is not \"not mounted\"")
    c.setMounted(false)
    t.eq(step(c, pack(), "dps").suggestion and step(c, pack(), "dps").suggestion.item, "Spiced Wolf Ribs",
        "on foot: the food")
end

tests["buff food BF-2: on a flight path, or not known: no food suggestion"] = function(t)
    local c = client({ RIBS }, {})
    c.setOnTaxi(true)
    t.eq(step(c, pack(), "dps").suggestion, nil, "on a flight path")
    c.setOnTaxi(nil)
    t.eq(step(c, pack(), "dps").suggestion, nil, "not known")
end

tests["buff food BF-2: the reason is in the trace"] = function(t)
    local c = client({ RIBS }, { Food = 18 })
    local v = step(c, pack(), "dps")
    local why
    for _, r in ipairs(v.trace or {}) do
        if r.step == "food" then why = r.note or r.result end
    end
    t.ok(type(why) == "string" and why:find("eating", 1, true) ~= nil, "eating named: " .. tostring(why))
end

-- BF-3 (section 230, MyBuddy) ---------------------------------------------------

tests["buff food BF-3: a settings row, on by default; off, no food is suggested and no bag is read"] = function(t)
    local c = client({ RIBS }, {})
    local api, reads, k = running(c)
    t.eq(k.settings:get(D.FOOD), true, "on by default")
    tick(c)
    t.eq(food(api), "Spiced Wolf Ribs")
    t.eq(k.settings:set(D.FOOD, false), true, "the setting is taken")
    c.fire("BAG_UPDATE_DELAYED")
    local from = reads()
    tick(c)
    t.eq(food(api), nil, "off: no food")
    t.eq(reads() - from, 0, "off: no bag read")
    k.settings:set(D.FOOD, true)
    tick(c)
    t.eq(food(api), "Spiced Wolf Ribs", "on again: the food")
end

tests["buff food BF-3: the food step says it is switched off"] = function(t)
    local s = ns.SnapshotOf({ inCombat = false, dead = false, buffs = {}, foodOn = false,
        mounted = false, onTaxi = false, buffFood = { name = "Spiced Wolf Ribs", item = RIBS, score = 12 } })
    local got, why = ns.Rotation._steps.food(s)
    t.eq(got, nil)
    t.ok(type(why) == "string" and why:find("switched off", 1, true) ~= nil, tostring(why))
end

-- Section 232: D.Read and D.Step take one trailing options table, extra,
-- with named fields. extra.food reaches the food read with another field
-- (Zen's extra.chosen) beside it; that one is Zen's to assert.
tests["buff food: extra.food reaches the food read with extra.chosen beside it (section 232)"] = function(t)
    local c = client({ RIBS }, {})
    local n, real = 0, c.bagItems
    c.bagItems = function(...) n = n + 1 return real(...) end
    local off = { food = { on = false }, chosen = { spell = "Wrath" } }
    local read = D.Read(c, pack(), {}, "dps", off)
    t.eq(read("foodOn"), false, "foodOn from extra.food")
    t.eq(read("buffFood"), nil, "switched off: no food")
    t.eq(n, 0, "and no bag read")
    local on = { food = { on = true }, chosen = { spell = "Wrath" } }
    t.eq(D.Read(c, pack(), {}, "dps", on)("buffFood").name, "Spiced Wolf Ribs", "on: the food")
    t.eq(on.food.kept, true, "kept in extra.food")
    local v = D.Step(c, pack(), nil, nil, nil, "dps", { food = { on = false }, chosen = { spell = "Wrath" } })
    t.ok(not (v.suggestion and v.suggestion.step == "food"), "D.Step hands extra on: no food when off")
    t.eq(D.Read(c, pack(), {}, "dps", { chosen = { spell = "Wrath" } })("foodOn"), nil, "no extra.food: not known")
end

-- Section 236: a pick made while another food was not read yet answers, but
-- is not kept; the late food is read on the next read.
tests["buff food: a pick made with a food not read yet is not kept (section 236)"] = function(t)
    local c = client({ RIBS, FISH }, {})
    c.setItemLines(RIBS, nil)
    local food = { on = true }
    local function read() return D.Read(c, pack(), {}, "heal", { food = food })("buffFood") end
    t.eq(read().name, "Smoked Sagefish", "the one read")
    t.eq(food.kept, false, "not kept: Spiced Wolf Ribs not read")
    c.setItemLines(RIBS, LINES[RIBS])
    t.eq(read().name, "Smoked Sagefish", "read again: still the healer's pick")
    t.eq(food.kept, true, "all read: kept")
end

-- Parity row D-13 (lead section 668), as Flow's /flow rot why food list
-- (Modules/Rotation/BuffItems.lua FoodWhyText, :236-268): every Well Fed
-- food carried, best first, what each gives, its score, which is picked and
-- when. Fails before: there is no BuffFood.WhyText and no D.Foods.
tests["well fed food why: best first, the pick marked, what each gives, and when"] = function(t)
    local BF = ns.BuffFood
    local lines = BF.WhyText({
        { id = 2, name = "Smoked Sagefish", score = 3, gain = { mp5 = 3 } },
        { id = 1, name = "Spiced Wolf Ribs", score = 10.5, gain = { Stamina = 6, Spirit = 6 } },
        { id = 3, name = "Mystery Meat", gain = {} },
    }, "dps", false)
    t.eq(lines[1], BF.WHY_HEAD:format("dps"))
    t.eq(lines[2], "  * Spiced Wolf Ribs: 6 Spirit, 6 Stamina; score 10.5")
    t.eq(lines[3], "  Smoked Sagefish: 3 mp5; score 3.0")
    t.eq(lines[4], "  Mystery Meat: no stat the score weighs; never suggested")
    t.eq(#lines, 4)
end

tests["well fed food why: none carried, Well Fed on you, and a food worth nothing"] = function(t)
    local BF = ns.BuffFood
    t.eq(BF.WhyText({}, "tank", false), { BF.WHY_NONE })
    t.eq(BF.WhyText(nil, "tank", false), { BF.WHY_NONE })
    local fed = BF.WhyText({ { id = 1, name = "Ribs", score = 4, gain = { Stamina = 6 } } }, "tank", true)
    t.eq(fed[#fed], BF.WHY_FED)
    local zero = BF.WhyText({ { id = 1, name = "Stew", score = 0, gain = { Strength = 10 } } }, "heal", false)
    t.eq(zero[2], "  Stew: 10 Strength; score 0.0; does nothing for you: never suggested")
end

tests["well fed food why: the driver lists every fight food in the bags with what it gives"] = function(t)
    local c = ns.make.fakeClient()
    c.setItemInfo(INFO)
    c.setBagItems({ { item = RIBS, count = 2 }, { item = FISH, count = 1 }, { item = BREAD, count = 3 },
                    { item = ROCK, count = 1 } })
    for id, l in pairs(LINES) do c.setItemLines(id, l) end
    local foods = D.Foods(c, nil, "dps")
    t.eq(#foods, 2, "the two Well Fed foods; bread and rock are not")
    local byName = {}
    for _, f in ipairs(foods) do byName[f.name] = f end
    t.eq(byName["Spiced Wolf Ribs"].gain, { Stamina = 6, Spirit = 6 })
    t.ok(type(byName["Spiced Wolf Ribs"].score) == "number")
    c.bagItems = function() return nil end
    t.eq(D.Foods(c, nil, "dps"), nil, "bags not read: nil, never none")
end

return tests

local _, ns = ...

-- Section 226, CF-30: Well Fed food. Out of a fight, with your buffs read
-- and no Well Fed among them, the best Well Fed food in your bags (by what
-- its buff is worth to your role) is the suggestion on the rotation icon and
-- key. Buff up, in a fight, or no such food in your bags: no food
-- suggestion. Made-up items, tooltip lines and textures; not tested in game.

local tests = {}
local D = ns.RotationDriver

local RIBS, FISH, BREAD, ROCK = 9001, 9002, 9003, 9004
local LINES = {
    [RIBS] = { "Spiced Wolf Ribs", "Use: Restores 552 health over 21 sec. If you spend at least 10 seconds eating you will become well fed and gain 6 Stamina and Spirit for 15 min." },
    [FISH] = { "Smoked Sagefish", "Use: Restores 378 health over 21 sec. If you spend at least 10 seconds eating you will become well fed and gain 3 Mana every 5 seconds for 15 min." },
    [BREAD] = { "Plain Bread", "Use: Restores 243 health over 18 sec. Must remain seated while eating." },
    [ROCK] = { "Lava Rock" },
}
local INFO = {
    [RIBS] = { name = "Spiced Wolf Ribs", classID = 0, subclassID = 5 },
    [FISH] = { name = "Smoked Sagefish", classID = 0, subclassID = 5 },
    [BREAD] = { name = "Plain Bread", classID = 0, subclassID = 5 },
    [ROCK] = { name = "Lava Rock", classID = 7, subclassID = 0 },
}

local MANA = { name = "Mana", forms = { "none" } }
local RAGE = { name = "Rage", forms = { "none" } }

local function pack(resource)
    return {
        resources = { resource or MANA },
        roles = { dps = {}, heal = {}, tank = {} },
        spells = { Wrath = { evidence = "test" } },
        lists = { default = { { spell = "Wrath", target = true, reason = "Wrath" } } },
        keys = { none = { key = "Wrath" } },
    }
end

-- A fake client out of a fight, alive, no target, with these items in the
-- bags and these buffs (nil: buffs not read).
local function client(items, buffs, inCombat)
    local c = ns.make.fakeClient()
    c.setDead(false)
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

tests["buff food: scored by role; mana food is worth nothing without mana"] = function(t)
    local BF = ns.BuffFood
    t.eq(BF.Score({ Stamina = 6, Spirit = 6 }, "dps", true), 12)
    t.eq(BF.Score({ mp5 = 3 }, "dps", true), 6)
    t.eq(BF.Score({ mp5 = 3 }, "heal", true), 9)
    t.eq(BF.Score({ Stamina = 6, Spirit = 6 }, "heal", true), 7.5)
    t.eq(BF.Score({ mp5 = 3 }, "dps", false), 0)
    t.eq(BF.Score({}, "dps", true), nil, "the tooltip does not say: not known")
end

tests["buff food: the best is picked; nothing worth something is never picked"] = function(t)
    local BF = ns.BuffFood
    t.eq(BF.Best({ { id = 2, score = 6 }, { id = 1, score = 12 } }).id, 1)
    t.eq(BF.Best({ { id = 5, score = 6 }, { id = 4, score = 6 } }).id, 4, "a tie: the lower id")
    t.eq(BF.Best({ { id = 3, score = nil }, { id = 2, score = 6 } }).id, 2, "not known counts below known")
    t.eq(BF.Best({ { id = 3, score = 0 } }), nil, "worth nothing: none")
    t.eq(BF.Best({}), nil)
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
    t.eq(key.type, "macro", "the key uses the item")
    t.eq(key.macrotext, "/use item:" .. RIBS)
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
    t.eq(step(client({ FISH }, {}), pack(RAGE), "dps").suggestion, nil, "mana food without mana: worth nothing")
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

-- Section 229 (F-1): the driver in a kernel. The food is read out of a fight
-- only, and kept between bag changes (BAG_UPDATE_DELAYED). Fails before the
-- repair: every tick read the bags, in a fight too.

local KCLASS = "TESTCLASS"

-- The driver on a kernel, switched on, over client c; the bag reads are
-- counted. Returns the api and the count so far.
local function running(c)
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setClass(KCLASS)
    local reads, real = 0, c.bagItems
    c.bagItems = function(...)
        reads = reads + 1
        return real(...)
    end
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    local api = D.Declare(k, { [KCLASS] = pack() })
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    k.settings:set(D.SETTING, true)
    return api, function() return reads end
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

return tests

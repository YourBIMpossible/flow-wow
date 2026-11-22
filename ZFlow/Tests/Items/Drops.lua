local _, ns = ...

-- Tests for ZFlow/Items/Drops.lua (L6-J, G10 second part): what the player
-- looted from which creature, per character, from loot-window readings.
-- Counts are shown as observed counts; a share is only shown from
-- Drops.MIN_SAMPLES loots of that creature on. Hand-written readings only.
--
-- The loot window comes through client.lootWindow() (CLIENT NEED). Until
-- the fake has its setter (setLootWindow), the read is put on it directly.

local D, Present = ns.Drops, ns.ItemPresent
local tests = {}

local function reading(guid, id, name, items)
    return { source = { kind = "creature", how = "corpse", guid = guid, id = id, name = name }, items = items }
end

-- Review of 50a474d (blocker): a pickpocket or skinning window has a
-- creature's GUID too. Only a window the client says is corpse loot counts.
tests["drops: a pickpocket or skinning window is not a corpse's loot"] = function(t)
    local book, seen = {}, {}
    for _, how in ipairs({ "pickpocket", "skinning", "gather", "something new" }) do
        local r = reading("g1", 40, "Kobold Miner", { { item = 97, count = 1 } })
        r.source.how = how
        local ok, why = D.Record(book, seen, r)
        t.eq(ok, false, how .. " is not recorded")
        t.eq(why, "not corpse loot")
    end
    t.eq(next(book), nil, "nothing written")
    t.eq(next(seen), nil, "and the creature is not marked as looted")
end

tests["drops: when the client can't say how the window was opened, nothing is recorded"] = function(t)
    local book, seen = {}, {}
    local r = reading("g1", 40, "Kobold Miner", { { item = 97, count = 1 } })
    r.source.how = nil
    local ok, why = D.Record(book, seen, r)
    t.eq({ ok, why }, { false, "not corpse loot" }, "not known is not 'a corpse'")
    t.eq(next(book), nil)
end

tests["drops: picking a pocket first does not hide the corpse's loot later"] = function(t)
    local book, seen = {}, {}
    local pick = reading("g1", 40, "Kobold Miner", { { item = 2589, count = 1 } })
    pick.source.how = "pickpocket"
    D.Record(book, seen, pick)
    local ok = D.Record(book, seen, reading("g1", 40, "Kobold Miner", { { item = 97, count = 2 } }))
    t.eq(ok, true, "the same creature's corpse is still counted")
    t.eq(book[40].looted, 1)
    t.eq(book[40].items[97].count, 2)
    t.eq(book[40].items[2589], nil, "what was pickpocketed is not a drop")
    local skin = reading("g1", 40, "Kobold Miner", { { item = 2318, count = 1 } })
    skin.source.how = "skinning"
    t.eq((D.Record(book, seen, skin)), false, "skinning it afterwards adds nothing")
    t.eq(book[40].items[2318], nil)
end

-- Review finding 2 (F-086): a saved name is not replaced by a later one.
tests["drops: a creature's saved name is kept, and a missing name stays missing"] = function(t)
    local book, seen = {}, {}
    D.Record(book, seen, reading("g1", 40, "Kobold Miner", {}))
    D.Record(book, seen, reading("g2", 40, "Some Other Target", {}))
    t.eq(book[40].name, "Kobold Miner", "the first name tied to this creature id stays")
    D.Record(book, seen, reading("g3", 41, nil, {}))
    t.eq(book[41].name, nil, "no name read: none made up")
    D.Record(book, seen, reading("g4", 41, "Kobold Tunneler", {}))
    t.eq(book[41].name, "Kobold Tunneler", "a name that arrives later fills the gap")
end

local function has(lines, text)
    for _, l in ipairs(lines or {}) do
        if l == text then return true end
    end
    return false
end

-- ------------------------------------------------------------------ Record

tests["drops: one loot window is one loot of that creature"] = function(t)
    local book, seen = {}, {}
    local ok = D.Record(book, seen, reading("g1", 40, "Kobold Miner", { { item = "item:97", count = 2 }, { item = 2589, count = 1 } }))
    t.eq(ok, true)
    t.eq(book[40].name, "Kobold Miner")
    t.eq(book[40].looted, 1)
    t.eq(book[40].items[97], { count = 2, times = 1 })
    t.eq(book[40].items[2589], { count = 1, times = 1 })
end

tests["drops: the same corpse opened again is not counted twice"] = function(t)
    local book, seen = {}, {}
    D.Record(book, seen, reading("g1", 40, "Kobold Miner", { { item = 97, count = 2 } }))
    local ok, why = D.Record(book, seen, reading("g1", 40, "Kobold Miner", { { item = 97, count = 2 } }))
    t.eq(ok, false)
    t.eq(why, "already counted")
    t.eq(book[40].looted, 1)
    t.eq(book[40].items[97].count, 2)
end

tests["drops: more corpses add up, and two stacks of one item are one drop"] = function(t)
    local book, seen = {}, {}
    D.Record(book, seen, reading("g1", 40, "Kobold Miner", { { item = 97, count = 2 }, { item = 97, count = 1 } }))
    D.Record(book, seen, reading("g2", 40, "Kobold Miner", {}))
    D.Record(book, seen, reading("g3", 40, "Kobold Miner", { { item = 97, count = 1 } }))
    t.eq(book[40].looted, 3, "an empty corpse is a loot too")
    t.eq(book[40].items[97], { count = 4, times = 2 }, "4 fangs, in 2 of the 3")
end

tests["drops: what is not a creature's corpse is not recorded"] = function(t)
    local book, seen = {}, {}
    t.eq((D.Record(book, seen, nil)), false)
    t.eq((D.Record(book, seen, { source = { kind = "object", guid = "o1", id = 5, name = "Chest" }, items = {} })), false)
    t.eq((D.Record(book, seen, { items = { { item = 97, count = 1 } } })), false, "no source read: whose loot is not guessed")
    t.eq((D.Record(book, seen, reading(nil, 40, "Kobold", {}))), false, "no guid: can't tell one corpse from the next")
    t.eq((D.Record(book, seen, reading("g1", nil, "Kobold", {}))), false, "no creature id")
    t.eq((D.Record(book, seen, { source = { kind = "creature", guid = "g9", id = 40 } })), false, "items not read")
    t.eq(next(book), nil, "nothing written")
end

tests["drops: an unreadable item or count is left out, never guessed"] = function(t)
    local book, seen = {}, {}
    D.Record(book, seen, reading("g1", 40, nil, { { item = "junk", count = 1 }, { item = 97 }, { item = 2589, count = 3 } }))
    t.eq(book[40].name, nil, "no name made up")
    t.eq(book[40].items[97], nil, "no count: not recorded")
    t.eq(book[40].items[2589], { count = 3, times = 1 })
    t.eq(book[40].unread, 2, "and it says how many it could not read")
end

-- ------------------------------------------------------------------ words

local function bookOf(looted, count, times)
    return { [40] = { name = "Kobold Miner", looted = looted, items = { [97] = { count = count, times = times } } } }
end

tests["drop words: under the threshold, counts only"] = function(t)
    t.eq(D.MIN_SAMPLES, 30)
    local lines = Present.DropLines(bookOf(12, 5, 4)[40], { [97] = "Broken Fang" }, D.MIN_SAMPLES)
    t.eq(lines[1], "Kobold Miner: looted 12 times")
    t.ok(has(lines, "Broken Fang: 5 seen, in 4 of 12 loots"), "counts, no percentage")
    t.ok(has(lines, "Too few loots to call these rates (30 needed)."), "and it says why")
end

tests["drop words: from the threshold on, the observed share is shown as observed"] = function(t)
    local lines = Present.DropLines(bookOf(40, 15, 10)[40], { [97] = "Broken Fang" }, D.MIN_SAMPLES)
    t.ok(has(lines, "Broken Fang: 15 seen, in 10 of 40 loots (25% of yours)"), "a share of this character's own loots")
end

tests["drop words: an item with no name, one loot, and nothing dropped"] = function(t)
    local lines = Present.DropLines({ looted = 1, items = { [4444] = { count = 1, times = 1 } } }, nil, 30)
    t.eq(lines[1], "creature: looted 1 time")
    t.ok(has(lines, "item 4444: 1 seen, in 1 of 1 loots"))
    t.eq(Present.DropLines({ name = "Rat", looted = 3, items = {} }, nil, 30)[2], "Nothing dropped yet.")
end

-- ------------------------------------------------------------------ module

local function setLoot(c, r)
    if type(c.setLootWindow) == "function" then return c.setLootWindow(r) end
    c.lootWindow = function() return r end
end

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, opts.char or {})
    local k = ns.Kernel({}, c)
    local diag = ns.Diag.Start(k)
    if opts.setting ~= nil then
        k:Setting({ key = D.SETTING, scope = "char", type = "bool", default = true, label = "Record what you loot" })
    end
    local api = D.Declare(k, diag)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    if opts.setting == false then k.settings:set(D.SETTING, false) end
    return k, c, api, diag
end

local function saved(c)
    local s = c.saved(ns.id.charDB)
    local learned = type(s) == "table" and s.learned or nil
    return type(learned) == "table" and learned.drops or nil
end

tests["drops module: a loot window is recorded for this character"] = function(t)
    local k, c, api = start()
    t.eq((k:ModuleState(D.NAME)), "started")
    setLoot(c, reading("g1", 40, "Kobold Miner", { { item = 97, count = 2 } }))
    c.fire(D.EVENT)
    t.eq(saved(c)[40].looted, 1)
    t.eq(saved(c)[40].items[97].count, 2)
    c.fire(D.EVENT)
    t.eq(saved(c)[40].looted, 1, "the same corpse again: not counted")
    t.eq(api.recorded(), 1)
end

tests["drops module: no loot read, or loot.record off, records nothing"] = function(t)
    local _, c = start()
    c.fire(D.EVENT)
    t.eq(saved(c), nil, "no read on the client: nothing is made")
    local _, c2 = start({ setting = false })
    setLoot(c2, reading("g1", 40, "Kobold Miner", { { item = 97, count = 2 } }))
    c2.fire(D.EVENT)
    t.eq(saved(c2), nil, "off: nothing recorded")
    t.eq(D.SETTING, "loot.record")
end

tests["drops command: the list, one creature, and no match"] = function(t)
    local char = { learned = { drops = {
        [40] = { name = "Kobold Miner", looted = 12, items = { [97] = { count = 5, times = 4 } } },
        [80] = { name = "Kobold Vermin", looted = 3, items = {} } } } }
    local k = start({ char = char })
    local all = D.Run(k, "")
    t.eq(all[1], "Loot recorded from 2 kinds of creature:")
    t.ok(has(all, "Kobold Miner: looted 12 times") and has(all, "Kobold Vermin: looted 3 times"))
    local one = D.Run(k, "kobold miner")
    t.eq(one[1], "Kobold Miner: looted 12 times")
    t.ok(has(one, "item 97: 5 seen, in 4 of 12 loots"))
    t.eq(D.Run(k, "kobold")[1], "Loot recorded from 2 kinds of creature:", "more than one match: the list of them")
    t.eq(D.Run(k, "dragon"), { 'No loot recorded from a creature named "dragon".' })
    t.eq(D.Run((start()), ""), { D.EMPTY })
end

tests["drops: look only - nothing loots, rolls or picks up"] = function(t)
    for name in pairs(D) do
        local n = tostring(name):lower()
        t.ok(not (n:find("^loot$") or n:find("take") or n:find("roll") or n:find("auto") or n:find("pickup")),
            "no acting function: " .. n)
    end
end

return tests

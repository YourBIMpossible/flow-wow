local _, ns = ...

-- Tests for ZFlow/Items/LootNote.lua (L6-E, G8): a chat note that marks junk
-- you just looted, by the same rule as the sell list (Disposition). It never
-- loots, skips, sells or deletes anything.
--
-- Two CLIENT NEEDs the lead adds to Core/Client.lua and Core/ClientFake.lua:
-- client.ownLoot(text) and client.itemInfo(item). Until the fake has them,
-- these tests put the reads on the fake directly, in the same shape.

local N, Present = ns.LootNote, ns.ItemPresent
local tests = {}
-- Item names carry the game's quality colour (Items/Present.lua, Tint; the
-- colour itself is tested in Tests/Items/ItemColourTests.lua). These tests are
-- about the words, so they read them with the colour taken off.
local plain = ns.ItemPresent.Plain

local INFO = {
    [97] = { name = "Broken Fang", quality = 0, sellPrice = 4 },
    [2318] = { name = "Light Leather", quality = 1, sellPrice = 15, classID = 7 },
    [3000] = { name = "Grey Mystery", quality = 0 },
}

local function info(item)
    local id = ns.Items.Id(item)
    local i = id and INFO[id]
    if not i then return nil end
    local out = {}
    for k, v in pairs(i) do out[k] = v end
    return out
end

-- ------------------------------------------------------------------ Note

tests["loot note: junk is marked, with what a vendor pays"] = function(t)
    t.eq(N.Note("item:97", 3, info, {}), "Junk: 3 x Broken Fang (4c each at a vendor)")
    t.eq(N.Note("item:97", nil, info, {}), "Junk: Broken Fang (4c each at a vendor)", "count not known: none shown")
end

tests["loot note: what is not junk gets no note"] = function(t)
    t.eq(N.Note("item:2318", 2, info, {}), nil, "white goods")
    t.eq(N.Note("item:3000", 1, info, {}), nil, "a grey with no known price decides nothing, as in the sell list")
    t.eq(N.Note("item:4444", 1, info, {}), nil, "no facts: no note")
    t.eq(N.Note("nonsense", 1, info, {}), nil, "not an item")
    t.eq(N.Note("item:97", 1, nil, {}), nil, "no item read: no note")
end

tests["loot note: the player's never-sell list is honoured"] = function(t)
    t.eq(N.Note("item:97", 1, info, { choices = { never = { [97] = true } } }), nil)
end

tests["loot note: the same rule as the sell list"] = function(t)
    local sellLeather = { rules = { { key = "all", order = 1, check = function()
        return { action = "sell", reason = "test rule", basis = "recommendation" }
    end } } }
    t.eq(N.Note("item:2318", 2, info, sellLeather), "To sell: 2 x Light Leather (15c each at a vendor)",
        "anything the rules sell is noted; only a 'junk' reason is called junk")
    -- The F-085 words themselves, with the em dash: not the constant restated.
    t.eq(N.Note("item:3000", 1, info, sellLeather), "To sell: 1 x Grey Mystery (price unknown—check vendor)",
        "no price seen: said, no figure")
    t.eq(Present.VENDOR_PRICE_UNKNOWN, "price unknown—check vendor")
end

-- ---------------------------------------------------------------- module

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    if opts.char then c.setSaved(ns.id.charDB, opts.char) end
    if opts.itemInfo ~= false then c.itemInfo = info end
    if opts.ownLoot ~= false then
        -- The fake's answer: "you:<item>:<count>" is the player's own loot.
        c.ownLoot = function(text)
            local item, count = tostring(text):match("^you:(item:%d+):(%d+)$")
            if not item then return nil end
            return item, tonumber(count)
        end
    end
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    if opts.setting ~= nil then
        k:Setting({ key = N.SETTING, scope = "char", type = "bool", default = true, label = "Junk loot note" })
    end
    -- Lead section 220 (SR-1, SR-2): with no reservations module the status
    -- is unavailable and nothing is advised for sale; this kernel has one.
    ns.Reservations.Declare(k)
    local api = N.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    if opts.setting == false then k.settings:set(N.SETTING, false) end
    return k, c, api
end

local function notes(c)
    local out = {}
    for _, p in ipairs(c.printed) do
        if plain(p):find("Junk:", 1, true) or plain(p):find("To sell:", 1, true) then out[#out + 1] = p end
    end
    return out
end

tests["loot note module: your own junk loot prints one note"] = function(t)
    local k, c, api = start()
    t.eq((k:ModuleState(N.NAME)), "started")
    c.fire(N.EVENT, "you:item:97:2")
    local got = notes(c)
    t.eq(#got, 1)
    t.eq(got[1], ns.id.title .. ": Junk: 2 x Broken Fang (4c each at a vendor)")
    t.eq(api.notes(), 1)
end

-- Review of 122e59a, finding 3: no flood of notes while grinding greys.
tests["loot note module: the same item is noted once a minute, not on every loot"] = function(t)
    local _, c, api = start()
    t.eq(N.REPEAT_S, 60)
    c.fire(N.EVENT, "you:item:97:2")
    c.fire(N.EVENT, "you:item:97:1")
    c.advance(30)
    c.fire(N.EVENT, "you:item:97:1")
    t.eq(#notes(c), 1, "three loots of it inside a minute: one note")
    t.eq(api.quieted(), 2, "and it counts the ones it kept quiet")
    c.advance(31)
    c.fire(N.EVENT, "you:item:97:1")
    t.eq(#notes(c), 2, "after the minute it is noted again")
end

tests["loot note module: another item is still noted, and with no time each item is noted once"] = function(t)
    local sellAll = { settings = {} }
    local _, c = start({ char = sellAll })
    INFO[98] = { name = "Bent Claw", quality = 0, sellPrice = 3 }
    c.fire(N.EVENT, "you:item:97:1")
    c.fire(N.EVENT, "you:item:98:1")
    t.eq(#notes(c), 2, "a different item has its own minute")
    local _, c2 = start()
    c2.uptime = function() return nil end
    c2.fire(N.EVENT, "you:item:97:1")
    c2.fire(N.EVENT, "you:item:97:1")
    t.eq(#notes(c2), 1, "no time: once for the session, never a flood")
    INFO[98] = nil
end

tests["loot note module: a never-sell list saved as a list is honoured too"] = function(t)
    local _, c = start({ char = { settings = { sell = { never = { "item:97" } } } } })
    c.fire(N.EVENT, "you:item:97:2")
    t.eq(#notes(c), 0)
end

tests["loot note module: someone else's loot, and non-junk, print nothing"] = function(t)
    local _, c, api = start()
    c.fire(N.EVENT, "Other receives loot: item:97")
    c.fire(N.EVENT, "you:item:2318:1")
    t.eq(#notes(c), 0)
    t.eq(api.notes(), 0)
end

tests["loot note module: without the own-loot read nothing is guessed"] = function(t)
    local _, c = start({ ownLoot = false })
    c.fire(N.EVENT, "you:item:97:2")
    t.eq(#notes(c), 0, "whose loot it is can't be told: no note")
end

tests["loot note module: loot.junkNote off prints nothing; on by default without a row"] = function(t)
    local _, c = start({ setting = false })
    c.fire(N.EVENT, "you:item:97:2")
    t.eq(#notes(c), 0)
    t.eq(N.SETTING, "loot.junkNote")
    local _, c2 = start({ setting = true })
    c2.fire(N.EVENT, "you:item:97:2")
    t.eq(#notes(c2), 1)
end

tests["loot note module: the never-sell list is read from saved data"] = function(t)
    local _, c = start({ char = { settings = { sell = { never = { [97] = true } } } } })
    c.fire(N.EVENT, "you:item:97:2")
    t.eq(#notes(c), 0)
end

tests["loot note: look only - it never loots, skips, sells or deletes"] = function(t)
    for name in pairs(N) do
        local n = tostring(name):lower()
        t.ok(not (n:find("^loot$") or n:find("skip") or n:find("delete") or n:find("^sell$") or n:find("auto")),
            "no acting function: " .. n)
    end
    local called = {}
    local only = setmetatable({}, { __index = function(_, name) called[name] = true return nil end })
    t.eq(N.FromClient(only, nil, "you:item:97:2"), nil, "a client with no reads: nothing")
    t.eq(called, { ownLoot = true }, "it asked for the own-loot read and nothing else")
end

for name, fn in pairs(tests) do
    tests[name] = function(t)
        return fn(setmetatable({ eq = function(got, want, msg) return t.eq(plain(got), plain(want), msg) end },
            { __index = t }))
    end
end

return tests

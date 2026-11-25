local _, ns = ...

-- Tests for ZFlow/Items/Keep.lua (L6-G, G3): the never-sell list from the
-- chat line. It writes only Z-Flow's own saved data (the character's
-- settings.sell.never) and nothing in the game.

local K = ns.ItemKeep
local tests = {}
-- Item names carry the game's quality colour (Items/Present.lua, Tint; the
-- colour itself is tested in Tests/Items/ItemColourTests.lua). These tests are
-- about the words, so they read them with the colour taken off.
local plain = ns.ItemPresent.Plain

local INFO = {
    [97] = { name = "Broken Fang", quality = 0, sellPrice = 4 },
    [2318] = { name = "Light Leather", quality = 1, sellPrice = 15, classID = 7 },
}

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    if opts.char ~= false then c.setSaved(ns.id.charDB, opts.char or {}) end
    c.setBagItems({ { item = 97, count = 3 } })
    if type(c.setItemInfo) == "function" then
        c.setItemInfo(INFO)
    else
        c.itemInfo = function(item)
            local i = INFO[ns.Items.Id(item) or 0]
            if not i then return nil end
            local out = {}
            for k, v in pairs(i) do out[k] = v end
            return out
        end
    end
    local k = ns.Kernel({}, c)
    local diag = ns.Diag.Start(k)
    ns.Reservations.Declare(k)
    local sell = ns.SellList.Declare(k)
    local keep = K.Start(k, diag, sell)
    k:Boot()
    if opts.beforeLoad then return k, c, keep, diag, sell end
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, keep, diag, sell
end

local function never(c)
    local saved = c.saved(ns.id.charDB)
    local s = type(saved) == "table" and saved.settings or nil
    local sell = type(s) == "table" and s.sell or nil
    return type(sell) == "table" and type(sell.never) == "table" and sell.never or {}
end

local function said(c, part)
    for _, p in ipairs(c.printed) do
        if plain(p):find(part, 1, true) then return true end
    end
    return false
end

local function has(lines, text)
    for _, l in ipairs(lines or {}) do
        if plain(l) == text then return true end
    end
    return false
end

local LINK = "|cff9d9d9d|hitem:97:0:0:0:0:0:0:0|h[broken fang]|h|r"   -- as the slash command hands it over: lower-cased

tests["keep: the word is added to the slash command"] = function(t)
    local _, _, _, diag = start()
    t.ok(type(diag.commands[K.WORD]) == "function", "the word is there")
    t.eq(K.WORD, "keep")
end

tests["keep: an item link is put on the never-sell list"] = function(t)
    local k, c = start()
    local lines, changed = K.Run(k, LINK)
    t.eq(changed, true)
    t.eq(never(c)[97], true, "saved for this character")
    t.eq(lines, { "Broken Fang is now on your never-sell list." })
end

tests["keep: a plain item ID works, and an item with no name read is 'item <key>'"] = function(t)
    local k, c = start()
    local lines = K.Run(k, "4444")
    t.eq(never(c)[4444], true)
    t.eq(lines, { "item 4444 is now on your never-sell list." })
end

tests["keep: adding it twice changes nothing and says so"] = function(t)
    local k = start()
    K.Run(k, "97")
    local lines, changed = K.Run(k, "97")
    t.eq(changed, false)
    t.eq(lines, { "Broken Fang is already on your never-sell list." })
end

tests["keep remove: takes it off the list"] = function(t)
    local k, c = start({ char = { settings = { sell = { never = { [97] = true, [2318] = true } } } } })
    local lines, changed = K.Run(k, "remove " .. LINK)
    t.eq(changed, true)
    t.eq(never(c)[97], nil, "gone")
    t.eq(never(c)[2318], true, "the other stays")
    t.eq(lines, { "Broken Fang is off your never-sell list." })
    local again, changed2 = K.Run(k, "remove 97")
    t.eq(changed2, false)
    t.eq(again, { "Broken Fang is not on your never-sell list." })
end

tests["keep: with nothing after it, the list is shown"] = function(t)
    local k = start({ char = { settings = { sell = { never = { [97] = true, [4444] = true } } } } })
    local lines, changed = K.Run(k, "")
    t.eq(changed, false)
    t.eq(lines[1], "Never sold (2):")
    t.ok(has(lines, "Broken Fang") and has(lines, "item 4444"), "each item, by name when it is read")
    local empty = K.Run((start()), "")
    t.eq(empty, { K.EMPTY })
end

tests["keep: something that is no item is refused and nothing is written"] = function(t)
    local k, c = start()
    local lines, changed = K.Run(k, "the fang thing")
    t.eq(changed, false)
    t.eq(lines, { K.USAGE })
    t.eq(next(never(c)), nil)
    t.eq(K.Run(k, "remove"), { K.USAGE }, "remove with no item: the same")
end

-- Review of fec9e2e, finding 2: more than one item in a line is not guessed at.
tests["keep: more than one item in one line is refused, and nothing is written"] = function(t)
    local k, c = start()
    local lines, changed = K.Run(k, LINK .. " |cffffffff|hitem:2318:0:0:0:0:0:0:0|h[light leather]|h|r")
    t.eq(changed, false)
    t.eq(lines, { K.ONE_AT_A_TIME })
    t.eq(next(never(c)), nil, "neither was stored")
    t.eq(K.Run(k, "remove item:97 item:2318"), { K.ONE_AT_A_TIME })
end

-- Finding 3: the list is read the way the sell list reads it (a set or a
-- list), so a write never loses what was saved in the other shape.
tests["keep: a list saved as a list is kept whole when one more is added"] = function(t)
    local k, c = start({ char = { settings = { sell = { never = { 97, "item:2318" } } } } })
    local lines, changed = K.Run(k, "4444")
    t.eq(changed, true)
    t.eq(never(c), { [97] = true, [2318] = true, [4444] = true }, "both old entries are still there, as a set")
    t.eq(K.Run(k, "")[1], "Never sold (3):")
    t.eq(lines, { "item 4444 is now on your never-sell list." })
end

tests["keep: the kept line says what is true: it is on your list"] = function(t)
    local d = ns.Disposition.Decide({ key = 97, count = 1, quality = 0, sellPrice = 4 },
        { choices = { never = { [97] = true } } })
    t.eq(d.reason, "on your never-sell list", "no buyback is claimed: the list is also filled by hand")
    t.eq(d.basis, "choice")
end

-- Re-review of 0ea8d2e, lows 5 and 7: plain words for the player, the full
-- command in the usage line, and every string from the Items text path.
tests["keep: the usage line gives the whole command"] = function(t)
    t.eq(K.USAGE, "Say " .. ns.id.slash .. " keep <item link>, " .. ns.id.slash .. " keep remove <item link>, or "
        .. ns.id.slash .. " keep for the list.")
end

tests["keep: a write the store refuses is said plainly, and the reason kept as a problem"] = function(t)
    local k = start()
    local set = k.store.set
    k.store.set = function() return false, "path settings.sell.never is blocked at settings" end
    local before = k.problems:count("keep")
    local lines, changed = K.Run(k, "97")
    k.store.set = set
    t.eq(changed, false)
    t.eq(lines, { "That could not be saved, so nothing was changed." }, "no internal path or error text for the player")
    t.eq(k.problems:count("keep"), before + 1, "the reason is kept where diagnostics can see it")
end

tests["keep: its words come from the Items text path"] = function(t)
    local P = ns.ItemPresent
    t.eq(K.NOT_LOADED, P.KEEP_NOT_LOADED)
    t.eq(K.EMPTY, P.KEEP_EMPTY)
    t.eq(K.ONE_AT_A_TIME, P.KEEP_ONE_AT_A_TIME)
    t.eq(K.USAGE, P.KeepUsage(ns.id.slash))
    t.eq(P.KeepText("added", "Broken Fang"), "Broken Fang is now on your never-sell list.")
    t.eq(P.KeepText("removed", "Broken Fang"), "Broken Fang is off your never-sell list.")
    t.eq(P.KeepText("already", "Broken Fang"), "Broken Fang is already on your never-sell list.")
    t.eq(P.KeepText("absent", "Broken Fang"), "Broken Fang is not on your never-sell list.")
    t.eq(P.KeepText("failed"), "That could not be saved, so nothing was changed.")
    t.eq(P.KeepText("header", 3), "Never sold (3):")
end

tests["keep: saved data not loaded is said, and nothing is written"] = function(t)
    -- At ADDON_LOADED the kernel makes a new character table when none is
    -- saved, so "not loaded" is the time before it (lead, L6-G merge).
    local k = start({ char = false, beforeLoad = true })
    local lines, changed = K.Run(k, "97")
    t.eq(changed, false)
    t.eq(lines, { K.NOT_LOADED })
end

tests["keep: the command prints its lines with the title"] = function(t)
    local _, c, _, diag = start()
    diag.commands[K.WORD]("97")
    t.ok(said(c, ns.id.title .. ": Broken Fang is now on your never-sell list."))
end

tests["keep: an open sell list shows the change at once"] = function(t)
    local _, c, _, diag, sell = start()
    c.setMerchantOpen(true)
    t.ok(has(sell.last(), "3 x Broken Fang: 4c each, 12c (the item's own sell price)"), "listed to sell first")
    diag.commands[K.WORD]("97")
    t.ok(has(sell.last(), "Broken Fang: on your never-sell list"), "now listed as kept")
    t.eq(sell.shows(), 2, "listed again")
    diag.commands[K.WORD]("remove 97")
    t.ok(has(sell.last(), "3 x Broken Fang: 4c each, 12c (the item's own sell price)"), "and back")
end

tests["keep: with no merchant open the sell list is not read"] = function(t)
    local _, _, _, diag, sell = start()
    diag.commands[K.WORD]("97")
    t.eq(sell.shows(), 0)
end

tests["keep: it writes only the never-sell list"] = function(t)
    local k, c = start({ char = { settings = { sell = { mine = { [5] = "keep" } }, other = 1 }, learned = { x = 1 } } })
    K.Run(k, "97")
    local saved = c.saved(ns.id.charDB)
    t.eq(saved.settings.sell.mine, { [5] = "keep" }, "other choices untouched")
    t.eq(saved.settings.other, 1)
    t.eq(saved.learned, { x = 1 })
end

for name, fn in pairs(tests) do
    tests[name] = function(t)
        return fn(setmetatable({ eq = function(got, want, msg) return t.eq(plain(got), plain(want), msg) end },
            { __index = t }))
    end
end


-- E-13 (lead section 660; Flow Modules/Items/Vendor.lua:718-720): an item
-- the player buys back is put on the never-sell list, so it is not sold
-- again. The buy-back read is client.onBoughtBack (CLIENT NEED, stubbed in
-- the fake: c.buyBack(item) is the player's buy-back).
tests["keep: an item bought back goes on the never-sell list and says so"] = function(t)
    local k, c = start()
    local lines, changed = K.BoughtBack(k, LINK)
    t.eq(changed, true)
    t.eq(never(c)[97], true, "saved for this character")
    t.eq(#lines, 1)
    t.eq(plain(lines[1]), "Broken Fang bought back, so it is now on your never-sell list.")
end

tests["keep: an item bought back that is already kept changes nothing and says nothing"] = function(t)
    local k, c = start()
    K.Run(k, LINK)
    local lines, changed = K.BoughtBack(k, LINK)
    t.eq(changed, false)
    t.eq(#lines, 0)
    t.eq(never(c)[97], true)
end

tests["keep: a buy-back that names no item, or before the saved data loads, writes nothing"] = function(t)
    local k, c = start()
    local lines, changed = K.BoughtBack(k, nil)
    t.eq(changed, false); t.eq(#lines, 0)
    lines, changed = K.BoughtBack(k, "not an item")
    t.eq(changed, false); t.eq(#lines, 0)
    t.eq(next(never(c)), nil)
    local k2 = start({ char = false, beforeLoad = true })
    lines, changed = K.BoughtBack(k2, LINK)
    t.eq(changed, false); t.eq(#lines, 0)
end

tests["keep: the player's buy-back through the client puts it on the list and tells them"] = function(t)
    local _, c = start()
    t.eq(type(c.buyBack), "function", "the fake has the buy-back")
    if type(c.buyBack) ~= "function" then return end
    c.buyBack(LINK)
    t.eq(never(c)[97], true)
    t.ok(said(c, "Broken Fang bought back, so it is now on your never-sell list."))
end

tests["keep: a client with no buy-back read still starts"] = function(t)
    local c = ns.make.fakeClient()
    c.onBoughtBack = nil
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    local k = ns.Kernel({}, c)
    local diag = ns.Diag.Start(k)
    ns.Reservations.Declare(k)
    local keep = K.Start(k, diag, ns.SellList.Declare(k))
    t.eq(type(keep.run), "function")
end

return tests

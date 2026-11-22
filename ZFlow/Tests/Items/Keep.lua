local _, ns = ...

-- Tests for ZFlow/Items/Keep.lua (L6-G, G3): the never-sell list from the
-- chat line. It writes only Z-Flow's own saved data (the character's
-- settings.sell.never) and nothing in the game.

local K = ns.ItemKeep
local tests = {}

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
    local sell = ns.SellList.Declare(k)
    local keep = K.Start(k, diag, sell)
    k:Boot()
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
        if p:find(part, 1, true) then return true end
    end
    return false
end

local function has(lines, text)
    for _, l in ipairs(lines or {}) do
        if l == text then return true end
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

tests["keep: saved data not loaded is said, and nothing is written"] = function(t)
    local k = start({ char = false })
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
    t.ok(has(sell.last(), "Broken Fang: you bought it back, so it's never sold"), "now listed as kept")
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

return tests

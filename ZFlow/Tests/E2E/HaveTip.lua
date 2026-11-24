local _, ns = ...

-- The have-count line on item tooltips (S5, Items/HaveTip.lua), end to
-- end, on the whole add-on loaded on a fake client. The real entry: the
-- game fills an item tooltip (c.showItemTooltip) and the module adds one
-- light blue line saying how many you have in your bags and, as of the
-- last bank visit, in your bank. The bank is read when it opens
-- (BANKFRAME_OPENED). Look only: nothing is sold, moved or equipped.
-- Made-up items. Not tested in game.

local tests = {}

local LINEN, WOOL, ODD = 2589, 2592, 424242
local INFO = {
    [LINEN] = { name = "Linen Cloth", quality = 1, sellPrice = 13, classID = 7 },
    [WOOL] = { name = "Wool Cloth", quality = 1, sellPrice = 33, classID = 7 },
}
local BANK_AS_OF = "in the bank (as of your last bank visit)"

-- opts.bag: the bag stacks (false: the bags are not read); opts.char: the
-- character's saved table; opts.account: the account's.
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setScreen(1024, 768)
    c.setClock(1700000000)
    c.setItemInfo(INFO)
    if opts.bag ~= false then c.setBagItems(opts.bag or { { item = LINEN, count = 3 } }) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

-- The have-count lines the tooltip of `link` got (other modules add theirs).
local function haveLines(c, link)
    local out = {}
    for _, l in ipairs(c.showItemTooltip(link)) do
        if type(l.text) == "string" and l.text:sub(1, 9) == "You have " then out[#out + 1] = l end
    end
    return out
end

local function noneActs(t, c)
    t.eq(#c.soldSlots, 0, "nothing sold")
    t.eq(c.equipCalls, 0, "nothing equipped")
end

local function savedBank(counts)
    return { learned = { bankCounts = { at = 1699990000, counts = counts } } }
end

tests["have tip e2e: bags and the last bank visit add up on the tooltip"] = function(t)
    local c = boot({ char = savedBank({ [LINEN] = 5 }) })
    local lines = haveLines(c, LINEN)
    t.eq(#lines, 1)
    t.eq(lines[1] and lines[1].text, "You have 8: 3 in bags, 5 " .. BANK_AS_OF)
    t.eq(lines[1] and { lines[1].r, lines[1].g, lines[1].b }, { 0.6, 0.85, 1 }, "the light blue line")
    noneActs(t, c)
end

tests["have tip e2e: only in bags, bank not seen yet, says so"] = function(t)
    local c = boot()
    local lines = haveLines(c, LINEN)
    t.eq(#lines, 1)
    t.eq(lines[1] and lines[1].text, "You have 3 in bags (bank not seen yet)")
end

tests["have tip e2e: opening the bank reads it, and the tooltip then counts it"] = function(t)
    local c = boot()
    c.setBank({ { item = LINEN, count = 4 }, { item = WOOL, count = 7 } })
    c.setBankOpen(true)
    local lines = haveLines(c, LINEN)
    t.eq(lines[1] and lines[1].text, "You have 7: 3 in bags, 4 " .. BANK_AS_OF)
    lines = haveLines(c, WOOL)
    t.eq(lines[1] and lines[1].text, "You have 7 " .. BANK_AS_OF .. ", none in bags")
    local saved = c.saved(ns.id.charDB).learned.bankCounts
    t.eq(saved.counts, { [LINEN] = 4, [WOOL] = 7 }, "kept for the next session")
    t.eq(saved.at, 1700000000, "dated with the client clock")
    noneActs(t, c)
end

tests["have tip e2e: a bank seen with none says none in the bank"] = function(t)
    local c = boot({ char = savedBank({ [WOOL] = 2 }) })
    t.eq(haveLines(c, LINEN)[1] and haveLines(c, LINEN)[1].text, "You have 3 in bags, none " .. BANK_AS_OF)
end

tests["have tip e2e: bags that change are read again after a moment"] = function(t)
    local c = boot()
    t.eq(haveLines(c, LINEN)[1].text, "You have 3 in bags (bank not seen yet)")
    c.setBagItems({ { item = LINEN, count = 9 } })
    c.advance(2, 2)
    t.eq(haveLines(c, LINEN)[1] and haveLines(c, LINEN)[1].text, "You have 9 in bags (bank not seen yet)")
end

tests["have tip e2e: unknown data gives no line and no guessed count"] = function(t)
    -- An item never held, bank not seen: no line.
    local c = boot()
    t.eq(#haveLines(c, ODD), 0, "an item you do not have gets no line")
    t.eq(#haveLines(c, "not an item"), 0, "a link that is no item gets no line")
    -- Bags not read: the bank count stands alone and says the bags were not read.
    local c2 = boot({ bag = false, char = savedBank({ [LINEN] = 5 }) })
    local lines = haveLines(c2, LINEN)
    t.eq(lines[1] and lines[1].text, "You have 5 " .. BANK_AS_OF .. "; bags not read")
    -- Bags not read and bank not seen: nothing, never "0".
    local c3 = boot({ bag = false })
    t.eq(#haveLines(c3, LINEN), 0)
    noneActs(t, c3)
end

tests["have tip e2e: the setting off takes the line away"] = function(t)
    local c = boot({ account = { settings = { items = { haveCount = false } } } })
    t.eq(#haveLines(c, LINEN), 0)
end

return tests

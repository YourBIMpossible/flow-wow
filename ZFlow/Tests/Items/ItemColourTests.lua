local _, ns = ...

-- Item names in the colour of their quality (Items/Present.lua: Tint, Plain,
-- Names), in the lists that name an item: the loot note, the merchant's sell
-- list and its kept section, the bank list and its prompt. Offline, over the
-- fake client with made-up items; how the colours look against the game's
-- own windows was not looked at in game.

local P = ns.ItemPresent
local tests = {}

local GREY, WHITE, GREEN, BLUE = "9d9d9d", "ffffff", "1eff00", "0070dd"

local function tint(hex, name) return "|cff" .. hex .. name .. "|r" end

tests["item colour: a name takes the game's colour for its quality"] = function(t)
    t.eq(P.Tint("Test Pelt", 0), tint(GREY, "Test Pelt"), "poor: grey")
    t.eq(P.Tint("Test Cloth", 1), tint(WHITE, "Test Cloth"), "common: white")
    t.eq(P.Tint("Test Blade", 2), tint(GREEN, "Test Blade"), "uncommon: green")
    t.eq(P.Tint("Test Staff", 3), tint(BLUE, "Test Staff"), "rare: blue")
    for q = 0, 5 do
        t.eq(P.Tint("Test Item", q), tint(ns.Kit.Quality(q).hex, "Test Item"), "the kit's own table, quality " .. q)
    end
end

tests["item colour: a quality not known is never guessed"] = function(t)
    t.eq(P.Tint("Test Item", nil), "Test Item", "not read")
    t.eq(P.Tint("Test Item", 9), "Test Item", "no such quality")
    t.eq(P.Tint("Test Item", 1.5), "Test Item", "not a whole number")
    t.eq(P.Tint("Test Item", "2"), "Test Item", "not a number")
    t.eq(P.Tint(tint(BLUE, "Test Staff"), 0), tint(BLUE, "Test Staff"), "coloured already: left alone")
    t.eq(P.Tint("", 2), "", "no name")
    t.eq(P.Tint(nil, 2), nil, "nothing")
end

tests["item colour: the colour comes off again, to sort or compare"] = function(t)
    t.eq(P.Plain(P.Tint("Test Blade", 2)), "Test Blade")
    t.eq(P.Plain("3 x " .. tint(GREY, "Test Pelt") .. ": 5c each"), "3 x Test Pelt: 5c each")
    t.eq(P.Plain({ tint(GREY, "a"), { tint(BLUE, "b") }, 3 }), { "a", { "b" }, 3 }, "a list of lines")
    t.eq(P.Plain(nil), nil)
end

tests["item colour: the name read from the game is coloured by what the game says"] = function(t)
    local names = P.Names(function(id)
        if id == 2589 then return { name = "Test Cloth", quality = 1 } end
        if id == 97 then return { name = "Test Fang" } end
        if id == 13 then error("the read failed") end
        return nil
    end)
    t.eq(names(2589), tint(WHITE, "Test Cloth"))
    t.eq(names("item:2589:0:0:0:0:0:0:0"), tint(WHITE, "Test Cloth"), "a link's own ID")
    t.eq(names(97), "Test Fang", "no quality read: no colour")
    t.eq(names(404), nil, "not read: no name")
    t.eq(names(13), nil, "a failed read: no name")
    t.eq(P.Names(nil), nil, "no reader")
end

tests["item colour: the loot note, the sell row and the bank prompt carry it"] = function(t)
    t.eq(P.LootNoteText({ name = "Test Fang", quality = 0, count = 2, sellPrice = 4 }, { reason = "junk" }),
        "Junk: 2 x " .. tint(GREY, "Test Fang") .. " (4c each at a vendor)")
    t.eq(P.SellRowText({ name = "Test Blade", quality = 2, count = 1, known = true, price = 50, total = 50,
        source = "the item's own sell price" }):find(tint(GREEN, "Test Blade"), 1, true), 5, "after '1 x '")
    t.eq(P.BankPrompt({ ok = true, rows = { { name = "Test Cloth", quality = 1, count = 12 }, { name = "Test Ore", count = 5 } } }),
        P.BANK_PROMPT_HEAD .. tint(WHITE, "Test Cloth") .. " x12, Test Ore x5", "one read, one not")
end

-- ------------------------------------------------------------ whole add-on
local PELT, BLADE, CLOTH = 771, 772, 773
local LINK = {
    pelt = "item:771:0:0:0:0:0:0:0",
    blade = "item:772:0:0:0:0:0:0:0",
    cloth = "item:773:0:0:0:0:0:0:0",
}
local INFO = {
    [PELT] = { name = "Test Pelt", quality = 0, sellPrice = 5 },
    [BLADE] = { name = "Test Blade", quality = 2, sellPrice = 50, classID = 2 },
    [CLOTH] = { name = "Test Cloth", quality = 1, sellPrice = 13, classID = 7 },
}

local function start(t, bag)
    if type(ns.offline) ~= "table" or type(ns.offline.addon) ~= "function" then
        t.skip("no whole add-on offline")
        return nil
    end
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, {})
    c.setItemInfo(INFO)
    c.setBagItems(bag)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function finds(lines, text)
    for _, l in ipairs(lines or {}) do
        if tostring(l):find(text, 1, true) then return true end
    end
    return false
end

tests["item colour module: looting a grey item prints its name in grey"] = function(t)
    local c, addon = start(t, { { item = LINK.pelt, count = 1 } })
    if not c then return end
    local before = #addon.problems:list()
    c.setOwnLoot(function(line) if line == "loot pelt" then return LINK.pelt, 2 end end)
    local from = #c.printed
    c.fire("CHAT_MSG_LOOT", "loot pelt")
    t.eq(#c.printed, from + 1, "one note")
    t.eq(c.printed[#c.printed], ns.id.title .. ": Junk: 2 x " .. tint(GREY, "Test Pelt") .. " (5c each at a vendor)")
    t.eq(#addon.problems:list(), before, "no problem recorded")
end

tests["item colour module: the merchant's list names each item in its own colour"] = function(t)
    local c, addon = start(t, { { item = LINK.pelt, count = 3 }, { item = LINK.blade, count = 1 } })
    if not c then return end
    local before = #addon.problems:list()
    c.setMerchantOpen(true)
    c.advance(1, 4)
    local lines = addon.sellList.last() or {}
    t.ok(finds(lines, "3 x " .. tint(GREY, "Test Pelt") .. ": 5c each"), "the junk, grey: " .. table.concat(lines, " / "))
    t.ok(finds(lines, tint(GREEN, "Test Blade")), "the green blade, green: " .. table.concat(lines, " / "))
    for _, l in ipairs(lines) do
        local _, opened = tostring(l):gsub("|c%x%x%x%x%x%x%x%x", "")
        local _, closed = tostring(l):gsub("|r", "")
        t.eq(opened, closed, "every colour is closed: " .. tostring(l))
    end
    t.eq(#addon.problems:list(), before, "no problem recorded")
end

tests["item colour module: the bank list and its prompt name the cloth in white"] = function(t)
    local c, addon = start(t, { { item = LINK.cloth, count = 20 } })
    if not c then return end
    local before = #addon.problems:list()
    c.setBankOpen(true)
    c.advance(1, 4)
    local lines = addon.bankList.last() or {}
    t.ok(finds(lines, "20 x " .. tint(WHITE, "Test Cloth")), "the row: " .. table.concat(lines, " / "))
    t.eq(#addon.problems:list(), before, "no problem recorded")
end

return tests

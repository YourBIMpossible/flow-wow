local _, ns = ...

-- Bag marks (G4, the slot marks only; the tooltip line is
-- Items/TooltipDisposition.lua's): a small picture in the corner of a bag
-- slot whose item the add-on has an opinion on. Look only: nothing is used,
-- sold, moved or clicked, no attribute is written and no secure frame is
-- made. The opinion is Items/Disposition.lua's, with the context the sell
-- and bank lists use (UI/BankList.lua's Context).
--
--   kind        = BagMarks.KindOf(decision)
--   marks, n    = BagMarks.Marks(slots, itemInfo, context)
--   api         = BagMarks.Declare(k)    api.drawn() (how many, last draw)
--
--   kind    "quest"    a quest item (its item class, or the quest or
--                      questNeeds rule)
--           "upgrade"  Disposition would equip it
--           "sell"     some of it would be sold (junk)
--           "material" kept as a profession's tool or material
--           nil        no opinion worth a mark (a plain keep, auction,
--                      disenchant, not known)
--   slots   client.bagSlots()'s rows { bag, slot, item, count }; nil: the
--           bags were not read, and Marks gives nil (never an empty table)
--   marks   { [bag] = { [slot] = kind } }, only the slots with a kind; the
--           client is given B.TEXTURE[kind] for each
--
-- Setting bags.marks (account, on by default): "Marks on your bag slots".
-- Events: BAG_UPDATE_DELAYED and PLAYER_ENTERING_WORLD, through the bus;
-- the bag window's own redraw through client.onBagRedraw when it has one.
-- Client (first guesses, not seen in game): client.markBagSlots(marks),
-- client.onBagRedraw(fn).

local B = {}
ns.BagMarks = B

B.NAME = "bagMarks"
B.SETTING = "bags.marks"

-- The game textures the client puts on a slot (first guesses, not seen in
-- game on 16001).
B.TEXTURE = {
    quest = "Interface\\GossipFrame\\AvailableQuestIcon",
    upgrade = "Interface\\PetBattles\\BattleBar-AbilityBadge-Strong",
    sell = "Interface\\MoneyFrame\\UI-GoldIcon",
    material = "Interface\\Buttons\\UI-CheckBox-Check",
}
B.WORD = {
    quest = "quest item", upgrade = "upgrade", sell = "junk to sell", material = "kept for a profession",
}

local QUEST = { quest = true, questNeeds = true }
local MATERIAL = { professionMaterial = true, professionTool = true }

function B.KindOf(decision)
    if type(decision) ~= "table" then return nil end
    local found = {}
    local d, seen = decision, {}
    while type(d) == "table" and not seen[d] do
        seen[d] = true
        if QUEST[d.rule] then found.quest = true
        elseif d.action == "equip" then found.upgrade = true
        elseif d.action == "sell" then found.sell = true
        elseif d.action == "keep" and MATERIAL[d.rule] then found.material = true end
        d = d.rest
    end
    for _, kind in ipairs({ "quest", "upgrade", "sell", "material" }) do
        if found[kind] then return kind end
    end
    return nil
end

function B.Marks(slots, itemInfo, context)
    if type(slots) ~= "table" then return nil end
    local marks, n = {}, 0
    for _, row in ipairs(slots) do
        if type(row) == "table" and type(row.bag) == "number" and type(row.slot) == "number" then
            local ok, kind = pcall(function()
                local entries = ns.Bank.Entries({ { item = row.item, count = row.count } }, itemInfo)
                local item = type(entries) == "table" and entries[1] or nil
                if type(item) ~= "table" then return nil end
                -- A quest item is one whatever rule decides first (an
                -- unsellable one is decided by "unsellable", order 2).
                if item.classID == ns.Disposition.QUEST_CLASS then return "quest" end
                return B.KindOf(ns.Disposition.Decide(item, type(context) == "table" and context or {}))
            end)
            if ok and kind then
                marks[row.bag] = marks[row.bag] or {}
                marks[row.bag][row.slot] = kind
                n = n + 1
            end
        end
    end
    return marks, n
end

function B.Declare(k)
    local api, ctx, drawn = {}, nil, 0
    function api.drawn() return drawn end

    local function draw()
        if ctx == nil or type(ctx.client.markBagSlots) ~= "function" then return end
        local marks = {}
        if ctx.settings:get(B.SETTING) == true and type(ctx.client.bagSlots) == "function" then
            local ok, m = pcall(function()
                return B.Marks(ctx.client.bagSlots(), ctx.client.itemInfo, ns.BankList.Context(ctx.store, nil))
            end)
            if ok and type(m) == "table" then
                for bag, slots in pairs(m) do
                    marks[bag] = {}
                    for slot, kind in pairs(slots) do marks[bag][slot] = B.TEXTURE[kind] end
                end
            end
        end
        local ok, n = pcall(ctx.client.markBagSlots, marks)
        drawn = ok and type(n) == "number" and n or 0
    end

    k:Module({
        name = B.NAME,
        needs = { "client", "store", "settings", "bus" },
        settings = { {
            key = B.SETTING, scope = "account", type = "bool", default = true,
            label = "Marks on your bag slots",
            help = "A small mark on a bag slot: ! a quest item, a gold coin junk to sell, a green arrow an "
                .. "upgrade, a tick something kept for a profession. It uses and sells nothing.",
            group = "gear", synonyms = { "quest", "upgrade", "bags", "icon", "mark" },
        } },
        provides = { Drawn = api.drawn },
        start = function(c)
            ctx = c
            c.bus:on(B.NAME, "BAG_UPDATE_DELAYED", draw)
            c.bus:on(B.NAME, "PLAYER_ENTERING_WORLD", draw)
            if type(c.client.onBagRedraw) == "function" then pcall(c.client.onBagRedraw, draw) end
            draw()
        end,
        stop = function()
            if ctx and type(ctx.client.markBagSlots) == "function" then pcall(ctx.client.markBagSlots, {}) end
            ctx = nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.bagMarks = B.Declare(ns)

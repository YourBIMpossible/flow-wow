local _, ns = ...

-- Bag marks (G4, the slot marks only; the tooltip line is
-- Items/TooltipDisposition.lua's): a small picture in the corner of a bag
-- slot whose item the add-on has an opinion on. Look only: nothing is used,
-- sold, moved or clicked, no attribute is written and no secure frame is
-- made. The opinion is Items/Disposition.lua's, with B.Context: the sell
-- and bank lists' context (UI/BankList.lua's) plus the gear and the
-- profession materials (G4).
--
--   kind        = BagMarks.KindOf(decision)
--   marks, n    = BagMarks.Marks(slots, itemInfo, context)
--   api         = BagMarks.Declare(k)    api.drawn() (how many, last draw)
--
--   kind    "quest"    a quest item (its item class, or the quest or
--                      questNeeds rule)
--           "upgrade"  Disposition would equip it, or says it is an
--                      upgrade you can wear now (Disposition.UPGRADE_NOW)
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
-- Client (first guesses, not seen in game): client.markBagKinds(marks),
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
        elseif d.rule == "laterOrOtherRole" and d.reason == ns.Disposition.UPGRADE_NOW then found.upgrade = true
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
                -- The level it asks, from the gear read (G4): Disposition
                -- says "an upgrade you can wear now" only when it is known.
                local g = type(context) == "table" and type(context.gear) == "table" and context.gear[item.key] or nil
                if item.minLevel == nil and type(g) == "table" and type(g.minLevel) == "number" then
                    item.minLevel = g.minLevel
                end
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

-- G4: the in-game context. UI/BankList.lua's Context (never-sell list,
-- bank rules, saved set pieces) and, read here:
--   level            client.level()
--   role             spec.role when the class pack scores it, else the
--                    pack's first role (as the gear why word)
--   gear[key]        { canUse, minLevel, diffs = { [role] = gain } } for each bag item
--                    client.gear(link) reads, judged by Gear/Verdict.lua
--                    against what you wear, the class pack's weights
--   materials[key]   { { prof, what }, ... }: the mats of the recipes saved
--                    from this character's own profession windows (char
--                    learned.facts.recipeBook, Items/RecipeBook.lua)
-- A read that is missing or raises leaves its part out: no mark from it.
local function call(client, read, ...)
    if type(client) ~= "table" or type(client[read]) ~= "function" then return nil end
    local ok, v = pcall(client[read], ...)
    if ok then return v end
    return nil
end

local function rolesOf(pack)
    local out = {}
    if type(pack) == "table" and type(pack.weights) == "table" then
        for role, w in pairs(pack.weights) do
            if type(role) == "string" and type(w) == "table" then out[#out + 1] = role end
        end
    end
    table.sort(out)
    return out
end

local function gearFacts(client, slots, pack, level, roles)
    local skills = call(client, "weaponSkills")
    if type(skills) ~= "table" then skills = nil end
    local gear = {}
    for _, row in ipairs(slots) do
        local key = type(row) == "table" and ns.Items.Key(row.item) or nil
        if key ~= nil and gear[key] == nil then
            local g = call(client, "gear", row.item)
            if type(g) == "table" then
                local fact = { diffs = {} }
                if type(g.minLevel) == "number" then fact.minLevel = g.minLevel end
                for i = 1, #roles do
                    local ok, lines, detail = pcall(ns.GearVerdict.Lines, g,
                        { pack = pack, role = roles[i], level = level, skills = skills })
                    if ok and lines ~= nil and type(detail) == "table" then
                        if type(detail.use) == "table" then fact.canUse = detail.use.can == true end
                        local r = detail.result
                        if type(r) == "table" and type(r.delta) == "number" then fact.diffs[roles[i]] = r.delta end
                    end
                end
                gear[key] = fact
            end
        end
    end
    return gear
end

local function materialsOf(store)
    if type(store) ~= "table" or type(store.get) ~= "function" then return nil end
    local ok, book = pcall(store.get, store, "char", ns.RecipeBook.PATH)
    if not ok or type(book) ~= "table" then return nil end
    local names = {}
    for name in pairs(book) do
        if type(name) == "string" then names[#names + 1] = name end
    end
    table.sort(names)
    local out = {}
    for _, name in ipairs(names) do
        local e = book[name]
        if type(e) == "table" and type(e.profession) == "string" and e.profession ~= "" and type(e.mats) == "table" then
            for item in pairs(e.mats) do
                local key = ns.Items.Key(item)
                if key ~= nil then
                    out[key] = out[key] or {}
                    out[key][#out[key] + 1] = { prof = e.profession, what = name }
                end
            end
        end
    end
    return out
end

function B.Context(client, store, settings, slots, packs)
    local context = ns.BankList.Context(store, nil)
    local level = call(client, "level")
    if type(level) == "number" then context.level = level end
    context.materials = materialsOf(store)
    -- G5: the same facts the sell list gives the outgrown food and drink
    -- rule, so a mark and the list agree. Not tested in game.
    if type(client) == "table" then
        context.consumables = ns.Disposition.ConsumableFacts(slots, client.itemInfo, client.itemLines)
    end
    local class = call(client, "class")
    packs = packs or ns.Packs
    local pack = type(packs) == "table" and class ~= nil and packs[class] or nil
    local roles = rolesOf(pack)
    if #roles > 0 and type(slots) == "table" then
        local chosen
        if type(settings) == "table" and type(settings.get) == "function" then
            local ok, v = pcall(settings.get, settings, ns.GearTooltipModule.ROLE)
            if ok then chosen = v end
        end
        context.role = roles[1]
        for i = 1, #roles do
            if roles[i] == chosen then context.role = chosen end
        end
        context.gear = gearFacts(client, slots, pack, context.level, roles)
    end
    return context
end

function B.Declare(k)
    local api, ctx, drawn = {}, nil, 0
    function api.drawn() return drawn end

    local function draw()
        if ctx == nil or type(ctx.client.markBagKinds) ~= "function" then return end
        local marks = {}
        if ctx.settings:get(B.SETTING) == true and type(ctx.client.bagSlots) == "function" then
            local ok, m = pcall(function()
                local slots = ctx.client.bagSlots()
                return B.Marks(slots, ctx.client.itemInfo, B.Context(ctx.client, ctx.store, ctx.settings, slots))
            end)
            if ok and type(m) == "table" then
                for bag, slots in pairs(m) do
                    marks[bag] = {}
                    for slot, kind in pairs(slots) do marks[bag][slot] = B.TEXTURE[kind] end
                end
            end
        end
        local ok, n = pcall(ctx.client.markBagKinds, marks)
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
            if ctx and type(ctx.client.markBagKinds) == "function" then pcall(ctx.client.markBagKinds, {}) end
            ctx = nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.bagMarks = B.Declare(ns)

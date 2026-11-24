local _, ns = ...

-- Bag marks (G4, the slot marks only; the tooltip line is
-- Items/TooltipDisposition.lua's): a small picture in the corner of a bag
-- slot whose item the add-on has an opinion on. Look only: nothing is used,
-- sold, moved or clicked, no attribute is written and no secure frame is
-- made. The opinion is Items/Disposition.lua's, with B.Context: the sell
-- and bank lists' context (UI/BankList.lua's) plus the gear and the
-- profession materials (G4).
--
--   kind        = BagMarks.KindOf(decision, also)
--   facts       = BagMarks.Facts(bag, context)
--   marks, n    = BagMarks.Marks(slots, itemInfo, context)
--   api         = BagMarks.Declare(k, diag)   api.drawn() (how many, last draw)
--   line        = BagMarks.StateLine(id, on)  what the bags word says
--   line        = BagMarks.UsageLine(id)
--
--   kind    one mark a slot, the first of B.ORDER that applies:
--           "step"     your steps hold some of it (the bank list's "staying
--                      with you": Bank.Pick's held, from the reservations)
--           "quest"    a quest item (its item class, or the quest or
--                      questNeeds rule)
--           "upgrade"  Disposition would equip it, or says it is an
--                      upgrade you can wear now (Disposition.UPGRADE_NOW)
--           "bank"     the bank list would bank it at your next visit
--                      (Bank.Pick's rows)
--           "sell"     some of it would be sold (junk)
--           "auction"  the auctions word would list it (Posting.List: a
--                      price seen in your own searches, worth the house)
--           "material" kept as a profession's tool or material
--           nil        no opinion worth a mark (a plain keep, not known)
--   also    what the lists say of the item: { step, bank, auction }, each
--           true or not; only true is a yes
--   facts   { step = { [key] = true }, bank = ..., auction = ... } for the
--           whole bag, worked out once a draw. All three are empty when
--           what your goals hold is not known (context.grants nil: the
--           reservations are unavailable): not known is never a mark.
--   slots   client.bagSlots()'s rows { bag, slot, item, count }; nil: the
--           bags were not read, and Marks gives nil (never an empty table)
--   marks   { [bag] = { [slot] = kind } }, only the slots with a kind; the
--           client is given B.TEXTURE[kind] for each
--
-- Parity row E-01 (Flow Modules/Items/BagIcons.lua): the step, bank and
-- auction marks. Flow's order top left is step, bank, sell, auction,
-- disenchant, kept here; its top right corner (what the item is: quest,
-- material) is not one the client can draw yet (client.markBagKinds draws
-- one texture a slot), so the two corners share one order: a quest item
-- and an upgrade keep their mark, a material gives way to the bank's and
-- the auctioneer's. No disenchant mark: no rule decides "disenchant", and
-- Flow's is the letters DE, which markBagKinds cannot draw.
--
-- Setting bags.marks (account, on by default): "Marks on your bag slots".
-- Events: BAG_UPDATE_DELAYED and PLAYER_ENTERING_WORLD, through the bus,
-- and Reservations.CHANGED (internal: a goal added or removed);
-- the bag window's own redraw through client.onBagRedraw when it has one.
-- Client (first guesses, not seen in game): client.markBagKinds(marks),
-- client.onBagRedraw(fn).
--
-- The word (parity row E-05), added to diag.commands when a diag is given:
--   <slash> bags       says whether the marks are on, and how to change it
--   <slash> bags on    switches the setting bags.marks on
--   <slash> bags off   switches it off
-- Anything else after the word prints the usage line and changes nothing.
-- It sets the settings row above, no switch of its own, and says on or off
-- only after reading the setting back. Not tested in game.

local B = {}
ns.BagMarks = B

B.NAME = "bagMarks"
B.SETTING = "bags.marks"
B.WORD = "bags"
B.HELP = "bags on, bags off: the marks on your bag slots; bags alone says which it is"

-- The game textures the client puts on a slot (first guesses, not seen in
-- game on 16001).
B.TEXTURE = {
    quest = "Interface\\GossipFrame\\AvailableQuestIcon",
    upgrade = "Interface\\PetBattles\\BattleBar-AbilityBadge-Strong",
    sell = "Interface\\MoneyFrame\\UI-GoldIcon",
    material = "Interface\\Buttons\\UI-CheckBox-Check",
    -- E-01, Flow's own pictures (Modules/Items/BagIcons.lua): the disc its
    -- step ring is made of (drawn here whole and white: the client sets no
    -- colour), the bag it shows where the game has no Banker picture, and
    -- the auctioneer's tracking picture.
    step = "Interface\\CharacterFrame\\TempPortraitAlphaMask",
    bank = "Interface\\Icons\\INV_Misc_Bag_10",
    auction = "Interface\\Minimap\\Tracking\\Auctioneer",
}
B.WORD = {
    quest = "quest item", upgrade = "upgrade", sell = "junk to sell", material = "kept for a profession",
    step = "held for your steps", bank = "for the bank", auction = "worth the auction house",
}
-- When several apply, the first of these is the slot's mark.
B.ORDER = { "step", "quest", "upgrade", "bank", "sell", "auction", "material" }

local QUEST = { quest = true, questNeeds = true }
local MATERIAL = { professionMaterial = true, professionTool = true }

function B.KindOf(decision, also)
    if type(decision) ~= "table" then return nil end
    local found = {}
    if type(also) == "table" then
        for _, kind in ipairs(B.ORDER) do
            if also[kind] == true then found[kind] = true end
        end
    end
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
    for _, kind in ipairs(B.ORDER) do
        if found[kind] then return kind end
    end
    return nil
end

-- E-01: what the bank list and the auctions word say of the whole bag, by
-- their own judgements (Bank.Pick, Posting.List), once a draw. bag:
-- Bank.Entries' entries. context: B.Context's; context.auctionSeen(key) is
-- the latest price seen, as Posting.List asks it. With what your goals
-- hold not known (no context.grants) nothing is said: the bank list then
-- lists with a line saying so and the auctions word offers nothing, and a
-- mark can carry no such line. Nothing is banked, posted or moved.
function B.Facts(bag, context)
    local facts = { step = {}, bank = {}, auction = {} }
    local grants = type(context) == "table" and context.grants or nil
    if type(bag) ~= "table" or type(grants) ~= "table" or type(grants.Held) ~= "function" then return facts end
    local okP, pick = pcall(ns.Bank.Pick, bag, context)
    if okP and type(pick) == "table" and pick.ok == true then
        for _, row in ipairs(pick.held) do facts.step[row.key] = true end
        for _, row in ipairs(pick.rows) do facts.bank[row.key] = true end
    end
    if type(context.auctionSeen) == "function" then
        local okL, rows = pcall(ns.Posting.List, bag, function(item)
            return ns.Disposition.Decide(item, context)
        end, context.auctionSeen)
        if okL and type(rows) == "table" then
            for _, row in ipairs(rows) do facts.auction[row.id] = true end
        end
    end
    return facts
end

function B.Marks(slots, itemInfo, context)
    if type(slots) ~= "table" then return nil end
    local ctx = type(context) == "table" and context or {}
    -- One entry a slot, in the slots' order; read once, for the lists'
    -- facts and for each slot's own decision.
    local okE, bag = pcall(ns.Bank.Entries, slots, itemInfo)
    if not okE or type(bag) ~= "table" then bag = {} end
    -- The level it asks, from the gear read (G4): Disposition says "an
    -- upgrade you can wear now" only when it is known.
    if type(ctx.gear) == "table" then
        for i = 1, #bag do
            local item = bag[i]
            local g = type(item) == "table" and item.key ~= nil and ctx.gear[item.key] or nil
            if type(g) == "table" and item.minLevel == nil and type(g.minLevel) == "number" then
                item.minLevel = g.minLevel
            end
        end
    end
    local facts = B.Facts(bag, ctx)
    local marks, n = {}, 0
    for i, row in ipairs(slots) do
        if type(row) == "table" and type(row.bag) == "number" and type(row.slot) == "number" then
            local ok, kind = pcall(function()
                local item = bag[i]
                if type(item) ~= "table" or item.key == nil then return nil end
                -- The first two of B.ORDER, before the decision: what your
                -- steps hold, then a quest item, which is one whatever rule
                -- decides first (an unsellable one is decided by
                -- "unsellable", order 2).
                if facts.step[item.key] then return "step" end
                if item.classID == ns.Disposition.QUEST_CLASS then return "quest" end
                return B.KindOf(ns.Disposition.Decide(item, ctx),
                    { bank = facts.bank[item.key], auction = facts.auction[item.key] })
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

-- The bags word's lines. id is the add-on's names (ns.id: title, slash);
-- on is the setting as it was read back, true or false.
local function wordOf(id)
    return tostring(id.slash) .. " " .. B.WORD
end

function B.StateLine(id, on)
    if on then
        return tostring(id.title) .. ": bag marks are on. Turn them off with " .. wordOf(id) .. " off."
    end
    return tostring(id.title) .. ": bag marks are off. Turn them on with " .. wordOf(id) .. " on."
end

function B.UsageLine(id)
    local cmd = wordOf(id)
    return tostring(id.title) .. ": " .. cmd .. " on or " .. cmd .. " off switches the marks on your bag slots; "
        .. cmd .. " alone says which it is."
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
-- and, E-01, only when `held` is given (what the bags hold for your goals,
-- SellList.Held's answer; nil: the reservations are unavailable):
--   grants           held, so the lists and each slot's decision count it
--   auctionSeen(key) the latest price seen for an item in your own
--                    searches on this realm (client.realm, client.faction;
--                    account Items/AuctionLog.lua's history), or nil
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

-- The latest look at an item in the player's own searches on this realm,
-- as Items/Posting.lua's own (its seenOn is local to its module), so the
-- mark and the auctions word read the same price. nil when no price is
-- saved for the realm: then nothing is asked for any item.
local function seenOf(client, store)
    if type(store) ~= "table" or type(store.get) ~= "function" then return nil end
    local rk = ns.AuctionLog.RealmKey(call(client, "realm"), call(client, "faction"))
    if rk == nil then return nil end
    local ok, saved = pcall(store.get, store, "account", ns.AuctionLog.PATH .. "." .. rk)
    if not ok or type(saved) ~= "table" then return nil end
    return function(key)
        local id = ns.Items.Id(key)
        local e = id ~= nil and saved[id] or nil
        if not e then return nil end
        local points = ns.PriceChart.Points(e)
        return points[#points]
    end
end

-- What the bags hold for your goals now, from one Reservations evaluation
-- (the sell list's SellList.Current and Held); nil when it is unavailable
-- or can't be asked.
local function heldNow(use)
    if type(use) ~= "function" then return nil end
    local ok, held = pcall(function() return ns.SellList.Held(ns.SellList.Current(use)) end)
    if ok and type(held) == "table" then return held end
    return nil
end

function B.Context(client, store, settings, slots, packs, held)
    local context = ns.BankList.Context(store, held)
    if held ~= nil then context.auctionSeen = seenOf(client, store) end
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

function B.Declare(k, diag)
    local api, ctx, drawn = {}, nil, 0
    function api.drawn() return drawn end

    local function draw()
        if ctx == nil or type(ctx.client.markBagKinds) ~= "function" then return end
        local marks = {}
        if ctx.settings:get(B.SETTING) == true and type(ctx.client.bagSlots) == "function" then
            local ok, m = pcall(function()
                local slots = ctx.client.bagSlots()
                return B.Marks(slots, ctx.client.itemInfo,
                    B.Context(ctx.client, ctx.store, ctx.settings, slots, nil, heldNow(ctx.use)))
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

    -- The setting as it reads now: true or false, nil when it can't be read.
    local function state()
        if ctx == nil then return nil end
        local ok, v = pcall(ctx.settings.get, ctx.settings, B.SETTING)
        if ok and type(v) == "boolean" then return v end
        return nil
    end

    -- The bags word. rest is what follows it, lower-cased by the slash
    -- command. It writes the setting and redraws; it uses, sells and moves
    -- nothing.
    local function run(rest)
        local id = k.id or ns.id
        local client = ctx and ctx.client or k.client
        local function say(line)
            if type(client) == "table" and type(client.print) == "function" then client.print(line) end
        end
        local word = type(rest) == "string" and rest:lower():match("^%s*(.-)%s*$") or ""
        if word ~= "" and word ~= "on" and word ~= "off" then
            say(B.UsageLine(id))
            return
        end
        if ctx == nil then
            say(tostring(id.title) .. ": bag marks are not started yet, so the setting can't be read.")
            return
        end
        if word == "" then
            local now = state()
            if now == nil then
                say(tostring(id.title) .. ": the bag marks setting can't be read.")
            else
                say(B.StateLine(id, now))
            end
            return
        end
        local want = word == "on"
        local ok, done, why = pcall(ctx.settings.set, ctx.settings, B.SETTING, want)
        if not ok then done, why = false, done end
        local now = state()
        draw()
        if done and now == want then
            say(B.StateLine(id, now))
        elseif now == nil then
            say(tostring(id.title) .. ": the bag marks setting can't be read, so it is not known whether it is "
                .. word .. (why ~= nil and (" (" .. tostring(why) .. ")") or "") .. ".")
        else
            say(tostring(id.title) .. ": the bag marks setting could not be changed"
                .. (why ~= nil and (" (" .. tostring(why) .. ")") or "") .. ". Bag marks are still "
                .. (now and "on" or "off") .. ".")
        end
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[B.WORD] = run
        if type(diag.help) == "table" then diag.help[B.WORD] = B.HELP end
    end

    k:Module({
        name = B.NAME,
        needs = { "client", "store", "settings", "bus" },
        settings = { {
            key = B.SETTING, scope = "account", type = "bool", default = true,
            label = "Marks on your bag slots",
            help = "A small mark on a bag slot: a white dot something your steps hold, ! a quest item, a green "
                .. "arrow an upgrade, a bag something for the bank, a gold coin junk to sell, the auctioneer "
                .. "something worth the auction house, a tick something kept for a profession. It uses, sells, "
                .. "banks and posts nothing.",
            group = "gear", synonyms = { "quest", "upgrade", "bags", "icon", "mark" },
        } },
        provides = { Drawn = api.drawn },
        start = function(c)
            ctx = c
            c.bus:on(B.NAME, "BAG_UPDATE_DELAYED", draw)
            c.bus:on(B.NAME, "PLAYER_ENTERING_WORLD", draw)
            -- E-01: a goal added or removed changes what your steps hold.
            c.bus:on(B.NAME, ns.Reservations.CHANGED, draw)
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
ns.bagMarks = B.Declare(ns, ns.diag)

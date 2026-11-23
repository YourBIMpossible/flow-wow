local _, ns = ...
-- Lead section 204. Bank reservations end to end, on the whole add-on loaded
-- on a fake client: a goal's claims (ItemPlan.Claims, through a
-- Reservations source) -> one Resources.Take and Resolve -> the bank list
-- panel, the advisor's bank prompt and the banker word. Each test sets what
-- the client answers and what the goals want, and reads what the player is
-- shown in all three.
-- Offline: the reads are the fake client's, not the game's. Not tested in game.
local tests = {}

local LINEN, PELT, BOLT, POTION = 2589, 4865, 2996, 858
local INFO = {
    [LINEN] = { name = "Linen Cloth", quality = 1, sellPrice = 13, classID = 7 },
    [POTION] = { name = "Lesser Healing Potion", quality = 1, sellPrice = 20, classID = 0 },
    [PELT] = { name = "Ruined Pelt", quality = 0, sellPrice = 5, classID = 15 },
}
local HOUR = 3600

-- goals: { { owner, item, count } }, read when the source is asked, so a test
-- can change them between evaluations. Each goal is a recipe planned by
-- ItemPlan over the evaluation's own snapshot; its claims are ItemPlan's.
local function goalSource(addon, goals)
    return function(snapshot)
        local claims = {}
        for _, g in ipairs(goals) do
            local key = addon.Items.Key(g.item)
            local recipes = { ["make:" .. g.owner] = { makes = BOLT, yield = 1, mats = { [key] = 1 } } }
            local plan = addon.ItemPlan.Build({ recipe = "make:" .. g.owner, count = g.count },
                { recipes = recipes, snapshot = snapshot })
            for _, c in ipairs(addon.ItemPlan.Claims(plan, g.owner, "tailoring")) do
                c.selected = true
                claims[#claims + 1] = c
            end
        end
        return claims
    end
end

-- opts: bag (stacks; false: unread), bank (stacks), char, account, goals,
-- source (a function instead of goals; false: none)
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setClock(1000 + 3 * HOUR)
    c.setItemInfo(INFO)
    if opts.bag ~= false then
        c.setBagItems(opts.bag or { { item = LINEN, count = 15 }, { item = LINEN, count = 5 },
                                    { item = POTION, count = 5 } })
    end
    if opts.bank then c.setBank(opts.bank) end
    local addon = ns.offline.addon(c)
    local goals = opts.goals or {}
    if opts.source then
        addon.Reservations.Source("test", opts.source)
    elseif opts.source ~= false then
        addon.Reservations.Source("test", goalSource(addon, goals))
    end
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon, goals
end

local function panelOf(c)
    for _, p in ipairs(c.panels) do
        if type(p.spec) == "table" and p.spec.name == ns.id.framePrefix .. "BankList" then return p end
    end
    return nil
end

local function promptOf(addon)
    for _, p in ipairs(addon.advisor.List()) do
        if p.id == addon.BankList.PROMPT_ID then return p.text end
    end
    return nil
end

-- What the banker word prints, without the title, split at its sections.
local function banker(c)
    local from = #c.printed
    c.slashes[ns.id.slash]("banker")
    local p = ns.id.title .. ": "
    local out = { all = {}, bank = {}, sell = {} }
    local part = "bank"
    for i = from + 1, #c.printed do
        local line = tostring(c.printed[i])
        if line:sub(1, #p) == p then line = line:sub(#p + 1) end
        out.all[#out.all + 1] = line
        if line:find("^In your bank") then part = (line:find("sell", 1, true) and "sell") or "inBank" end
        if part == "bank" then out.bank[#out.bank + 1] = line
        elseif part == "sell" then out.sell[#out.sell + 1] = line end
    end
    return out
end

local function has(lines, text)
    for _, l in ipairs(lines or {}) do
        if l == text then return true end
    end
    return false
end

local function joined(lines) return table.concat(lines or {}, " / ") end

local function starts(lines, prefix)
    for _, l in ipairs(lines or {}) do
        if l:sub(1, #prefix) == prefix then return true end
    end
    return false
end

-- The panel at a bank visit, and the banker's "to bank" part, which must
-- be the same lines.
local function visit(t, c)
    c.setBankOpen(true)
    local lines = panelOf(c).lines
    local word = banker(c)
    t.eq(word.bank, lines, "the banker word lists what the panel lists")
    c.setBankOpen(false)
    return lines, word
end

local function bumpBags(c)
    c.fire("BAG_UPDATE_DELAYED")
    c.advance(1, 5)
end

tests["bank reservations: the reserved part stays, the free part goes to the bank"] = function(t)
    local c, addon = start({ goals = { { owner = "goal:bolts", item = LINEN, count = 8 } } })
    local lines = visit(t, c)
    t.ok(has(lines, "12 x Linen Cloth: kept for later"), "the free 12 to the bank: " .. joined(lines))
    t.ok(not has(lines, "20 x Linen Cloth: kept for later"), "not all 20")
    t.ok(has(lines, ns.ItemPresent.HELD_HEADER) and has(lines, "8 x Linen Cloth"), "8 held: " .. joined(lines))
    t.eq(promptOf(addon), "1 kind of item to put in the bank.", "the prompt counts the same rows")
end

tests["bank reservations: a goal that holds every stack leaves nothing to bank"] = function(t)
    local c, addon = start({ goals = { { owner = "goal:bolts", item = LINEN, count = 25 } } })
    local lines = visit(t, c)
    t.ok(has(lines, ns.ItemPresent.NOTHING_TO_BANK), joined(lines))
    t.ok(has(lines, "20 x Linen Cloth"), "all 20 held, never more than the bags have: " .. joined(lines))
    t.eq(promptOf(addon), nil, "no prompt")
end

tests["bank reservations: two goals on one item hold their sum, counted once"] = function(t)
    local c = start({ goals = { { owner = "goal:a", item = LINEN, count = 6 },
                                { owner = "goal:b", item = LINEN, count = 4 } } })
    local lines = visit(t, c)
    t.ok(has(lines, "10 x Linen Cloth: kept for later"), joined(lines))
    t.ok(has(lines, "10 x Linen Cloth"), "10 held: " .. joined(lines))
end

tests["bank reservations: a goal made, changed and dropped; nothing stale"] = function(t)
    local c, addon, goals = start({})
    local lines = visit(t, c)
    t.ok(has(lines, "20 x Linen Cloth: kept for later"), "no goal: all 20: " .. joined(lines))
    t.ok(not has(lines, ns.ItemPresent.HELD_HEADER), "nothing held")
    -- Made.
    goals[1] = { owner = "goal:bolts", item = LINEN, count = 20 }
    bumpBags(c)
    t.eq(promptOf(addon), nil, "the prompt follows at the next bag event")
    lines = visit(t, c)
    t.ok(has(lines, ns.ItemPresent.NOTHING_TO_BANK), "all held now: " .. joined(lines))
    -- Changed.
    goals[1].count = 5
    bumpBags(c)
    t.eq(promptOf(addon), "1 kind of item to put in the bank.")
    lines = visit(t, c)
    t.ok(has(lines, "15 x Linen Cloth: kept for later") and has(lines, "5 x Linen Cloth"), joined(lines))
    -- Dropped.
    goals[1] = nil
    bumpBags(c)
    lines = visit(t, c)
    t.ok(has(lines, "20 x Linen Cloth: kept for later"), "dropped: all 20 again: " .. joined(lines))
    t.ok(not has(lines, ns.ItemPresent.HELD_HEADER), "no held list left over")
end

tests["bank reservations: the player's carry and bank choices win over a hold"] = function(t)
    local goals = { { owner = "goal:bolts", item = LINEN, count = 8 } }
    local c = start({ goals = goals, account = { settings = { banker = { rules = { [LINEN] = "carry" } } } } })
    local lines = visit(t, c)
    t.ok(has(lines, ns.ItemPresent.NOTHING_TO_BANK), "carry: none banked: " .. joined(lines))
    c = start({ goals = goals, account = { settings = { banker = { rules = { [LINEN] = "bank" } } } } })
    lines = visit(t, c)
    t.ok(has(lines, "20 x Linen Cloth: you chose to bank it"), "bank: all of it, as chosen: " .. joined(lines))
end

tests["bank reservations: a never-sell item with a hold banks only its free part"] = function(t)
    local c = start({ goals = { { owner = "goal:bolts", item = LINEN, count = 8 } },
                      char = { settings = { sell = { never = { [LINEN] = true } } } } })
    local lines = visit(t, c)
    t.ok(has(lines, "12 x Linen Cloth: kept for later"), joined(lines))
    t.ok(has(lines, "8 x Linen Cloth"), "8 held: " .. joined(lines))
end

tests["bank reservations: what a goal holds in the bank is not offered for sale"] = function(t)
    local c = start({ bag = { { item = POTION, count = 1 } }, bank = { { item = PELT, count = 3 } },
                      goals = { { owner = "goal:pelts", item = PELT, count = 2 } } })
    c.setBankOpen(true)   -- the bank seen: its counts are saved and read
    local word = banker(c)
    c.setBankOpen(false)
    t.ok(starts(word.sell, "1 x Ruined Pelt: "), "one of three to sell: " .. joined(word.sell))
    t.ok(not starts(word.sell, "3 x Ruined Pelt: "), "not all three: " .. joined(word.sell))
end

tests["bank reservations: after a reload, a bank not seen yet still keeps the hold"] = function(t)
    local c = start({ bag = { { item = POTION, count = 1 } },
                      char = { learned = { bankCounts = { at = 1000, counts = { [PELT] = 3 } } } },
                      goals = { { owner = "goal:pelts", item = PELT, count = 2 } } })
    local word = banker(c)
    t.ok(starts(word.sell, "1 x Ruined Pelt: "), "only the one no goal may want: " .. joined(word.sell))
    t.ok(not starts(word.sell, "3 x Ruined Pelt: "), joined(word.sell))
end

tests["bank reservations: no goal at all, the bank's junk is offered for sale"] = function(t)
    local c = start({ bag = { { item = POTION, count = 1 } },
                      char = { learned = { bankCounts = { at = 1000, counts = { [PELT] = 3 } } } } })
    local word = banker(c)
    t.ok(starts(word.sell, "3 x Ruined Pelt: "), joined(word.sell))
end

tests["bank reservations: unavailable says so and offers nothing for sale"] = function(t)
    local c, addon = start({ source = function() error("goals could not be read") end,
                             char = { learned = { bankCounts = { at = 1000, counts = { [PELT] = 3 } } } } })
    c.setBankOpen(true)
    local lines = panelOf(c).lines
    local word = banker(c)
    c.setBankOpen(false)
    t.ok(has(lines, addon.BankList.RESERVATIONS_UNKNOWN), "the panel says it: " .. joined(lines))
    t.ok(has(word.bank, addon.BankList.RESERVATIONS_UNKNOWN), "the word says it: " .. joined(word.bank))
    t.eq(word.sell, { addon.Banker.SELL_UNKNOWN }, "nothing offered for sale")
    t.ok(not has(lines, ns.ItemPresent.HELD_HEADER), "nothing claimed as held")
end

tests["bank reservations: bags not read with a goal is unavailable, not none"] = function(t)
    local c, addon = start({ bag = false, goals = { { owner = "goal:bolts", item = LINEN, count = 8 } },
                             char = { learned = { bankCounts = { at = 1000, counts = { [PELT] = 3 } } } } })
    local word = banker(c)
    t.eq(word.sell, { addon.Banker.SELL_UNKNOWN }, joined(word.all))
end

tests["bank reservations: look only - no acting client call during any of it"] = function(t)
    local c, addon, goals = start({ goals = { { owner = "goal:bolts", item = LINEN, count = 8 } } })
    local acting = { "useContainerItem", "pickupContainerItem", "sell", "buy", "postAuction", "placeBid",
                     "deposit", "withdraw", "splitContainerItem", "deleteCursorItem" }
    local called = {}
    for _, name in ipairs(acting) do
        if type(c[name]) == "function" then
            c[name] = function() called[#called + 1] = name end
        end
    end
    visit(t, c)
    goals[1].count = 3
    bumpBags(c)
    banker(c)
    t.eq(called, {}, "no acting call")
    for name in pairs(addon.Reservations) do
        local n = tostring(name):lower()
        t.ok(not (n:find("deposit") or n:find("withdraw") or n:find("sell") or n:find("move")), "no acting function: " .. n)
    end
end

-- The player's own goals list (Items/Goals.lua), saved for the character,
-- with no test-only source: the add-on's "goals" source alone holds them.
tests["bank reservations: a saved goal holds its count, the rest goes to the bank"] = function(t)
    local c, addon = start({ source = false,
                             char = { settings = { goals = { { item = LINEN, count = 8 } } } } })
    local lines = visit(t, c)
    t.ok(has(lines, "12 x Linen Cloth: kept for later"), "the free 12 to the bank: " .. joined(lines))
    t.ok(has(lines, ns.ItemPresent.HELD_HEADER) and has(lines, "8 x Linen Cloth"), "8 held: " .. joined(lines))
    t.eq(promptOf(addon), "1 kind of item to put in the bank.")
end

tests["bank reservations: a goal added with the goal word holds at the next look"] = function(t)
    local c, addon = start({ source = false })
    local lines = visit(t, c)
    t.ok(has(lines, "20 x Linen Cloth: kept for later"), "no goal yet: all 20: " .. joined(lines))
    c.slashes[ns.id.slash]("goal add " .. LINEN .. " 8")
    bumpBags(c)
    lines = visit(t, c)
    t.ok(has(lines, "12 x Linen Cloth: kept for later") and has(lines, "8 x Linen Cloth"), joined(lines))
    t.eq(promptOf(addon), "1 kind of item to put in the bank.")
end

-- The sell side (UI/SellList.lua, one evaluation per merchant visit) holds
-- the same saved goal: the player is not offered what the goal keeps.
local function sellLines(c)
    c.setMerchantOpen(true)
    local lines
    for _, p in ipairs(c.panels) do
        if type(p.spec) == "table" and p.spec.name == ns.id.framePrefix .. "SellList" then lines = p.lines end
    end
    c.setMerchantOpen(false)
    return lines
end

tests["bank reservations: a saved goal is held at the merchant too, only the rest is offered"] = function(t)
    local c = start({ source = false, bag = { { item = PELT, count = 3 }, { item = POTION, count = 2 } },
                      char = { settings = { goals = { { item = PELT, count = 2 } } } } })
    local lines = sellLines(c)
    t.ok(lines ~= nil, "the sell panel was drawn")
    t.ok(has(lines, "Ruined Pelt: 2 held for your steps"), "two kept, with why: " .. joined(lines))
    local one, three = false, false
    for _, l in ipairs(lines or {}) do
        if l:sub(1, 17) == "1 x Ruined Pelt: " then one = true end
        if l:sub(1, 17) == "3 x Ruined Pelt: " then three = true end
    end
    t.ok(one and not three, "one of three offered: " .. joined(lines))
    c.slashes[ns.id.slash]("goal remove " .. PELT)
    lines = sellLines(c)
    three = false
    for _, l in ipairs(lines or {}) do
        if l:sub(1, 17) == "3 x Ruined Pelt: " then three = true end
    end
    t.ok(three and not has(lines, "Ruined Pelt: 2 held for your steps"), "goal gone, all three: " .. joined(lines))
end

return tests

local _, ns = ...

-- Tests for ZFlow/UI/ProfDock.lua (lead section 387): the one panel under
-- the game's profession window. First the pure parts (the next step in
-- plain words for every kind of step, the reason when there is no step, the
-- list and its order, where the panel stands), then the whole add-on on a
-- fake client: the panel shows with the profession window and hides with
-- it, the setting turns it off, and a recipe the player has not learned is
-- never listed as something to make.
-- Every recipe, item, price and trainer here is made up.
-- Offline: the reads are the fake client's, not the game's. Not tested in game.
-- Red before the code: ns.ProfDock does not exist, so every test fails.

local tests = {}

local function D() return ns.ProfDock end
local function has(t)
    t.eq(type(D()), "table", "ns.ProfDock")
    return type(D()) == "table"
end

-- Items: 1 Test Ore, 2 Test Bar, 3 Test Cloth, 4 Test Thread.
local NAMES = { [1] = "Test Ore", [2] = "Test Bar", [3] = "Test Cloth", [4] = "Test Thread",
    [50] = "Test Buckle", [51] = "Test Nail" }
local PRICES = { [2] = 100, [3] = 10, [4] = 5 }

local BOOK = {
    ["Test Buckle"] = { profession = "Blacksmithing", makes = 50, mats = { [2] = 2 } },
    ["Test Nail"] = { profession = "Blacksmithing", makes = 51, mats = { [2] = 1 } },
    ["Test Old Rod"] = { profession = "Blacksmithing", makes = 52, mats = { [2] = 1 } },
    ["Smelt Test Bar"] = { profession = "Mining", makes = 2, mats = { [1] = 2 } },
    ["Test Bolt"] = { profession = "Tailoring", makes = 53, mats = { [3] = 2, [4] = 1 } },
    ["Test Patch"] = { profession = "Tailoring", makes = 54, mats = { [3] = 1 } },
}
-- At 50: Buckle orange, Nail yellow, Old Rod grey; Bolt orange, Patch yellow.
local COLOURS = {
    ["Test Buckle"] = { optimal = { lo = 45, hi = 55 } },
    ["Test Nail"] = { medium = { lo = 48, hi = 60 } },
    ["Test Old Rod"] = { trivial = { lo = 40, hi = 60 } },
    ["Test Bolt"] = { optimal = { lo = 50, hi = 52 } },
    ["Test Patch"] = { medium = { lo = 50, hi = 60 } },
}

local function input(over)
    local i = {
        prof = "Blacksmithing", skill = 50, max = 75,
        book = BOOK, colours = COLOURS,
        bags = {}, bank = {},
        price = function(item) return PRICES[item] end,
        name = function(item) return NAMES[item] end,
    }
    for k, v in pairs(over or {}) do i[k] = v end
    return i
end

local function names(rows)
    local out = {}
    for i, r in ipairs(rows) do out[i] = r.recipe end
    return out
end

local function keyed(view, key)
    for _, part in ipairs(view.children) do
        if part.key == key then return part end
    end
    return nil
end

-- -------------------------------------------------------------- next step
tests["prof dock: the next step in plain words, for every kind of step"] = function(t)
    if not has(t) then return end
    local i = input()
    local cases = {
        { { kind = "learn_recipe", recipe = "Test Nail" }, "Learn Test Nail from the trainer", nil },
        { { kind = "learn_recipe", recipe = "Test Nail", npc = "Test Smith" }, "Learn Test Nail from the trainer",
            "Trainer: Test Smith" },
        { { kind = "train_tier" }, "Train the next Blacksmithing rank at the trainer",
            "Your skill is at its cap until you do." },
        { { kind = "craft", recipe = "Test Buckle", item = 50, count = 3 }, "Make 3 Test Buckle", nil },
        { { kind = "craft", recipe = "Test Buckle", item = 50, count = 3, station = "anvil" }, "Make 3 Test Buckle",
            "At an anvil" },
        { { kind = "craft", recipe = "Test Unnamed", item = 99, count = 2 }, "Make Test Unnamed 2 times", nil },
        { { kind = "craft", recipe = "Test Unnamed", item = 99, count = 1 }, "Make Test Unnamed once", nil },
        { { kind = "make_part", item = 2, count = 4, recipe = "Test Buckle" }, "Smelt 4 Test Bar", "For Test Buckle" },
        { { kind = "make_part", item = 2, count = 4, station = "forge" }, "Smelt 4 Test Bar at a forge", nil },
        { { kind = "take_bank", item = 1, count = 6, recipe = "Test Buckle" }, "Take 6 Test Ore from the bank",
            "For Test Buckle" },
        { { kind = "gather", item = 1, count = 5 }, "Gather 5 Test Ore", nil },
        { { kind = "buy_vendor", item = 4, count = 2 }, "Buy 2 Test Thread from a trade goods vendor", nil },
        { { kind = "buy_auction", item = 3, count = 7 }, "Buy 7 Test Cloth at the auction house", nil },
        { { kind = "go_station", station = "anvil" }, "Go to an anvil", nil },
        { { kind = "go_station", station = "forge" }, "Go to a forge", nil },
        { { kind = "later_kind", text = "The planner's own line" }, "The planner's own line", nil },
        { { kind = "later_kind" }, "Follow the next step in your plan", nil },
    }
    for n, case in ipairs(cases) do
        local line, sub = D().StepText(case[1], i)
        t.eq(line, case[2], "case " .. n .. " (" .. case[1].kind .. ")")
        t.eq(sub, case[3], "case " .. n .. " sub")
    end
end

tests["prof dock: a smelt reads Smelt, and never twice"] = function(t)
    if not has(t) then return end
    local i = input({ prof = "Mining" })
    t.eq((D().StepText({ kind = "craft", recipe = "Smelt Test Bar", item = 2, count = 4 }, i)), "Smelt 4 Test Bar")
    t.eq((D().StepText({ kind = "craft", recipe = "Smelt Test Odd", item = 99, count = 2 }, i)),
        "Smelt Test Odd 2 times")
end

tests["prof dock: an item with no name still reads as a sentence"] = function(t)
    if not has(t) then return end
    local line = D().StepText({ kind = "take_bank", item = 77, count = 2 }, input())
    t.eq(line, "Take 2 of a material from the bank")
    t.eq(D().StepText(nil, input()), nil, "no step, no line")
end

tests["prof dock: the box carries the plan's first step, its count and item"] = function(t)
    if not has(t) then return end
    local steps = { { kind = "take_bank", item = 1, count = 6 }, { kind = "craft", recipe = "Test Buckle", item = 50,
        count = 1 } }
    local n = D().Next(steps, nil, nil, input())
    t.eq(n.text, "Take 6 Test Ore from the bank")
    t.eq(n.kind, "take_bank")
    t.eq(n.item, 1)
    t.eq(n.count, 6)
    t.eq(n.empty, nil)
end

-- ------------------------------------------------------------- empty plan
tests["prof dock: an empty plan says why and what to do, never blank"] = function(t)
    if not has(t) then return end
    local i = input()
    local n = D().Next({}, "no recipe", nil, i)
    t.eq(n.empty, true)
    t.eq(n.text, "None of your recipes gives a skill point now.")
    t.eq(n.sub, "Open a Blacksmithing trainer once so " .. ns.id.title .. " can read what you can learn.")
    n = D().Next({}, "no reading", nil, i)
    t.eq(n.text, ns.id.title .. " has not read your Blacksmithing skill yet.")
    t.eq(n.sub, "Close this window and open it again.")
    n = D().Next({}, "no colours", nil, i)
    t.eq(n.text, ns.id.title .. " has not read these recipes yet.")
    n = D().Next({}, "no materials", nil, i, { { recipe = "Test Buckle" } })
    t.eq(n.text, "You lack the materials for Test Buckle.")
    t.eq(n.sub, "The list below says what each recipe needs.")
    for _, why in ipairs({ "a reason added later", false }) do
        n = D().Next(nil, why or nil, nil, i)
        t.ok(type(n.text) == "string" and n.text ~= "", "an unknown reason still has a line")
        t.ok(type(n.sub) == "string" and n.sub ~= "")
    end
    n = D().Next(nil, nil, nil, nil)
    t.eq(n.text, ns.id.title .. " could not tell which profession this is.")
    t.eq(n.empty, true)
end

-- ------------------------------------------------------------------- list
tests["prof dock: the list is the planner's order: sure first, then the cheapest"] = function(t)
    if not has(t) then return end
    local rows = D().Rows(input())
    t.eq(names(rows), { "Test Buckle", "Test Nail" }, "grey and other professions never listed")
    t.eq(rows[1].chance, "sure")
    t.eq(rows[2].chance, "maybe")
    local both = D().Rows(input({ colours = {
        ["Test Buckle"] = { medium = { lo = 45, hi = 55 } }, ["Test Nail"] = { medium = { lo = 45, hi = 55 } } } }))
    t.eq(names(both), { "Test Nail", "Test Buckle" }, "two maybes: the cheaper first")
end

tests["prof dock: no more rows than the limit"] = function(t)
    if not has(t) then return end
    local book, colours = {}, {}
    for n = 1, 8 do
        local name = "Test Thing " .. n
        book[name] = { profession = "Blacksmithing", makes = 100 + n, mats = { [2] = n } }
        colours[name] = { optimal = { lo = 40, hi = 60 } }
    end
    local rows = D().Rows(input({ book = book, colours = colours }))
    t.eq(#rows, D().ROWS)
    t.eq(D().ROWS, 5)
    t.eq(rows[1].recipe, "Test Thing 1", "the cheapest first")
    t.eq(rows[5].recipe, "Test Thing 5")
    t.eq(#D().Rows(input({ book = book, colours = colours }), { limit = 2 }), 2)
end

tests["prof dock: each row says what one craft is missing, and where it comes from"] = function(t)
    if not has(t) then return end
    local rows = D().Rows(input({ bags = { [2] = 1 } }))
    local buckle, nail = rows[1], rows[2]
    t.eq(buckle.ready, false)
    t.eq(#buckle.missing, 1)
    t.eq(buckle.missing[1].item, 2)
    t.eq(buckle.missing[1].count, 1, "two needed, one held")
    t.eq(buckle.missing[1].name, "Test Bar")
    t.eq(buckle.missing[1].from, "buy_auction", "nothing nearer is known")
    t.eq(nail.ready, true, "one bar is enough for a nail")
    t.eq(#nail.missing, 0)

    local banked = D().Rows(input({ bank = { [2] = 9 } }))
    t.eq(banked[1].missing[1].from, "bank")
    t.eq(banked[1].missing[1].bank, 9)
    local smelt = D().Rows(input({ bags = { [1] = 2 } }))
    t.eq(smelt[1].missing[1].from, "smelt", "ore in the bags and the smelt is known")
    local bankFirst = D().Rows(input({ bags = { [1] = 2 }, bank = { [2] = 1 } }))
    t.eq(bankFirst[1].missing[1].from, "bank", "the bank before a smelt")
    local sold = D().Rows(input({ vendorPrice = function(item) if item == 2 then return 40 end end }))
    t.eq(sold[1].missing[1].from, "buy_vendor")
end

tests["prof dock: the hover gives the reason"] = function(t)
    if not has(t) then return end
    local rows = D().Rows(input({ bank = { [2] = 1 } }))
    local tip = rows[1].tooltip
    t.ok(tip:find("Sure skill point: this recipe is orange.", 1, true), tip)
    t.ok(tip:find("(estimate)", 1, true), "a price is always called an estimate: " .. tip)
    t.ok(tip:find("The cheapest of your recipes that still give a point.", 1, true), tip)
    t.ok(tip:find("Missing 2 Test Bar: take it from your bank (1 there).", 1, true), tip)
    t.ok(rows[2].tooltip:find("Might give a skill point: this recipe is yellow.", 1, true), rows[2].tooltip)
    t.ok(not rows[2].tooltip:find("The cheapest of your recipes", 1, true), "only the first row is the cheapest")
    local ready = D().Rows(input({ bags = { [2] = 5 } }))
    t.ok(ready[1].tooltip:find("You have everything to make one.", 1, true), ready[1].tooltip)
    local unpriced = D().Rows(input({ price = function() return nil end }))
    t.ok(unpriced[1].tooltip:find("No price seen for its materials yet", 1, true), unpriced[1].tooltip)
end

tests["prof dock: learn the recipe first: one the window says is not learned is never listed"] = function(t)
    if not has(t) then return end
    local rows = D().Rows(input(), { known = { ["Test Buckle"] = false } })
    t.eq(names(rows), { "Test Nail" })
    -- A recipe that is not in the book at all (never learned) cannot appear,
    -- whatever its colour.
    local colours = { ["Test Never Learned"] = { optimal = { lo = 40, hi = 60 } } }
    t.eq(#D().Rows(input({ colours = colours })), 0)
    t.eq(#D().Rows(nil), 0)
    t.eq(#D().Rows({}), 0)
end

-- ------------------------------------------------------------------- view
tests["prof dock: the view is a next-step box, then the list; no empty boxes"] = function(t)
    if not has(t) then return end
    local i = input({ bags = { [2] = 1 } })
    local rows = D().Rows(i, {
        info = function(item) return { name = NAMES[item], quality = 2 } end,
        icon = function(recipe) return "Interface\\Icons\\" .. recipe:gsub(" ", "") end,
    })
    local view = D().View({ prof = "Blacksmithing", rows = rows,
        next = D().Next({ { kind = "take_bank", item = 1, count = 6 } }, nil, nil, i) })
    t.eq(view.id, "ProfDock")
    t.eq(view.title, ns.id.title .. ": Blacksmithing")
    t.eq(view.escape, false, "Escape closes the profession window, not this")
    t.eq(view.children[1].kind, "section")
    t.eq(view.children[1].text, "Next step")
    t.eq(keyed(view, "next").text, "Take 6 Test Ore from the bank")
    t.eq(keyed(view, "listHead").text, "Cheapest skill points")
    local first, second = keyed(view, "row1"), keyed(view, "row2")
    local q = ns.Kit.Quality(2)
    t.eq(first.text, "|cff" .. q.hex .. "Test Buckle|r", "the item's name in its rarity colour")
    t.eq(first.icon, "Interface\\Icons\\TestBuckle")
    t.eq(first.right, "Need 1 Test Bar")
    t.eq(first.tone, "warn")
    t.eq(second.right, "Ready")
    t.eq(second.tone, "good")
    t.ok(type(first.tooltip) == "string" and first.tooltip ~= "")
    for _, part in ipairs(view.children) do
        t.ok(type(part.text) == "string" and part.text ~= "", "every part has text: " .. tostring(part.key))
        t.eq(part.onClick, nil, "nothing here is a button: " .. tostring(part.key))
    end
    t.eq(view.height, D().Height(rows))
    t.ok(ns.Kit.Window(view) ~= nil, "the kit takes the view")

    local bare = D().View({ prof = "Blacksmithing", rows = {}, next = D().Next({}, "no recipe", nil, i) })
    t.eq(keyed(bare, "listHead"), nil, "no heading over an empty list")
    t.eq(#bare.children, 2)
    t.ok(bare.height < view.height, "a panel with no list is shorter")
    t.ok(#D().View(nil).children == 2 and D().View(nil).children[2].text ~= "", "no model still draws a line")
end

tests["prof dock: more than one missing material is counted, and an unread rarity is plain"] = function(t)
    if not has(t) then return end
    local rows = D().Rows(input({ prof = "Tailoring" }))
    local view = D().View({ prof = "Tailoring", rows = rows, next = D().Next({}, "no materials", nil, input()) })
    t.eq(keyed(view, "row1").text, "Test Bolt", "no rarity read: the plain name")
    t.eq(keyed(view, "row1").right, "Need 2 Test Cloth +1 more")
    local plain = D().Plain({ rows = rows, next = D().Next({}, "no recipe", nil, input({ prof = "Tailoring" })) })
    t.eq(plain[1].text, "Next step: None of your recipes gives a skill point now.")
    t.eq(plain[3].text, "Test Bolt: Need 2 Test Cloth +1 more")
end

-- ------------------------------------------------------------------ place
tests["prof dock: it stands under the profession window, as wide as it"] = function(t)
    if not has(t) then return end
    local point, width, where = D().Dock({ l = 20, r = 404, b = 300, t = 700 }, 1024, 768, 200)
    t.eq(point, { "TOPLEFT", "BOTTOMLEFT", 20, 300 - D().GAP })
    t.eq(width, 384)
    t.eq(where, "under")
    local _, wide = D().Dock({ l = 20, r = 920, b = 300, t = 700 }, 1024, 768, 200)
    t.eq(wide, D().MAX_WIDTH, "never wider than the kit's lines read well")
    local _, narrow = D().Dock({ l = 20, r = 120, b = 300, t = 700 }, 1024, 768, 200)
    t.eq(narrow, D().MIN_WIDTH)
end

tests["prof dock: beside the window when there is no room under it, else its own place"] = function(t)
    if not has(t) then return end
    local point, _, where = D().Dock({ l = 20, r = 404, b = 100, t = 600 }, 1024, 768, 200)
    t.eq(where, "beside")
    t.eq(point, { "TOPLEFT", "BOTTOMLEFT", 404 + D().GAP, 600 })
    t.eq(D().Dock({ l = 600, r = 1000, b = 100, t = 600 }, 1024, 768, 200), nil, "no room either way")
    t.eq(D().Dock(nil, 1024, 768, 200), nil)
    t.eq(D().Dock({ l = 20, r = 404, b = 300, t = 700 }, nil, nil, 200), nil, "the screen is not read")
    t.eq(D().Dock({ l = 20, r = 404, b = 300 }, 1024, 768, 200), nil, "half a rectangle")
    t.eq(D().Dock({ l = 404, r = 20, b = 300, t = 700 }, 1024, 768, 200), nil)
    local low = D().Dock({ l = 20, r = 404, b = 100, t = 150 }, 1024, 768, 200)
    t.eq(low[4], 200, "kept on the screen")
end

-- ------------------------------------------------- the whole add-on, faked
-- opts: bags, bank (char), setting (false: off), unknown (a recipe the
-- window lists as not learned), frame (false: no rectangle), frames (false:
-- no kit window).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, { learned = {
        facts = { profSkill = { Blacksmithing = { skill = 50, max = 75 } }, recipeBook = opts.book or BOOK },
        recipeColors = COLOURS,
        bankCounts = opts.bank and { counts = opts.bank } or nil,
    } })
    c.setScreen(1024, 768)
    if opts.frames == false then c.setFrames(false) end
    if opts.frame ~= false then c.setFrameRect("TradeSkillFrame", { l = 20, r = 404, b = 400, t = 760 }) end
    c.setItemInfo({ [50] = { name = "Test Buckle", quality = 2 }, [51] = { name = "Test Nail", quality = 1 },
        [2] = { name = "Test Bar", quality = 1 } })
    if opts.bags then c.setBagItems(opts.bags) end
    local recipes = {
        { id = 11, name = "Test Buckle", learned = true, difficulty = "optimal", icon = "Interface\\Icons\\TestBuckle" },
        { id = 12, name = "Test Nail", learned = opts.unknown ~= "Test Nail", difficulty = "medium" },
    }
    c.setRecipes({ profession = 164, name = "Blacksmithing", skill = 50, max = 75, recipes = recipes })
    local addon = ns.offline.addon(c)
    -- Lead section 450: the dock is what stands when the profession path
    -- panel is turned off; with it on, the dock steps aside (Tests/E2E/ProfPathPanel.lua).
    addon.settings:set(ns.ProfPathPanel.SETTING, false)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    if opts.setting == false then addon.settings:set(D().SETTING, false) end
    return c, addon
end

local function window(c) return c.kitWindows()[D().ID] end

local function texts(w)
    local out = {}
    for _, part in ipairs(w.parts) do out[#out + 1] = tostring(part.text) end
    return table.concat(out, "\n")
end

tests["prof dock module: shown when the profession window opens, hidden when it closes"] = function(t)
    if not has(t) then return end
    local c = start()
    t.ok(window(c) == nil or window(c).shown == false, "nothing before a profession window")
    c.fire("TRADE_SKILL_SHOW")
    local w = window(c)
    t.ok(w ~= nil and w.shown == true, "shown with the profession window")
    if w == nil then return end
    t.ok(texts(w):find("Next step", 1, true), texts(w))
    c.fire("TRADE_SKILL_CLOSE")
    t.eq(window(c).shown, false, "hidden with it")
    c.fire("TRADE_SKILL_SHOW")
    t.eq(window(c).shown, true, "and back on the next open")
end

tests["prof dock module: it stands under the game's window, and follows it on the next open"] = function(t)
    if not has(t) then return end
    local c = start()
    c.fire("TRADE_SKILL_SHOW")
    local w = window(c)
    if w == nil then return t.ok(false, "no window") end
    t.eq(w.point, { "TOPLEFT", "BOTTOMLEFT", 20, 400 - D().GAP })
    t.eq(w.width, 384)
    c.fire("TRADE_SKILL_CLOSE")
    c.setFrameRect("TradeSkillFrame", { l = 300, r = 684, b = 500, t = 760 })
    c.fire("TRADE_SKILL_SHOW")
    t.eq(window(c).point, { "TOPLEFT", "BOTTOMLEFT", 300, 500 - D().GAP }, "the player moved the game's window")
end

tests["prof dock module: no rectangle read: still shown, at its own place"] = function(t)
    if not has(t) then return end
    local c = start({ frame = false })
    c.fire("TRADE_SKILL_SHOW")
    local w = window(c)
    t.ok(w ~= nil and w.shown == true)
    if w then t.eq(w.point, D().DEFAULT_POINT) end
end

tests["prof dock module: the setting turns it off, and on again"] = function(t)
    if not has(t) then return end
    local c, addon = start({ setting = false })
    c.fire("TRADE_SKILL_SHOW")
    t.ok(window(c) == nil or window(c).shown == false, "off: nothing shown")
    addon.settings:set(D().SETTING, true)
    c.fire("TRADE_SKILL_SHOW")
    t.ok(window(c) ~= nil and window(c).shown == true, "on again")
    t.eq(addon.settings:get(D().SETTING), true)
end

tests["prof dock module: the setting is on unless turned off"] = function(t)
    if not has(t) then return end
    local _, addon = start()
    t.eq(addon.settings:get(D().SETTING), true)
end

tests["prof dock module: the next step and the list come from the plan"] = function(t)
    if not has(t) then return end
    local c = start({ bags = { { id = 2, count = 1 } } })
    c.fire("TRADE_SKILL_SHOW")
    local w = window(c)
    if w == nil then return t.ok(false, "no window") end
    local said = texts(w)
    t.ok(said:find("Cheapest skill points", 1, true), said)
    t.ok(said:find("Test Buckle", 1, true), said)
    t.ok(said:find("Test Nail", 1, true), said)
    local at = {}
    for i, part in ipairs(w.parts) do at[part.key or i] = part.text end
    t.ok(type(at.next) == "string" and at.next ~= "", "the next-step box is never blank")
    t.ok(tostring(at.row1):find("Test Buckle", 1, true), "the sure point first: " .. tostring(at.row1))
    t.ok(tostring(at.row2):find("Test Nail", 1, true), tostring(at.row2))
end

tests["prof dock module: a recipe the window says is not learned is never listed"] = function(t)
    if not has(t) then return end
    local c = start({ unknown = "Test Nail" })
    c.fire("TRADE_SKILL_SHOW")
    local w = window(c)
    if w == nil then return t.ok(false, "no window") end
    for _, part in ipairs(w.parts) do
        if type(part.key) == "string" and part.key:find("^row") then
            t.ok(not tostring(part.text):find("Test Nail", 1, true), "listed as something to make: " .. part.text)
        end
    end
end

tests["prof dock module: nothing learned yet: a plain reason, never blank"] = function(t)
    if not has(t) then return end
    local c = start({ book = {} })
    c.setRecipes({ profession = 164, name = "Blacksmithing", skill = 50, max = 75, recipes = {} })
    c.fire("TRADE_SKILL_SHOW")
    local w = window(c)
    if w == nil then return t.ok(false, "no window") end
    t.eq(w.shown, true)
    local at = {}
    for i, part in ipairs(w.parts) do at[part.key or i] = part.text end
    t.ok(type(at.next) == "string" and at.next ~= "", "a reason, not a blank box")
    t.eq(at.listHead, nil, "no heading over an empty list")
end

tests["prof dock module: no kit window: the plain panel says the same"] = function(t)
    if not has(t) then return end
    local c = start({ frames = false })
    c.fire("TRADE_SKILL_SHOW")
    t.eq(window(c), nil)
    local panel
    for _, h in ipairs(c.rowPanels) do
        if h.spec.name == ns.id.framePrefix .. "ProfDock" then panel = h end
    end
    t.ok(panel == nil or #panel.rows > 0, "the plain panel, when there is one, has its lines")
end

tests["prof dock module: the panel has no click that does anything in the game"] = function(t)
    if not has(t) then return end
    local c = start({ bags = { { id = 2, count = 5 } } })
    c.fire("TRADE_SKILL_SHOW")
    for _, key in ipairs({ "next", "row1", "row2" }) do
        t.eq(c.kitClick(D().ID, key), false, key .. " is a line of text, not a button")
    end
end

return tests

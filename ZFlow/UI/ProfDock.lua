local _, ns = ...

-- Profession panel (lead section 387): ONE compact panel that hangs under
-- the game's own profession window, shown when that window opens and hidden
-- when it closes. It says what to do next for a skill point, in plain
-- words, and lists the cheapest of the player's own recipes that still give
-- a point, each with what is missing.
--
-- LOOK ONLY. Nothing here crafts, buys, takes from the bank, trains or
-- clicks anything: every part is a line of text with a picture, and no part
-- carries a click.
--
-- A planner's reader, not a ladder table (section 379): every line comes
-- from Items/ProfPlan.lua (Plan and Candidates) and Items/ProfSources.lua,
-- read from what this character saved. A recipe is listed only when it is
-- in the saved recipe book, which holds learned recipes only, and never
-- when the open window says it is not learned: a recipe the player does not
-- know shows up as "Learn ... from the trainer" in the next step, never as
-- something to make.
--
--   ProfDock.StepText(step, input) -> text, sub        pure
--   ProfDock.Next(steps, why, say, input, list) -> { text, sub, icon, item,
--     count, kind, empty = true when it is a reason, not a step }   pure
--   ProfDock.Rows(input, opts) -> rows                 pure
--     opts.known   { [recipe] = false } for recipes the open window says
--                  are not learned
--     opts.limit   how many rows (ProfDock.ROWS)
--     opts.info(item) -> { name, quality }; opts.icon(recipe, entry) -> icon
--     row = { recipe, name, quality, icon, item, chance, cost, ready,
--             missing = { { item, name, count, bank, from } }, tooltip }
--   ProfDock.View(model) -> a kit window spec          pure
--     model = { prof, skill, max, next, rows, todo, pick, width, height }
--     skill/max (when read) stand at the top as a line and a bar;
--     todo is ProfDock.Todo's rows, under "Still to do".
--   ProfDock.Todo(cardPrompts, learnPrompts, prof) -> rows   pure
--   ProfDock.Dock(rect, screenW, screenH, height) -> point, width | nil
--   ProfDock.Declare(k) -> api
--
-- A free primary profession slot (queue item A3, G17/G18): while the panel
-- is up it also says which profession to learn and why, one line each, in
-- the panel itself; no window of its own. The advice is UI/ProfPick.lua's
-- (Advice, StepOf, Lines), read here and never changed; its setting and its
-- "not now" are honoured. Words only: nothing is trained.
--   ProfDock.Pick(advice, where) -> { { name, text, sub, icon, tooltip } }
--     advice  what ProfPick.Advice gave; where(name) -> a line saying
--             where it is taught, or nil
--
-- Not seen in game: where the panel stands under the profession window, its
-- width against that window, and whether every line fits.

ns.ProfDock = {}
local D = ns.ProfDock

D.NAME = "profDock"
D.SETTING = "prof.dock"
D.ID = "ProfDock"
-- %s here and in the reasons below: the add-on's own name (ns.id.title),
-- then the profession.
D.TITLE = "%s: %s"
D.TITLE_PLAIN = "%s: professions"
D.ROWS = 5
D.WIDTH, D.MIN_WIDTH, D.MAX_WIDTH = 384, 320, 480
-- The window's own title and edges, the "Next step" heading and its
-- card; then the list's heading; then each row of the list.
D.BASE_HEIGHT, D.LIST_HEAD, D.ROW_HEIGHT = 166, 36, 28
D.GAP = 6
-- The game's profession window, classic then modern.
D.FRAMES = { "TradeSkillFrame", "ProfessionsFrame" }
D.DEFAULT_POINT = { "TOPLEFT", "TOPLEFT", 16, -560 }

D.HEAD_NEXT = "Next step"
D.HEAD_LIST = "Cheapest skill points"
D.HEAD_TODO = "Still to do"
-- The skill at the top: a line and the bar under it; the "Still to
-- do" section's heading and its wrapped lines.
D.SKILL_LINE, D.BAR = 28, 18
D.TODO_HEAD, D.TODO_ROW = 36, 40
-- Difficulty in words, on the row itself: orange and yellow are
-- never carried by colour alone.
D.CHANCE_SURE = "Sure skill point"
D.CHANCE_MIGHT = "Might give a skill point"
D.READY = "Ready"
D.NEED = "Need %d %s"
D.MORE = " +%d more"
D.UNNAMED = "of a material"

D.HEAD_PICK = "Free profession slot"
D.PICK_TEXT = "Learn %s"
D.PICK_HEAD, D.PICK_ROW = 36, 40
-- Why, in a few words, for the second line of each profession advised.
D.PICK_WHY = {
    Alchemy = "Potions from the herbs you gather",
    Blacksmithing = "Armour and weapons from ore",
    Enchanting = "Enchants from gear you do not need",
    Engineering = "Gadgets and bombs from ore and stone",
    Herbalism = "Gathers herbs as you level, to use or sell",
    Leatherworking = "Armour from the leather you skin",
    Mining = "Gathers ore as you level, to use or sell",
    Skinning = "Leather from the beasts you kill",
    Tailoring = "Bags and cloth gear from the cloth you loot",
}
D.PICK_ICON = {
    Alchemy = "Interface\\Icons\\Trade_Alchemy",
    Blacksmithing = "Interface\\Icons\\Trade_BlackSmithing",
    Enchanting = "Interface\\Icons\\Trade_Engraving",
    Engineering = "Interface\\Icons\\Trade_Engineering",
    Herbalism = "Interface\\Icons\\Trade_Herbalism",
    Leatherworking = "Interface\\Icons\\Trade_LeatherWorking",
    Mining = "Interface\\Icons\\Trade_Mining",
    Skinning = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
    Tailoring = "Interface\\Icons\\Trade_Tailoring",
}
D.PICK_ICON_ANY = "Interface\\Icons\\INV_Misc_Book_09"

D.SMELT_PROF = "Mining"
D.ICON = {
    learn_recipe = "Interface\\Icons\\INV_Misc_Book_09",
    train_tier = "Interface\\Icons\\INV_Misc_Book_11",
    go_station = "Interface\\Icons\\INV_Misc_Map_01",
}

-- The reason shown when the plan is empty: what is wrong, then the one
-- thing to do about it, filled by fill() below: {addon} is the add-on's
-- name, {prof} the profession, {recipe} the recipe short of materials.
D.WHY = {
    ["no reading"] = { "{addon} has not read your {prof} skill yet.", "Close this window and open it again." },
    ["no colours"] = { "{addon} has not read these recipes yet.", "Close this window and open it again." },
    ["no materials"] = { "You lack the materials for {recipe}.", "The list below says what each recipe needs." },
    ["no recipe"] = { "None of your recipes gives a skill point now.",
        "Open a {prof} trainer once so {addon} can read what you can learn." },
}
D.WHY_NO_PROF = { "{addon} could not tell which profession this is.", "Close this window and open it again." }

D.FROM = {
    bank = "take it from your bank",
    smelt = "smelt it at a forge from the ore in your bags",
    gather = "gather it; a node is marked on this map",
    buy_vendor = "a vendor sells it",
    buy_auction = "buy it at the auction house",
}

local function title()
    local id = ns.id
    return type(id) == "table" and type(id.title) == "string" and id.title or "The add-on"
end

local function fill(line, prof, recipe)
    local slots = { addon = title(), prof = prof or "profession", recipe = recipe or prof or "that recipe" }
    return (line:gsub("{(%a+)}", function(key) return slots[key] end))
end

local function whole(n)
    return type(n) == "number" and n == n and n >= 1 and n < math.huge and n == math.floor(n)
end

local function text(v)
    return type(v) == "string" and v ~= ""
end

local function call(f, ...)
    if type(f) ~= "function" then return nil end
    local ok, a = pcall(f, ...)
    if ok then return a end
    return nil
end

local function count(t, item)
    local n = type(t) == "table" and t[item] or nil
    if type(n) == "number" and n == n and n > 0 and n < math.huge then return math.floor(n) end
    return 0
end

local function sortedKeys(t)
    local keys = {}
    for key in pairs(t) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        if type(a) == type(b) and (type(a) == "number" or type(a) == "string") then return a < b end
        return tostring(a) < tostring(b)
    end)
    return keys
end

local function article(word)
    if word:match("^[AEIOUaeiou]") then return "an " .. word end
    return "a " .. word
end

local function nameOf(input, item)
    local name = call(type(input) == "table" and input.name or nil, item)
    if text(name) then return name end
    return nil
end

local function counted(n, name)
    return string.format("%d %s", n, name or D.UNNAMED)
end

-- The next step in plain words, and the smaller line under it (or nil).
-- The planner's own line (step.text) is used only for a kind this file does
-- not know, so a step added later still reads as something.
function D.StepText(step, input)
    if type(step) ~= "table" then return nil end
    local kind, n = step.kind, whole(step.count) and step.count or nil
    local item = nameOf(input, step.item)
    local forRecipe = text(step.recipe) and ("For " .. step.recipe) or nil
    if kind == "learn_recipe" then
        local what = text(step.recipe) and step.recipe or "a new recipe"
        return "Learn " .. what .. " from the trainer", text(step.npc) and ("Trainer: " .. step.npc) or nil
    elseif kind == "train_tier" then
        local prof = type(input) == "table" and text(input.prof) and (input.prof .. " ") or ""
        return "Train the next " .. prof .. "rank at the trainer",
            text(step.npc) and ("Trainer: " .. step.npc) or "Your skill is at its cap until you do."
    elseif kind == "craft" then
        local smelts = type(input) == "table" and input.prof == D.SMELT_PROF
        local verb = smelts and "Smelt" or "Make"
        local sub = text(step.station) and ("At " .. article(step.station)) or nil
        if item and n then return verb .. " " .. counted(n, item), sub end
        local recipe = text(step.recipe) and step.recipe or "your recipe"
        local lead = recipe:sub(1, #verb + 1) == verb .. " " and recipe or (verb .. " " .. recipe)
        if n == nil then return lead, sub end
        if n == 1 then return lead .. " once", sub end
        return string.format("%s %d times", lead, n), sub
    elseif kind == "make_part" then
        local at = text(step.station) and (" at " .. article(step.station)) or ""
        return "Smelt " .. counted(n or 1, item) .. at, forRecipe
    elseif kind == "take_bank" then
        return "Take " .. counted(n or 1, item) .. " from the bank", forRecipe
    elseif kind == "gather" then
        return "Gather " .. counted(n or 1, item), forRecipe
    elseif kind == "buy_vendor" then
        local who = text(step.npc) and step.npc or "a trade goods vendor"
        return "Buy " .. counted(n or 1, item) .. " from " .. who, forRecipe
    elseif kind == "buy_auction" then
        return "Buy " .. counted(n or 1, item) .. " at the auction house", forRecipe
    elseif kind == "go_station" then
        return "Go to " .. article(text(step.station) and step.station or "crafting station"), forRecipe
    end
    if text(step.text) then return step.text, forRecipe end
    return "Follow the next step in your plan", forRecipe
end

-- The "Next step" box: the plan's first step, or the reason there is none.
-- Never nil and never without text.
function D.Next(steps, why, _, input, list)
    local step = type(steps) == "table" and steps[1] or nil
    if type(step) == "table" then
        local line, sub = D.StepText(step, input)
        return { text = line, sub = sub, kind = step.kind, item = step.item,
            count = whole(step.count) and step.count or nil, recipe = step.recipe, icon = D.ICON[step.kind] }
    end
    local prof = type(input) == "table" and text(input.prof) and input.prof or nil
    if not prof then
        return { text = fill(D.WHY_NO_PROF[1]), sub = fill(D.WHY_NO_PROF[2]), empty = true, why = why }
    end
    local pair = D.WHY[why] or D.WHY["no reading"]
    local recipe
    if why == "no materials" and type(list) == "table" and type(list[1]) == "table" and text(list[1].recipe) then
        recipe = list[1].recipe
    end
    return { text = fill(pair[1], prof, recipe), sub = fill(pair[2], prof, recipe), empty = true,
        why = D.WHY[why] and why or "no reading" }
end

-- A known Mining smelt that makes this item from one ore the bags hold
-- enough of for one.
local function smelts(input, item)
    if type(input.book) ~= "table" then return false end
    for _, r in pairs(input.book) do
        if type(r) == "table" and r.profession == D.SMELT_PROF and r.makes == item and r.partial ~= true
            and type(r.mats) == "table" then
            local ore, per, n = nil, nil, 0
            for k, v in pairs(r.mats) do ore, per, n = k, v, n + 1 end
            if n == 1 and whole(per) and count(input.bags, ore) >= per then return true end
        end
    end
    return false
end

-- Where a short material comes from, as one of the D.FROM keys: the bank,
-- a smelt, then what ProfSources says (a node, a vendor, the auction house).
local function from(input, item, short)
    if count(input.bank, item) > 0 then return "bank" end
    if smelts(input, item) then return "smelt" end
    local S = ns.ProfSources
    local step = type(S) == "table" and call(S.For, input, item, short) or nil
    if type(step) == "table" and D.FROM[step.kind] then return step.kind end
    return "buy_auction"
end

local function costText(cost)
    local P = ns.Prices
    if type(P) ~= "table" or type(cost) ~= "number" then return nil end
    local said = call(P.Text, { value = math.floor(cost + 0.5), basis = P.ESTIMATED }, "auction")
    if text(said) then return said end
    return nil
end

-- Why this row is where it is and what it lacks, for the hover.
function D.Reason(row, rank)
    local lines = {}
    if row.chance == "sure" then
        lines[#lines + 1] = "Sure skill point: this recipe is orange."
    else
        lines[#lines + 1] = "Might give a skill point: this recipe is yellow."
    end
    local cost = costText(row.cost)
    if cost then
        lines[#lines + 1] = "Materials for one: " .. cost .. "."
        if rank == 1 then lines[#lines + 1] = "The cheapest of your recipes that still give a point." end
    else
        lines[#lines + 1] = "No price seen for its materials yet, so it comes after the priced ones."
    end
    if row.ready then
        lines[#lines + 1] = "You have everything to make one."
    else
        for _, m in ipairs(row.missing) do
            local where = D.FROM[m.from] or D.FROM.buy_auction
            if m.from == "bank" then where = string.format("%s (%d there)", where, m.bank) end
            lines[#lines + 1] = "Missing " .. counted(m.count, m.name) .. ": " .. where .. "."
        end
    end
    return table.concat(lines, "\n")
end

-- The cheapest recipes that still give a point, in the planner's order
-- (sure first, then cheapest, unpriced last, then by name), each with what
-- one craft lacks from the bags.
function D.Rows(input, opts)
    local out = {}
    local P = ns.ProfPlan
    if type(input) ~= "table" or type(P) ~= "table" then return out end
    if type(opts) ~= "table" then opts = {} end
    local known = type(opts.known) == "table" and opts.known or {}
    local limit = whole(opts.limit) and opts.limit or D.ROWS
    local list = call(P.Candidates, input)
    if type(list) ~= "table" then return out end
    for _, c in ipairs(list) do
        if #out >= limit then break end
        local entry = type(c) == "table" and c.entry or nil
        -- "Learn the recipe first": never a recipe the window says is not
        -- learned, whatever an older save still holds.
        if type(entry) == "table" and type(entry.mats) == "table" and text(c.recipe) and known[c.recipe] ~= false then
            local info = call(opts.info, entry.makes)
            local row = { recipe = c.recipe, item = entry.makes, chance = c.chance, cost = c.cost, missing = {},
                name = type(info) == "table" and text(info.name) and info.name or c.recipe,
                quality = type(info) == "table" and info.quality or nil,
                icon = call(opts.icon, c.recipe, entry) }
            for _, item in ipairs(sortedKeys(entry.mats)) do
                local per = entry.mats[item]
                local short = (whole(per) and per or 0) - count(input.bags, item)
                if short > 0 then
                    row.missing[#row.missing + 1] = { item = item, name = nameOf(input, item), count = short,
                        bank = count(input.bank, item), from = from(input, item, short) }
                end
            end
            row.ready = #row.missing == 0
            row.tooltip = D.Reason(row, #out + 1)
            out[#out + 1] = row
        end
    end
    return out
end

-- The item's name in the game's colour for its rarity; plain when the
-- rarity is not read.
local function coloured(name, quality)
    local Kit = ns.Kit
    local q = type(Kit) == "table" and call(Kit.Quality, quality) or nil
    if type(q) ~= "table" or q.known ~= true or not text(q.hex) then return name end
    return "|cff" .. q.hex .. name .. "|r"
end

local function need(row)
    local first = row.missing[1]
    local said = string.format(D.NEED, first.count, first.name or D.UNNAMED)
    if #row.missing > 1 then said = said .. string.format(D.MORE, #row.missing - 1) end
    return said
end

-- The lines for a free profession slot: one per profession advised, with
-- why in a few words; the whole advice and where it is taught on hover.
function D.Pick(advice, where)
    local out = {}
    if type(advice) ~= "table" or type(advice.wants) ~= "table" then return out end
    for _, name in ipairs(advice.wants) do
        if text(name) then
            local tip = text(advice.text) and advice.text or nil
            local at = type(where) == "function" and call(where, name) or nil
            if text(at) then tip = tip and (tip .. "\n" .. at) or at end
            out[#out + 1] = { name = name, text = string.format(D.PICK_TEXT, name),
                sub = D.PICK_WHY[name] or (text(at) and at) or nil,
                icon = D.PICK_ICON[name] or D.PICK_ICON_ANY, tooltip = tip }
        end
    end
    return out
end

-- "Still to do" (all-windows row 3): what ProfCard and ProfLearn
-- already work out, gathered into the panel. cardPrompts: ProfCard's
-- prompts ({ id, text }); only this profession's own is the panel's
-- business. learnPrompts: ProfLearn's ({ id, text }) — a recipe in
-- the bags is the character's, whichever profession it belongs to.
function D.Todo(cardPrompts, learnPrompts, prof)
    local out = {}
    if type(cardPrompts) == "table" and text(prof) then
        local PC = ns.ProfCard
        local prefix = "aps.prof."
        if type(PC) == "table" and text(PC.PREFIX) then prefix = PC.PREFIX end
        for _, p in ipairs(cardPrompts) do
            if type(p) == "table" and p.id == prefix .. prof and text(p.text) then
                out[#out + 1] = { text = p.text, icon = D.ICON.train_tier }
            end
        end
    end
    if type(learnPrompts) == "table" then
        for _, p in ipairs(learnPrompts) do
            if type(p) == "table" and text(p.text) then
                out[#out + 1] = { text = p.text, icon = D.ICON.learn_recipe }
            end
        end
    end
    return out
end

function D.Height(rows, pick, more)
    local n = type(rows) == "table" and #rows or 0
    local p = type(pick) == "table" and #pick or 0
    local h = D.BASE_HEIGHT
    if type(more) == "table" and more.bar then h = h + D.SKILL_LINE + D.BAR end
    if n > 0 then h = h + D.LIST_HEAD + n * D.ROW_HEIGHT end
    local todo = 0
    if type(more) == "table" and whole(more.todo) then todo = more.todo end
    if todo > 0 then h = h + D.TODO_HEAD + todo * D.TODO_ROW end
    if p > 0 then h = h + D.PICK_HEAD + p * D.PICK_ROW end
    return h
end

-- A cheapest row's smaller line: its difficulty in words (never
-- colour alone), and its cost in coins when a price is known.
local function rowSub(row)
    local said
    if row.chance == "sure" then said = D.CHANCE_SURE else said = D.CHANCE_MIGHT end
    local cost = costText(row.cost)
    if cost then said = said .. " · " .. cost end
    return said
end

function D.View(model)
    if type(model) ~= "table" then model = {} end
    local nextStep = type(model.next) == "table" and model.next or D.Next(nil, nil, nil, nil)
    local rows = type(model.rows) == "table" and model.rows or {}
    local children = {}
    -- The profession and its skill at the top, as a bar that fills —
    -- only when the skill was read; the next step's reason covers the
    -- panel when it was not.
    local hasSkill = whole(model.skill) and whole(model.max) and model.max > 0
    if hasSkill and text(model.prof) then
        local words = string.format("%d / %d", model.skill, model.max)
        local icon = D.PICK_ICON[model.prof]
        if icon == nil then icon = D.PICK_ICON_ANY end
        children[#children + 1] = { kind = "line", key = "skill", text = model.prof, icon = icon, right = words }
        children[#children + 1] = { kind = "bar", key = "skillBar", text = words,
            value = model.skill, max = model.max }
    end
    children[#children + 1] = { kind = "section", key = "nextHead", text = D.HEAD_NEXT }
    children[#children + 1] = { kind = "card", key = "next", text = nextStep.text, sub = nextStep.sub,
        icon = nextStep.icon, wrap = true }
    if #rows > 0 then
        children[#children + 1] = { kind = "section", key = "listHead", text = D.HEAD_LIST }
        for i, row in ipairs(rows) do
            local right, tone = D.READY, "good"
            if not row.ready then right, tone = need(row), "warn" end
            children[#children + 1] = { kind = "line", key = "row" .. i, text = coloured(row.name, row.quality),
                icon = row.icon, sub = rowSub(row), right = right, tone = tone, tooltip = row.tooltip }
        end
    end
    local todo = {}
    if type(model.todo) == "table" then todo = model.todo end
    if #todo > 0 then
        children[#children + 1] = { kind = "section", key = "todoHead", text = D.HEAD_TODO }
        for i, row in ipairs(todo) do
            children[#children + 1] = { kind = "line", key = "todo" .. i, text = row.text, icon = row.icon,
                wrap = true }
        end
    end
    local pick = {}
    if type(model.pick) == "table" then pick = model.pick end
    if #pick > 0 then
        children[#children + 1] = { kind = "section", key = "pickHead", text = D.HEAD_PICK }
        for i, row in ipairs(pick) do
            children[#children + 1] = { kind = "line", key = "pick" .. i, text = row.text, sub = row.sub,
                icon = row.icon, tooltip = row.tooltip }
        end
    end
    local more = { bar = hasSkill == true, todo = #todo }
    return {
        id = D.ID,
        title = text(model.prof) and string.format(D.TITLE, title(), model.prof)
            or string.format(D.TITLE_PLAIN, title()),
        width = model.width or D.WIDTH, height = model.height or D.Height(rows, pick, more),
        point = D.DEFAULT_POINT, escape = false,
        children = children,
    }
end

-- The same, for the plain panel: lines of text.
function D.Plain(model)
    local out = {}
    local nextStep = type(model) == "table" and type(model.next) == "table" and model.next or D.Next(nil, nil, nil, nil)
    if type(model) == "table" and whole(model.skill) and whole(model.max) and text(model.prof) then
        out[#out + 1] = { kind = "info", text = string.format("%s: %d / %d", model.prof, model.skill, model.max) }
    end
    out[#out + 1] = { kind = "info", text = D.HEAD_NEXT .. ": " .. nextStep.text }
    if text(nextStep.sub) then out[#out + 1] = { kind = "info", text = nextStep.sub } end
    for _, row in ipairs(type(model) == "table" and type(model.rows) == "table" and model.rows or {}) do
        out[#out + 1] = { kind = "info", text = row.name .. ": " .. (row.ready and D.READY or need(row)) }
    end
    local todoRows = {}
    if type(model) == "table" and type(model.todo) == "table" then todoRows = model.todo end
    for _, row in ipairs(todoRows) do
        out[#out + 1] = { kind = "info", text = D.HEAD_TODO .. ": " .. row.text }
    end
    for _, row in ipairs(type(model) == "table" and type(model.pick) == "table" and model.pick or {}) do
        out[#out + 1] = { kind = "info", text = D.HEAD_PICK .. ": " .. row.text
            .. (text(row.sub) and (". " .. row.sub) or "") }
    end
    return out
end

local function amount(v)
    return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- Where the panel stands against the profession window's rectangle: under
-- it, left edges in line and as wide as it (within D.MIN_WIDTH and
-- D.MAX_WIDTH); beside it, tops in line, when there is no room under it.
-- nil when the rectangle or the screen is not read, or neither fits: the
-- panel then keeps its own place. point = { anchor, screen anchor, x, y }.
function D.Dock(rect, screenW, screenH, height)
    if type(rect) ~= "table" or not (amount(rect.l) and amount(rect.r) and amount(rect.b) and amount(rect.t)) then
        return nil
    end
    if not (amount(screenW) and amount(screenH) and amount(height)) or rect.r <= rect.l or rect.t <= rect.b then
        return nil
    end
    local width = math.max(D.MIN_WIDTH, math.min(D.MAX_WIDTH, math.floor(rect.r - rect.l + 0.5)))
    if width > screenW then return nil end
    local top = rect.b - D.GAP
    if top - height >= 0 then
        local x = math.max(0, math.min(rect.l, screenW - width))
        return { "TOPLEFT", "BOTTOMLEFT", x, top }, width, "under"
    end
    local x = rect.r + D.GAP
    if x + width <= screenW and height <= screenH then
        local y = math.max(height, math.min(rect.t, screenH))
        return { "TOPLEFT", "BOTTOMLEFT", x, y }, width, "beside"
    end
    return nil
end

function D.Declare(k)
    local api = {}
    local host, model
    function api.shown() return host ~= nil and host.shown() == true end
    function api.model() return model end

    k:Module({
        name = D.NAME,
        needs = { "client", "store", "bus", "settings" },
        settings = { {
            key = D.SETTING, scope = "account", type = "bool", default = true,
            label = "Next-step panel under the profession window",
            help = "When you open a profession window, a small panel under it says what to do next for a skill "
                .. "point and lists your cheapest recipes that still give one, with what each is missing. It only "
                .. "shows information: nothing is crafted, bought or trained for you.",
            group = "professions",
            synonyms = { "profession", "professions", "recipes", "skill", "next step", "level", "trainer", "craft" },
        } },
        provides = { Shown = api.shown },
        start = function(ctx)
            local client = ctx.client

            local function ask(name, ...)
                local f = client[name]
                if type(f) ~= "function" then return nil end
                local ok, a, b = pcall(f, ...)
                if ok then return a, b end
                return nil
            end

            -- The open window: its profession, live skill, which recipes
            -- it says are not learned, and each recipe's own picture.
            local function window()
                local r = ask("recipes")
                local known, icons = {}, {}
                if type(r) == "table" and type(r.recipes) == "table" then
                    for _, row in ipairs(r.recipes) do
                        if type(row) == "table" and text(row.name) then
                            if row.learned == false then known[row.name] = false end
                            if row.icon ~= nil then icons[row.name] = row.icon end
                        end
                    end
                else
                    r = ask("tradeSkillRows")
                end
                if type(r) ~= "table" then return nil, nil, nil, known, icons end
                return text(r.name) and r.name or nil, r.skill, r.max, known, icons
            end

            local function slot(height)
                local w, h = ask("screen")
                for _, name in ipairs(D.FRAMES) do
                    local rect = ask("frameRect", name)
                    if type(rect) == "table" then
                        local point, width = D.Dock(rect, w, h, height)
                        if point then return point, width end
                    end
                end
                return nil
            end

            local function picture(icon)
                if type(icon) == "string" and icon ~= "" then return icon end
                if type(icon) == "number" and icon == icon and icon > 0 then return icon end
                return nil
            end

            -- A saved table read that never raises.
            local function saved(scope, path)
                if type(path) ~= "string" then return nil end
                local ok, v = pcall(ctx.store.get, ctx.store, scope, path)
                if ok and type(v) == "table" then return v end
                return nil
            end

            -- A free primary slot: the picker's own advice, with its
            -- setting and its saved "not now" honoured.
            local function pickRows(here)
                local PP = ns.ProfPick
                if type(PP) ~= "table" or type(PP.Advice) ~= "function" then return {} end
                if ctx.settings:get(PP.SETTING) == false then return {} end
                local advice = call(PP.Advice, ask("professions"), ask("class"), ask("level"),
                    saved("char", PP.STATE))
                local npcs, faction = saved("account", PP.NPCS), ask("faction")
                return D.Pick(advice, function(name)
                    if type(PP.StepOf) ~= "function" or type(PP.Lines) ~= "function" then return nil end
                    local lines = PP.Lines(PP.StepOf(name, here, npcs, faction))
                    return type(lines) == "table" and lines[1] or nil
                end)
            end

            -- "Still to do": ProfCard's prompts for this profession
            -- (at its cap, or the next rank it can learn) and
            -- ProfLearn's bag recipes, from the same saved reads
            -- those modules use themselves.
            local function todoRows(prof)
                local card
                local PC = ns.ProfCard
                local Seen = ns.ProfSeen
                if type(PC) == "table" and type(PC.Prompts) == "function" and type(Seen) == "table" then
                    card = call(PC.Prompts, saved("char", Seen.READINGS), saved("account", Seen.NPCS),
                        ask("faction"), saved("char", PC.LISTS), ask("level"))
                end
                local learn
                local PL = ns.ProfLearn
                local Book = ns.RecipeBook
                if type(PL) == "table" and type(PL.Prompts) == "function" and type(Book) == "table" then
                    local function nameOf(id)
                        local info = ask("itemInfo", id)
                        if type(info) == "table" then return info.name end
                        return nil
                    end
                    learn = call(PL.Prompts, ask("bagItems"), nameOf, saved("char", Book.PATH))
                end
                return D.Todo(card, learn, prof)
            end

            local function build()
                local P = ns.ProfPlan
                local prof, skill, max, known, icons = window()
                local input, steps, why, say, list
                if prof and type(P) == "table" then
                    local source
                    if type(ctx.use) == "function" then
                        local ok, s = pcall(ctx.use, P.NODE_SOURCE)
                        if ok then source = s end
                    end
                    input = call(P.Input, client, ctx.store, prof, source)
                    if type(input) == "table" then
                        -- The window's own reading is the newest there is.
                        if whole(skill) and whole(max) then input.skill, input.max = skill, max end
                        local ok, a, b, c = pcall(P.Plan, input)
                        if ok then steps, why, say = a, b, c end
                        list = call(P.Candidates, input)
                    end
                end
                if type(input) ~= "table" then input = { prof = prof } end
                local rows = D.Rows(input, {
                    known = known,
                    info = function(item) return ask("itemInfo", item) end,
                    icon = function(recipe, entry)
                        return picture(icons[recipe]) or picture(ask("itemTexture", entry.makes))
                    end,
                })
                local nextStep = D.Next(steps, why, say, input, list)
                if not nextStep.empty then
                    local icon
                    if nextStep.kind == "craft" then icon = picture(icons[nextStep.recipe]) end
                    if icon == nil and nextStep.item ~= nil then icon = picture(ask("itemTexture", nextStep.item)) end
                    nextStep.icon = icon or nextStep.icon
                end
                local pick = pickRows(input.here)
                local todo = todoRows(prof)
                local hasSkill = false
                if whole(skill) and whole(max) then hasSkill = true end
                local height = D.Height(rows, pick, { bar = hasSkill, todo = #todo })
                local point, width = slot(height)
                return { prof = prof, skill = skill, max = max, next = nextStep, rows = rows, pick = pick,
                    todo = todo, height = height, width = width or D.WIDTH, point = point }
            end

            local function draw()
                model = build()
                host.draw(D.View(model), D.Plain(model), function() end)
                -- Each open: the profession window may have moved, and the
                -- list may be longer or shorter than last time.
                host.place(model.point, model.width, model.height)
            end

            local function hide()
                model = nil
                host.show(false)
            end

            ctx.bus:on(D.NAME, "TRADE_SKILL_SHOW", function()
                if ctx.settings:get(D.SETTING) == false then
                    hide()
                    return
                end
                draw()
                host.show(true)
            end)
            ctx.bus:on(D.NAME, "TRADE_SKILL_LIST_UPDATE", function()
                if model == nil or not host.shown() then return end
                draw()
            end)
            ctx.bus:on(D.NAME, "TRADE_SKILL_CLOSE", hide)

            local id = k.id or ns.id
            local panel
            if type(client.rowPanel) == "function" then
                panel = client.rowPanel({ name = id.framePrefix .. "ProfDock", width = D.WIDTH, height = 80 })
            end
            if panel then
                panel.show(false)
                panel.place(D.DEFAULT_POINT)
            end
            host = ns.KitHost.New(k, client, { name = id.framePrefix .. "ProfDockKit", panel = panel,
                place = function() return model and model.point or nil end })
        end,
        stop = function()
            model = nil
            if host then host.show(false) end
        end,
    })
    return api
end

ns.profDock = D.Declare(ns)

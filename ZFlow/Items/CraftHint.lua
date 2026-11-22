local _, ns = ...

-- CraftHint: for a profession window, what to make, what it takes, and how
-- many can be made right now.
--
--   hint = CraftHint.Build(goal, context)
--
-- goal and context are ItemPlan's (context may also carry `names` for the
-- presenter). The hint builds one plan from the one snapshot and words it
-- with ItemPresent. Pure: no frame, no click, nothing read from the game.
--
-- The old craft hint counted the player's things twice: once through the
-- skill planner's stock, and once more by asking the bags directly for the
-- "make now" figure. The second count is gone. "Make now" is read off the
-- plan: what the plan took from the bags for the goal's own materials. So it
-- always agrees with the rows, it honours what other claims hold (the plan
-- already left those out), and with the bags unread it is "unknown", not 0.
--
-- hint = {
--   ok       false with one line when the goal can't be planned
--   plan     the ItemPlan result
--   view     the ItemPresent view
--   title    "Make 4 x Kit"
--   makeNow  how many crafts of the goal the bags cover now, or "unknown"
--   button   { recipe, count, text = "Make 2" } when makeNow is 1 or more.
--            Data only: whoever draws the button also owns the click.
--   lines    the title, the view's lines, then the make-now line
-- }
--
-- Not carried over from the old file: the "cheapest recipes for a skill
-- point" and "what your bags make for skill" rows. They rank by skill-up
-- chances and auction prices that belong to the skill planner, which is not
-- on this branch, and the chances have no recorded source.

local Hint = {}
ns.CraftHint = Hint

local function isCount(n)
    return type(n) == "number" and n == n and n >= 0 and n < math.huge
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta < tb end
        if ta == "number" or ta == "string" then return a < b end
        return tostring(a) < tostring(b)
    end)
    return keys
end

-- How many crafts of `recipe` the plan's bag takings cover right now.
--   plan    an ItemPlan result whose goal is this recipe
--   recipe  { makes, mats = { [itemKey] = n per craft } }
-- -> a whole number from 0 to the crafts planned, or "unknown" (bags unread,
--    or the plan and recipe can't be read together).
-- A material that an inner craft needs too shares one plan row. What the
-- inner crafts need is taken off first, so the figure can be low but never
-- high.
function Hint.MakeNow(plan, recipe)
    if type(plan) ~= "table" or not plan.ok or plan.unknown == "bags" then return "unknown" end
    if type(recipe) ~= "table" or type(recipe.mats) ~= "table" or next(recipe.mats) == nil then return "unknown" end
    local times
    for _, c in ipairs(type(plan.crafts) == "table" and plan.crafts or {}) do
        if c.makes == recipe.makes then times = c.times end
    end
    if not isCount(times) then return "unknown" end
    local rowOf = {}
    for _, r in ipairs(plan.rows) do rowOf[r.key] = r end
    local now = times
    for key, per in pairs(recipe.mats) do
        local r = rowOf[key]
        if not isCount(per) or per <= 0 or not r or type(r.have) ~= "table" then return "unknown" end
        local elsewhere = math.max(0, r.need - per * times)
        local mine = math.max(0, r.have.bags - elsewhere)
        now = math.min(now, math.floor(mine / per))
    end
    return math.max(0, now)
end

function Hint.Build(goal, context)
    context = type(context) == "table" and context or {}
    local Plan, Present = ns.ItemPlan, ns.ItemPresent
    local hint = { ok = false, makeNow = "unknown", lines = {} }
    if not (Plan and Present) then
        hint.lines[1] = "Can't plan this: the item planner is not loaded"
        return hint
    end
    local plan = Plan.Build(goal, context)
    local view = Present.View(plan, { names = context.names })
    hint.plan, hint.view = plan, view
    if not plan.ok then
        hint.lines = view.lines
        return hint
    end
    hint.ok = true
    local recipe = context.recipes[goal.recipe]
    hint.title = "Make " .. tostring(goal.count) .. " x " .. Present.Name(recipe.makes, context.names)
    hint.makeNow = Hint.MakeNow(plan, recipe)
    hint.lines[1] = hint.title
    for _, line in ipairs(view.lines) do hint.lines[#hint.lines + 1] = line end
    if hint.makeNow == "unknown" then
        hint.lines[#hint.lines + 1] = "Can't tell how many you can make now"
    elseif hint.makeNow > 0 then
        hint.button = { recipe = goal.recipe, count = hint.makeNow, text = "Make " .. hint.makeNow }
        hint.lines[#hint.lines + 1] = "You can make " .. hint.makeNow .. " now"
    else
        hint.lines[#hint.lines + 1] = "You can't make any yet"
    end
    return hint
end

-- The upgrades list: what each one still needs.
--   list = { { recipe = "Boots", link = optional, tag = "+3", missing = { "2 Stone" }, unread = true } }
function Hint.UpgradeLines(list)
    local out = {}
    for _, u in ipairs(type(list) == "table" and list or {}) do
        local what
        if u.unread then
            what = "open this window again so all its materials can be read"
        elseif type(u.missing) == "table" and #u.missing > 0 then
            what = "needs " .. table.concat(u.missing, ", ")
        else
            what = "nothing missing"
        end
        local name = tostring(u.link or u.recipe)
        if type(u.tag) == "string" and u.tag ~= "" then name = name .. " (" .. u.tag .. ")" end
        out[#out + 1] = name .. ": " .. what
    end
    return out
end

-- What one upgrade takes, for its hover text: { { key, text, enough } }, one
-- per material, read from the snapshot.
--   enough  true, false, or "unknown" (bags unread, or short in the bags
--           while the bank was never seen)
function Hint.UpgradeMats(u, snapshot, names)
    local out = {}
    local mats = type(u) == "table" and type(u.mats) == "table" and u.mats or {}
    snapshot = type(snapshot) == "table" and snapshot or {}
    local Present = ns.ItemPresent
    local bags = type(snapshot.bags) == "table" and snapshot.bags or nil
    local bank = (snapshot.bankKnown and type(snapshot.bank) == "table") and snapshot.bank or nil
    for _, key in ipairs(sortedKeys(mats)) do
        local need = mats[key]
        local name = Present and Present.Name(key, names) or ("item " .. tostring(key))
        local head = tostring(need) .. " x " .. name .. ": "
        local row = { key = key }
        if not bags then
            row.text, row.enough = head .. "bags not read yet", "unknown"
        else
            local inBags = isCount(bags[key]) and bags[key] or 0
            row.text = head .. "you have " .. inBags
            if bank then
                local inBank = isCount(bank[key]) and bank[key] or 0
                if inBank > 0 then row.text = row.text .. " (+" .. inBank .. " in the bank)" end
                row.enough = isCount(need) and inBags + inBank >= need
            elseif isCount(need) and inBags >= need then
                row.enough = true
            else
                row.text, row.enough = row.text .. " (bank not seen yet)", "unknown"
            end
        end
        out[#out + 1] = row
    end
    return out
end

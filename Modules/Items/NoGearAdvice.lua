-- Local Flow tweaks, kept together in ONE file that Flow.toc already lists, so
-- /reload picks up edits (WoW only reads new files from the toc at game start).
--
-- 1. Flow stops nagging about two things, unless you turn them back on:
--   * "Equip <item> from your bags" (Flow Improvements list) and the easy-button
--     step "Equip <item> (upgrade +n)"
--   * "Put <spell> on your action bars" (Flow Improvements list)
-- Kept as they were: the gear marks on bag items, tooltip verdicts, quest-reward
-- arrows, and the new-spell card. They only show something when you look.
--   /flow gearadvice on|off     (off by default)
--   /flow baradvice on|off      (off by default)
--
-- 2. Near-first route (further down): /flow nearfirst on|off (on by default)

local _, ns = ...

local function on(key) return ns.db and ns.db[key] == true end

-- Silences a registered advisor's check() unless the setting is on.
local function quiet(advisorKey, setting)
    local advisor = ns:Get("advisor", advisorKey)
    if not (advisor and advisor.check) then return end
    local original = advisor.check
    advisor.check = function()
        if not on(setting) then return {} end
        return original()
    end
end

quiet("gear", "gearAdvice")
quiet("bars", "barAdvice")

local action = ns:Get("action", "gear:upgrade")
if action and action.get then
    local original = action.get
    action.get = function(ctx)
        if not on("gearAdvice") then return nil end
        return original(ctx)
    end
end

local function toggle(setting, what)
    return function(arg)
        arg = (arg or ""):lower()
        if arg == "on" or arg == "off" then ns.db[setting] = (arg == "on") end
        ns:Print(what .. ": " .. (on(setting) and "on" or "off"))
    end
end

ns.commands.gearadvice = toggle("gearAdvice", "equip suggestions (improvements list and easy button), /flow gearadvice on|off")
ns.commands.baradvice = toggle("barAdvice", "put-it-on-your-bars suggestions (improvements list), /flow baradvice on|off")

ns:Register("test", "advice: equip and action-bar nags are quiet unless switched on", function(t)
    local g, b = ns.db.gearAdvice, ns.db.barAdvice
    ns.db.gearAdvice, ns.db.barAdvice = false, false
    t:eq(ns:Get("action", "gear:upgrade").get({}), nil, "no equip step on the easy button")
    t:eq(#ns:Get("advisor", "gear").check(), 0, "no equip line in the improvements list")
    t:eq(#ns:Get("advisor", "bars").check(), 0, "no 'put it on your bars' line")
    ns.db.gearAdvice, ns.db.barAdvice = g, b
end)

-------------------------------------------------------------------------------
-- Near-first route: the arrow prefers what is close to you.
--
-- The planner (Planner.lua) minimises the whole trip's walking, so a stop 1500
-- yards away can still come early if it fits a good loop, and an item-drop
-- objective ("collect 8 X") is treated like any kill. This wraps the planner
-- (without editing it) and, for each plan only, makes stops heavier the further
-- they are from YOU right now:
--   * up to 300 yd away: unchanged
--   * beyond that: +1x per 700 yd more, at most 3x
--   * item-drop stops ("Collect ...") not within 150 yd: another 1.5x. They are
--     still planned (their quest can't be turned in without them), just after
--     the nearby kills.
--   * class training (milestone) is left alone.
-- The planner re-plans as you move, so "near" always means near you.
-------------------------------------------------------------------------------
;(function()
    local P = ns.planner
    -- Upstream Flow has its own copy (Modules/Nav/NearFirst.lua): use that one.
    if not (P and P.Plan) or ns.nearFirst then return end

    local NEAR, SPAN, MAX_MUL = 300, 700, 3
    local DROP_MUL, DROP_NEAR = 1.5, 150

    local F = {}
    ns.nearFirst = F

    local function nearOn() return not (ns.db and ns.db.nearFirst == false) end

    -- How many times heavier a stop `d` yards away (nil: unknown) counts.
    function F.Multiplier(goal, d)
        if goal.milestone then return 1 end
        local m = 1
        if d and d > NEAR then m = math.min(MAX_MUL, 1 + (d - NEAR) / SPAN) end
        if goal.kind == "collect" and not (d and d <= DROP_NEAR) then m = m * DROP_MUL end
        return m
    end

    local function nearestYards(p, goal)
        local best
        for _, pt in ipairs(goal.points or {}) do
            if pt.wx and pt.cont == p.cont then
                local dx, dy = pt.wx - p.wx, pt.wy - p.wy
                local d = math.sqrt(dx * dx + dy * dy)
                if not best or d < best then best = d end
            end
        end
        return best
    end

    -- A /reload runs this file again: wrap the planner's own Plan, never our
    -- previous wrapper, or the weights would be applied twice.
    local original = P._flowOriginalPlan or P.Plan
    P._flowOriginalPlan = original
    function P.Plan(self, p, goals, opts)
        if not (nearOn() and p and p.wx and p.wy and goals) then return original(self, p, goals, opts) end
        local saved = {}
        for _, g in ipairs(goals) do
            local m = F.Multiplier(g, nearestYards(p, g))
            if m ~= 1 then
                saved[g] = g.weight or false
                g.weight = (g.weight or 1) * m
            end
        end
        local ok, result = pcall(original, self, p, goals, opts)
        for g, w in pairs(saved) do g.weight = w or nil end   -- the goals keep their own weights
        if not ok then error(result, 0) end
        return result
    end

    ns.commands.nearfirst = function(arg)
        arg = (arg or ""):lower()
        if arg == "on" or arg == "off" then ns.db.nearFirst = (arg == "on") end
        ns:Print("route prefers stops near you: " .. (nearOn() and "on" or "off") .. " (/flow nearfirst on|off)")
        if arg == "on" or arg == "off" then
            if ns.nav and ns.nav.Collect then pcall(ns.nav.Collect, ns.nav) end
        end
    end

    ns:Register("test", "nearfirst: far stops and item drops wait; weights come back", function(t)
        local saved = ns.db.nearFirst
        ns.db.nearFirst = true
        t:eq(F.Multiplier({}, 100), 1, "close: unchanged")
        t:near(F.Multiplier({}, 1000), 2, 0.001, "1,000 yd: 2x")
        t:eq(F.Multiplier({}, 9000), 3, "capped at 3x")
        t:eq(F.Multiplier({ milestone = true }, 9000), 1, "class training left alone")
        t:eq(F.Multiplier({ kind = "collect" }, 100), 1, "an item drop right here is fine")
        t:near(F.Multiplier({ kind = "collect" }, 200), 1.5, 0.001, "a drop further off waits")

        local p = { cont = 0, wx = 0, wy = 0 }
        local function goal(key, x, y, extra)
            local g = { key = key, text = key, points = { { cont = 0, wx = x, wy = y } } }
            for k, v in pairs(extra or {}) do g[k] = v end
            return g
        end
        -- Both straight ahead, the drop a hair nearer: unweighted the drop comes
        -- first (300 + 10 yd vs 310 + 10); with near-first it is heavier, so the
        -- kill comes first.
        local drop = goal("1:1", 300, 0, { kind = "collect" })
        local kill = goal("2:1", 310, 0, { kind = "kill", weight = 1 })
        local plan = ns.planner:Plan(p, { drop, kill }, {})
        t:eq(plan and plan[1].goal.key, "2:1", "a kill right behind an item drop comes first")
        t:eq(drop.weight, nil, "the drop's own weight is back")
        t:eq(kill.weight, 1, "the kill's own weight is back")

        ns.db.nearFirst = false
        plan = ns.planner:Plan(p, { drop, kill }, {})
        t:eq(plan and plan[1].goal.key, "1:1", "off: the nearer drop comes first")
        ns.db.nearFirst = saved
    end)
end)()

-------------------------------------------------------------------------------
-- Weapon stone on one press. Flow's own "buff:item" step (BuffItems.lua) only
-- offers a stone at a kill/loot stop or just after a fight, and only for items
-- the game files as "Item Enhancement", which a rough sharpening stone may not
-- be on this client. This step goes by the item's NAME and shows whenever your
-- main hand has no stone/oil on it, you're out of combat and not resting (inns
-- and cities): one press of the Flow key puts it on.
--   /flow stone on|off     (on by default; /flow stone alone says what it sees)
-------------------------------------------------------------------------------
;(function()
    local BI = ns.buffItems
    -- Upstream BuffItems.lua finds weapon buffs by name itself: use that one.
    if not (BI and BI.FitsWeapon) or BI.IsWeaponBuff then return end
    local A = ns.api

    local function stoneOn() return not (ns.db and ns.db.stoneStep == false) end

    -- Names that mean "goes on a weapon": stones, weightstones, oils.
    local function isWeaponBuff(name)
        if not name then return false end
        return name:find("Sharpening Stone") ~= nil or name:find("Weightstone") ~= nil
            or name:find("Oil") ~= nil
    end

    local function nameOf(id)
        local n = A.ItemInfo and A.ItemInfo(id)
        if n then return n end
        if C_Item and C_Item.GetItemNameByID then return C_Item.GetItemNameByID(id) end
    end

    local function mainHandSub()
        local id = GetInventoryItemID and GetInventoryItemID("player", 16)
        if not id then return nil end
        local info
        if C_Item and C_Item.GetItemInfoInstant then info = { C_Item.GetItemInfoInstant(id) }
        elseif GetItemInfoInstant then info = { GetItemInfoInstant(id) } end
        if info and info[6] == 2 then return info[7] end
    end

    -- The first weapon buff in your bags that fits the weapon: { id, name } or nil.
    local function find(weaponSub)
        local C = C_Container
        local slots = (C and C.GetContainerNumSlots) or GetContainerNumSlots
        local itemAt = (C and C.GetContainerItemID) or GetContainerItemID
        if not (slots and itemAt) then return nil end
        for bag = 0, 4 do
            for slot = 1, (slots(bag) or 0) do
                local id = itemAt(bag, slot)
                local name = id and nameOf(id)
                if isWeaponBuff(name) and BI.FitsWeapon(name, weaponSub) then return { id = id, name = name } end
            end
        end
    end

    local function why()
        local sub = mainHandSub()
        local hasEnchant = GetWeaponEnchantInfo and GetWeaponEnchantInfo() and true or false
        local item = sub and find(sub)
        return sub, hasEnchant, item
    end

    ns:Register("action", "buff:stone", { order = 4, get = function()
        if not stoneOn() or UnitIsDeadOrGhost("player") then return nil end
        if IsResting and IsResting() then return nil end
        local sub, hasEnchant, item = why()
        if not sub or hasEnchant or not item then return nil end
        local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(item.id)) or (GetItemIcon and GetItemIcon(item.id))
        return { type = "item", item = "item:" .. item.id, icon = icon, targetSlot = 16,
                 label = "Put on your weapon: " .. item.name,
                 reason = "Your weapon has no stone on it" }
    end })

    ns.commands.stone = function(arg)
        arg = (arg or ""):lower()
        if arg == "on" or arg == "off" then ns.db.stoneStep = (arg == "on") end
        local sub, hasEnchant, item = why()
        ns:Print("weapon stone step: " .. (stoneOn() and "on" or "off") .. " (/flow stone on|off)")
        print(string.format("  main hand type: %s, already has a stone/oil: %s, one in your bags that fits: %s, resting here: %s",
            tostring(sub), tostring(hasEnchant), item and item.name or "none",
            tostring(IsResting and IsResting() or false)))
    end

    ns:Register("test", "stone: weapon buffs are found by name and fit the weapon", function(t)
        t:ok(isWeaponBuff("Rough Sharpening Stone"), "a sharpening stone")
        t:ok(isWeaponBuff("Rough Weightstone"), "a weightstone")
        t:ok(not isWeaponBuff("Linen Bandage"), "not a bandage")
        t:ok(not isWeaponBuff(nil), "no name, no match")
        t:ok(BI.FitsWeapon("Rough Sharpening Stone", 7), "stone on a one-hand sword")
        t:ok(not BI.FitsWeapon("Rough Sharpening Stone", 4), "no stone on a mace")
        t:ok(BI.FitsWeapon("Rough Weightstone", 5), "weightstone on a two-hand mace")
        t:ok(ns:Get("action", "buff:stone") ~= nil, "the step is registered")
    end)
end)()

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
-- 3. Weapon stone step (further down): /flow stone
-- 4. Buff button (at the end): buffs and weapon stones/oils on their own
--    button left of Flow's icon. /flow buffbutton on|off, /flow buffkey <KEY>

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

    -- Names that mean "goes on a weapon": stones, weightstones, real weapon oils
    -- (not Oily Blackmouth, Fire Oil or Oil of Immolation).
    local OILS = { "Wizard Oil", "Mana Oil", "^Frost Oil$", "^Shadow Oil$" }
    local function isWeaponBuff(name)
        if not name then return false end
        if name:find("Sharpening Stone") or name:find("Weightstone") then return true end
        for _, o in ipairs(OILS) do
            if name:find(o) then return true end
        end
        return false
    end

    local FISHING_POLE = 20
    local SUBNAME = { [0] = "one-hand axe", [1] = "two-hand axe", [4] = "one-hand mace",
        [5] = "two-hand mace", [6] = "polearm", [7] = "one-hand sword", [8] = "two-hand sword",
        [10] = "staff", [13] = "fist weapon", [15] = "dagger", [20] = "fishing pole" }

    local function fits(name, sub)
        return sub ~= nil and sub ~= FISHING_POLE and BI.FitsWeapon(name, sub) and true or false
    end

    -- A live enemy targeted: you're about to pull, let the rotation's opener go first.
    local function enemyTargeted()
        return UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target") or false
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

    -- Every weapon buff in your bags: { { id, name }, ... }.
    local function carried()
        local out, seen = {}, {}
        local C = C_Container
        local slots = (C and C.GetContainerNumSlots) or GetContainerNumSlots
        local itemAt = (C and C.GetContainerItemID) or GetContainerItemID
        if not (slots and itemAt) then return out end
        for bag = 0, 4 do
            for slot = 1, (slots(bag) or 0) do
                local id = itemAt(bag, slot)
                local name = id and not seen[id] and nameOf(id)
                if id then seen[id] = true end
                if isWeaponBuff(name) then out[#out + 1] = { id = id, name = name } end
            end
        end
        return out
    end

    -- The first weapon buff in your bags that fits the weapon: { id, name } or nil.
    local function find(weaponSub)
        for _, it in ipairs(carried()) do
            if fits(it.name, weaponSub) then return it end
        end
    end

    local function why()
        local sub = mainHandSub()
        local hasEnchant = GetWeaponEnchantInfo and GetWeaponEnchantInfo() and true or false
        local item = sub and find(sub)
        return sub, hasEnchant, item
    end

    -- Order 2.5: before buff:item and bag:learn, which aren't urgent and would
    -- otherwise be returned first and keep this step off the icon.
    -- Urgent unless an enemy is targeted or you're under half health (fishing:
    -- no step at all, the pole is on): out of combat the
    -- rotation nearly always suggests something (a paladin's seal, an aura),
    -- and a step that isn't urgent only shows when the rotation suggests nothing.
    ns:Register("action", "buff:stone", { order = 2.5, get = function(ctx)
        if not stoneOn() or UnitIsDeadOrGhost("player") then return nil end
        if IsResting and IsResting() then return nil end
        if ctx and ctx.fishing then return nil end
        local sub, hasEnchant, item = why()
        if not sub or hasEnchant or not item then return nil end
        local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(item.id)) or (GetItemIcon and GetItemIcon(item.id))
        return { type = "item", item = "item:" .. item.id, icon = icon, targetSlot = 16,
                 -- Low on health: let the rotation's heal go first.
                 urgent = not enemyTargeted() and (UnitHealth("player") or 0) > 0.5 * (UnitHealthMax("player") or 1),
                 label = "Put on your weapon: " .. item.name,
                 reason = "Your weapon has no stone on it" }
    end })

    ns.commands.stone = function(arg)
        arg = (arg or ""):lower()
        if arg == "on" or arg == "off" then ns.db.stoneStep = (arg == "on") end
        local sub, hasEnchant, item = why()
        local resting = IsResting and IsResting() or false
        ns:Print("weapon stone step: " .. (stoneOn() and "on" or "off") .. " (/flow stone on|off)")
        local mh = GetInventoryItemID and GetInventoryItemID("player", 16)
        print(string.format("  main hand: %s (%s)", mh and (nameOf(mh) or ("item " .. mh)) or "nothing",
            sub and (SUBNAME[sub] or ("weapon type " .. sub)) or "not a weapon"))
        print("  already has a stone/oil on it: " .. (hasEnchant and "yes" or "no"))
        local all = carried()
        if #all == 0 then print("  stones/oils in your bags: none") end
        for _, it in ipairs(all) do
            print(string.format("  in your bags: %s - %s", it.name,
                fits(it.name, sub) and "fits this weapon" or "does NOT fit this weapon (sharpening stones: blades; weightstones: maces/staves)"))
        end
        print("  resting (inn/city, step waits): " .. (resting and "yes" or "no")
            .. ", enemy targeted: " .. (enemyTargeted() and "yes" or "no"))
        local blocker = (not stoneOn() and "the step is off")
            or (not sub and "no weapon in your main hand")
            or (hasEnchant and "your weapon already has one on")
            or (not item and "nothing in your bags fits this weapon")
            or (resting and "you're resting; leave the inn/city")
            or (InCombatLockdown() and "you're in combat")
        if blocker then
            print("  -> not showing: " .. blocker)
        else
            local where = (ns.buffButton and ns.buffButton.On())
                and "on the blue buff button left of Flow's icon - click it or press your buff key (/flow buffkey)"
                or "on Flow's icon - click the icon or press your Flow key"
            print("  -> showing " .. where .. ": \"Put on your weapon: " .. item.name .. "\"")
        end
        local shown = ns.rotation and ns.rotation.shown
        if shown then
            print("  Flow's icon shows right now: " .. tostring(shown.label or shown.spell or shown.key or shown.kind))
        end
    end

    ns:Register("test", "stone: weapon buffs are found by name and fit the weapon", function(t)
        t:ok(isWeaponBuff("Rough Sharpening Stone"), "a sharpening stone")
        t:ok(isWeaponBuff("Rough Weightstone"), "a weightstone")
        t:ok(not isWeaponBuff("Linen Bandage"), "not a bandage")
        t:ok(not isWeaponBuff(nil), "no name, no match")
        t:ok(isWeaponBuff("Lesser Wizard Oil"), "a wizard oil")
        t:ok(not isWeaponBuff("Oily Blackmouth"), "not a fish")
        t:ok(not isWeaponBuff("Fire Oil"), "not fire oil")
        t:ok(not fits("Lesser Wizard Oil", FISHING_POLE), "nothing on a fishing pole")
        local a = ns:Get("action", "buff:stone")
        t:ok(a and a.order < 3, "comes before buff:item and bag:learn")
        t:ok(BI.FitsWeapon("Rough Sharpening Stone", 7), "stone on a one-hand sword")
        t:ok(not BI.FitsWeapon("Rough Sharpening Stone", 4), "no stone on a mace")
        t:ok(BI.FitsWeapon("Rough Weightstone", 5), "weightstone on a two-hand mace")
        t:ok(ns:Get("action", "buff:stone") ~= nil, "the step is registered")
    end)
end)()

-- Buff button (local): a second button, beside Flow's icon, for your buffs and
-- weapon enhancements, so the main icon and key are only ever your fight
-- (damage, heals, dispels, Flow Actions) and the two never get mixed up.
--
--   Buff button: the rotation's "buff" suggestions (seals, auras, blessings,
--   shouts, group buffs) first, then a stone, weightstone or oil for your
--   weapon (buff:stone, buff:item). Out of combat it shows what's missing and
--   hides when nothing is.
--   In a fight: WoW won't let addons change what a button casts, so it holds
--   the buff spell you last cast from it (a paladin's seal: press it again
--   when the seal runs out). Bright = needed now, dim = still on.
--
--   /flow buffbutton on|off     (on by default)
--   /flow buffkey <KEY>         its own key, e.g. /flow buffkey Q  (off: clear)
-- It sits left of Flow's icon and moves with it (Shift + drag Flow's icon).
do
    local A, E = ns.api, ns.rotation
    local BB = {}
    ns.buffButton = BB

    local function cfg()
        ns.db.buffButton = ns.db.buffButton or {}
        return ns.db.buffButton
    end
    function BB.On() return ns.db ~= nil and cfg().enabled ~= false end

    -------------------------------------------------------------------------------
    -- Pure parts (tested)
    -------------------------------------------------------------------------------

    -- A priority list without its "buff" rules (cached per list).
    local stripped = setmetatable({}, { __mode = "k" })
    function BB.Strip(list)
        if not list then return nil end
        local out = stripped[list]
        if out then return out end
        out = {}
        for _, r in ipairs(list) do
            if r.kind ~= "buff" then out[#out + 1] = r end
        end
        stripped[list] = out
        return out
    end

    local strippedSets = setmetatable({}, { __mode = "k" })
    local function stripSet(set)
        if not set then return nil end
        local out = strippedSets[set]
        if out then return out end
        out = {}
        for k, v in pairs(set) do out[k] = BB.Strip(v) end
        strippedSets[set] = out
        return out
    end

    -- What the button shows out of combat: a buff spell first (quick), then an
    -- item for your weapon (a 3 s use).
    function BB.Pick(spellBuff, itemBuff) return spellBuff or itemBuff end

    -- What the button holds for a fight: the live buff spell, else the buff spell
    -- you last cast, else nothing (an item takes too long mid-fight).
    function BB.FightSpell(live, lastCast)
        if live and live.spell then return live.spell end
        return lastCast
    end

    -------------------------------------------------------------------------------
    -- The rotation without its buffs; the buffs on their own
    -------------------------------------------------------------------------------

    local liveBuff, liveAt = nil, 0   -- the rotation's buff suggestion, and when it was worked out

    local function ready(rule, ctx)
        if not ctx.inCombat and E.Resting() then return false end
        if not E:Knows(rule.spell) then return false end
        if rule.when then
            local ok, w = pcall(rule.when, ctx)
            if not ok or not w then return false end
        end
        return E:Ready(rule.spell, rule.target and "target" or nil)
    end

    local function pickBuff(def, ctx)
        local list = (def.priorities and def.priorities[ctx.fightType]) or def.priority or {}
        for _, rule in ipairs(list) do
            if rule.kind == "buff" and ready(rule, ctx) then
                return { spell = rule.spell, kind = "buff", reason = rule.reason or rule.spell }
            end
        end
        local ok, g = pcall(E.GroupBuff, E, ctx, def)
        if ok and g then return g end
    end

    local function noGroupBuff() return nil end

    local origChoose = E.Choose
    function E:Choose()
        local def = BB.On() and self:Definition()
        if not def then return origChoose(self) end
        local p, ps, gb = def.priority, def.priorities, self.GroupBuff
        def.priority, def.priorities, self.GroupBuff = BB.Strip(p), stripSet(ps), noGroupBuff
        local ok, s = pcall(origChoose, self)
        def.priority, def.priorities, self.GroupBuff = p, ps, gb
        if not ok then error(s, 0) end
        local ctx = self.lastCtx
        if ctx then
            local okB, b = pcall(pickBuff, def, ctx)
            liveBuff, liveAt = okB and b or nil, GetTime()
        end
        return s
    end

    -- Weapon enhancements and buff items leave the main icon for this button.
    local itemGets = {}
    for _, key in ipairs({ "buff:stone", "buff:item" }) do
        local a = ns:Get("action", key)
        if a and a.get then
            local orig = a.get
            itemGets[#itemGets + 1] = orig
            a.get = function(ctx)
                if BB.On() then return nil end
                return orig(ctx)
            end
        end
    end

    local function pickItem()
        if not ns.actions or (ns.db.actions and ns.db.actions.enabled == false) then return nil end
        if UnitIsDeadOrGhost("player") then return nil end
        local ctx = ns.actions:Context()
        for _, get in ipairs(itemGets) do
            local ok, s = pcall(get, ctx)
            if ok and s then return s end
        end
    end

    -------------------------------------------------------------------------------
    -- The button
    -------------------------------------------------------------------------------

    local btn, tex, label, keyText
    local shownText          -- what the secure button is set to, to skip repeats
    local lastCast           -- the buff spell you last cast (held for fights)
    local buffSpells = {}    -- every buff spell this button has shown
    local current            -- what it shows now

    local function spellTex(spell) return spell and select(2, A.SpellInfo(spell)) end

    local function itemId(s) return s and s.item and tonumber(tostring(s.item):match("(%d+)")) end

    local function describe(s)
        if not s then return "" end
        if s.spell then return "spell " .. s.spell .. " @" .. tostring(s.unit or "player") end
        return "item " .. tostring(s.item) .. " slot " .. tostring(s.targetSlot)
    end

    local function setAction(s)
        if InCombatLockdown() or not btn then return end
        local text = describe(s)
        if text == shownText then return end
        shownText = text
        for _, a in ipairs({ "type", "spell", "item", "unit", "target-slot" }) do btn:SetAttribute(a, nil) end
        if s and s.spell then
            btn:SetAttribute("type", "spell")
            btn:SetAttribute("spell", s.spell)
            btn:SetAttribute("unit", s.unit or "player")
        elseif s and s.item then
            btn:SetAttribute("type", "item")
            btn:SetAttribute("item", s.item)
            btn:SetAttribute("target-slot", s.targetSlot)
        end
    end

    local function keyLabel()
        local key = cfg().key
        if not key then return "" end
        return ns.cast and ns.cast.ShortKey and ns.cast.ShortKey(key, GetBindingText and function(k) return GetBindingText(k, "KEY_", true) end) or key
    end

    local function paint(s, bright)
        if not btn then return end
        local t = s and (s.icon or (s.spell and spellTex(s.spell))
            or (itemId(s) and ((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemId(s))) or (GetItemIcon and GetItemIcon(itemId(s))))))
        tex:SetTexture(t or "Interface\\Icons\\INV_Misc_QuestionMark")
        tex:SetDesaturated(not bright)
        btn:SetAlpha(bright and 1 or 0.55)
        local name = s and (s.spell or (itemId(s) and A.ItemInfo and A.ItemInfo(itemId(s))) or s.label) or ""
        if s and s.target then name = name .. " on " .. s.target end
        label:SetText(name)
        keyText:SetText(keyLabel())
    end

    local function fillTooltip(tt)
        local s = current
        local id = s and s.spell and select(4, A.SpellInfo(s.spell))
        local item = itemId(s)
        if id and tt.SetSpellByID then tt:SetSpellByID(id)
        elseif item and tt.SetItemByID then tt:SetItemByID(item) end
        if id or item then tt:AddLine(" ") end
        tt:AddLine("Flow buff button", 1, 0.82, 0)
        if s and s.reason then tt:AddLine("Why: " .. s.reason, 1, 1, 1, true) end
        if InCombatLockdown() then
            tt:AddLine("In a fight it holds " .. tostring(s and s.spell or "nothing") .. " (it can't change mid-fight).", 1, 0.6, 0.3, true)
        end
        local key = cfg().key
        tt:AddLine(key and ("Key: " .. ((GetBindingText and GetBindingText(key, "KEY_", true)) or key))
            or "No key yet: /flow buffkey <key>", 0.8, 0.8, 0.8)
    end

    local function build()
        btn = CreateFrame("Button", "FlowBuffButton", UIParent, "SecureActionButtonTemplate")
        btn:SetSize(40, 40)
        btn:SetFrameStrata("HIGH")
        local main = _G.FlowCastButton
        if main then btn:SetPoint("RIGHT", main, "LEFT", -12, 0)
        else btn:SetPoint("CENTER", UIParent, "CENTER", -60, -160) end
        btn:RegisterForClicks("AnyUp", "AnyDown")
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("TOPLEFT", -2, 2); bg:SetPoint("BOTTOMRIGHT", 2, -2)
        bg:SetColorTexture(0.1, 0.6, 1, 0.9)   -- blue edge: the buff button
        tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOP", btn, "BOTTOM", 0, -3)
        label:SetWidth(110)
        label:SetTextColor(0.5, 0.8, 1)
        keyText = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        keyText:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -2, -2)
        btn:SetScript("OnEnter", function(self)
            ns.Tip(self, "ANCHOR_LEFT")
            pcall(fillTooltip, GameTooltip)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        btn:HookScript("PostClick", function(_, _, down)
            if down ~= false and current and not InCombatLockdown() then
                ns:Log("action", "buff button pressed: " .. describe(current))
            end
        end)
        btn:Hide()
    end

    -- Key: an override binding, like Flow's own key (your bindings never change).
    local owner = CreateFrame("Frame")
    local pendingKey = false
    local function applyKey()
        if InCombatLockdown() then pendingKey = true return end
        pendingKey = false
        ClearOverrideBindings(owner)
        local key = cfg().key
        if key and BB.On() then SetOverrideBindingClick(owner, true, key, "FlowBuffButton", "LeftButton") end
        if keyText then keyText:SetText(keyLabel()) end
    end

    local function fresh() return liveBuff and GetTime() - liveAt < 1 and liveBuff or nil end

    local acc = 0
    local function tick(_, dt)
        acc = acc + dt
        if acc < 0.25 then return end
        acc = 0
        if not btn then return end
        if not BB.On() then
            if not InCombatLockdown() and btn:IsShown() then btn:Hide() end
            return
        end
        local live = fresh()
        if live and live.spell then buffSpells[live.spell] = true end
        if InCombatLockdown() then
            -- The button holds what it was set to at the pull; bright when the
            -- rotation wants that spell again.
            local held = btn:GetAttribute("spell")
            current = held and { spell = held, reason = live and live.reason } or nil
            if current then paint(current, live and live.spell == held) end
            return
        end
        local s = BB.Pick(live, pickItem())
        current = s
        setAction(s)
        if s then paint(s, true) end
        if (s ~= nil) ~= btn:IsShown() then btn:SetShown(s ~= nil) end
    end

    ns:OnLoad(function()
        build()
        applyKey()
        local driver = CreateFrame("Frame")
        driver:SetScript("OnUpdate", tick)
    end)

    ns:On("PLAYER_ENTERING_WORLD", applyKey)
    ns:On("PLAYER_REGEN_ENABLED", function() if pendingKey then applyKey() end end)

    -- Just before the fight locks buttons: hold the buff spell for the fight.
    ns:On("PLAYER_REGEN_DISABLED", function()
        if not (btn and BB.On()) then return end
        local spell = BB.FightSpell(fresh(), lastCast)
        if spell and E:Knows(spell) then
            setAction({ spell = spell, unit = "player" })
            if not btn:IsShown() then btn:Show() end
        else
            setAction(nil)
            if btn:IsShown() then btn:Hide() end
        end
    end)

    ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
        if unit ~= "player" then return end
        local name = A.SpellInfo(A.Safe(spellID) or 0)
        if name and buffSpells[name] then lastCast = name end
    end)

    -------------------------------------------------------------------------------
    -- Commands and test
    -------------------------------------------------------------------------------

    function BB.Set(on)
        cfg().enabled = on and true or false
        applyKey()
    end

    -- Options > AddOns > Flow, under "Flow".
    if ns.settings and ns.settings.AddCheck then
        ns.settings:AddCheck({
            label = "Buff button beside Flow's icon",
            note = "(own key: /flow buffkey <key>)",
            tip = "Your buffs (seals, auras, blessings, shouts, party buffs) and weapon stones and oils go on a "
                .. "separate blue button left of Flow's icon, so Flow's key only does your fight: damage, heals "
                .. "and cleanses. Give it its own key with /flow buffkey Q. In a fight it keeps the buff you "
                .. "last cast from it and lights up when that buff runs out. Off: buffs and stones go back on "
                .. "Flow's icon and key.",
            get = function() return BB.On() end,
            set = function(on) BB.Set(on) end,
        })
    end

    ns.commands.buffbutton = function(arg)
        arg = (arg or ""):lower()
        if arg == "on" or arg == "off" then BB.Set(arg == "on") end
        ns:Print("buff button: " .. (BB.On() and "on" or "off") .. " (/flow buffbutton on|off)")
        print("  key: " .. (cfg().key or "none (/flow buffkey <key>)"))
        print("  shows now: " .. (current and describe(current) or "nothing"))
        print("  held for fights: " .. tostring(lastCast or "nothing cast from it yet"))
    end

    ns.commands.buffkey = function(arg)
        arg = (arg or ""):gsub("%s+", ""):upper()
        if arg == "" then
            ns:Print("buff button key: " .. (cfg().key or "none") .. "  (/flow buffkey Q sets it, /flow buffkey off clears it)")
            return
        end
        if arg == "OFF" then cfg().key = nil
        else
            local main = ns.cast and ns.cast.KeysOf and ns.cast.KeysOf(ns.db.cast) or {}
            for _, k in ipairs(main) do
                if k == arg then ns:Print(arg .. " is already Flow's main key: pick another") return end
            end
            cfg().key = arg
            local other = GetBindingAction and GetBindingAction(arg)
            if other and other ~= "" then
                ns:Print(string.format("note: %s also did %s; while Flow's buff button has it, it presses the buff button.",
                    arg, _G["BINDING_NAME_" .. other] or other))
            end
        end
        applyKey()
        ns:Print("buff button key: " .. (cfg().key or "none"))
    end

    ns:Register("test", "buff button: buffs off the main icon, onto their own button", function(t)
        local list = { { spell = "Seal", kind = "buff" }, { spell = "Strike" }, { spell = "Aura", kind = "buff" }, { spell = "Heal", kind = "heal" } }
        local out = BB.Strip(list)
        t:eq(#out, 2, "two rules left")
        t:eq(out[1].spell, "Strike", "damage kept")
        t:eq(out[2].spell, "Heal", "heal kept")
        t:ok(BB.Strip(list) == out, "cached per list")
        t:eq(BB.Pick({ spell = "Seal" }, { item = "item:2862" }).spell, "Seal", "a buff spell before a stone")
        t:eq(BB.Pick(nil, { item = "item:2862" }).item, "item:2862", "the stone when no buff spell is due")
        t:eq(BB.FightSpell({ spell = "Seal" }, "Blessing"), "Seal", "fight: the buff due now")
        t:eq(BB.FightSpell(nil, "Seal"), "Seal", "fight: else the one you last cast")
        t:ok(BB.FightSpell(nil, nil) == nil, "fight: else nothing")
        local stone = ns:Get("action", "buff:stone") or ns:Get("action", "buff:item")
        t:ok(not BB.On() or stone == nil or stone.get({}) == nil, "stones aren't on the main icon while the buff button is on")
    end)
end

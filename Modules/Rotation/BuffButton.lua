-- Self button: a second button, left of Flow's icon, for your buffs and weapon
-- enhancements, so the main icon and key are only ever your fight (damage,
-- heals, dispels, Flow Actions) and the two never get mixed up.
--
--   Out of combat it shows a stone, weightstone, oil or buff item first
--   (BuffItems.lua's "buff:item": a 3 s use that can't go on in a fight), then
--   the rotation's "buff" suggestions (auras, aspects, blessings on you).
--   Seals, shouts, shields, Hunter's Mark and fight forms stay on Flow's icon
--   with the fight (BB.OnAction). Before all of those, hurt after a fight:
--   your bandage or food; after them, by a campfire: place your camp objects
--   and sit. So Flow's key keeps to the fight, loot and gathering. It always
--   shows the next buff: the one due, else the one of yours (spell, stone,
--   Well Fed, elixir) that runs out first, with its time left. All of it,
--   bandage and campfire included, stays faded until a fight is near (an
--   enemy targeted, a kill step, just after a fight), so you use it when you
--   choose; "no buffs due" only when you have no buffs at all (hover: why).
--   In a fight: WoW won't let addons change what a button casts, so it holds
--   the buff spell due at the pull, else the one you last cast from it (press
--   it again when that buff runs out). Bright = needed now, dim = still on.
--
--   /flow buffbutton on|off     (off by default: buffs stay on Flow's key until you turn it on)
--   /flow buffkey <KEY>         its own key, e.g. /flow buffkey Q  (off: clear)
-- It sits left of Flow's icon. With the move handle (Modules/MoveHandle.lua,
-- ns:MoveHandle) Ctrl + drag moves it and Ctrl + mouse wheel resizes it.
local _, ns = ...
local A, E = ns.api, ns.rotation
if not (A and E and E.Choose) then return end

local BB = {}
ns.buffButton = BB

local function cfg()
    ns.db.buffButton = ns.db.buffButton or {}
    return ns.db.buffButton
end
-- Off unless you turn it on: on, the Flow key stops casting your buffs
-- (blessings, auras, Mark of the Wild) and stones, which surprised players
-- who never asked for a second button.
function BB.On() return ns.db ~= nil and cfg().enabled == true end
-- Does this button do your fishing by itself? On, with a key (reeling in
-- needs a key: a click can't reach the bobber). Then the Flow key leaves
-- fishing to it (Actions.lua).
function BB.Fishes() return BB.On() and (cfg().key ~= nil or cfg().key2 ~= nil) end

-- Buffs that stay on Flow's icon and key because they're part of the fight,
-- pressed with the rest of it: a paladin's seal (Judgement needs one up),
-- shouts, shields (Lightning Shield, Power Word: Shield), Hunter's Mark, and
-- a druid's fight form (Bear, Cat, Moonkin) when the rotation asks you to
-- shift for the fight. Auras, aspects, blessings, Mark of the Wild and Travel
-- Form go on the self button.
local ON_ACTION = { "^Seal of ", " Shout$", " Shield$", "^Hunter's Mark$",
                    "^Bear Form$", "^Dire Bear Form$", "^Cat Form$", "^Moonkin Form$" }
function BB.OnAction(rule)
    local name = type(rule) == "table" and rule.spell
    if type(name) ~= "string" then return false end
    for _, pat in ipairs(ON_ACTION) do
        if name:find(pat) then return true end
    end
    return false
end

-------------------------------------------------------------------------------
-- Pure parts (tested)
-------------------------------------------------------------------------------

-- A priority list without the "buff" rules that move to this button (cached
-- per list).
local stripped = setmetatable({}, { __mode = "k" })
function BB.Strip(list)
    if not list then return nil end
    local out = stripped[list]
    if out then return out end
    out = {}
    for _, r in ipairs(list) do
        if r.kind ~= "buff" or BB.OnAction(r) then out[#out + 1] = r end
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

-- What the button shows out of combat: the item first (do it while you can),
-- then a buff spell. Before them, hurt after a fight: your bandage or food.
-- After them, by a campfire: place your camp objects, sit for the camp buffs.
-- An item that's only a preview (soon: no fight near yet) goes last.
-- Not Well Fed and carrying the food for it: your buff spells (aura, seal,
-- blessing, Righteous Fury) first, then that food. "The food buff is always
-- first... it's overriding everything I need to use." Hurt or out of mana
-- after a fight, healing up still comes first (a cure, a drink, a heal
-- spell, the food that heals you), except a bandage: then the Well Fed food
-- (one meal heals you and buffs you; bandaging first would waste the bandage).
-- Fishing (at a fishing step without your pole on, or your pole on with no
-- lure): equip the pole / put on the lure, right after healing up.
function BB.Pick(spellBuff, itemBuff, recover, camp, fish)
    if fish then return recover or fish end
    if itemBuff and itemBuff.wellFed then
        if recover then return recover.bandage and itemBuff or recover end
        return spellBuff or itemBuff
    end
    if itemBuff and itemBuff.soon then return recover or spellBuff or camp or itemBuff end
    return recover or itemBuff or spellBuff or camp
end

-- Bright (do it now) or faded (the next buff, use it when you choose).
-- Everything is faded until a fight is near (about to kill a lot, just after
-- a fight, or an enemy targeted): the bandage, the food and the campfire
-- too. A buff that's still on (later) lights up then only if it runs out
-- within RUNNING_OUT seconds. The faded one still works when pressed.
-- The pole or its lure is bright always: you're fishing now.
local RUNNING_OUT = 120
function BB.Bright(s, fightNear)
    if s and s.fish then return true end
    if not s or s.idle or fightNear ~= true then return false end
    if s.later then return (s.left or math.huge) < RUNNING_OUT end
    return true
end

-- Nothing due: the buff that runs out first. cands = { { step, left } },
-- left in seconds (math.huge: never runs out, only when nothing else does).
-- The step comes back marked later, with its time left.
function BB.Soonest(cands)
    local best
    for _, c in ipairs(cands or {}) do
        if c.step and c.left and (not best or c.left < best.left) then best = c end
    end
    if not best then return nil end
    best.step.later, best.step.left = true, best.left
    return best.step
end

-- "12m", "40s", or "on" (never runs out).
function BB.Left(sec)
    if not sec or sec == math.huge then return "on" end
    if sec >= 60 then return math.floor(sec / 60 + 0.5) .. "m" end
    return math.max(0, math.floor(sec)) .. "s"
end

-- What the button holds for a fight: the live buff spell, else the buff spell
-- you last cast, else nothing (an item takes too long mid-fight).
function BB.FightSpell(live, lastCast)
    if live and live.spell then return live.spell end
    return lastCast
end

-- Pure: nothing is due; what then? always: "always show my next buff" is
-- ticked; fight: an enemy is targeted and this key heals. -> "next" (the
-- buff that runs out first, as before 0.35.208), "heal" (your heal, ready)
-- or "hide".
function BB.WhenIdle(always, fight)
    if always then return "next" end
    return fight and "heal" or "hide"
end

-- What the button shows when nothing is due (dim, does nothing).
function BB.Idle()
    return { idle = true, label = "no buffs due", reason = "Nothing to buff right now." }
end

-------------------------------------------------------------------------------
-- The rotation without its buffs; the buffs on their own
-------------------------------------------------------------------------------

local liveBuff, liveAt = nil, 0   -- the rotation's buff suggestion, and when it was worked out
local liveRecover                 -- hurt after a fight: the bandage or food to use (same moment)
local liveCure                    -- a poison, curse... on you that you can remove (the split, below)
local liveNext                    -- your buffs still on, with their time left (out of a fight, once a second)
local liveNextAt = -math.huge

-- In towns and inns too: the button only shows it (faded), you choose.
local function ready(rule, ctx)
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
        if rule.kind == "buff" and not BB.OnAction(rule) and ready(rule, ctx) then
            return { spell = rule.spell, kind = "buff", reason = rule.reason or rule.spell }
        end
    end
    -- (Buffs for your group are Flow's key's: this button is for you, 0.35.244.)
end
BB._pickBuff = pickBuff  -- (tests)

-- Your buff spells that are on you now, each with its time left.
local function onSpells(def, ctx)
    local list = (def.priorities and def.priorities[ctx.fightType]) or def.priority or {}
    local out = {}
    for _, rule in ipairs(list) do
        if rule.kind == "buff" and not BB.OnAction(rule) and E:Knows(rule.spell) then
            local on, left = A.Buff("player", rule.spell)
            if on then
                out[#out + 1] = { left = left, step = { spell = rule.spell, kind = "buff", unit = "player",
                    reason = "Still on you. Recast it whenever you like, before it runs out." } }
            end
        end
    end
    return out
end

-- The split (0.35.241): this button is yours, Flow's key is your target's.
-- With a key of its own and looking after you (CareKeys: K.Moved), out of a
-- fight everything cast on YOU is this button's: healing up (heal spell,
-- bandage, food, drink), a poison or curse to take off you, your buffs. Flow's
-- key keeps what goes on your TARGET: attacks on an enemy, and heals, buffs
-- and cures on a friendly one. Which key you press says who gets it.
function BB.TakesMine()
    local K = ns.careKeys
    return (K ~= nil and K.Moved ~= nil and K.Moved()) and true or false
end
-- Pure: is this step cast on you? (A step with no unit named is, when it
-- helps: heals and buffs fall on yourself.)
function BB.IsMine(s)
    if not s then return false end
    if s.unit then return s.unit == "player" end
    return (s.kind == "heal" or s.kind == "emergency" or s.kind == "buff" or s.kind == "recover") and true or false
end
-- Pure: what Flow's key keeps of a step once this button takes yours: nil
-- for one on you out of a fight; anything else stays (in a fight nothing
-- moves: the keys are set at the pull, and Flow's icon still says what's wanted).
function BB.ForTarget(s, takesMine, inCombat)
    if s and takesMine and not inCombat and BB.IsMine(s) then return nil end
    return s
end
-- Pure: healing up before the rest; a poison or curse on you first of all.
function BB.MineFirst(cure, recover) return cure or recover end

-- Healing up, all of it, as Flow's key did it (E:HealStep out of a fight):
-- nothing above 80% but a drink; else your recovery order, then a drink.
function BB.MineRecover(e, ctx, def)
    if ctx.inCombat then return nil end
    if E.HealthFine(ctx) then return e:DrinkStep(ctx) end
    return e:Recover(ctx, def, "all") or e:DrinkStep(ctx)
end

-- While the button is on, the rotation chooses from its lists without the
-- buffs; what it would have buffed is worked out beside it, for this button.
-- Buffs for your group stay with Flow's key ("Target button buffs your group"). The definition is put back whatever happens.
local origChoose = E.Choose
function E:Choose()
    local def = BB.On() and self:Definition()
    if not def then return origChoose(self) end
    local p, ps = def.priority, def.priorities
    local hs, dp = self.HealStep, self.Dispel
    local mine = BB.TakesMine()
    local cure
    def.priority, def.priorities = BB.Strip(p), stripSet(ps)
    if mine then
        -- Healing yourself up and curing yourself, out of a fight: not Flow's
        -- key's any more (worked out for this button just below).
        self.HealStep = function(e, c, d)
            if c.inCombat then return hs(e, c, d) end
            return nil
        end
        self.Dispel = function(e, c, d)
            local found = dp(e, c, d)
            local kept = BB.ForTarget(found, true, c.inCombat)
            if found and not kept then cure = found end
            return kept
        end
    end
    local ok, s = pcall(origChoose, self)
    def.priority, def.priorities = p, ps
    self.HealStep, self.Dispel = hs, dp
    if not ok then error(s, 0) end
    local ctx = self.lastCtx
    if ctx then
        local okB, b = pcall(pickBuff, def, ctx)
        liveBuff, liveAt = okB and b or nil, GetTime()
        -- Hurt: this button's part of healing up. Yours altogether (the split):
        -- the whole order, heal spell included, and a drink.
        local okR, rec
        if mine then
            okR, rec = pcall(BB.MineRecover, self, ctx, def)
        else
            okR, rec = pcall(self.Recover, self, ctx, def, "items")
        end
        liveRecover = okR and rec or nil
        liveCure = mine and cure or nil
        -- Your buffs still on (for "what's next" on the button): only shown
        -- out of a fight, and it reads every buff of yours for each buff
        -- rule, so once a second there, not ten times a second everywhere
        -- (review of pull request 19).
        if ctx.inCombat then
            liveNext = nil
        elseif GetTime() - liveNextAt >= 1 then
            local okN, on = pcall(onSpells, def, ctx)
            liveNext, liveNextAt = okN and on or nil, GetTime()
        end
    end
    return s
end

-- Weapon enhancements and buff items leave the main icon for this button.
local itemGet
do
    local a = ns:Get("action", "buff:item")
    if a and a.get then
        itemGet = a.get
        a.get = function(ctx)
            if BB.On() then return nil end
            return itemGet(ctx)
        end
    end
end

-- The campfire steps (place your camp objects, sit, wait) leave it too, once
-- this button has a key of its own: sitting is the game's Sit/Stand on that
-- key (a button can't sit you: macro buttons are ignored on Forever), so
-- with no key they stay on Flow's key, which sits you the same way.
function BB.TakesCamp() return BB.On() and (cfg().key ~= nil or cfg().key2 ~= nil) end
local campGet
do
    local a = ns:Get("action", "buff:camp")
    if a and a.get then
        campGet = a.get
        a.get = function(ctx)
            if BB.TakesCamp() then return nil end
            return campGet(ctx)
        end
    end
end
-- Flow Actions' context for this moment, or nil (Actions off, or dead).
local function actionCtx()
    if not ns.actions or (ns.db.actions and ns.db.actions.enabled == false) then return nil end
    if UnitIsDeadOrGhost("player") then return nil end
    local ok, ctx = pcall(ns.actions.Context, ns.actions)
    return ok and ctx or nil
end

local function pickCamp(ctx)
    if not (campGet and ctx) then return nil end
    local ok, s = pcall(campGet, ctx)
    return ok and s or nil
end

-- The next buff item, a fight near or not (BuffItems' ItemStep with preview).
-- The bags are read at most once a second for the preview.
local BI = ns.buffItems
local itemAt, itemCache = -10, nil
local function pickItem(ctx)
    if not ctx then return nil end
    if not (BI and BI.ItemStep) then
        if not itemGet then return nil end
        local ok, s = pcall(itemGet, ctx)
        return ok and s or nil
    end
    local now = GetTime()
    if now - itemAt < 1 then return itemCache end
    itemAt = now
    local ok, s = pcall(BI.ItemStep, ctx, true)
    itemCache = ok and s or nil
    return itemCache
end

-- Fishing (Flow Actions), one press per step: at a fishing step without your
-- pole on, equip it; pole on with no lure, the best lure you carry; line
-- out, reel in (only with a buff key: the key is turned into Interact, a
-- mouse click can't reach the bobber); else cast.
local function pickFish(ctx)
    local X = ns.actions
    if not (ctx and X and X.EquipStep and X.LureStep and X.ReelStep and X.CastStep) then return nil end
    local steps = { X.EquipStep, X.LureStep, (cfg().key or cfg().key2) and X.ReelStep or nil, X.CastStep }
    for i = 1, 4 do
        if steps[i] then
            local ok, s = pcall(steps[i], ctx)
            if ok and s then return s end
        end
    end
end

-- Nothing due: your buff spells and buff items still on, the one running
-- out first (read with the bags, at most once a second).
local upAt, upCache = -10, nil
local function pickUpcoming(spells)
    local now = GetTime()
    if now - upAt >= 1 then
        upAt = now
        local ok, items = pcall(BI and BI.UpcomingItems or function() return {} end)
        upCache = ok and items or {}
    end
    local cands = {}
    for _, c in ipairs(spells or {}) do cands[#cands + 1] = c end
    for _, c in ipairs(upCache or {}) do cands[#cands + 1] = { step = c.step, left = c.left } end
    return BB.Soonest(cands)
end

local function fightNear(ctx)
    if not (BI and BI.FightNear) then return true end   -- can't tell: as before, bright
    local ok, near = pcall(BI.FightNear, ctx)
    return ok and near and true or false
end

-------------------------------------------------------------------------------
-- The button
-------------------------------------------------------------------------------

local btn, tex, label, keyText, modTag, timer, sweep, edge
local shownText          -- what the secure button is set to, to skip repeats
local lastCast           -- the buff spell you last cast (held for fights)
local buffSpells = {}    -- every buff spell this button has shown
local current            -- what it shows now

local function spellTex(spell) return spell and select(2, A.SpellInfo(spell)) end

local function itemId(s) return s and s.item and tonumber(tostring(s.item):match("(%d+)")) end

local function itemTex(id)
    return (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id))
end

local function describe(s)
    if not s then return "" end
    if s.idle then return "nothing due (dim)" end
    if s.type == "sit" or s.type == "wait" or s.type == "interact" then return s.type end
    if s.type == "clear" then return "clear target" end
    if s.spell then return "spell " .. s.spell .. " @" .. tostring(s.unit or "player") end
    return "item " .. tostring(s.item) .. " slot " .. tostring(s.targetSlot) .. (s.unit and (" @" .. s.unit) or "")
end

local function setAction(s)
    if InCombatLockdown() or not btn then return end
    local text = describe(s)
    if text == shownText then return end
    shownText = text
    for _, a in ipairs({ "type", "spell", "item", "unit", "target-slot" }) do btn:SetAttribute(a, nil) end
    if s and (s.type == "sit" or s.type == "wait" or s.type == "interact") then
        -- Sit: the key does it (applyKey binds it to the game's Sit/Stand).
        -- Reel in: the key is the game's Interact (applyKey). Stay sitting:
        -- nothing. In each, a click does nothing.
    elseif s and s.type == "clear" then
        -- The secure "target" type with unit "none" clears your target.
        btn:SetAttribute("type", "target")
        btn:SetAttribute("unit", "none")
    elseif s and s.spell then
        btn:SetAttribute("type", "spell")
        btn:SetAttribute("spell", s.spell)
        btn:SetAttribute("unit", s.unit or "player")
    elseif s and s.item then
        btn:SetAttribute("type", "item")
        btn:SetAttribute("item", s.item)
        btn:SetAttribute("target-slot", s.targetSlot)
        if s.unit then btn:SetAttribute("unit", s.unit) end   -- a bandage: on you
    end
end

-- Its keys: one, or two ("we should support 2 key binds for the buff bar
-- too", 0.35.231), as Flow's own key has. Pure: from its saved settings.
function BB.KeysOf(c)
    local out = {}
    if c and c.key then out[#out + 1] = c.key end
    if c and c.key2 and c.key2 ~= c.key then out[#out + 1] = c.key2 end
    return out
end
function BB.Keys() return BB.KeysOf(cfg()) end
local function keyLabel()
    local short = ns.cast and ns.cast.ShortKey
    local parts = {}
    for _, key in ipairs(BB.Keys()) do
        parts[#parts + 1] = short and short(key, GetBindingText and function(k) return GetBindingText(k, "KEY_", true) end) or key
    end
    return table.concat(parts, " / ")
end

local function paint(s, bright)
    if not btn then return end
    local id = itemId(s)
    local t = s and (s.icon or (s.spell and spellTex(s.spell)) or (id and itemTex(id)))
    tex:SetTexture(t or "Interface\\Icons\\INV_Misc_QuestionMark")
    tex:SetDesaturated(not bright)
    btn:SetAlpha(bright and 1 or 0.55)
    local name = s and ((s.type == "sit" and "Sit by the fire") or (s.type == "wait" and "Stay sitting")
        or s.spell or (id and A.ItemInfo and A.ItemInfo(id)) or s.label) or ""
    if s and s.target then name = name .. " on " .. s.target end
    if s and s.later then name = name .. " (" .. BB.Left(s.left) .. ")" end
    label:SetText(name)
    -- Docked: the held modifier on its own line above the bind ("CTRL +"
    -- over "E / MB4"); on its own: in the bind's place, as before.
    local held = s and s.mod and BB.Docked() and ns.careKeys and ns.careKeys.LABEL[s.mod] or nil
    if modTag then
        modTag:SetText(held and (held .. " +") or "")
        modTag:SetShown(held ~= nil)
    end
    keyText:SetText((not held and s and s.press) or keyLabel())
    -- Its cooldown counted down, and red when its target is out of reach (as
    -- Flow's icon does it).
    local cd, reach = "", true
    if s and s.spell then
        local okC, start, dur = pcall(A.CooldownRaw, s.spell)
        if okC and ns.CooldownText then cd = ns.CooldownText(start, dur, GetTime()) or "" end
        local unit = s.unit
        if unit and unit ~= "player" and A.InRange then
            local okR, inRange = pcall(A.InRange, s.spell, unit)
            if okR then reach = inRange ~= false end
        end
    end
    if timer then timer:SetText(cd) end
    if sweep and s and (s.spell or s.item) and ns.SetCooldownFrame then pcall(ns.SetCooldownFrame, sweep, s)
    elseif sweep then pcall(sweep.SetCooldown, sweep, 0, 0) end
    if reach then tex:SetVertexColor(1, 1, 1) else tex:SetVertexColor(1, 0.3, 0.3) end
end

local function fillTooltip(tt)
    local s = current
    local id = s and s.spell and select(4, A.SpellInfo(s.spell))
    local item = itemId(s)
    if id and tt.SetSpellByID then tt:SetSpellByID(id)
    elseif item and tt.SetItemByID then tt:SetItemByID(item) end
    if id or item then tt:AddLine(" ") end
    tt:AddLine("Flow self button", 1, 0.82, 0)
    if s and s.later then
        tt:AddLine("Next buff to run out: " .. BB.Left(s.left) .. " left.", 0.5, 0.8, 1, true)
    end
    if s and s.faded then
        tt:AddLine("Faded: no fight near yet. It lights up when you're about to fight "
            .. "(an enemy targeted, a kill step, or just after a fight). Press it whenever you like.", 0.5, 0.8, 1, true)
    end
    if s and s.reason then tt:AddLine("Why: " .. s.reason, 1, 1, 1, true) end
    if InCombatLockdown() then
        tt:AddLine("In a fight it holds " .. tostring(s and s.spell or "nothing") .. " (it can't change mid-fight).", 1, 0.6, 0.3, true)
    end
    local key = cfg().key
    tt:AddLine(key and ("Key: " .. ((GetBindingText and GetBindingText(key, "KEY_", true)) or key))
        or "No key yet: /flow buffkey <key>", 0.8, 0.8, 0.8)
    if BB.handle then
        tt:AddLine("Hold Ctrl: drag to move it, turn the mouse wheel to resize it.", 0.6, 0.6, 0.6)
    end
end

-- The same size as Flow's icon (was 40: "make the self button look much like
-- the target button", 0.35.209); its blue edge tells the two apart.
BB.SIZE = 52
-- Docked: joined to Flow's icon, right under it, so the two read as one
-- block ("an option to join or dock buff to easy", 0.35.228). The buff
-- button's icons hang from its top edge, the modifier names sit once
-- between the two rows, and both spell names go below the lot.
BB.DOCK_GAP = 17     -- between the two rows: room for the modifier names (and Flow's edge, round its icon since 0.35.256)
-- (Docked unless you took it off: the default since 0.35.240.)
function BB.DockWanted(saved) return saved ~= false end
function BB.Docked() return BB.DockWanted(cfg().dock) and _G.FlowCastButton ~= nil end
-- Docked, it has a size of its own (0.35.253: "hover the self button and
-- scroll to resize it, independent of the target button"): Ctrl + mouse wheel
-- over it. Until you've set one it's the size of Flow's icon.
-- Pure: saved: your docked size or nil; main: Flow's icon's size.
function BB.DockScale(saved, main)
    local s = tonumber(saved) or tonumber(main) or 1
    return ns.ClampScale and ns.ClampScale(s) or s
end
-- Pure: the size one wheel notch gives (a tenth up or down, within the limits).
function BB.DockScaleStep(now, delta)
    local step = ns.SCALE_STEP or 0.1
    local s = (tonumber(now) or 1) + (delta > 0 and step or -step)
    return ns.ClampScale and ns.ClampScale(s) or s
end
-- One wheel notch over the docked button. true: done here.
function BB.DockWheel(delta)
    if not BB.Docked() or not btn or InCombatLockdown() then return false end
    cfg().dockScale = BB.DockScaleStep(btn:GetScale(), delta)
    BB.Place()
    return true
end
-- Puts the button where it belongs: docked, where you left it, or (never
-- moved) just left of the Flow button. Out of a fight only.
function BB.Place()
    if not btn or InCombatLockdown() then return false end
    local main = _G.FlowCastButton
    btn:ClearAllPoints()
    if label then label:ClearAllPoints() end
    if keyText then keyText:ClearAllPoints() end
    if BB.Docked() then
        btn:SetScale(BB.DockScale(cfg().dockScale, main:GetScale()))
        btn:SetPoint("TOP", main, "BOTTOM", 0, -BB.DOCK_GAP)
        -- Docked: its name under it from its left edge, its key at its top
        -- right (Flow's own key is at Flow's bottom right: the two sit together
        -- beside the gap). Only in this mode: on its own it's as it always was.
        -- (Mirrored when the small icons run to the right: 0.35.324.)
        local right = ns.SelfSide and ns.SelfSide() == "right"
        BB.placedSide = right and "right" or "left"
        if label then
            if right then label:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -2) else label:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2) end
            label:SetJustifyH(right and "RIGHT" or "LEFT")
            label:SetWidth(170)
        end
        if keyText then
            if right then keyText:SetPoint("RIGHT", btn, "LEFT", -6, 0) else keyText:SetPoint("LEFT", btn, "RIGHT", 6, 0) end
        end
        return true
    end
    if label then
        label:SetPoint("TOP", btn, "BOTTOM", 0, -3)
        label:SetJustifyH("CENTER")
        label:SetWidth(110)
    end
    if keyText then keyText:SetPoint("BOTTOM", btn, "TOP", 0, 2) end
    if ns.RestorePlace and (cfg().point or not main) then
        ns.RestorePlace(btn, cfg(), -60, -160)
    elseif main then
        if ns.ClampScale then btn:SetScale(ns.ClampScale(cfg().scale or 1)) end
        btn:SetPoint("RIGHT", main, "LEFT", -12, 0)
    else
        btn:SetPoint("CENTER", UIParent, "CENTER", -60, -160)
    end
    return true
end
function BB.SetDock(on)
    if InCombatLockdown() then return false end
    cfg().dock = on and true or false
    BB.Place()
    if ns.careKeys and ns.careKeys.Apply then pcall(ns.careKeys.Apply) end
    return true
end
function BB.Shown() return btn ~= nil and btn:IsShown() end

local function build()
    btn = CreateFrame("Button", "FlowBuffButton", UIParent, "SecureActionButtonTemplate")
    btn:SetSize(BB.SIZE, BB.SIZE)
    btn:SetFrameStrata("MEDIUM")   -- (under the game's own windows: the game menu, Settings; 0.35.163)
    -- (Placed at the end, once its texts exist: BB.Place.)
    btn:RegisterForClicks("AnyUp", "AnyDown")
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    local e = ns.ICON_EDGE or 3   -- (the same edge as round Flow's icon)
    bg:SetPoint("TOPLEFT", -e, e); bg:SetPoint("BOTTOMRIGHT", e, -e)
    bg:SetColorTexture(0.1, 0.6, 1, 0.9)   -- blue edge: the self button
    edge = bg
    tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetWidth(110)
    label:SetTextColor(0.5, 0.8, 1)
    -- Its key above it, as on Flow's icon (same font and size).
    keyText = btn:CreateFontString(nil, "OVERLAY")
    keyText:SetFont(STANDARD_TEXT_FONT, (ns.cast and ns.cast.KEY_FONT) or 11, "OUTLINE")
    keyText:SetPoint("BOTTOM", btn, "TOP", 0, 2)   -- (BB.Place puts it at the top right when docked)
    modTag = btn:CreateFontString(nil, "OVERLAY")
    modTag:SetFont(STANDARD_TEXT_FONT, (ns.cast and ns.cast.KEY_FONT) or 11, "OUTLINE")
    modTag:SetPoint("BOTTOMLEFT", keyText, "TOPLEFT", 0, 2)
    modTag:SetTextColor(0.4, 1, 0.4)
    modTag:Hide()
    BB._keyText, BB._modTag = keyText, modTag   -- (tests)
    -- The global cooldown and its spell's own, swept over the icon as on Flow's.
    sweep = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    sweep:SetAllPoints()
    if sweep.SetHideCountdownNumbers then sweep:SetHideCountdownNumbers(true) end
    -- Its spell's cooldown, counted down on the icon as on Flow's (0.35.228).
    timer = btn:CreateFontString(nil, "OVERLAY")
    timer:SetFont(STANDARD_TEXT_FONT, 18, "THICKOUTLINE")
    timer:SetPoint("CENTER", 0, 0)
    timer:SetTextColor(1, 0.95, 0.7)
    BB.Place()
    btn:SetScript("OnEnter", function(self)
        ns.Tip(self, "ANCHOR_LEFT")
        pcall(fillTooltip, GameTooltip)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- A step's own work before the press (the pole: remember your weapons,
    -- so they go back on when you leave), as on the Flow key.
    btn:HookScript("PreClick", function()
        if current and current.before and not InCombatLockdown() then pcall(current.before) end
    end)
    btn:HookScript("PostClick", function(self, _, down)
        if down == false then return end
        -- (A cast from it is Flow's suggestion, not a choice of yours: Cast.lua.)
        if current and ns.cast and ns.cast.NotePress then ns.cast.NotePress(current.spell) end
        -- By mouse (the pointer is on it) or by its key: counted, and said in the log.
        local mouse = self:IsMouseOver() and true or false
        if mouse then BB.byMouse = (BB.byMouse or 0) + 1 else BB.byKey = (BB.byKey or 0) + 1 end
        if current and not current.idle and not InCombatLockdown() then
            ns:Log("action", "self button pressed" .. (mouse and " (mouse)" or "") .. ": " .. describe(current))
        end
    end)
    -- Ctrl: drag to move, mouse wheel to resize. Same as the Flow button.
    -- (Docked it goes where Flow's icon goes: dragging it drags Flow's button,
    -- and the two move as one (0.35.315: "when they're docked, it doesn't
    -- seem to move them"); its wheel resizes it alone, and the one note under
    -- both is Flow's.)
    if ns.MoveHandle then BB.handle = ns:MoveHandle(btn, { name = "the self button", save = cfg,
        fixed = function() return BB.Docked() end, quiet = function() return BB.Docked() end,
        dragVia = function() return BB.Docked() and ns.cast and ns.cast.handle or nil end,
        wheel = function(delta) return BB.DockWheel(delta) end }) end
    btn:Hide()
end

-------------------------------------------------------------------------------
-- Why a click on the self button might not cast (0.35.291)
-------------------------------------------------------------------------------
-- "Clicking on the self button doesn't cast it." Its key works (the log has
-- the presses), so either something lies over the button and takes the
-- click, or the click arrives and the game doesn't act on it. The log now
-- says whether a press came by mouse, and /flow selfbutton why (also in the
-- diagnostics) lists every frame that takes clicks and lies over the button.

-- Pure: do two rectangles ({ left, bottom, width, height }, screen units) overlap?
function BB.Overlaps(a, b)
    if not (a and b and a[1] and b[1] and a[3] and b[3]) then return false end
    return a[1] < b[1] + b[3] and b[1] < a[1] + a[3] and a[2] < b[2] + b[4] and b[2] < a[2] + a[4]
end
-- Pure: is a frame at this strata and level drawn over one at that?
BB.STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
function BB.Above(strataA, levelA, strataB, levelB)
    local a, b = BB.STRATA[strataA or ""] or 0, BB.STRATA[strataB or ""] or 0
    if a ~= b then return a > b end
    return (levelA or 0) > (levelB or 0)
end
-- Every value read from another add-on's or the game's frame is unwrapped
-- first (ns.api.Safe: nil when the game hides it). Testing a hidden one was
-- blocked and logged "taint from Flow" each time this looked (0.35.315).
local function safe(v) return ns.api.Safe(v) end
local function rectOf(f)
    local ok, l, b, w, h = pcall(f.GetRect, f)
    if not ok then return nil end
    l, b, w, h = safe(l), safe(b), safe(w), safe(h)
    if not (l and b and w and h) then return nil end
    local s = safe(f:GetEffectiveScale()) or 1
    return { l * s, b * s, w * s, h * s }
end
local function nameOf(f)
    local n = f.GetName and safe(f:GetName())
    if n then return n end
    local p = f.GetParent and f:GetParent()
    local pn = p and p.GetName and safe(p:GetName())
    return pn and ("a child of " .. pn) or "an unnamed frame"
end
-- The frames that take clicks, are on screen and lie over the button.
function BB.Covering()
    local out = {}
    if not (btn and btn:IsVisible() and EnumerateFrames) then return out end
    local mine = rectOf(btn)
    if not mine then return out end
    local strata, level = btn:GetFrameStrata(), btn:GetFrameLevel()
    local f = EnumerateFrames()
    local seen = 0
    while f and seen < 20000 do
        seen = seen + 1
        local ok, hit = pcall(function()
            if f == btn or (f.IsForbidden and safe(f:IsForbidden()) ~= false) then return false end
            if not (safe(f:IsVisible()) and safe(f:IsMouseEnabled())) then return false end
            if not BB.Above(safe(f:GetFrameStrata()), safe(f:GetFrameLevel()), strata, level) then return false end
            return BB.Overlaps(rectOf(f), mine)
        end)
        if ok and hit then out[#out + 1] = nameOf(f) .. " (" .. tostring(safe(f:GetFrameStrata())) .. " " .. tostring(safe(f:GetFrameLevel())) .. ")" end
        f = EnumerateFrames(f)
    end
    return out
end
-- look: also look for frames over the button (it reads every frame in the
-- game: only when you ask, /flow selfbutton why; the diagnostics don't).
function BB.WhyLines(look)
    local out = {}
    if not btn then return { "self button: not built (it's off)" } end
    out[#out + 1] = string.format("self button: %s; shown: %s; takes clicks: %s; at %s level %d; scale %.2f",
        BB.On() and "on" or "off", tostring(btn:IsShown()), tostring(btn:IsMouseEnabled()),
        tostring(btn:GetFrameStrata()), btn:GetFrameLevel(), btn:GetScale())
    out[#out + 1] = string.format("  set to cast: type %s, spell %s, item %s, on %s", tostring(btn:GetAttribute("type")),
        tostring(btn:GetAttribute("spell")), tostring(btn:GetAttribute("item")), tostring(btn:GetAttribute("unit")))
    out[#out + 1] = string.format("  presses this session: %d by mouse, %d by key", BB.byMouse or 0, BB.byKey or 0)
    if look then
        local okC, list = pcall(BB.Covering)
        if okC then BB.lastCover, BB.lastCoverAt = list, date("%H:%M:%S") end
        if okC and #list > 0 then
            out[#out + 1] = "  OVER IT (these take the click before it does): " .. table.concat(list, "; ")
        else
            out[#out + 1] = "  nothing that takes clicks lies over it" .. (btn:IsVisible() and "" or " (it isn't on screen now, so this can't be checked)")
        end
    end
    if BB.lastCover then
        out[#out + 1] = string.format("  while it was on screen at %s: %s", tostring(BB.lastCoverAt),
            #BB.lastCover > 0 and ("OVER IT: " .. table.concat(BB.lastCover, "; ")) or "nothing over it")
    end
    out[#out + 1] = "  cast on key down: " .. tostring(GetCVar and GetCVar("ActionButtonUseKeyDown"))
    return out
end

-- Key: an override binding, like Flow's own key (your bindings never change).
-- While your fishing line is out (keyInteract), the key is the game's
-- Interact instead, which reels in the bobber.
local owner = CreateFrame("Frame")
local pendingKey = false
local keyInteract = false
local function applyKey()
    if InCombatLockdown() then pendingKey = true return end
    pendingKey = false
    ClearOverrideBindings(owner)
    for _, key in ipairs(BB.On() and BB.Keys() or {}) do
        -- By a campfire with sitting the step: the key is the game's own
        -- Sit/Stand (as Flow's key does it); reeling in: the game's Interact;
        -- else it clicks this button.
        if BB.sitting then SetOverrideBinding(owner, true, key, "SITORSTAND")
        elseif keyInteract then SetOverrideBinding(owner, true, key, "INTERACTTARGET")
        else SetOverrideBindingClick(owner, true, key, "FlowBuffButton", "LeftButton") end
    end
    if keyText then keyText:SetText(keyLabel()) end
end
local function setKeyInteract(on)
    on = on and true or false
    if on == keyInteract then return end
    keyInteract = on
    applyKey()
end
-- Back to a click before a fight (bindings can't change during one).
ns:On("PLAYER_REGEN_DISABLED", function()
    if BB.sitting or keyInteract then BB.sitting, keyInteract = false, false; applyKey() end
end)

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
    -- A modifier held: the icon becomes what that press casts ("holding
    -- modifiers should update the self button as well", 0.35.228).
    local heldStep = ns.careKeys and ns.careKeys.HeldStep and ns.careKeys.HeldStep() or nil
    if heldStep and btn:IsShown() then
        paint(heldStep, true)
        return
    end
    local live = fresh()
    if live and live.spell then buffSpells[live.spell] = true end
    if InCombatLockdown() then
        -- The button holds what it was set to at the pull; bright when the
        -- rotation wants that spell again.
        local held = btn:GetAttribute("spell")
        current = held and { spell = held, reason = live and live.reason } or nil
        -- (Bright too while Flow wants a heal and this key heals: CareKeys.lua.)
        local wanted = ns.careKeys and ns.careKeys.HealWanted and ns.careKeys.HealWanted() or false
        if current then paint(current, (live and live.spell == held) or wanted) end
        -- Flow wants a heal and this key casts it: its edge takes the
        -- suggestion's orange, on the beat (Pulse.lua); else its own blue.
        if wanted ~= BB.wanted then
            BB.wanted = wanted
            if wanted then
                local c = ns.pulse.COLOR
                edge:SetColorTexture(c[1], c[2], c[3], 1)
                ns.pulse.Add(edge)
            else
                ns.pulse.Remove(edge)
                edge:SetColorTexture(0.1, 0.6, 1, 0.9)
            end
        end
        return
    end
    local ctx = actionCtx()
    -- (Out of a fight: its edge is its own blue again.)
    if BB.wanted then
        BB.wanted = false
        ns.pulse.Remove(edge)
        edge:SetColorTexture(0.1, 0.6, 1, 0.9)
    end
    local recover, camp = GetTime() - liveAt < 1 and BB.MineFirst(liveCure, liveRecover) or nil, BB.TakesCamp() and pickCamp(ctx) or nil
    local s = BB.Pick(live, pickItem(ctx), recover, camp, pickFish(ctx))
    -- Nothing due ("I don't want my self button always showing buffs: like the
    -- target button, if I need it show it, else what fits my target", 0.35.208):
    -- with an enemy targeted and heals on this key, your heal, ready; else the
    -- button goes away until something is due. "Always show my next buff"
    -- (Flow Settings) brings back the buff that runs out first.
    if not s then
        local K = ns.careKeys
        local ctxR = E.lastCtx
        local heal = K and K.Active() and K.plan and K.plan.key or nil
        local what = BB.WhenIdle(cfg().always == true, heal ~= nil and ctxR ~= nil and ctxR.hostile == true)
        if what == "next" then
            s = pickUpcoming(GetTime() - liveAt < 1 and liveNext or nil)
        elseif what == "heal" then
            s = { spell = heal.spell, unit = "player", kind = "heal", standby = true,
                  reason = "Nothing to buff: your heal, ready for this fight. Shift, Ctrl, Alt and Ctrl + Shift with this key: the icons beside it." }
        else
            current = nil
            setAction(nil)
            if BB.sitting then BB.sitting = false; applyKey() end
            setKeyInteract(false)
            if btn:IsShown() then btn:Hide() end
            return
        end
    end
    current = s or BB.Idle()
    current.faded = s ~= nil and not BB.Bright(s, fightNear(ctx)) or nil
    setAction(s)
    local sit = s and s.type == "sit" or false
    if sit ~= (BB.sitting or false) then BB.sitting = sit; applyKey() end
    setKeyInteract(s and s.type == "interact")
    paint(current, s ~= nil and not current.faded)
    if not btn:IsShown() then btn:Show() end
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
    setKeyInteract(false)   -- the key clicks the button again for the fight
    -- With a key of its own and heals on it (CareKeys.lua): in a fight the
    -- key is your quickest heal; else the buff due, as before.
    local care = ns.careKeys and ns.careKeys.FightKey and ns.careKeys.FightKey()
    local spell = care or BB.FightSpell(fresh(), lastCast)
    if spell and E:Knows(spell) then
        setAction({ spell = spell, unit = "player" })
        if not btn:IsShown() then btn:Show() end
    else
        setAction(nil)
        if btn:IsShown() then btn:Hide() end
    end
end)

ns:On("BAG_UPDATE_DELAYED", function() itemAt, upAt = -10, -10 end)

ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit ~= "player" then return end
    itemAt, upAt = -10, -10   -- a stone, oil or food just used: look at the bags again now
    local name = A.SpellInfo(A.Safe(spellID) or 0)
    if name and buffSpells[name] then lastCast = name end
    -- A group buff cast from here: remember it, as Engine.lua does for the
    -- main key (it only records what's on the main icon). Where the game
    -- hides party auras, "Blessing of Might on Bob" stayed lit after casting.
    if name and current and current.spell == name and current.guid then
        E.buffMemory[current.guid] = E.buffMemory[current.guid] or {}
        E.buffMemory[current.guid][name] = GetTime()
    end
end)

-------------------------------------------------------------------------------
-- Options and commands
-------------------------------------------------------------------------------

function BB.Set(on)
    cfg().enabled = on and true or false
    applyKey()
end
-- Its key, set from Flow Settings and the Flow menu (nil clears it). Giving
-- it a key turns the button on: a key for a button that's off does nothing.
function BB.Key(slot) if slot == 2 then return cfg().key2 end return cfg().key end
function BB.SetKey(key, slot)
    if InCombatLockdown() then return false end
    if slot == 2 then cfg().key2 = key else cfg().key = key end
    if key then cfg().enabled = true end
    applyKey()
    return true
end

-- Options > AddOns > Flow, under "Flow".
if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck({
        group = "key",
        label = "Self button beside Flow's icon",
        note = "(own key: /flow buffkey <key>)",
        tip = "Your buffs (auras, aspects, blessings, party buffs), weapon stones and oils, your bandage and "
            .. "food after a fight, and the campfire steps (place, sit) go on a "
            .. "separate blue button left of Flow's icon, so Flow's key only does your fight: damage, heals, "
            .. "cleanses, plus seals, shouts, shields and Hunter's Mark. Out of combat it's always there and "
            .. "shows your next buff (the one due, else the one running out first, with its time left), all of "
            .. "it faded until a fight is near (an enemy targeted, a kill step, just after "
            .. "a fight), so you can use it when you choose (hover it for why). Give it its own key with /flow buffkey Q. In a fight "
            .. "it keeps the buff you last cast from it and lights up when that buff runs out. Off: all of it "
            .. "goes back on Flow's icon and key.",
        get = function() return BB.On() end,
        set = function(on) BB.Set(on) end,
    })
end

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck({
        group = "key",
        label = "Self button always shows my next buff",
        note = "(off: only when something is due)",
        tip = "Off: the self button shows up when a buff, a stone, a bandage or food is due, and with an enemy targeted it "
            .. "shows your heal; otherwise it stays away, like Flow's icon. On: it is always there, with the buff that runs out first and its time left.",
        get = function() return cfg().always == true end,
        set = function(on) cfg().always = on and true or nil end,
    })
end

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck({
        group = "key",
        label = "Dock the self button under the Flow icon",
        note = "(the two as one block)",
        tip = "The self button sits right under Flow's icon, its little icons under Flow's, with Shift, Ctrl, Alt and C+S written once between the two rows. Off: it stands where you put it.",
        get = function() return BB.DockWanted(cfg().dock) end,
        set = function(on) BB.SetDock(on) end,
    })
end

ns.commands.buffbutton = function(arg)
    local why = (arg or ""):lower():match("^why%s*(%a*)$")
    if why then
        -- ("why quick", the diagnostics: without the look over every frame.)
        for i, l in ipairs(BB.WhyLines(why ~= "quick")) do if i == 1 then ns:Print(l) else print(l) end end
        return
    end
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then BB.Set(arg == "on") end
    ns:Print("self button: " .. (BB.On() and "on" or "off") .. " (/flow buffbutton on|off)")
    print("  key: " .. (cfg().key or "none (/flow buffkey <key>)"))
    print("  shows now: " .. (current and describe(current) or "nothing"))
    print("  held for fights: " .. tostring(lastCast or "nothing cast from it yet"))
end

ns.commands.buffkey = function(arg)
    arg = (arg or ""):gsub("%s+", ""):upper()
    if arg == "" then
        ns:Print("self button key: " .. (cfg().key or "none") .. "  (/flow buffkey Q sets it, /flow buffkey off clears it)")
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
            ns:Print(string.format("note: %s also did %s; while Flow's self button has it, it presses the self button.",
                arg, _G["BINDING_NAME_" .. other] or other))
        end
    end
    applyKey()
    ns:Print("self button key: " .. (cfg().key or "none"))
end

-- /flow buffkey2 <KEY>: a second key for the self button (off: clear it).
-- Flow Settings has the same, with what the key already does.
ns.commands.buffkey2 = function(arg)
    arg = (arg or ""):gsub("%s+", ""):upper()
    if arg == "" then
        ns:Print("self button's second key: " .. (cfg().key2 or "none") .. "  (/flow buffkey2 R sets it, /flow buffkey2 off clears it)")
        return
    end
    if InCombatLockdown() then ns:Print("key bindings can't change in a fight") return end
    if arg == "OFF" then
        BB.SetKey(nil, 2)
    else
        for _, k in ipairs(ns.cast and ns.cast.KeysOf and ns.cast.KeysOf(ns.db.cast) or {}) do
            if k == arg then ns:Print(arg .. " is already Flow's main key: pick another") return end
        end
        BB.SetKey(arg, 2)
    end
    ns:Print("self button's second key: " .. (cfg().key2 or "none"))
end

-- The button's new name (0.35.278: "the target and self buttons"): the same
-- commands under it. The old ones still work.
ns.commands.selfbutton = ns.commands.buffbutton
ns.commands.selfkey = ns.commands.buffkey
ns.commands.selfkey2 = ns.commands.buffkey2

-- (Until 0.35.315 Flow also looked over every frame in the game every half
-- minute, for the diagnostics. Reading other frames' hidden values was
-- logged as taint from Flow each time: now only when you ask.)

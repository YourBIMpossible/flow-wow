-- Buff button: a second button, left of Flow's icon, for your buffs and weapon
-- enhancements, so the main icon and key are only ever your fight (damage,
-- heals, dispels, Flow Actions) and the two never get mixed up.
--
--   Out of combat it shows a stone, weightstone, oil or buff item first
--   (BuffItems.lua's "buff:item": a 3 s use that can't go on in a fight), then
--   the rotation's "buff" suggestions (auras, aspects, blessings, group buffs).
--   Seals, shouts, shields, Hunter's Mark and fight forms stay on Flow's icon
--   with the fight (BB.OnAction). Before all of those, hurt after a fight:
--   your bandage or food; after them, by a campfire: place your camp objects
--   and sit. So Flow's key keeps to the fight, loot and gathering. It always
--   shows the next buff: the one due, else the one of yours (spell, stone,
--   Well Fed, elixir) that runs out first, with its time left. All of it,
--   bandage and campfire included, stays faded until a fight is near (an
--   enemy targeted, a kill stop, just after a fight), so you use it when you
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

-- Buffs that stay on Flow's icon and key because they're part of the fight,
-- pressed with the rest of it: a paladin's seal (Judgement needs one up),
-- shouts, shields (Lightning Shield, Power Word: Shield), Hunter's Mark, and
-- a druid's fight form (Bear, Cat, Moonkin) when the rotation asks you to
-- shift for the fight. Auras, aspects, blessings, Mark of the Wild and Travel
-- Form go on the buff button.
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
-- Not Well Fed and carrying the food for it: that food beats the bandage. One
-- meal heals you and buffs you; bandaging first would waste the bandage.
-- Fishing (at a fishing stop without your pole on, or your pole on with no
-- lure): equip the pole / put on the lure, right after healing up.
function BB.Pick(spellBuff, itemBuff, recover, camp, fish)
    if fish then return recover or fish end
    if itemBuff and itemBuff.wellFed and recover then return itemBuff end
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

-- What the button shows when nothing is due (dim, does nothing).
function BB.Idle()
    return { idle = true, label = "no buffs due", reason = "Nothing to buff right now." }
end

-------------------------------------------------------------------------------
-- The rotation without its buffs; the buffs on their own
-------------------------------------------------------------------------------

local liveBuff, liveAt = nil, 0   -- the rotation's buff suggestion, and when it was worked out
local liveRecover                 -- hurt after a fight: the bandage or food to use (same moment)
local liveNext                    -- your buffs still on, with their time left (same moment)

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
    if E.GroupBuff then
        local ok, g = pcall(E.GroupBuff, E, ctx, def)
        if ok and g then return g end
    end
end

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

local function noGroupBuff() return nil end

-- While the button is on, the rotation chooses from its lists without the
-- buffs (and without group buffs); what it would have buffed is worked out
-- beside it, for this button. The definition is put back whatever happens.
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
        local okR, rec = pcall(self.Recover, self, ctx, def, "items")
        liveRecover = okR and rec or nil
        local okN, on = pcall(onSpells, def, ctx)
        liveNext = okN and on or nil
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

-- The campfire steps (place your camp objects, sit, wait) leave it too.
local campGet
do
    local a = ns:Get("action", "buff:camp")
    if a and a.get then
        campGet = a.get
        a.get = function(ctx)
            if BB.On() then return nil end
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

-- Fishing (Flow Actions): at a fishing stop without your pole on, equip it;
-- your pole on with no lure, the best lure you carry.
local function pickFish(ctx)
    local X = ns.actions
    if not (ctx and X and X.EquipStep and X.LureStep) then return nil end
    local ok, s = pcall(X.EquipStep, ctx)
    if ok and s then return s end
    ok, s = pcall(X.LureStep, ctx)
    return ok and s or nil
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

local btn, tex, label, keyText
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
    if s.type == "sit" or s.type == "wait" then return s.type end
    if s.spell then return "spell " .. s.spell .. " @" .. tostring(s.unit or "player") end
    return "item " .. tostring(s.item) .. " slot " .. tostring(s.targetSlot) .. (s.unit and (" @" .. s.unit) or "")
end

local function setAction(s)
    if InCombatLockdown() or not btn then return end
    local text = describe(s)
    if text == shownText then return end
    shownText = text
    for _, a in ipairs({ "type", "spell", "item", "unit", "target-slot", "macrotext" }) do btn:SetAttribute(a, nil) end
    if s and s.type == "sit" then
        btn:SetAttribute("type", "macro")
        btn:SetAttribute("macrotext", "/sit")
    elseif s and s.type == "wait" then
        -- Stay sitting: pressing it does nothing.
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

local function keyLabel()
    local key = cfg().key
    if not key then return "" end
    local short = ns.cast and ns.cast.ShortKey
    return short and short(key, GetBindingText and function(k) return GetBindingText(k, "KEY_", true) end) or key
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
    if s and s.later then
        tt:AddLine("Next buff to run out: " .. BB.Left(s.left) .. " left.", 0.5, 0.8, 1, true)
    end
    if s and s.faded then
        tt:AddLine("Faded: no fight near yet. It lights up when you're about to fight "
            .. "(an enemy targeted, a kill stop, or just after a fight). Press it whenever you like.", 0.5, 0.8, 1, true)
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

local function build()
    btn = CreateFrame("Button", "FlowBuffButton", UIParent, "SecureActionButtonTemplate")
    btn:SetSize(40, 40)
    btn:SetFrameStrata("HIGH")
    -- Where you left it, or (never moved) just left of the Flow button.
    local main = _G.FlowCastButton
    if ns.RestorePlace and (cfg().point or not main) then
        ns.RestorePlace(btn, cfg(), -60, -160)
    elseif main then
        if ns.ClampScale then btn:SetScale(ns.ClampScale(cfg().scale or 1)) end
        btn:SetPoint("RIGHT", main, "LEFT", -12, 0)
    else
        btn:SetPoint("CENTER", UIParent, "CENTER", -60, -160)
    end
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
    -- A step's own work before the press (the pole: remember your weapons,
    -- so they go back on when you leave), as on the Flow key.
    btn:HookScript("PreClick", function()
        if current and current.before and not InCombatLockdown() then pcall(current.before) end
    end)
    btn:HookScript("PostClick", function(_, _, down)
        if down ~= false and current and not current.idle and not InCombatLockdown() then
            ns:Log("action", "buff button pressed: " .. describe(current))
        end
    end)
    -- Ctrl: drag to move, mouse wheel to resize. Same as the Flow button.
    if ns.MoveHandle then BB.handle = ns:MoveHandle(btn, { name = "the buff button", save = cfg }) end
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
    local ctx = actionCtx()
    local recover, camp = GetTime() - liveAt < 1 and liveRecover or nil, pickCamp(ctx)
    local s = BB.Pick(live, pickItem(ctx), recover, camp, pickFish(ctx))
        or pickUpcoming(GetTime() - liveAt < 1 and liveNext or nil)
    current = s or BB.Idle()
    current.faded = s ~= nil and not BB.Bright(s, fightNear(ctx)) or nil
    setAction(s)
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
    local spell = BB.FightSpell(fresh(), lastCast)
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

-- Options > AddOns > Flow, under "Flow".
if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck({
        label = "Buff button beside Flow's icon",
        note = "(own key: /flow buffkey <key>)",
        tip = "Your buffs (auras, aspects, blessings, party buffs), weapon stones and oils, your bandage and "
            .. "food after a fight, and the campfire steps (place, sit) go on a "
            .. "separate blue button left of Flow's icon, so Flow's key only does your fight: damage, heals, "
            .. "cleanses, plus seals, shouts, shields and Hunter's Mark. Out of combat it's always there and "
            .. "shows your next buff (the one due, else the one running out first, with its time left), all of "
            .. "it faded until a fight is near (an enemy targeted, a kill stop, just after "
            .. "a fight), so you can use it when you choose (hover it for why). Give it its own key with /flow buffkey Q. In a fight "
            .. "it keeps the buff you last cast from it and lights up when that buff runs out. Off: all of it "
            .. "goes back on Flow's icon and key.",
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

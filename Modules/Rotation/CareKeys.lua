-- The second key: heals and potions, with modifiers of their own.
--
-- "Perhaps we should have two target buttons, two key binds: one is heals and
-- pots, the other is attacks. If both had their hotkey with all their
-- modifiers we can fit quite a few things: ten different casts." (0.35.206)
--
-- Flow already has a second button with its own key: the self button
-- (BuffButton.lua, a contributor's: `/flow buffbutton on`, `/flow buffkey
-- <key>`). This file gives that key the same four modifiers Flow's key has,
-- for looking after yourself:
--
--   the key      out of a fight: your next buff, bandage or food, as before;
--                in a fight: your quickest heal, on you
--   SHIFT        your other heal (Healing Touch: the big, slow one)
--   CTRL         your heal over time (Rejuvenation)
--   ALT          your healthstone or healing potion
--   C+S          your best bandage; without one, your cure (Cure Poison...)
--
-- All set before the pull, like Flow's key: the game lets nothing change in
-- a fight. Little icons left of the self button show what each press casts.
-- Flow's own key is untouched (Shift + key still heals, Alt is still your
-- potion): the same heal on both keys does no harm, and nothing you're used
-- to moves. Freeing those two presses of Flow's key for attacks is the next
-- step, once this has been played.
--
-- "Heals and potions on the self button's key" (Flow Settings, Your easy
-- key) turns it off. /flow carekeys says what each press is set to.

local _, ns = ...
local A, E = ns.api, ns.rotation
local BB = ns.buffButton
if not (A and E and BB) then return end

local K = {}
ns.careKeys = K

K.SLOTS = { "shift", "ctrl", "alt", "more" }   -- (the order of the icons, as beside Flow's own: Shift nearest, 0.35.227)
K.MODS = { shift = { "SHIFT" }, ctrl = { "CTRL" }, alt = { "ALT" }, more = { "CTRL", "SHIFT" } }
K.LABEL = { shift = "SHIFT", ctrl = "CTRL", alt = "ALT", more = "C+S" }
K.NAME = { shift = "Shift", ctrl = "Ctrl", alt = "Alt", more = "Ctrl + Shift" }
K.BUTTON = { shift = "careshift", ctrl = "carectrl", alt = "carealt", more = "caremore" }
-- The icons' sizes, nearest the button first: the same as beside Flow's icon
-- ("make the self button look much like the target button and its additional
-- icons", 0.35.209).
K.SIZES = { 36, 30, 25, 22 }

local function cfg()
    ns.db.buffButton = ns.db.buffButton or {}
    return ns.db.buffButton
end
function K.Wanted() return cfg().care ~= false end
-- On: the self button is on, has a key, and this isn't switched off.
function K.Active() return BB.On() and #BB.Keys() > 0 and K.Wanted() end

-- The heal and the potion have left Flow's own key (0.35.207: "yes, move
-- them"): Shift + Flow's key and Alt + Flow's key are attacks, and looking
-- after yourself is this key's. Only while this key is active; "Flow's key
-- keeps its heal and potion" in Flow Settings puts them back on both.
function K.Moved() return K.Active() and cfg().keepOnMain ~= true end

-- Pure: the key with a slot's modifiers, in the game's order.
--   K.KeyFor("E", "more") -> "CTRL-SHIFT-E"; a key that already uses one: nil.
function K.KeyFor(key, slot, modKey)
    modKey = modKey or (ns.cast and ns.cast.ModKey)
    if not modKey then return nil end
    for _, mod in ipairs(K.MODS[slot] or {}) do
        key = key and modKey(key, mod)
    end
    return key
end

-- Pure: what each press casts.
--   o.quick      your quickest heal (what Shift + Flow's key casts)
--   o.heals      your heals you know, in the class's order
--   o.hots       your heals over time you know
--   o.emergency  "item:123": healthstone or healing potion (nil: none)
--   o.bandage    "item:123": your best bandage (nil: none)
--   o.cures      your cures you know (Cure Poison, Remove Curse...)
-- -> { key, shift, ctrl, alt, more }: each a step or nil.
function K.Plan(o)
    o = o or {}
    local function heal(spell, why) return spell and { spell = spell, kind = "heal", unit = "player", reason = why } or nil end
    local plan = { key = heal(o.quick, "Your quickest heal, on you") }
    local used = {}
    if o.quick then used[o.quick] = true end
    for _, hot in ipairs(o.hots or {}) do
        if not used[hot] then
            plan.ctrl = heal(hot, "Your heal over time, on you")
            used[hot] = true
            break
        end
    end
    for _, spell in ipairs(o.heals or {}) do
        if not used[spell] then
            plan.shift = heal(spell, "Your other heal, on you")
            used[spell] = true
            break
        end
    end
    if o.emergency then
        plan.alt = { item = o.emergency, kind = "emergency", reason = "Your healthstone or healing potion" }
    end
    if o.bandage then
        plan.more = { item = o.bandage, kind = "bandage", unit = "player", reason = "Your best bandage, on you" }
    elseif o.cures and o.cures[1] then
        plan.more = { spell = o.cures[1], kind = "dispel", unit = "player", reason = "Your cure, on you" }
    end
    return plan
end

-- Pure: a step as the secure button's attributes: kind, what, unit.
function K.Attributes(s)
    if not s then return nil end
    if s.item then return "item", s.item, s.unit end
    if s.spell then return "spell", s.spell, s.unit or "player" end
    return nil
end

local lastBandage   -- (a bandage on cooldown isn't offered as a step: keep the last one seen)
function K.Now()
    local def = E:Definition()
    local knows = function(spell) return E:Knows(spell) end
    local C, BI = ns.cast, ns.buffItems
    local heals, hots, cures = {}, {}, {}
    for _, spell in ipairs(def and def.heals or {}) do if knows(spell) then heals[#heals + 1] = spell end end
    for _, spell in ipairs(def and def.hots or {}) do if knows(spell) then hots[#hots + 1] = spell end end
    for _, rule in ipairs(def and def.dispels or {}) do
        if type(rule) == "table" and rule.spell and knows(rule.spell) then cures[#cures + 1] = rule.spell end
    end
    local quick = C and C.HealFor and C.HealFor(def, knows, function(spell) return select(3, A.SpellInfo(spell)) end) or heals[1]
    local emergency
    if BI and BI.EmergencyCarry then
        local ok, it = pcall(BI.EmergencyCarry)
        emergency = ok and it and it.id and ("item:" .. it.id) or nil
    end
    if BI and BI.BandageStep then
        local ok, step = pcall(BI.BandageStep, false)
        if ok and step and step.item then lastBandage = step.item end
    end
    if lastBandage then
        local id = tonumber(tostring(lastBandage):match("(%d+)"))
        if id and (A.Count and A.Count(id) or 0) <= 0 then lastBandage = nil end
    end
    return K.Plan({ quick = quick, heals = heals, hots = hots, emergency = emergency, bandage = lastBandage, cures = cures })
end

-------------------------------------------------------------------------------
-- The secure side: attributes on the self button, bindings on its key
-------------------------------------------------------------------------------
local owner = CreateFrame("Frame")
local slotText, slotStep = {}, {}
local boundKey, boundSet
local icons = {}
K.plan = nil

local function button() return _G.FlowBuffButton end

local function clearSlot(btn, slot)
    for _, a in ipairs({ "type", "spell", "item", "unit" }) do btn:SetAttribute("*" .. a .. "-" .. K.BUTTON[slot], nil) end
end

local function keysText() return K.Active() and table.concat(BB.Keys(), "+") or nil end
local function bind()
    ClearOverrideBindings(owner)
    local set = {}
    -- (Each of the button's keys, one or two, gets the same modifier presses.)
    for _, key in ipairs(K.Active() and BB.Keys() or {}) do
        for _, slot in ipairs(K.SLOTS) do
            local modKey = slotText[slot] and K.KeyFor(key, slot)
            if modKey then
                SetOverrideBindingClick(owner, true, modKey, "FlowBuffButton", K.BUTTON[slot])
                set[#set + 1] = slot
            end
        end
    end
    boundKey, boundSet = keysText(), table.concat(set, ",")
end

local function texOf(s)
    if not s then return nil end
    if s.spell then return select(2, A.SpellInfo(s.spell)) end
    local id = tonumber(tostring(s.item):match("(%d+)"))
    return id and ((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id)))
end
local function nameOf(s)
    if not s then return "nothing" end
    if s.spell then return s.spell end
    local id = tonumber(tostring(s.item):match("(%d+)"))
    return (id and A.ItemInfo and A.ItemInfo(id)) or "your item"
end

-- Pure: where a press's column is, docked: the x of its right edge and of
-- its middle, from the button's left edge (both negative: out to the left).
-- The same steps as the icons beside Flow's own (Display.lua): 10 to the
-- first, 6 between, sizes K.SIZES.
-- (Those are for icons out to the left. Out to the right the same numbers,
-- the other way: K.ColumnEdge and K.ColumnCentre take the side, 0.35.324.)
function K.ColumnEdge(index, side) return side == "right" and -K.ColumnRight(index) or K.ColumnRight(index) end
function K.ColumnCentre(index, side) return side == "right" and -K.ColumnMiddle(index) or K.ColumnMiddle(index) end
function K.ColumnRight(index)
    local x = -10
    for i = 1, index - 1 do x = x - (K.SIZES[i] or K.SIZES[#K.SIZES]) - 6 end
    return x
end
function K.ColumnMiddle(index)
    return K.ColumnRight(index) - (K.SIZES[index] or K.SIZES[#K.SIZES]) / 2
end
-- Docked: SHIFT, CTRL, ALT and C+S written once, between the two rows, one
-- over each column, always all four (they name Flow's presses too).
local dockNames = {}
function K.DockNames(btn, show, side)
    for index, slot in ipairs(K.SLOTS) do
        local fs = dockNames[index]
        if show and not fs then
            fs = btn:CreateFontString(nil, "OVERLAY")
            fs:SetTextColor(0.85, 0.85, 0.85)
            dockNames[index] = fs
        end
        if fs then
            if show then
                local sz = K.SIZES[index] or K.SIZES[#K.SIZES]
                fs:SetFont(STANDARD_TEXT_FONT, math.max(8, math.floor(sz * 0.3)), "OUTLINE")
                fs:SetText(K.LABEL[slot])
                fs:ClearAllPoints()
                fs:SetPoint("BOTTOM", btn, side == "right" and "TOPRIGHT" or "TOPLEFT", K.ColumnCentre(index, side), 2)
                fs:Show()
            else
                fs:Hide()
            end
        end
    end
end
K._dockNames = dockNames   -- (tests)

-- The little icons, left of the self button: what each modifier casts.
local function paint()
    local btn = button()
    if not btn then return end
    local n = 0
    local prevIcon
    local docked = (BB.Docked and BB.Docked()) and true or false
    local side = ns.SelfSide and ns.SelfSide() or "left"
    K.side = side
    local right = side == "right"
    K.DockNames(btn, docked and K.Active(), side)
    for index, slot in ipairs(K.SLOTS) do
        local ic = icons[slot]
        local s = K.Active() and slotStep[slot] or nil
        if s and not ic then
            -- (A button of the game's secure kind, so a click on the icon casts
            -- it: 0.35.227. Set here, which only runs out of a fight.)
            ic = CreateFrame("Button", nil, btn, "SecureActionButtonTemplate")
            ic:RegisterForClicks("AnyUp", "AnyDown")
            ic.hl = ic:CreateTexture(nil, "HIGHLIGHT")
            ic.hl:SetAllPoints()
            ic.hl:SetColorTexture(1, 1, 1, 0.25)
            ic.back = ic:CreateTexture(nil, "BACKGROUND", nil, -1)
            ic.back:SetPoint("TOPLEFT", -1, 1); ic.back:SetPoint("BOTTOMRIGHT", 1, -1)
            ic.back:SetColorTexture(0, 0, 0, 0.85)
            ic.tex = ic:CreateTexture(nil, "ARTWORK")
            ic.tex:SetAllPoints()
            ic.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            -- Its cooldown, in the middle (as on Flow's own small icons).
            ic.timer = ic:CreateFontString(nil, "OVERLAY")
            ic.timer:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
            ic.timer:SetPoint("CENTER")
            if ns.AddCooldown then ns.AddCooldown(ic, ic.timer) end
            ic.label = ic:CreateFontString(nil, "OVERLAY")
            ic.label:SetPoint("BOTTOM", ic, "TOP", 0, 2)
            ic.label:SetTextColor(0.85, 0.85, 0.85)
            ic:EnableMouse(true)
            ic:SetScript("OnEnter", function(self)
                ns.Tip(self, "ANCHOR_LEFT")
                GameTooltip:AddLine(K.NAME[self.slot] .. " + your self button key: " .. nameOf(self.step), 1, 0.82, 0)
                if self.step and self.step.reason then GameTooltip:AddLine(self.step.reason, 1, 1, 1, true) end
                GameTooltip:AddLine("Click the icon to cast it. Set before the pull; it can't change in a fight.", 0.6, 0.6, 0.6, true)
                GameTooltip:Show()
            end)
            ic:SetScript("OnLeave", function() GameTooltip:Hide() end)
            ic.slot = slot
            icons[slot] = ic
        end
        if ic then
            if s then
                n = n + 1
                ic.step = s
                local kind, what, unit = K.Attributes(s)
                local text = tostring(kind) .. ":" .. tostring(what) .. "@" .. tostring(unit)
                if text ~= ic.set then
                    ic.set = text
                    for _, a in ipairs({ "type", "spell", "item", "unit" }) do ic:SetAttribute(a, nil) end
                    ic:SetAttribute("type", kind)
                    ic:SetAttribute(kind, what)
                    ic:SetAttribute("unit", unit)
                end
                ic.tex:SetTexture(texOf(s) or "Interface\\Icons\\INV_Misc_QuestionMark")
                -- (Out to the left, nearest first and biggest, bottoms level: as Flow's icon has them.)
                ic:ClearAllPoints()
                if docked then
                    -- Docked under Flow's icon: each press keeps its own column,
                    -- under Flow's icon for the same modifier, whether or not the
                    -- others have anything on them (0.35.237: with no potion on
                    -- Alt the icons closed up, C+S stood under Flow's Alt, and
                    -- "ALT" was missing from the names). Hung from the top edge;
                    -- the names are written once for all four (K.DockNames).
                    local sz = K.SIZES[index] or K.SIZES[#K.SIZES]
                    ic:SetSize(sz, sz)
                    if right then ic:SetPoint("TOPLEFT", btn, "TOPRIGHT", K.ColumnEdge(index, side), 0)
                    else ic:SetPoint("TOPRIGHT", btn, "TOPLEFT", K.ColumnRight(index), 0) end
                    ic.label:Hide()
                else
                    -- (On its own: out to the left, nearest first and biggest, bottoms level.)
                    local sz = K.SIZES[n] or K.SIZES[#K.SIZES]
                    ic:SetSize(sz, sz)
                    ic.label:SetFont(STANDARD_TEXT_FONT, math.max(8, math.floor(sz * 0.3)), "OUTLINE")
                    ic.label:SetText(K.LABEL[slot])
                    ic.label:Show()
                    if right then
                        if prevIcon then ic:SetPoint("BOTTOMLEFT", prevIcon, "BOTTOMRIGHT", 6, 0)
                        else ic:SetPoint("BOTTOMLEFT", btn, "BOTTOMRIGHT", 10, 0) end
                    elseif prevIcon then ic:SetPoint("BOTTOMRIGHT", prevIcon, "BOTTOMLEFT", -6, 0)
                    else ic:SetPoint("BOTTOMRIGHT", btn, "BOTTOMLEFT", -10, 0) end
                end
                prevIcon = ic
                ic:Show()
            else
                ic:Hide()
            end
        end
    end
end

-- Sets the four presses. Out of a fight (and in the last moment before one).
function K.Apply()
    local btn = button()
    if InCombatLockdown() or not btn then return false end
    local plan = K.Active() and K.Now() or {}
    K.plan = plan
    local changed = false
    for _, slot in ipairs(K.SLOTS) do
        local kind, what, unit = K.Attributes(plan[slot])
        local text = kind and (kind .. ":" .. tostring(what) .. "@" .. tostring(unit)) or nil
        if text ~= slotText[slot] then
            clearSlot(btn, slot)
            if kind then
                btn:SetAttribute("*type-" .. K.BUTTON[slot], kind)
                btn:SetAttribute("*" .. kind .. "-" .. K.BUTTON[slot], what)
                btn:SetAttribute("*unit-" .. K.BUTTON[slot], unit)
            end
            if (slotText[slot] ~= nil) ~= (text ~= nil) then changed = true end
            slotText[slot] = text
        end
        slotStep[slot] = kind and plan[slot] or nil
    end
    if changed or keysText() ~= boundKey or boundSet == nil then bind() end
    paint()
    return true
end

-- The button was moved to the other half of the screen (or docked to a
-- target button that was): its small icons and labels swap sides. Looked at
-- twice a second, out of a fight (its icons are the game's secure buttons).
do
    local watcher, acc = CreateFrame("Frame"), 0
    watcher:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.5 then return end
        acc = 0
        if InCombatLockdown() or not button() or not ns.SelfSide then return end
        local side = ns.SelfSide()
        if side == K.side then return end
        local BB2 = ns.buffButton
        if BB2 and BB2.Docked and BB2.Docked() and BB2.Place then pcall(BB2.Place) end
        pcall(K.Apply)
    end)
end

-- Does one of this key's presses cast this item or spell? -> the slot
-- ("key", "shift", "ctrl", "alt", "more") or nil.
function K.SlotOf(what)
    if not (K.Active() and K.plan and what) then return nil end
    for _, slot in ipairs({ "key", "shift", "ctrl", "alt", "more" }) do
        local s = K.plan[slot]
        if s and ((s.item and s.item == what) or (s.spell and s.spell == what)) then return slot end
    end
    return nil
end
function K.Holds(what) return K.SlotOf(what) ~= nil end
-- Pure: the press in a few letters ("E", "S-E", "C-E", "A-E", "CS-E"), or in words.
function K.PressText(slot, keyLabel, words)
    if words then return (slot == "key" and "" or (K.NAME[slot] .. " + ")) .. keyLabel end
    local short = { key = "", shift = "S-", ctrl = "C-", alt = "A-", more = "CS-" }
    return (short[slot] or "") .. keyLabel
end
-- How to press what Flow advises, when this key casts it (a heal advised
-- counts as the key itself: it heals you, if not with that very spell).
function K.PressFor(advice, words)
    if not (K.Active() and advice) then return nil end
    local slot = K.SlotOf(advice.item or advice.spell)
    if not slot and K.Moved() and (advice.kind == "heal" or advice.kind == "emergency") and advice.spell then slot = "key" end
    if not slot then return nil end
    local key = BB.Keys()[1]
    local label = (ns.cast and ns.cast.ShortKey and ns.cast.ShortKey(key, GetBindingText and function(k) return GetBindingText(k, "KEY_", true) end)) or key
    return K.PressText(slot, label, words) .. (words and "" or ":")
end
-- Flow wants a heal right now (in a fight): the self button lights up.
function K.HealWanted()
    if not K.Active() then return false end
    for _, s in ipairs({ E.current, E.advice }) do
        if s and (s.kind == "heal" or s.kind == "emergency") then return true end
    end
    return false
end

-- A modifier is held: what this key casts with it, for the self button's
-- icon (as Flow's icon shows its own). nil: none held, or nothing on it.
function K.HeldStep(mod)
    if not K.Active() then return nil end
    if mod == nil and ns.queue and ns.queue.HeldMod then
        mod = ns.queue.HeldMod(IsControlKeyDown(), IsShiftKeyDown(), IsAltKeyDown())
    end
    local s = mod and slotStep[mod]
    if not s then return nil end
    local out = {}
    for k, v in pairs(s) do out[k] = v end
    out.press = K.LABEL[mod] .. "+"
    out.mod = mod
    return out
end

-- The key's own spell for a fight (BuffButton asks at the pull): your
-- quickest heal, or nil (off, or no heal known: the self button's own way).
function K.FightKey()
    if not K.Active() then return nil end
    local ok, plan = pcall(K.Now)
    local s = ok and plan and plan.key
    return s and s.spell or nil
end

local acc = 0
local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.5 then return end
    acc = 0
    if not InCombatLockdown() then pcall(K.Apply) end
end)
ns:On("PLAYER_REGEN_DISABLED", function() pcall(K.Apply) end)

-------------------------------------------------------------------------------
-- Settings, /flow carekeys
-------------------------------------------------------------------------------
function K.Lines()
    local out = {}
    if not BB.On() then
        out[1] = "the second key is off: /flow selfbutton on, then /flow selfkey <key> (heals and potions go on its modifiers)"
        return out
    end
    if #BB.Keys() == 0 then
        out[1] = "the self button has no key yet: /flow selfkey <key> (heals and potions go on its modifiers)"
        return out
    end
    if not K.Wanted() then out[1] = "heals and potions on the self button key: off" return out end
    local plan = K.plan or {}
    out[1] = string.format("self button key %s in a fight: %s", table.concat(BB.Keys(), " / "), nameOf(plan.key))
    for _, slot in ipairs(K.SLOTS) do
        local modKey = K.KeyFor(BB.Keys()[1], slot)
        out[#out + 1] = string.format("  %s (%s): %s%s", K.NAME[slot], tostring(modKey), nameOf(plan[slot]),
            slotText[slot] and (" [set as " .. slotText[slot] .. "]") or "")
    end
    out[#out + 1] = BB.TakesMine and BB.TakesMine()
        and "  out of a fight: this key is yours (healing up, a cure for you, your buffs); Flow's key is your target's"
        or "  out of a fight: Flow's key heals you too (\"Flow's key keeps its heal and potion\" is ticked)"
    return out
end
ns.commands.carekeys = function()
    for i, l in ipairs(K.Lines()) do if i == 1 then ns:Print(l) else print(l) end end
end
ns:Register("help", "carekeys", { order = 31, title = "The second key: heals and potions", lines = {
    "Turn on the self button and give it a key (/flow selfbutton on, /flow selfkey <key>): in a fight that key is your quickest heal,",
    "Shift + it your heal over time, Ctrl + it your other heal, Alt + it your healthstone or potion, Ctrl + Shift + it your bandage.",
    "Out of a fight the two keys split the same way: the self button's key is for you (heal up, eat, drink, bandage, cure, buffs),",
    "Flow's key is for your target (attacks on an enemy; heals, buffs and cures on a friendly player you target).",
    "/flow carekeys: what each press is set to.",
} })

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck({
        group = "key",
        label = "Flow's key keeps its heal and potion too",
        note = "(Shift and Alt + Flow's key)",
        tip = "With heals and potions on the self button's key, Shift + Flow's key and Alt + Flow's key become two more "
            .. "attacks (a druid's Entangling Roots and Nature's Grasp). Tick this to keep your heal on Shift and your "
            .. "potion on Alt of Flow's key as well.",
        get = function() return cfg().keepOnMain == true end,
        set = function(on) cfg().keepOnMain = on and true or nil end,
    })
end
if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck({
        group = "key",
        label = "Heals and potions on the self button's key",
        note = "(needs the self button and its key)",
        tip = "In a fight the self button's key casts your quickest heal on you; Shift + it your heal over time, "
            .. "Ctrl + it your other heal, Alt + it your healthstone or healing potion, Ctrl + Shift + it your best "
            .. "bandage. Little icons left of the self button show each. Flow's own key is unchanged. /flow carekeys lists them.",
        get = function() return K.Wanted() end,
        set = function(on)
            cfg().care = on and true or false
            if not InCombatLockdown() then pcall(K.Apply) end
        end,
    })
end

-- The icons' cooldown and can't-cast look (0.35.273), kept fresh a few times
-- a second. Only their pictures and texts change, which is allowed in a fight.
K.STATUS_EVERY = 0.25
function K.PaintStatus(now)
    if not ns.PaintStatus then return 0 end
    local n = 0
    for _, ic in pairs(icons) do
        if ic:IsShown() and ic.step and ic.tex then
            local ok = pcall(ns.PaintStatus, ic.tex, ic.timer, ic.step, now or GetTime(), ic.cd)
            if ok then n = n + 1 end
        end
    end
    return n
end
K._icons = icons   -- (tests)
if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(K.STATUS_EVERY, function() pcall(K.PaintStatus) end)
end

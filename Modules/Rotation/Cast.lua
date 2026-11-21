-- Cast button: click the suggestion icon, or press your Flow key, to cast
-- what Flow suggests.
--
-- WoW's rule: in combat, addons can't change what a button casts. So:
--   * out of combat the button always casts exactly what the icon shows
--     (buffs, seals, your pull, heals between fights);
--   * when combat starts it locks in one spell for the fight: Blizzard's own
--     one-button assistant spell if this client has one (it is allowed to
--     change itself), otherwise whatever Flow suggested at the pull;
--   * while locked, a small "key:" icon shows what your key will cast, so the
--     big icon (Flow's live advice) and the key never get confused.
-- Move it: hold Ctrl and drag (out of combat).

local _, ns = ...
local A, E = ns.api, ns.rotation
local C = {}
ns.cast = C

local btn, keyText, lockIcon
C.KEY_FONT = 11   -- the bind above the icon (the queue's CTRL / SHIFT / ALT are 8 to 10)
-- (Tests) the bind's text above the icon.
function C._KeyText() return keyText end
local macro, lockedSpell = nil, nil

-- Flow's own presses: the spell one of Flow's keys was set to cast, and
-- when. A cast of yours then isn't a choice of yours: a paladin's seal or
-- blessing (Paladin Rotation.lua) is learned only from casts you made
-- yourself, never from Flow's own suggestion.
C.PRESS_WINDOW = 2   -- seconds: a press to its cast (a blessing casts at once)
local presses = {}   -- [spell] = when (one entry per spell)
function C.NotePress(spell, now)
    if type(spell) == "string" and spell ~= "" then presses[spell] = now or GetTime() end
end
-- Pure: `log` ({ [spell] = when }) has a press of `spell` within `window`
-- seconds before `now`.
function C.PressedFor(log, spell, now, window)
    local at = spell and log and log[spell]
    return at ~= nil and now >= at and now - at <= (window or C.PRESS_WINDOW)
end
function C.FlowPressed(spell) return C.PressedFor(presses, spell, GetTime()) end

-- Who the press casts on. A step that names its own person (s.unit: a group
-- buff, a heal for the friend you've targeted) goes on them; any other heal
-- and your own buffs go on you (with a friend targeted, a buff meant for you
-- went on them); anything else on your target as usual.
-- (Until 0.35.222 a heal went on you whatever the step said: the icon read
-- "Regrowth on Bob" and the key healed you; only Ctrl + key reached Bob.
-- "For it to decide self cast is a broken concept.")
function C.UnitFor(s)
    if not s then return nil end
    if s.unit then return s.unit end
    if s.kind == "heal" or s.kind == "emergency" then return "player" end
    if s.kind == "buff" then return "player" end
    return nil
end

local function macroFor(s)
    if not s then return "" end
    if s.spell == "Attack" or s.spell == "Auto Attack" then return "/startattack" end
    local unit = C.UnitFor(s)
    if unit then return "/cast [@" .. unit .. "] " .. s.spell end
    return "/cast " .. s.spell
end

-- A heal or buff that can go on someone else: Ctrl + key puts it on your target.
local function helpful(s) return s and s.spell and (s.kind == "buff" or s.kind == "heal" or s.kind == "emergency") end
C._helpful = helpful

-- What the key itself is bound to instead of Flow's button: nil (the
-- button), "INTERACTTARGET" (reel in the bobber, mine the vein, loot your
-- kill), "SITORSTAND" (sit by a campfire) or "STARTATTACK" (the game's Start
-- Attack: auto attack on, never off).
local keyCommand = nil

function C.IsAttack(spell) return spell == "Attack" or spell == "Auto Attack" end

-- Does this client have the game's own "Start Attack" key command? The
-- Attack spell toggles: pressed while you swing, it stops you (Yang: the key
-- turned auto attack off). Start Attack only ever turns it on.
local startAttack
function C.HasStartAttack()
    if startAttack == nil and GetNumBindings and GetBinding then
        startAttack = false
        local ok, n = pcall(GetNumBindings)
        for i = 1, ok and n or 0 do
            if GetBinding(i) == "STARTATTACK" then startAttack = true break end
        end
    end
    return startAttack == true
end

-- The key's own command for this suggestion (nil: Flow's button).
function C.KeyCommandFor(s, canStartAttack)
    if not s then return nil end
    if s.type == "interact" then return "INTERACTTARGET" end
    if s.type == "sit" then return "SITORSTAND" end
    if C.IsAttack(s.spell) and canStartAttack then return "STARTATTACK" end
    return nil
end

-- What the key holds for a fight (it can't change once it starts). Never
-- the Attack spell where it would toggle: pressed while you swing it turns
-- auto attack off. Then nothing, so a press does nothing.
function C.FightLock(spell, canStartAttack)
    if C.IsAttack(spell) and not canStartAttack then return nil end
    return spell
end

-- What the press does, as text: for the diagnostics and to skip repeats.
local function describe(s)
    if not s then return "" end
    if s.type == "item" then return "/use " .. tostring(s.item) .. (s.targetSlot and (" on slot " .. s.targetSlot) or "") end
    if s.type == "interact" then return "Interact" end
    if s.type == "sit" then return "Sit" end
    if s.type == "wait" then return "Wait" end
    if s.type == "clear" then return "/cleartarget" end
    if s.type == "target" then return "/target " .. tostring(s.unit) end
    if s.type == "click" then return "/click " .. tostring(s.label) end
    return macroFor(s)
end
C._describe = describe  -- (tests)

-- Points the secure button at the suggestion, as the "spell" or "item"
-- button type: Forever ignores macro-type secure buttons (the fight records
-- showed every press arriving with the right macro, and nothing cast).
-- Attack: the key is bound to the game's Start Attack where it has one (on,
-- never off); else the Attack spell, suggested only while you're not
-- swinging (C.FightLock keeps it off the key for a fight). Items: equips gear (the pole), or with targetSlot applies to
-- that slot (a lure on your main hand). "interact": the key itself is bound
-- to the game's Interact for as long as that's the action.
local function setAction(s)
    if InCombatLockdown() then return end
    local text = describe(s)
    if text == macro then return end
    for _, a in ipairs({ "spell", "item", "unit", "target-slot", "clickbutton" }) do btn:SetAttribute(a, nil) end
    local kind = s and (s.type or "spell")
    -- (Ctrl, Shift and Alt + key are the queue's: C:SetQueue, below.)
    if kind == "spell" and s.spell then
        btn:SetAttribute("type", "spell")
        btn:SetAttribute("spell", s.spell)
        -- Heals and your own buffs on you: "player" as the unit (C.UnitFor).
        -- Flow Actions (Fishing, Find Minerals) say unit = "player" too, so a
        -- target you have selected (an NPC) never makes the cast fail.
        btn:SetAttribute("unit", C.UnitFor(s))
    elseif kind == "click" and s.button then
        -- Presses one of Flow's own buttons (the profession panel's "Make N").
        btn:SetAttribute("type", "click")
        btn:SetAttribute("clickbutton", s.button)
    elseif kind == "target" and s.unit then
        -- Targets a unit Flow can see (a quest NPC's nameplate, "nameplate4"):
        -- the secure "target" type with that unit.
        btn:SetAttribute("type", "target")
        btn:SetAttribute("unit", s.unit)
    elseif kind == "clear" then
        -- The secure "target" type with unit "none" clears your target.
        btn:SetAttribute("type", "target")
        btn:SetAttribute("unit", "none")
    elseif kind == "item" and s.item then
        btn:SetAttribute("type", "item")
        btn:SetAttribute("item", s.item)
        btn:SetAttribute("target-slot", s.targetSlot)
        btn:SetAttribute("unit", s.unit)   -- (a bandage: on you)
    else
        btn:SetAttribute("type", nil)
    end
    macro, lockedSpell = text, s and s.spell
    C:SetKeyCommand(C.KeyCommandFor(s, C.HasStartAttack()))
end

-- Where the key's bind and the held-modifier tag sit. On its own: above
-- the icon, the tag just left of the bind (as since 0.35.199). With the buff
-- button docked under it (0.35.236: "the key bind text anchored to the
-- bottom right of the target button and the spell text on top; only in the
-- docked mode"): the bind at the icon's bottom right, the tag after it,
-- so the gap between the two rows is free.
-- The small "press this instead" icon (what Flow advises in a fight when the
-- key holds another spell), with its few words beside it.
--   On its own: over the icon's bottom right corner, words to its left.
--   Docked: that corner is the auto-attack badge's and the self button is
--   right under it, so it stands in the open, right of the key bind, words
--   after it (0.35.242: it sat under the badge and over the gap).
-- Pure: point, relative point, x, y for the icon (to the Flow icon, or to the
-- key bind when docked), then the same for its words (to the small icon).
-- (side: the side the small icons run to, 0.35.324; this goes on the other.)
function C.AdvicePlace(docked, side)
    if side == "right" then
        if docked then return "RIGHT", "LEFT", -10, 0, "RIGHT", "LEFT", -3, 0 end
        return "BOTTOMLEFT", "BOTTOMLEFT", -8, -8, "LEFT", "RIGHT", 2, 0
    end
    if docked then return "LEFT", "RIGHT", 10, 0, "LEFT", "RIGHT", 3, 0 end
    return "BOTTOMRIGHT", "BOTTOMRIGHT", 8, -8, "RIGHT", "LEFT", -2, 0
end
function C.PlaceAdvice(docked, side)
    side = side or C.labelsSide or "left"
    local icon = E.icon
    if not (lockIcon and icon and keyText) then return false end
    local p, rp, x, y, lp, lrp, lx, ly = C.AdvicePlace(docked, side)
    lockIcon:ClearAllPoints()
    lockIcon:SetPoint(p, docked and keyText or icon, rp, x, y)
    lockIcon.label:ClearAllPoints()
    lockIcon.label:SetPoint(lp, lockIcon, lrp, lx, ly)
    -- (Above the badge, the cooldown numbers and the click buttons: never under anything.)
    lockIcon:SetFrameLevel(icon:GetFrameLevel() + 40)
    return true
end
C._LockIcon = function() return lockIcon end   -- (tests)

function C.LayoutLabels(docked, side)
    local icon = E.icon
    if not (keyText and icon) then return false end
    side = side or C.labelsSide or "left"
    C.labelsSide = side
    local right = side == "right"
    keyText:ClearAllPoints()
    -- (Docked: the bind at the middle of the icon's right side, the held
    -- modifier on its own line above it, the auto-attack badge below.)
    if docked and right then keyText:SetPoint("RIGHT", icon, "LEFT", -6, 0)
    elseif docked then keyText:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    else keyText:SetPoint("BOTTOM", icon, "TOP", 0, 2) end
    if icon.shiftTag then
        icon.shiftTag:ClearAllPoints()
        if docked and right then icon.shiftTag:SetPoint("BOTTOMRIGHT", keyText, "TOPRIGHT", 0, 2)
        elseif docked then icon.shiftTag:SetPoint("BOTTOMLEFT", keyText, "TOPLEFT", 0, 2)
        else icon.shiftTag:SetPoint("RIGHT", keyText, "LEFT", -4, 0) end
    end
    C.PlaceAdvice(docked, side)
    C.labelsDocked = docked and true or false
    return true
end

-- Blizzard's single-button assistant, if this client has one.
local function assistantSpell()
    if not (C_AssistedCombat and C_AssistedCombat.GetActionSpell) then return nil end
    local ok, id = pcall(C_AssistedCombat.GetActionSpell)
    if ok and id then return (A.SpellInfo(id)) end
end

-- A key's name short enough for the corner of the target button: "Mouse
-- Button 5" -> "MB5", "SHIFT-NUMPAD3" -> "S-N3", "SPACE" -> "Spc". Keys
-- already short ("`", "F", "1") stay as the game names them.
local SHORT = {
    SPACE = "Spc", ESCAPE = "Esc", BACKSPACE = "Bksp", CAPSLOCK = "Caps", ENTER = "Ent", TAB = "Tab",
    PAGEUP = "PgUp", PAGEDOWN = "PgDn", INSERT = "Ins", DELETE = "Del", HOME = "Home", END = "End",
    UP = "Up", DOWN = "Dn", LEFT = "Lt", RIGHT = "Rt",
    MOUSEWHEELUP = "WhUp", MOUSEWHEELDOWN = "WhDn",
    NUMPADPLUS = "N+", NUMPADMINUS = "N-", NUMPADMULTIPLY = "N*", NUMPADDIVIDE = "N/", NUMPADDECIMAL = "N.",
}
local MOD = { ALT = "A-", CTRL = "C-", SHIFT = "S-", META = "M-" }
function C.ShortKey(key, bindingText)
    if type(key) ~= "string" or key == "" then return "" end
    local mods, base = "", key
    while true do
        local m, rest = base:match("^(%u+)%-(.+)$")
        if not (m and MOD[m]) then break end
        mods, base = mods .. MOD[m], rest
    end
    local short = SHORT[base] or (base:match("^BUTTON(%d+)$") and "MB" .. base:match("^BUTTON(%d+)$"))
        or (base:match("^NUMPAD(%d)$") and "N" .. base:match("^NUMPAD(%d)$"))
    if not short then
        local text = bindingText and bindingText(base) or nil
        short = (text and #text <= 3) and text or base
    end
    return mods .. short
end

-- "`" or "` / F" (both keys). short: the target button's corner ("` / MB5");
-- otherwise the game's full names (tooltips, settings).
function C:KeyLabel(short)
    local out = {}
    local text = GetBindingText and function(k) return GetBindingText(k, "KEY_", true) end
    for _, key in ipairs(C.KeysOf(ns.db.cast)) do
        out[#out + 1] = short and C.ShortKey(key, text) or (text and text(key)) or key
    end
    return table.concat(out, " / ")
end

-- The target button's tooltip: what it does now (the spell's or item's own
-- tooltip, then why Flow suggests it), what the key is locked to in a fight,
-- and what's coming up next, each with its reason.
--   shown: the suggestion (E.shown), locked: the spell the key holds in combat,
--   deck: E:OnDeck(...) entries { spell, reason }
function C.TooltipLines(shown, locked, deck, inCombat)
    local lines = {}
    if shown then
        local what = (shown.spell and shown.target and (shown.spell .. " on " .. shown.target)) or shown.label or shown.spell or "?"
        lines[#lines + 1] = { "Flow suggests: " .. what, 1, 0.82, 0 }
        if shown.reason and shown.reason ~= what then lines[#lines + 1] = { "Why: " .. shown.reason, 1, 1, 1 } end
    else
        lines[#lines + 1] = { "Flow: nothing to press right now", 1, 0.82, 0 }
    end
    if inCombat and locked and (not shown or locked ~= shown.spell) then
        lines[#lines + 1] = { "The key casts " .. locked .. " this fight (it can't change in combat).", 1, 0.6, 0.3 }
    end
    if deck and #deck > 0 then
        lines[#lines + 1] = { "Coming up:", 1, 0.82, 0 }
        for i, d in ipairs(deck) do
            lines[#lines + 1] = { string.format("  %d. %s%s", i, d.spell, d.reason and ("  |cffaaaaaa(" .. d.reason .. ")|r") or ""), 1, 1, 1 }
        end
    end
    return lines
end

-- "Ctrl + key: Moonfire", "Shift + key: Rejuvenation on you", ... for the
-- slots that have something on them (slots: C:Slots()).
function C.QueueLines(slots)
    local out = {}
    for _, e in ipairs({ { "ctrl", "Ctrl" }, { "shift", "Shift" }, { "alt", "Alt" } }) do
        local s = slots and slots[e[1]]
        if s then
            local what = s.spell or s.label or "your healthstone or healing potion"
            local on = (s.spell and s.unit == "player" and " on you") or (s.spell and s.kind ~= "damage" and s.unit == "target" and " on your target") or ""
            out[#out + 1] = e[2] .. " + key: " .. what .. on
        end
    end
    return out
end

function C:FillTooltip(tt)
    local s = E.shown
    -- The underlying cast: the spell's (or item's) own tooltip first.
    local id = s and s.spell and select(4, A.SpellInfo(s.spell))
    local item = s and s.item and tonumber(tostring(s.item):match("(%d+)"))
    if id and tt.SetSpellByID then tt:SetSpellByID(id)
    elseif item and tt.SetItemByID then tt:SetItemByID(item) end
    if id or item then tt:AddLine(" ") end
    local deck = {}
    local ctx = E.lastCtx
    if ctx and (ctx.inCombat or ctx.hostile) then
        local ok, d = pcall(E.OnDeck, E, 3, s and s.spell)
        if ok then deck = d end
    end
    for _, l in ipairs(C.TooltipLines(s, lockedSpell, deck, InCombatLockdown())) do
        tt:AddLine(l[1], l[2], l[3], l[4], true)
    end
    local key = C:KeyLabel()
    tt:AddLine(key ~= "" and ("Key: " .. key) or "No key yet: /flow settings", 0.8, 0.8, 0.8)
    -- The queue: what the key casts with each modifier held.
    if key ~= "" then
        for _, line in ipairs(C.QueueLines(C:Slots())) do tt:AddLine(line, 0.4, 1, 0.4, true) end
    end
    tt:AddLine("Hold a modifier and the icon shows what it casts. In a fight all four are set at the pull; "
        .. "the one Flow advises pulses. Advice that's on none of them shows in the corner (bar:), where it also glows.", 0.8, 0.8, 0.8, true)
    tt:AddLine("Hold Ctrl: a handle appears; drag it to move the icon, or turn the mouse wheel to resize it.", 0.6, 0.6, 0.6)
    for _, st in ipairs(E.status or {}) do
        local c = st.color or { 1, 0.82, 0 }
        tt:AddLine(st.tip, c[1], c[2], c[3], true)
    end
    tt:AddLine("Right-click: options (after-fight order, bandages, camp).", 0.6, 0.6, 0.6)
end

-- The corner label for advice the key can't do mid-fight.
function C.AdviceLabel(adv, healSpell, second)
    if adv and healSpell and adv.spell == healSpell then return "Shift+" end
    if adv and second then return second end   -- (the second key casts it: "2nd:")
    return "bar:"
end

local function refreshLabels()
    if not keyText then return end
    -- A heal on the icon in a fight, while the key holds something else:
    -- the label says Shift + your key casts it (it does, all fight).
    local live = E.current
    local first = C.KeysOf(ns.db.cast)[1]
    local healKey = first and C.HealSpell and C:HealSpell() and C.HealKeyFor(first)
    if InCombatLockdown() and healKey and live and live.spell and (live.kind == "heal" or live.kind == "emergency")
        and lockedSpell ~= live.spell then
        keyText:SetText("|cff66ff66S-" .. C.ShortKey(first, GetBindingText and function(k) return GetBindingText(k, "KEY_", true) end) .. "|r")
        if not ns.db.cast.healTipShown then
            ns.db.cast.healTipShown = true
            ns:Print(string.format("tip: Shift + %s casts %s on you, even in a fight (the key itself can't change mid-fight).",
                (GetBindingText and GetBindingText(first, "KEY_", true)) or first, C:HealSpell()))
        end
    else
        keyText:SetText(C:KeyLabel(true))
    end
    -- In a fight the icon shows what the key casts (it was set at the pull);
    -- the corner shows the better spell it can't switch to (Display.lua,
    -- E.advice): "Shift+" when that's your heal (Shift + key casts it),
    -- else "bar:" (press it on your action bar, where it glows). Advice
    -- that Ctrl, Shift or Alt + key casts needs no corner icon: its slot
    -- in the queue pulses instead (E.adviceSlot, Display.lua).
    local adv = InCombatLockdown() and E.advice or nil
    if adv and adv.spell and not E.adviceSlot then
        local _, tex = A.SpellInfo(adv.spell)
        lockIcon.tex:SetTexture(tex)
        lockIcon.label:SetText(C.AdviceLabel(adv, C:HealSpell(), ns.careKeys and ns.careKeys.PressFor and ns.careKeys.PressFor(adv)))
        lockIcon:Show()
        ns.pulse.Add(lockIcon)   -- (on the same beat as every other "press this": Pulse.lua)
    else
        ns.pulse.Remove(lockIcon)
        lockIcon:Hide()
    end
end

local function build(cfg)
    btn = CreateFrame("Button", "FlowCastButton", UIParent, "SecureActionButtonTemplate")
    btn:SetSize(52, 52)
    btn:SetFrameStrata("MEDIUM")   -- (under the game's own windows: the game menu, Settings; 0.35.163)
    ns.RestorePlace(btn, cfg, 0, -160)
    -- Listen for both press and release: the secure button itself acts on the
    -- one matching your "cast on key down" setting. (Registering only one
    -- made key presses do nothing on some clients.)
    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn:SetAttribute("type", "macro")
    btn:SetAttribute("macrotext", "")
    -- Ctrl + drag moves it; make ctrl-clicks (and shift-clicks, as before) do
    -- nothing with the mouse, so moving never casts. (Ctrl + key and Shift +
    -- key are bindings to the "ctrl" and "heal" buttons: unaffected.)
    btn:SetAttribute("shift-type1", "macro")
    btn:SetAttribute("shift-macrotext1", "")
    btn:SetAttribute("ctrl-type1", "macro")
    btn:SetAttribute("ctrl-macrotext1", "")
    -- Right-click never casts: it opens the key's options (below). "*" covers
    -- Shift/Ctrl/Alt + right-click too ("type2" alone left Shift + right-click
    -- falling back to "type", the spell).
    btn:SetAttribute("*type2", "macro")
    btn:SetAttribute("*macrotext2", "")
    btn:SetMovable(true)
    btn:SetClampedToScreen(true)
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function(self)
        if ns.MoveKeyDown() and not InCombatLockdown() then self:StartMoving(); C.moving = true end
    end)
    btn:SetScript("OnDragStop", function() C:EndMove() end)
    -- Right-click: the Flow key's options (recovery order, bandages, camp).
    btn:HookScript("OnClick", function(_, button, down)
        if button == "RightButton" and not down and not InCombatLockdown() and ns.buffItems then
            ns.buffItems:OpenMenu()
        end
    end)
    btn:SetScript("OnEnter", function(self)
        ns.Tip(self, "ANCHOR_RIGHT")
        pcall(C.FillTooltip, C, GameTooltip)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- The visible icon sits on top of the secure button.
    local icon = E.icon
    if icon then
        icon:ClearAllPoints()
        icon:SetPoint("CENTER", btn, "CENTER")
        icon:SetScale(btn:GetScale())
        -- The key's bind is written above the icon, the way CTRL, SHIFT and ALT
        -- are above the queue's icons beside it (it used to sit in the icon's
        -- corner, over the spell's picture).
        keyText = icon:CreateFontString(nil, "OVERLAY")
        keyText:SetFont(STANDARD_TEXT_FONT, C.KEY_FONT, "OUTLINE")
        keyText:SetPoint("BOTTOM", icon, "TOP", 0, 2)
        keyText:SetTextColor(0.85, 0.85, 0.85)
        -- The tag for the modifier you hold ("CTRL+", "SHIFT+"): on the same
        -- line as the key's bind, just left of it, in the same lettering, so
        -- the two read as one: "SHIFT+ MB5 / Q" (0.35.199; it sat above the
        -- modifier icons in bigger letters and looked out of line).
        if icon.shiftTag then
            icon.shiftTag:ClearAllPoints()
            icon.shiftTag:SetFont(STANDARD_TEXT_FONT, C.KEY_FONT, "OUTLINE")
            icon.shiftTag:SetPoint("RIGHT", keyText, "LEFT", -4, 0)
        end
        lockIcon = CreateFrame("Frame", nil, icon)
        lockIcon:SetSize(22, 22)
        lockIcon:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 8, -8)
        lockIcon.edge = lockIcon:CreateTexture(nil, "BACKGROUND")
        lockIcon.edge:SetPoint("TOPLEFT", -2, 2); lockIcon.edge:SetPoint("BOTTOMRIGHT", 2, -2)
        lockIcon.edge:SetColorTexture(ns.pulse.COLOR[1], ns.pulse.COLOR[2], ns.pulse.COLOR[3], 1)
        lockIcon.tex = lockIcon:CreateTexture(nil, "OVERLAY")
        lockIcon.tex:SetAllPoints()
        lockIcon.label = lockIcon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lockIcon.label:SetPoint("RIGHT", lockIcon, "LEFT", -2, 0)
        lockIcon.label:SetText("bar:")
        lockIcon:Hide()
        C.PlaceAdvice(C.labelsDocked)
    end
    -- Ctrl: drag to move, mouse wheel to resize (the icon too).
    C.handle = ns:MoveHandle(btn, { name = "the Flow button", save = function() return ns.db.rotation end,
        also = function() return { E.icon } end,
        -- Docked: the one note goes under the self button too (0.35.247).
        noteUnder = function() return C.NoteUnder() end })
end

-------------------------------------------------------------------------------
-- The frame the move note goes under: the self button when it's docked under
-- Flow's icon and showing, else nil (Flow's own button).
function C.NoteUnder()
    local BB = ns.buffButton
    local b = _G.FlowBuffButton
    if BB and BB.Docked and BB.Docked() and b and b:IsShown() then return b end
    return nil
end

-------------------------------------------------------------------------------
-- Key binding. Uses an override binding: your own key bindings are never
-- changed, and clearing Flow's key gives the key back to whatever it did.
-------------------------------------------------------------------------------

local owner = CreateFrame("Frame")
local pendingKey = false

-- Shift + your key: your heal, on you, any time, fights included. The key
-- itself can't change in a fight (WoW's rule), so a heal Flow showed mid-fight
-- couldn't be cast with it until the fight was over. The heal is set before
-- the fight on a second "button" of the same secure button ("heal") that
-- only the Shift binding presses: clicking or Ctrl-dragging the icon is
-- unchanged. Setting: "Shift + easy key heals you" (/flow settings).
local healSpell, anyHeal

-- Your heal for it: the fastest to cast, of the heals you know that land at
-- once (E.DirectHeal: a heal over time only when it's all you have). The
-- same heal Flow advises when you've been hit a lot, so the advice and
-- Shift + key agree. knows(spell), castMs(spell).
function C.HealFor(def, knows, castMs)
    return E.DirectHeal(def and def.heals, def and def.hots, knows, castMs)
end

-- Your key with a modifier added, in the game's order (ALT, CTRL, SHIFT):
-- ModKey("`", "SHIFT") -> "SHIFT-`", ModKey("SHIFT-E", "CTRL") -> "CTRL-SHIFT-E".
-- A key that already uses that modifier gets none.
function C.ModKey(key, mod)
    if type(key) ~= "string" or key == "" or key:find(mod .. "-", 1, true) then return nil end
    local has = { ALT = key:find("ALT-", 1, true), CTRL = key:find("CTRL-", 1, true), SHIFT = key:find("SHIFT-", 1, true) }
    has[mod] = true
    local base = key:gsub("ALT%-", ""):gsub("CTRL%-", ""):gsub("SHIFT%-", "")
    return (has.ALT and "ALT-" or "") .. (has.CTRL and "CTRL-" or "") .. (has.SHIFT and "SHIFT-" or "") .. base
end
-- Shift + key: your heal. Ctrl + key: the shown heal or buff on your target.
function C.HealKeyFor(key) return C.ModKey(key, "SHIFT") end
function C.TargetKeyFor(key) return C.ModKey(key, "CTRL") end

function C:HealSpell() return healSpell end
-- Your quick heal, whichever key casts it (Shift + Flow's key, or the second key).
function C:AnyHeal() return anyHeal end

-------------------------------------------------------------------------------
-- The queue's three modifier presses (Queue.lua decides what goes on them):
-- Ctrl + key, Shift + key and Alt + key each press a second "button" of the
-- same secure button: "ctrl", "heal" and "emerg". Only their bindings press
-- them, so clicking or Ctrl-dragging the icon is unchanged.
--
-- Their attributes carry the "*" prefix. With a modifier held the game looks
-- a press up as "shift-type-heal", then "*type-heal", then the button's
-- plain "type": never as plain "type-heal". Set without the "*" (as it was
-- until 0.35.162), Shift + key fell through to the key's own spell: it cast
-- Wrath, not your heal.
-------------------------------------------------------------------------------
local SLOT_BUTTON = { ctrl = "ctrl", shift = "heal", alt = "emerg", more = "more" }
-- The modifiers each slot is pressed with ("more": Ctrl and Shift together).
local SLOT_MODS = { ctrl = { "CTRL" }, shift = { "SHIFT" }, alt = { "ALT" }, more = { "CTRL", "SHIFT" } }
C.SLOTS = { "ctrl", "shift", "alt", "more" }
-- Your key with a slot's modifiers added ("Q", "more" -> "CTRL-SHIFT-Q");
-- nil when the key already uses one of them.
function C.SlotKey(key, slot)
    local k = key
    for _, mod in ipairs(SLOT_MODS[slot] or {}) do
        if not k then return nil end
        k = C.ModKey(k, mod)
    end
    if not SLOT_MODS[slot] then return nil end
    return k
end
local SLOT_ATTRS = { "type", "spell", "item", "unit" }
local slotText = {}   -- [slot] = what it's set to, as text (to skip repeats)
local slotView = {}   -- [slot] = the step it casts (C:Slots, for the icons)

-- What a slot's step sets on the button: type ("spell" / "item"), the spell
-- or item, and the unit (always one: without it the press would take the
-- key's own unit, and a Moonfire would try to land on you). nil: nothing.
function C.SlotAttributes(s)
    if not s then return nil end
    if s.item then return "item", s.item, s.unit end
    if s.spell then return "spell", s.spell, s.unit or C.UnitFor(s) or "target" end
    return nil
end

-- Points one slot ("ctrl", "shift", "alt") at a step. Out of a fight only.
-- Returns true when the slot went from empty to set or back (its binding
-- comes and goes with it).
local function setSlot(slot, s)
    if InCombatLockdown() or not btn then return false end
    local kind, what, unit = C.SlotAttributes(s)
    local text = kind and (kind .. ":" .. tostring(what) .. "@" .. tostring(unit)) or nil
    if text == slotText[slot] then
        if kind then slotView[slot] = s end   -- (the same press: keep the newest reason)
        return false
    end
    local had = slotText[slot] ~= nil
    local name = SLOT_BUTTON[slot]
    for _, a in ipairs(SLOT_ATTRS) do
        btn:SetAttribute("*" .. a .. "-" .. name, nil)
        btn:SetAttribute(a .. "-" .. name, nil)   -- (the plain ones older versions set)
    end
    if kind then
        btn:SetAttribute("*type-" .. name, kind)
        btn:SetAttribute("*" .. kind .. "-" .. name, what)
        btn:SetAttribute("*unit-" .. name, unit)
    end
    slotText[slot], slotView[slot] = text, kind and s or nil
    return had ~= (text ~= nil)
end
C._setSlot = setSlot   -- (tests)

-- The steps Ctrl, Shift and Alt + key cast right now: { ctrl, shift, alt }.
function C:Slots() return slotView end

local emergItem
local function setHeal()
    if InCombatLockdown() or not btn then return end
    local spell = ns.db.cast.shiftHeal ~= false and C.HealFor(E:Definition(),
        function(s) return E:Knows(s) end, function(s) return select(3, A.SpellInfo(s)) end) or nil
    -- Moved to the second key (CareKeys.lua): Shift + key is an attack's.
    anyHeal = spell
    if ns.careKeys and ns.careKeys.Moved and ns.careKeys.Moved() then spell = nil end
    if spell == healSpell then return end
    healSpell = spell
    -- (C:SetQueue puts it on Shift + key, with the other two.)
end
C._setHeal = setHeal

-- Sets all three from the queue (Queue.lua Q.Now / Q.Slots): out of a fight
-- ten times a second, and once more at the pull, where they lock.
function C:SetQueue(q)
    if InCombatLockdown() or not btn then return end
    local changed = false
    for _, slot in ipairs(C.SLOTS) do
        if setSlot(slot, q and q[slot] or nil) then changed = true end
    end
    if changed then self:ApplyKey() end
end
-- Out of a fight: for what the key shows now. (Timed for /flow perf; one
-- failing read must not stop the key's own update.)
local timedQueue = ns.perf.Wrap("target button: queue", function(s) return ns.queue.Now(s) end)
function C.SetLiveQueue(s)
    if not ns.queue then return end
    local ok, q = pcall(timedQueue, s)
    if ok then C:SetQueue(q)
    elseif "queue: " .. tostring(q) ~= E.lastError then E.lastError, E.lastErrorAt = "queue: " .. tostring(q), GetTime(); ns:Log("rotation", E.lastError) end
end
-- At the pull: for the spell the key was just locked to.
function C.SetFightQueue()
    if not ns.queue then return end
    local ok, q = pcall(ns.queue.Now, lockedSpell and { spell = lockedSpell } or nil, lockedSpell or "")
    if ok then C:SetQueue(q)
    else ns:Log("rotation", "queue at the pull: " .. tostring(q)) end
end

-- Alt + key: your healthstone (else your best healing potion), set before
-- the fight like the Shift heal, so the item works in a fight even when
-- it's on none of your bars. It can't switch mid-fight: with the healthstone
-- on cooldown, the potion is on the Flow icon to press from your bar or bag.
function C.ItemKeyFor(key) return C.ModKey(key, "ALT") end
function C:EmergencyItem() return emergItem end
-- The item for Alt + key, or nil. carried = BI.PickEmergency of your bags.
function C.EmergencyItemFor(cast, rotation, carried)
    if (cast and cast.altItem == false) or (rotation and rotation.emergencyItems == false) or not carried then return nil end
    return "item:" .. carried.id
end
local function setEmergency()
    if InCombatLockdown() or not btn then return end
    local BI = ns.buffItems
    local item = C.EmergencyItemFor(ns.db.cast, ns.db.rotation, BI and BI.EmergencyCarry and BI.EmergencyCarry() or nil)
    -- (On the second key when the heal and potion moved there: Alt + key is an attack's.)
    if ns.careKeys and ns.careKeys.Moved and ns.careKeys.Moved() then item = nil end
    emergItem = item
    -- (C:SetQueue puts it on Alt + key; without one, Alt takes the queue's spell.)
end
C._setEmergency = setEmergency
ns:On("BAG_UPDATE_DELAYED", function() if C_Timer then C_Timer.After(0.2, setEmergency) else setEmergency() end end)
ns:On("PLAYER_REGEN_ENABLED", function() if C_Timer then C_Timer.After(0.5, setEmergency) else setEmergency() end end)

-- Your easy-button keys: up to two (ns.db.cast.key and .key2), both cast the
-- suggestion. Returns the ones set, without repeats.
function C.KeysOf(cast)
    local out = {}
    if not cast then return out end
    -- (not ipairs over {key, key2}: it stops at a missing first key)
    if cast.key then out[#out + 1] = cast.key end
    if cast.key2 and cast.key2 ~= cast.key then out[#out + 1] = cast.key2 end
    return out
end
function C:Keys() return C.KeysOf(ns.db.cast) end

function C:ApplyKey()
    if InCombatLockdown() then pendingKey = true return end
    pendingKey = false
    ClearOverrideBindings(owner)
    for _, key in ipairs(self:Keys()) do
        if keyCommand then SetOverrideBinding(owner, true, key, keyCommand)
        else SetOverrideBindingClick(owner, true, key, "FlowCastButton", "LeftButton") end
        -- The queue: a modifier is bound while its slot has something on it.
        -- While the key is the game's Start Attack (the first press at a new
        -- enemy: Engine EngageStep), every modifier press is Start Attack too:
        -- "when I engage with a spell I expect auto attack to go on right
        -- then" (0.35.230: opening with Shift + key cast Moonfire and never
        -- started the swing; only the plain key did).
        for _, slot in ipairs(C.SLOTS) do
            local modKey = C.SlotKey(key, slot)
            if modKey and C.ModsStartAttack(keyCommand) then
                SetOverrideBinding(owner, true, modKey, keyCommand)
            elseif modKey and slotText[slot] then
                SetOverrideBindingClick(owner, true, modKey, "FlowCastButton", SLOT_BUTTON[slot])
            end
        end
    end
    refreshLabels()
end

-- Pure: do the modifier presses run the key's command too? Only for Start
-- Attack (Interact and Sit stay the plain key's alone).
function C.ModsStartAttack(cmd) return cmd == "STARTATTACK" end

-- Key = a game command (Interact, Start Attack) or back to Flow's button.
-- Only out of combat (the fight lock sets it just before the lockdown).
function C:SetKeyCommand(cmd)
    if cmd == keyCommand or InCombatLockdown() then return end
    keyCommand = cmd
    self:ApplyKey()
end
function C:KeyCommand() return keyCommand end

-- What the key still does in this fight, for the icon when nothing new is
-- suggested: { spell, kind = "held", label }, or nil (nothing, or the
-- harmless Start Attack).
function C.HeldView(spell, cmd)
    if not spell or (C.IsAttack(spell) and cmd == "STARTATTACK") then return nil end
    -- (Was "key: Wrath": "why does it say key:?" Just the spell's name now, 0.35.228.)
    return { spell = spell, kind = "held", label = spell }
end
function C:Held() return C.HeldView(lockedSpell, keyCommand) end

-- What else uses this key: friendly name, or nil if it's free (or Flow's).
function C:Conflict(key)
    local action = GetBindingAction and GetBindingAction(key)
    if not action or action == "" or action:find("FlowCastButton", 1, true) then return nil end
    return _G["BINDING_NAME_" .. action] or action, action
end

local MOVEMENT = {
    MOVEFORWARD = true, MOVEBACKWARD = true, TURNLEFT = true, TURNRIGHT = true,
    STRAFELEFT = true, STRAFERIGHT = true, JUMP = true, TOGGLEAUTORUN = true,
}
function C:IsMovement(action) return MOVEMENT[action] == true end

-- slot 1 (your key) or 2 (a second key for the same button).
function C:SetKey(key, slot)
    if slot == 2 then ns.db.cast.key2 = key else ns.db.cast.key = key end
    self:ApplyKey()
end

-------------------------------------------------------------------------------
-- Wiring
-------------------------------------------------------------------------------

-- In-game key binding menu entry (Bindings.xml).
BINDING_HEADER_FLOW = "Flow"
_G["BINDING_NAME_CLICK FlowCastButton:LeftButton"] = "Cast Flow's suggestion"

ns:OnLoad(function(saved)
    saved.cast = saved.cast or {}
    build(saved.rotation)
    C:ApplyKey()

    -- Runs on its own frame: the button hides when there's nothing to press,
    -- and a hidden frame's OnUpdate never runs, so (before 0.35.22) the
    -- button never came back out of combat and the key did nothing.
    local acc = 0
    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.1 then return end
        acc = 0
        if not InCombatLockdown() then
            local s = E.shown
            setAction(s)
            setHeal()
            C.SetLiveQueue(s)
            -- Hidden when there's nothing to press, so it never blocks clicks
            -- on the world. (Can only change out of combat.)
            local want = s ~= nil or not ns.db.rotation.locked
            if want ~= btn:IsShown() then btn:SetShown(want) end
        end
        refreshLabels()
    end)
end)

-------------------------------------------------------------------------------
-- The key follows your form in a fight (0.35.205)
-------------------------------------------------------------------------------
-- "I may want to pull with Moonfire and then go Bear Form, and the easy
-- button gets stuck in the last form: is there a way for it to change based
-- on form?" Flow's own code can't touch the key in a fight. The game can: a
-- secure handler with a state driver on your form runs a small restricted
-- snippet when the form changes, and that snippet may set the key's spell
-- even in combat, as long as everything it needs was handed to it before
-- the fight. So before every pull Flow gives the handler, for each form, the
-- spell for the key and for Ctrl + key (the class's formKeys); changing
-- form mid-fight swaps them in. Shift (your heal), Alt (your potion) and
-- Ctrl + Shift stay as they were set at the pull.
--
-- A class says what each form's fight uses (rotation definition):
--   formKeys = function(engine) return {
--       none = { key = "Wrath", ctrl = "Moonfire" },           -- no form
--       ["Bear Form"] = { key = "Maul", ctrl = "Demoralizing Roar" } } end
--
-- "The key follows your form in a fight" (Flow Settings, Easy keys)
-- turns it off. /flow key test says what each form is given.

-- The presses a change of form may swap: the key, and each modifier by the
-- name its click has on the button (SLOT_BUTTON). Shift and Alt only when
-- they hold attacks (the heal and potion moved to the second key,
-- CareKeys.lua): a heal or a potion is left where it is.
C.FORM_SLOTS = { "ctrl", "shift", "alt", "more" }
local FORM_BUTTON = { ctrl = "ctrl", shift = "heal", alt = "emerg", more = "more" }
local function formSnippet()
    local parts = { [[
    if not PlayerInCombat() then return end
    local b = self:GetFrameRef("flowkey")
    if not b then return end
    local k = self:GetAttribute("key-" .. newstate)
    if k and k ~= "" then
        b:SetAttribute("type", "spell")
        b:SetAttribute("spell", k)
        b:SetAttribute("unit", "target")
    end
    local v
]] }
    for _, slot in ipairs(C.FORM_SLOTS) do
        local name = FORM_BUTTON[slot]
        parts[#parts + 1] = string.format([[
    v = self:GetAttribute("%s-" .. newstate)
    if v and v ~= "" then
        b:SetAttribute("*type-%s", "spell")
        b:SetAttribute("*spell-%s", v)
        b:SetAttribute("*unit-%s", "target")
        local d = self:GetFrameRef("deck-%s")
        if d then
            d:SetAttribute("type", "spell")
            d:SetAttribute("spell", v)
            d:SetAttribute("unit", "target")
        end
    end
]], slot, name, name, name, slot)
    end
    return table.concat(parts)
end
C._FormSnippet = formSnippet   -- (tests)
C.FORM_STATES = 8   -- form numbers the handler is given (0 = no form)
-- One more state, past the forms: stealthed in a form (a druid prowling in
-- Cat Form, 0.35.326). "When I go into prowl, use my opening attack from
-- stealth on my key, and when I attack, go to all the attack buttons instead
-- of that from-behind attack." The key holds the opener while you prowl; the
-- moment stealth breaks the game itself moves it to the form's own spells
-- (the same handler that follows a change of form), in a fight too.
-- A class says so with formKeys().stealth = { form = "Cat Form", key = ... }.
C.STEALTH_STATE = C.FORM_STATES + 1

-- Pure: the state driver's condition and each state's spells. forms: your
-- forms in the game's order ({ name, index } each); keys: the class's
-- formKeys ({ key, ctrl, shift, alt, more }: a spell or a list, the first
-- you know); knows(spell) -> bool; slots: the modifiers to fill (default:
-- Ctrl and Ctrl + Shift only). No spell twice in one form. State 0 is no form.
function C.FormPlan(forms, keys, knows, slots)
    slots = slots or { "ctrl", "more" }
    local function entry(e)
        if not e then return nil end
        local used, any = {}, false
        local function pick(v)
            if type(v) == "string" then v = { v } end
            for _, spell in ipairs(v or {}) do
                if not used[spell] and (not knows or knows(spell)) then
                    used[spell] = true
                    any = true
                    return spell
                end
            end
        end
        local out = { key = pick(e.key) }
        local hasShift = false
        for _, slot in ipairs(slots) do
            out[slot] = pick(e[slot])
            if slot == "shift" then hasShift = true end
        end
        -- (As the queue does it: the second attack on Shift, the nearest icon;
        -- what Shift had on Ctrl. Only where Shift is an attack's.)
        if hasShift then out.ctrl, out.shift = out.shift, out.ctrl end
        return any and out or nil
    end
    local cond, plan = {}, { [0] = entry(keys and keys.none) }
    for _, f in ipairs(forms or {}) do
        if f.index and f.index <= C.FORM_STATES then
            -- (Stealthed in this form first: the game takes the first condition that holds.)
            local st = keys and keys.stealth
            if st and st.form == f.name then
                local e = entry(st)
                if e then
                    cond[#cond + 1] = string.format("[form:%d,stealth] %d", f.index, C.STEALTH_STATE)
                    plan[C.STEALTH_STATE] = e
                    plan.stealthForm = f.index
                end
            end
            cond[#cond + 1] = string.format("[form:%d] %d", f.index, f.index)
            plan[f.index] = entry(keys and keys[f.name])
        end
    end
    cond[#cond + 1] = "0"
    return table.concat(cond, "; "), plan
end
-- Which modifiers a change of form swaps right now.
function C.FormSlots()
    local moved = ns.careKeys and ns.careKeys.Moved and ns.careKeys.Moved()
    return moved and C.FORM_SLOTS or { "ctrl", "more" }
end

local formHeader, formCond, formSwitched
C.formPlan = nil
function C.FormKeyOn() return ns.db.cast.formKey ~= false end

-- Hands the handler this fight's spells. Out of a fight (and in the last
-- moment before one) only.
function C.SetFormKeys()
    if InCombatLockdown() or not btn then return false end
    local def = E:Definition()
    local keys
    if def and def.formKeys and C.FormKeyOn() then
        local ok, k = pcall(def.formKeys, E)
        keys = ok and k or nil
    end
    if not keys and not formHeader then return false end   -- (a class with no forms: no handler at all)
    if not formHeader then
        local ok, h = pcall(CreateFrame, "Frame", "FlowFormKey", UIParent, "SecureHandlerStateTemplate")
        if not ok or not h or not h.SetFrameRef then
            if not C.formFailed then ns:Log("rotation", "form key: this client has no secure state handler (" .. tostring(h) .. ")") end
            C.formFailed = true
            return false
        end
        formHeader = h
        h:SetFrameRef("flowkey", btn)
        h:SetAttribute("_onstate-flowform", formSnippet())
    end
    local slots = C.FormSlots()
    local cond, plan = C.FormPlan(A.StanceSpells(), keys, function(spell) return E:Knows(spell) end, slots)
    for i = 0, C.STEALTH_STATE do
        local p = keys and plan[i]
        formHeader:SetAttribute("key-" .. i, p and p.key or "")
        for _, slot in ipairs(C.FORM_SLOTS) do
            formHeader:SetAttribute(slot .. "-" .. i, p and p[slot] or "")
        end
    end
    if cond ~= formCond then
        if formCond and UnregisterStateDriver then UnregisterStateDriver(formHeader, "flowform") end
        RegisterStateDriver(formHeader, "flowform", cond)
        formCond = cond
        ns:Log("rotation", "form key: watching " .. cond)
    end
    C.formPlan = keys and plan or nil
    return true
end
C._FormHeader = function() return formHeader end   -- (tests)

-- Flow's own picture of it: your form changed in a fight, so the key (and
-- Ctrl + key) now cast that form's spells. The handler did the real work.
local function formNow()
    local index = 0
    for _, s in ipairs(A.StanceSpells()) do
        if s.active then index = s.index break end
    end
    local p = C.formPlan
    if p and p.stealthForm == index and p[C.STEALTH_STATE] and IsStealthed then
        local ok, hidden = pcall(IsStealthed)
        if ok and A.Safe(hidden) == true then return C.STEALTH_STATE end
    end
    return index
end
-- Is the hand-over from a stealth opener set up? (Without it an opener on
-- the key would stay there all fight: the class asks before choosing one.)
function C.StealthReady()
    return C.formPlan ~= nil and C.formPlan[C.STEALTH_STATE] ~= nil and formHeader ~= nil
end
function C.StealthOpener()
    local p = C.formPlan and C.formPlan[C.STEALTH_STATE]
    return C.StealthReady() and p and p.key or nil
end
local function formChanged()
    if not (InCombatLockdown() and C.formPlan and formHeader) then return end
    local p = C.formPlan[formNow()]
    if not p then return end
    if p.key then lockedSpell = p.key end
    for _, slot in ipairs(C.FORM_SLOTS) do
        if p[slot] then slotView[slot] = { spell = p[slot], kind = "damage", reason = "This form's spell for this press" } end
    end
    formSwitched = true
    ns:Log("rotation", string.format("form key: form %d in a fight, the key casts %s, Ctrl %s, Shift %s, Alt %s, C+S %s", formNow(), tostring(p.key), tostring(p.ctrl), tostring(p.shift), tostring(p.alt), tostring(p.more)))
end
ns:On("UPDATE_SHAPESHIFT_FORM", formChanged)
-- (Stealth broke in a fight: the opener gives way to the form's own spells.)
ns:On("UPDATE_STEALTH", formChanged)
-- After the fight: what Flow remembers having set is stale (the handler
-- changed it), so the next update writes the key and Ctrl again.
ns:On("PLAYER_REGEN_ENABLED", function()
    if formSwitched then
        formSwitched = false
        macro = nil
        for _, slot in ipairs(C.FORM_SLOTS) do slotText[slot] = nil end
    end
    if C_Timer then C_Timer.After(0.3, function() pcall(C.SetFormKeys) end) end
end)
ns:On("PLAYER_ENTERING_WORLD", function() if C_Timer then C_Timer.After(3, function() pcall(C.SetFormKeys) end) end end)
ns:On("SPELLS_CHANGED", function() if not InCombatLockdown() then pcall(C.SetFormKeys) end end)

-- /flow key test: what each form is given.
function C.FormLines()
    if not C.formPlan then
        return { "  key follows your form: " .. (C.formFailed and "not on this client (no secure state handler)" or (C.FormKeyOn() and "nothing to switch (this class has no forms set up)" or "off")) }
    end
    local out = { "  key follows your form in a fight (watching " .. tostring(formCond) .. "):" }
    local names = { [0] = "no form" }
    for _, s in ipairs(A.StanceSpells()) do names[s.index] = s.name end
    names[C.STEALTH_STATE] = (names[C.formPlan.stealthForm or -1] or "a form") .. ", stealthed (the opener; then that form's)"
    for i = 0, C.STEALTH_STATE do
        local p = C.formPlan[i]
        if p then
            out[#out + 1] = string.format("    %s: key %s, Ctrl %s, Shift %s, Alt %s, Ctrl + Shift %s", names[i] or ("form " .. i), tostring(p.key),
                tostring(p.ctrl), tostring(p.shift or "(as at the pull)"), tostring(p.alt or "(as at the pull)"), tostring(p.more))
        end
    end
    return out
end

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck({
        group = "key",
        label = "The key follows your form in a fight",
        tip = "Change form in a fight (Bear Form after pulling as a caster) and your key and Ctrl + key cast that form's spells. Off: they keep what they had at the pull.",
        get = function() return C.FormKeyOn() end,
        set = function(on)
            ns.db.cast.formKey = on and true or false
            if not InCombatLockdown() then pcall(C.SetFormKeys) end
        end,
    })
end

-- Last moment before combat lockdown: lock in the spell for this fight.
ns:On("PLAYER_REGEN_DISABLED", function()
    if btn and not btn:IsShown() then btn:Show() end  -- key must work all fight
    setHeal()   -- Shift + key: your heal, all fight
    setEmergency()   -- Alt + key: your healthstone or potion
    -- The key goes back to Flow's button for the fight (not Interact or Sit). This
    -- event comes just before the lockdown, so changes are still allowed.
    if keyCommand == "INTERACTTARGET" or keyCommand == "SITORSTAND" then C:SetKeyCommand(nil) end
    local helper = assistantSpell()
    if helper then
        setAction({ spell = helper })
    else
        -- The key can't change during the fight, so lock it to something worth
        -- pressing all fight: the class decides (pullLock). Attack only where
        -- it can't turn your swing off (C.FightLock); else nothing at all,
        -- never whatever the icon showed last (it was Attack, pressed again
        -- mid-fight it stopped your swing).
        local s = E.current
        local def = E:Definition()
        local spell = def and def.pullLock and def.pullLock(s, E) or (s and s.spell)
        spell = C.FightLock(spell, C.HasStartAttack())
        if spell and s and spell == s.spell then setAction(s)
        elseif spell then setAction({ spell = spell })
        else setAction(nil) end
    end
    -- The queue locks with the key: Ctrl, Shift and Alt + key keep what
    -- they're given now for the whole fight (Queue.lua: your second attack,
    -- your heal, your healthstone or the spell that holds your target).
    C.SetFightQueue()
    -- And what each form casts, for a change of form mid-fight (above).
    pcall(C.SetFormKeys)
end)

ns:On("PLAYER_REGEN_ENABLED", function()
    if pendingKey then C:ApplyKey() end
end)

-- Re-apply the key once the game has loaded its own bindings.
ns:On("PLAYER_ENTERING_WORLD", function() C:ApplyKey() end)
ns:On("UPDATE_BINDINGS", function()
    if InCombatLockdown() then return end
    for _, key in ipairs(C:Keys()) do
        if GetBindingAction(key, true) == "" then C:ApplyKey() return end
    end
end)

-- /flow key test: what your keys do right now.
function C:Test()
    local keys = self:Keys()
    ns:Print("cast key check:")
    if #keys == 0 then print("  key: not set (/flow settings)") end
    for i, key in ipairs(keys) do
        print(string.format("  key%s: %s (%s), bound to %s", i == 1 and "" or " " .. i,
            (GetBindingText and GetBindingText(key, "KEY_", true)) or key, key, tostring(GetBindingAction(key, true))))
    end
    local first = keys[1]
    -- The queue: what each modifier + key casts, and what the game has it bound to.
    for _, e in ipairs({ { "ctrl" }, { "shift" }, { "alt" }, { "more" } }) do
        local s = slotView[e[1]]
        local modKey = first and C.SlotKey(first, e[1])
        print(string.format("  %s + key: %s", e[1], (s and modKey)
            and string.format("%s casts %s on %s (set as %s; bound to %s)", modKey, tostring(s.spell or s.item),
                tostring(select(3, C.SlotAttributes(s)) or "its own target"), tostring(slotText[e[1]]), tostring(GetBindingAction(modKey, true)))
            or "nothing on it"))
    end
    print("  button shown: " .. tostring(btn and btn:IsShown()) .. ", casts: "
        .. (macro and macro ~= "" and macro or "nothing right now (no suggestion)"))
    print("  key's own command: " .. tostring(keyCommand or "none (Flow's button)")
        .. ", game has Start Attack (auto attack on, never off): " .. tostring(C.HasStartAttack()))
    print("  in combat: " .. tostring(InCombatLockdown()) .. ", cast on key down: "
        .. tostring(GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")))
    for _, l in ipairs(C.FormLines()) do print(l) end
    if ns.clickSlots then for _, l in ipairs(ns.clickSlots.Lines()) do print(l) end end
end

-------------------------------------------------------------------------------
-- Fight record for the diagnostics ("[cast]" lines in the log): what was
-- suggested at the pull, what the key was set to, whether the button got
-- your clicks / key presses, and what Flow suggested during the fight.
-------------------------------------------------------------------------------

local fight
local afterUntil = 0   -- the after-fight heal window is recorded too (15 s after a fight)
local lastAction       -- the Flow Action you just pressed: { label, at } (see complain below)
ns:On("PLAYER_REGEN_DISABLED", function()
    local key = ns.db.cast.key
    fight = { at = GetTime(), ticks = 0, empty = 0, seen = {}, clicks = 0, downs = 0 }
    ns:Log("cast", string.format("fight start: suggestion %s, key %s -> %s, button %s, macro %q, keydown %s",
        tostring(E.current and E.current.spell), tostring(key),
        tostring(key and GetBindingAction(key, true)), tostring(btn and btn:IsShown()),
        tostring(macro), tostring(GetCVarBool and GetCVarBool("ActionButtonUseKeyDown"))))
end)

ns:On("PLAYER_REGEN_ENABLED", function()
    if not fight then return end
    local seen = {}
    for spell, n in pairs(fight.seen) do seen[#seen + 1] = spell .. " x" .. n end
    local mods = fight.mods or {}
    ns:Log("cast", string.format("fight end (%.0f s): key pressed %d time(s), button got %d click(s) (%d key-down), ctrl + key %d, shift + key %d, alt + key %d, %d spell(s) cast, suggested %s; nothing %d of %d ticks; last error %s",
        GetTime() - fight.at, fight.keys or 0, fight.clicks, fight.downs, mods.ctrl or 0, mods.shift or 0, mods.alt or 0, fight.casts or 0, #seen > 0 and table.concat(seen, ", ") or "nothing",
        fight.empty, fight.ticks, tostring(E.lastError)))
    fight = nil
end)

ns:OnLoad(function()
    if not btn then return end
    -- A Flow Action can need a step just before the press (the pole: note
    -- which weapons to put back afterwards).
    btn:HookScript("PreClick", function()
        local s = E.shown
        if s and s.before and not InCombatLockdown() then pcall(s.before) end
    end)
    btn:HookScript("PostClick", function(_, button, down)
        -- A modifier press (the queue: "ctrl", "heal" = Shift, "emerg" = Alt):
        -- each one logged with what it casts and counted for the fight, so
        -- the diagnostics show whether Ctrl, Shift and Alt + key get used.
        local mod = (button == "ctrl" and "ctrl") or (button == "heal" and "shift") or (button == "emerg" and "alt")
            or (button == "more" and "more") or nil
        if mod then
            if down ~= false then
                local step = slotView[mod]
                if step then C.NotePress(step.spell) end
                ns:Log(mod == "shift" and "heal" or "cast", string.format("%s + key pressed: %s, hurt %.0f, in a fight %s",
                    mod, tostring(step and (step.spell or step.item)), E.hurt or 0, tostring(InCombatLockdown())))
                if fight then
                    fight.mods = fight.mods or {}
                    fight.mods[mod] = (fight.mods[mod] or 0) + 1
                    -- (It reached the button: the key check below must not say it didn't.)
                    fight.reached = (fight.reached or 0) + 1
                end
                if mod == "shift" and E.NoteShiftPress then E.NoteShiftPress() end   -- (death reports)
            end
            return
        end
        -- Press audit (Audit.lua): what the icon showed and what the key was
        -- really set to cast, at this press. (Key down only; a game command
        -- on the key, like Interact, has nothing to compare.)
        if down ~= false and button == "LeftButton" then C.NotePress(btn:GetAttribute("spell")) end
        if down ~= false and button == "LeftButton" and ns.audit and not keyCommand then
            pcall(ns.audit.Press, E.iconShows, btn:GetAttribute("spell") or btn:GetAttribute("item"),
                InCombatLockdown() and true or false, fight and (GetTime() - fight.at) or nil, lockedSpell)
        end
        local s = E.shown
        local label = s and (s.label or s.key)
        -- (one press clicks twice, key down and up: log it once)
        local again = lastAction and lastAction.label == label and GetTime() - lastAction.at < 0.4
        if not fight and s and s.kind == "action" and not again then
            lastAction = { label = label, at = GetTime() }
            ns:Log("action", string.format("pressed: %s (%s %s)", tostring(lastAction.label),
                tostring(btn:GetAttribute("type")), tostring(btn:GetAttribute("item") or btn:GetAttribute("spell"))))
        end
        if not fight and GetTime() < afterUntil then
            ns:Log("cast", string.format("after-fight press: %s down=%s spell %s unit %s", tostring(button), tostring(down),
                tostring(btn:GetAttribute("spell")), tostring(btn:GetAttribute("unit"))))
        end
        if fight then
            fight.clicks = fight.clicks + 1
            fight.reached = (fight.reached or 0) + 1
            if down then fight.downs = fight.downs + 1 end
            if fight.clicks == 1 then
                ns:Log("cast", string.format("first press in fight: %s down=%s macro %q", tostring(button), tostring(down), tostring(macro)))
            end
        end
    end)
    local acc = 0
    local sampler = CreateFrame("Frame")
    sampler:SetScript("OnUpdate", function(_, dt)
        if not fight then return end
        acc = acc + dt
        if acc < 0.5 then return end
        acc = 0
        fight.ticks = fight.ticks + 1
        local s = E.current
        local what = s and (s.spell or s.item or s.label or "?")
        if what then fight.seen[what] = (fight.seen[what] or 0) + 1 else fight.empty = fight.empty + 1 end
    end)
end)

-- During a fight, the game's own complaints (out of range, not ready, no
-- target...) and failed casts go into the fight record too (first few).
-- (afterUntil: declared with `fight` above)
ns:On("PLAYER_REGEN_ENABLED", function() afterUntil = GetTime() + 15 end)
-- A Flow Action you just pressed (equip an upgrade, the fishing pole...):
-- what the game said back in the next 2 s goes in the log too, so a failing
-- "Equip X" shows why ("You can't use that item", a level too low...).
local function complain(what)
    if not fight and lastAction and GetTime() - lastAction.at < 2 then
        ns:Log("action", string.format("%s: game said: %s", tostring(lastAction.label), tostring(what)))
        return
    end
    if not fight and GetTime() < afterUntil then ns:Log("cast", "after fight, game said: " .. tostring(what)) return end
    if not fight then return end
    fight.errors = (fight.errors or 0) + 1
    if fight.errors <= 5 then ns:Log("cast", "game said: " .. tostring(what)) end
end
ns:On("UI_ERROR_MESSAGE", function(_, msg) complain(ns.api.Safe(msg)) end)
ns:On("UNIT_SPELLCAST_FAILED", function(unit, _, spellID)
    if unit == "player" then complain("cast failed: " .. tostring(ns.api.SpellInfo(ns.api.Safe(spellID) or 0))) end
end)
ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit ~= "player" or not fight then return end
    fight.casts = (fight.casts or 0) + 1
end)

-------------------------------------------------------------------------------
-- Moving and resizing the icon: hold Ctrl (out of combat) and a "drag to
-- move" handle appears over it, and the mouse wheel over it resizes it.
-- The shared handle (ns:MoveHandle, Modules/MoveHandle.lua) does both; the visible icon
-- resizes along with the secure button under it.
-------------------------------------------------------------------------------

-- Finish a drag of the button itself and remember where. The cast button is
-- a secure frame: moving it is forbidden in combat ("Flow has been blocked
-- from an action..." when a drag was still going as a fight began). So a
-- drag still going when combat starts is finished at the start of the fight
-- (still allowed then, see PLAYER_REGEN_DISABLED below), and a release
-- during the fight does nothing.
function C:EndMove()
    if not (self.moving and btn) or InCombatLockdown() then return end
    self.moving = false
    btn:StopMovingOrSizing()
    local a, _, b, x, y = btn:GetPoint()
    ns.db.rotation.point = { a, b, x, y }
end
ns:On("PLAYER_REGEN_DISABLED", function() C:EndMove() end)

-------------------------------------------------------------------------------
-- Key check: a listener that sees your Flow key go down (and passes it on
-- untouched), so the fight record can say, press by press, whether the key
-- arrived, what it was bound to right then, and whether the button then got
-- the click. ("Key does nothing" with the binding looking right otherwise.)
-------------------------------------------------------------------------------

local spy = CreateFrame("Frame", nil, UIParent)
local spyLogged = 0
local clicksAtPress = 0
-- Pure: did a key press fail to reach the button? reached: clicks the button
-- has had this fight (the main one and the modifier ones); before: that
-- count when the key went down.
function C.Missed(reached, before)
    return (reached or 0) == (before or 0)
end

-- Only when keys can be passed on: a keyboard frame that can't would eat every key.
if spy.SetPropagateKeyboardInput then
    spy:SetPropagateKeyboardInput(true)
    spy:EnableKeyboard(true)
end
spy:SetScript("OnKeyDown", function(_, key)
    local mine
    for _, k in ipairs(ns.db and ns.db.cast and C.KeysOf(ns.db.cast) or {}) do
        if key == k:match("[^-]+$") then mine = k end
    end
    if not mine then return end
    if E.NoteKeyPress then E.NoteKeyPress() end   -- (the pull's Start Attack press is counted: Engine EngageStep)
    -- (Every click that reached the button, the modifier ones too: after
    -- Ctrl + key the log said "the button did NOT get the click" right under
    -- "ctrl + key pressed: Entangling Roots", which the button itself wrote.)
    clicksAtPress = fight and (fight.reached or 0) or 0
    if fight then fight.keys = (fight.keys or 0) + 1 end
    if spyLogged < 6 then
        spyLogged = spyLogged + 1
        local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        ns:Log("cast", string.format("key %s pressed: bound to %s, button %s, focus %s",
            tostring(key), tostring(GetBindingAction(mine, true)), btn and (btn:IsShown() and "shown" or "hidden") or "missing",
            focus and (focus:GetName() or "a text box") or "none"))
        C_Timer.After(0.3, function()
            if fight and C.Missed(fight.reached, clicksAtPress) then ns:Log("cast", "  ...and the button did NOT get the click") end
        end)
    end
end)
ns:On("PLAYER_REGEN_DISABLED", function() spyLogged = 0 end)
-- A Flow key on a mouse button (Button 4 / 5, the wheel button): no key event
-- comes for those, so the game's own "a mouse button went down" tells.
local MOUSE_KEY = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
ns:On("GLOBAL_MOUSE_DOWN", function(button)
    local key = MOUSE_KEY[button or ""]
    if not key or not (ns.db and ns.db.cast) then return end
    for _, k in ipairs(C.KeysOf(ns.db.cast)) do
        if k:match("[^-]+$") == key then
            if E.NoteKeyPress then E.NoteKeyPress() end
            return
        end
    end
end)

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
-- Move it: hold Shift and drag (out of combat).

local _, ns = ...
local A, E = ns.api, ns.rotation
local C = {}
ns.cast = C

local btn, keyText, lockIcon
local macro, lockedSpell = nil, nil

-- Who the press casts on: heals and your own buffs on you (with a friend
-- targeted, a buff meant for you went on them), a group buff on its person
-- (s.unit), anything else on your target as usual. Ctrl + key casts a heal
-- or buff on your target instead (see "ontarget" below).
function C.UnitFor(s)
    if not s then return nil end
    if s.kind == "heal" or s.kind == "emergency" then return "player" end
    if s.unit then return s.unit end
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
-- kill) or "STARTATTACK" (the game's Start Attack: auto attack on, never off).
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
    if s.type == "clear" then return "/cleartarget" end
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
    -- Ctrl + key: the same heal or buff on your target (a second "button"
    -- of the secure button, pressed only by the Ctrl binding).
    local onTarget = helpful(s) and ns.db.cast.ctrlTarget ~= false
    btn:SetAttribute("type-ontarget", onTarget and "spell" or nil)
    btn:SetAttribute("spell-ontarget", onTarget and s.spell or nil)
    btn:SetAttribute("unit-ontarget", onTarget and "target" or nil)
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
    elseif kind == "clear" then
        -- The secure "target" type with unit "none" clears your target.
        btn:SetAttribute("type", "target")
        btn:SetAttribute("unit", "none")
    elseif kind == "item" and s.item then
        btn:SetAttribute("type", "item")
        btn:SetAttribute("item", s.item)
        btn:SetAttribute("target-slot", s.targetSlot)
    else
        btn:SetAttribute("type", nil)
    end
    macro, lockedSpell = text, s and s.spell
    C:SetKeyCommand(C.KeyCommandFor(s, C.HasStartAttack()))
end

-- Blizzard's single-button assistant, if this client has one.
local function assistantSpell()
    if not (C_AssistedCombat and C_AssistedCombat.GetActionSpell) then return nil end
    local ok, id = pcall(C_AssistedCombat.GetActionSpell)
    if ok and id then return (A.SpellInfo(id)) end
end

-- A key's name short enough for the corner of the easy button: "Mouse
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

-- "`" or "` / F" (both keys). short: the easy button's corner ("` / MB5");
-- otherwise the game's full names (tooltips, settings).
function C:KeyLabel(short)
    local out = {}
    local text = GetBindingText and function(k) return GetBindingText(k, "KEY_", true) end
    for _, key in ipairs(C.KeysOf(ns.db.cast)) do
        out[#out + 1] = short and C.ShortKey(key, text) or (text and text(key)) or key
    end
    return table.concat(out, " / ")
end

-- The easy button's tooltip: what it does now (the spell's or item's own
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
    if key ~= "" and C:HealSpell() then
        tt:AddLine("Shift + key: " .. C:HealSpell() .. " on you (works in fights too).", 0.4, 1, 0.4)
    end
    if key ~= "" and helpful(s) and ns.db.cast.ctrlTarget ~= false then
        tt:AddLine("Ctrl + key: " .. s.spell .. " on your target instead.", 0.4, 0.8, 1)
    end
    tt:AddLine("Hold Shift and drag to move; hold Ctrl and use the mouse wheel to resize.", 0.6, 0.6, 0.6)
end

local function refreshLabels()
    if not keyText then return end
    -- A heal on the icon in a fight, while the key holds something else:
    -- the label says Shift + your key casts it (it does, all fight).
    local live = E.current
    local first = C.KeysOf(ns.db.cast)[1]
    local healKey = first and C.HealSpell and C:HealSpell() and C.HealKeyFor(first)
    if InCombatLockdown() and healKey and live and (live.kind == "heal" or live.kind == "emergency")
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
    -- In combat, show what the key is locked to when it differs from the
    -- advice. (With no advice at all, the icon itself shows it: C:Held.)
    local liveSpell = live and live.spell
    if InCombatLockdown() and lockedSpell and liveSpell and lockedSpell ~= liveSpell then
        local _, tex = A.SpellInfo(lockedSpell)
        lockIcon.tex:SetTexture(tex)
        lockIcon:Show()
    else
        lockIcon:Hide()
    end
end

local function build(cfg)
    btn = CreateFrame("Button", "FlowCastButton", UIParent, "SecureActionButtonTemplate")
    btn:SetSize(52, 52)
    btn:SetFrameStrata("HIGH")
    ns.RestorePlace(btn, cfg, 0, -160)
    -- Listen for both press and release: the secure button itself acts on the
    -- one matching your "cast on key down" setting. (Registering only one
    -- made key presses do nothing on some clients.)
    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn:SetAttribute("type", "macro")
    btn:SetAttribute("macrotext", "")
    -- Shift + drag moves it; make shift-clicks do nothing so moving never casts.
    btn:SetAttribute("shift-type1", "macro")
    btn:SetAttribute("shift-macrotext1", "")
    btn:SetMovable(true)
    btn:SetClampedToScreen(true)
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() and not InCombatLockdown() then self:StartMoving(); C.moving = true end
    end)
    btn:SetScript("OnDragStop", function() C:EndMove() end)
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
        keyText = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        keyText:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -2, -2)
        lockIcon = CreateFrame("Frame", nil, icon)
        lockIcon:SetSize(22, 22)
        lockIcon:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 8, -8)
        lockIcon.tex = lockIcon:CreateTexture(nil, "OVERLAY")
        lockIcon.tex:SetAllPoints()
        lockIcon.label = lockIcon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lockIcon.label:SetPoint("RIGHT", lockIcon, "LEFT", -2, 0)
        lockIcon.label:SetText("key:")
        lockIcon:Hide()
    end
    -- Shift: drag to move. Ctrl: mouse wheel to resize (the icon too).
    C.handle = ns:MoveHandle(btn, { name = "the Flow button", save = function() return ns.db.rotation end,
        also = function() return { E.icon } end })
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
-- only the Shift binding presses: clicking or shift-dragging the icon is
-- unchanged. Setting: "Shift + easy key heals you" (/flow settings).
local healSpell

-- Your heal for it: the fastest to cast of your class's heals that you know
-- (a fight is no time for a slow one). knows(spell), castMs(spell).
function C.HealFor(def, knows, castMs)
    local best, bestMs
    for _, spell in ipairs(def and def.heals or {}) do
        if knows(spell) then
            local ms = castMs(spell) or 0
            if not best or ms < bestMs then best, bestMs = spell, ms end
        end
    end
    return best
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

local function setHeal()
    if InCombatLockdown() or not btn then return end
    local spell = ns.db.cast.shiftHeal ~= false and C.HealFor(E:Definition(),
        function(s) return E:Knows(s) end, function(s) return select(3, A.SpellInfo(s)) end) or nil
    if spell == healSpell then return end
    healSpell = spell
    btn:SetAttribute("type-heal", spell and "spell" or nil)
    btn:SetAttribute("spell-heal", spell)
    btn:SetAttribute("unit-heal", spell and "player" or nil)
    C:ApplyKey()   -- the Shift binding comes and goes with the heal
end
C._setHeal = setHeal

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
        local healKey = healSpell and C.HealKeyFor(key)
        if healKey then SetOverrideBindingClick(owner, true, healKey, "FlowCastButton", "heal") end
        local targetKey = ns.db.cast.ctrlTarget ~= false and C.TargetKeyFor(key)
        if targetKey then SetOverrideBindingClick(owner, true, targetKey, "FlowCastButton", "ontarget") end
    end
    refreshLabels()
end

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
    return { spell = spell, kind = "held", label = "key: " .. spell }
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
            -- Hidden when there's nothing to press, so it never blocks clicks
            -- on the world. (Can only change out of combat.)
            local want = s ~= nil or not ns.db.rotation.locked
            if want ~= btn:IsShown() then btn:SetShown(want) end
        end
        refreshLabels()
    end)
end)

-- Last moment before combat lockdown: lock in the spell for this fight.
ns:On("PLAYER_REGEN_DISABLED", function()
    if btn and not btn:IsShown() then btn:Show() end  -- key must work all fight
    setHeal()   -- Shift + key: your heal, all fight
    -- The key goes back to Flow's button for the fight (not Interact). This
    -- event comes just before the lockdown, so changes are still allowed.
    if keyCommand == "INTERACTTARGET" then C:SetKeyCommand(nil) end
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
    print("  shift + key: " .. (healSpell and first and C.HealKeyFor(first)
        and string.format("%s casts %s on you (bound to %s)", C.HealKeyFor(first), healSpell, tostring(GetBindingAction(C.HealKeyFor(first), true)))
        or "no heal on it"))
    local tk = first and C.TargetKeyFor(first)
    print("  ctrl + key: " .. (tk and ns.db.cast.ctrlTarget ~= false
        and string.format("%s casts %s on your target (bound to %s)", tk, tostring(btn and btn:GetAttribute("spell-ontarget") or "nothing now"),
            tostring(GetBindingAction(tk, true)))
        or "off"))
    print("  button shown: " .. tostring(btn and btn:IsShown()) .. ", casts: "
        .. (macro and macro ~= "" and macro or "nothing right now (no suggestion)"))
    print("  key's own command: " .. tostring(keyCommand or "none (Flow's button)")
        .. ", game has Start Attack (auto attack on, never off): " .. tostring(C.HasStartAttack()))
    print("  in combat: " .. tostring(InCombatLockdown()) .. ", cast on key down: "
        .. tostring(GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")))
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
    ns:Log("cast", string.format("fight end (%.0f s): key pressed %d time(s), button got %d click(s) (%d key-down), shift + key %d, %d spell(s) cast, suggested %s; nothing %d of %d ticks; last error %s",
        GetTime() - fight.at, fight.keys or 0, fight.clicks, fight.downs, fight.healPresses or 0, fight.casts or 0, #seen > 0 and table.concat(seen, ", ") or "nothing",
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
        -- Shift + key (the "heal" button): every press logged, with Flow's
        -- hurt estimate, so the diagnostics show whether the heal went off.
        if button == "heal" then
            if down ~= false then
                ns:Log("heal", string.format("shift + key pressed: %s on you, hurt %.0f, in a fight %s",
                    tostring(btn:GetAttribute("spell-heal")), E.hurt or 0, tostring(InCombatLockdown())))
            end
            if fight then fight.healPresses = (fight.healPresses or 0) + 1 end
            if down ~= false and E.NoteShiftPress then E.NoteShiftPress() end   -- (death reports)
            return
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
        if s then fight.seen[s.spell] = (fight.seen[s.spell] or 0) + 1 else fight.empty = fight.empty + 1 end
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
-- Moving and resizing the icon: hold Shift (out of combat) and a "drag to
-- move" handle appears over it; hold Ctrl and the mouse wheel resizes it.
-- The shared handle (ns:MoveHandle in Core.lua) does both; the visible icon
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
    -- (key press noted below)
    clicksAtPress = fight and fight.clicks or 0
    if fight then fight.keys = (fight.keys or 0) + 1 end
    if spyLogged < 6 then
        spyLogged = spyLogged + 1
        local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        ns:Log("cast", string.format("key %s pressed: bound to %s, button %s, focus %s",
            tostring(key), tostring(GetBindingAction(mine, true)), btn and (btn:IsShown() and "shown" or "hidden") or "missing",
            focus and (focus:GetName() or "a text box") or "none"))
        C_Timer.After(0.3, function()
            if fight and fight.clicks == clicksAtPress then ns:Log("cast", "  ...and the button did NOT get the click") end
        end)
    end
end)
ns:On("PLAYER_REGEN_DISABLED", function() spyLogged = 0 end)

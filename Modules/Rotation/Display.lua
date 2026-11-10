-- Shows the suggestion: a movable icon near the middle of the screen, plus a
-- pulsing glow on whichever action bar button holds that spell.

local _, ns = ...
local A, E = ns.api, ns.rotation

local COLORS = {
    -- No red: red reads as "can't". Gold means "heal now".
    damage    = { 0.2, 1.0, 0.2 },    -- green
    buff      = { 0.35, 0.75, 1.0 },  -- light blue
    heal      = { 1.0, 0.8, 0.2 },    -- gold, steady pulse
    emergency = { 1.0, 0.85, 0.1 },   -- bright gold, fast pulse
    held      = { 0.55, 0.55, 0.55 }, -- grey: what the key still does mid-fight (nothing new to press)
}

local BAR_PREFIXES = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarRightButton", "MultiBarLeftButton",
    "MultiBar5Button", "MultiBar6Button", "MultiBar7Button",
}

local icon, glows, current
local buttonsBySpell = {}

-- A coloured frame made of plain colour textures. Works on every client
-- (no dependency on Blizzard art files).
local function makeBorder(parent, thickness, inset)
    local b = { edges = {} }
    local function edge(p1, p2, horizontal)
        local t = parent:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetColorTexture(1, 1, 1, 1)
        t:SetPoint(p1, parent, p1, 0, 0)
        t:SetPoint(p2, parent, p2, 0, 0)
        if horizontal then t:SetHeight(thickness) else t:SetWidth(thickness) end
        b.edges[#b.edges + 1] = t
    end
    edge("TOPLEFT", "TOPRIGHT", true)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    edge("TOPLEFT", "BOTTOMLEFT", false)
    edge("TOPRIGHT", "BOTTOMRIGHT", false)
    b.fill = parent:CreateTexture(nil, "OVERLAY", nil, 6)
    b.fill:SetColorTexture(1, 1, 1, 1)
    b.fill:SetPoint("TOPLEFT", inset or 0, -(inset or 0))
    b.fill:SetPoint("BOTTOMRIGHT", -(inset or 0), inset or 0)
    function b:SetColor(r, g, bl)
        for _, t in ipairs(self.edges) do t:SetVertexColor(r, g, bl, 1) end
        self.fill:SetVertexColor(r, g, bl, 0.25)
    end
    return b
end

-------------------------------------------------------------------------------
-- Suggestion icon
-------------------------------------------------------------------------------

local function buildIcon(cfg)
    local f = CreateFrame("Frame", "FlowRotationIcon", UIParent)
    f:SetSize(52, 52)
    f:SetFrameStrata("HIGH")
    ns.RestorePlace(f, cfg, 0, -160)  -- the cast button then puts it on top of itself

    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    f.border = makeBorder(f, 3)
    f.border.fill:Hide()  -- keep the spell icon clear

    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints()
    -- Flow draws its own countdown (below), so the game's numbers stay off.
    if f.cd.SetHideCountdownNumbers then f.cd:SetHideCountdownNumbers(true) end
    -- The cooldown timer: seconds left, big in the middle of the icon, above
    -- the cooldown's dark sweep. The global cooldown (1.5 s after every cast)
    -- isn't counted: only real cooldowns.
    f.timerLayer = CreateFrame("Frame", nil, f)
    f.timerLayer:SetAllPoints()
    f.timerLayer:SetFrameLevel(f.cd:GetFrameLevel() + 2)
    f.timer = f.timerLayer:CreateFontString(nil, "OVERLAY")
    f.timer:SetFont(STANDARD_TEXT_FONT, 18, "THICKOUTLINE")
    f.timer:SetPoint("CENTER", 0, 0)
    f.timer:SetTextColor(1, 0.95, 0.7)
    -- Auto attack on: a crossed-swords badge on the LEFT of the button (the
    -- "active" side; on deck is on the right), gently pulsing while swinging.
    f.swing = CreateFrame("Frame", nil, f.timerLayer)
    f.swing:SetSize(24, 24)   -- the "active" side: left of the button
    f.swing:SetPoint("RIGHT", f, "LEFT", -8, 0)
    f.swing.back = f.swing:CreateTexture(nil, "BACKGROUND")
    f.swing.back:SetPoint("TOPLEFT", -1, 1); f.swing.back:SetPoint("BOTTOMRIGHT", 1, -1)
    f.swing.back:SetColorTexture(0, 0, 0, 0.85)
    f.swing.tex = f.swing:CreateTexture(nil, "ARTWORK")
    f.swing.tex:SetAllPoints()
    f.swing.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local _, swingIcon = A.SpellInfo("Auto Attack")
    f.swing.tex:SetTexture(swingIcon or "Interface\\Icons\\INV_Sword_04")
    local pulse = f.swing:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1); fade:SetToAlpha(0.45); fade:SetDuration(0.6)
    f.swing.pulse = pulse
    f.swing:Hide()
    -- On deck (right of the button): the next three spells in your priority
    -- order, shrinking, each with its cooldown timer. Greyed while cooling down.
    f.deck = {}
    local SIZES = { 30, 25, 21 }
    local prev
    for i, sz in ipairs(SIZES) do
        local d = CreateFrame("Frame", nil, f)
        d:SetSize(sz, sz)
        if prev then d:SetPoint("LEFT", prev, "RIGHT", 4, 0) else d:SetPoint("LEFT", f, "RIGHT", 8, 0) end
        d.back = d:CreateTexture(nil, "BACKGROUND")
        d.back:SetPoint("TOPLEFT", -1, 1); d.back:SetPoint("BOTTOMRIGHT", 1, -1)
        d.back:SetColorTexture(0, 0, 0, 0.85)
        d.tex = d:CreateTexture(nil, "ARTWORK")
        d.tex:SetAllPoints(); d.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        d.timer = d:CreateFontString(nil, "OVERLAY")
        d.timer:SetFont(STANDARD_TEXT_FONT, math.max(9, math.floor(sz * 0.42)), "OUTLINE")
        d.timer:SetPoint("CENTER")
        d:SetAlpha(1 - (i - 1) * 0.15)
        -- Hover: that spell's own tooltip and why it's coming up.
        d:EnableMouse(true)
        d:SetScript("OnEnter", function(self)
            local e = self.entry
            if not e then return end
            ns.Tip(self, "ANCHOR_BOTTOM")
            local id = select(4, A.SpellInfo(e.spell))
            if id and GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(id); GameTooltip:AddLine(" ") end
            GameTooltip:AddLine(string.format("Coming up %d: %s", i, e.spell), 1, 0.82, 0)
            if e.reason then GameTooltip:AddLine("Why: " .. e.reason, 1, 1, 1, true) end
            GameTooltip:Show()
        end)
        d:SetScript("OnLeave", function() GameTooltip:Hide() end)
        d:Hide()
        f.deck[i] = d
        prev = d
    end

    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.text:SetPoint("TOP", f, "BOTTOM", 0, -4)

    -- Position and moving are handled by the secure cast button underneath
    -- (Modules/Rotation/Cast.lua): the icon is anchored to it.
    f:EnableMouse(false)
    f:Hide()
    return f
end

-------------------------------------------------------------------------------
-- Action button glow
-------------------------------------------------------------------------------

local function glowFor(btn)
    glows = glows or {}
    local g = glows[btn]
    if g then return g end
    g = CreateFrame("Frame", nil, btn)
    g:SetPoint("TOPLEFT", btn, "TOPLEFT", -3, 3)
    g:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 3, -3)
    g:SetFrameStrata(btn:GetFrameStrata())
    g:SetFrameLevel(btn:GetFrameLevel() + 10)
    g.border = makeBorder(g, 3, 3)
    local ag = g:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local fade = ag:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.35)
    fade:SetDuration(0.45)
    g.anim, g.fade = ag, fade
    g:Hide()
    glows[btn] = g
    return g
end

local function scanButtons()
    wipe(buttonsBySpell)
    for _, prefix in ipairs(BAR_PREFIXES) do
        for i = 1, 12 do
            local btn = _G[prefix .. i]
            if btn and btn:IsVisible() then
                local slot = btn.action
                if not slot and btn.GetAttribute then slot = btn:GetAttribute("action") end
                if slot and HasAction(slot) then
                    local kind, id = GetActionInfo(slot)
                    if kind == "spell" and id then
                        local name = A.SpellInfo(id)
                        if name then
                            buttonsBySpell[name] = buttonsBySpell[name] or {}
                            table.insert(buttonsBySpell[name], btn)
                            glowFor(btn)  -- build now, out of combat
                        end
                    end
                end
            end
        end
    end
    -- Stance bar (paladin auras): button i holds stance form i.
    for _, s in ipairs(A.StanceSpells()) do
        local btn = _G["StanceButton" .. s.index] or _G["ShapeshiftButton" .. s.index]
        if btn and btn:IsVisible() then
            buttonsBySpell[s.name] = buttonsBySpell[s.name] or {}
            table.insert(buttonsBySpell[s.name], btn)
            glowFor(btn)
        end
    end
end

local function clearGlows()
    if not glows then return end
    for _, g in pairs(glows) do
        g.anim:Stop()
        g:Hide()
    end
end

local function showGlows(spell, color, kind)
    clearGlows()
    for _, btn in ipairs(buttonsBySpell[spell] or {}) do
        local g = glowFor(btn)
        g.border:SetColor(color[1], color[2], color[3])
        g.fade:SetDuration(kind == "emergency" and 0.2 or 0.45)
        g:Show()
        g.anim:Play()
    end
end

-------------------------------------------------------------------------------
-- Update loop
-------------------------------------------------------------------------------


-- Cooldown of what the button does: a spell, or an item (a lure, a recipe).
local function cooldownOf(s)
    if s.spell then return A.CooldownRaw(s.spell) end
    local id = s.item and tonumber(tostring(s.item):match("(%d+)"))
    if id then
        local get = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
        if get then
            local ok, start, dur = pcall(get, id)
            if ok then return start, dur end
        end
    end
    return 0, 0
end

-- The timer's text for a cooldown: "" when ready or only the global
-- cooldown; "1m" / "12" / "4.2" otherwise.
local GCD = 1.6
function ns.CooldownText(start, dur, now)
    start, dur = ns.api.Safe(start), ns.api.Safe(dur)
    if not (start and dur) or start == 0 or dur <= GCD then return "" end
    local left = start + dur - now
    if left <= 0 then return "" end
    if left >= 60 then return string.format("%dm", math.ceil(left / 60)) end
    if left >= 10 then return string.format("%d", math.floor(left + 0.5)) end
    return string.format("%.1f", left)
end

-- Border for a Flow Action (equip the pole, make a campfire...): not the
-- route purple, which reads as "epic item". Spells use the spell colour
-- (light blue, like buffs); items their own quality colour (white, green...).
local function actionColor(s)
    local id = s.item and tonumber(tostring(s.item):match("(%d+)"))
    if id then
        local q = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
        local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
        if c then return { c.r, c.g, c.b } end
        return { 1, 1, 1 }
    end
    if s.type == "interact" or s.type == "clear" or s.type == "click" then return { 0.85, 0.85, 0.85 } end
    return COLORS.buff
end
ns.ActionColor = actionColor  -- (tests)
local function render(s, cfg)
    -- New to Flow: the icon comes in at your first enemy (Reveal.lua). The
    -- key still casts the suggestion meanwhile.
    if ns.reveal and not ns.reveal:Shown("icon") then
        current = nil
        clearGlows()
        icon:Hide()
        return
    end
    if not s then
        current = nil
        clearGlows()
        if cfg.locked then icon:Hide() else
            icon.tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            icon.text:SetText("Shift-drag me")
            icon:Show()
        end
        return
    end

    local color = COLORS[s.kind] or actionColor(s)
    local tex = s.icon
    if not tex and s.spell then tex = select(2, A.SpellInfo(s.spell)) end
    icon.tex:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
    icon.border:SetColor(color[1], color[2], color[3])
    -- Flow Actions always say what the press does ("Equip your Fishing Pole").
    -- A buff for someone in your group says who it's for.
    icon.text:SetText(s.label or (s.target and ("on " .. s.target)) or (cfg.debug and s.reason) or "")
    local start, dur = cooldownOf(s)
    icon.cd:SetCooldown(start or 0, dur or 0)
    icon.timer:SetText(ns.CooldownText(start, dur, GetTime()))
    icon:Show()

    local key = tostring(s.spell or s.item or s.type) .. s.kind
    if key ~= current then
        current = key
        -- (A held spell isn't advice: no glow on your action bars.)
        if s.spell and s.kind ~= "held" then showGlows(s.spell, color, s.kind) else clearGlows() end
    end
end

local elapsed = 0
local function onUpdate(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.1 then return end
    elapsed = 0

    local cfg = ns.db.rotation
    if not cfg.enabled then
        E.shown = nil
        if icon:IsShown() then icon:Hide(); clearGlows(); current = nil end
        return
    end

    local ok, s = pcall(E.Evaluate, E)
    if not ok then
        -- Keep the error for /flow rot why; print it at most every 5s in debug.
        local now = GetTime()
        if cfg.debug and s ~= E.lastError and now - (E.lastErrorAt or 0) > 5 then
            ns:Print("rotation error: " .. tostring(s))
        end
        if s ~= E.lastError then ns:Log("rotation", s) end
        E.lastError, E.lastErrorAt = s, now
        s = nil
    end
    -- Out of combat, a Flow Action (equip the pole, cast Fishing...) when
    -- there's no spell to suggest, or before it when it's urgent (reel in).
    if not InCombatLockdown() and ns.actions then
        local okA, a = pcall(ns.actions.Current, ns.actions)
        if okA and a and (a.urgent or not s) then s = a end
    end
    E.shown = s   -- what the icon shows = what the key does (Cast.lua)
    -- Mid-fight with nothing new to press, the key still does what it was
    -- set to at the pull: show that, greyed, instead of an empty spot (the
    -- key never does something while the button looks gone).
    local view = s
    if not s and InCombatLockdown() and ns.cast and ns.cast.Held then view = ns.cast:Held() end
    local okR, err = pcall(render, view, cfg)
    if not okR then E.lastError, E.lastErrorAt = "display: " .. tostring(err), GetTime() end
    -- Swords badge while auto attack is on.
    local swinging = icon:IsShown() and A.Swinging()
    if swinging ~= icon.swing:IsShown() then
        icon.swing:SetShown(swinging)
        if swinging then icon.swing.pulse:Play() else icon.swing.pulse:Stop() end
    end
    -- On deck: only while there's a fight on or about to be (hostile target).
    local ctx = E.lastCtx
    local deck = {}
    if icon:IsShown() and ctx and (ctx.inCombat or ctx.hostile) and cfg.deck ~= false then
        local okD, d = pcall(E.OnDeck, E, #icon.deck, s and s.spell)
        if okD then deck = d end
    end
    local now = GetTime()
    for i, slot in ipairs(icon.deck) do
        local e = deck[i]
        slot.entry = e
        if e then
            local _, tex = A.SpellInfo(e.spell)
            slot.tex:SetTexture(tex)
            local start, dur = A.CooldownRaw(e.spell)
            local txt = ns.CooldownText(start, dur, now)
            slot.timer:SetText(txt)
            slot.tex:SetDesaturated(txt ~= "")
            slot:Show()
        else
            slot:Hide()
        end
    end
end

ns:OnLoad(function(saved)
    icon = buildIcon(saved.rotation)
    E.icon = icon  -- for the cast button (Cast.lua)
    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", ns.perf.Wrap("rotation + actions (10/s)", onUpdate))
end)

local function rescan()
    scanButtons()
    current = nil  -- force glows to re-apply to the new buttons
end

-- For /flow rot why: which action buttons hold this spell?
function E:ButtonsFor(spell)
    return buttonsBySpell[spell] or {}
end
for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "ACTIONBAR_SLOT_CHANGED",
                      "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
                      "UPDATE_SHAPESHIFT_FORMS", "SPELLS_CHANGED" }) do
    ns:On(ev, rescan)
end

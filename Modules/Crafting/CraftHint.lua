-- On the profession window: how many to make to reach the skill that's right
-- for you, and a "Make N" button that crafts exactly that many. When the
-- skill gets there, Flow says so (stop crafting) and names your next stop.
-- It shows the stop the faint profession arrow points to, where each
-- material comes from (bags, bank, smelting), and a fold-out list of the
-- upgrades you could make once you have their materials.
--
-- The button crafts through the game's own crafting call (DoTradeSkill /
-- C_TradeSkillUI.CraftRecipe) from your click. It doesn't touch the game's
-- quantity box, so no Blizzard frame is tainted.

local _, ns = ...
local A = ns.api
local H = {}
ns.craftHint = H

local GOLD = "|cffffd100"
local WIDTH = 340
local panel
H.upgradesOpen = false   -- the upgrades fold-out is open
local made = {}        -- recipe -> crafted since Flow suggested the count
local announced = {}   -- prof -> target already announced as reached
local lastCraftAt = 0  -- you crafted a planned recipe this recently (GetTime)

-- Which profession window is open (name), and its frame.
local function openProfession()
    local frame = (ProfessionsFrame and ProfessionsFrame:IsShown() and ProfessionsFrame)
        or (TradeSkillFrame and TradeSkillFrame:IsShown() and TradeSkillFrame)
    if not frame then return nil end
    local prof
    if GetTradeSkillLine then
        local ok, name = pcall(GetTradeSkillLine)
        if ok and name and name ~= "UNKNOWN" then prof = name end
    end
    if not prof and C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
        local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        prof = ok and info and info.professionName or nil
    end
    return prof, frame
end

-- The plan's craft stops for a profession (from the skill planner).
function H.CraftStops(prof)
    local out = {}
    for _, g in ipairs(ns.skillPlan and ns.skillPlan.lastStops or {}) do
        if g.recipe and g.prof == prof and not g.blockedBy then out[#out + 1] = g end
    end
    return out
end

-- Which of this window's stops to show: the one the faint profession arrow
-- points to, else the first one on the profession route, else the main
-- route, else the first. `choice`: { goal }; `profPlan`, `plan`: { { goal } }.
function H.Pick(stops, choice, profPlan, plan)
    local byKey = {}
    for _, g in ipairs(stops) do if g.key then byKey[g.key] = g end end
    local cg = choice and choice.goal
    if cg and cg.key and byKey[cg.key] then return byKey[cg.key] end
    for _, list in ipairs({ profPlan or {}, plan or {} }) do
        for _, st in ipairs(list) do
            local k = st.goal and st.goal.key
            if k and byKey[k] then return byKey[k] end
        end
    end
    return stops[1]
end

-- Where each material for `left` more of a stop comes from, one line each,
-- and how many you can make right now from your bags.
-- bagsOf / bankOf(id) -> count (tests); defaults: your bags and bank.
function H.MaterialLines(g, left, bagsOf, bankOf)
    local SP = ns.skillPlan
    local reagents = g.reagents
    if not reagents then
        local known = ns.recipes and ns.recipes:Known(g.prof)
        reagents = known and known[g.recipe] and known[g.recipe].reagents
    end
    if not (SP and reagents and next(reagents)) then return {}, left end
    bagsOf, bankOf = bagsOf or A.Count, bankOf or SP.BankCount
    local function smeltOf(id)
        local s = ns:Get("itemSource", id)
        return s and s.smelt
    end
    local function name(id)
        local s = ns:Get("itemSource", id)
        return (s and s.name) or (A.ItemInfo and A.ItemInfo(id)) or ("item " .. id)
    end
    local ids = {}
    for id in pairs(reagents) do ids[#ids + 1] = id end
    table.sort(ids)
    local st, lines, now = SP.Stock(bagsOf, bankOf, smeltOf), {}, left
    for _, id in ipairs(ids) do
        local q = reagents[id]
        local r = st:Take(id, q * left)
        lines[#lines + 1] = SP.SourceLine(name(id), r, r.from and name(r.from))
        now = math.min(now, math.floor((bagsOf(id) or 0) / q))
    end
    return lines, math.max(0, now)
end

-- The upgrades fold-out's lines: what each one still needs.
function H.UpgradeLines(list)
    local out = {}
    for _, u in ipairs(list or {}) do
        local what = u.unread and "open this window again so Flow can read all its materials"
            or ("needs " .. table.concat(u.missing or {}, ", "))
        out[#out + 1] = string.format("%s (%s): %s", u.link or u.recipe, u.tag or "", what)
    end
    return out
end

function H.ToggleUpgrades()
    H.upgradesOpen = not H.upgradesOpen
    if panel and panel:IsShown() then H:Refresh() end
end

-- The first route stop that isn't this one: "then go here".
function H.NextStop(exceptKey)
    for _, s in ipairs(ns.nav and ns.nav.plan or {}) do
        if s.goal.key ~= exceptKey and not (s.goal.key or ""):find("^craft:") then
            return s.goal.text or s.goal.title
        end
    end
end

-- Crafts n of a recipe by name, through the game's own call.
function H.Craft(recipe, n)
    if InCombatLockdown() then return false end
    if GetNumTradeSkills and GetTradeSkillInfo and DoTradeSkill then
        for i = 1, GetNumTradeSkills() do
            if GetTradeSkillInfo(i) == recipe then DoTradeSkill(i, n) return true end
        end
    end
    local T = C_TradeSkillUI
    if T and T.GetAllRecipeIDs and T.GetRecipeInfo and T.CraftRecipe then
        for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
            local info = T.GetRecipeInfo(id)
            if info and info.name == recipe then T.CraftRecipe(id, n) return true end
        end
    end
    return false
end

local function remaining(g)
    return math.max(0, (g.makeCount or 0) - (made[g.recipe] or 0))
end

local function tooltip(owner, g)
    ns.Tip(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(string.format("Make %s%d|r x %s", GOLD, remaining(g), g.recipe), 1, 1, 1)
    for _, d in ipairs(g.details or {}) do GameTooltip:AddLine(d, 0.8, 0.8, 0.8, true) end
    local nextStop = H.NextStop(g.key)
    if nextStop then GameTooltip:AddLine("Then: " .. nextStop, 0.6, 0.9, 1, true) end
    GameTooltip:Show()
end

local function build()
    panel = CreateFrame("Frame", "FlowCraftHint", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    panel:SetSize(WIDTH, 52)
    panel:SetFrameStrata("HIGH")
    if panel.SetBackdrop then
        panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        panel:SetBackdropColor(0.06, 0.05, 0.08, 0.92)
        local r = ns.theme.route
        panel:SetBackdropBorderColor(r[1], r[2], r[3], 1)
    end
    panel.text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.text:SetPoint("TOPLEFT", 8, -7); panel.text:SetPoint("RIGHT", -96, 0)
    panel.text:SetJustifyH("LEFT")
    panel.sub = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.sub:SetPoint("TOPLEFT", panel.text, "BOTTOMLEFT", 0, -3); panel.sub:SetPoint("RIGHT", -96, 0)
    panel.sub:SetJustifyH("LEFT")
    -- Where each material comes from (bags, bank, smelting).
    panel.mats = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.mats:SetPoint("TOPLEFT", panel.sub, "BOTTOMLEFT", 0, -4)
    panel.mats:SetWidth(WIDTH - 16)
    panel.mats:SetJustifyH("LEFT")
    local m = ns.theme.muted or { 0.75, 0.75, 0.75 }
    panel.mats:SetTextColor(m[1], m[2], m[3])
    -- The upgrades you lack materials for: folded away unless you open it.
    panel.upBtn = CreateFrame("Button", nil, panel)
    panel.upBtn:SetSize(WIDTH - 16, 14)
    panel.upBtn.label = panel.upBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.upBtn.label:SetPoint("LEFT")
    panel.upBtn:SetScript("OnClick", function() H.ToggleUpgrades() end)
    panel.ups = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.ups:SetPoint("TOPLEFT", panel.upBtn, "BOTTOMLEFT", 8, -2)
    panel.ups:SetWidth(WIDTH - 24)
    panel.ups:SetJustifyH("LEFT")
    panel.btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.btn:SetSize(84, 24); panel.btn:SetPoint("TOPRIGHT", -6, -6)
    panel.btn:SetScript("OnClick", function(self)
        local g, n = panel.goal, panel.makeNow or 0
        if g and n > 0 and not H.Craft(g.recipe, n) then
            ns:Print("Couldn't find " .. g.recipe .. " in this profession window.")
        end
    end)
    panel:EnableMouse(true)
    panel:SetScript("OnEnter", function(self) if self.goal then tooltip(self, self.goal) end end)
    panel:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.btn:SetScript("OnEnter", function() if panel.goal then tooltip(panel.btn, panel.goal) end end)
    panel.btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel:Hide()
end

-- The panel, built once (tests use it too).
function H.Panel()
    if not panel then build() end
    return panel
end

-- Lays out the material lines and the fold-out, and sizes the panel.
local function layout(matLines, upLines)
    panel.mats:SetText(table.concat(matLines, "\n"))
    local h = 7 + panel.text:GetStringHeight() + 3 + panel.sub:GetStringHeight() + 4
    if #matLines > 0 then h = h + panel.mats:GetStringHeight() + 4 end
    panel.upBtn:ClearAllPoints()
    if #upLines > 0 then
        panel.upBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -h)
        panel.upBtn.label:SetText(string.format("%s Upgrades you lack materials for (%d)",
            H.upgradesOpen and "[-]" or "[+]", #upLines))
        panel.upBtn:Show()
        h = h + 16
        if H.upgradesOpen then
            panel.ups:SetText(table.concat(upLines, "\n"))
            panel.ups:Show()
            h = h + panel.ups:GetStringHeight() + 4
        else
            panel.ups:Hide()
        end
    else
        panel.upBtn:Hide(); panel.ups:Hide()
    end
    panel:SetHeight(math.max(52, h + 6))
end

-- A new plan (after your bags change) already counts from what's left: start over.
local lastStops
local function onPlan()
    local stops = ns.skillPlan and ns.skillPlan.lastStops
    if stops ~= lastStops then lastStops = stops; wipe(made) end
end

function H:Refresh()
    onPlan()
    local prof, frame = openProfession()
    local stops = prof and H.CraftStops(prof) or {}
    local N = ns.nav or {}
    local g = H.Pick(stops, N.profChoice, N.profPlan, N.plan)
    local upLines = H.UpgradeLines(prof and ns.skillPlan and ns.skillPlan.lastUpgrades
        and ns.skillPlan.lastUpgrades[prof])
    if not (frame and (g or #upLines > 0)) then
        if panel then panel:Hide() end
        return
    end
    if not panel then build() end
    panel.goal = g
    panel.makeNow = 0
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -2)
    local rank = A.Skill(prof) or (g and g.rank)
    local matLines = {}
    if not g then
        panel.text:SetText("Flow: nothing to make here for your skill right now.")
        local nextStop = H.NextStop()
        panel.sub:SetText(nextStop and ("Next: " .. nextStop) or "")
        panel.btn:SetText("Make 0")
        panel.btn:Disable()
    elseif not g.extra and rank and g.target and rank >= g.target then
        panel.text:SetText(string.format("|cff40ff40Done:|r %s is %d, right for your level.", prof, rank))
        local nextStop = H.NextStop(g.key)
        panel.sub:SetText(nextStop and ("Next: " .. nextStop) or "Nothing more to make for now.")
        panel.btn:Disable()
    else
        local left = remaining(g)
        local now
        matLines, now = H.MaterialLines(g, left)
        panel.makeNow = now
        panel.text:SetText(string.format("Flow: make %s%d|r x %s", GOLD, left, g.recipe))
        panel.sub:SetText((g.extra == "upgrade" and "An upgrade for you, not needed for the skill (hover for more).")
            or (g.extra == "smelt" and string.format("Bars for your %s plan.", g.serves or "profession"))
            or string.format("%s %d -> %d. More would be wasted (hover for why).", prof, rank or 0, g.target or 0))
        if now < left and now == 0 then
            panel.sub:SetText(panel.sub:GetText() .. " Get the materials below first.")
        end
        panel.btn:SetText("Make " .. now)
        panel.btn:SetEnabled(now > 0)
    end
    layout(matLines, upLines)
    panel:Show()
end

-- The skill reached its target while you craft: say stop, and where next.
local function checkReached()
    for prof, t in pairs(ns.skillPlan and ns.skillPlan.lastTargets or {}) do
        local rank = A.Skill(prof)
        local crafting = GetTime() - lastCraftAt < 60
        if rank and t.target and rank >= t.target and crafting and announced[prof] ~= t.target then
            announced[prof] = t.target
            local nextStop = H.NextStop()
            local msg = string.format("Flow: %s is %d. That's enough for now, stop crafting.", prof, rank)
            ns:Print(msg .. (nextStop and ("  Next: " .. nextStop) or ""))
            if UIErrorsFrame then UIErrorsFrame:AddMessage(msg, 0.25, 1, 0.25) end
            if SOUNDKIT and SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01 then pcall(PlaySound, SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01) end
        end
    end
end

ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit ~= "player" then return end
    local name = A.SpellInfo(A.Safe(spellID) or 0)
    if not name then return end
    for _, g in ipairs(ns.skillPlan and ns.skillPlan.lastStops or {}) do
        if g.recipe == name then made[name] = (made[name] or 0) + 1; lastCraftAt = GetTime() end
    end
    if panel and panel:IsShown() then H:Refresh() end
end)


ns:On("SKILL_LINES_CHANGED", function() checkReached(); if panel and panel:IsShown() then H:Refresh() end end)
ns:On("CHAT_MSG_SKILL", function() C_Timer.After(0.2, checkReached) end)
for _, ev in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_UPDATE" }) do
    ns:On(ev, function() C_Timer.After(0.4, function() pcall(H.Refresh, H) end) end)
end
ns:On("TRADE_SKILL_CLOSE", function() if panel then panel:Hide() end end)

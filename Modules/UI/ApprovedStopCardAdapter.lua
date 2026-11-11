-- Flow's stop card (the window a click on a stop opens), drawn by the approved
-- glossy card in ApprovedStopCard.lua. Loads after Nav.lua, before Tests.lua.
-- This adapter only replaces Flow's owned ShowStop view. Route logic is unchanged.
local _, ns = ...
local N, UI, M = ns.nav, ns.approvedStopCard, ns.approvedStopCardModel
assert(N and UI and M, "Approved stop card: load Nav, model and renderer before the adapter")
local card

local function pointsFor(name)
    return ns.places and ns.places:Points(name) or {}
end
local function inLog(goal)
    local id = tonumber(tostring(goal.key or ""):match("^(%d+):"))
        or tonumber(tostring(goal.key or ""):match("^pickup:(%d+)$"))
    if not id then return false end
    local get = C_QuestLog and C_QuestLog.GetLogIndexForQuestID or GetQuestLogIndexByID
    if not get then return false end
    local ok, index = pcall(get, id)
    return ok and type(index) == "number" and index > 0
end
local function selectedPoint(goal)
    for _, stop in ipairs(N.plan or {}) do if stop.goal and stop.goal.key == goal.key then return stop.point end end
    -- A card outside the current plan may show its nearest known point; no route edit.
    local player = N:PlayerPos()
    local best, distance
    for _, p in ipairs(goal.points or {}) do
        if player and p.cont == player.cont and type(p.wx) == "number" and type(p.wy) == "number" then
            local d = (p.wx - player.wx) ^ 2 + (p.wy - player.wy) ^ 2
            if not distance or d < distance then best, distance = p, d end
        end
    end
    return best
end
local function make()
    if card then return card end
    -- Never overwrite a frame created by the previous renderer during a session.
    if _G.FlowStopCard then error("An older FlowStopCard already exists: restart/reload after loading the adapter in the TOC") end
    card = UI.Create(UIParent, {
        name = "FlowStopCard",
        savePoint = function(p) ns.db.nav.cardPoint = p end,
        onError = function(err) ns:Log("stop-card", err) end,
    })
    if UISpecialFrames then table.insert(UISpecialFrames, "FlowStopCard") end
    return card
end

-- Keep the original callable for a deliberate rollback; do not run both renderers.
N.legacyShowStop = N.ShowStop
function N:ShowStop(goal, anchor)
    if not goal then return end
    if GameTooltip then GameTooltip:Hide() end   -- the card says it all: the hover tooltip would just cover it
    local f = make()
    if f:IsShown() and f.goal and f.goal.key == goal.key then f:Hide(); return end
    local actions = {}
    if inLog(goal) then
        actions[#actions + 1] = { label = "Select in quest log", callback = function() self:OpenInGame(goal) end }
    end
    actions[#actions + 1] = { label = "Show on map", callback = function()
        if ns.mapOverlay then ns.mapOverlay:Focus(goal.key, 20) end
        if not (WorldMapFrame and WorldMapFrame:IsShown()) then ns:Print("press M: Flow highlights this stop on your map.") end
    end }
    actions[#actions + 1] = { label = "Go here next", primary = true, enabled = not goal.blockedBy,
        callback = function() self:Select(goal.key); f:Hide() end }
    local kind = ns.theme and ns.theme.kinds and ns.theme.kinds[self:StopKind(goal)]
    local point = selectedPoint(goal)
    local distance
    local player = self:PlayerPos()
    if player and point and type(point.wx) == "number" and type(point.wy) == "number" and point.cont == player.cont then
        distance = string.format("%d yd", math.sqrt((point.wx - player.wx) ^ 2 + (point.wy - player.wy) ^ 2))
    end
    local model = M.Build(goal, point, { pointsFor = pointsFor, category = kind and kind.label, actions = actions,
        distance = distance })
    -- Preserve other current quest objectives as structured body rows.
    local id = tonumber(tostring(goal.key or ""):match("^(%d+):"))
    if id and C_QuestLog and C_QuestLog.GetQuestObjectives then
        local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, id)
        local function plain(s) return tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", "") end
        if ok and type(objectives) == "table" then
            local seen = { [plain(model.title)] = true }
            for _, line in ipairs(model.details) do seen[plain(line)] = true end
            for _, objective in ipairs(objectives) do
                if type(objective.text) == "string" and not seen[plain(objective.text)] then
                    model.details[#model.details + 1] = objective.text
                    seen[plain(objective.text)] = true
                end
            end
        end
    end
    -- The profession's own icon: the one Flow's bags use, else the spell's.
    if model.profession then
        local known = ns.disposition and ns.disposition.PROF_ICON and ns.disposition.PROF_ICON[model.profession]
        if known then model.icon = known
        elseif ns.api and ns.api.SpellInfo then
            local ok, _, icon = pcall(ns.api.SpellInfo, model.profession)
            if ok and icon then model.icon = icon end
        end
    end
    if not model.icon and not model.profession then model.icon = kind and kind.icon end
    f.goal = goal; f:SetModel(model); f:ClearAllPoints()
    local saved = ns.db.nav.cardPoint
    if saved then f:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
    else
        local placed = ns.PlaceAtTipSpot and ns.PlaceAtTipSpot(f, anchor or UIParent)
        if not placed and anchor and anchor.GetRight and anchor:GetRight() then
            -- Beside what you clicked, on whichever side has room.
            local right = anchor:GetRight() * anchor:GetEffectiveScale() / UIParent:GetEffectiveScale()
            if right + f:GetWidth() + 8 > GetScreenWidth() then f:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -8, 0)
            else f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0) end
        elseif not placed then f:SetPoint("CENTER", UIParent, "CENTER", 0, 40) end
    end
    f:Show()
end

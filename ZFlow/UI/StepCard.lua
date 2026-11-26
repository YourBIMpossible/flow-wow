local _, ns = ...

-- The step card (parity row A1-13): a small window that shows the card
-- for one route step and lets the player act on it. The data half is
-- Nav/StepCard.lua (Zen-3): SC.Card(step, facts) gives the title, the
-- sub (the objective, or "Hand the quest in"), the distance as the
-- caller gave it, the body lines and three actions in order (Quest
-- log, Map, Do this next), each with its why when it is off; SC.Run
-- gives the call a click makes. This file only draws that card and
-- makes the calls; it computes nothing about the step itself.
--
--   M.Declare(k, diag) -> api     api.Toggle(step, facts, anchor),
--                                 api.Close(), api.Shown()
--   ns.stepCard                   the same api, declared at load.
--
-- Toggle is the one call the arrow's left-click hook makes (the hook
-- itself is the lead's patch to UI/Arrow.lua; it is named as a LEAD
-- NEED in this slice's READY). The hook passes the current step as
-- Nav/TripRoute.lua's View()/Current() gives it, the facts it already
-- read (inLog, distance, index — all optional) and, when it can, the
-- arrow's own rectangle on screen ({ left, bottom, width, height },
-- UIParent coordinates) so the card can open beside the arrow. The
-- window fills the facts it owns: canSelectQuest from the client
-- (lead section 828) and canFirst from the tripRoute module; a
-- missing inLog is read from the client's quest log.
--
-- Behaviour (agreed with the owner, 2026-11-25): the card opens
-- beside the arrow, on the side with room; once the player drags it,
-- the place it was left in wins (nav.cardPoint, char, no default —
-- nil means "beside the arrow"). It stays open until it is closed:
-- Escape, the close button, a second Toggle for the same step, or
-- Do this next (the route re-plans, so the card's step is stale).
-- A Toggle for a different step redraws the card for that step.
--
-- A click calls SC.Run and makes the call it gives, and nothing
-- else: the Quest log button calls client.selectQuest (it never
-- opens the quest log window itself — that would taint), the Map
-- button calls client.showMap, Do this next calls tripRoute.First.
-- A button that is off is drawn greyed with its why as its tooltip.
-- Not tested in game.

local M = {}
ns.StepCard = M

M.NAME = "stepCard"
M.ID = "stepCard"
M.WIDTH = 340        -- the card's width; Flow's anchor check uses 350
M.HEIGHT = 200       -- where the height starts; the window fits its parts
M.GAP = 8            -- the gap between the arrow and the card
M.PLACE_KEY = "nav.cardPoint"
M.PATH = "layout.stepCard"
M.LABEL = "Step card place"
M.SYNONYMS = { "step", "card", "place", "position", "move" }

-- One step is the same step when its quest and its label agree. The
-- route hands out a fresh table for a step on every read, so the
-- tables themselves never match.
function M.StepKey(step)
    if type(step) ~= "table" then return "" end
    return tostring(step.quest) .. "|" .. tostring(step.label)
end

-- The card's first place, beside the arrow: hanging from its top
-- left, its top aligned with the arrow's top, on the arrow's right
-- when the card fits there and on its left when it does not, clamped
-- to the screen. anchor is the arrow's rectangle ({ left, bottom,
-- width, height }, UIParent coordinates, y up from the bottom);
-- screenW/screenH are the screen's size. nil when either is unusable
-- (the window then opens at its own default place).
function M.BesidePoint(anchor, screenW, screenH)
    if type(anchor) ~= "table" then return nil end
    if type(screenW) ~= "number" or type(screenH) ~= "number" then return nil end
    if type(anchor.left) ~= "number" or type(anchor.bottom) ~= "number"
        or type(anchor.width) ~= "number" or type(anchor.height) ~= "number" then
        return nil
    end
    local x = anchor.left + anchor.width + M.GAP
    if x + M.WIDTH > screenW then x = anchor.left - M.GAP - M.WIDTH end
    if x < 0 then x = 0 end
    if x + M.WIDTH > screenW then x = math.max(0, screenW - M.WIDTH) end
    local y = anchor.bottom + anchor.height
    if y > screenH then y = screenH end
    if y - M.HEIGHT < 0 then y = M.HEIGHT end
    return { "TOPLEFT", "BOTTOMLEFT", x, y }
end

function M.Declare(k, diag)
    local api = {}
    local ctx, handle
    local current   -- { step, facts, key } for the step the card shows

    local function client()
        if ctx and ctx.client then return ctx.client end
        return k.client
    end

    local function problems(what, why)
        if k.problems and k.problems.add then k.problems:add(M.NAME, what, tostring(why)) end
    end

    local function settings()
        if ctx and ctx.settings then return ctx.settings end
        return k.settings
    end

    local function savedPlace()
        local s = settings()
        if type(s) ~= "table" or type(s.get) ~= "function" then return nil end
        local ok, v = pcall(s.get, s, M.PLACE_KEY)
        if ok and type(v) == "table" then return v end
        return nil
    end

    local function savePlace(at)
        local s = settings()
        if type(s) ~= "table" or type(s.set) ~= "function" then return end
        local ok, why = pcall(s.set, s, M.PLACE_KEY,
            { point = { at[1], at[2], at[3], at[4] } })
        if not ok then problems("place", why) end
    end

    -- The facts the window owns, filled over a copy of the caller's.
    local function factsOf(facts, c)
        local f = {}
        if type(facts) == "table" then
            for key, v in pairs(facts) do f[key] = v end
        end
        if type(c) == "table" and type(c.selectQuest) == "function" then
            f.canSelectQuest = true
        else
            f.canSelectQuest = false
        end
        local SC = ns.Nav and ns.Nav.StepCard
        local route = k.use and k.use("tripRoute")
        if type(SC) == "table" and type(SC.CanFirst) == "function" then
            f.canFirst = SC.CanFirst(route)
        else
            f.canFirst = false
        end
        if f.inLog == nil and type(c) == "table" and type(c.questLog) == "function" then
            local ok, rows = pcall(c.questLog)
            if ok and type(rows) == "table" then
                local set = {}
                for _, row in ipairs(rows) do
                    if type(row) == "table" and type(row.id) == "number" then
                        set[row.id] = true
                    end
                end
                f.inLog = set
            end
        end
        return f
    end

    -- A button's click: SC.Run's call, made and nothing more.
    local function run(action)
        if not current then return end
        local SC = ns.Nav and ns.Nav.StepCard
        if type(SC) ~= "table" or type(SC.Run) ~= "function" then return end
        local call = SC.Run(action.key, current.step, current.facts)
        if type(call) ~= "table" then return end
        local c = client()
        if call.call == "questLog" then
            if type(c) == "table" and type(c.selectQuest) == "function" then
                pcall(c.selectQuest, call.quest)
            end
        elseif call.call == "showMap" then
            if type(c) == "table" and type(c.showMap) == "function" then
                pcall(c.showMap, call.map)
            end
        elseif call.call == "first" then
            local route = k.use and k.use("tripRoute")
            if type(route) == "table" and type(route.First) == "function" then
                pcall(route.First, call.index)
            end
            api.Close()
        end
    end

    local function tree(card, point)
        local children = { { kind = "header", title = card.title } }
        if card.sub ~= nil or card.distance ~= nil then
            local line = { kind = "line", key = "sub" }
            if card.sub ~= nil then
                line.text = card.sub
                line.right = card.distance
            else
                line.text = card.distance
            end
            children[#children + 1] = line
        end
        for i, s in ipairs(card.lines) do
            children[#children + 1] = { kind = "line", key = "line" .. i, text = s, wrap = true }
        end
        local buttons = {}
        for _, a in ipairs(card.actions) do
            local action = a
            buttons[#buttons + 1] = { kind = "button", key = "act." .. action.key,
                text = action.label, enabled = action.enabled, tooltip = action.why,
                onClick = function() run(action) end }
        end
        children[#children + 1] = { kind = "footer", buttons = buttons }
        local spec = { id = M.ID, title = card.title, width = M.WIDTH, height = M.HEIGHT,
            fit = true, movable = true, closable = true, escape = true, children = children }
        if point ~= nil then spec.point = point end
        return ns.Kit.Window(spec)
    end

    local function draw(card, anchor)
        local c = client()
        local saved = savedPlace()
        local beside
        if type(saved) ~= "table" and anchor ~= nil and type(c) == "table"
            and type(c.screen) == "function" then
            local ok, w, h = pcall(c.screen)
            if ok then beside = M.BesidePoint(anchor, w, h) end
        end
        local t, why = tree(card, beside)
        if not t then
            problems("tree", why)
            return false
        end
        local point, width, height = ns.Kit.Place(saved, t)
        if handle then
            handle.update(t)
            handle.show(true)
            return true
        end
        local prefix = ""
        if k.id and type(k.id.framePrefix) == "string" then prefix = k.id.framePrefix end
        handle = c.kitWindow(M.ID, t, {
            name = prefix .. "StepCard",
            point = point, width = width, height = height,
            onMoved = function(at)
                if type(at) == "table" then savePlace(at) end
            end,
            onClose = function() end,
            failed = function(err) problems("draw", err) end,
        })
        if not handle then
            problems("window", "the client could not draw the window")
            return false
        end
        handle.show(true)
        return true
    end

    -- Opens the card for the step, closes it when it already shows
    -- that step, and redraws it when the step has changed. True when
    -- the card was opened, closed or redrawn.
    function api.Toggle(step, facts, anchor)
        local c = client()
        if type(c) ~= "table" or type(c.kitWindow) ~= "function" then return false end
        if type(step) ~= "table" then return false end
        local key = M.StepKey(step)
        if api.Shown() and current and current.key == key then
            api.Close()
            return true
        end
        local SC = ns.Nav and ns.Nav.StepCard
        if type(SC) ~= "table" or type(SC.Card) ~= "function" then return false end
        local f = factsOf(facts, c)
        local card = SC.Card(step, f)
        if not card then return false end
        current = { step = step, facts = f, key = key }
        return draw(card, anchor)
    end

    function api.Close()
        if handle then handle.close() end
    end

    function api.Shown()
        return handle ~= nil and handle.shown() == true
    end

    k:Setting({ key = M.PLACE_KEY, scope = "char", type = "table", path = M.PATH,
        keepOnResetAll = true, group = "general.windows", label = M.LABEL,
        synonyms = M.SYNONYMS })

    k:Module({
        name = M.NAME,
        needs = { "client", "settings" },
        provides = { Toggle = api.Toggle, Close = api.Close, Shown = api.Shown },
        start = function(c) ctx = c end,
    })

    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.stepCard = M.Declare(ns, ns.diag)

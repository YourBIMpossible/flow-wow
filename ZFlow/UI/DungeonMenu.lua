-- The Dungeon Quests menu (DISPATCH §652, slice 1): the card grid of
-- dungeons, the detail view with the B-55 badge and the Solo/Group toggle,
-- and the Quests tab. Data only from Nav/DungeonStates.lua and
-- Nav/DungeonRead.lua, plus the dungeonVisit api.Ratio for the badge
-- (B-55, 44427648; a stub here until it merges, one function below).
--
-- The card grid is a scroll of dungeon cards (one column): the kit has no
-- multi-column grid part, and the client that draws the kit is hands-off,
-- so a left/right layout with a text-only topic list would lose the mini
-- badge on every row. The grid stands above the detail view; the detail
-- view is the picked dungeon's heading, its facts and badge, the Solo/Group
-- toggle, and the Quests tab.
--
-- Built from the kit's parts only (UI/Kit.lua, drawn by client.kitWindow):
-- this file names no template, colour, font or size, and works out nothing:
-- the states, groups, chain lines, search, entrance and run are
-- Nav/DungeonStates.lua's and Nav/DungeonRead.lua's. The badge is drawn
-- from the ratio only: the text, the tone and the tip.
--
-- LOOK ONLY, apart from the waypoint the player asks for with the button:
-- nothing is accepted, targeted, cast or clicked for the player. The badge
-- has no click here: preparing or cancelling a run needs the dungeonRun
-- module, which is not loaded; the badge is a display until then.
--
--   M.Declare(k, diag) -> api     api.Open(), api.Close(), api.Shown()
--   M.Badge(ratio, solo) -> { text, tone }   pure: "?" or "N.Nx", "good" | "muted"
--   M.BadgeTip(solo) -> "Needs a group." | nil   pure
--   M.LineTone(tone) -> the kit's tone for a badge tone, or nil   pure
-- Its place is kept, account wide, at M.PATH. The merge hook that opens
-- this window (the slash word, the arrow menu) is the lead's
-- (DungeonMenu.Section); this file registers no word of its own.
-- Not tested in game.
local _, ns = ...

local M = {}
-- ns.DungeonMenu is Nav/DungeonMenu.lua's (B-53, the arrow menu's section);
-- this window's table has its own name so neither hides the other.
ns.DungeonMenuWindow = M

M.NAME = "dungeonMenu"
M.ID = "dungeonMenu"
M.HEADER = "Dungeon Quests"
M.SEARCH = "Search dungeons"
M.SHOW_ON_MAP = "Show on map"
-- P-TRIP (S40): hands the dungeon run (Nav/DungeonRead.lua R.Run) to the
-- route (Nav/TripRoute.lua), which the quest arrow walks. Quests tab only.
-- B-52: with "Get ready" steps before it (R.Ready) for training due, a
-- repair and a bank the player has seen.
M.PLAN_RUN = "Plan the run"
M.NO_ROUTE = "Routes are not loaded."
-- Where the window was left, account wide: { point, width, height }
-- (Twin review 18:06, F1). Read back through ns.Kit.Place.
M.PATH = "layout.dungeonMenu"
-- The card grid's height: the window is taller than the old one, so the
-- grid and the Quests pane both fit.
M.GRID_HEIGHT = 180
-- B-55 (FLOW-PARITY): the badge's words, as Nav/DungeonBadge.lua has them.
M.NEEDS_GROUP = "Needs a group."
M.UNKNOWN = "?"
-- The Solo/Group toggle, as the mock has it in the detail view.
M.PARTY = { "Solo", "Group" }

-- The tone a group's lines are drawn in (the kit's three words).
local TONE = { log = "good", later = "warn", notforyou = "bad" }
-- The kit's quest picture for a group's lines, by its name in Kit.look.icon.
local ICON = { log = "questInLog", pickup = "questAvailable", inside = "questAvailable",
    later = "questLater", notforyou = "questNotForYou" }

local function iconOf(group)
    local icons = ns.Kit and ns.Kit.look and ns.Kit.look.icon
    if type(icons) == "table" then return icons[ICON[group]] end
    return nil
end

local function join(a, b)
    if a and b then return a .. " · " .. b end
    return a or b
end

-- The dungeonVisit api.Ratio read (B-55, FLOW-PARITY): the measured
-- clear-speed ratio for a dungeon by name, or nil when unmeasured or the
-- module is not loaded. One function, so it switches to the real api when
-- B-55 merges (fork branch zflow-zen3-b55, tip 44427648, batch 3). The
-- ratio is by name, as Nav/DungeonBadge.lua B.Build reads it.
-- B-55 NEED: dungeonVisit.Ratio is not on the base yet, so the pcall below
-- hides any mismatch as "?". The end-to-end test against the real module
-- comes after B-55 lands; that is not this slice's job.
local function dungeonVisitRatio(k, name)
    local visit = k.use and k.use("dungeonVisit")
    if type(visit) ~= "table" or type(visit.Ratio) ~= "function" then return nil end
    local ok, v = pcall(visit.Ratio, name)
    if ok and type(v) == "number" and v == v and v > 0 and v ~= math.huge then return v end
    return nil
end

-- The badge (B-55, as Nav/DungeonBadge.lua B.Status draws it): the text is
-- the ratio as "N.Nx", or "?" when never measured; the tone is "good", or
-- "muted" when solo. A run never measured is never suggested, only "?".
function M.Badge(ratio, solo)
    local text = M.UNKNOWN
    if type(ratio) == "number" and ratio == ratio and ratio > 0 and ratio ~= math.huge then
        text = string.format("%.1fx", ratio)
    end
    return { text = text, tone = solo == true and "muted" or "good" }
end

-- The badge's tip: only "Needs a group." when solo; the ratio lines come
-- from the measured run (Nav/DungeonVisit.lua) and are not read here.
function M.BadgeTip(solo)
    if solo == true then return M.NEEDS_GROUP end
    return nil
end

-- The kit's tone for a badge tone: the kit draws "good", "warn" and "bad"
-- only, so a muted badge carries no tone.
function M.LineTone(tone)
    if tone == "good" then return "good" end
    return nil
end

function M.Declare(k, diag)
    local api = {}
    local ctx, handle
    local st
    local view = { search = "", pick = nil, solo = true, folded = {}, said = nil, reads = 0 }
    local cancelStep
    local render

    local R, S = ns.DungeonRead, ns.DungeonStates
    local id = k.id or ns.id

    local function client() return ctx and ctx.client or k.client end

    -- The reader's index, built in slices out of the way of the frame.
    local function index()
        if st and st.state ~= "failed" and st.state ~= "noquestie" then return end
        st = R.Start(client())
        if st.state == "building" and ctx and ctx.sched then
            cancelStep = ctx.sched:every(M.NAME, 0.05, function()
                R.Step(st, client(), R.SLICE)
                if st.state ~= "building" then
                    if cancelStep then cancelStep() end
                    cancelStep = nil
                    if render then render() end
                end
            end)
        end
    end

    local function picked(list)
        for i, d in ipairs(list) do
            if d.key == view.pick then return i, d end
        end
        if list[1] then
            view.pick = list[1].key
            return 1, list[1]
        end
        return nil, nil
    end

    local function empty(why) return { kind = "empty", key = "empty", text = why[1], how = why[2] } end

    local function showOnMap(d)
        local e, why = R.Entrance(st, client(), d and d.key)
        if not e then
            view.said = why[1]
            return
        end
        local Wp = ns.Nav.Waypoint
        local wp, reason = Wp.Set(Wp.Slot(k.store), { map = e.map }, e.text)
        view.said = wp and ("Waypoint set: " .. tostring(Wp.Text(wp)) .. ".") or (tostring(reason) .. ".")
    end

    -- FLOW-PARITY B-52 (lead section 471, from lane B's route-b 464899f6):
    -- "Get ready on the way". The steps to put before a run, read when the
    -- button is pressed: training due (Nav/ClassTrainerStep.lua), a repair
    -- while the gear is low (Nav/RepairStep.lua), and the nearest bank the
    -- player has seen on this map (Nav/Errand.lua). A module that is not
    -- loaded or a read that raises gives no step. Look only.
    local function readySteps()
        local function stepOf(name)
            local m = k.use and k.use(name)
            if type(m) ~= "table" or type(m.Step) ~= "function" then return nil end
            local ok, v = pcall(m.Step)
            if ok then return v end
            return nil
        end
        -- The errand module is ns.Errand (Nav/Errand.lua), not under ns.Nav:
        -- asked under the wrong name the bank was never found (White, lead
        -- section 539).
        local E = ns.Errand
        local bank
        if type(E) == "table" and type(E.Find) == "function" then
            local ok, v = pcall(E.Find, "banker", client(), k.store)
            if ok then bank = v end
        end
        if type(R.Ready) ~= "function" then return {} end
        return R.Ready(stepOf("classTrainerStep"), stepOf("repairStep"), bank)
    end

    local function planRun(d)
        local run, why = R.Run(st, client(), d and d.key)
        if not run then
            view.said = why[1]
            return
        end
        local trip = k.use and k.use(ns.Nav.TripRoute.NAME)
        if not trip or type(trip.Run) ~= "function" then
            view.said = M.NO_ROUTE
            return
        end
        -- B-52: the get-ready steps go first; the player does each.
        local ready = readySteps()
        if #ready > 0 then
            local steps = {}
            for _, s in ipairs(ready) do steps[#steps + 1] = s end
            for _, s in ipairs(run.steps) do steps[#steps + 1] = s end
            run.steps = steps
        end
        view.said = trip.Run(run)
    end

    local function footer(d)
        local e = R.Entrance(st, client(), d and d.key)
        local showTip = nil
        if e == nil then showTip = R.WHY_NO_ENTRANCE[1] end
        local buttons = { { kind = "button", key = "showOnMap", text = M.SHOW_ON_MAP, enabled = e ~= nil,
                tooltip = showTip,
                onClick = function()
                    showOnMap(d)
                    render()
                end } }
        local run, why = R.Run(st, client(), d and d.key)
        local planTip = nil
        if run == nil and why then planTip = why[1] end
        buttons[#buttons + 1] = { kind = "button", key = "planRun", text = M.PLAN_RUN, enabled = run ~= nil,
            tooltip = planTip,
            onClick = function()
                planRun(d)
                render()
            end }
        return { kind = "footer", key = "footer", text = view.said or "", buttons = buttons }
    end

    -- The card grid: one card per dungeon, in level order. A card is a
    -- line: the name, the level range and the quest count under it, and the
    -- B-55 badge at the right ("N.Nx" for a measured run, "?" otherwise).
    local function cardGrid(list, out)
        local cards = {}
        for _, d in ipairs(list) do
            local badge = M.Badge(dungeonVisitRatio(k, d.name), view.solo)
            cards[#cards + 1] = { kind = "line", key = "dungeon." .. tostring(d.key), text = d.name,
                sub = join(S.LevelText(d), S.CountText(#d.ids)),
                right = badge.text, tone = M.LineTone(badge.tone),
                onClick = function()
                    view.pick, view.said, view.reads = d.key, nil, 0
                    render()
                end }
        end
        out[#out + 1] = { kind = "scroll", key = "dungeons", height = M.GRID_HEIGHT, children = cards }
    end

    -- The detail view for the picked dungeon: its name as the page heading,
    -- its facts and badge, and the Solo/Group toggle.
    local function detail(d, out)
        out[#out + 1] = { kind = "section", key = "detail", text = d.name, big = true }
        local badge = M.Badge(dungeonVisitRatio(k, d.name), view.solo)
        out[#out + 1] = { kind = "line", key = "facts", text = S.LevelText(d) or "Level unknown",
            sub = S.CountText(#d.ids), right = badge.text, tone = M.LineTone(badge.tone),
            tooltip = M.BadgeTip(view.solo) }
        out[#out + 1] = { kind = "choice", key = "party", items = M.PARTY, selected = view.solo and 1 or 2,
            drop = true, onSelect = function(i)
                view.solo = (i == 1)
                render()
            end }
    end

    local function questsPane(d, out)
        local pane = R.Pane(st, client(), d.key)
        if pane.why then
            out[#out + 1] = empty(pane.why)
            return
        end
        local rows = {}
        for _, g in ipairs(pane.groups) do
            if #g.rows > 0 then
                local folded = view.folded[g.id]
                if folded == nil then folded = g.folded == true end
                rows[#rows + 1] = { kind = "section", key = "group." .. g.id,
                    text = g.title .. " (" .. #g.rows .. ")", folded = folded,
                    onFold = function(now)
                        view.folded[g.id] = now
                        render()
                    end }
                if not folded then
                    for _, r in ipairs(g.rows) do
                        local levelText = nil
                        if r.level then levelText = "Level " .. tostring(r.level) end
                        rows[#rows + 1] = { kind = "line", text = r.name, icon = iconOf(g.id),
                            sub = join(join(r.chain, r.note), r.next),
                            right = levelText, tone = TONE[g.id] }
                    end
                end
            end
        end
        out[#out + 1] = { kind = "scroll", key = "quests", children = rows }
    end

    local function tree()
        local children = {
            { kind = "header", key = "header", title = M.HEADER,
              search = { placeholder = M.SEARCH, text = view.search, onText = function(text)
                  view.search = type(text) == "string" and text or ""
                  view.pick = nil
                  render()
              end } },
        }
        if not st or st.state ~= "ready" then
            local pane = R.Pane(st, client(), nil)
            children[#children + 1] = empty(pane.why or S.WHY.noDungeon)
        else
            local list = R.Search(R.List(st), view.search)
            cardGrid(list, children)
            local _, d = picked(list)
            if not d then
                children[#children + 1] = empty(#R.List(st) == 0 and S.WHY.noQuests or R.WHY_NO_MATCH)
            else
                detail(d, children)
                questsPane(d, children)
                children[#children + 1] = footer(d)
            end
        end
        -- It lists dungeons, so it can be resized, also on the first draw before
        -- the list is read (its saved size is given back then too).
        return ns.Kit.Window({ id = M.ID, title = id.title .. ": " .. M.HEADER, resizable = true,
            width = 460, height = 620, children = children })
    end

    render = function()
        if not handle then return end
        local t, why = tree()
        if not t then
            k.problems:add(M.NAME, "tree", tostring(why))
            return
        end
        handle.update(t)
    end

    function api.Open()
        local c = client()
        if type(c) ~= "table" or type(c.kitWindow) ~= "function" then return false end
        index()
        local t, why = tree()
        if not t then
            k.problems:add(M.NAME, "tree", tostring(why))
            return false
        end
        if not handle then
            -- A name of its own: the game's Escape list closes a named
            -- window (the kit wires it); its place is kept when moved.
            local point, width, height = ns.Kit.Place(k.store:get("account", M.PATH), t)
            handle = c.kitWindow(M.ID, t, {
                name = id.framePrefix .. "DungeonMenu",
                point = point, width = width, height = height,
                onMoved = function(at, w, h)
                    if type(at) ~= "table" then return end
                    local ok, why = k.store:set("account", M.PATH,
                        { point = { at[1], at[2], at[3], at[4] }, width = w, height = h })
                    if not ok then k.problems:add(M.NAME, "place", tostring(why)) end
                end,
                onClose = function() end,
                failed = function(err) k.problems:add(M.NAME, "draw", tostring(err)) end,
            })
            if not handle then
                k.problems:add(M.NAME, "window", "the client could not draw the window")
                return false
            end
        else
            handle.update(t)
        end
        handle.show(true)
        return true
    end

    function api.Close()
        if handle then handle.close() end
    end

    function api.Shown()
        return handle ~= nil and handle.shown() == true
    end

    k:Module({
        name = M.NAME,
        needs = { "client", "store", "sched" },
        provides = { Open = api.Open, Close = api.Close, Shown = api.Shown },
        start = function(c) ctx = c end,
        stop = function()
            if cancelStep then cancelStep() end
            cancelStep = nil
            if handle then handle.close() end
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.dungeonMenu = M.Declare(ns, ns.diag)

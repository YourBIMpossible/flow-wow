-- The Dungeon Quests window (lead sections 303 item 6 and 318). Left: the
-- dungeons in level order with a search in the header. Right: three tabs,
-- Quests (first), Bosses and Map. Quests: the five groups of
-- Nav/DungeonStates.lua, "Not for you" folded, one line per quest with its
-- level, "Step n of m" and "Available at Level X". Show on map sets the
-- player's own waypoint (Nav/Waypoint.lua) at the dungeon's entrance.
-- Bosses: every boss of the dungeon and what it can drop, with the drops
-- this account saw marked (Nav/DungeonRead.lua R.Loot, lead DISPATCH 426).
-- Each dungeon in the list carries its level range; a summary line above
-- the tabs names the picked one, its range and its quest count.
-- Every empty pane says what is missing and how to get it.
--
-- Built from the kit's parts only (UI/Kit.lua, drawn by client.kitWindow):
-- this file names no template, colour, font or size, and works out nothing:
-- the states, groups, chain lines, search, entrance and loot are
-- Nav/DungeonStates.lua's and Nav/DungeonRead.lua's.
--
-- LOOK ONLY, apart from the waypoint the player asks for with the button:
-- nothing is accepted, targeted, cast or clicked for the player.
--
--   W.Declare(k, diag) -> api     api.Open(), api.Close(), api.Shown()
--   `<slash> dungeons` opens it; so does the arrow menu's row
--   (UI/ArrowMenu.lua M.WINDOWS).
-- Its place is kept, account wide, at W.PATH.
-- Each quest line carries the kit's quest picture for its group
-- (Kit.look.icon, UI/Kit/Theme.lua); this file names no picture itself.
-- Not tested in game.
local _, ns = ...

local W = {}
ns.DungeonWindow = W

W.NAME = "dungeonWindow"
W.ID = "dungeons"
W.WORD = "dungeons"
W.HELP = "open the Dungeon Quests window"
W.HEADER = "Dungeon Quests"
W.SEARCH = "Search dungeons"
W.TABS = { "Quests", "Bosses", "Map" }
W.SHOW_ON_MAP = "Show on map"
-- P-TRIP (S40): hands the dungeon run (Nav/DungeonRead.lua R.Run) to the
-- route (Nav/TripRoute.lua), which the quest arrow walks. Quests tab only.
-- B-52: with "Get ready" steps before it (R.Ready) for training due, a
-- repair and a bank the player has seen.
W.PLAN_RUN = "Plan the run"
W.NO_ROUTE = "Routes are not loaded."
W.BOSS_LOOT = "learned.bossLoot"   -- account, UI/BossLoot.lua
W.DROPS = "learned.drops"          -- character, Items/Drops.lua
-- Where the window was left, account wide: { point, width, height }
-- (Twin review 18:06, F1). Read back through ns.Kit.Place.
W.PATH = "layout.dungeonWindow"
-- Bosses tab: item names not read yet are asked again this many times, this
-- many seconds apart, for each dungeon picked.
W.READ_TRIES = 5
W.READ_WAIT = 1

-- The tone a group's lines are drawn in (the kit's three words).
local TONE = { log = "good", later = "warn", notforyou = "bad" }
-- The kit's quest picture for a group's lines, by its name in Kit.look.icon.
local ICON = { log = "questInLog", pickup = "questAvailable", inside = "questAvailable",
    later = "questLater", notforyou = "questNotForYou" }

local function iconOf(group)
    local icons = ns.Kit and ns.Kit.look and ns.Kit.look.icon
    return type(icons) == "table" and icons[ICON[group]] or nil
end

local function join(a, b)
    if a and b then return a .. " · " .. b end
    return a or b
end

function W.Declare(k, diag)
    local api = {}
    local ctx, handle
    local st
    local view = { search = "", pick = nil, tab = 1, folded = {}, said = nil, reads = 0 }
    local cancelStep, cancelRead
    local render

    local R, S = ns.DungeonRead, ns.DungeonStates
    local id = k.id or ns.id

    local function client() return ctx and ctx.client or k.client end

    -- The reader's index, built in slices out of the way of the frame.
    local function index()
        if st and st.state ~= "failed" and st.state ~= "noquestie" then return end
        st = R.Start(client())
        if st.state == "building" and ctx and ctx.sched then
            cancelStep = ctx.sched:every(W.NAME, 0.05, function()
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
        local E = ns.Nav and ns.Nav.Errand
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
            view.said = W.NO_ROUTE
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
        local buttons = { { kind = "button", key = "showOnMap", text = W.SHOW_ON_MAP, enabled = e ~= nil,
                tooltip = e == nil and R.WHY_NO_ENTRANCE[1] or nil,
                onClick = function()
                    showOnMap(d)
                    render()
                end } }
        if view.tab == 1 then
            local run, why = R.Run(st, client(), d and d.key)
            buttons[#buttons + 1] = { kind = "button", key = "planRun", text = W.PLAN_RUN, enabled = run ~= nil,
                tooltip = run == nil and why and why[1] or nil,
                onClick = function()
                    planRun(d)
                    render()
                end }
        end
        return { kind = "footer", key = "footer", text = view.said or "", buttons = buttons }
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
                        rows[#rows + 1] = { kind = "line", text = r.name, icon = iconOf(g.id),
                            sub = join(join(r.chain, r.note), r.next),
                            right = r.level and ("Level " .. tostring(r.level)) or nil, tone = TONE[g.id] }
                    end
                end
            end
        end
        out[#out + 1] = { kind = "scroll", key = "quests", children = rows }
    end

    local function bossesPane(d, out)
        local book = k.store:get("account", W.BOSS_LOOT)
        local drops = k.store:get("char", W.DROPS)
        local loot = R.Loot(st, client(), d.key, book, drops)
        if loot.why then
            out[#out + 1] = empty(loot.why)
            return
        end
        -- Lead DISPATCH 426: every boss with what it can drop, before the
        -- first kill. A drop this account saw is marked, never counted as
        -- the heading; a boss with no list says so in plain words.
        local rows = {}
        for _, b in ipairs(loot.bosses) do
            rows[#rows + 1] = { kind = "section", text = tostring(b.name or R.BOSS_UNNAMED) }
            if #b.items == 0 then
                rows[#rows + 1] = { kind = "line", text = R.BOSS_NO_DATA[1], sub = R.BOSS_NO_DATA[2] }
            end
            for _, it in ipairs(b.items) do
                rows[#rows + 1] = { kind = "itemLine", name = it.name, quality = it.quality, icon = it.icon,
                    item = it.item, note = it.seen and R.SEEN or nil }
            end
        end
        out[#out + 1] = { kind = "scroll", key = "bosses", children = rows }
        -- Items the client had not read yet get their names a moment later:
        -- drawn again a few times, then left as they are.
        if loot.unread > 0 and view.reads < W.READ_TRIES and not cancelRead and ctx and ctx.sched then
            view.reads = view.reads + 1
            cancelRead = ctx.sched:after(W.NAME, W.READ_WAIT, function()
                cancelRead = nil
                if view.tab == 2 and render then render() end
            end)
        end
    end

    local function mapPane(d, out)
        local e, why = R.Entrance(st, client(), d.key)
        if not e then
            out[#out + 1] = empty(why)
            return
        end
        out[#out + 1] = { kind = "line", key = "entrance", text = "Entrance",
            sub = string.format("%.1f, %.1f", e.x, e.y) }
    end

    local function tree()
        local children = {
            { kind = "header", key = "header", title = W.HEADER,
              search = { placeholder = W.SEARCH, text = view.search, onText = function(text)
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
            local names = {}
            for i, d in ipairs(list) do names[i] = S.ListText(d) end
            local sel, d = picked(list)
            children[#children + 1] = { kind = "topicList", key = "dungeons", items = names, selected = sel,
                onSelect = function(i)
                    if list[i] then view.pick, view.said, view.reads = list[i].key, nil, 0 end
                    render()
                end }
            -- Lead DISPATCH 343: as the journal's, the dungeon's name with
            -- its level range above the tabs, its quest count below.
            if d then
                children[#children + 1] = { kind = "line", key = "summary", text = d.name,
                    right = S.LevelText(d), sub = S.CountText(#d.ids) }
            end
            children[#children + 1] = { kind = "tabs", key = "tabs", items = W.TABS, selected = view.tab,
                onSelect = function(i)
                    view.tab = i
                    render()
                end }
            if not d then
                children[#children + 1] = empty(#R.List(st) == 0 and S.WHY.noQuests or R.WHY_NO_MATCH)
            else
                if view.tab == 2 then bossesPane(d, children)
                elseif view.tab == 3 then mapPane(d, children)
                else questsPane(d, children) end
                if view.tab ~= 2 then children[#children + 1] = footer(d) end
            end
        end
        -- It lists dungeons, so it can be resized, also on the first draw before
        -- the list is read (its saved size is given back then too).
        return ns.Kit.Window({ id = W.ID, title = id.title .. ": " .. W.HEADER, resizable = true,
            children = children })
    end

    render = function()
        if not handle then return end
        local t, why = tree()
        if not t then
            k.problems:add(W.NAME, "tree", tostring(why))
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
            k.problems:add(W.NAME, "tree", tostring(why))
            return false
        end
        if not handle then
            -- A name of its own: the game's Escape list closes a named
            -- window (the kit wires it); its place is kept when moved.
            local point, width, height = ns.Kit.Place(k.store:get("account", W.PATH), t)
            handle = c.kitWindow(W.ID, t, {
                name = id.framePrefix .. "DungeonWindow",
                point = point, width = width, height = height,
                onMoved = function(at, w, h)
                    if type(at) ~= "table" then return end
                    local ok, why = k.store:set("account", W.PATH,
                        { point = { at[1], at[2], at[3], at[4] }, width = w, height = h })
                    if not ok then k.problems:add(W.NAME, "place", tostring(why)) end
                end,
                onClose = function() end,
                failed = function(err) k.problems:add(W.NAME, "draw", tostring(err)) end,
            })
            if not handle then
                k.problems:add(W.NAME, "window", "the client could not draw the window")
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

    if diag and type(diag.commands) == "table" then
        diag.commands[W.WORD] = function() api.Open() end
        if type(diag.help) == "table" then diag.help[W.WORD] = W.HELP end
    end

    k:Module({
        name = W.NAME,
        needs = { "client", "store", "sched" },
        provides = { Open = api.Open, Close = api.Close, Shown = api.Shown },
        start = function(c) ctx = c end,
        stop = function()
            if cancelStep then cancelStep() end
            cancelStep = nil
            if type(cancelRead) == "function" then cancelRead() end
            cancelRead = nil
            if handle then handle.close() end
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.dungeonWindow = W.Declare(ns, ns.diag)

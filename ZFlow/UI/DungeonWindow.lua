-- The Dungeon Quests window (lead sections 303 item 6 and 318). Left: the
-- dungeons in level order with a search in the header. Right: three tabs,
-- Quests (first), Bosses and Map. Quests: the five groups of
-- Nav/DungeonStates.lua, "Not for you" folded, one line per quest with its
-- level, "Step n of m" and "Available at Level X". Show on map sets the
-- player's own waypoint (Nav/Waypoint.lua) at the dungeon's entrance.
-- Bosses: this account's own seen loot (Nav/DungeonRead.lua R.Loot).
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
-- Not tested in game. No quest-state icons yet: the kit's theme has none
-- (asked of the kit's owner, from-plexy RESULTS).
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
W.BOSS_LOOT = "learned.bossLoot"   -- account, UI/BossLoot.lua
W.DROPS = "learned.drops"          -- character, Items/Drops.lua
-- Where the window was left, account wide: { point, width, height }
-- (Twin review 18:06, F1). Read back through ns.Kit.Place.
W.PATH = "layout.dungeonWindow"

-- The tone a group's lines are drawn in (the kit's three words).
local TONE = { log = "good", later = "warn", notforyou = "bad" }

local function join(a, b)
    if a and b then return a .. " · " .. b end
    return a or b
end

function W.Declare(k, diag)
    local api = {}
    local ctx, handle
    local st
    local view = { search = "", pick = nil, tab = 1, folded = {}, said = nil }
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

    local function footer(d)
        local e = R.Entrance(st, client(), d and d.key)
        return { kind = "footer", key = "footer", text = view.said or "",
            buttons = { { kind = "button", key = "showOnMap", text = W.SHOW_ON_MAP, enabled = e ~= nil,
                tooltip = e == nil and R.WHY_NO_ENTRANCE[1] or nil,
                onClick = function()
                    showOnMap(d)
                    render()
                end } } }
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
                        rows[#rows + 1] = { kind = "line", text = r.name, sub = join(r.chain, r.note),
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
        local rows = {}
        for _, b in ipairs(loot.bosses) do
            rows[#rows + 1] = { kind = "section", text = tostring(b.name or "A boss")
                .. " (" .. tostring(b.kills) .. (b.kills == 1 and " kill)" or " kills)") }
            for _, it in ipairs(b.items) do
                rows[#rows + 1] = { kind = "itemLine", name = it.name, quality = it.quality, icon = it.icon,
                    item = it.item, note = "seen " .. tostring(it.times) .. (it.times == 1 and " time" or " times") }
            end
        end
        out[#out + 1] = { kind = "scroll", key = "bosses", children = rows }
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
            for i, d in ipairs(list) do names[i] = d.name end
            local sel, d = picked(list)
            children[#children + 1] = { kind = "topicList", key = "dungeons", items = names, selected = sel,
                onSelect = function(i)
                    if list[i] then view.pick, view.said = list[i].key, nil end
                    render()
                end }
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
            if handle then handle.close() end
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.dungeonWindow = W.Declare(ns, ns.diag)

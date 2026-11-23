-- The in-dungeon tracker (lead section 303 item 8 (d)). Inside a dungeon, a
-- small kit window lists the bosses killed this visit (Nav/BossKills.lua)
-- and this dungeon's quests in your log (Nav/DungeonRead.lua). It shows
-- nothing outside an instance, with its setting off, or when the client
-- took neither kill event (BossKills api.Reported): a tracker that can
-- never show a kill is not shown at all.
--
-- Built from the kit's parts only (UI/Kit.lua, drawn by client.kitWindow):
-- this file names no template, colour, font, size or picture (the quest
-- picture is Kit.look.icon.questInLog), and works out nothing itself.
--
-- LOOK ONLY. It reads and draws; it targets, casts and clicks nothing.
--
--   T.Declare(k) -> api     api.Refresh(), api.Shown()
-- Setting (account, on by default): T.SETTING. Its place is kept at T.PATH.
-- Which dungeon: the instance name the client gives (client.instanceName)
-- matched to Questie's name for it; a name Questie spells otherwise gives
-- the kills only, and says the dungeon is not known.
-- Not tested in game.
local _, ns = ...

local T = {}
ns.DungeonTracker = T

T.NAME = "dungeonTracker"
T.ID = "dungeonTracker"
T.SETTING = "dungeon.tracker"
T.PATH = "layout.dungeonTracker"
T.TITLE = "In this dungeon"
T.KILLS = "Bosses killed"
T.QUESTS = "Your quests here"
T.NO_KILL = "No boss killed yet this visit."
T.NO_QUEST = "No quest of this dungeon in your log."
T.NOT_KNOWN = "Not known which dungeon this is."
T.A_BOSS = "A boss"
-- The instance kinds a dungeon is (client.instance().kind).
T.KINDS = { party = true, raid = true }

local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if ok then return v end
    return nil
end

function T.Declare(k)
    local api = {}
    local ctx, handle, st, cancelStep
    local refresh
    local id = k.id or ns.id
    local R = ns.DungeonRead

    k:Setting({ key = T.SETTING, scope = "account", type = "bool", default = true,
        label = "Dungeon tracker", group = "party",
        help = "Inside a dungeon: the bosses you killed this visit and the dungeon's quests in your log. "
            .. "Shows nothing when the game does not report boss kills.",
        synonyms = { "tracker", "dungeon", "boss", "kills", "instance" } })

    local function client() return ctx and ctx.client or k.client end

    local function hide()
        if handle then handle.show(false) end
    end

    -- The reader's index, in slices out of the way of the frame.
    local function index()
        if st and st.state ~= "failed" and st.state ~= "noquestie" then return end
        st = R.Start(client())
        if st.state == "building" and ctx and ctx.sched then
            cancelStep = ctx.sched:every(T.NAME, 0.05, function()
                R.Step(st, client(), R.SLICE)
                if st.state ~= "building" then
                    if cancelStep then cancelStep() end
                    cancelStep = nil
                    refresh()
                end
            end)
        end
    end

    local function tree(kills)
        local children = { { kind = "section", key = "kills", text = T.KILLS .. " (" .. #kills .. ")" } }
        if #kills == 0 then
            children[#children + 1] = { kind = "line", key = "noKill", text = T.NO_KILL }
        end
        for _, e in ipairs(kills) do
            children[#children + 1] = { kind = "line", text = e.name or T.A_BOSS }
        end
        children[#children + 1] = { kind = "section", key = "quests", text = T.QUESTS }
        local d = st and st.state == "ready" and R.DungeonNamed(st, ask(client(), "instanceName")) or nil
        if not d then
            -- The real reason (Twin review, lead section 286): no Questie,
            -- a list that could not be read, a list still being read; only
            -- with the list read is the dungeon itself not known.
            local why = T.NOT_KNOWN
            if not st or st.state == "noquestie" then
                why = ns.DungeonStates.WHY.noQuestie[1]
            elseif st.state == "failed" then
                why = (st.why or R.WHY_LIST)[1]
            elseif st.state == "building" then
                why = R.WHY_BUILDING[1]
            end
            children[#children + 1] = { kind = "line", key = "notKnown", text = why }
        else
            local pane = R.Pane(st, client(), d.key)
            if pane.why then
                -- A pane that waits (your level not known ...) says why.
                children[#children + 1] = { kind = "line", key = "why", text = pane.why[1] }
                return ns.Kit.Window({ id = T.ID, title = id.title .. ": " .. T.TITLE, children = children })
            end
            local mine = {}
            for _, g in ipairs(pane.groups or {}) do
                if g.id == "log" then mine = g.rows end
            end
            if #mine == 0 then
                children[#children + 1] = { kind = "line", key = "noQuest", text = T.NO_QUEST }
            end
            local icon = ns.Kit.look and ns.Kit.look.icon and ns.Kit.look.icon.questInLog or nil
            for _, r in ipairs(mine) do
                children[#children + 1] = { kind = "line", text = r.name, icon = icon, sub = r.chain }
            end
        end
        return ns.Kit.Window({ id = T.ID, title = id.title .. ": " .. T.TITLE, children = children })
    end

    refresh = function()
        if not ctx then return end
        local c = client()
        local inst = ask(c, "instance")
        local inside = type(inst) == "table" and inst.inside == true and T.KINDS[inst.kind] == true
        local kills = k.use and k.use(ns.BossKills.NAME) or nil
        local reported = type(kills) == "table" and type(kills.Reported) == "function" and kills.Reported() == true
        if ctx.settings:get(T.SETTING) ~= true or not inside or not reported then
            hide()
            return
        end
        index()
        local t, why = tree(type(kills.Kills) == "function" and kills.Kills() or {})
        if not t then
            k.problems:add(T.NAME, "tree", tostring(why))
            return
        end
        if not handle then
            if type(c.kitWindow) ~= "function" then return end
            local point, width, height = ns.Kit.Place(ctx.store:get("account", T.PATH), t)
            handle = c.kitWindow(T.ID, t, {
                name = id.framePrefix .. "DungeonTracker",
                point = point, width = width, height = height,
                onMoved = function(at, w, h)
                    if type(at) ~= "table" then return end
                    local ok, err = ctx.store:set("account", T.PATH,
                        { point = { at[1], at[2], at[3], at[4] }, width = w, height = h })
                    if not ok then k.problems:add(T.NAME, "place", tostring(err)) end
                end,
                failed = function(err) k.problems:add(T.NAME, "draw", tostring(err)) end,
            })
            if not handle then
                k.problems:add(T.NAME, "window", "the client could not draw the tracker")
                return
            end
        else
            handle.update(t)
        end
        handle.show(true)
    end

    function api.Refresh() if refresh then refresh() end end
    function api.Shown() return handle ~= nil and handle.shown() == true end

    k:Module({
        name = T.NAME,
        needs = { "client", "store", "settings", "bus", "sched" },
        provides = { Refresh = api.Refresh, Shown = api.Shown },
        start = function(c)
            ctx = c
            for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "QUEST_LOG_UPDATE" }) do
                c.client.listen(event, function() refresh() end)
            end
            c.bus:on(T.NAME, ns.BossKills.EVENT, function() refresh() end)
            local row = c.settings:row(T.SETTING)
            c.store:watch(row and row.scope or "account", row and row.path or ("settings." .. T.SETTING),
                function() refresh() end)
            refresh()
        end,
        -- Stopped, nothing brings it back: refresh does nothing without ctx
        -- (Twin low note).
        stop = function()
            if cancelStep then cancelStep() end
            cancelStep = nil
            hide()
            ctx = nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.dungeonTracker = T.Declare(ns)

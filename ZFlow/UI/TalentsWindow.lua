local _, ns = ...

-- The Talents window (KNOW lane, C-62): the levelling build of your class
-- pack, every talent in the order to take it, with the levels its points
-- come at. One window on the shared kit (UI/Kit.lua), a page to read beside
-- the game's own talent window.
--
--   the talents word   opens the window. One row for each talent of the
--                      build: "Levels 10 to 14: Improved Wrath, 5 points".
--                      The row's second line and its tooltip say why the
--                      talent is taken. A pack with more than one build
--                      has a tab for each.
--   your points        when the client says which talents you have
--                      (talentRanks), a row shows "3/5" and the first
--                      talent not full is marked "next". When it does not,
--                      the rows up to your level are marked "by now" and
--                      nothing is said about what you have.
--   unspent points     "You have 3 talent points to spend." under the
--                      build's name, when the client says how many
--                      (Spells/Talents.lua Tl.Unspent).
--
-- LOOK ONLY. No talent is learned, no point is spent, nothing is clicked.
--
-- The builds are the class packs' own (pack.talentBuilds: name, order =
-- { { talent, points, why = } }); no build is authored here. The first
-- talent point comes at T.FIRST_LEVEL, then one a level.
--
-- Client reads: class, level, kitWindow, unspentTalents, and talentRanks()
-- -> { [talent name] = rank } or nil. talentRanks is asked for in the lane
-- report (the lead writes Core/Client.lua); while the client has no such
-- read, what you have is "not known".
--
-- Pure parts:
--   T.Entries(build) -> { { name, points, need, from, to, why } }
--   T.Text(entry)    -> the row's words
--   T.Mark(entry, level, ranks, isNext) -> right text, tone (both may be nil)
--   T.Next(entries, ranks) -> the index of the first talent not full, or nil
--
-- Saved data: account "layout.talentsWindow" (where the window stands).

local T = {}
ns.TalentsWindow = T

T.NAME = "talentsWindow"
T.ID = "talents"
T.WORD = "talents"
T.HEADER = "Talents"
T.PATH = "layout.talentsWindow"
T.WIDTH, T.HEIGHT = 520, 480
T.FIRST_LEVEL = 10

T.HELP = "open the talents page: your class's levelling build, talent by talent"
T.ABOUT = "Take the talents from the top down, one point a level from level %d. Nothing is spent for you."
T.NO_BUILD = { "No levelling build for your class yet.", "Your class is read at login; open this again in a moment." }
T.UNSPENT_ONE = "You have 1 talent point to spend."
T.UNSPENT = "You have %d talent points to spend."
T.ONE = "Level %d: %s"
T.MANY = "Levels %d to %d: %s, %d points"
T.NEXT = "next"
T.BY_NOW = "by now"
T.FOOTER = "A page to read beside the game's talent window."

local function count(v)
    return type(v) == "number" and v == v and v >= 0 and v ~= math.huge
end

-- One entry for each row of the build's order. need: the rank of that
-- talent once this row is taken (a talent may come back later in a build).
function T.Entries(build)
    local out, have, spent = {}, {}, 0
    local order
    if type(build) == "table" then order = build.order end
    for _, row in ipairs(type(order) == "table" and order or {}) do
        if type(row) == "table" and type(row[1]) == "string" then
            local points = 1
            if count(row[2]) and row[2] >= 1 then points = math.floor(row[2]) end
            have[row[1]] = (have[row[1]] or 0) + points
            local e = { name = row[1], points = points, need = have[row[1]],
                        from = T.FIRST_LEVEL + spent, to = T.FIRST_LEVEL + spent + points - 1 }
            if type(row.why) == "string" and row.why ~= "" then e.why = row.why end
            spent = spent + points
            out[#out + 1] = e
        end
    end
    return out
end

function T.Text(entry)
    if entry.points == 1 then return T.ONE:format(entry.from, entry.name) end
    return T.MANY:format(entry.from, entry.to, entry.name, entry.points)
end

function T.Next(entries, ranks)
    if type(ranks) ~= "table" then return nil end
    for i, e in ipairs(entries) do
        local have = ranks[e.name]
        if not count(have) then have = 0 end
        if have < e.need then return i end
    end
    return nil
end

function T.Mark(entry, level, ranks, isNext)
    if type(ranks) == "table" then
        local have = ranks[entry.name]
        if not count(have) then have = 0 end
        local first = entry.need - entry.points
        local got = math.max(0, math.min(entry.points, have - first))
        local text = got .. "/" .. entry.points
        if got >= entry.points then return text, "good" end
        if isNext then return text .. " " .. T.NEXT, "warn" end
        return text, nil
    end
    if count(level) and entry.from <= level then return T.BY_NOW, nil end
    return nil, nil
end

function T.Declare(k, diag)
    local api = {}
    local ctx, handle
    local render
    local picked = 1
    local id = k.id or ns.id

    local function client() return ctx and ctx.client or k.client end

    local function ask(read, ...)
        local c = client()
        if type(c) ~= "table" or type(c[read]) ~= "function" then return nil end
        local ok, v = pcall(c[read], ...)
        if not ok then return nil end
        return v
    end

    local function builds()
        local class = ask("class")
        local pack
        if type(class) == "string" and type(ns.Packs) == "table" then pack = ns.Packs[class] end
        local list
        if type(pack) == "table" then list = pack.talentBuilds end
        local out = {}
        for _, b in ipairs(type(list) == "table" and list or {}) do
            if type(b) == "table" and type(b.name) == "string" and type(b.order) == "table" then out[#out + 1] = b end
        end
        return out
    end

    local function tree()
        local children = { { kind = "header", key = "header", title = T.HEADER } }
        local all = builds()
        if picked > #all then picked = 1 end
        local build = all[picked]
        local body = {}
        if build then
            if #all > 1 then
                local names = {}
                for i, b in ipairs(all) do names[i] = b.name end
                children[#children + 1] = { kind = "tabs", key = "builds", items = names, selected = picked,
                    onSelect = function(i)
                        picked = i
                        render()
                    end }
            end
            children[#children + 1] = { kind = "line", key = "build", text = build.name,
                sub = T.ABOUT:format(T.FIRST_LEVEL), wrap = true }
            local points
            if ns.SpellTalents and type(ns.SpellTalents.Unspent) == "function" then
                points = ns.SpellTalents.Unspent(client())
            end
            if count(points) and points > 0 then
                local text = T.UNSPENT:format(points)
                if points == 1 then text = T.UNSPENT_ONE end
                children[#children + 1] = { kind = "line", key = "unspent", text = text, tone = "warn" }
            end
            local entries = T.Entries(build)
            local level, ranks = ask("level"), ask("talentRanks")
            local nextAt = T.Next(entries, ranks)
            for i, e in ipairs(entries) do
                local right, tone = T.Mark(e, level, ranks, i == nextAt)
                body[#body + 1] = { kind = "line", key = "talent." .. i, text = T.Text(e), sub = e.why,
                    tooltip = e.why, right = right, tone = tone, wrap = true }
            end
        end
        if #body == 0 then
            body[#body + 1] = { kind = "empty", key = "empty", text = T.NO_BUILD[1], how = T.NO_BUILD[2] }
        end
        children[#children + 1] = { kind = "scroll", key = "body", children = body }
        children[#children + 1] = { kind = "footer", key = "footer", text = T.FOOTER }
        return ns.Kit.Window({ id = T.ID, title = id.title .. ": " .. T.HEADER, resizable = true,
            width = T.WIDTH, height = T.HEIGHT, children = children })
    end

    render = function()
        if not handle then return end
        local t, why = tree()
        if not t then
            k.problems:add(T.NAME, "tree", tostring(why))
            return
        end
        handle.update(t)
    end

    function api.Open()
        local c = client()
        if type(c) ~= "table" or type(c.kitWindow) ~= "function" then return false end
        local t, why = tree()
        if not t then
            k.problems:add(T.NAME, "tree", tostring(why))
            return false
        end
        if not handle then
            local point, width, height = ns.Kit.Place(k.store:get("account", T.PATH), t)
            handle = c.kitWindow(T.ID, t, {
                name = id.framePrefix .. "TalentsWindow",
                point = point, width = width, height = height,
                onMoved = function(at, w, h)
                    if type(at) ~= "table" then return end
                    local ok, err = k.store:set("account", T.PATH,
                        { point = { at[1], at[2], at[3], at[4] }, width = w, height = h })
                    if not ok then k.problems:add(T.NAME, "place", tostring(err)) end
                end,
                onClose = function() end,
                failed = function(err) k.problems:add(T.NAME, "draw", tostring(err)) end,
            })
            if not handle then
                k.problems:add(T.NAME, "window", "the client could not draw the window")
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
        diag.commands[T.WORD] = function() api.Open() end
        if type(diag.help) == "table" then diag.help[T.WORD] = T.HELP end
    end

    k:Module({
        name = T.NAME,
        needs = { "client", "store", "bus" },
        provides = { Open = api.Open, Close = api.Close, Shown = api.Shown },
        start = function(c)
            ctx = c
            -- An open page keeps in step with your level and your points.
            for _, ev in ipairs({ "PLAYER_LEVEL_UP", "CHARACTER_POINTS_CHANGED" }) do
                c.bus:on(T.NAME, ev, function() render() end)
            end
        end,
        stop = function()
            if handle then handle.close() end
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.talentsWindow = T.Declare(ns, ns.diag)

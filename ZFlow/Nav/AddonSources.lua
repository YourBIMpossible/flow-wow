local _, ns = ...
-- Optional runtime sources (N67, research items 16 and 26): two other
-- add-ons, read only while the game runs and only when they are loaded.
--
--   GatherMate2: the gathering nodes it knows on the player's map, as an
--   extra source of node places. Z-Flow's own data stays first; each node
--   read here says source = "GatherMate2" so a consumer can rank it after
--   its own. Kept in memory for the current map only (at most NODES_MAX),
--   read again on login, on its ADDON_LOADED, on a map change and when the
--   setting changes.
--   Attune: this character's attunement progress. The attunements under
--   way (more than 0, less than 100 percent) are one Advisor prompt; no
--   chain view (that is a separate proposal, not built).
--
-- LOOK ONLY. Nothing is written to either add-on, nothing of theirs is kept
-- in Z-Flow's saved data, and reading their tables at runtime copies none
-- of their code or database. Absent, switched off or a read that raises:
-- Z-Flow is as without them, and the diag word says which.
--
-- The client reads (Core/Client.lua, N67):
--   client.gatherMateNodes(map) -> { { kind, x, y, node } } or nil
--   client.attuneProgress()     -> { { id, name, percent } } or nil
--   client.position()           -> { map, x, y } or nil
--
--   S.Line(k) -> "sources: GatherMate2 ...; Attune ..."  for the diag word
--   ns.use(S.GATHER_NAME) -> { Nodes(), State() }
--     Nodes() -> copies of the nodes on the current map, or nil
--     State() -> "absent" | "off" | "failed" | "no map" | "ready", count
--   ns.use(S.ATTUNE_NAME) -> { Rows(), State() }
--     Rows()  -> copies of the attunement rows read, or nil
--     State() -> "absent" | "off" | "failed" | "ready", count, under way
-- Not tested in game: the reads are first guesses.
ns.Nav = ns.Nav or {}
local S = {}
ns.Nav.AddonSources = S

S.GATHER_NAME = "gatherMateSource"
S.ATTUNE_NAME = "attuneSource"
S.GATHER_SETTING = "professions.gatherMateNodes"
S.ATTUNE_SETTING = "party.attuneProgress"
S.NODES_MAX = 500
S.ATTUNE_SHOWN = 3
S.ADVICE_ID = "attune.progress"
S.SOURCE = "GatherMate2"

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function copyRows(rows)
    if type(rows) ~= "table" then return nil end
    local out = {}
    for i, r in ipairs(rows) do
        local row = {}
        for key, v in pairs(r) do row[key] = v end
        out[i] = row
    end
    return out
end

-- Follows the module's setting and the client events; every refresh runs
-- under a pcall, so nothing raised by a read reaches the event.
local function follow(c, key, events, isMine, refresh)
    local cancels = {}
    local function safe() pcall(refresh) end
    local row = c.settings:row(key)
    local scope = row and row.scope or "char"
    local path = row and row.path or ("settings." .. key)
    local okW, cancel = pcall(c.store.watch, c.store, scope, path, safe)
    if okW and type(cancel) == "function" then cancels[#cancels + 1] = cancel end
    for _, event in ipairs(events) do
        local okL, cancelL = pcall(c.client.listen, event, function(name)
            if event == "ADDON_LOADED" and not isMine(name) then return end
            safe()
        end)
        if okL and type(cancelL) == "function" then cancels[#cancels + 1] = cancelL end
    end
    safe()
    return function()
        for _, fn in ipairs(cancels) do pcall(fn) end
    end
end

local EVENTS = { "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }

function S.DeclareGather(k)
    local id = k.id or ns.id
    local ctx, unfollow
    local cache = { state = "absent", count = 0 }
    local api = {}

    local function refresh()
        cache.nodes, cache.map, cache.count = nil, nil, 0
        if not ctx then cache.state = "absent"; return end
        if ctx.settings:get(S.GATHER_SETTING) == false then cache.state = "off"; return end
        local client = ctx.client
        if type(client.gatherMateNodes) ~= "function" then cache.state = "absent"; return end
        local map
        if type(client.position) == "function" then
            local okP, pos = pcall(client.position)
            if okP and type(pos) == "table" and type(pos.map) == "number" then map = pos.map end
        end
        if map == nil then cache.state = "no map"; return end
        local ok, rows = pcall(client.gatherMateNodes, map)
        if not ok then cache.state = "failed"; return end
        if type(rows) ~= "table" then cache.state = "absent"; return end
        local nodes = {}
        for _, r in ipairs(rows) do
            if #nodes >= S.NODES_MAX then break end
            if type(r) == "table" and finite(r.x) and finite(r.y) then
                local node = { x = r.x, y = r.y, map = map, source = S.SOURCE }
                if type(r.kind) == "string" then node.kind = r.kind end
                if type(r.node) == "string" then node.node = r.node end
                nodes[#nodes + 1] = node
            end
        end
        cache.state, cache.map, cache.nodes, cache.count = "ready", map, nodes, #nodes
    end

    function api.Nodes()
        if cache.state ~= "ready" then return nil end
        return copyRows(cache.nodes)
    end
    function api.State() return cache.state, cache.count end

    k:Module({
        name = S.GATHER_NAME,
        needs = { "client", "store", "settings" },
        provides = { Nodes = api.Nodes, State = api.State },
        settings = { {
            key = S.GATHER_SETTING, scope = "char", type = "bool", default = true,
            label = "Read GatherMate2 nodes",
            help = "When GatherMate2 is installed and loaded, Z-Flow reads the gathering nodes it knows on "
                .. "your map, as an extra source beside its own. Read only: nothing of GatherMate2's is "
                .. "changed or kept in Z-Flow's saved data.",
            group = "professions",
            synonyms = { "gathermate", "nodes", "herbs", "ore", "mining", "herbalism", "gather", "addon" },
        } },
        start = function(c)
            ctx = c
            unfollow = follow(c, S.GATHER_SETTING, EVENTS,
                function(name) return name == id.gatherMate end, refresh)
        end,
        stop = function()
            if unfollow then unfollow() end
            unfollow, ctx = nil, nil
            cache = { state = "absent", count = 0 }
        end,
    })
    return api
end

-- The prompt text for the attunements under way, or nil for none.
function S.AdviceText(rows)
    if type(rows) ~= "table" then return nil end
    local busy = {}
    for _, r in ipairs(rows) do
        if type(r) == "table" and type(r.name) == "string" and finite(r.percent)
            and r.percent > 0 and r.percent < 100 then
            busy[#busy + 1] = r
        end
    end
    if #busy == 0 then return nil end
    table.sort(busy, function(a, b)
        if a.percent ~= b.percent then return a.percent > b.percent end
        return a.name < b.name
    end)
    local parts = {}
    for i = 1, math.min(#busy, S.ATTUNE_SHOWN) do
        parts[i] = busy[i].name .. " " .. math.floor(busy[i].percent + 0.5) .. "%"
    end
    local text = "Attunements under way: " .. table.concat(parts, ", ")
    if #busy > S.ATTUNE_SHOWN then text = text .. " and " .. (#busy - S.ATTUNE_SHOWN) .. " more" end
    return text .. ".", #busy
end

function S.DeclareAttune(k)
    local id = k.id or ns.id
    local ctx, unfollow, advisor
    local cache = { state = "absent", count = 0, busy = 0 }
    local api = {}

    local function prompt(text)
        if type(advisor) ~= "table" then return end
        if text then
            advisor.Add(S.ADVICE_ID, text, 0)
        else
            advisor.Remove(S.ADVICE_ID)
        end
    end

    local function refresh()
        cache.rows, cache.count, cache.busy = nil, 0, 0
        if not ctx then cache.state = "absent"; return end
        if ctx.settings:get(S.ATTUNE_SETTING) == false then
            cache.state = "off"
            prompt(nil)
            return
        end
        local client = ctx.client
        if type(client.attuneProgress) ~= "function" then
            cache.state = "absent"
            prompt(nil)
            return
        end
        local ok, rows = pcall(client.attuneProgress)
        if not ok then
            cache.state = "failed"
            prompt(nil)
            return
        end
        if type(rows) ~= "table" then
            cache.state = "absent"
            prompt(nil)
            return
        end
        cache.state, cache.rows, cache.count = "ready", copyRows(rows), #rows
        local text, busy = S.AdviceText(rows)
        cache.busy = busy or 0
        prompt(text)
    end

    function api.Rows()
        if cache.state ~= "ready" then return nil end
        return copyRows(cache.rows)
    end
    function api.State() return cache.state, cache.count, cache.busy end

    k:Module({
        name = S.ATTUNE_NAME,
        needs = { "client", "store", "settings", "advisor" },
        provides = { Rows = api.Rows, State = api.State },
        settings = { {
            key = S.ATTUNE_SETTING, scope = "char", type = "bool", default = true,
            label = "Show Attune progress",
            help = "When Attune is installed and loaded, the Advisor names the attunements you have under way "
                .. "with their percent, as Attune counts them. Read only: nothing of Attune's is changed or "
                .. "kept in Z-Flow's saved data.",
            group = "party",
            synonyms = { "attune", "attunement", "attunements", "raid", "dungeon", "keys", "addon" },
        } },
        start = function(c)
            ctx = c
            local okU, got = pcall(c.use, "advisor")
            if okU and type(got) == "table" then advisor = got end
            unfollow = follow(c, S.ATTUNE_SETTING, { "ADDON_LOADED", "PLAYER_ENTERING_WORLD",
                "ZONE_CHANGED_NEW_AREA", "QUEST_TURNED_IN" },
                function(name) return name == id.attune end, refresh)
        end,
        stop = function()
            if unfollow then unfollow() end
            prompt(nil)
            unfollow, ctx, advisor = nil, nil, nil
            cache = { state = "absent", count = 0, busy = 0 }
        end,
    })
    return api
end

-- The diag word's line: what each source is doing now.
local function describe(k, name, label, say)
    local okS, state = pcall(function() return k:ModuleState(name) end)
    if not okS or state ~= "started" then return label .. " not running" end
    local okU, api = pcall(k.use, name)
    if not okU or type(api) ~= "table" or type(api.State) ~= "function" then return label .. " not running" end
    return label .. " " .. say(api.State())
end

local WORDS = { absent = "absent", off = "switched off", failed = "read failed",
                ["no map"] = "not known where you are" }

function S.Line(k)
    local id = k.id or ns.id
    local gm = describe(k, S.GATHER_NAME, id.gatherMate, function(state, count)
        if state == "ready" then return tostring(count) .. (count == 1 and " node" or " nodes") .. " on this map" end
        return WORDS[state] or tostring(state)
    end)
    local at = describe(k, S.ATTUNE_NAME, id.attune, function(state, count, busy)
        if state == "ready" then
            return tostring(count) .. (count == 1 and " attunement" or " attunements") .. " read, "
                .. tostring(busy) .. " under way"
        end
        return WORDS[state] or tostring(state)
    end)
    return "sources: " .. gm .. "; " .. at .. "."
end

-- The addon's own: declared when this file loads, started at login.
ns.gatherMateSource = S.DeclareGather(ns)
ns.attuneSource = S.DeclareAttune(ns)

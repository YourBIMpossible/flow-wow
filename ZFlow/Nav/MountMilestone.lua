local _, ns = ...
-- Z-Flow mount milestone (FLOW-PARITY B-25, lead section 460): the road to
-- the first mount, in order, as Flow's Modules/Nav/Mounts.lua:77-93 has it:
-- save up before the riding level, learn riding (Nav/RidingStep.lua says
-- that line and points at the trainer), then the mount. LOOK ONLY: nothing
-- trains, buys or mounts.
--
-- Where things come from (never a shipped price):
--   level      client.level()
--   riding     client.skillRanks(), through RidingStep.IsRiding
--   price      a riding trainer's list the player has seen
--              (account "learned.places.npcs", ridingCosts[40], written by
--              RidingStep.Seen); not seen: "price not seen yet"
--   money      client.money()
--   mount      the player seen mounted (client.mounted() true) at a look,
--              recorded as it happens in char M.SEEN; never seen: the mount
--              is still to come. A mount price is never known here (Z-Flow
--              keeps no merchant lists): it stays unknown.
--
-- Pure:
--   M.Next(s) -> "save" | "riding" | "mount" | nil
--     s = { level, rank (riding rank, 0 none; nil not read), mountSeen }
--   M.Cost(npcs) -> copper or nil: the lowest seen price for riding
--   M.Lines(next, cost, money) -> { line, ... }
--   M.Step(next, ridingStep, cost) -> { label, place } or nil: the
--     "Learn riding" step at the trainer RidingStep found on this map.
-- Module "mountMilestone" provides Next, Lines, Step. The arrow call (not
-- wired here; UI/Arrow.lua is not leased): ns.use("mountMilestone").Step().
-- Not tested in game.
ns.Nav = ns.Nav or {}
local N = ns.Nav
local M = {}
N.MountMilestone = M

M.NAME = "mountMilestone"
M.PROMPT = "nav.mountMilestone"
M.PRIORITY = 1
M.SETTING = "nav.mountMilestone"
M.SEEN = "learned.mount.seen"
M.NPCS = "learned.places.npcs"
M.LEVEL = 40          -- the riding level (RidingStep.TIERS[1])
M.RANK = 75           -- the first riding rank
M.SAVE_FROM = 5       -- levels before M.LEVEL the save-up line starts (Flow saveFrom)
M.EVERY = 5           -- seconds between looks

M.SAVE = "Riding at level %d costs about %s; you have %s. Start saving for it."
M.SAVE_SHORT = "Riding at level %d costs about %s; you have it."
M.SAVE_UNKNOWN = "Riding at level %d (price not seen yet): start saving for it."
M.SAVE_NO_MONEY = "Riding at level %d costs about %s (money not readable): start saving for it."
M.MOUNT = "Next: buy your first mount from a mount vendor (price not seen yet)."
M.LEARN = "Learn riding (%s)"
M.LEARN_UNKNOWN = "Learn riding (price not seen yet)"

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function coin(copper)
    local P = ns.Prices
    if finite(copper) and P and type(P.Coin) == "function" then
        local ok, s = pcall(P.Coin, copper)
        if ok and type(s) == "string" and s ~= "" then return s end
    end
    return nil
end

function M.Next(s)
    if type(s) ~= "table" or not finite(s.level) or not finite(s.rank) then return nil end
    if s.rank >= M.RANK then
        if s.mountSeen then return nil end
        return "mount"
    end
    if s.level < M.LEVEL - M.SAVE_FROM then return nil end
    if s.level < M.LEVEL then return "save" end
    return "riding"
end

function M.Cost(npcs)
    if type(npcs) ~= "table" then return nil end
    local best
    for _, e in pairs(npcs) do
        local v
        if type(e) == "table" and type(e.ridingCosts) == "table" then v = e.ridingCosts[M.LEVEL] end
        if finite(v) and v >= 0 and (best == nil or v < best) then best = v end
    end
    return best
end

-- The riding line itself is RidingStep's (it names the trainer); the
-- milestone adds the lines before and after it.
function M.Lines(next, cost, money)
    if next == "save" then
        local price, have = coin(cost), coin(money)
        if not price then return { M.SAVE_UNKNOWN:format(M.LEVEL) } end
        if have and finite(money) and money >= cost then return { M.SAVE_SHORT:format(M.LEVEL, price) } end
        if have then return { M.SAVE:format(M.LEVEL, price, have) } end
        return { M.SAVE_NO_MONEY:format(M.LEVEL, price) }
    end
    if next == "mount" then return { M.MOUNT } end
    return {}
end

function M.Step(next, riding, cost)
    if next ~= "riding" or type(riding) ~= "table" or type(riding.place) ~= "table" then return nil end
    local price = coin(cost)
    local p = riding.place
    return { kind = "riding", label = price and M.LEARN:format(price) or M.LEARN_UNKNOWN,
             place = { map = p.map, x = p.x, y = p.y } }
end

function M.Declare(k)
    local api = {}
    local ctx
    local shown

    local function ask(read, ...)
        local c = ctx and ctx.client
        if type(c) ~= "table" or type(c[read]) ~= "function" then return nil end
        local ok, v = pcall(c[read], ...)
        if not ok then return nil end
        return v
    end

    local function get(scope, path)
        local st = ctx and ctx.store
        if type(st) ~= "table" or type(st.get) ~= "function" then return nil end
        local ok, v = pcall(st.get, st, scope, path)
        if ok then return v end
        return nil
    end

    local function on()
        if not ctx or not ctx.settings then return true end
        return ctx.settings:get(M.SETTING) ~= false
    end

    local function rank()
        local ranks = ask("skillRanks")
        if type(ranks) ~= "table" then return nil end
        local R = ns.RidingStep
        local have = 0
        for name, row in pairs(ranks) do
            if R and R.IsRiding(name) then
                local r
                if type(row) == "table" then r = row.rank end
                if not finite(r) then return nil end
                if r > have then have = r end
            end
        end
        return have
    end

    function api.next()
        if not ctx or not on() then return nil end
        return M.Next({ level = ask("level"), rank = rank(), mountSeen = get("char", M.SEEN) == true })
    end

    function api.lines()
        return M.Lines(api.next(), M.Cost(get("account", M.NPCS)), ask("money"))
    end

    function api.step()
        local nx = api.next()
        if nx ~= "riding" then return nil end
        local rs = ctx.use and ctx.use("ridingStep")
        local riding
        if type(rs) == "table" and type(rs.Step) == "function" then
            local ok, v = pcall(rs.Step)
            if ok then riding = v end
        end
        return M.Step(nx, riding, M.Cost(get("account", M.NPCS)))
    end

    function api.look()
        if not ctx then return end
        if ask("mounted") == true and get("char", M.SEEN) ~= true and ctx.store and type(ctx.store.set) == "function" then
            pcall(ctx.store.set, ctx.store, "char", M.SEEN, true)
        end
        local advisor = ctx.use and ctx.use("advisor")
        if type(advisor) ~= "table" then return end
        local lines = api.lines()
        local said
        if #lines > 0 then said = table.concat(lines, " ") end
        if said == shown then return end
        if said then advisor.Add(M.PROMPT, said, M.PRIORITY) else advisor.Remove(M.PROMPT) end
        shown = said
    end

    k:Setting({ key = M.SETTING, scope = "account", type = "bool", default = true,
        label = "Mount milestone", group = "travel.route",
        help = "Before riding, say what it costs from the price you have seen; after it, that the mount is next. It trains and buys nothing.",
        synonyms = { "mount", "riding", "save", "gold" } })

    k:Module({
        name = M.NAME,
        needs = { "client", "store", "settings", "advisor" },
        provides = { Next = function() return api.next() end, Lines = function() return api.lines() end,
                     Step = function() return api.step() end },
        ticks = { { every = M.EVERY, when = "always", run = function() pcall(api.look) end } },
        start = function(c) ctx = c; shown = nil end,
        stop = function() ctx, shown = nil, nil end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.mountMilestone = M.Declare(ns)

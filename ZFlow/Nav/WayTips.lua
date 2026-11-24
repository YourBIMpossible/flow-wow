local _, ns = ...
-- Z-Flow: the waypoint hint (lead section 467, parity row A1-38). The
-- first WT.TIMES times the add-on starts for this account, chat says once
-- how to set a waypoint; the count is kept at WT.PATH (account). After
-- that it is never said again. A chat line, not a map tooltip.
-- Compared with Flow Modules/Nav/Waypoint.lua (W.TIP_TIMES = 2, a tooltip
-- over the world map counted at db.nav.wayTips): here it is a chat line at
-- start, and the words name the commands Z-Flow has. Not tested in game.
--
--   WT.Declare(k, diag) -> api
--     api.Tell() -> the line said, or nil when the count is used up or the
--                   store cannot keep it (then nothing is said: a hint that
--                   cannot be counted would be said every time)
ns.Nav = ns.Nav or {}
local N = ns.Nav

local WT = {}
N.WayTips = WT

WT.NAME = "wayTips"
WT.TIMES = 2
WT.SCOPE = "account"
WT.PATH = "layout.wayTips"
-- Player-visible words, authored here.
WT.TEXT = "Waypoint: /way <x> <y> [note], /way <zone> <x> <y>, /way repair (or inn, mail, ...), "
    .. "/way <party member>; /way clear"

function WT.Declare(k, diag)
    local api = {}
    local ctx

    function api.Tell()
        local store = ctx and ctx.store or k.store
        local c = ctx and ctx.client or k.client
        if type(store) ~= "table" or type(c) ~= "table" or type(c.print) ~= "function" then return nil end
        local okGet, n = pcall(store.get, store, WT.SCOPE, WT.PATH)
        if not okGet then return nil end
        n = type(n) == "number" and n or 0
        if n >= WT.TIMES then return nil end
        local okSet, done = pcall(store.set, store, WT.SCOPE, WT.PATH, n + 1)
        if not okSet or done == false then return nil end
        local id = k.id or ns.id
        local line = id.title .. ": " .. WT.TEXT
        pcall(c.print, line)
        return line
    end

    k:Module({
        name = WT.NAME,
        needs = { "client", "store" },
        provides = { Tell = function() return api.Tell() end },
        start = function(c)
            ctx = c
            api.Tell()
        end,
        stop = function() ctx = nil end,
    })

    return api
end

ns.wayTips = WT.Declare(ns, ns.diag)

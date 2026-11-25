-- c.gossipOptions() with the option's icon and type (A2-27, the shape
-- note from-zen/zflow-gossip-shape.md), c.gossipRawLines() for the
-- diagnostics, and the fake's twins carried into Nav/ServiceSeen.lua.
-- The real client over a hand-built environment. Made-up options and
-- npcs, test only. The icon file IDs are ASSUMED; not tested in game.
local _, ns = ...

local tests = {}

local VENDOR, BINDER, TRAINER = 132060, 132052, 132058

-- opts.secret: the one value issecretvalue calls secret (it refuses nil).
local function newEnv(opts)
    opts = opts or {}
    local env = {}
    function env.issecretvalue(v)
        if v == nil then error("issecretvalue: nil") end
        return opts.secret ~= nil and v == opts.secret
    end
    return env
end

local function info(id, name, icon)
    return { gossipOptionID = id, name = name, icon = icon, status = 0, flags = 0, orderIndex = id }
end

tests["client gossipOptions: the type from the icon, the icon kept"] = function(t)
    local env = newEnv()
    env.C_GossipInfo = { GetOptions = function()
        return { info(1, "Let me browse your goods.", VENDOR), info(2, "Make this inn your home.", BINDER),
                 info(3, "Train me.", TRAINER) }
    end }
    t.eq(ns.make.client(env).gossipOptions(), {
        { id = 1, name = "Let me browse your goods.", icon = VENDOR, type = "vendor" },
        { id = 2, name = "Make this inn your home.", icon = BINDER, type = "binder" },
        { id = 3, name = "Train me.", icon = TRAINER },
    })
end

tests["client gossipOptions: the older read's pairs give the type by place"] = function(t)
    local env = newEnv()
    env.C_GossipInfo = { GetOptions = function() return { info(1, "Show me the way.", 999), info(2, "Bank", 998) } end }
    env.GetGossipOptions = function() return "Show me the way.", "taxi", "Bank", "Banker" end
    t.eq(ns.make.client(env).gossipOptions(), {
        { id = 1, name = "Show me the way.", icon = 999, type = "taxi" },
        { id = 2, name = "Bank", icon = 998, type = "banker" },
    })
end

tests["client gossipOptions: with no C_GossipInfo the pairs alone"] = function(t)
    local env = newEnv()
    env.GetGossipOptions = function() return "Goods", "vendor", "Chat", "gossip" end
    t.eq(ns.make.client(env).gossipOptions(), {
        { name = "Goods", type = "vendor" }, { name = "Chat", type = "gossip" },
    })
    t.eq(ns.make.client(newEnv()).gossipOptions(), nil)
end

tests["client gossipOptions: a secret icon gives no icon and no type; a failed read is nil"] = function(t)
    local env = newEnv({ secret = VENDOR })
    env.C_GossipInfo = { GetOptions = function() return { info(4, "Goods", VENDOR) } end }
    t.eq(ns.make.client(env).gossipOptions(), { { id = 4, name = "Goods" } })
    env.C_GossipInfo = { GetOptions = function() error("no window") end }
    t.eq(ns.make.client(env).gossipOptions(), nil)
end

tests["client gossipRawLines: each option raw, then the pairs; nil with no read"] = function(t)
    local env = newEnv()
    env.C_GossipInfo = { GetOptions = function() return { info(1, "Goods", VENDOR), { name = "Odd" } } end }
    env.GetGossipOptions = function() return "Goods", "vendor" end
    t.eq(ns.make.client(env).gossipRawLines(), {
        "id=1 icon=132060 name=Goods", "id=? icon=? name=Odd", "pair 1: Goods / vendor",
    })
    t.eq(ns.make.client(newEnv()).gossipRawLines(), nil)
end

tests["diag KeepGossip: the newest windows are kept"] = function(t)
    local diag = {}
    for i = 1, ns.Diag.GOSSIP_KEPT + 2 do ns.Diag.KeepGossip(diag, i, { "line " .. i }) end
    t.eq(#diag.gossip, ns.Diag.GOSSIP_KEPT)
    t.eq(diag.gossip[1], { at = 3, lines = { "line 3" } })
end

tests["fake gossipOptions: icon and type pass through; raw lines from the same list"] = function(t)
    local c = ns.make.fakeClient()
    t.eq(c.gossipRawLines(), nil)
    c.setGossipOptions({ { id = 1, name = "Goods", icon = VENDOR, type = "vendor" }, { name = "Chat" } })
    t.eq(c.gossipOptions(), { { id = 1, name = "Goods", icon = VENDOR, type = "vendor" }, { name = "Chat" } })
    t.eq(c.gossipRawLines(), { "id=1 icon=132060 name=Goods", "id=? icon=? name=Chat" })
end

tests["fake gossipOptions: a vendor option is saved as a vendor sighting"] = function(t)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setClock(5000)
    c.setZone(1, 1411)
    c.setPosition(1411, 0.5, 0.25)
    local npc = { guid = "Creature-0-1-2-3-88-0", name = "Vendor Test" }
    c.serviceNpc = function() return npc end
    c.merchantRepairs = function() return nil end
    c.setGossipOptions({ { id = 1, name = "Goods", icon = VENDOR, type = "vendor" } })
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    ns.ServiceSeen.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    c.fire("GOSSIP_SHOW")
    local saved = c.saved(ns.id.charDB).learned.places.services[npc.guid]
    t.eq(saved.kinds, { vendor = true })
    local diag = c.saved(ns.id.accountDB).diag
    t.eq(diag.gossip[#diag.gossip].lines, { "id=1 icon=132060 name=Goods" }, "the diagnostics line was kept")
    t.eq(k.problems:count(), 0)
end

return tests

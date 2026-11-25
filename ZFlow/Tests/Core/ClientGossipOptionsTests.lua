-- c.gossipOptions(): the options of the open gossip window, one row each
-- ({ type, icon, name }), for Nav/ServiceSeen.lua's gossip learning. The
-- real client over a hand-built environment, then the fake. The game calls
-- (C_GossipInfo.GetOptions, the older GetGossipOptions, GossipFrame:IsShown)
-- are first guesses. Made-up answers. Not tested in game.
local _, ns = ...

local tests = {}

-- A gossip window that says whether it is shown (nil: no such frame).
local function window(shown)
    if shown == nil then return nil end
    local f = {}
    function f:IsShown() return shown end
    return f
end

-- An environment with the newer call answering `rows`.
local function newer(rows, shown)
    local env = { GossipFrame = window(shown), chosen = 0 }
    env.C_GossipInfo = {
        GetOptions = function() return rows end,
        SelectOption = function() env.chosen = env.chosen + 1 end,
    }
    function env.SelectGossipOption() env.chosen = env.chosen + 1 end
    return env
end

tests["gossip options: each option is a row with its type in lower case, icon and name"] = function(t)
    local env = newer({
        { name = "Let me browse your goods.", icon = 132060, type = "Vendor" },
        { name = "I need a ride.", icon = 132057, type = "taxi" },
    }, true)
    local c = ns.make.client(env)
    t.eq(c.gossipOptions(), {
        { type = "vendor", icon = 132060, name = "Let me browse your goods." },
        { type = "taxi", icon = 132057, name = "I need a ride." },
    })
    t.eq(env.chosen, 0, "nothing is chosen")
end

tests["gossip options: a row with no usable type keeps type nil, nothing is derived"] = function(t)
    local env = newer({
        { name = "Make this inn your home.", icon = 132052 },
        { name = "vendor", icon = "vendor", type = 5 },
        { type = "", name = "" },
    }, true)
    local got = ns.make.client(env).gossipOptions()
    t.eq(got, {
        { icon = 132052, name = "Make this inn your home." },
        { name = "vendor" },
        {},
    })
    t.eq(got[1].type, nil, "no type from the words or the icon")
end

tests["gossip options: nil when the window is not shown"] = function(t)
    local env = newer({ { name = "A", type = "vendor" } }, false)
    t.eq(ns.make.client(env).gossipOptions(), nil)
end

tests["gossip options: an open window with no options is an empty list"] = function(t)
    t.eq(ns.make.client(newer({}, true)).gossipOptions(), {})
end

tests["gossip options: no options and no window to ask is not known"] = function(t)
    t.eq(ns.make.client(newer({}, nil)).gossipOptions(), nil, "open or not is not known: no empty list")
    local got = ns.make.client(newer({ { name = "A", type = "banker" } }, nil)).gossipOptions()
    t.eq(got, { { type = "banker", name = "A" } }, "rows the game gave are still told")
end

tests["gossip options: nil when the call is missing, raises or answers no list"] = function(t)
    t.eq(ns.make.client({}).gossipOptions(), nil, "no call")
    t.eq(ns.make.client({ GossipFrame = window(true) }).gossipOptions(), nil, "a window, no call")
    local raises = { GossipFrame = window(true), C_GossipInfo = { GetOptions = function() error("no") end } }
    t.eq(ns.make.client(raises).gossipOptions(), nil, "raises")
    t.eq(ns.make.client(newer("odd", true)).gossipOptions(), nil, "not a list")
    t.eq(ns.make.client(newer({ "odd" }, true)).gossipOptions(), nil, "a row that is no table")
end

tests["gossip options: the older flat list is read as text and type pairs"] = function(t)
    local env = { GossipFrame = window(true) }
    function env.GetGossipOptions() return "Buy", "Vendor", "Fly", "taxi", "Talk", "gossip" end
    t.eq(ns.make.client(env).gossipOptions(), {
        { type = "vendor", name = "Buy" },
        { type = "taxi", name = "Fly" },
        { type = "gossip", name = "Talk" },
    })
end

tests["gossip options: the older list with a missing type, none, or an odd count"] = function(t)
    local env = { GossipFrame = window(true) }
    function env.GetGossipOptions() return "Buy", nil, "Fly", "taxi" end
    t.eq(ns.make.client(env).gossipOptions(), { { name = "Buy" }, { type = "taxi", name = "Fly" } })
    function env.GetGossipOptions() return end
    t.eq(ns.make.client(env).gossipOptions(), {}, "open, no options")
    function env.GetGossipOptions() return "Buy", "vendor", "Fly" end
    t.eq(ns.make.client(env).gossipOptions(), nil, "an odd count is not a list of pairs")
    function env.GetGossipOptions() error("no") end
    t.eq(ns.make.client(env).gossipOptions(), nil, "raises")
end

tests["gossip options: a secret field is not known"] = function(t)
    local env = newer({ { name = "Hidden words", icon = 7, type = "vendor" } }, true)
    function env.issecretvalue(v) return v == "Hidden words" end
    t.eq(ns.make.client(env).gossipOptions(), { { type = "vendor", icon = 7 } })
end

tests["gossip options: the fake answers a copy of what was set, nil when not set"] = function(t)
    local c = ns.make.fakeClient()
    t.eq(c.gossipOptions(), nil, "not set: not known")
    local set = { { type = "vendor", icon = 1, name = "Buy" }, { icon = 2 } }
    c.setGossipOptions(set)
    local got = c.gossipOptions()
    t.eq(got, { { type = "vendor", icon = 1, name = "Buy" }, { icon = 2 } })
    got[1].type = "changed"
    set[2].icon = 9
    t.eq(c.gossipOptions(), { { type = "vendor", icon = 1, name = "Buy" }, { icon = 2 } }, "no table shared")
    c.setGossipOptions({})
    t.eq(c.gossipOptions(), {}, "an open window with no options")
    c.setGossipOptions(nil)
    t.eq(c.gossipOptions(), nil)
end

return tests

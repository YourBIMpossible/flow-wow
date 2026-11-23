-- c.taxiNodes() (lead DISPATCH section 182 item 2; MyBuddy's
-- RESEARCH-FLIGHTS.md section 6, "New client functions" 1): the flight
-- points on the open flight map. The real client over a hand-built
-- environment, then ClientFake's own version. Read only: nothing is
-- taken, selected or clicked, and no frame is made.
--   c.taxiNodes() -> { map = n or nil, here = name or nil,
--                      nodes = { { name, x, y, state } } } or nil
--   state: "current" | "reachable" | "unreachable" | nil (not known)
-- Unknown stays unknown: a failed, missing, odd or secret answer is left
-- out or nil, never a made-up node.
local _, ns = ...

local tests = {}

local function vec(x, y)
    return { x = x, y = y, GetXY = function(self) return self.x, self.y end }
end

-- The newer read: the taxi map 1414 with three nodes. Every call is
-- written in env.calls; the taking calls are there to be refused.
local function newEnv(list)
    local env = { calls = {} }
    local function note(name) env.calls[#env.calls + 1] = name end
    env.Enum = { FlightPathState = { Current = 0, Reachable = 1, Unreachable = 2 } }
    env.GetTaxiMapID = function() note("GetTaxiMapID") return 1414 end
    env.C_TaxiMap = { GetAllTaxiNodes = function(map)
        note("GetAllTaxiNodes")
        if map ~= 1414 then return {} end
        return list or {
            { name = "Orgrimmar", position = vec(0.5, 0.4), state = 0 },
            { name = "Crossroads", position = vec(0.5, 0.6), state = 1 },
            { name = "Far Away", position = vec(0.2, 0.2), state = 2 },
        }
    end }
    for _, name in ipairs({ "TakeTaxiNode", "SelectTaxiNode", "TaxiNodeSetCurrent", "CloseTaxiMap", "CreateFrame" }) do
        env[name] = function() note(name) end
    end
    return env
end

-- The older read only: NumTaxiNodes and its family.
local function oldEnv(kinds)
    local env = newEnv()
    env.C_TaxiMap = nil
    local rows = {
        { "Orgrimmar", 0.5, 0.4 }, { "Crossroads", 0.5, 0.6 }, { "Far Away", 0.2, 0.2 },
    }
    kinds = kinds or { "CURRENT", "REACHABLE", "NONE" }
    env.NumTaxiNodes = function() return #rows end
    env.TaxiNodeName = function(i) return rows[i] and rows[i][1] end
    env.TaxiNodePosition = function(i) return rows[i][2], rows[i][3] end
    env.TaxiNodeGetType = function(i) return kinds[i] end
    return env
end

local function taken(env)
    for _, name in ipairs(env.calls) do
        if name == "TakeTaxiNode" or name == "SelectTaxiNode" or name == "TaxiNodeSetCurrent"
            or name == "CloseTaxiMap" or name == "CreateFrame" then
            return name
        end
    end
    return nil
end

tests["c.taxiNodes: the newer read gives name, place and state, and where you stand"] = function(t)
    local env = newEnv()
    t.eq(ns.make.client(env).taxiNodes(), { map = 1414, here = "Orgrimmar", nodes = {
        { name = "Orgrimmar", x = 0.5, y = 0.4, state = "current" },
        { name = "Crossroads", x = 0.5, y = 0.6, state = "reachable" },
        { name = "Far Away", x = 0.2, y = 0.2, state = "unreachable" },
    } })
    t.eq(taken(env), nil, "nothing taken, selected or made")
end

tests["c.taxiNodes: a plain { x, y } position is read too"] = function(t)
    local env = newEnv({ { name = "Crossroads", position = { x = 0.5, y = 0.6 }, state = 1 } })
    t.eq(ns.make.client(env).taxiNodes(), { map = 1414, nodes = {
        { name = "Crossroads", x = 0.5, y = 0.6, state = "reachable" },
    } })
end

tests["c.taxiNodes: the older read when the newer is missing; a kind not known is no state"] = function(t)
    local env = oldEnv()
    t.eq(ns.make.client(env).taxiNodes(), { map = 1414, here = "Orgrimmar", nodes = {
        { name = "Orgrimmar", x = 0.5, y = 0.4, state = "current" },
        { name = "Crossroads", x = 0.5, y = 0.6, state = "reachable" },
        { name = "Far Away", x = 0.2, y = 0.2 },
    } })
    t.eq(taken(env), nil)
end

tests["c.taxiNodes: no flight map open, or no reads at all, gives nil"] = function(t)
    t.eq(ns.make.client({}).taxiNodes(), nil, "no reads")
    t.eq(ns.make.client(newEnv({})).taxiNodes(), nil, "the map lists no node: closed")
    local closed = oldEnv()
    closed.NumTaxiNodes = function() return 0 end
    t.eq(ns.make.client(closed).taxiNodes(), nil, "NumTaxiNodes 0: closed")
    local noMap = newEnv()
    noMap.GetTaxiMapID = function() return nil end
    t.eq(ns.make.client(noMap).taxiNodes(), nil, "no taxi map and no older read")
end

tests["c.taxiNodes: a read that raises, or odd answers, give nothing made up"] = function(t)
    local raised = newEnv()
    raised.C_TaxiMap.GetAllTaxiNodes = function() error("no") end
    t.eq(ns.make.client(raised).taxiNodes(), nil, "raised")
    t.eq(ns.make.client(newEnv("lots")).taxiNodes(), nil, "a list that is no table")
    local odd = newEnv({
        { name = 5, position = vec(0.1, 0.1), state = 1 },
        { name = "", position = vec(0.1, 0.1), state = 1 },
        { name = "No Place", state = 1 },
        { name = "Text Place", position = vec("a", 0.1), state = 1 },
        { name = "Not A Number", position = vec(0 / 0, 0.1), state = 1 },
        { name = "Odd State", position = vec(0.3, 0.3), state = 9 },
        "not a node",
    })
    t.eq(ns.make.client(odd).taxiNodes(), { map = 1414, nodes = {
        { name = "Odd State", x = 0.3, y = 0.3 },
    } })
    local oldOdd = oldEnv()
    oldOdd.NumTaxiNodes = function() return "three" end
    t.eq(ns.make.client(oldOdd).taxiNodes(), nil, "a count that is no number")
    local noEnum = newEnv()
    noEnum.Enum = nil
    t.eq(ns.make.client(noEnum).taxiNodes(), { map = 1414, nodes = {
        { name = "Orgrimmar", x = 0.5, y = 0.4 },
        { name = "Crossroads", x = 0.5, y = 0.6 },
        { name = "Far Away", x = 0.2, y = 0.2 },
    } }, "no state names from the client: no state is guessed, and no here")
end

tests["c.taxiNodes: a secret name or place leaves that node out; a secret state is not known"] = function(t)
    local env = newEnv({
        { name = "Hidden Name", position = vec(0.1, 0.1), state = 1 },
        { name = "Hidden Place", position = vec(0.25, 0.1), state = 1 },
        { name = "Hidden State", position = vec(0.3, 0.3), state = 7 },
        { name = "Crossroads", position = vec(0.5, 0.6), state = 1 },
    })
    env.issecretvalue = function(v)
        if v == nil then error("issecretvalue: nil") end
        return v == "Hidden Name" or v == 0.25 or v == 7
    end
    env.Enum.FlightPathState.Current = 7       -- the hidden state would have read "current"
    t.eq(ns.make.client(env).taxiNodes(), { map = 1414, nodes = {
        { name = "Hidden State", x = 0.3, y = 0.3 },
        { name = "Crossroads", x = 0.5, y = 0.6, state = "reachable" },
    } }, "and no here from a hidden state")
    local secretList = newEnv()
    secretList.issecretvalue = function(v)
        if v == nil then error("issecretvalue: nil") end
        return type(v) == "table" and v[1] ~= nil
    end
    t.eq(ns.make.client(secretList).taxiNodes(), nil, "the whole list hidden")
    local secretMap = newEnv()
    secretMap.issecretvalue = function(v)
        if v == nil then error("issecretvalue: nil") end
        return v == 1414
    end
    t.eq(ns.make.client(secretMap).taxiNodes(), nil, "the map hidden, and no older read")
end

tests["c.taxiNodes: look only - no taxi action and no frame, map open or closed"] = function(t)
    for _, env in ipairs({ newEnv(), oldEnv(), newEnv({}) }) do
        local c = ns.make.client(env)
        c.taxiNodes()
        c.taxiNodes()
        t.eq(taken(env), nil)
    end
end

tests["fake taxiNodes: unknown until set, a copy, nil again when cleared"] = function(t)
    local c = ns.make.fakeClient()
    t.eq(c.taxiNodes(), nil)
    local read = { map = 1414, here = "Orgrimmar", nodes = { { name = "Orgrimmar", x = 0.5, y = 0.4, state = "current" } } }
    c.setTaxiNodes(read)
    local got = c.taxiNodes()
    t.eq(got, read)
    got.nodes[1].name = "changed"
    t.eq(c.taxiNodes().nodes[1].name, "Orgrimmar", "a copy")
    c.setTaxiNodes(nil)
    t.eq(c.taxiNodes(), nil)
end

return tests

-- F-32: c.clickBindings() (C_ClickBindings.GetProfileInfo) and
-- c.mouseFoci() (GetMouseFoci, else GetMouseFocus). The real client over
-- a hand-built environment, then ClientFake's twin.
local _, ns = ...

local tests = {}

local function newEnv(secret)
    local env = {}
    function env.issecretvalue(v)
        if v == nil then error("issecretvalue: nil") end
        return secret ~= nil and v == secret
    end
    return env
end

local function frame(debugName, name)
    local f = {}
    if debugName ~= nil then function f:GetDebugName() return debugName end end
    if name ~= nil then function f:GetName() return name end end
    return f
end

tests["client clickBindings: each binding's type, action, button and modifiers"] = function(t)
    local env = newEnv()
    env.C_ClickBindings = { GetProfileInfo = function()
        return {
            { type = 1, actionID = 2061, button = "LeftButton", modifiers = 1 },
            "not a row",
            { type = 4, actionID = 1, button = "RightButton", modifiers = 0 },
        }
    end }
    t.eq(ns.make.client(env).clickBindings(), {
        { type = 1, actionID = 2061, button = "LeftButton", modifiers = 1 },
        { type = 4, actionID = 1, button = "RightButton", modifiers = 0 },
    })
end

tests["client clickBindings: none to read is nil; a secret field is left out"] = function(t)
    t.eq(ns.make.client(newEnv()).clickBindings(), nil)
    local broken = newEnv()
    broken.C_ClickBindings = { GetProfileInfo = function() error("no") end }
    t.eq(ns.make.client(broken).clickBindings(), nil)
    local env = newEnv(2061)
    env.C_ClickBindings = { GetProfileInfo = function()
        return { { type = 1, actionID = 2061, button = "LeftButton", modifiers = 0 } }
    end }
    t.eq(ns.make.client(env).clickBindings(), { { type = 1, button = "LeftButton", modifiers = 0 } })
end

tests["client mouseFoci: names from GetMouseFoci, debug name first, unnamed skipped"] = function(t)
    local env = newEnv()
    function env.GetMouseFoci() return { frame("PlayerFrame.Button", "PlayerFrame"), frame(nil, "WorldFrame"), frame(nil, nil) } end
    function env.GetMouseFocus() return frame(nil, "Older") end
    t.eq(ns.make.client(env).mouseFoci(), { "PlayerFrame.Button", "WorldFrame" })
end

tests["client mouseFoci: GetMouseFocus when there is no GetMouseFoci; neither is nil"] = function(t)
    local env = newEnv()
    function env.GetMouseFocus() return frame(nil, "TargetFrame") end
    t.eq(ns.make.client(env).mouseFoci(), { "TargetFrame" })
    t.eq(ns.make.client(newEnv()).mouseFoci(), nil)
    local broken = newEnv()
    function broken.GetMouseFoci() error("no") end
    t.eq(ns.make.client(broken).mouseFoci(), nil)
    local raising = newEnv("Secret")
    function raising.GetMouseFoci()
        local f = {}
        function f:GetDebugName() error("restricted") end
        return { f, frame("Secret", "Plain") }
    end
    t.eq(ns.make.client(raising).mouseFoci(), { "Plain" }, "a name that raises or is secret falls to the next")
end

tests["fake clickBindings and mouseFoci: nil until set, then copies"] = function(t)
    local c = ns.make.fakeClient()
    t.eq({ c.clickBindings(), c.mouseFoci() }, {})
    local list = { { type = 1, actionID = 5, button = "LeftButton", modifiers = 0 } }
    c.setClickBindings(list)
    c.setMouseFoci({ "PlayerFrame" })
    local got = c.clickBindings()
    list[1].actionID = 9
    t.eq(got, { { type = 1, actionID = 5, button = "LeftButton", modifiers = 0 } })
    t.eq(c.mouseFoci(), { "PlayerFrame" })
end

return tests

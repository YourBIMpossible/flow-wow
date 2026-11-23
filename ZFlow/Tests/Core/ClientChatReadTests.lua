-- N60b chat readability: the client's chat window calls (Core/Client.lua
-- chatFont, setChatFont, chatFading, setChatFading, chatWheel, chatTabAlpha,
-- localTime). The real client over a hand-built environment (`env` stands
-- in for the game's globals). Every call read here is a first guess, not
-- seen in game on 16001.
-- Fails before: the client has none of them (c.chatFont is nil).
local _, ns = ...

local tests = {}

local SECRET = {}

local function window()
    local f = { path = "Fonts\\FRIZQT__.TTF", size = 14, flags = "", fading = true, visible = 120, moves = {},
        scripts = {} }
    function f:GetFont() return self.path, self.size, self.flags end
    function f:SetFont(path, size, flags) self.path, self.size, self.flags = path, size, flags end
    function f:GetFading() return self.fading end
    function f:SetFading(on) self.fading = on end
    function f:GetTimeVisible() return self.visible end
    function f:SetTimeVisible(n) self.visible = n end
    function f:HookScript(name, fn) self.scripts[name] = fn end
    function f:ScrollUp() self.moves[#self.moves + 1] = "up" end
    function f:ScrollDown() self.moves[#self.moves + 1] = "down" end
    function f:ScrollToTop() self.moves[#self.moves + 1] = "top" end
    function f:ScrollToBottom() self.moves[#self.moves + 1] = "bottom" end
    return f
end

local function tab()
    local b = { alpha = 1 }
    function b:SetAlpha(a) self.alpha = a end
    function b:GetAlpha() return self.alpha end
    return b
end

local function gameEnv()
    local env = { ChatFrame1 = window(), ChatFrame1Tab = tab(), keys = {} }
    env.issecretvalue = function(v) return v == SECRET end
    env.hooksecurefunc = function(obj, name, hook)
        local plain = obj[name]
        obj[name] = function(...)
            local a, b, c3 = plain(...)
            hook(...)
            return a, b, c3
        end
    end
    env.IsControlKeyDown = function() return env.keys.ctrl == true end
    env.IsShiftKeyDown = function() return env.keys.shift == true end
    return env
end

local function has(t, c)
    local ok = type(c.chatFont) == "function" and type(c.setChatFont) == "function"
        and type(c.chatFading) == "function" and type(c.setChatFading) == "function"
        and type(c.chatWheel) == "function" and type(c.chatTabAlpha) == "function"
        and type(c.localTime) == "function"
    t.ok(ok, "the client has the chat readability calls")
    return ok
end

tests["client chat read: font size read and set, path and flags kept"] = function(t)
    local env = gameEnv()
    local c = ns.make.client(env)
    if not has(t, c) then return end
    t.eq(c.chatFont(1), 14)
    t.eq(c.setChatFont(1, 18), true)
    t.eq({ env.ChatFrame1.path, env.ChatFrame1.size, env.ChatFrame1.flags }, { "Fonts\\FRIZQT__.TTF", 18, "" })
    t.eq(c.chatFont(2), nil, "no window 2")
    t.eq(c.setChatFont(2, 18), nil)
    env.ChatFrame1.GetFont = function() return SECRET, SECRET, SECRET end
    t.eq(c.chatFont(1), nil, "a hidden answer is not read")
    t.eq(c.setChatFont(1, 12), nil, "nor written over")
    env.ChatFrame1.GetFont = function() error("raised") end
    t.eq(c.chatFont(1), nil, "a raise is nil")
end

tests["client chat read: fading read and set"] = function(t)
    local env = gameEnv()
    local c = ns.make.client(env)
    if not has(t, c) then return end
    t.eq(c.chatFading(1), { fading = true, time = 120 })
    t.eq(c.setChatFading(1, false, 300), true)
    t.eq({ env.ChatFrame1.fading, env.ChatFrame1.visible }, { false, 300 })
    t.eq(c.setChatFading(1, true), true, "no time: only the fading")
    t.eq({ env.ChatFrame1.fading, env.ChatFrame1.visible }, { true, 300 })
    t.eq(c.setChatFading(1, "yes"), nil)
    t.eq(c.chatFading(3), nil)
end

tests["client chat read: the wheel hook runs after the game's and does what fn answers"] = function(t)
    local env = gameEnv()
    local c = ns.make.client(env)
    if not has(t, c) then return end
    local seen = {}
    local cancel = c.chatWheel(1, function(delta, ctrl, shift)
        seen[#seen + 1] = { delta, ctrl, shift }
        if ctrl then return "top" end
        if shift then return "bottom" end
        return 2
    end)
    t.eq(type(cancel), "function")
    local hook = env.ChatFrame1.scripts.OnMouseWheel
    t.eq(type(hook), "function", "hooked, not set")
    if type(hook) ~= "function" then return end
    hook(env.ChatFrame1, 1)
    t.eq(env.ChatFrame1.moves, { "up", "up" })
    env.keys.ctrl = true
    hook(env.ChatFrame1, -1)
    env.keys.ctrl, env.keys.shift = false, true
    hook(env.ChatFrame1, 1)
    t.eq(env.ChatFrame1.moves, { "up", "up", "top", "bottom" })
    t.eq(seen, { { 1, false, false }, { -1, true, false }, { 1, false, true } })
    hook(env.ChatFrame1, SECRET)
    t.eq(#seen, 3, "a hidden delta is not read")
    cancel()
    env.keys.shift = false
    hook(env.ChatFrame1, -1)
    t.eq(#env.ChatFrame1.moves, 4, "after cancel the hook does nothing")
    -- Hooked once: a second fn takes the same hook.
    t.eq(type(c.chatWheel(1, function() return 1 end)), "function")
    t.eq(env.ChatFrame1.scripts.OnMouseWheel, hook)
    env.ChatFrame1.HookScript = nil
    t.eq(c.chatWheel(2, function() end), nil, "no window 2")
end

tests["client chat read: tab alpha held above the game's fade, then given back"] = function(t)
    local env = gameEnv()
    local c = ns.make.client(env)
    if not has(t, c) then return end
    local tabFrame = env.ChatFrame1Tab
    tabFrame:SetAlpha(0.4)
    t.eq(c.chatTabAlpha(1, 1), true)
    t.eq(tabFrame.alpha, 1)
    tabFrame:SetAlpha(0)
    t.eq(tabFrame.alpha, 1, "the game's fade is held off")
    t.eq(c.chatTabAlpha(1, nil), true)
    t.eq(tabFrame.alpha, 0, "released: what the game asked last")
    tabFrame:SetAlpha(0.2)
    t.eq(tabFrame.alpha, 0.2)
    t.eq(c.chatTabAlpha(4, 1), nil, "no tab 4")
end

tests["client chat read: local time from date, nil when it raises"] = function(t)
    local env = gameEnv()
    env.date = function(fmt)
        if fmt ~= "*t" then return nil end
        return { hour = 9, min = 5, sec = 7 }
    end
    local c = ns.make.client(env)
    if not has(t, c) then return end
    t.eq({ c.localTime() }, { 9, 5, 7 })
    env.date = function() error("raised") end
    t.eq(c.localTime(), nil)
end

return tests

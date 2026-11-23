-- N59 (lead section 243): the info bar frame and the reads it shows, on the
-- real client boundary with a stand-in for the globals of the game, on the
-- fake client, and in the capture (Diag.NAMES and its fields). No game
-- client is involved. Made-up values only.
local _, ns = ...

-- A stand-in for the game globals. Every frame and region made is in
-- env.made, in order; a method the stand-in has no answer for is recorded
-- in o.calls and answers nothing. A field never set is read with rawget:
-- the stand-in answers every missing key with a method.
local function gameEnv()
    local env = { made = {}, UIParent = {}, tipLines = {} }
    local function obj(kind, name, parent, template)
        local o = { kind = kind, name = name, parent = parent, template = template, scripts = {},
                    calls = {}, shown = true, w = 200, h = 20 }
        setmetatable(o, { __index = function(_, key)
            return function(_, ...) o.calls[#o.calls + 1] = { key, ... } end
        end })
        function o:SetScript(script, fn) self.scripts[script] = fn end
        function o:GetPoint() return "TOP", env.UIParent, "TOP", 5, -30 end
        function o:IsShown() return self.shown end
        function o:Show() self.shown = true end
        function o:Hide() self.shown = false end
        function o:SetSize(w, h) self.w, self.h = w, h end
        function o:GetWidth() return self.w end
        function o:GetHeight() return self.h end
        function o:SetText(text) self.text = text end
        function o:SetFont(path, size, flags) self.font = { path, size, flags } end
        function o:GetFont() return "Fonts\\TEST.TTF", 12, "" end
        function o:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
        function o:SetMovable(on) self.movable = on end
        function o:SetResizable(on) self.resizable = on end
        function o:StartMoving() self.moving = true end
        function o:StartSizing(corner) self.sizing = corner end
        function o:StopMovingOrSizing() self.moving, self.sizing = false, nil end
        function o:SetAttribute(key, value)
            self.attributes = self.attributes or {}
            self.attributes[key] = value
        end
        function o:CreateTexture()
            local r = obj("Texture", nil, o)
            env.made[#env.made + 1] = r
            return r
        end
        function o:CreateFontString()
            local r = obj("FontString", nil, o)
            env.made[#env.made + 1] = r
            return r
        end
        return o
    end
    function env.CreateFrame(kind, name, parent, template)
        local f = obj(kind, name, parent, template)
        env.made[#env.made + 1] = f
        return f
    end
    env.GameTooltip = {
        SetOwner = function(self, owner) self.owner = owner end,
        ClearLines = function() env.tipLines = {} end,
        AddLine = function(_, line) env.tipLines[#env.tipLines + 1] = line end,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
        IsOwned = function(self, f) return self.owner == f end,
    }
    return env
end

local function find(env, kind)
    local out = {}
    for _, o in ipairs(env.made) do
        if o.kind == kind then out[#out + 1] = o end
    end
    return out
end

local function bar(env)
    return ns.make.client(env).infoBar({ name = "TestInfoBar", width = 300, height = 20 })
end

local function listed(name)
    for _, n in ipairs(ns.Diag and ns.Diag.NAMES or {}) do
        if n == name then return true end
    end
    return false
end

local function shapes(e)
    return ns.Diag.Collect(ns.Kernel({}, ns.make.fakeClient({ env = e })), "test").shapes
end

return {
    ["info bar client: one frame with a backing and a text, hidden until shown"] = function(t)
        local env = gameEnv()
        local h = bar(env)
        t.ok(type(h) == "table", "a handle")
        if type(h) ~= "table" then return end
        local frame = find(env, "Frame")[1]
        t.eq(frame.shown, false, "hidden at first")
        h.setText("Gold 1g")
        t.eq(find(env, "FontString")[1].text, "Gold 1g")
        h.show(true)
        t.eq(frame.shown, true)
        h.show(false)
        t.eq(frame.shown, false)
    end,

    ["info bar client: no frame maker, no handle"] = function(t)
        local c = ns.make.client({ UIParent = {} })
        t.ok(type(c.infoBar) == "function", "the client has an info bar maker")
        if type(c.infoBar) ~= "function" then return end
        t.eq(c.infoBar({ name = "X" }), nil)
    end,

    ["info bar client: font size keeps the font file, opacity is the backing alpha"] = function(t)
        local env = gameEnv()
        local h = bar(env)
        t.ok(type(h) == "table", "a handle")
        if type(h) ~= "table" then return end
        h.font(16)
        t.eq(find(env, "FontString")[1].font, { "Fonts\\TEST.TTF", 16, "" })
        h.alpha(0.25)
        -- The backing keeps the theme's fill colour (lead section 350); only
        -- the opacity is the player's.
        local fill = ns.Kit.look.color.fill
        t.eq(find(env, "Texture")[1].color, { fill[1], fill[2], fill[3], 0.25 })
    end,

    ["info bar client: dragged when unlocked, not when locked"] = function(t)
        local env = gameEnv()
        local h = bar(env)
        t.ok(type(h) == "table", "a handle")
        if type(h) ~= "table" then return end
        local frame = find(env, "Frame")[1]
        local moved
        h.onMoved(function(point) moved = point end)
        h.lock(true)
        frame.scripts.OnDragStart(frame)
        t.eq(rawget(frame, "moving"), nil, "locked: no move")
        h.lock(false)
        frame.scripts.OnDragStart(frame)
        t.eq(rawget(frame, "moving"), true)
        frame.scripts.OnDragStop(frame)
        t.eq(moved, { "TOP", "TOP", 5, -30 })
    end,

    ["info bar client: the grip resizes when unlocked and says the new size"] = function(t)
        local env = gameEnv()
        local h = bar(env)
        t.ok(type(h) == "table", "a handle")
        if type(h) ~= "table" then return end
        local frame = find(env, "Frame")[1]
        local grip = find(env, "Button")[1]
        t.ok(grip ~= nil, "a grip")
        if not grip then return end
        local size
        h.onResized(function(w, ht) size = { w, ht } end)
        grip.scripts.OnMouseDown(grip, "LeftButton")
        t.eq(rawget(frame, "sizing"), "BOTTOMRIGHT")
        frame.w, frame.h = 360, 40
        grip.scripts.OnMouseUp(grip, "LeftButton")
        t.eq(size, { 360, 40 })
        h.lock(true)
        grip.scripts.OnMouseDown(grip, "LeftButton")
        t.eq(rawget(frame, "sizing"), nil, "locked: no resize")
    end,

    ["info bar client: a click is said, but not the release of a drag"] = function(t)
        local env = gameEnv()
        local h = bar(env)
        t.ok(type(h) == "table", "a handle")
        if type(h) ~= "table" then return end
        local frame = find(env, "Frame")[1]
        local clicks = {}
        h.onClick(function(button) clicks[#clicks + 1] = button end)
        frame.scripts.OnDragStart(frame)
        frame.scripts.OnDragStop(frame)
        frame.scripts.OnMouseUp(frame, "LeftButton")
        t.eq(clicks, {}, "the end of a drag is no click")
        frame.scripts.OnMouseUp(frame, "RightButton")
        t.eq(clicks, { "RightButton" })
    end,

    ["info bar client: hover is said, and the tip shows the lines given"] = function(t)
        local env = gameEnv()
        local h = bar(env)
        t.ok(type(h) == "table", "a handle")
        if type(h) ~= "table" then return end
        local frame = find(env, "Frame")[1]
        local seen = {}
        h.onHover(function(on) seen[#seen + 1] = on end)
        frame.scripts.OnEnter(frame)
        h.tip({ "Gold: 1g", "Free bag slots: 3 of 16" })
        t.eq(env.tipLines, { "Gold: 1g", "Free bag slots: 3 of 16" })
        t.eq(env.GameTooltip.shown, true)
        frame.scripts.OnLeave(frame)
        h.tip(nil)
        t.eq(env.GameTooltip.shown, false)
        t.eq(seen, { true, false })
    end,

    ["info bar client: no secure template and no macro type on any frame"] = function(t)
        local env = gameEnv()
        bar(env)
        t.ok(#env.made > 0, "frames made")
        for _, o in ipairs(env.made) do
            t.ok(o.template == nil or not tostring(o.template):find("Secure"), "no secure template")
            t.eq(rawget(o, "attributes"), nil, "no attribute set")
        end
    end,

    ["info bar reads: experience with rested, nil when not answered"] = function(t)
        local e = { UnitXP = function() return 450 end, UnitXPMax = function() return 1000 end,
                    GetXPExhaustion = function() return 200 end }
        local function xp(env)
            local c = ns.make.client(env)
            if type(c.xp) ~= "function" then return "no read" end
            return c.xp()
        end
        t.eq(xp(e), { cur = 450, max = 1000, rested = 200 })
        e.GetXPExhaustion = function() return nil end
        t.eq(xp(e), { cur = 450, max = 1000, rested = 0 }, "not rested")
        e.UnitXPMax = function() return 0 end
        t.eq(xp(e), nil, "no required amount")
        t.eq(xp({}), nil, "no read")
    end,

    ["info bar reads: the watched faction, false when none, nil when not answered"] = function(t)
        local function rep(env)
            local c = ns.make.client(env)
            if type(c.watchedFaction) ~= "function" then return "no read" end
            return c.watchedFaction()
        end
        local e = { GetWatchedFactionInfo = function() return "Test Faction", 5, 3000, 9000, 3300 end,
                    FACTION_STANDING_LABEL5 = "Friendly" }
        t.eq(rep(e), { name = "Test Faction", standing = 5, label = "Friendly", min = 3000, max = 9000, value = 3300 })
        e.GetWatchedFactionInfo = function() return nil end
        t.eq(rep(e), false, "none watched")
        t.eq(rep({}), nil, "no read")
        local n = { C_Reputation = { GetWatchedFactionData = function()
            return { name = "New Faction", reaction = 4, currentReactionThreshold = 0,
                     nextReactionThreshold = 3000, currentStanding = 100 }
        end }, FACTION_STANDING_LABEL4 = "Neutral" }
        t.eq(rep(n), { name = "New Faction", standing = 4, label = "Neutral", min = 0, max = 3000, value = 100 })
    end,

    ["info bar reads: server time, frame rate and latency, nil when not answered"] = function(t)
        local function read(env, name)
            local c = ns.make.client(env)
            if type(c[name]) ~= "function" then return "no read" end
            return c[name]()
        end
        local e = { GetGameTime = function() return 14, 5 end, GetFramerate = function() return 59.7 end,
                    GetNetStats = function() return 1, 2, 40, 45 end }
        t.eq(read(e, "gameTime"), { hour = 14, minute = 5 })
        t.eq(read(e, "framerate"), 59)
        t.eq(read(e, "latency"), { home = 40, world = 45 })
        t.eq(read({}, "gameTime"), nil)
        t.eq(read({}, "framerate"), nil)
        t.eq(read({}, "latency"), nil)
        local bad = { GetGameTime = function() return "x" end, GetNetStats = function() error("no") end }
        t.eq(read(bad, "gameTime"), nil)
        t.eq(read(bad, "latency"), nil)
    end,

    ["info bar reads: the data broker only where the library is already loaded"] = function(t)
        local function broker(env, name, obj)
            local c = ns.make.client(env)
            if type(c.broker) ~= "function" then return "no read" end
            return c.broker(name, obj)
        end
        t.eq(broker({}, "Z", { text = "x" }), nil, "no LibStub")
        local made
        local lib = { NewDataObject = function(_, name, obj)
            made = { name, obj }
            return obj
        end }
        local e = { LibStub = function(name, silent)
            if name == "LibDataBroker-1.1" and silent then return lib end
            return nil
        end }
        local obj = { type = "data source", text = "x" }
        t.eq(broker(e, "TestBar", obj), obj)
        t.eq(made, { "TestBar", obj })
        t.eq(broker({ LibStub = function() return nil end }, "Z", {}), nil, "no library")
    end,

    ["info bar fake: the reads are what the test set, unknown until set"] = function(t)
        local c = ns.make.fakeClient()
        t.ok(type(c.setXp) == "function", "the fake has the setters")
        if type(c.setXp) ~= "function" then return end
        t.eq(c.xp(), nil)
        t.eq(c.watchedFaction(), nil)
        t.eq(c.gameTime(), nil)
        t.eq(c.framerate(), nil)
        t.eq(c.latency(), nil)
        c.setXp({ cur = 1, max = 2, rested = 0 })
        c.setWatchedFaction(false)
        c.setGameTime(9, 30)
        c.setFramerate(60)
        c.setLatency(20, 30)
        t.eq(c.xp(), { cur = 1, max = 2, rested = 0 })
        t.eq(c.watchedFaction(), false)
        t.eq(c.gameTime(), { hour = 9, minute = 30 })
        t.eq(c.framerate(), 60)
        t.eq(c.latency(), { home = 20, world = 30 })
    end,

    ["info bar fake: the bar keeps what it was told; a locked bar is not dragged"] = function(t)
        local c = ns.make.fakeClient()
        t.ok(type(c.infoBar) == "function", "the fake makes info bars")
        if type(c.infoBar) ~= "function" then return end
        local h = c.infoBar({ name = "X", width = 300, height = 20 })
        local b = c.infoBars[1]
        h.setText("a")
        h.show(true)
        h.font(14)
        h.alpha(0.5)
        h.size(320, 24)
        h.place({ "TOP", "TOP", 0, -10 })
        t.eq({ b.text, b.shown, b.fontSize, b.alpha, b.width, b.height }, { "a", true, 14, 0.5, 320, 24 })
        t.eq(b.point, { "TOP", "TOP", 0, -10 })
        local moved, sized, clicked, hovered
        h.onMoved(function(p) moved = p end)
        h.onResized(function(w, ht) sized = { w, ht } end)
        h.onClick(function(button) clicked = button end)
        h.onHover(function(on) hovered = on end)
        h.lock(true)
        b.drag({ "CENTER", "CENTER", 1, 1 })
        b.resize(400, 30)
        t.eq(moved, nil, "locked: no drag")
        t.eq(sized, nil, "locked: no resize")
        h.lock(false)
        b.drag({ "CENTER", "CENTER", 1, 1 })
        b.resize(400, 30)
        b.click("LeftButton")
        b.hover(true)
        t.eq(moved, { "CENTER", "CENTER", 1, 1 })
        t.eq(sized, { 400, 30 })
        t.eq(clicked, "LeftButton")
        t.eq(hovered, true)
        h.tip({ "x" })
        t.eq(b.tipLines, { "x" })
        c.setFrames(false)
        t.eq(c.infoBar({ name = "Y" }), nil)
    end,

    ["info bar capture: every new read is named and has its capture field"] = function(t)
        for _, name in ipairs({ "UnitXP", "UnitXPMax", "GetXPExhaustion", "GetWatchedFactionInfo",
                                "C_Reputation.GetWatchedFactionData", "GetGameTime", "GetFramerate",
                                "GetNetStats", "LibStub", "FACTION_STANDING_LABEL1" }) do
            t.ok(listed(name), name .. " in Diag.NAMES")
        end
        local e = { UnitXP = function() return 450 end, UnitXPMax = function() return 1000 end,
                    GetXPExhaustion = function() return 200 end,
                    GetWatchedFactionInfo = function() return "Test Faction", 5, 3000, 9000, 3300 end,
                    GetGameTime = function() return 14, 5 end, GetFramerate = function() return 60 end,
                    GetNetStats = function() return 1, 2, 40, 45 end }
        local s = shapes(e)
        local function field(name)
            return type(s[name]) == "table" and s[name] or { values = {} }
        end
        t.eq(field("xp").values.v1, 450)
        t.eq(field("xpMax").values.v1, 1000)
        t.eq(field("xpRested").values.v1, 200)
        t.eq(field("watchedFaction").values.v1, "Test Faction")
        t.eq(field("watchedFaction").values.v5, 3300)
        t.eq(field("watchedFactionNew").ok, false, "a call the client lacks is recorded, not an error")
        t.eq(field("gameTime").values.v2, 5)
        t.eq(field("framerate").values.v1, 60)
        t.eq(field("netStats").values.v4, 45)
    end,
}

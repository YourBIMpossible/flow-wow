-- c.taxiMark() and c.mapPins() (lead DISPATCH section 187 section 7): the
-- ring on the open flight map and the flight points on the world map. The
-- real client over a hand-built environment, then ClientFake's own twins.
-- LOOK ONLY: plain frames that take no mouse, no secure template, no taxi
-- action, no CVar.
--   c.taxiMark() -> h or nil      h.mark({ name, x, y }, text) -> true | false; h.hide()
--   c.mapPins()  -> h or nil      h.map() -> uiMapID shown or nil;
--                                 h.draw(pins, lines); h.clear()
local _, ns = ...

local tests = {}

-- A frame, texture, line or font string that writes down what is done to it.
local function region(kind, parent)
    local f = { kind = kind, parent = parent, shown = true, made = {} }
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:SetSize(w, h) self.w, self.h = w, h end
    function f:EnableMouse(on) self.mouse = on end
    function f:ClearAllPoints() self.point = nil end
    function f:SetPoint(...) self.point = { ... } end
    function f:SetAllPoints(to) self.all = to end
    function f:SetColorTexture(...) self.colour = { ... } end
    function f:SetText(text) self.text = text end
    function f:SetThickness(n) self.thick = n end
    function f:SetStartPoint(...) self.from = { ... } end
    function f:SetEndPoint(...) self.to = { ... } end
    function f:CreateTexture() local r = region("Texture", self); self.made[#self.made + 1] = r; return r end
    function f:CreateFontString() local r = region("FontString", self); self.made[#self.made + 1] = r; return r end
    function f:CreateLine() local r = region("Line", self); self.made[#self.made + 1] = r; return r end
    return f
end

-- opts.secret: the one value issecretvalue calls secret (it refuses nil,
-- as the game's may); opts.noFrames; opts.mapID; opts.names: what
-- TaxiNodeName answers by index.
local function newEnv(opts)
    opts = opts or {}
    local env = { frames = {}, calls = {} }
    local function note(name) env.calls[#env.calls + 1] = name end
    function env.issecretvalue(v)
        if v == nil then error("issecretvalue: nil") end
        return opts.secret ~= nil and v == opts.secret
    end
    function env.CreateFrame(kind, name, parent, template)
        note("CreateFrame")
        if opts.noFrames then error("no frames") end
        local f = region(kind, parent)
        f.name, f.template = name, template
        env.frames[#env.frames + 1] = f
        return f
    end
    env.TaxiFrame = region("Frame")
    env.TaxiRouteMap = region("Frame")
    function env.TaxiRouteMap:GetWidth() return 300 end
    function env.TaxiRouteMap:GetHeight() return 400 end
    local names = opts.names or { "Home Post", "Far Post" }
    env.NumTaxiNodes = function() note("NumTaxiNodes") return #names end
    env.TaxiNodeName = function(i) note("TaxiNodeName") return names[i] end
    env.TaxiButton2 = region("Button")
    function env.TaxiButton2:IsVisible() return true end
    env.WorldMapFrame = region("Frame")
    function env.WorldMapFrame:GetMapID() return opts.mapID == nil and 1414 or opts.mapID end
    local canvas = region("Frame")
    function canvas:GetWidth() return 1000 end
    function canvas:GetHeight() return 500 end
    env.WorldMapFrame.ScrollContainer = { Child = canvas }
    env.canvas = canvas
    for _, name in ipairs({ "TakeTaxiNode", "SelectTaxiNode", "TaxiNodeSetCurrent", "CloseTaxiMap", "SetCVar" }) do
        env[name] = function() note(name) end
    end
    env.C_CVar = { SetCVar = function() note("C_CVar.SetCVar") end }
    return env
end

-- The first look-only fault in env, or nil.
local function fault(env)
    for _, name in ipairs(env.calls) do
        if name ~= "CreateFrame" and name ~= "NumTaxiNodes" and name ~= "TaxiNodeName" then return name end
    end
    for _, f in ipairs(env.frames) do
        if f.template ~= nil then return "a frame with a template: " .. tostring(f.template) end
        if f.mouse ~= false then return "a frame that may take the mouse" end
    end
    return nil
end

tests["client taxiMark: hidden when made, on the flight map, no mouse, no template"] = function(t)
    local env = newEnv()
    local h = ns.make.client(env).taxiMark()
    t.ok(h ~= nil, "made")
    local f = env.frames[1]
    t.ok(f.parent == env.TaxiFrame, "on the flight map")
    t.eq({ f.shown, f.mouse, f.template }, { false, false, nil })
    t.eq(fault(env), nil)
end

tests["client taxiMark: mark rings the node's own button and says the words; hide hides"] = function(t)
    local env = newEnv()
    local h = ns.make.client(env).taxiMark()
    local f = env.frames[1]
    t.eq(h.mark({ name = "Far Post", x = 0.5, y = 0.25 }, "Z-Flow: Wolves"), true)
    t.eq(f.shown, true)
    t.eq({ f.point[1], f.point[3], f.point[4], f.point[5] }, { "CENTER", "CENTER", 0, 0 })
    t.ok(f.point[2] == env.TaxiButton2, "at the button")
    local label
    for _, r in ipairs(f.made) do if r.kind == "FontString" then label = r end end
    t.ok(label ~= nil, "a label")
    t.eq(label and label.text, "Z-Flow: Wolves")
    h.hide()
    t.eq(f.shown, false)
    t.eq(fault(env), nil)
end

tests["client taxiMark: with no button of that name it stands at the node's share of the map"] = function(t)
    local env = newEnv({ names = { "Home Post", "Other" } })
    local h = ns.make.client(env).taxiMark()
    local f = env.frames[1]
    t.eq(h.mark({ name = "Far Post", x = 0.5, y = 0.25 }, "x"), true)
    t.eq({ f.point[1], f.point[3], f.point[4], f.point[5] }, { "CENTER", "TOPLEFT", 150, -100 })
    t.ok(f.point[2] == env.TaxiRouteMap)
end

tests["client taxiMark: a secret node name is not matched; a place not known is not shown"] = function(t)
    local env = newEnv({ secret = "Far Post" })
    local h = ns.make.client(env).taxiMark()
    local f = env.frames[1]
    t.eq(h.mark({ name = "Far Post", x = 0.5, y = 0.25 }, "x"), true)
    t.ok(f.point[2] == env.TaxiRouteMap, "by the share, not the hidden name's button")
    h.hide()
    local odd = newEnv({ names = {} })
    local h2 = ns.make.client(odd).taxiMark()
    t.eq(h2.mark({ name = "Far Post", x = 0 / 0, y = 0.25 }, "x"), false)
    t.eq(odd.frames[1].shown, false)
    t.eq(h2.mark(nil), false)
end

tests["client taxiMark: no flight map frame or no frames is nil"] = function(t)
    t.eq(ns.make.client({}).taxiMark(), nil)
    t.eq(ns.make.client(newEnv({ noFrames = true })).taxiMark(), nil)
end

tests["client mapPins: a plain frame on the world map's canvas with no mouse"] = function(t)
    local env = newEnv()
    local h = ns.make.client(env).mapPins()
    t.ok(h ~= nil, "made")
    local host = env.frames[1]
    t.ok(host.parent == env.canvas, "on the canvas")
    t.eq({ host.mouse, host.template }, { false, nil })
end

tests["client mapPins: map is the shown map's ID; closed, secret or missing is nil"] = function(t)
    local env = newEnv()
    local h = ns.make.client(env).mapPins()
    t.eq(h.map(), 1414)
    env.WorldMapFrame.shown = false
    t.eq(h.map(), nil, "the window is closed")
    t.eq(ns.make.client(newEnv({ secret = 1414 })).mapPins().map(), nil, "a secret map")
    t.eq(ns.make.client(newEnv({ mapID = false })).mapPins().map(), nil, "no number")
    local none = newEnv()
    function none.WorldMapFrame:GetMapID() return nil end
    t.eq(ns.make.client(none).mapPins().map(), nil, "no map: issecretvalue is not asked about nil")
end

tests["client mapPins: draw puts dots and lines at the shares of the canvas; extras hide; clear hides all"] = function(t)
    local env = newEnv()
    local h = ns.make.client(env).mapPins()
    local host, canvas = env.frames[1], env.canvas
    h.draw({ { name = "A", kind = "have", role = "from", x = 0.5, y = 0.5 }, { name = "B", kind = "new", x = 0.1, y = 0.2 } },
        { { from = "A", to = "B", ax = 0.5, ay = 0.5, bx = 0.1, by = 0.2 } })
    local dots, lines = {}, {}
    -- Each dot is a Button on the host (B-10: it takes clicks).
    for _, f in ipairs(env.frames) do
        if f.kind == "Button" and f.parent == host then dots[#dots + 1] = f end
    end
    for _, r in ipairs(host.made) do
        if r.kind == "Line" then lines[#lines + 1] = r end
    end
    t.eq(#dots, 2)
    t.eq(#lines, 1)
    t.eq({ dots[1].point[1], dots[1].point[3], dots[1].point[4], dots[1].point[5] }, { "CENTER", "TOPLEFT", 500, -250 })
    t.ok(dots[1].point[2] == canvas)
    t.eq({ dots[2].point[4], dots[2].point[5] }, { 100, -100 })
    t.eq({ dots[1].shown, dots[2].shown }, { true, true })
    t.eq({ lines[1].from[1], lines[1].from[3], lines[1].from[4] }, { "TOPLEFT", 500, -250 })
    t.eq({ lines[1].to[1], lines[1].to[3], lines[1].to[4] }, { "TOPLEFT", 100, -100 })
    t.eq(lines[1].shown, true)
    h.draw({ { name = "A", kind = "have", x = 0.5, y = 0.5 } }, {})
    t.eq({ dots[1].shown, dots[2].shown, lines[1].shown }, { true, false, false })
    h.clear()
    t.eq({ dots[1].shown, dots[2].shown, lines[1].shown }, { false, false, false })
    t.eq(fault(env), nil)
end

tests["client mapPins: no world map, no canvas or no frames is nil"] = function(t)
    t.eq(ns.make.client({}).mapPins(), nil)
    local bare = newEnv()
    bare.WorldMapFrame.ScrollContainer = nil
    t.eq(ns.make.client(bare).mapPins(), nil)
    t.eq(ns.make.client(newEnv({ noFrames = true })).mapPins(), nil)
end

tests["client flight marks: look only - no taxi action, no CVar, no secure frame"] = function(t)
    local env = newEnv()
    local c = ns.make.client(env)
    local mark, pins = c.taxiMark(), c.mapPins()
    mark.mark({ name = "Far Post", x = 0.5, y = 0.5 }, "x")
    mark.mark({ name = "Nowhere", x = 0.2, y = 0.5 }, "x")
    mark.hide()
    pins.map()
    pins.draw({ { name = "A", kind = "have", x = 0.5, y = 0.5 } }, { { ax = 0, ay = 0, bx = 1, by = 1 } })
    pins.clear()
    t.eq(fault(env), nil)
end

tests["fake taxiMark: records the node and the words; hide; no frames is nil"] = function(t)
    local c = ns.make.fakeClient()
    local h = c.taxiMark()
    t.ok(c.taxiMarks[1] == h)
    t.eq({ h.shown, h.marks, h.hides }, { false, 0, 0 })
    t.eq(h.mark({ name = "Far Post", x = 0.5, y = 0.25 }, "words"), true)
    t.eq({ h.node, h.label, h.shown, h.marks }, { { name = "Far Post", x = 0.5, y = 0.25 }, "words", true, 1 })
    h.hide()
    t.eq({ h.shown, h.hides }, { false, 1 })
    c.setFrames(false)
    t.eq(c.taxiMark(), nil)
    t.eq(#c.taxiMarks, 1)
end

tests["fake mapPins: map as set, draw keeps copies, clear empties; no frames is nil"] = function(t)
    local c = ns.make.fakeClient()
    local h = c.mapPins()
    t.ok(c.mapPinSets[1] == h)
    t.eq(h.map(), nil, "no world map shown until set")
    c.setWorldMap(1414)
    t.eq(h.map(), 1414)
    local pins = { { name = "A", kind = "have", x = 0.5, y = 0.5 } }
    h.draw(pins, { { from = "A", to = "B", ax = 0, ay = 0, bx = 1, by = 1 } })
    pins[1].name = "changed"
    t.eq(h.pins, { { name = "A", kind = "have", x = 0.5, y = 0.5 } })
    t.eq(#h.lines, 1)
    t.eq({ h.shown, h.draws }, { true, 1 })
    h.clear()
    t.eq({ h.pins, h.lines, h.shown, h.clears }, { {}, {}, false, 1 })
    c.setWorldMap(nil)
    t.eq(h.map(), nil)
    c.setFrames(false)
    t.eq(c.mapPins(), nil)
end

return tests

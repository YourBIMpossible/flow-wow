-- B-10 / B-11 / B-19: a click on a world map mark. c.mapPins() and
-- c.routePins() handles take h.onClick(fn): mapPins calls fn(pin.name,
-- button), routePins fn(n, button). A mapPins dot's OnEnter shows
-- pin.title then each pin.tip line in GameTooltip, owned by the dot. The
-- real client over a hand-built environment, then ClientFake's twins.
local _, ns = ...

local tests = {}

-- A frame, texture or font string that writes down what is done to it.
local function region(kind, parent)
    local f = { kind = kind, parent = parent, shown = true, made = {}, scripts = {} }
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:SetSize(w, h) self.w, self.h = w, h end
    function f:EnableMouse(on) self.mouse = on end
    function f:ClearAllPoints() self.point = nil end
    function f:SetPoint(...) self.point = { ... } end
    function f:SetAllPoints(to) self.all = to end
    function f:SetColorTexture(...) self.colour = { ... } end
    function f:SetVertexColor(...) self.vertex = { ... } end
    function f:SetTexture(path) self.texture = path end
    function f:SetText(text) self.text = text end
    function f:SetFrameStrata(s) self.strata = s end
    function f:SetThickness(n) self.thick = n end
    function f:SetStartPoint(...) self.from = { ... } end
    function f:SetEndPoint(...) self.to = { ... } end
    function f:RegisterForClicks(...) self.clicks = { ... } end
    function f:SetScript(name, fn) self.scripts[name] = fn end
    function f:CreateTexture() local r = region("Texture", self); self.made[#self.made + 1] = r; return r end
    function f:CreateFontString() local r = region("FontString", self); self.made[#self.made + 1] = r; return r end
    function f:CreateLine() local r = region("Line", self); self.made[#self.made + 1] = r; return r end
    return f
end

local function newEnv()
    local env = { frames = {} }
    function env.issecretvalue(v)
        if v == nil then error("issecretvalue: nil") end
        return false
    end
    function env.CreateFrame(kind, name, parent, template)
        local f = region(kind, parent)
        f.name, f.template = name, template
        env.frames[#env.frames + 1] = f
        return f
    end
    env.WorldMapFrame = region("Frame")
    function env.WorldMapFrame:GetMapID() return 1414 end
    local canvas = region("Frame")
    function canvas:GetWidth() return 1000 end
    function canvas:GetHeight() return 500 end
    env.WorldMapFrame.ScrollContainer = { Child = canvas }
    -- GameTooltip that writes down its calls.
    local tip = { calls = {} }
    local function note(name) return function(_, ...) tip.calls[#tip.calls + 1] = { name, ... } end end
    tip.SetOwner, tip.SetText, tip.AddLine = note("SetOwner"), note("SetText"), note("AddLine")
    tip.Show, tip.Hide = note("Show"), note("Hide")
    env.GameTooltip = tip
    return env
end

-- The Buttons made on the host frame (env.frames[1]), in order.
local function buttons(env)
    local out = {}
    for _, f in ipairs(env.frames) do
        if f.kind == "Button" and f.parent == env.frames[1] then out[#out + 1] = f end
    end
    return out
end

tests["client mapPins: each dot is a Button taking left and right clicks; onClick gets the pin's name"] = function(t)
    local env = newEnv()
    local h = ns.make.client(env).mapPins()
    local got = {}
    t.eq(h.onClick(function(name, button) got[#got + 1] = { name, button } end), true)
    h.draw({ { name = "Home Post", kind = "have", x = 0.5, y = 0.5 }, { name = "Far Post", kind = "new", x = 0.1, y = 0.2 } }, {})
    local b = buttons(env)
    t.eq(#b, 2)
    t.eq(b[1].clicks, { "LeftButtonUp", "RightButtonUp" })
    t.eq({ b[1].point[4], b[1].point[5] }, { 500, -250 })
    t.ok(type(b[1].made[1]) == "table" and b[1].made[1].colour ~= nil, "the dot's colour is a texture on the button")
    b[2].scripts.OnClick(b[2], "RightButton")
    b[1].scripts.OnClick(b[1], "LeftButton")
    t.eq(got, { { "Far Post", "RightButton" }, { "Home Post", "LeftButton" } })
    -- Redrawn, the first dot now stands for another pin.
    h.draw({ { name = "Other", kind = "have", x = 0.2, y = 0.2 } }, {})
    b[1].scripts.OnClick(b[1], "LeftButton")
    t.eq(got[3], { "Other", "LeftButton" })
end

tests["client mapPins: OnEnter shows the title then the tip lines, owned by the dot; OnLeave hides"] = function(t)
    local env = newEnv()
    local h = ns.make.client(env).mapPins()
    h.draw({ { name = "A", kind = "have", x = 0.5, y = 0.5, title = "Home Post", tip = { "Click: fly here", 7 } } }, {})
    local b = buttons(env)[1]
    b.scripts.OnEnter(b)
    local calls = env.GameTooltip.calls
    t.eq(calls[1][1], "SetOwner")
    t.ok(calls[1][2] == b, "owned by the dot")
    t.eq(calls[1][3], "ANCHOR_RIGHT")
    t.eq(calls[2], { "SetText", "Home Post" })
    t.eq(calls[3], { "AddLine", "Click: fly here", 1, 1, 1, true })
    t.eq(calls[4], { "Show" })
    t.eq(#calls, 4, "a line that is not text is skipped")
    b.scripts.OnLeave(b)
    t.eq(calls[5], { "Hide" })
end

tests["client mapPins: no title, no tooltip; a failing onClick fn does not stop the next"] = function(t)
    local env = newEnv()
    local h = ns.make.client(env).mapPins()
    local got = {}
    h.onClick(function() error("boom") end)
    h.onClick(function(name) got[#got + 1] = name end)
    t.eq(h.onClick("not a function"), true)
    h.draw({ { name = "A", kind = "have", x = 0.5, y = 0.5 } }, {})
    local b = buttons(env)[1]
    b.scripts.OnEnter(b)
    t.eq(#env.GameTooltip.calls, 0)
    b.scripts.OnClick(b, "LeftButton")
    t.eq(got, { "A" })
end

tests["client routePins: each mark takes left and right clicks; onClick gets the mark's number"] = function(t)
    local env = newEnv()
    local h = ns.make.client(env).routePins()
    local got = {}
    t.eq(h.onClick(function(n, button) got[#got + 1] = { n, button } end), true)
    h.draw({ { n = 1, x = 0.5, y = 0.5, text = "Step one" }, { n = 2, x = 0.1, y = 0.2, text = "Step two" } })
    local b = buttons(env)
    t.eq(#b, 2)
    t.eq(b[2].clicks, { "LeftButtonUp", "RightButtonUp" })
    b[2].scripts.OnClick(b[2], "RightButton")
    b[1].scripts.OnClick(b[1], "LeftButton")
    t.eq(got, { { 2, "RightButton" }, { 1, "LeftButton" } })
end

tests["fake mapPins and routePins: onClick keeps fn; click calls it, LeftButton by default"] = function(t)
    local c = ns.make.fakeClient()
    local got = {}
    local pins = c.mapPins()
    t.eq(pins.onClick(function(name, button) got[#got + 1] = { name, button } end), true)
    pins.click("Home Post")
    pins.click("Far Post", "RightButton")
    local route = c.routePins()
    t.eq(route.onClick(function(n, button) got[#got + 1] = { n, button } end), true)
    route.click(3)
    t.eq(got, { { "Home Post", "LeftButton" }, { "Far Post", "RightButton" }, { 3, "LeftButton" } })
end

return tests

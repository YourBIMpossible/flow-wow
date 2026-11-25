-- F-20: c.setTipSpot(fn) decides where the client's tooltips go. Every
-- SetOwner in Core/Client.lua goes through one helper that asks
-- fn(anchor): "GAME" -> GameTooltip_SetDefaultAnchor(tip, owner) when the
-- client has it; any other text -> SetOwner(owner, text); no fn or an
-- error -> the anchor as given. Checked through one tooltip the client
-- shows (a route mark's, c.routePins), then ClientFake's twin.
local _, ns = ...

local tests = {}

local function region(kind, parent)
    local f = { kind = kind, parent = parent, shown = true, scripts = {} }
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:SetSize() end
    function f:ClearAllPoints() end
    function f:SetPoint() end
    function f:SetAllPoints() end
    function f:SetTexture() end
    function f:SetVertexColor() end
    function f:SetText(text) self.text = text end
    function f:SetFrameStrata() end
    function f:RegisterForClicks() end
    function f:SetScript(name, fn) self.scripts[name] = fn end
    function f:CreateTexture() return region("Texture", self) end
    function f:CreateFontString() return region("FontString", self) end
    return f
end

-- opts.default: give the env a GameTooltip_SetDefaultAnchor recorder.
local function newEnv(opts)
    opts = opts or {}
    local env = { frames = {}, defaults = {} }
    function env.issecretvalue(v)
        if v == nil then error("issecretvalue: nil") end
        return false
    end
    function env.CreateFrame(kind, name, parent)
        local f = region(kind, parent)
        f.name = name
        env.frames[#env.frames + 1] = f
        return f
    end
    env.WorldMapFrame = region("Frame")
    function env.WorldMapFrame:GetMapID() return 1414 end
    local canvas = region("Frame")
    function canvas:GetWidth() return 1000 end
    function canvas:GetHeight() return 500 end
    env.WorldMapFrame.ScrollContainer = { Child = canvas }
    local tip = { owners = {} }
    function tip:SetOwner(owner, anchor) self.owners[#self.owners + 1] = { owner, anchor } end
    function tip:SetText() end
    function tip:AddLine() end
    function tip:Show() end
    function tip:Hide() end
    env.GameTooltip = tip
    if opts.default then
        function env.GameTooltip_SetDefaultAnchor(t, owner) env.defaults[#env.defaults + 1] = { t, owner } end
    end
    return env
end

-- Hover the first route mark of a fresh routePins; returns the mark.
local function hover(c, env)
    local h = c.routePins()
    h.draw({ { n = 1, x = 0.5, y = 0.5, text = "Step one" } })
    local mark
    for _, f in ipairs(env.frames) do if f.kind == "Button" then mark = f end end
    mark.scripts.OnEnter(mark)
    return mark
end

tests["client tipSpot: no fn - the tip is owned with the anchor as written"] = function(t)
    local env = newEnv({ default = true })
    local mark = hover(ns.make.client(env), env)
    t.eq(#env.GameTooltip.owners, 1)
    t.ok(env.GameTooltip.owners[1][1] == mark, "owned by the mark")
    t.eq(env.GameTooltip.owners[1][2], "ANCHOR_RIGHT")
    t.eq(#env.defaults, 0)
end

tests["client tipSpot: GAME puts the tip at the game's own spot"] = function(t)
    local env = newEnv({ default = true })
    local c = ns.make.client(env)
    local asked = {}
    t.eq(c.setTipSpot(function(anchor) asked[#asked + 1] = anchor return "GAME" end), true)
    local mark = hover(c, env)
    t.eq(asked, { "ANCHOR_RIGHT" })
    t.eq(#env.GameTooltip.owners, 0, "SetOwner not called")
    t.eq(#env.defaults, 1)
    t.ok(env.defaults[1][1] == env.GameTooltip and env.defaults[1][2] == mark, "the tip and its owner")
end

tests["client tipSpot: GAME with no GameTooltip_SetDefaultAnchor keeps the anchor"] = function(t)
    local env = newEnv()
    local c = ns.make.client(env)
    c.setTipSpot(function() return "GAME" end)
    hover(c, env)
    t.eq(env.GameTooltip.owners[1][2], "ANCHOR_RIGHT")
end

tests["client tipSpot: another anchor is used; an error or no text keeps the anchor"] = function(t)
    local env = newEnv({ default = true })
    local c = ns.make.client(env)
    c.setTipSpot(function() return "ANCHOR_LEFT" end)
    hover(c, env)
    t.eq(env.GameTooltip.owners[1][2], "ANCHOR_LEFT")
    local env2 = newEnv({ default = true })
    local c2 = ns.make.client(env2)
    c2.setTipSpot(function() error("boom") end)
    hover(c2, env2)
    t.eq(env2.GameTooltip.owners[1][2], "ANCHOR_RIGHT")
    local env3 = newEnv({ default = true })
    local c3 = ns.make.client(env3)
    c3.setTipSpot(function() return nil end)
    t.eq(c3.setTipSpot("not a function"), true)
    hover(c3, env3)
    t.eq(env3.GameTooltip.owners[1][2], "ANCHOR_RIGHT")
end

tests["fake tipSpot: the anchor until a fn is set, then its answer"] = function(t)
    local c = ns.make.fakeClient()
    t.eq(c.tipSpot("ANCHOR_RIGHT"), "ANCHOR_RIGHT")
    t.eq(c.setTipSpot(function() return "GAME" end), true)
    t.eq(c.tipSpot("ANCHOR_RIGHT"), "GAME")
end

return tests

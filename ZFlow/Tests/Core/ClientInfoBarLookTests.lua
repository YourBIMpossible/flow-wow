-- The info bar in the shared look (lead sections 320, 322 and 350): its
-- backing, edge and text come from the one theme file (UI/Kit/Theme.lua,
-- ns.Kit.look), as every kit window's do, with the bar's own layout (a
-- strip, not a journal window). Real client, hand-built stand-in.
-- Fails before: the backing is black (0, 0, 0), there is no edge, and the
-- text is GameFontNormalSmall.
local _, ns = ...

local function gameEnv()
    local env = { made = {}, UIParent = {} }
    local function obj(kind, layer, font)
        local o = { kind = kind, layer = layer, font = font, scripts = {}, w = 300, h = 20 }
        setmetatable(o, { __index = function() return function() end end })
        function o:SetScript(script, fn) self.scripts[script] = fn end
        function o:SetSize(w, h) self.w, self.h = w, h end
        function o:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
        function o:CreateTexture(_, lay)
            local r = obj("Texture", lay)
            env.made[#env.made + 1] = r
            return r
        end
        function o:CreateFontString(_, lay, fnt)
            local r = obj("FontString", lay, fnt)
            env.made[#env.made + 1] = r
            return r
        end
        return o
    end
    function env.CreateFrame(kind)
        local f = obj(kind)
        env.made[#env.made + 1] = f
        return f
    end
    return env
end

local function textures(env, layer)
    local out = {}
    for _, o in ipairs(env.made) do
        if o.kind == "Texture" and o.layer == layer and o.color ~= nil then out[#out + 1] = o end
    end
    return out
end

local tests = {}

tests["info bar look: backing, edge and text come from the theme"] = function(t)
    local look = ns.Kit and ns.Kit.look
    t.ok(type(look) == "table", "the theme is loaded")
    if type(look) ~= "table" then return end
    local env = gameEnv()
    local c = ns.make.client(env)
    local h = c.infoBar({ name = "InfoBarLook", width = 300, height = 20 })
    t.ok(type(h) == "table", "a bar")
    if type(h) ~= "table" then return end
    local fill, edge = look.color.fill, look.color.edge
    local back = textures(env, "BACKGROUND")[1]
    t.ok(back ~= nil, "a backing")
    if back == nil then return end
    t.eq({ back.color[1], back.color[2], back.color[3] }, { fill[1], fill[2], fill[3] }, "the theme's fill")
    local edges = textures(env, "BORDER")
    t.eq(#edges, 4, "a thin edge on each side")
    for i, e in ipairs(edges) do
        t.eq(e.color, { edge[1], edge[2], edge[3], edge[4] }, "edge " .. i .. " in the theme's edge colour")
    end
    local text
    for _, o in ipairs(env.made) do
        if o.kind == "FontString" then text = o end
    end
    t.eq(text and text.font, look.font.small, "the theme's small font")
    h.alpha(0.3)
    t.eq(back.color, { fill[1], fill[2], fill[3], 0.3 }, "the player's opacity keeps the theme's colour")
end

return tests

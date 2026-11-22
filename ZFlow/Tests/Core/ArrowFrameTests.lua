-- The real client's arrow frames (Core/Client.lua c.arrow) over a stub
-- environment that records every call. No game client is involved: this
-- checks which object each call lands on, not what the game draws.
local _, ns = ...

-- A stub object: every method exists, records (name, args) and returns
-- the object's own answer for that name, if it has one.
local function stub(kind, log)
    local o = { kind = kind, calls = {} }
    return setmetatable(o, { __index = function(_, name)
        return function(self, ...)
            local call = { name = name, ... }
            self.calls[#self.calls + 1] = call
            if log then log[#log + 1] = { self, call } end
            if name == "CreateTexture" or name == "CreateFontString" then
                return stub(name, log)
            end
            local answer = rawget(self, "answers") and self.answers[name]
            if answer then return answer(...) end
            return nil
        end
    end })
end

local function env()
    local made = {}
    local e = { UIParent = stub("UIParent") }
    e.CreateFrame = function(kind, name, parent)
        local f = stub(kind)
        f.name, f.parent = name, parent
        made[#made + 1] = f
        return f
    end
    return e, made
end

local function called(o, name)
    local out = {}
    for _, cl in ipairs(o.calls) do
        if cl.name == name then out[#out + 1] = cl end
    end
    return out
end

local function arrow()
    local e, made = env()
    local c = ns.make.client(e)
    local h = c.arrow({ name = "TestArrow", size = 56, art = 64, artPath = "x\\" })
    return h, made[1], made[2]
end

return {
    ["c.arrow: the art sits on a holder centred on the placed frame"] = function(t)
        local h, f, holder = arrow()
        t.ok(h ~= nil)
        t.eq(f.name, "TestArrow")
        t.eq(holder.parent, f, "the holder is the placed frame's child")
        t.eq(#called(f, "CreateTexture"), 0, "no texture on the placed frame")
        t.ok(#called(holder, "CreateTexture") > 0, "the textures are the holder's")
        t.eq(#called(f, "CreateFontString"), 0)
        t.eq(#called(holder, "CreateFontString"), 1, "the text is the holder's")
        local at = called(holder, "SetPoint")[1]
        t.eq({ at[1], at[2], at[3] }, { "CENTER", f, "CENTER" })
    end,

    ["c.arrow: scale goes to the holder; the placed frame stays at scale 1 and its size"] = function(t)
        local h, f, holder = arrow()
        local sizes = #called(f, "SetSize")
        h.place({ "TOPLEFT", "TOPLEFT", 100, -50 })
        h.scale(0.5)
        h.scale(0.8)
        t.eq(#called(f, "SetScale"), 0, "a saved point never moves with the scale")
        local s = called(holder, "SetScale")
        t.eq(#s, 2)
        t.eq(s[2][1], 0.8)
        t.eq(#called(f, "SetSize"), sizes, "the placed frame is not resized")
        local p = called(f, "SetPoint")
        t.eq({ p[#p][1], p[#p][3], p[#p][4], p[#p][5] }, { "TOPLEFT", "TOPLEFT", 100, -50 })
        h.scale(0)
        h.scale("big")
        t.eq(#called(holder, "SetScale"), 2, "no scale from a bad number")
    end,

    ["c.arrow: dragging is true from drag start to drag stop"] = function(t)
        local h, f = arrow()
        local scripts = {}
        for _, cl in ipairs(called(f, "SetScript")) do scripts[cl[1]] = cl[2] end
        t.eq(h.dragging(), false)
        scripts.OnDragStart()
        t.eq(h.dragging(), true)
        scripts.OnDragStop()
        t.eq(h.dragging(), false)
    end,

    ["c.arrow: without a holder frame the placed frame takes the art and the scale"] = function(t)
        local e = { UIParent = stub("UIParent") }
        local n, first = 0, nil
        e.CreateFrame = function(kind)
            n = n + 1
            if n > 1 then return nil end
            first = stub(kind)
            return first
        end
        local h = ns.make.client(e).arrow({})
        t.ok(h ~= nil)
        t.ok(#called(first, "CreateTexture") > 0)
        h.scale(0.5)
        t.eq(#called(first, "SetScale"), 1)
    end,
}

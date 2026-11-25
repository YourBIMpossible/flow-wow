-- B-28: the real client's picture frame (Core/Client.lua c.picture) over a
-- stub environment that records every call. No game client is involved:
-- this checks which object each call lands on, not what the game draws.
-- The picture shows a travel spell or the hearthstone in the quest arrow's
-- place. It must not look clickable: it takes no mouse and holds no action.
local _, ns = ...

local function stub(kind)
    local o = { kind = kind, calls = {} }
    return setmetatable(o, { __index = function(_, name)
        return function(self, ...)
            self.calls[#self.calls + 1] = { name = name, ... }
            if name == "CreateTexture" or name == "CreateMaskTexture" then
                local refuse = rawget(self, "refuse")
                if refuse and refuse[name] then error("no " .. name) end
                local child = stub(name)
                local made = rawget(self, "made") or {}
                rawset(self, "made", made)
                made[#made + 1] = child
                return child
            end
            return nil
        end
    end })
end

local function env(refuse)
    local made = {}
    local e = { UIParent = stub("UIParent") }
    e.CreateFrame = function(kind, name, parent)
        local f = stub(kind)
        f.name, f.parent, f.refuse = name, parent, refuse
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

local function last(o, name)
    local all = called(o, name)
    return all[#all]
end

local SPEC = { name = "TestPicture", size = 56, art = 38, level = 6 }

local function picture(refuse)
    local e, made = env(refuse)
    local c = ns.make.client(e)
    return c.picture(SPEC), made[1]
end

local T = {}

T["client picture: one frame, the arrow frame's size, hidden, with no mouse"] = function(t)
    local h, f = picture()
    t.ok(type(h) == "table", "a handle")
    t.eq(f.name, "TestPicture")
    t.eq(last(f, "SetSize") and last(f, "SetSize")[1], 56, "the frame is as wide as the arrow's")
    t.eq(last(f, "SetSize")[2], 56, "and as high")
    t.eq(#called(f, "Hide"), 1, "a new picture is hidden")
    t.eq(#called(f, "Show"), 0)
    t.eq(last(f, "EnableMouse") and last(f, "EnableMouse")[1], false, "it takes no mouse")
    t.eq(#called(f, "SetScript"), 0, "no script: it hears no click, drag or pointer")
    t.eq(#called(f, "RegisterForDrag"), 0, "it is not dragged")
    t.eq(#called(f, "SetAttribute"), 0, "it holds no action")
    local tex = rawget(f, "made")[1]
    t.eq(last(tex, "SetSize")[1], 38, "the picture itself is 38 wide")
    t.eq(last(tex, "SetPoint")[1], "CENTER", "in the middle of the frame")
    t.eq({ last(tex, "SetTexCoord")[1], last(tex, "SetTexCoord")[2] }, { 0.07, 0.93 }, "the icon's border is cut off")
end

T["client picture: place, show, alpha and the texture land on the frame"] = function(t)
    local h, f = picture()
    h.place({ "CENTER", "CENTER", 10, -20 })
    local set = last(f, "SetPoint")
    t.eq({ set[1], set[3], set[4], set[5] }, { "CENTER", "CENTER", 10, -20 })
    t.eq(#called(f, "ClearAllPoints"), 1)
    h.place(nil)
    t.eq(#called(f, "ClearAllPoints"), 1, "no point: left where it is")
    h.show(true)
    t.eq(#called(f, "Show"), 1)
    h.show(false)
    t.eq(#called(f, "Hide"), 2)
    h.alpha(0.85)
    t.eq(last(f, "SetAlpha")[1], 0.85)
    h.alpha("x")
    t.eq(#called(f, "SetAlpha"), 1, "not a number: left as it is")
    local tex = rawget(f, "made")[1]
    t.eq(h.setTexture(134400), true, "a texture is taken")
    t.eq(last(tex, "SetTexture")[1], 134400)
    t.eq(h.setTexture(nil), false, "none: cleared, and said so")
    t.eq(last(f, "EnableMouse")[1], false, "still no mouse after all of it")
    -- The path with both its separators (a lost backslash draws nothing).
    local sep = string.char(92)
    t.eq(last(rawget(f, "made")[2], "SetTexture")[1], "Interface" .. sep .. "CharacterFrame" .. sep .. "TempPortraitAlphaMask")
end

T["client picture: round when the client has masks"] = function(t)
    local _, f = picture()
    local made = rawget(f, "made")
    local kinds = {}
    for i, o in ipairs(made) do kinds[i] = o.kind end
    t.eq(kinds, { "CreateTexture", "CreateMaskTexture" }, "the picture and its mask")
    t.eq(last(made[1], "AddMaskTexture")[1], made[2], "the mask is on the picture")
    t.eq(last(made[2], "SetAllPoints")[1], made[1], "and exactly over it")
end

T["client picture: no masks on this client: square, no error"] = function(t)
    local h, f = picture({ CreateMaskTexture = true })
    t.ok(type(h) == "table", "still a handle")
    local made = rawget(f, "made")
    t.eq(#made, 1, "only the picture")
    t.eq(#called(made[1], "AddMaskTexture"), 0)
    t.eq(h.setTexture(134400), true)
end

T["client picture: a client that makes no frame gives no handle"] = function(t)
    local e = { UIParent = {} }
    t.eq(ns.make.client(e).picture(SPEC), nil)
    e.CreateFrame = function() error("no frames") end
    t.eq(ns.make.client(e).picture(SPEC), nil)
end

return T

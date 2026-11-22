-- The arrow that is under the other one (stacked) on the real client
-- (Core/Client.lua c.arrow, owner decision D3): it keeps a mouse target, a
-- rim that reaches past the arrow on top, so a Ctrl-drag there moves it
-- alone. A plain click or a plain drag on it does nothing, and the pointer
-- over it tells nothing. Over a stub environment that records every call.
-- No game client is involved: this checks which calls land on the placed
-- frame, not what the game does with a hit rectangle. Not seen in game.
local _, ns = ...

local function stub(kind)
    local o = { kind = kind, calls = {} }
    return setmetatable(o, { __index = function(_, name)
        return function(self, ...)
            self.calls[#self.calls + 1] = { name = name, ... }
            if name == "CreateTexture" or name == "CreateFontString" then return stub(name) end
            local answer = rawget(self, "answers") and self.answers[name]
            if answer then return answer(...) end
            return nil
        end
    end })
end

-- Ctrl is held unless e.ctrl is false.
local function env()
    local made = {}
    local e = { UIParent = stub("UIParent") }
    e.IsControlKeyDown = function() return e.ctrl ~= false end
    e.CreateFrame = function(kind, name, parent)
        local f = stub(kind)
        f.name, f.parent = name, parent
        made[#made + 1] = f
        return f
    end
    return e, made
end

local SPEC = { name = "TestNeedle", size = 56, art = 64, artPath = "x\\" }

local function called(o, name)
    local out = {}
    for _, cl in ipairs(o.calls) do
        if cl.name == name then out[#out + 1] = cl end
    end
    return out
end

local function lastCall(o, name)
    local all = called(o, name)
    return all[#all]
end

local function scripts(f)
    local out = {}
    for _, cl in ipairs(called(f, "SetScript")) do out[cl[1]] = cl[2] end
    return out
end

-- An arrow, its placed frame, its scripts and the environment.
local function arrow()
    local e, made = env()
    local h = ns.make.client(e).arrow(SPEC)
    local f = made[1]
    f.answers = { GetPoint = function() return "CENTER", nil, "CENTER", 150, -40 end }
    return h, f, scripts(f), e
end

-- The last hit rectangle the frame was given: { left, right, top, bottom }.
local function insets(f)
    local cl = lastCall(f, "SetHitRectInsets")
    return cl and { cl[1], cl[2], cl[3], cl[4] } or nil
end

return {
    ["stacked drag: under the other arrow the frame still takes the mouse"] = function(t)
        local h, f = arrow()
        h.behind(true)
        t.eq(lastCall(f, "EnableMouse")[1], true, "the mouse is not switched off")
        for _, cl in ipairs(called(f, "EnableMouse")) do
            t.eq(cl[1], true, "at no time")
        end
    end,

    ["stacked drag: under, its mouse target reaches past the arrow on top, the same on every side"] = function(t)
        local h, f = arrow()
        h.behind(true)
        local got = insets(f)
        t.ok(got ~= nil, "the frame is given a hit rectangle")
        if got == nil then return end
        t.ok(type(got[1]) == "number" and got[1] < -(SPEC.art - SPEC.size) / 2,
            "wider than the art: a rim the arrow on top does not cover")
        t.eq({ got[2], got[3], got[4] }, { got[1], got[1], got[1] }, "one rim all round")
    end,

    ["stacked drag: in front again, the mouse target is the frame itself"] = function(t)
        local h, f = arrow()
        h.behind(true)
        h.behind(false)
        t.eq(insets(f), { 0, 0, 0, 0 })
        t.eq(lastCall(f, "EnableMouse")[1], true)
    end,

    ["stacked drag: an arrow never sent under is given no rim"] = function(t)
        local h, f = arrow()
        h.behind(false)
        local got = insets(f)
        t.ok(got == nil or (got[1] == 0 and got[2] == 0 and got[3] == 0 and got[4] == 0))
    end,

    ["stacked drag: a Ctrl-drag on the arrow under starts a move"] = function(t)
        local h, f, on = arrow()
        h.behind(true)
        on.OnDragStart()
        t.eq(h.dragging(), true)
        t.eq(#called(f, "StartMoving"), 1)
    end,

    ["stacked drag: the drag lasts while the arrow is still said to be under, update after update"] = function(t)
        local h, f, on = arrow()
        h.behind(true)
        on.OnDragStart()
        h.behind(true)
        h.behind(true)
        t.eq(h.dragging(), true, "not let go by the same word again")
        t.eq(#called(f, "StopMovingOrSizing"), 0)
    end,

    ["stacked drag: let go, the place is told once"] = function(t)
        local h, f, on = arrow()
        local told = {}
        h.onMoved(function(point) told[#told + 1] = point end)
        h.behind(true)
        on.OnDragStart()
        h.behind(true)
        on.OnDragStop()
        t.eq(told, { { "CENTER", "CENTER", 150, -40 } })
        t.eq(h.dragging(), false)
        t.eq(#called(f, "StopMovingOrSizing"), 1)
        on.OnDragStop()
        t.eq(#told, 1, "a late second stop tells nothing")
    end,

    ["stacked drag: without Ctrl the arrow under does not move"] = function(t)
        local h, f, on, e = arrow()
        local told = 0
        h.onMoved(function() told = told + 1 end)
        h.behind(true)
        e.ctrl = false
        on.OnDragStart()
        on.OnDragStop()
        t.eq(h.dragging(), false)
        t.eq(#called(f, "StartMoving"), 0)
        t.eq(told, 0)
    end,

    ["stacked drag: a client that cannot say whether Ctrl is held starts no drag"] = function(t)
        local h, f, on, e = arrow()
        h.behind(true)
        e.IsControlKeyDown = nil
        on.OnDragStart()
        t.eq(h.dragging(), false)
        t.eq(#called(f, "StartMoving"), 0)
    end,

    ["stacked drag: a click on the arrow under tells nothing"] = function(t)
        local h, f, on = arrow()
        local got = {}
        h.onClick(function(which) got[#got + 1] = which end)
        h.behind(true)
        on.OnMouseDown(f, "LeftButton")
        on.OnMouseUp(f, "LeftButton")
        on.OnMouseDown(f, "RightButton")
        on.OnMouseUp(f, "RightButton")
        t.eq(got, {}, "neither button")
    end,

    ["stacked drag: the pointer over the arrow under tells nothing"] = function(t)
        local h, _, on = arrow()
        local got = {}
        h.onHover(function(over) got[#got + 1] = over end)
        h.behind(true)
        on.OnEnter()
        on.OnLeave()
        t.eq(got, {})
    end,

    ["stacked drag: in front again, clicks and the pointer are told as before"] = function(t)
        local h, f, on = arrow()
        local clicks, hovers = {}, {}
        h.onClick(function(which) clicks[#clicks + 1] = which end)
        h.onHover(function(over) hovers[#hovers + 1] = over end)
        h.behind(true)
        h.behind(false)
        on.OnMouseDown(f, "RightButton")
        on.OnMouseUp(f, "RightButton")
        on.OnEnter()
        on.OnLeave()
        t.eq(clicks, { "right" })
        t.eq(hovers, { true, false })
    end,

    ["stacked drag: the release that ends a drag of the arrow under is not a click after it is in front"] = function(t)
        local h, f, on = arrow()
        local got = {}
        h.onClick(function(which) got[#got + 1] = which end)
        h.behind(true)
        on.OnMouseDown(f, "LeftButton")
        on.OnDragStart()
        on.OnDragStop()
        h.behind(false)
        on.OnMouseUp(f, "LeftButton")
        t.eq(got, {})
    end,

    ["stacked drag: sent under in the middle of a drag, the drag is still let go and nothing is saved"] = function(t)
        local h, f, on = arrow()
        local told = 0
        h.onMoved(function() told = told + 1 end)
        on.OnDragStart()
        h.behind(true)
        t.eq(h.dragging(), false)
        t.eq(#called(f, "StopMovingOrSizing"), 1)
        on.OnDragStop()
        t.eq(told, 0)
    end,

    ["stacked drag: the levels go down and come back as before"] = function(t)
        local e, made = env()
        local h = ns.make.client(e).arrow({ name = "TestNeedle", size = 56, art = 64, artPath = "x\\", level = 6 })
        local f = made[1]
        h.behind(true)
        t.eq(lastCall(f, "SetFrameLevel")[1], 4)
        h.behind(false)
        t.eq(lastCall(f, "SetFrameLevel")[1], 6)
    end,
}

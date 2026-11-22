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
                local child = stub(name, log)
                local made = rawget(self, "made") or {}
                rawset(self, "made", made)
                made[#made + 1] = child
                return child
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

-- The halo, beam and beam texcoord numbers here are not Nav/ArrowMotion's:
-- what the frame does with them can only have come from the spec.
local SPEC = { name = "TestArrow", size = 56, art = 64, artPath = "x\\",
               halo = { 70, 30, -9 }, beam = { 22, 44 },
               beamUp = { 0, 1, 0, 0.75 }, beamDown = { 0, 1, 0.75, 0 } }

local function arrow(spec)
    local e, made = env()
    local c = ns.make.client(e)
    local h = c.arrow(spec or SPEC)
    return h, made[1], made[2], made[3]
end

-- The last frame level a frame was given, or nil when it was given none.
local function levelOf(o)
    local all = {}
    for _, cl in ipairs(o.calls) do
        if cl.name == "SetFrameLevel" then all[#all + 1] = cl end
    end
    return all[#all] and all[#all][1] or nil
end

-- The holder's textures by what they are, in the order c.arrow makes them.
local function art(holder)
    local m = rawget(holder, "made") or {}
    return { shadow = m[1], pool = m[2], body = m[3], shine = m[4],
             halo = m[5], ripple = m[6], beam = m[7], beamDown = m[8] }
end

local function scripts(f)
    local out = {}
    for _, cl in ipairs(called(f, "SetScript")) do out[cl[1]] = cl[2] end
    return out
end

local function lastCall(o, name)
    local all = called(o, name)
    return all[#all]
end

-- A quiet environment for counting: every object answers every method with
-- one shared function per name that records nothing, so the only tables or
-- functions made during a call are the caller's own. stats.lookups counts
-- method lookups, stats.textures the textures made.
local function quietEnv()
    local stats = { lookups = 0, textures = 0 }
    local fns, mt = {}, nil
    local function obj() return setmetatable({}, mt) end
    mt = { __index = function(_, name)
        stats.lookups = stats.lookups + 1
        local fn = fns[name]
        if not fn then
            if name == "CreateTexture" then
                fn = function()
                    stats.textures = stats.textures + 1
                    return obj()
                end
            elseif name == "CreateFontString" then
                fn = function() return obj() end
            else
                fn = function() return nil end
            end
            fns[name] = fn
        end
        return fn
    end }
    return { UIParent = obj(), CreateFrame = function() return obj() end }, stats
end

-- Draws d twice and returns what that made: textures and method lookups.
-- (Memory is not measured here: a test may not read collectgarbage.)
local function drawCost(h, stats, d)
    local textures, lookups = stats.textures, stats.lookups
    h.draw(d)
    h.draw(d)
    return stats.textures - textures, stats.lookups - lookups
end

return {
    ["c.arrow: the art sits on a holder centred on the placed frame"] = function(t)
        local h, f, holder, top = arrow()
        t.ok(h ~= nil)
        t.eq(f.name, "TestArrow")
        t.eq(holder.parent, f, "the holder is the placed frame's child")
        t.eq(#called(f, "CreateTexture"), 0, "no texture on the placed frame")
        t.ok(#called(holder, "CreateTexture") > 0, "the textures are the holder's")
        t.eq(#called(holder, "CreateFontString"), 0, "no text on the scaled holder")
        t.eq(#called(f, "CreateFontString"), 0, "nor on the placed frame, which is under the art (ACB1)")
        t.eq(#called(top, "CreateFontString"), 1, "the text is the text frame's, unscaled (AF3)")
        t.eq(top.parent, f, "and the text frame is the placed frame's child, not the holder's")
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
        local on = scripts(f)
        t.eq(h.dragging(), false)
        on.OnDragStart()
        t.eq(h.dragging(), true)
        on.OnDragStop()
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

    -- ------------------------------------------------- AR13: the spec's numbers
    ["c.arrow: the halo, beam and beam texcoords are the spec's (AR13)"] = function(t)
        local h, _, holder = arrow()
        local a = art(holder)
        local size = lastCall(a.halo, "SetSize")
        t.eq({ size[1], size[2] }, { 70, 30 }, "the halo's size")
        for _, key in ipairs({ "halo", "ripple", "beam", "beamDown" }) do
            local at = lastCall(a[key], "SetPoint")
            t.eq({ at[2], at[4], at[5] }, { holder, 0, -9 }, key .. " sits at the spec's halo height")
        end
        local up, down = lastCall(a.beam, "SetTexCoord"), lastCall(a.beamDown, "SetTexCoord")
        t.eq({ up[1], up[2], up[3], up[4] }, { 0, 1, 0, 0.75 })
        t.eq({ down[1], down[2], down[3], down[4] }, { 0, 1, 0.75, 0 })
        t.ok(h ~= nil)
    end,

    ["c.arrow: with no halo or beam in the spec, no size, place or texcoord is made up (AR13)"] = function(t)
        local h, _, holder = arrow({ name = "Bare", size = 56, art = 64, artPath = "x\\" })
        local a = art(holder)
        t.eq(#called(a.halo, "SetSize"), 0)
        t.eq(#called(a.halo, "SetPoint"), 0)
        t.eq(#called(a.beam, "SetTexCoord"), 0)
        t.eq(#called(a.beamDown, "SetTexCoord"), 0)
        h.draw({ arrived = true })
        t.eq(#called(a.ripple, "SetSize"), 0, "a draw with no ripple size sets none")
        t.eq(#called(a.beam, "SetSize"), 0, "a draw with no beam size sets none")
        h.draw({ arrived = true, ripple = { 40, 20, 0.5 }, beam = { 10, 30, 0.5 } })
        local rs, bs = lastCall(a.ripple, "SetSize"), lastCall(a.beamDown, "SetSize")
        t.eq({ rs[1], rs[2] }, { 40, 20 }, "the draw table's own sizes are used")
        t.eq({ bs[1], bs[2] }, { 10, 30 })
    end,

    -- ------------------------------------------- AR9: nothing made by a draw
    ["c.arrow: a draw after the first makes no texture and looks no method up (AR9)"] = function(t)
        local N = ns.Nav
        local e, stats = quietEnv()
        local h = ns.make.client(e).arrow(SPEC)
        t.ok(h ~= nil)
        t.eq(stats.textures, 8, "eight textures, made once")
        local m = N.ArrowMotion()
        N.ArrowAim(m, { turn = 1, colour = { 1, 0.5, 0 }, snap = true })
        h.draw(N.ArrowStep(m, 0.016, 1))            -- the first frame
        local textures, lookups = drawCost(h, stats, N.ArrowStep(m, 0.016, 2))
        t.eq(textures, 0, "pointing: no new texture")
        t.eq(lookups, 0, "pointing: no method looked up again")

        -- Arrived for the first time: the ring, ripple and beams draw, still
        -- with nothing made.
        N.ArrowAim(m, { arrived = true, wave = true, snap = true })
        local d = N.ArrowStep(m, 0.016, 3)
        t.eq(d.arrived, true)
        textures, lookups = drawCost(h, stats, d)
        t.eq(textures, 0, "arrived: no new texture")
        t.eq(lookups, 0, "arrived: no method looked up again")

        -- The needle (turned, not cut from the sheet).
        h.look("needle")
        N.ArrowAim(m, { arrived = false, snap = true })
        textures, lookups = drawCost(h, stats, N.ArrowStep(m, 0.016, 4))
        t.eq(textures, 0, "needle: no new texture")
        t.eq(lookups, 0, "needle: no method looked up again")
    end,

    ["c.arrow: a draw still reaches every texture it did (AR9)"] = function(t)
        local h, _, holder = arrow()
        local a = art(holder)
        h.draw({ turn = 0, cell = { 0, 0.5, 0.25, 0.75 }, colour = { 0.1, 0.2, 0.3 },
                 body = 0.8, shine = 0.7, shadow = 0.6, pool = 0.2, bodyY = 1.5,
                 arrived = true, halo = 0.4, ripple = { 40, 20, 0.5 }, beam = { 10, 30, 0.25 } })
        for _, key in ipairs({ "shadow", "body", "shine" }) do
            local tc = lastCall(a[key], "SetTexCoord")
            t.eq({ tc[1], tc[2], tc[3], tc[4] }, { 0, 0.5, 0.25, 0.75 }, key .. " takes the cell")
        end
        for _, key in ipairs({ "body", "pool", "halo", "ripple", "beam", "beamDown" }) do
            local vc = lastCall(a[key], "SetVertexColor")
            t.eq({ vc[1], vc[2], vc[3] }, { 0.1, 0.2, 0.3 }, key .. " takes the colour")
        end
        t.eq(lastCall(a.body, "SetAlpha")[1], 0.8)
        t.eq(lastCall(a.shine, "SetAlpha")[1], 0.7)
        t.eq(lastCall(a.shadow, "SetAlpha")[1], 0.6)
        t.eq(lastCall(a.pool, "SetAlpha")[1], 0.2)
        t.eq(lastCall(a.body, "SetPoint")[5], 1.5, "the float")
        t.eq(lastCall(a.halo, "SetAlpha")[1], 0.4)
        t.eq(lastCall(a.ripple, "SetAlpha")[1], 0.5)
        t.eq(lastCall(a.beam, "SetAlpha")[1], 0.25)
        t.eq(lastCall(a.beamDown, "SetAlpha")[1], 0.25)
        for _, key in ipairs({ "halo", "ripple", "beam", "beamDown" }) do
            t.ok(lastCall(a[key], "Show") ~= nil, key .. " shown on arrival")
        end
        h.draw({ arrived = false })
        for _, key in ipairs({ "halo", "ripple", "beam", "beamDown" }) do
            t.ok(lastCall(a[key], "Hide") ~= nil, key .. " hidden again")
        end
    end,

    -- ------------------------------------------------------ AF2, AF3 and AF4
    ["c.arrow: behind lowers the holder with the frame, and back (AF2)"] = function(t)
        local e, made = env()
        local h = ns.make.client(e).arrow({ name = "Lv", size = 56, art = 64, artPath = "x\\", level = 6 })
        local f, holder = made[1], made[2]
        h.behind(true)
        t.eq(lastCall(f, "SetFrameLevel")[1], 4)
        t.eq(lastCall(holder, "SetFrameLevel")[1], 5, "the art goes down with its frame")
        h.behind(false)
        t.eq(lastCall(f, "SetFrameLevel")[1], 6)
        t.eq(lastCall(holder, "SetFrameLevel")[1], 7)
    end,

    ["c.arrow: the text is placed against the unscaled frame (AF3)"] = function(t)
        local h, f, _, top = arrow()
        local label = top and (rawget(top, "made") or {})[1]
        t.ok(label ~= nil, "the label is on the text frame")
        if label == nil then return end
        h.text({ "one", "two" }, { "TOP", "BOTTOM", 0, -4 })
        local at = lastCall(label, "SetPoint")
        t.eq({ at[1], at[2], at[3], at[4], at[5] }, { "TOP", f, "BOTTOM", 0, -4 })
        t.eq(lastCall(label, "SetText")[1], "one\ntwo")
        t.eq(#called(label, "SetFont"), 0, "the text size is left alone")
        t.eq(#called(label, "SetAlpha"), 0, "and its opacity")
    end,

    ["c.arrow: a drag ends when the arrow is hidden or goes behind (AF4)"] = function(t)
        local h, f = arrow()
        local on = scripts(f)
        t.ok(type(on.OnHide) == "function", "the frame has an OnHide script")
        if type(on.OnHide) ~= "function" then return end
        on.OnDragStart()
        on.OnHide()
        t.eq(h.dragging(), false, "hidden by the client mid-drag")
        t.eq(#called(f, "StopMovingOrSizing"), 1)

        on.OnDragStart()
        h.show(false)
        t.eq(h.dragging(), false, "hidden by the addon mid-drag")
        t.eq(#called(f, "StopMovingOrSizing"), 2)

        on.OnDragStart()
        h.behind(true)
        t.eq(h.dragging(), false, "sent behind mid-drag")
        t.eq(#called(f, "StopMovingOrSizing"), 3)

        local moved = 0
        h.onMoved(function() moved = moved + 1 end)
        on.OnDragStart()
        on.OnHide()
        t.eq(moved, 0, "a drag cut short saves no place")
        h.show(true)
        t.eq(h.dragging(), false)
    end,

    -- ------------------------------------------- ACB1: the text above the art
    -- A stub cannot see layering. These check the frame levels c.arrow asks
    -- for, and which frame owns the label: what the game then draws on top
    -- is a client check.
    ["c.arrow: the text has a frame of its own, one level above the holder, in both stack orders (ACB1)"] = function(t)
        local e, made = env()
        local h = ns.make.client(e).arrow({ name = "Lv", size = 56, art = 64, artPath = "x\\", level = 6 })
        local f, holder, top = made[1], made[2], made[3]
        t.ok(top ~= nil, "a third frame is made")
        if top == nil then return end
        t.eq(top.parent, f, "a child of the placed frame, not of the scaled holder")
        t.eq(#(rawget(top, "made") or {}), 1, "the label is the text frame's")
        t.eq(rawget(f, "made"), nil, "the placed frame draws nothing itself")
        t.eq(#rawget(holder, "made"), 8, "the holder has the art and no text")
        t.eq({ levelOf(f), levelOf(holder), levelOf(top) }, { 6, 7, 8 }, "in front: frame, art, text")
        h.behind(true)
        t.eq({ levelOf(f), levelOf(holder), levelOf(top) }, { 4, 5, 6 }, "behind: the text goes down with them, still on top")
        h.behind(false)
        t.eq({ levelOf(f), levelOf(holder), levelOf(top) }, { 6, 7, 8 }, "and back")
        h.scale(0.5)
        t.eq(#called(top, "SetScale"), 0, "the text frame is never scaled")
        t.eq(#called(f, "SetScale"), 0)
    end,

    ["c.arrow: without a text frame the label is the placed frame's, as before (ACB1)"] = function(t)
        local e = { UIParent = stub("UIParent") }
        local n, made = 0, {}
        e.CreateFrame = function(kind)
            n = n + 1
            if n > 2 then return nil end
            made[n] = stub(kind)
            return made[n]
        end
        local h = ns.make.client(e).arrow({ level = 6 })
        t.ok(h ~= nil)
        t.eq(n, 3, "a text frame was asked for")
        local label = (rawget(made[1], "made") or {})[1]
        t.ok(label ~= nil, "the label falls back to the placed frame")
        if label == nil then return end
        h.text({ "one" }, { "TOP", "BOTTOM", 0, -4 })
        t.eq(lastCall(label, "SetText")[1], "one")
        h.behind(true)
        t.eq({ levelOf(made[1]), levelOf(made[2]) }, { 4, 5 })
    end,

    ["c.arrow: without a holder the text frame is one level above the placed frame (ACB1)"] = function(t)
        local e = { UIParent = stub("UIParent") }
        local n, made = 0, {}
        e.CreateFrame = function(kind)
            n = n + 1
            if n == 2 then return nil end
            made[#made + 1] = stub(kind)
            return made[#made]
        end
        local h = ns.make.client(e).arrow({ level = 6 })
        t.ok(h ~= nil)
        local f, top = made[1], made[2]
        t.ok(top ~= nil, "a text frame is still made")
        if top == nil then return end
        t.eq({ levelOf(f), levelOf(top) }, { 6, 7 })
        h.behind(true)
        t.eq({ levelOf(f), levelOf(top) }, { 4, 5 })
    end,

    -- ------------------------------------- ACB2, ACB9: a drag stop with no drag
    ["c.arrow: a drag stop with no drag in progress does nothing and saves nothing (ACB2, ACB9)"] = function(t)
        local h, f = arrow()
        f.answers = { GetPoint = function() return "CENTER", nil, "CENTER", 10, 20 end }
        local on = scripts(f)
        local moved = {}
        h.onMoved(function(point) moved[#moved + 1] = point end)

        on.OnDragStop()
        t.eq(#moved, 0, "never dragged: nothing saved")
        t.eq(#called(f, "StopMovingOrSizing"), 0, "and nothing stopped")

        on.OnDragStart()
        h.show(false)                               -- hidden mid-drag: the drag is let go
        local stops, placed = #called(f, "StopMovingOrSizing"), #called(f, "SetUserPlaced")
        on.OnDragStop()                             -- the client fires it late
        t.eq(#moved, 0, "hidden mid-drag, then a drag stop: nothing saved")
        t.eq(#called(f, "StopMovingOrSizing"), stops, "nothing stopped twice")
        t.eq(#called(f, "SetUserPlaced"), placed)

        h.show(true)
        on.OnDragStart()
        h.behind(true)                              -- sent behind mid-drag
        on.OnDragStop()
        t.eq(#moved, 0, "sent behind mid-drag, then a drag stop: nothing saved")

        h.behind(false)
        on.OnDragStart()
        on.OnDragStop()
        t.eq(moved, { { "CENTER", "CENTER", 10, 20 } }, "a drag that ends by itself is still saved")
        on.OnDragStop()
        t.eq(#moved, 1, "and only once")
    end,

    -- ------------------------------------------------ ACB3: one snapshot table
    -- What a reused snapshot must not change. (That it is reused is not
    -- measured here: a test may not read collectgarbage.)
    ["listeners: a call inside a call, and listeners added or removed during it (ACB3)"] = function(t)
        local L = ns.make.listeners(function() end, function() end)
        local log = {}
        local cancelB, inner = nil, false
        L.add("k", function(v)
            log[#log + 1] = "a" .. v
            if not inner then
                inner = true
                L.call("k", 2)                      -- the same key, inside its own call
                L.call("other", 9)
                cancelB()                           -- b is removed before its turn
                L.add("k", function(w) log[#log + 1] = "late" .. w end)
            end
        end)
        cancelB = L.add("k", function(v) log[#log + 1] = "b" .. v end)
        L.add("k", function(v) log[#log + 1] = "c" .. v end)
        L.add("other", function(v) log[#log + 1] = "o" .. v end)
        L.call("k", 1)
        t.eq(log, { "a1", "a2", "b2", "c2", "o9", "c1" },
            "the inner call is whole; the outer one goes on where it was, without the removed b or the late one")
        log = {}
        L.call("k", 3)
        t.eq(log, { "a3", "c3", "late3" })
        log = {}
        L.call("other", 4)
        t.eq(log, { "o4" }, "nothing of one key is left over in another's call")
    end,

    ["listeners: a listener that fails does not spoil the next call (ACB3)"] = function(t)
        local L = ns.make.listeners(function() end, function() end)
        local log, fail = {}, true
        L.add("k", function(v)
            log[#log + 1] = "a" .. v
            if fail then error("boom") end
        end)
        L.add("k", function(v) log[#log + 1] = "b" .. v end)
        t.eq(pcall(L.call, "k", 1), false, "the failure reaches the caller, as before")
        fail = false
        L.call("k", 2)
        L.call("k", 3)
        t.eq(log, { "a1", "a2", "b2", "a3", "b3" })
    end,
}

local _, ns = ...
-- S15 click slots and S29 move handle (P-KEYS slice C): the client's
-- clickRow and moveHandle over a hand-built environment (`env` stands in
-- for the game's globals), then the fake twins. First guesses, not tested
-- in game.
local tests = {}

local function count(list, what)
    local n = 0
    for _, v in ipairs(list) do if v == what then n = n + 1 end end
    return n
end

-- Frames that record every method called on them (frame.calls) and how
-- they were made (env.made: { kind, name, parent, template, frame }).
-- env.lock is what InCombatLockdown answers. A named frame is also a
-- global, as the game's are.
local function frameEnv(lock)
    local env = { made = {}, lock = lock, UIParent = { isParent = true } }
    function env.InCombatLockdown() return env.lock end
    function env.CreateFrame(kind, name, parent, template)
        local f = { attrs = {}, calls = {}, scripts = {}, shown = true }
        local function log(m) f.calls[#f.calls + 1] = m end
        function f:Hide() log("Hide"); self.shown = false end
        function f:Show() log("Show"); self.shown = true end
        function f:IsShown() return self.shown end
        function f:SetSize() log("SetSize") end
        function f:SetFrameStrata() log("SetFrameStrata") end
        function f:SetClampedToScreen() log("SetClampedToScreen") end
        function f:SetMovable(on) log("SetMovable"); self.movable = on end
        function f:EnableMouse() log("EnableMouse") end
        function f:RegisterForDrag() log("RegisterForDrag") end
        function f:RegisterForClicks(...) log("RegisterForClicks"); self.clicks = { ... } end
        function f:SetHighlightTexture() log("SetHighlightTexture") end
        function f:ClearAllPoints() log("ClearAllPoints") end
        function f:SetPoint(...) log("SetPoint"); self.point = { ... } end
        function f:GetPoint() return "BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", 120, 80 end
        function f:StartMoving() log("StartMoving") end
        function f:StopMovingOrSizing() log("StopMovingOrSizing") end
        function f:SetUserPlaced(on) log("SetUserPlaced"); self.userPlaced = on end
        function f:SetScript(name, fn) self.scripts[name] = fn end
        function f:CreateTexture()
            local tex = {}
            function tex:SetAllPoints() end
            function tex:SetColorTexture() end
            function tex:SetTexture(v) self.texture = v end
            f.tex = tex
            return tex
        end
        function f:SetAttribute(attr, value)
            log("SetAttribute")
            if env.refuse then error("blocked") end
            self.attrs[attr] = value
        end
        function f:GetAttribute(attr) return self.attrs[attr] end
        env.made[#env.made + 1] = { kind = kind, name = name, parent = parent, template = template, frame = f }
        if type(name) == "string" then env[name] = f end
        return f
    end
    return env
end

local function row(env, n)
    return ns.make.client(env).clickRow({ name = "TestSlots", count = n or 3, size = 32, gap = 4 })
end

-- ------------------------------------------------------------- clickRow
tests["client clickRow: a hidden holder and secure buttons on it, one per slot"] = function(t)
    local env = frameEnv(false)
    local h = row(env, 3)
    t.eq(type(h), "table")
    t.eq(#env.made, 4)
    t.eq({ env.made[1].kind, env.made[1].name }, { "Frame", "TestSlots" })
    t.ok(env.made[1].parent == env.UIParent, "the holder is on the screen")
    for i = 1, 3 do
        local m = env.made[i + 1]
        t.eq({ m.kind, m.name, m.template }, { "Button", "TestSlots" .. i, "SecureActionButtonTemplate" })
        t.ok(m.parent == env.made[1].frame, "on the holder")
        t.eq(m.frame.shown, false, "hidden until it holds something")
        t.eq(m.frame.clicks, { "AnyUp", "AnyDown" }, "takes the player's click")
    end
    t.eq(env.made[1].frame.shown, false)
    t.eq(env.made[1].frame.movable, true, "the holder can be moved by the handle")
end

tests["client clickRow: nil in a fight, with the lock not known, or with no frames"] = function(t)
    local env = frameEnv(true)
    t.eq(row(env), nil, "in a fight")
    t.eq(#env.made, 0, "nothing made in a fight")
    t.eq(row(frameEnv(nil)), nil, "the lock gave no answer")
    t.eq(ns.make.client({}).clickRow({ name = "TestSlots", count = 2 }), nil, "no CreateFrame")
    local e = frameEnv(false)
    e.CreateFrame = function() error("the client refused") end
    t.eq(row(e), nil, "a failed call")
    t.eq(row(frameEnv(false), 0), nil, "no slots asked for")
end

tests["client clickRow: set outside a fight puts the attribute on that slot's button"] = function(t)
    local env = frameEnv(false)
    local h = row(env)
    t.eq(h.set(2, "spell", "Renew"), true)
    t.eq(env.made[3].frame.attrs.spell, "Renew")
    t.eq(h.get(2, "spell"), "Renew")
    t.eq(h.get(1, "spell"), nil)
    local ok, why = h.set(9, "spell", "Renew")
    t.eq({ ok, why }, { false, "absent" })
end

tests["client clickRow: set, show and place in a fight are refused and the frame is not touched"] = function(t)
    local env = frameEnv(false)
    local h = row(env)
    h.set(1, "type", "spell")
    env.lock = true
    local before = #env.made[2].frame.calls
    t.eq({ h.set(1, "type", "item") }, { false, "lockdown" })
    t.eq({ h.show(1, true) }, { false, "lockdown" })
    t.eq({ h.show(0, true) }, { false, "lockdown" })
    t.eq({ h.place({ "CENTER", "CENTER", 0, 0 }) }, { false, "lockdown" })
    t.eq(#env.made[2].frame.calls, before, "the button was not asked")
    t.eq(h.get(1, "type"), "spell", "what it held stays")
    env.lock = "no"
    t.eq({ h.set(1, "type", "item") }, { false, "lockdown" }, "a lock that is not a plain false is the lock")
end

tests["client clickRow: a SetAttribute that fails is refused"] = function(t)
    local env = frameEnv(false)
    local h = row(env)
    env.refuse = true
    t.eq({ h.set(1, "type", "spell") }, { false, "refused" })
end

tests["client clickRow: show and hide a slot and the row; place the row; an icon"] = function(t)
    local env = frameEnv(false)
    local h = row(env)
    t.eq(h.show(2, true), true)
    t.eq(h.isShown(2), true)
    t.eq(h.show(0, true), true)
    t.eq(env.made[1].frame.shown, true)
    t.eq(h.show(2, false), true)
    t.eq(h.isShown(2), false)
    t.eq(h.place({ "CENTER", "CENTER", 10, -20 }), true)
    local p = env.made[1].frame.point
    t.eq({ p[1], p[3], p[4], p[5] }, { "CENTER", "CENTER", 10, -20 })
    t.ok(p[2] == env.UIParent, "placed against the screen")
    t.eq(h.icon(1, "tex:Smite"), true)
    t.eq(env.made[2].frame.tex.texture, "tex:Smite")
    t.eq(h.icon(1, nil), false, "no picture")
end

-- ----------------------------------------------------------- moveHandle
local function handle(env, onMoved)
    local c = ns.make.client(env)
    c.clickRow({ name = "TestSlots", count = 2 })
    local h = c.moveHandle({ target = "TestSlots", width = 10, height = 32, onMoved = onMoved })
    local grip = env.made[#env.made].frame
    return h, grip, env.TestSlots
end

tests["client moveHandle: a grip on the named frame; nil with no such frame"] = function(t)
    local env = frameEnv(false)
    local h, _, holder = handle(env, function() end)
    t.eq(type(h), "table")
    t.ok(env.made[#env.made].parent == holder, "the grip hangs on the frame it moves")
    t.eq(ns.make.client(frameEnv(false)).moveHandle({ target = "Nothing" }), nil)
    t.eq(ns.make.client(frameEnv(false)).moveHandle(nil), nil)
end

tests["client moveHandle: a drag out of a fight moves the frame and hands back its place"] = function(t)
    local env = frameEnv(false)
    local got
    local _, grip, holder = handle(env, function(point) got = point end)
    grip.scripts.OnDragStart()
    grip.scripts.OnDragStop()
    t.eq(count(holder.calls, "StartMoving"), 1)
    t.eq(count(holder.calls, "StopMovingOrSizing"), 1)
    t.eq(holder.userPlaced, false, "the client's own layout cache is not written")
    t.eq(got, { "BOTTOMLEFT", "BOTTOMLEFT", 120, 80 })
end

tests["client moveHandle: a drag in a fight does not move the frame"] = function(t)
    local env = frameEnv(false)
    local got
    local _, grip, holder = handle(env, function(point) got = point end)
    env.lock = true
    grip.scripts.OnDragStart()
    grip.scripts.OnDragStop()
    t.eq(count(holder.calls, "StartMoving"), 0)
    t.eq(got, nil, "nothing handed back")
end

-- SC-3: a drag that ends in a fight does not stop the protected frame
-- then; it stops it, and hands back the place, once the fight is over.
local function fireEvent(env, name, ...)
    for _, m in ipairs(env.made) do
        local fn = m.frame.scripts.OnEvent
        if type(fn) == "function" then fn(m.frame, name, ...) end
    end
end

tests["client moveHandle: a drag that ends in a fight stops after the fight"] = function(t)
    local env = frameEnv(false)
    local got, n = nil, 0
    local _, grip, holder = handle(env, function(point) got = point; n = n + 1 end)
    grip.scripts.OnDragStart()
    env.lock = true
    grip.scripts.OnDragStop()
    t.eq(count(holder.calls, "StopMovingOrSizing"), 0, "not stopped in the fight")
    t.eq(got, nil, "nothing handed back in the fight")
    env.lock = false
    fireEvent(env, "PLAYER_REGEN_ENABLED")
    t.eq(count(holder.calls, "StopMovingOrSizing"), 1, "stopped after the fight")
    t.eq(got, { "BOTTOMLEFT", "BOTTOMLEFT", 120, 80 })
    fireEvent(env, "PLAYER_REGEN_ENABLED")
    t.eq(count(holder.calls, "StopMovingOrSizing"), 1, "once only")
    t.eq(n, 1)
end

tests["client moveHandle: a handler that raises does not escape"] = function(t)
    local env = frameEnv(false)
    local _, grip = handle(env, function() error("boom") end)
    grip.scripts.OnDragStart()
    t.eq(pcall(grip.scripts.OnDragStop), true)
end

-- ------------------------------------------------------------------ fakes
tests["fake clickRow and moveHandle: recorded, frozen in a fight, logged as secure sets"] = function(t)
    local c = ns.make.fakeClient()
    c.setCombat(false)
    local h = c.clickRow({ name = "TestSlots", count = 2 })
    t.ok(h ~= nil and c.clickRows[1] == h)
    if not h then return end
    t.eq(h.set(1, "spell", "Smite"), true)
    t.eq(c.secureGiven[#c.secureGiven], { name = "TestSlots1", attr = "spell", value = "Smite" })
    local moved
    t.ok(c.moveHandle({ target = "TestSlots", onMoved = function(p) moved = p end }) ~= nil)
    t.eq(c.dragHandle("TestSlots", { "CENTER", "CENTER", 5, 5 }), true)
    t.eq(moved, { "CENTER", "CENTER", 5, 5 })
    c.setCombat(true)
    t.eq({ h.set(1, "spell", "Renew") }, { false, "lockdown" })
    t.eq(h.get(1, "spell"), "Smite")
    t.eq({ c.dragHandle("TestSlots", { "CENTER", "CENTER", 0, 0 }) }, { false, "lockdown" })
    t.eq(c.clickRow({ name = "Other", count = 1 }), nil, "not made in a fight")
    c.setCombat(false); c.setFrames(false)
    t.eq(c.clickRow({ name = "Other", count = 1 }), nil, "no frames")
end

return tests

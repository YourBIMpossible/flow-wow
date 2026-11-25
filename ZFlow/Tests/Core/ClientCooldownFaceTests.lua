-- The cooldown face (lead section 624 Step 4): c.cooldownFace(spec), one
-- plain face of its own (a picture, the dark sweep over it, the seconds in
-- the middle) for Rotation/Cooldowns.lua. Two halves:
--   the real client (Core/Client.lua) over a hand-built environment whose
--   frames keep every call made on them;
--   the fake client (Core/ClientFake.lua), which records what was drawn.
-- What is checked is what the helper does, not how it looks: the sweep is
-- set from the client's own (start, duration), a time that cannot be read
-- draws nothing, the game's own numbers are switched off, and only the
-- face itself is ever placed, shown or hidden: a frame it is set against
-- gets no call at all. Made-up frames and numbers. Not tested in game.
local _, ns = ...

local tests = {}

-- A frame that keeps every method call made on it, in order.
local function recorder(kind, name, parent, template)
    local f = { kind = kind, name = name, parent = parent, template = template, calls = {}, kids = {}, shown = true }
    local special = {}
    function special.Show(self) self.shown = true end
    function special.Hide(self) self.shown = false end
    function special.IsShown(self) return self.shown end
    function special.GetFrameLevel() return 5 end
    function special.CreateTexture(self)
        local kid = recorder("Texture", nil, self)
        self.kids[#self.kids + 1] = kid
        return kid
    end
    function special.CreateFontString(self)
        local kid = recorder("FontString", nil, self)
        self.kids[#self.kids + 1] = kid
        return kid
    end
    return setmetatable(f, { __index = function(owner, m)
        local fn = function(self, ...)
            self.calls[#self.calls + 1] = { m, ... }
            if special[m] then return special[m](self, ...) end
            return nil
        end
        rawset(owner, m, fn)
        return fn
    end })
end

-- The calls of one name made on a frame.
local function calls(f, name)
    local out = {}
    for _, one in ipairs(f.calls) do
        if one[1] == name then out[#out + 1] = one end
    end
    return out
end

local function last(f, name)
    local list = calls(f, name)
    return list[#list]
end

-- An environment with CreateFrame, a parent, a clock, one spell and one
-- item on cooldown, one of each ready, and a frame named "Other Button".
local function world()
    local made = {}
    local env = { UIParent = recorder("Frame", "UIParent"), STANDARD_TEXT_FONT = "font" }
    env["Other Button"] = recorder("Button", "Other Button")
    function env.CreateFrame(kind, name, parent, template)
        local f = recorder(kind, name, parent, template)
        made[#made + 1] = f
        return f
    end
    function env.GetTime() return 100 end
    function env.GetSpellCooldown(id)
        if id == 11 then return 90, 30, 1 end
        if id == 12 then return 0, 0, 1 end
        if id == 13 then error("no such spell") end
        return nil
    end
    function env.GetItemCooldown(id)
        if id == 21 then return 95, 60 end
        if id == 22 then return 0, 0 end
        return nil
    end
    return env, made
end

local function byKind(made, kind)
    for _, f in ipairs(made) do
        if f.kind == kind then return f end
    end
    return nil
end

tests["cooldown face: one plain face on the screen, hidden at first, with the game's numbers off"] = function(t)
    local env, made = world()
    local h = ns.make.client(env).cooldownFace({ name = "Test Face", size = 38 })
    t.ok(type(h) == "table", "a handle")
    if type(h) ~= "table" then return end
    local face = made[1]
    t.eq(face and face.kind, "Frame", "a plain frame")
    t.ok(face ~= nil and face.parent == env.UIParent, "on the screen, not on a button")
    t.eq(face and face.shown, false, "hidden until shown")
    t.eq(h.shown(), false)
    local cd = byKind(made, "Cooldown")
    t.ok(cd ~= nil, "a sweep frame")
    t.ok(cd ~= nil and cd.parent == face, "over the face")
    local off = cd and last(cd, "SetHideCountdownNumbers")
    t.eq(off and off[2], true, "the game's own numbers are switched off")
    t.eq(#calls(face, "SetAttribute"), 0, "nothing secure is set")
    local mouse = last(face, "EnableMouse")
    t.ok(mouse == nil or mouse[2] == false, "it takes no mouse")
end

tests["cooldown face: the sweep is set from the spell's own start and length"] = function(t)
    local env, made = world()
    local h = ns.make.client(env).cooldownFace({})
    t.ok(type(h) == "table", "a handle")
    if type(h) ~= "table" then return end
    local cd = byKind(made, "Cooldown")
    t.eq(h.spell(11), "sweep", "on cooldown")
    local set = cd and last(cd, "SetCooldown")
    t.eq(set and { set[2], set[3] }, { 90, 30 }, "start and length as the client gave them")
    t.eq(h.spell(12), "none", "read, and not on cooldown")
    set = cd and last(cd, "SetCooldown")
    t.eq(set and { set[2], set[3] }, { 0, 0 }, "the sweep is cleared")
    h.spell(11)
    t.eq(h.spell(13), nil, "a read that fails: not known")
    set = cd and last(cd, "SetCooldown")
    t.eq(set and { set[2], set[3] }, { 0, 0 }, "nothing is drawn for a time that cannot be read")
    t.eq(h.spell(14), nil, "no answer from the client: not known")
    t.eq(h.spell("x"), nil, "not a spell id")
end

tests["cooldown face: an item's sweep, from the item's own start and length"] = function(t)
    local env, made = world()
    local h = ns.make.client(env).cooldownFace({})
    t.ok(type(h) == "table", "a handle")
    if type(h) ~= "table" then return end
    local cd = byKind(made, "Cooldown")
    t.eq(h.item(21), "sweep")
    local set = cd and last(cd, "SetCooldown")
    t.eq(set and { set[2], set[3] }, { 95, 60 })
    t.eq(h.item(22), "none")
    t.eq(h.item(23), nil, "not known")
    t.eq(h.item(0), nil, "not an item id")
end

tests["cooldown face: the seconds are the caller's text, shown and cleared"] = function(t)
    local env, made = world()
    local h = ns.make.client(env).cooldownFace({})
    t.ok(type(h) == "table", "a handle")
    if type(h) ~= "table" then return end
    local text
    for _, f in ipairs(made) do
        for _, kid in ipairs(f.kids) do
            if kid.kind == "FontString" then text = kid end
        end
    end
    t.ok(text ~= nil, "a text over the sweep")
    if not text then return end
    t.eq(text.shown, false, "nothing said at first")
    h.seconds("7")
    t.eq(last(text, "SetText")[2], "7")
    t.eq(text.shown, true)
    h.seconds(nil)
    t.eq(text.shown, false, "nil clears it")
    h.seconds("4.2")
    h.spell(11)
    h.clear()
    t.eq(text.shown, false, "clear takes the seconds away")
    local cd = byKind(made, "Cooldown")
    local set = cd and last(cd, "SetCooldown")
    t.eq(set and { set[2], set[3] }, { 0, 0 }, "and the sweep")
end

tests["cooldown face: only the face is placed, shown or hidden; the frame it is set against gets no call"] = function(t)
    local env, made = world()
    local h = ns.make.client(env).cooldownFace({})
    t.ok(type(h) == "table", "a handle")
    if type(h) ~= "table" then return end
    local face, other = made[1], env["Other Button"]
    h.place({ "CENTER", "CENTER", 380, 220 })
    local p = last(face, "SetPoint")
    t.eq(p and { p[2], p[4], p[5], p[6] }, { "CENTER", "CENTER", 380, 220 }, "placed where it was asked")
    t.ok(p ~= nil and p[3] == env.UIParent, "against the screen")
    local ok, why = h.anchor("LEFT", "Other Button", "RIGHT", 6, 0)
    t.eq(ok, true, "set against a frame by its name")
    t.eq(why, nil)
    p = last(face, "SetPoint")
    t.eq(p and { p[2], p[4], p[5], p[6] }, { "LEFT", "RIGHT", 6, 0 }, "the face is what is placed")
    t.ok(p ~= nil and p[3] == other, "against the named frame")
    h.show(true)
    t.eq(face.shown, true)
    t.eq(h.shown(), true)
    h.show(false)
    t.eq(face.shown, false)
    t.eq(#other.calls, 0, "the other frame got no call at all")
    local before = #calls(face, "SetPoint")
    local no, reason = h.anchor("LEFT", "No Such Frame", "RIGHT", 6, 0)
    t.eq(no, false, "no frame by that name")
    t.eq(reason, "no frame")
    t.eq(#calls(face, "SetPoint"), before, "and the face stays where it was")
end

-- Twin's review of 79b3143e (lead section 638): the client turns the
-- SetPoint down (it raises), and h.anchor says so; the named frame still
-- gets no call. Red before for the fake half only: the real client already
-- answered "refused", untested.
tests["cooldown face: a SetPoint the client turns down is answered as refused"] = function(t)
    local env, made = world()
    local h = ns.make.client(env).cooldownFace({})
    t.ok(type(h) == "table", "a handle")
    if type(h) ~= "table" then return end
    local face, other = made[1], env["Other Button"]
    local asked = 0
    rawset(face, "SetPoint", function()
        asked = asked + 1
        error("made-up refusal")
    end)
    local ok, why = h.anchor("LEFT", "Other Button", "RIGHT", 6, 0)
    t.eq(ok, false, "not set")
    t.eq(why, "refused", "and it says the client turned it down")
    t.eq(asked, 1, "the face was what the client was asked to place")
    t.eq(#other.calls, 0, "the other frame got no call")
end

tests["cooldown face, fake: a test can make the next anchor be refused, and the record keeps it"] = function(t)
    local c = ns.make.fakeClient()
    t.ok(type(c.cooldownFace) == "function" and type(c.setCooldownAnchorRefused) == "function",
        "the fake has the helper and the setter")
    if type(c.cooldownFace) ~= "function" or type(c.setCooldownAnchorRefused) ~= "function" then return end
    c.setFrameRect("Other Button", { l = 0, r = 10, b = 0, t = 10 })
    local h = c.cooldownFace({})
    local rec = c.cooldownFaces[1]
    h.place({ "CENTER", "CENTER", 0, 0 })
    c.setCooldownAnchorRefused(true)
    local ok, why = h.anchor("LEFT", "Other Button", "RIGHT", 6, 0)
    t.eq(ok, false)
    t.eq(why, "refused")
    t.eq(rec.refused, 1, "the record counts the refusal")
    t.eq(rec.anchor, nil, "and the face is not set against the frame")
    c.setCooldownAnchorRefused(false)
    t.eq(h.anchor("LEFT", "Other Button", "RIGHT", 6, 0), true, "switched off again: it is set")
    t.eq(rec.refused, 1, "no more refusals counted")
    local no, reason = h.anchor("LEFT", "No Such Frame", "RIGHT", 6, 0)
    t.eq(no, false)
    t.eq(reason, "no frame", "no frame is still told apart from refused")
end

tests["cooldown face: a client that cannot make a frame gives no face"] = function(t)
    local env = world()
    env.CreateFrame = nil
    t.eq(ns.make.client(env).cooldownFace({}), nil)
end

tests["cooldown face, fake: every face is kept with what was drawn on it"] = function(t)
    local c = ns.make.fakeClient()
    t.ok(type(c.cooldownFace) == "function", "the fake has the same helper")
    if type(c.cooldownFace) ~= "function" then return end
    local h = c.cooldownFace({ name = "Test Face", size = 58 })
    local rec = c.cooldownFaces and c.cooldownFaces[1]
    t.ok(type(h) == "table" and type(rec) == "table", "a handle and its record")
    if type(h) ~= "table" or type(rec) ~= "table" then return end
    t.eq({ rec.name, rec.size, rec.shown }, { "Test Face", 58, false })
    h.place({ "CENTER", "CENTER", 380, 220 })
    t.eq(rec.point, { "CENTER", "CENTER", 380, 220 })
    h.show(true)
    t.eq(rec.shown, true)
    t.eq(h.shown(), true)
    t.eq(h.icon("tex"), true)
    t.eq(rec.texture, "tex")
    t.eq(h.icon(nil), false, "nil clears the picture")
    t.eq(rec.texture, nil)
    t.eq(h.spell(11), nil, "a spell never set: not known")
    t.eq(rec.sweep, nil)
    c.setSpellCooldown(11, true)
    t.eq(h.spell(11), "sweep")
    t.eq(rec.sweep, { kind = "spell", id = 11 })
    c.setSpellCooldown(11, false)
    t.eq(h.spell(11), "none")
    t.eq(rec.sweep, nil, "ready: the sweep is cleared")
    c.setItemCooldown(21, 30)
    t.eq(h.item(21), "sweep")
    t.eq(rec.sweep, { kind = "item", id = 21 })
    c.setItemCooldown(21, 0)
    t.eq(h.item(21), "none")
    h.seconds("7")
    t.eq(rec.seconds, "7")
    c.setSpellCooldown(11, true)
    h.spell(11)
    h.clear()
    t.eq(rec.sweep, nil, "clear takes the sweep away")
    t.eq(rec.seconds, nil, "and the seconds")
    local no, reason = h.anchor("LEFT", "Other Button", "RIGHT", 6, 0)
    t.eq(no, false, "a name the fake has no frame for")
    t.eq(reason, "no frame")
    c.setFrameRect("Other Button", { l = 0, r = 10, b = 0, t = 10 })
    t.eq(h.anchor("LEFT", "Other Button", "RIGHT", 6, 0), true)
    t.eq(rec.anchor, { point = "LEFT", to = "Other Button", relPoint = "RIGHT", x = 6, y = 0 })
    t.eq(rec.point, nil, "set against a frame: no place on the screen of its own")
    h.place({ "CENTER", "CENTER", 0, 0 })
    t.eq(rec.anchor, nil, "placed on the screen again: no longer set against the frame")
    c.cooldownFace({})
    t.eq(#c.cooldownFaces, 2, "each face made is kept, in order")
end

return tests

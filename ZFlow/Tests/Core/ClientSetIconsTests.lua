-- The set icon row (P-SETS branch 2, S19; Gear/SetIcons.lua). The real
-- client over a hand-built environment; ClientFake's own version after.
--   c.iconRow(spec) -> h: draw(icons, act), show(on), shown(), place(point),
--                      onMoved(fn, failed); nil without frames
-- The row acts on nothing itself: a left click asks act(key), no more.
-- Needs game test: the layout, the clicks and the tooltip owner.
local _, ns = ...

local tests = {}

-- A stand-in for the client's frames and its tooltip.
local function gameEnv()
    local env = { frames = {}, UIParent = {}, tip = { lines = {}, shown = false } }
    function env.tip.SetOwner(self, owner) self.owner = owner; self.lines = {} end
    function env.tip.AddLine(self, text) self.lines[#self.lines + 1] = text end
    function env.tip.Show(self) self.shown = true end
    function env.tip.Hide(self) self.shown = false end
    env.GameTooltip = env.tip
    local function texture(parent)
        local tx = { kind = "Texture", parent = parent }
        function tx:SetTexture(v, ...) if select("#", ...) == 0 then self.file = v end end
        function tx:SetColorTexture(r, g, b, a) self.rgba = { r, g, b, a } end
        function tx:SetPoint() end
        function tx:SetAllPoints() end
        return tx
    end
    function env.CreateFrame(kind, name, parent)
        local f = { kind = kind, name = name, parent = parent, scripts = {}, shown = true, textures = {} }
        function f:SetScript(script, fn) self.scripts[script] = fn end
        function f:IsShown() return self.shown end
        function f:Show() self.shown = true end
        function f:Hide() self.shown = false end
        function f:CreateTexture()
            local tx = texture(self)
            self.textures[#self.textures + 1] = tx
            return tx
        end
        function f:GetPoint() return self.at and self.at[1], nil, self.at and self.at[2], self.at and self.at[3], self.at and self.at[4] end
        env.frames[#env.frames + 1] = f
        if name ~= nil and env[name] == nil then env[name] = f end
        return f
    end
    return env
end

local function shownButtons(env)
    local out = {}
    for _, f in ipairs(env.frames) do
        if f.kind == "Button" and f.shown then out[#out + 1] = f end
    end
    return out
end

-- Fails before: c.iconRow is absent (Core/Client.lua, the S19 row).
tests["c.iconRow: one button per icon, the gold edge on the worn set, a left click asks act(key)"] = function(t)
    local env = gameEnv()
    local h = ns.make.client(env).iconRow({ name = "TestSetIcons", size = 28 })
    if not h then t.ok(false, "no icon row") return end
    local acts = {}
    h.draw({
        { key = "tank", texture = "tex-a", edge = true, tip = { "tank", "You wear all of it." } },
        { key = "heal", texture = "tex-b", edge = false, tip = { "heal" } },
    }, function(key) acts[#acts + 1] = key end)
    local bs = shownButtons(env)
    t.eq(#bs, 2, "two buttons")
    if #bs < 2 then return end
    t.eq(bs[1].textures[1].rgba, { 1, 0.82, 0, 1 }, "the worn set's edge is gold")
    t.eq(bs[2].textures[1].rgba, { 0, 0, 0, 0.9 }, "the other a thin dark edge")
    t.eq(bs[1].textures[2].file, "tex-a", "its picture")
    bs[1].scripts.OnClick(bs[1], "LeftButton")
    bs[2].scripts.OnClick(bs[2], "RightButton")
    t.eq(acts, { "tank" }, "a left click asks act; another button asks nothing")
    bs[1].scripts.OnEnter(bs[1])
    t.eq(env.tip.lines, { "tank", "You wear all of it." }, "hover: the tip lines")
    t.eq(env.tip.shown, true)
    bs[1].scripts.OnLeave(bs[1])
    t.eq(env.tip.shown, false)
end

tests["c.iconRow: at most twelve, a redraw hides the rest, an error in act stays in the row"] = function(t)
    local env = gameEnv()
    local h = ns.make.client(env).iconRow({ name = "TestSetIconsMax" })
    if not h then t.ok(false, "no icon row") return end
    local many = {}
    for i = 1, 14 do many[i] = { key = "s" .. i, tip = { "s" .. i } } end
    h.draw(many, function() end)
    t.eq(#shownButtons(env), 12, "twelve at most")
    h.draw({ { key = "one", tip = { "one" } } }, function() error("broken") end)
    local bs = shownButtons(env)
    t.eq(#bs, 1, "the redraw hides the others")
    t.ok(bs[1] ~= nil and pcall(bs[1].scripts.OnClick, bs[1], "LeftButton"), "a raising act does not raise into the client")
    h.draw({}, nil)
    t.eq(#shownButtons(env), 0)
end

tests["c.iconRow: hidden at first, shown on ask, and not made without frames"] = function(t)
    local env = gameEnv()
    local h = ns.make.client(env).iconRow({ name = "TestSetIconsShow" })
    if not h then t.ok(false, "no icon row") return end
    t.eq(h.shown(), false)
    h.show(true)
    t.eq(h.shown(), true)
    t.eq(env.TestSetIconsShow.shown, true)
    t.eq(ns.make.client({}).iconRow({ name = "TestNoFrames" }), nil)
end

tests["fake client: the icon row records its icons, presses as the player and is dragged"] = function(t)
    local c = ns.make.fakeClient()
    local h = c.iconRow({ name = "TestSetIcons" })
    if not h then t.ok(false, "no icon row") return end
    t.eq(c.iconRows[1], h)
    local got = {}
    h.draw({ { key = "tank", edge = true } }, function(key) got[#got + 1] = key end)
    t.eq(h.press("tank"), true)
    t.eq(h.press("none"), false)
    t.eq(got, { "tank" })
    local moved
    h.onMoved(function(point) moved = point end)
    h.drag({ "TOPLEFT", "TOPLEFT", 10, -20 })
    t.eq(moved, { "TOPLEFT", "TOPLEFT", 10, -20 })
end

-- S19: the game's own equipment sets are not used on 16001 (never asked);
-- their names, and EquipItemByName, are recorded at login.
tests["diag: the equip and equipment set names are recorded at login"] = function(t)
    local listed = {}
    for _, name in ipairs(ns.Diag.NAMES) do listed[name] = true end
    for _, name in ipairs({ "EquipItemByName", "C_EquipmentSet.GetEquipmentSetIDs",
        "C_EquipmentSet.GetEquipmentSetInfo", "C_EquipmentSet.UseEquipmentSet" }) do
        t.ok(listed[name] == true, name)
    end
end

return tests

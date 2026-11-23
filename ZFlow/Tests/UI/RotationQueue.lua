-- Tests for ZFlow/UI/RotationQueue.lua (S13, the modifier queue display)
-- over the fake client in a kernel, and the two client reads it stands on
-- (client.slotIcon, client.modifiers) over a made-up environment. The
-- views are hand-made and given on the bus. Not tested in game.
local _, ns = ...

local U = ns.RotationQueue
local Q = ns.Queue
local I = ns.RotationIcon
local D = ns.RotationDriver
local R = ns.Rotation
local tests = {}

local CLASS = "TESTCLASS"
-- Test values, not client data.
local IDS = { Wrath = 5176, Moonfire = 8921, Starfire = 2912, Rejuvenation = 774,
    ["Entangling Roots"] = 339, Maul = 6807, Pounce = 9005 }
local function tex(name) return IDS[name] + 100000 end

local function pack()
    return {
        spells = { Wrath = { evidence = "test" } },
        lists = { default = { { spell = "Wrath", target = true, reason = "Wrath" } } },
        keys = { none = { key = "Wrath" } },
    }
end

-- What must never be called: the queue shows, it presses nothing.
local FORBIDDEN = { "SetAttribute", "SetBinding", "SetBindingClick", "SetOverrideBinding",
    "SetOverrideBindingClick", "CastSpell", "CastSpellByName", "CastSpellByID", "UseAction",
    "RunMacroText", "SecureCmdOptionParse", "RegisterStateDriver", "glow", "panel", "arrow" }

local function row()
    return { key = "Wrath", shift = "Moonfire", ctrl = "Starfire", alt = "Rejuvenation", more = "Entangling Roots" }
end
local function plan()
    return { states = { [0] = row(), [1] = { key = "Maul", shift = "Wrath" },
        [R.STEALTH_STATE] = { key = "Pounce", ctrl = "Moonfire" } } }
end

-- opts: saved (account table), off (the driver setting left off), noFrames,
-- noTextures, before(c) (last word on the client before the kernel is made).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    for name, id in pairs(IDS) do
        c.setSpellId(name, id)
        if not opts.noTextures then c.setSpellTexture(id, tex(name)) end
    end
    c.setSaved(ns.id.accountDB, opts.saved or {})
    c.setSaved(ns.id.charDB, {})
    c.setDead(false)
    c.setClass(CLASS)
    c.setScreen(1024, 768)
    c.setForm(0)
    if opts.noFrames then c.setFrames(false) end
    local calls = {}
    for _, name in ipairs(FORBIDDEN) do
        c[name] = function() calls[name] = (calls[name] or 0) + 1 end
    end
    if opts.before then opts.before(c) end
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    D.Declare(k, { [CLASS] = pack() })
    I.Declare(k)
    local api = U.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    k.settings:set(D.SETTING, not opts.off)
    return k, c, api, calls
end

-- A view as the driver gives it out of a fight: the keys carry the plan.
local function view(spell, snapshot, keys)
    return {
        snapshot = snapshot or { form = 0, inCombat = false, hostile = true },
        suggestion = spell and { spell = spell } or nil,
        keys = keys or { plan = plan(), stealthForm = 3 },
    }
end
local function give(k, v) k.bus:emit(D.EVENT, v) end
local function shown(c)
    local out = {}
    for i, h in ipairs(c.slotIcons) do out[i] = h.shown end
    return out
end
local function count(calls)
    local n = 0
    for _, v in pairs(calls) do n = n + v end
    return n
end

-- ------------------------------------------------------------ what it says
tests["rotation queue: names and colours"] = function(t)
    t.eq(U.NAME, "rotationQueue")
    t.eq(U.SETTING, "rotationQueue.enabled")
    t.eq(U.MOD_EVENT, "MODIFIER_STATE_CHANGED")
    t.eq(U.COLOR, { advised = { 1, 0.82, 0 }, held = { 0.4, 1, 0.4 } })
end

tests["rotation queue: its setting is on by default"] = function(t)
    local k = start()
    t.eq(k.settings:get(U.SETTING), true)
end

-- ------------------------------------------------------------ what it makes
tests["rotation queue: four hidden slot icons, nearest first, each with its word and size"] = function(t)
    local k, c, api = start()
    t.eq(#c.slotIcons, 4)
    t.ok(api.handles() ~= nil)
    for i, slot in ipairs(Q.ORDER) do
        local h = c.slotIcons[i]
        t.ok(api.handles()[i] == h, "the handle the module holds")
        t.eq(h.spec.size, Q.SIZES[i])
        t.eq(h.spec.label, Q.LABEL[slot])
        t.eq(h.spec.name, ns.id.framePrefix .. "RotationQueue" .. i)
        t.eq(h.shown, false)
    end
    t.eq(k.problems:count(U.NAME), 0)
end

-- ------------------------------------------------------------ what it shows
tests["rotation queue: with an enemy targeted each slot shows what its press casts"] = function(t)
    local k, c = start()
    give(k, view(nil))
    t.eq(shown(c), { true, true, true, true })
    for i, slot in ipairs(Q.ORDER) do
        t.eq(c.slotIcons[i].texture, tex(row()[slot]), slot)
        t.eq(c.slotIcons[i].marked, nil, slot .. ": no edge")
    end
end

tests["rotation queue: the press that casts the suggestion is edged gold"] = function(t)
    local k, c = start()
    give(k, view("Starfire"))
    t.eq(c.slotIcons[2].marked, U.COLOR.advised)
    t.eq(c.slotIcons[1].marked, nil)
    give(k, view("Wrath"))
    for i = 1, 4 do t.eq(c.slotIcons[i].marked, nil, "the plain key casts it") end
    give(k, view("Hurricane"))
    for i = 1, 4 do t.eq(c.slotIcons[i].marked, nil, "not on a press") end
end

tests["rotation queue: the held modifier is edged green, over gold"] = function(t)
    local k, c = start()
    c.setModifiers(false, true, false)
    give(k, view("Starfire"))
    t.eq(c.slotIcons[1].marked, U.COLOR.held)
    t.eq(c.slotIcons[2].marked, U.COLOR.advised)
    c.setModifiers(true, false, false)
    give(k, view("Starfire"))
    t.eq(c.slotIcons[1].marked, nil)
    t.eq(c.slotIcons[2].marked, U.COLOR.held)
    c.setModifiers(true, true, false)
    give(k, view(nil))
    t.eq(c.slotIcons[4].marked, U.COLOR.held, "Ctrl + Shift")
end

tests["rotation queue: a modifier that is not known marks nothing"] = function(t)
    local k, c = start()
    c.setModifiers(true, nil, false)
    give(k, view(nil))
    for i = 1, 4 do t.eq(c.slotIcons[i].marked, nil) end
    t.eq(shown(c), { true, true, true, true }, "an enemy is targeted: still shown")
end

tests["rotation queue: the row of the form, and the stealth row when stealthed in it"] = function(t)
    local k, c = start()
    give(k, view(nil, { form = 1, inCombat = true }))
    t.eq(shown(c), { true, false, false, false }, "bear: only Shift is set")
    t.eq(c.slotIcons[1].texture, tex("Wrath"))
    give(k, view(nil, { form = 3, stealthed = true, inCombat = true }))
    t.eq(shown(c), { false, true, false, false })
    t.eq(c.slotIcons[2].texture, tex("Moonfire"))
    give(k, view(nil, { form = 2, inCombat = true }))
    t.eq(shown(c), { false, false, false, false }, "a form the plan has no row for")
end

tests["rotation queue: a snapshot with no form asks the client"] = function(t)
    local k, c = start()
    c.setForm(1)
    give(k, view(nil, { inCombat = true }))
    t.eq(shown(c), { true, false, false, false })
    c.setForm(nil)
    give(k, view(nil, { inCombat = true }))
    t.eq(shown(c), { false, false, false, false }, "the form is not known: nothing is guessed")
end

tests["rotation queue: a slot with no texture is not drawn"] = function(t)
    local k, c = start({ before = function(c2) c2.spellTexture = function(id)
        if id == IDS.Starfire then return nil end
        return id + 100000
    end end })
    give(k, view("Starfire"))
    t.eq(shown(c), { true, false, true, true })
    t.eq(c.slotIcons[2].marked, nil)
    local k3, c3 = start({ noTextures = true })
    give(k3, view(nil))
    t.eq(shown(c3), { false, false, false, false })
end

-- ------------------------------------------------------------ when it shows
tests["rotation queue: out of a fight with no enemy it shows only while a modifier is held"] = function(t)
    local k, c = start()
    local calm = { form = 0, inCombat = false, hostile = false }
    give(k, view(nil, calm))
    t.eq(shown(c), { false, false, false, false })
    c.setModifiers(false, false, true)
    give(k, view(nil, calm))
    t.eq(shown(c), { true, true, true, true })
    t.eq(c.slotIcons[3].marked, U.COLOR.held)
    c.setModifiers(false, false, false)
    give(k, view(nil, { form = 0, inCombat = true, hostile = false }))
    t.eq(shown(c), { true, true, true, true }, "in a fight")
end

tests["rotation queue: in a fight the keys are a refusal; the last plan seen is kept"] = function(t)
    local k, c = start()
    give(k, view(nil))
    give(k, view("Moonfire", { form = 0, inCombat = true, hostile = true }, { ok = false, reason = "combat" }))
    t.eq(shown(c), { true, true, true, true })
    t.eq(c.slotIcons[1].marked, U.COLOR.advised)
end

tests["rotation queue: no view hides it and forgets the plan"] = function(t)
    local k, c = start()
    give(k, view(nil))
    give(k, nil)
    t.eq(shown(c), { false, false, false, false })
    give(k, view(nil, { form = 0, inCombat = true }, { ok = false }))
    t.eq(shown(c), { false, false, false, false }, "the old plan is gone")
end

tests["rotation queue: either setting off hides it"] = function(t)
    local k, c = start()
    give(k, view(nil))
    k.settings:set(U.SETTING, false)
    give(k, view(nil))
    t.eq(shown(c), { false, false, false, false })
    k.settings:set(U.SETTING, true)
    give(k, view(nil))
    t.eq(shown(c), { true, true, true, true })
    k.settings:set(D.SETTING, false)
    give(k, view(nil))
    t.eq(shown(c), { false, false, false, false })
end

tests["rotation queue: hidden in a pet battle and in a vehicle"] = function(t)
    local k, c = start()
    c.setPetBattle(true)
    give(k, view(nil))
    t.eq(shown(c), { false, false, false, false })
    c.setPetBattle(false)
    c.setVehicle(true)
    give(k, view(nil))
    t.eq(shown(c), { false, false, false, false })
    c.setVehicle(false)
    give(k, view(nil))
    t.eq(shown(c), { true, true, true, true })
end

-- ------------------------------------------------------------ where it stands
tests["rotation queue: beside the default place of the big icon, running left"] = function(t)
    local k, c = start()
    give(k, view(nil))
    local want = Q.Place(I.DEFAULT_POINT, I.SIZE, "left")
    for i = 1, 4 do t.eq(c.slotIcons[i].point, want[i]) end
end

tests["rotation queue: placed once, and again only when the big icon has moved"] = function(t)
    local k, c = start()
    give(k, view(nil))
    give(k, view("Starfire"))
    give(k, view(nil))
    t.eq(c.slotIcons[1].places, 1)
    local point = { "CENTER", "CENTER", 200, 0 }
    k.settings:set(I.SETTING, { point = point })
    give(k, view(nil))
    t.eq(c.slotIcons[1].places, 2)
    local want = Q.Place(point, I.SIZE, "right")
    for i = 1, 4 do t.eq(c.slotIcons[i].point, want[i], "right of centre runs right") end
end

tests["rotation queue: in a fight the side is frozen; after it the slots follow the big icon"] = function(t)
    local k, c = start()
    local fight = { form = 0, inCombat = true, hostile = true }
    give(k, view(nil))
    local left = Q.Place(I.DEFAULT_POINT, I.SIZE, "left")
    t.eq(c.slotIcons[1].point, left[1])
    local point = { "CENTER", "CENTER", 200, 0 }
    k.settings:set(I.SETTING, { point = point })
    give(k, view(nil, fight))
    local kept = Q.Place(point, I.SIZE, "left")
    for i = 1, 4 do t.eq(c.slotIcons[i].point, kept[i], "moved with the icon, still to its left") end
    give(k, view(nil))
    local right = Q.Place(point, I.SIZE, "right")
    for i = 1, 4 do t.eq(c.slotIcons[i].point, right[i], "the fight is over: right of centre runs right") end
end

tests["rotation queue: a first view in a fight still picks a side"] = function(t)
    local k, c = start()
    local point = { "CENTER", "CENTER", 200, 0 }
    k.settings:set(I.SETTING, { point = point })
    give(k, view(nil, { form = 0, inCombat = true, hostile = true }))
    local want = Q.Place(point, I.SIZE, "right")
    for i = 1, 4 do t.eq(c.slotIcons[i].point, want[i]) end
end

tests["rotation queue: a run that would leave the screen goes to the other side"] = function(t)
    local k, c = start()
    -- Left half, hard against the left edge: the run to the left does not fit.
    local point = { "BOTTOMLEFT", "BOTTOMLEFT", 20, 300 }
    k.settings:set(I.SETTING, { point = point })
    give(k, view(nil))
    local want = Q.Place(point, I.SIZE, "right")
    for i = 1, 4 do t.eq(c.slotIcons[i].point, want[i]) end
end

tests["rotation queue: every slot stands on the screen"] = function(t)
    local k, c = start({ before = function(client) client.setScreen(200, 150) end })
    k.settings:set(I.SETTING, { point = { "BOTTOMLEFT", "BOTTOMLEFT", 20, 50 } })
    give(k, view(nil))
    for i, w in ipairs(Q.SIZES) do
        local p = c.slotIcons[i].point
        t.eq(p[1], "BOTTOMLEFT")
        t.eq(p[3] >= 0 and p[3] + w <= 200, true, "slot " .. i .. " across")
        t.eq(p[4] >= 0 and p[4] + w <= 150, true, "slot " .. i .. " up")
    end
end

-- ------------------------------------------------------------ the modifier event
tests["rotation queue: a modifier pressed between two views redraws the last one"] = function(t)
    local k, c = start()
    give(k, view("Starfire"))
    c.setModifiers(false, true, false)
    c.fire(U.MOD_EVENT, "LSHIFT", 1)
    t.eq(c.slotIcons[1].marked, U.COLOR.held)
    t.eq(c.slotIcons[2].marked, U.COLOR.advised)
    c.setModifiers(false, false, false)
    c.fire(U.MOD_EVENT, "LSHIFT", 0)
    t.eq(c.slotIcons[1].marked, nil)
end

-- ------------------------------------------------------------ what is missing
tests["rotation queue: no frames: one problem line, nothing shown, nothing raised"] = function(t)
    local k, c, api = start({ noFrames = true })
    t.eq(api.handles(), nil)
    t.eq(k.problems:count(U.NAME), 1)
    give(k, view(nil))
    c.fire(U.MOD_EVENT, "LSHIFT", 1)
    t.eq(#c.slotIcons, 0)
end

tests["rotation queue: a client with no slot icon read: one problem line"] = function(t)
    local k, _, api = start({ before = function(c) c.slotIcon = nil end })
    t.eq(api.handles(), nil)
    t.eq(k.problems:count(U.NAME), 1)
    give(k, view(nil))
end

tests["rotation queue: a client with no modifier read: one problem line, still shown, no green"] = function(t)
    local k, c = start({ before = function(c2) c2.modifiers = nil end })
    t.eq(k.problems:count(U.NAME), 1)
    give(k, view("Starfire"))
    t.eq(shown(c), { true, true, true, true })
    t.eq(c.slotIcons[2].marked, U.COLOR.advised)
end

tests["rotation queue: a modifier read that raises is not known"] = function(t)
    local k, c = start({ before = function(c2) c2.modifiers = function() error("boom") end end })
    give(k, view(nil))
    t.eq(shown(c), { true, true, true, true })
    for i = 1, 4 do t.eq(c.slotIcons[i].marked, nil) end
end

-- ------------------------------------------------------------ what it never does
tests["rotation queue: it presses, binds and casts nothing"] = function(t)
    local k, c, _, calls = start()
    c.setModifiers(false, true, false)
    give(k, view("Starfire"))
    c.fire(U.MOD_EVENT, "LSHIFT", 1)
    give(k, view(nil, { form = 3, stealthed = true, inCombat = true }))
    give(k, nil)
    t.eq(count(calls), 0)
end

-- ------------------------------------------------------------ the client reads
local function gameEnv(opts)
    opts = opts or {}
    local env = { frames = {}, textures = {}, texts = {}, UIParent = {} }
    function env.CreateFrame(kind, name, parent)
        local f = { kind = kind, name = name, parent = parent, shown = true }
        function f:Hide() self.shown = false end
        function f:Show() self.shown = true end
        function f:SetSize(w, h) self.w, self.h = w, h end
        function f:EnableMouse(on) self.mouse = on end
        function f:ClearAllPoints() self.point = nil end
        function f:SetPoint(a, _, r, x, y) self.point = { a, r, x, y } end
        if not opts.noTexture then
            function f:CreateTexture(_, layer)
                local tx = { layer = layer, shown = true }
                function tx:SetTexture(...) self.value = { ... } end
                if not opts.noColorTexture then
                    function tx:SetColorTexture(...) self.colour = { ... } end
                end
                function tx:SetAllPoints() self.all = true end
                function tx:SetPoint() end
                function tx:Hide() self.shown = false end
                function tx:Show() self.shown = true end
                env.textures[#env.textures + 1] = tx
                return tx
            end
        end
        function f:CreateFontString()
            local fs = {}
            function fs:SetPoint() end
            function fs:SetText(v) self.text = v end
            function fs:SetTextColor(r, g, b) self.colour = { r, g, b } end
            env.texts[#env.texts + 1] = fs
            return fs
        end
        env.frames[#env.frames + 1] = f
        return f
    end
    return env
end
local function layer(env, name)
    for _, tx in ipairs(env.textures) do
        if tx.layer == name then return tx end
    end
    return nil
end

tests["client slot icon: a hidden frame of the asked size with its word, taking no mouse"] = function(t)
    local env = gameEnv()
    local h = ns.make.client(env).slotIcon({ name = "TestSlot", size = 30, label = "CTRL" })
    t.ok(h ~= nil)
    local f = env.frames[#env.frames]
    t.eq(f.name, "TestSlot")
    t.eq(f.shown, false)
    t.eq({ f.w, f.h }, { 30, 30 })
    t.eq(f.mouse, false)
    t.eq(env.texts[1].text, "CTRL")
    t.eq(env.texts[1].colour, { 0.85, 0.85, 0.85 })
    t.eq(layer(env, "BACKGROUND").shown, false, "no edge until marked")
    t.eq(h.setTexture(1234), true)
    t.eq(layer(env, "ARTWORK").value, { 1234 })
    t.eq(h.setTexture(nil), false)
    h.show(true)
    t.eq(f.shown, true)
    h.show(false)
    t.eq(f.shown, false)
    h.place({ "TOPLEFT", "TOPLEFT", 5, -6 })
    t.eq(f.point, { "TOPLEFT", "TOPLEFT", 5, -6 })
end

tests["client slot icon: mark draws the edge and colours the word; no colour takes both back"] = function(t)
    local env = gameEnv()
    local h = ns.make.client(env).slotIcon({ size = 30, label = "ALT" })
    local ring = layer(env, "BACKGROUND")
    t.eq(h.mark(1, 0.82, 0), true)
    t.eq(ring.shown, true)
    t.eq(ring.colour, { 1, 0.82, 0, 1 })
    t.eq(env.texts[1].colour, { 1, 0.82, 0 })
    t.eq(h.mark(nil), false)
    t.eq(ring.shown, false)
    t.eq(env.texts[1].colour, { 0.85, 0.85, 0.85 })
    t.eq(h.mark(1, nil, 0), false, "half a colour is no colour")
end

tests["client slot icon: a client with no SetColorTexture gets the colour through SetTexture"] = function(t)
    local env = gameEnv({ noColorTexture = true })
    local h = ns.make.client(env).slotIcon({ size = 30 })
    t.eq(h.mark(0.4, 1, 0.4), true)
    t.eq(layer(env, "BACKGROUND").value, { 0.4, 1, 0.4, 1 })
end

tests["client slot icon: no frame, no icon; no texture, nothing is drawn and it says so"] = function(t)
    t.eq(ns.make.client({}).slotIcon({ size = 30 }), nil)
    local env = gameEnv({ noTexture = true })
    local h = ns.make.client(env).slotIcon({ size = 30 })
    t.ok(h ~= nil)
    t.eq(h.setTexture(1234), false)
    t.eq(h.mark(1, 1, 1), false)
end

tests["client modifiers: ctrl, shift, alt as true or false"] = function(t)
    local env = {
        IsControlKeyDown = function() return true end,
        IsShiftKeyDown = function() return false end,
        IsAltKeyDown = function() return nil end,
    }
    t.eq({ ns.make.client(env).modifiers() }, { true, false, false })
    env.IsShiftKeyDown = function() return 1 end
    t.eq({ ns.make.client(env).modifiers() }, { true, true, false }, "an older client answers 1")
end

tests["client modifiers: a read that is missing or raises is not known"] = function(t)
    local ctrl, shift, alt = ns.make.client({}).modifiers()
    t.eq(ctrl, nil)
    t.eq(shift, nil)
    t.eq(alt, nil)
    ctrl, shift, alt = ns.make.client({
        IsControlKeyDown = function() error("boom") end,
        IsShiftKeyDown = function() return true end,
    }).modifiers()
    t.eq(ctrl, nil)
    t.eq(shift, true)
    t.eq(alt, nil)
end

return tests

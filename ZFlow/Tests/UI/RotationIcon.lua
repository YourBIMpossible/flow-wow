-- Tests for ZFlow/UI/RotationIcon.lua (WOW-ROTATION-ICON, G27 core): the
-- one icon that shows the rotation driver's suggestion, over the fake
-- client in a kernel, and the two client reads it stands on (client.icon,
-- client.spellTexture) over a made-up environment. Not tested in game.
local _, ns = ...

local I = ns.RotationIcon
local D = ns.RotationDriver
local tests = {}

local WRATH, MOONFIRE = 5176, 8921
local WRATH_TEX, MOONFIRE_TEX = 136006, 136096 -- test values, not client data
local CLASS = "TESTCLASS"

local function pack()
    return {
        spells = { Wrath = { evidence = "test" }, Moonfire = { evidence = "test" } },
        lists = { default = {
            { spell = "Moonfire", target = true, reason = "Moonfire" },
            { spell = "Wrath", target = true, reason = "Wrath" },
        } },
        keys = { none = { key = "Wrath" } },
    }
end

-- What must never be called: the icon shows, it presses nothing.
local FORBIDDEN = { "SetAttribute", "SetBinding", "SetBindingClick", "SetOverrideBinding",
    "SetOverrideBindingClick", "CastSpell", "CastSpellByName", "CastSpellByID", "UseAction",
    "RunMacroText", "SecureCmdOptionParse", "RegisterStateDriver", "glow", "panel", "arrow" }

-- opts: saved (account table), enabled (the setting on after login),
-- predecessor, noFrames, noMoveKey, noTextures, before(c) (last word on
-- the client before the kernel is made), rowTaken (another row holds the
-- icon's place).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSpellId("Wrath", WRATH)
    c.setSpellId("Moonfire", MOONFIRE)
    c.setSpell(WRATH, { known = true, usable = true, noPower = false })
    c.setSpell(MOONFIRE, { known = true, usable = true, noPower = false })
    c.setSpellCooldown(WRATH, false)
    c.setSpellCooldown(MOONFIRE, false)
    c.setInRange(WRATH, true)
    c.setInRange(MOONFIRE, true)
    if not opts.noTextures then
        c.setSpellTexture(WRATH, WRATH_TEX)
        c.setSpellTexture(MOONFIRE, MOONFIRE_TEX)
    end
    c.target = function() return { exists = true, hostile = true, dead = false } end
    c.setSaved(ns.id.accountDB, opts.saved or {})
    c.setSaved(ns.id.charDB, {})
    c.setDead(false)
    c.setClass(CLASS)
    c.setScreen(1024, 768)
    if opts.predecessor then c.setLoaded(ns.id.predecessor, true) end
    if opts.noFrames then c.setFrames(false) end
    if opts.noMoveKey then c.setMoveKey(false) end
    local calls = {}
    for _, name in ipairs(FORBIDDEN) do
        c[name] = function() calls[name] = (calls[name] or 0) + 1 end
    end
    if opts.before then opts.before(c) end
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    if opts.rowTaken then
        k:Setting({ key = "other.icon", scope = "account", type = "table", label = "Other", path = I.PATH })
    end
    D.Declare(k, { [CLASS] = pack() })
    local api = I.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    k.settings:set(D.SETTING, opts.enabled == true)
    return k, c, api, calls
end

local function tick(c) c.advance(D.EVERY + 0.05, 1) end
local function suggest(k, spell)
    k.bus:emit(D.EVENT, { suggestion = spell and { spell = spell } or nil, trace = {} })
end
local function saved(c)
    local layout = c.saved(ns.id.accountDB).layout
    return type(layout) == "table" and layout.rotationIcon or nil
end
local function count(calls)
    local n = 0
    for _, v in pairs(calls) do n = n + v end
    return n
end

-- ------------------------------------------------------------ what it says
tests["rotation icon: names"] = function(t)
    t.eq(I.NAME, "rotationIcon")
    t.eq(I.PATH, "layout.rotationIcon")
    t.eq(type(I.SIZE), "number")
    t.eq(ns.Nav.ClampPoint(I.DEFAULT_POINT), I.DEFAULT_POINT, "the default is a usable point")
end

tests["rotation icon: the spell of a view"] = function(t)
    t.eq(I.Spell(nil), nil, "no view")
    t.eq(I.Spell(false), nil)
    t.eq(I.Spell({ trace = {} }), nil, "nothing suggested")
    t.eq(I.Spell({ suggestion = {} }), nil, "a suggestion with no spell")
    t.eq(I.Spell({ suggestion = { spell = "" } }), nil)
    t.eq(I.Spell({ suggestion = { spell = 5176 } }), nil, "a name, not a number")
    t.eq(I.Spell({ suggestion = { spell = "Wrath" } }), "Wrath")
    t.eq(I.Spell({ suggestion = { spell = "Wrath" }, stale = true }), "Wrath",
        "a kept view is still the driver's view")
end

-- ------------------------------------------------------------------ shown
tests["rotation icon: made hidden at the default point, nothing saved, while the setting is off"] = function(t)
    local k, c, api = start()
    t.eq(#c.icons, 1, "one icon")
    t.eq(c.icons[1].spec, { name = ns.id.framePrefix .. "RotationIcon", size = I.SIZE })
    t.ok(api.handle() == c.icons[1])
    t.eq(c.icons[1].shown, false)
    t.eq(c.icons[1].point, I.DEFAULT_POINT)
    c.advance(2, 10)
    t.eq(c.icons[1].shown, false, "the setting is off: nothing is suggested, nothing shown")
    t.eq(saved(c), nil)
    t.eq(k.problems:count(), 0)
    t.eq(k:ModuleState(I.NAME), "started")
end

tests["rotation icon: the driver's suggestion is shown with that spell's texture"] = function(t)
    local k, c = start({ enabled = true })
    tick(c)
    local h = c.icons[1]
    t.eq(h.shown, true)
    t.eq(h.texture, MOONFIRE_TEX, "Moonfire is first in the list")
    c.setSpellCooldown(MOONFIRE, true)
    tick(c)
    t.eq(h.shown, true)
    t.eq(h.texture, WRATH_TEX, "the next suggestion, the next texture")
    t.eq(k.problems:count(), 0)
end

tests["rotation icon: switching the setting off hides it"] = function(t)
    local k, c = start({ enabled = true })
    tick(c)
    t.eq(c.icons[1].shown, true)
    t.eq(k.settings:set(D.SETTING, false), true)
    tick(c)
    t.eq(c.icons[1].shown, false)
    c.advance(2, 10)
    t.eq(c.icons[1].shown, false)
end

tests["rotation icon: a view that arrives while the setting is off shows nothing"] = function(t)
    local k, c = start()
    suggest(k, "Wrath")
    t.eq(c.icons[1].shown, false)
    t.eq(c.icons[1].texture, nil)
end

tests["rotation icon: nothing suggested hides it"] = function(t)
    local k, c = start({ enabled = true })
    suggest(k, "Wrath")
    t.eq(c.icons[1].shown, true)
    t.eq(c.icons[1].texture, WRATH_TEX)
    suggest(k, nil)
    t.eq(c.icons[1].shown, false, "a view with no suggestion")
    suggest(k, "Wrath")
    t.eq(c.icons[1].shown, true)
    k.bus:emit(D.EVENT, nil)
    t.eq(c.icons[1].shown, false, "no view")
end

-- ------------------------------------------------- unknown stays unknown
tests["rotation icon: a spell the client gives no id for is not shown"] = function(t)
    local k, c = start({ enabled = true })
    suggest(k, "Starfire")
    t.eq(c.icons[1].shown, false)
    t.eq(c.icons[1].texture, nil, "no texture is made up")
end

tests["rotation icon: a spell the client gives no texture for is not shown"] = function(t)
    local k, c = start({ enabled = true, noTextures = true })
    suggest(k, "Wrath")
    t.eq(c.icons[1].shown, false)
    t.eq(c.icons[1].texture, nil, "no texture is made up")
    c.setSpellTexture(WRATH, WRATH_TEX)
    suggest(k, "Wrath")
    t.eq(c.icons[1].shown, true, "shown once the client says")
    c.setSpellTexture(WRATH, nil)
    suggest(k, "Wrath")
    t.eq(c.icons[1].shown, false, "and hidden again: an old texture is not a new answer")
end

tests["rotation icon: a client with no texture read shows nothing and raises nothing"] = function(t)
    local k, c = start({ enabled = true, before = function(c) c.spellTexture = nil end })
    suggest(k, "Wrath")
    t.eq(c.icons[1].shown, false)
    t.eq(k:ModuleState(I.NAME), "started")
end

tests["rotation icon: a texture read that raises shows nothing"] = function(t)
    local k, c = start({ enabled = true,
        before = function(c) c.spellTexture = function() error("no") end end })
    suggest(k, "Wrath")
    t.eq(c.icons[1].shown, false)
    t.eq(k:ModuleState(I.NAME), "started", "the module is not switched off for it")
end

-- ----------------------------------------------------------------- frames
tests["rotation icon: a client that makes no icon is one problem and nothing else"] = function(t)
    local k, c, api = start({ enabled = true, noFrames = true })
    t.eq(#c.icons, 0)
    t.eq(api.handle(), nil)
    t.eq(k.problems:count("rotationIcon"), 1)
    suggest(k, "Wrath")
    tick(c)
    t.eq(k.problems:count("rotationIcon"), 1, "said once")
    t.eq(k:ModuleState(I.NAME), "started")
    t.eq(saved(c), nil)
end

tests["rotation icon: a client with no icon maker at all is handled the same"] = function(t)
    local k, _, api = start({ enabled = true, before = function(c) c.icon = nil end })
    t.eq(api.handle(), nil)
    suggest(k, "Wrath")
    t.eq(k.problems:count("rotationIcon"), 1)
    t.eq(k:ModuleState(I.NAME), "started")
end

tests["rotation icon: nothing is made beside the predecessor"] = function(t)
    local _, c, api = start({ predecessor = true })
    t.eq(#c.icons, 0)
    t.eq(api.handle(), nil)
end

tests["rotation icon: switched off, the icon is hidden and stays hidden"] = function(t)
    local k, c = start({ enabled = true })
    suggest(k, "Wrath")
    t.eq(c.icons[1].shown, true)
    k:SwitchOff(I.NAME, "test")
    t.eq(c.icons[1].shown, false)
    suggest(k, "Wrath")
    t.eq(c.icons[1].shown, false)
end

tests["rotation icon: it presses nothing, glows nothing and makes no other frame"] = function(t)
    local k, c, _, calls = start({ enabled = true })
    tick(c)
    suggest(k, "Wrath")
    c.icons[1].drag({ "CENTER", "CENTER", 10, 10 })
    k.settings:set(D.SETTING, false)
    tick(c)
    t.eq(count(calls), 0)
    t.eq(#c.icons, 1)
end

-- ------------------------------------------------------------------- place
tests["rotation icon: a reset of all keeps the icon's place; the row's own reset clears it (D6)"] = function(t)
    local k, c = start()
    t.eq(k.settings:row(I.SETTING).keepOnResetAll, true)
    c.icons[1].drag({ "CENTER", "CENTER", 30, -40 })
    k.settings:reset("all")
    t.eq(k.settings:get(I.SETTING), { point = { "CENTER", "CENTER", 30, -40 } }, "kept by a reset of all")
    k.settings:reset(I.SETTING)
    t.eq(k.settings:get(I.SETTING), nil, "the place reset is its own path")
    t.eq(k.problems:count(), 0)
end

tests["rotation icon: a Ctrl drag saves the point in the layout and the next start restores it"] = function(t)
    local k, c = start()
    c.icons[1].drag({ "CENTER", "CENTER", 30, -40 })
    t.eq(saved(c), { point = { "CENTER", "CENTER", 30, -40 } })
    t.eq(k.settings:get(I.SETTING), { point = { "CENTER", "CENTER", 30, -40 } }, "through the setting row")
    t.eq(k.settings:row(I.SETTING).path, I.PATH)
    t.eq(k.settings:row(I.SETTING).scope, "account")
    t.eq(k.problems:count(), 0)
    local _, c2 = start({ saved = c.saved(ns.id.accountDB) })
    t.eq(c2.icons[1].point, { "CENTER", "CENTER", 30, -40 })
end

tests["rotation icon: without Ctrl nothing moves and nothing is saved"] = function(t)
    local _, c = start({ noMoveKey = true })
    c.icons[1].drag({ "CENTER", "CENTER", 30, -40 })
    t.eq(c.icons[1].point, I.DEFAULT_POINT)
    t.eq(saved(c), nil)
end

tests["rotation icon: a drag off the screen is brought back onto it"] = function(t)
    local _, c = start()
    local far = { "BOTTOMLEFT", "BOTTOMLEFT", 5000, 5000 }
    local want = ns.Nav.ClampPoint(far, I.SIZE, 1024, 768)
    c.icons[1].drag(far)
    t.eq(saved(c), { point = want })
    t.eq(c.icons[1].point, want)
    t.ok(want[3] < 5000 and want[4] < 5000, "moved back")
end

tests["rotation icon: a saved point that is no point gives the default"] = function(t)
    local _, c = start({ saved = { layout = { rotationIcon = { point = { "CENTER", 4 } } } } })
    t.eq(c.icons[1].point, I.DEFAULT_POINT)
    _, c = start({ saved = { layout = { rotationIcon = "there" } } })
    t.eq(c.icons[1].point, I.DEFAULT_POINT)
end

tests["rotation icon: a refused row is one problem; the icon still shows, its place is not kept"] = function(t)
    local k, c = start({ enabled = true, rowTaken = true })
    t.eq(k.problems:count("rotationIcon"), 1)
    suggest(k, "Wrath")
    t.eq(c.icons[1].shown, true)
    c.icons[1].drag({ "CENTER", "CENTER", 30, -40 })
    t.eq(saved(c), nil)
    t.eq(k.problems:count("rotationIcon"), 1, "said once")
    t.eq(k:ModuleState(I.NAME), "started")
end

-- ------------------------------------------------ pet battles and vehicles
-- The client has no read for either today. Where one exists it is used;
-- where none does, the case is not handled.
tests["rotation icon: hidden in a pet battle or a vehicle where the client can say so"] = function(t)
    for _, name in ipairs({ "petBattle", "vehicle" }) do
        local answer = true
        local k, c = start({ enabled = true,
            before = function(c) c[name] = function() return answer end end })
        suggest(k, "Wrath")
        t.eq(c.icons[1].shown, false, name .. ": in one")
        answer = false
        suggest(k, "Wrath")
        t.eq(c.icons[1].shown, true, name .. ": not in one")
        answer = nil
        suggest(k, "Wrath")
        t.eq(c.icons[1].shown, true, name .. ": the client did not say, which is not a yes")
    end
end

tests["rotation icon: a read that is not known shows the icon; a read that raises is no answer"] = function(t)
    local k, c = start({ enabled = true })
    t.eq(c.petBattle(), nil, "the pet battle read starts not known")
    t.eq(c.vehicle(), nil, "so does the vehicle read")
    suggest(k, "Wrath")
    t.eq(c.icons[1].shown, true)
    k, c = start({ enabled = true, before = function(c) c.vehicle = function() error("no") end end })
    suggest(k, "Wrath")
    t.eq(c.icons[1].shown, true)
    t.eq(k:ModuleState(I.NAME), "started")
end

tests["rotation icon: it follows the fake's own pet battle and vehicle reads"] = function(t)
    local k, c = start({ enabled = true })
    suggest(k, "Wrath")
    t.eq(c.icons[1].shown, true)
    c.setPetBattle(true)
    suggest(k, "Wrath")
    t.eq(c.icons[1].shown, false, "in a pet battle")
    c.setPetBattle(false)
    suggest(k, "Wrath")
    t.eq(c.icons[1].shown, true, "out of it")
    c.setVehicle(true)
    suggest(k, "Wrath")
    t.eq(c.icons[1].shown, false, "in a vehicle")
    c.setVehicle(nil)
    suggest(k, "Wrath")
    t.eq(c.icons[1].shown, true, "not known shows it")
end

-- ------------------------------------------------------- out of range (187)
tests["187 rotation icon: the mark of a view is far only for the out of range step"] = function(t)
    t.eq(I.Mark(nil), nil, "no view")
    t.eq(I.Mark({ trace = {} }), nil, "nothing suggested")
    t.eq(I.Mark({ suggestion = { spell = "Wrath", step = "list" } }), nil, "a ready spell")
    t.eq(I.Mark({ suggestion = { spell = "Wrath" } }), nil, "no step")
    t.eq(I.Mark({ suggestion = { spell = "Wrath", step = "farOpener", label = "Out of range" } }), "far")
end

tests["187 rotation icon: an out of range suggestion is shown marked, a ready one plain"] = function(t)
    local k, c = start({ enabled = true })
    local h = c.icons[1]
    k.bus:emit(D.EVENT, { suggestion = { spell = "Wrath", step = "farOpener", label = "Out of range" }, trace = {} })
    t.eq(h.shown, true, "still shown: it is the next spell")
    t.eq(h.texture, WRATH_TEX)
    t.eq(h.marked, "far", "but marked out of range")
    k.bus:emit(D.EVENT, { suggestion = { spell = "Wrath", step = "list" }, trace = {} })
    t.eq(h.shown, true)
    t.eq(h.marked, nil, "in range again: the mark is gone")
    k.bus:emit(D.EVENT, { suggestion = { spell = "Wrath", step = "farOpener" }, trace = {} })
    suggest(k, nil)
    t.eq(h.shown, false)
    t.eq(h.marked, nil, "hidden: no mark is left behind")
    t.eq(k.problems:count(), 0)
end

tests["187 rotation icon: the driver's own out of range step marks the icon"] = function(t)
    local k, c = start({ enabled = true })
    c.setInRange(WRATH, false)
    c.setInRange(MOONFIRE, false)
    tick(c)
    local h = c.icons[1]
    t.eq(h.shown, true)
    t.eq(h.marked, "far", "nothing in range: the next spell is shown marked")
    c.setInRange(WRATH, true)
    c.setInRange(MOONFIRE, true)
    tick(c)
    t.eq(h.marked, nil, "in range: plain")
    t.eq(k.problems:count(), 0)
end

tests["187 rotation icon: an icon with no mark call still shows the spell"] = function(t)
    local k, c = start({ enabled = true, before = function(fc)
        local make = fc.icon
        fc.icon = function(spec)
            local h = make(spec)
            if h then h.mark = nil end
            return h
        end
    end })
    k.bus:emit(D.EVENT, { suggestion = { spell = "Wrath", step = "farOpener" }, trace = {} })
    t.eq(c.icons[1].shown, true)
    t.eq(k.problems:count(), 0)
end

-- ------------------------------------------------------ the client's reads
-- A made-up environment: frames record what they are told.
local function gameEnv(opts)
    opts = opts or {}
    local env = { frames = {}, textures = {}, UIParent = {}, ctrl = opts.ctrl }
    function env.IsControlKeyDown() return env.ctrl end
    function env.CreateFrame(kind, name, parent)
        local f = { kind = kind, name = name, parent = parent, scripts = {}, calls = {}, shown = true }
        function f:SetScript(script, fn) self.scripts[script] = fn end
        function f:Hide() self.shown = false end
        function f:Show() self.shown = true end
        function f:SetSize(w, h) self.w, self.h = w, h end
        function f:StartMoving() self.calls.StartMoving = (self.calls.StartMoving or 0) + 1 end
        function f:StopMovingOrSizing() self.calls.Stop = (self.calls.Stop or 0) + 1 end
        function f:ClearAllPoints() self.point = nil end
        function f:SetPoint(a, _, r, x, y) self.point = { a, r, x, y } end
        function f:GetPoint() return "CENTER", env.UIParent, "CENTER", 10, 20 end
        if not opts.noTexture then
            function f:CreateTexture()
                local tex = {}
                function tex:SetTexture(v) self.value = v end
                function tex:SetAllPoints() self.all = true end
                function tex:SetVertexColor(r, g, b) self.color = { r, g, b } end
                env.textures[#env.textures + 1] = tex
                return tex
            end
        end
        env.frames[#env.frames + 1] = f
        return f
    end
    return env
end

tests["client icon: a hidden frame of the asked size with one texture"] = function(t)
    local env = gameEnv()
    local h = ns.make.client(env).icon({ name = "TestIcon", size = 40 })
    t.ok(h ~= nil)
    local f = env.frames[#env.frames]
    t.eq(f.name, "TestIcon")
    t.eq(f.shown, false)
    t.eq({ f.w, f.h }, { 40, 40 })
    t.eq(#env.textures, 1)
    t.eq(h.setTexture(1234), true)
    t.eq(env.textures[1].value, 1234)
    h.show(true)
    t.eq(f.shown, true)
    h.show(false)
    t.eq(f.shown, false)
    h.place({ "TOPLEFT", "TOPLEFT", 5, -6 })
    t.eq(f.point, { "TOPLEFT", "TOPLEFT", 5, -6 })
end

tests["187 client icon: the far mark tints the picture red, no mark puts the plain colour back"] = function(t)
    local env = gameEnv()
    local h = ns.make.client(env).icon({ name = "TestIcon" })
    t.eq(h.mark("far"), true)
    t.eq(env.textures[1].color, { 1, 0.3, 0.3 })
    t.eq(h.mark(nil), true)
    t.eq(env.textures[1].color, { 1, 1, 1 })
    local bare = gameEnv({ noTexture = true })
    t.eq(ns.make.client(bare).icon({ name = "TestIcon" }).mark("far"), false, "no picture, no mark")
end

tests["client icon: no frame, no icon; no texture, setTexture says so"] = function(t)
    t.eq(ns.make.client({}).icon({ name = "TestIcon" }), nil)
    local env = gameEnv({ noTexture = true })
    local h = ns.make.client(env).icon({ name = "TestIcon" })
    t.ok(h ~= nil)
    t.eq(h.setTexture(1234), false)
    t.eq(h.setTexture(nil), false)
end

tests["client icon: it moves only while Ctrl is held"] = function(t)
    local env = gameEnv({ ctrl = false })
    local h = ns.make.client(env).icon({ name = "TestIcon" })
    local f = env.frames[#env.frames]
    local at, n = nil, 0
    h.onMoved(function(point) at, n = point, n + 1 end)
    f.scripts.OnDragStart()
    f.scripts.OnDragStop()
    t.eq(f.calls.StartMoving, nil, "a plain drag starts nothing")
    t.eq(n, 0)
    env.ctrl = nil
    f.scripts.OnDragStart()
    f.scripts.OnDragStop()
    t.eq(n, 0, "a client that cannot say starts no drag")
    env.ctrl = true
    f.scripts.OnDragStart()
    f.scripts.OnDragStop()
    t.eq(f.calls.StartMoving, 1)
    t.eq(f.calls.Stop, 1)
    t.eq(n, 1)
    t.eq(at, { "CENTER", "CENTER", 10, 20 })
end

tests["client icon: a failing moved callback is handed to its caller"] = function(t)
    local env = gameEnv({ ctrl = true })
    local h = ns.make.client(env).icon({ name = "TestIcon" })
    local f = env.frames[#env.frames]
    local got
    h.onMoved(function() error("boom") end, function(err) got = err end)
    f.scripts.OnDragStart()
    t.eq(pcall(f.scripts.OnDragStop), true)
    t.eq(type(got) == "string" and got:find("boom", 1, true) ~= nil, true)
end

tests["client spellTexture: the client's answer, or nil"] = function(t)
    t.eq(ns.make.client({}).spellTexture(5176), nil, "no read at all")
    local c = ns.make.client({ C_Spell = {
        GetSpellTexture = function(id) return id == 5176 and 136006 or nil end } })
    t.eq(c.spellTexture(5176), 136006)
    t.eq(c.spellTexture(1), nil, "the client gave nothing")
    t.eq(c.spellTexture(nil), nil)
    t.eq(c.spellTexture("Wrath"), nil, "by id only")
    c = ns.make.client({ GetSpellTexture = function() return "Interface\\Icons\\Spell_Nature_AbolishMagic" end })
    t.eq(c.spellTexture(5176), "Interface\\Icons\\Spell_Nature_AbolishMagic", "the older read answers")
    c = ns.make.client({ C_Spell = { GetSpellTexture = function() error("no") end },
        GetSpellTexture = function() return 7 end })
    t.eq(c.spellTexture(5176), 7, "the older read when the newer one fails")
    c = ns.make.client({ GetSpellTexture = function() return "" end })
    t.eq(c.spellTexture(5176), nil, "an empty name is no texture")
    c = ns.make.client({ GetSpellTexture = function() return 0 end })
    t.eq(c.spellTexture(5176), nil)
    c = ns.make.client({ GetSpellTexture = function() return true end })
    t.eq(c.spellTexture(5176), nil)
end

tests["fake icon: it stands in for the client's"] = function(t)
    local c = ns.make.fakeClient()
    local h = c.icon({ name = "X" })
    t.ok(c.icons[1] == h)
    t.eq(h.shown, false)
    t.eq(h.setTexture(5), true)
    t.eq(h.texture, 5)
    t.eq(h.setTexture(nil), false)
    t.eq(h.texture, nil)
    local got
    h.onMoved(function() error("boom") end, function(err) got = err end)
    h.drag({ "CENTER", "CENTER", 1, 2 })
    t.eq(type(got), "string")
    c.setFrames(false)
    t.eq(c.icon({}), nil)
    c.setSpellTexture(5176, 9)
    t.eq(c.spellTexture(5176), 9)
    t.eq(c.spellTexture(1), nil)
end

-- Lead section 294: an icon that is on but has nothing to suggest in a
-- fight says so once, instead of staying away without a word.
local function saidEmpty(c)
    local n = 0
    for _, line in ipairs(c.printed) do
        if tostring(line):find(I.EMPTY, 1, true) then n = n + 1 end
    end
    return n
end

-- A view of the driver with the class pack read and no suggestion: the
-- one case the line is for (Twin review 17:11, F1).
local function nothing(k)
    k.bus:emit(D.EVENT, { pack = true, trace = {} })
end
local ENEMY = { exists = true, hostile = true, dead = false }

tests["rotation icon 294: on, in a fight, an enemy targeted, nothing to suggest: one line, once a session"] = function(t)
    local k, c = start({ enabled = true })
    c.setCombat(true)
    c.setTarget(ENEMY)
    nothing(k)
    t.eq(c.icons[1].shown, false, "nothing to show")
    t.eq(saidEmpty(c), 1, "one line")
    t.ok(tostring(c.printed[#c.printed]):find(ns.id.title, 1, true) == 1, "from the add-on, by its title")
    nothing(k)
    nothing(k)
    t.eq(saidEmpty(c), 1, "not again")
end

tests["rotation icon 294: out of a fight, or switched off, nothing to suggest says nothing"] = function(t)
    local k, c = start({ enabled = true })
    c.setCombat(false)
    c.setTarget(ENEMY)
    nothing(k)
    t.eq(saidEmpty(c), 0, "out of a fight")
    local k2, c2 = start()
    c2.setCombat(true)
    c2.setTarget(ENEMY)
    nothing(k2)
    t.eq(saidEmpty(c2), 0, "switched off")
end

-- Twin review 17:11, F1: a missing read is not "nothing to suggest".
tests["rotation icon 294 F1: no line when a texture read failed or no enemy is targeted yet"] = function(t)
    local k, c = start({ enabled = true })
    c.setCombat(true)
    k.bus:emit(D.EVENT, { pack = true, suggestion = { spell = "No Such Spell" }, trace = {} })
    suggest(k, "No Such Spell")
    t.eq(c.icons[1].shown, false, "a suggestion whose picture was not read: hidden")
    t.eq(saidEmpty(c), 0, "a suggestion exists: not the empty line")
    c.setTarget({ exists = false })
    nothing(k)
    t.eq(saidEmpty(c), 0, "no enemy targeted yet: not the empty line")
    k.bus:emit(D.EVENT, { trace = {} })
    t.eq(saidEmpty(c), 0, "the class pack not read: not the empty line")
    c.setTarget(ENEMY)
    k.bus:emit(D.EVENT, { pack = true, trace = {}, stale = true })
    t.eq(saidEmpty(c), 0, "an earlier reading kept after a failed read: not the empty line")
    nothing(k)
    t.eq(saidEmpty(c), 1, "the line is still there for the real case")
end

return tests

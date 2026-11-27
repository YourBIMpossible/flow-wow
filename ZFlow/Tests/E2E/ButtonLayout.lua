-- Tests for Rotation/Cooldowns.lua (button spec Step 2, §624): the
-- Cooldowns display — one small face per spell the rotation offers
-- that is on its own cooldown, the dark sweep and the seconds, in
-- Separate mode standing in its own place with its own grip, in
-- Combined mode one face on the Flow button's right. Over the fake
-- client; the driver is stood in for by a module of its name that
-- declares its rows, and views are handed in on its bus event.
-- Fails before the module: ns.Cooldowns is absent.
local _, ns = ...

local tests = {}

local CD = ns.Cooldowns
local D = ns.RotationDriver

local SMITE, RENEW, FORT = 585, 139, 1243
local IDS = { ["Smite"] = SMITE, ["Renew"] = RENEW, ["Power Word: Fortitude"] = FORT }

local function has(t)
    local ok = type(CD) == "table" and type(CD.Text) == "function" and type(CD.Order) == "function"
        and type(CD.Tracked) == "function" and type(CD.Declare) == "function"
    t.ok(ok, "ns.Cooldowns answers Text, Order, Tracked and Declare")
    return ok
end

-- A view whose plan offers Smite on the plain key and Renew on ctrl.
local function view()
    return { pack = true, snapshot = nil, attrs = { ok = true, button = {
        { attr = "type", value = "spell" }, { attr = "spell", value = "Smite" },
        { attr = "*type-ctrl", value = "spell" }, { attr = "*spell-ctrl", value = "Renew" },
    } } }
end

-- A client stub for the pure reads: spell ids by name, nothing else.
local function stubClient()
    return {
        spellId = function(name) return IDS[name] end,
        class = function() return "PRIEST" end,
    }
end

tests["cooldowns text: the bare seconds, upstream's way"] = function(t)
    if not has(t) then return end
    t.eq(CD.Text(nil), nil)
    t.eq(CD.Text(0), nil)
    t.eq(CD.Text(1.5), nil, "at the threshold nothing is said, so the global cooldown never flashes a number")
    t.eq(CD.Text(4.3), "4.3")
    t.eq(CD.Text(9.9), "9.9")
    t.eq(CD.Text(30), "30")
    t.eq(CD.Text(60), "1m")
    t.eq(CD.Text(61), "2m", "minutes round up")
    t.eq(CD.Text(119), "2m")
end

tests["cooldowns mode: combined only when the setting says so"] = function(t)
    if not has(t) then return end
    t.eq(CD.ModeOf("combined"), "combined")
    t.eq(CD.ModeOf("separate"), "separate")
    t.eq(CD.ModeOf(nil), "separate", "no row yet (Step 1 is another lane's): Separate, the default")
    t.eq(CD.ModeOf("both"), "separate")
end

tests["cooldowns order: soonest ready first, the Flow spell wins a tie"] = function(t)
    if not has(t) then return end
    local rows = CD.Order({
        { kind = "spell", id = 1, left = 30 },
        { kind = "spell", id = 2, left = 5 },
        { kind = "item", id = 3, left = 12 },
    })
    t.eq({ rows[1].id, rows[2].id, rows[3].id }, { 2, 3, 1 })
    local tie = CD.Order({
        { kind = "spell", id = 1, left = 10 },
        { kind = "spell", id = 2, left = 10, first = true },
        { kind = "spell", id = 3, left = 10 },
    })
    t.eq({ tie[1].id, tie[2].id, tie[3].id }, { 2, 1, 3 }, "the Flow button's spell first, then plan order")
end

tests["cooldowns tracked: the plan's spells, once each, the Flow spell first"] = function(t)
    if not has(t) then return end
    local rows = CD.Tracked(stubClient(), view())
    t.eq(#rows, 2)
    t.eq(rows[1], { kind = "spell", id = SMITE, first = true })
    t.eq(rows[2], { kind = "spell", id = RENEW })
    local none = CD.Tracked(stubClient(), { pack = true, attrs = { ok = false, button = {} } })
    t.eq(none, {}, "a view that is not a plan view tracks nothing")
    local itemView = { pack = true, attrs = { ok = true, button = {
        { attr = "type", value = "item" }, { attr = "item", value = "item:1234" },
    } } }
    local items = CD.Tracked(stubClient(), itemView)
    t.eq(items, { { kind = "item", id = 1234, first = true } }, "an item slot reads its number out of item:ID")
end

-- The module on a kernel of its own, the driver stood in for.
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, {})
    c.setClass("PRIEST"); c.setLevel(20); c.setDead(false); c.setCombat(false)
    c.setScreen(1000, 768)
    for name, id in pairs(IDS) do
        c.setSpellId(name, id)
        c.setSpell(id, { known = true, usable = true })
        c.setSpellCooldown(id, false)
        c.setSpellTexture(id, "tex:" .. name)
    end
    if opts.before then opts.before(c) end
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    k:Module({ name = D.NAME, settings = {
        { key = D.SETTING, scope = "account", type = "bool", default = false, label = "Rotation", group = "combat" },
        { key = "flowButton.layout", scope = "account", type = "choice", choices = { "separate", "combined" },
          default = "separate", label = "Button layout", group = "combat" },
    } })
    CD.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    k.settings:set(D.SETTING, true)
    if opts.mode then k.settings:set("flowButton.layout", opts.mode) end
    c.advance(2, 20)
    return c, k
end

local function offer(c, k)
    k.bus:emit(D.EVENT, view())
    c.advance(2, 20)
end

tests["cooldowns: a spell on its own cooldown gets a face, a sweep and its seconds"] = function(t)
    if not has(t) then return end
    local c, k = boot()
    c.setSpellCooldown(SMITE, true); c.setSpellCooldownLeft(SMITE, 30)
    offer(c, k)
    t.eq(#c.cooldownFaces, 1, "one face made")
    local face = c.cooldownFaces[1]
    t.eq(face.shown, true)
    t.eq(face.sweep, { kind = "spell", id = SMITE })
    t.eq(face.seconds, "30")
    t.eq(face.texture, "tex:Smite")
    t.eq(face.point, CD.DEFAULT_POINT, "the group stands at its default place")
    t.eq(face.size, CD.SIZE)
    t.eq(face.name, ns.id.framePrefix .. CD.FACE_NAME, "the face's name is built from the frame prefix, like the buttons'")
end

tests["cooldowns: ready, global-only and unread spells get no face; the group still stands"] = function(t)
    if not has(t) then return end
    local c, k = boot()
    offer(c, k)
    t.eq(#c.cooldownFaces, 1, "the group's own face only")
    local face = c.cooldownFaces[1]
    t.eq(face.shown, true, "shown, so the group can be found and dragged")
    t.eq(face.sweep, nil)
    t.eq(face.seconds, nil)
    t.eq(face.texture, nil)
end

tests["cooldowns: faces stand soonest first, in a row from the group's place"] = function(t)
    if not has(t) then return end
    local c, k = boot()
    c.setSpellCooldown(SMITE, true); c.setSpellCooldownLeft(SMITE, 30)
    c.setSpellCooldown(RENEW, true); c.setSpellCooldownLeft(RENEW, 5)
    offer(c, k)
    t.eq(#c.cooldownFaces, 2)
    t.eq(c.cooldownFaces[1].sweep, { kind = "spell", id = RENEW }, "Renew (5s) stands first")
    t.eq(c.cooldownFaces[1].seconds, "5.0")
    t.eq(c.cooldownFaces[2].sweep, { kind = "spell", id = SMITE })
    local p = CD.DEFAULT_POINT
    t.eq(c.cooldownFaces[2].point, { p[1], p[2], p[3] + CD.SIZE + CD.GAP, p[4] }, "the next face one face and a gap to the right")
end

tests["cooldowns: an item on cooldown gets the sweep and no seconds"] = function(t)
    if not has(t) then return end
    local c, k = boot()
    c.setItemCooldown(1234, 45)
    k.bus:emit(D.EVENT, { pack = true, attrs = { ok = true, button = {
        { attr = "type", value = "item" }, { attr = "item", value = "item:1234" },
    } } })
    c.advance(2, 20)
    t.eq(#c.cooldownFaces, 1)
    t.eq(c.cooldownFaces[1].sweep, { kind = "item", id = 1234 })
    t.eq(c.cooldownFaces[1].seconds, nil, "items are never given seconds")
end

tests["cooldowns: the group stands where it was saved"] = function(t)
    if not has(t) then return end
    local saved = { layout = { cooldowns = { frame = { "TOPLEFT", "TOPLEFT", 40, -40 } } } }
    local c, k = boot({ account = saved })
    offer(c, k)
    t.eq(c.cooldownFaces[1].point, { "TOPLEFT", "TOPLEFT", 40, -40 })
end

tests["cooldowns combined: one big face on the Flow button's right, the soonest spell"] = function(t)
    if not has(t) then return end
    local flowName = ns.id.framePrefix .. "FlowButton"
    local c, k = boot({ mode = "combined", before = function(cc)
        cc.setFrameRect(flowName, { left = 400, bottom = 200, width = 52, height = 52 })
    end })
    c.setSpellCooldown(SMITE, true); c.setSpellCooldownLeft(SMITE, 30)
    c.setSpellCooldown(RENEW, true); c.setSpellCooldownLeft(RENEW, 5)
    offer(c, k)
    local big
    for i = 1, #c.cooldownFaces do
        if c.cooldownFaces[i].size == CD.COMBINED_SIZE then big = c.cooldownFaces[i] end
    end
    t.ok(big ~= nil, "the combined face was made at the Flow button's size")
    if big then
        t.eq(big.shown, true)
        t.eq(big.sweep, { kind = "spell", id = RENEW }, "the soonest spell only")
        t.eq(big.seconds, "5.0")
        t.ok(big.anchor ~= nil and big.anchor.to == flowName, "anchored to the Flow button")
    end
end

tests["cooldowns combined: no Flow frame to anchor to, no face; the frame there, the face stands"] = function(t)
    if not has(t) then return end
    local flowName = ns.id.framePrefix .. "FlowButton"
    local c, k = boot({ mode = "combined" })
    c.setSpellCooldown(SMITE, true); c.setSpellCooldownLeft(SMITE, 30)
    offer(c, k)
    local big
    for i = 1, #c.cooldownFaces do
        if c.cooldownFaces[i].size == CD.COMBINED_SIZE then big = c.cooldownFaces[i] end
    end
    t.ok(big ~= nil, "the combined face was made")
    if big then t.eq(big.shown, false, "no frame by that name: the anchor is refused and the face stays hidden") end
    c.setFrameRect(flowName, { left = 400, bottom = 200, width = 52, height = 52 })
    c.advance(2, 20)
    if big then
        t.eq(big.shown, true, "the frame there: the face stands on the next tick")
        t.eq(big.sweep, { kind = "spell", id = SMITE })
        t.ok(big.anchor ~= nil and big.anchor.to == flowName, "anchored to the Flow button")
    end
end

return tests

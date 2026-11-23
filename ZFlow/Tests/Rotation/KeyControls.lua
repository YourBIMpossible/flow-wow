local _, ns = ...
-- N41 and S23 (P-KEYS slice B), pure: the key controls shaping the
-- rotation key's plan (Rotation/KeyControls.lua), the plan's per-slot units
-- on the button (Rotation/Cast.lua), and the click-casting check's one line
-- (UI/ClickCheck.lua). Hand-made plans, snapshots and clients; made-up
-- cast times, keys and actions. Not tested in game.
local tests = {}

local function KC() return ns.KeyControls end
local function CC() return ns.ClickCheck end

local PACK = { heals = { self = { "Holy Light", "Flash of Light" }, hots = {} } }
local ALL = { shift = true, alt = true, ctrl = true, actions = true }
local ACTION = "CLICK ZFlowRotationKey:LeftButton"
local OTHER = "CLICK SomeClickCastButton:LeftButton"   -- made up

local function snap()
    return { spells = {
        ["Holy Light"] = { known = true, usable = true, castMs = 2500 },
        ["Flash of Light"] = { known = true, usable = true, castMs = 1500 },
    } }
end

local function plan()
    return { condition = "0", altItem = 9201,
        states = { [0] = { key = "Judgement", ctrl = "Exorcism", alt = "Divine Protection", more = "Hammer of Wrath" } } }
end

local function with(over)
    local out = {}
    for k, v in pairs(ALL) do out[k] = v end
    for k, v in pairs(over or {}) do out[k] = v end
    return out
end

local function ready(t)
    local ok = type(KC()) == "table" and type(KC().Shape) == "function"
    t.ok(ok, "Rotation/KeyControls.lua gives KC.Shape")
    return ok
end

local function unitOf(p, slot)
    if type(p) ~= "table" or type(p.units) ~= "table" then return nil end
    return p.units[slot]
end

tests["key controls: Shift on puts your fastest direct heal on Shift + key, on you"] = function(t)
    if not ready(t) then return end
    local p = KC().Shape(plan(), with(), snap(), PACK, false)
    t.eq(p.states[0].shift, "Flash of Light")
    t.eq(unitOf(p, "shift"), "player")
end

tests["key controls: Shift off leaves Shift + key not set"] = function(t)
    if not ready(t) then return end
    local p = KC().Shape(plan(), with({ shift = false }), snap(), PACK, false)
    t.eq(p.states[0].shift, nil)
    t.eq(unitOf(p, "shift"), nil)
end

tests["key controls: Shift on with no heal known sets nothing on Shift"] = function(t)
    if not ready(t) then return end
    local p = KC().Shape(plan(), with(), { spells = {} }, PACK, false)
    t.eq(p.states[0].shift, nil)
end

tests["key controls: Shift goes on every form's row"] = function(t)
    if not ready(t) then return end
    local p0 = plan()
    p0.states[1] = { key = "Judgement" }
    local p = KC().Shape(p0, with(), snap(), PACK, false)
    t.eq(p.states[0].shift, "Flash of Light")
    t.eq(p.states[1].shift, "Flash of Light")
end

tests["key controls: Alt on keeps the healing item; Alt off leaves Alt + key not set"] = function(t)
    if not ready(t) then return end
    local on = KC().Shape(plan(), with(), snap(), PACK, false)
    t.eq(on.altItem, 9201)
    local off = KC().Shape(plan(), with({ alt = false }), snap(), PACK, false)
    t.eq(off.altItem, nil)
    t.eq(off.states[0].alt, nil)
end

tests["key controls: Ctrl on a friend you target casts your quick heal on its group token"] = function(t)
    if not ready(t) then return end
    local p = KC().Shape(plan(), with(), snap(), PACK, "party2")
    t.eq(p.states[0].ctrl, "Flash of Light")
    t.eq(unitOf(p, "ctrl"), "party2", "a stable token, never the target")
    local q = KC().Shape(plan(), with(), snap(), PACK, true)
    t.eq(q.states[0].ctrl, "Exorcism", "a friend with no group token: the pack's spell")
    t.eq(unitOf(q, "ctrl"), nil)
end

tests["key controls: the friend you target is read as its group token"] = function(t)
    if not ready(t) then return end
    local c = ns.make.fakeClient()
    t.eq(KC().FriendUnit(c), nil, "nothing known")
    c.setGuid("target", "Player-2")
    c.setUnitCare("target", { exists = true, friend = true, isSelf = false, dead = false, hurt = true })
    t.eq(KC().FriendUnit(c), nil, "not in your group: left out")
    c.setParty({ { unit = "party1", guid = "Player-1" }, { unit = "party2", guid = "Player-2" } })
    c.setUnitCare("party2", { exists = true, friend = true, isSelf = false, dead = false, hurt = true })
    t.eq(KC().FriendUnit(c), "party2")
    c.setUnitCare("party2", { exists = true, friend = false, dead = false, hurt = true })
    t.eq(KC().FriendUnit(c), nil, "a foe")
    c.setUnitCare("party2", { exists = true, friend = true, isSelf = false, dead = false, hurt = true })
    c.setUnitCareFails(true)
    t.eq(KC().FriendUnit(c), nil, "the read raised")
    c.setUnitCareFails(false)
    t.eq(KC().FriendUnit(c), "party2", "the read recovers")
    t.eq(KC().FriendUnit(nil), nil)
end

tests["key controls: Ctrl on with no friend targeted keeps the pack's spell"] = function(t)
    if not ready(t) then return end
    local p = KC().Shape(plan(), with(), snap(), PACK, false)
    t.eq(p.states[0].ctrl, "Exorcism")
    t.eq(unitOf(p, "ctrl"), nil)
end

tests["key controls: Ctrl off leaves Ctrl + key not set, friend or not"] = function(t)
    if not ready(t) then return end
    local p = KC().Shape(plan(), with({ ctrl = false }), snap(), PACK, true)
    t.eq(p.states[0].ctrl, nil)
    t.eq(unitOf(p, "ctrl"), nil)
end

tests["key controls: no controls or no plan: the plan is given back as it was"] = function(t)
    if not ready(t) then return end
    local p = KC().Shape(plan(), nil, snap(), PACK, true)
    t.eq(p.states[0].ctrl, "Exorcism")
    t.eq(p.altItem, 9201)
    t.eq(KC().Shape(nil, with(), snap(), PACK, true), nil)
end

tests["key controls: a friend is a target that exists, is friendly and is not you; a failed read is no"] = function(t)
    if not ready(t) or type(KC().Friend) ~= "function" then t.ok(false, "KC.Friend") return end
    local function client(row, fails)
        return { unitCare = function(unit)
            if fails then error("read failed (test)") end
            if unit == "target" then return row end
            return nil
        end }
    end
    t.eq(KC().Friend(client({ exists = true, friend = true, isSelf = false })), true)
    t.eq(KC().Friend(client({ exists = true, friend = false })), false)
    t.eq(KC().Friend(client({ exists = true, friend = true, isSelf = true })), false)
    t.eq(KC().Friend(client({ exists = false })), false)
    t.eq(KC().Friend(client(nil, true)), false)
    t.eq(KC().Friend({}), false)
end

tests["key controls: the key does gathering off: the gathering step is kept off the key, shown still"] = function(t)
    if not ready(t) or type(KC().Gate) ~= "function" then t.ok(false, "KC.Gate") return end
    local s = { spell = "Find Minerals", kind = "buff", unit = "player", step = "track" }
    local gated = KC().Gate(s, with({ actions = false }))
    t.eq(gated.spell, "Find Minerals")
    t.eq(gated.keyOff, true)
    local kept = KC().Gate({ spell = "Find Minerals", step = "track" }, with())
    t.eq(kept.keyOff, nil)
    local other = KC().Gate({ spell = "Judgement", step = "list" }, with({ actions = false }))
    t.eq(other.keyOff, nil)
    t.eq(KC().Gate(nil, with({ actions = false })), nil)
end

tests["key controls: fishing is a hook with no action yet"] = function(t)
    if not ready(t) or type(KC().Fishing) ~= "function" then t.ok(false, "KC.Fishing") return end
    t.eq(KC().Fishing({ fishingPole = true }), nil)
end

tests["cast: a plan's units go on the modifier slots; no unit is the target"] = function(t)
    local C = ns.cast
    local p = plan()
    p.states[0].shift = "Flash of Light"
    p.units = { shift = "player" }
    local a = C.Attributes(nil, p, nil, false, 0)
    local got = {}
    for _, r in ipairs(a.button or {}) do got[r.attr] = r.value end
    t.eq(got["*spell-shift"], "Flash of Light")
    t.eq(got["*unit-shift"], "player")
    t.eq(got["*unit-ctrl"], "target")
    t.eq(unitOf(a.plan, "shift"), "player")
end

tests["cast: a plan that changes only a slot's unit is a changed plan"] = function(t)
    local C = ns.cast
    local before = plan()
    local after = plan()
    after.units = { ctrl = "player" }
    local applied = C.Apply(before, nil, false).plan
    t.eq(C.Apply(after, applied, false).changed, true)
    t.eq(C.Apply(before, applied, false).changed, false)
end

local function cc(t)
    local ok = type(CC()) == "table" and type(CC().Read) == "function" and type(CC().Line) == "function"
    t.ok(ok, "UI/ClickCheck.lua gives CC.Read and CC.Line")
    return ok
end

local function client(opts)
    opts = opts or {}
    return {
        addonLoaded = function(name) return opts.loaded ~= nil and opts.loaded[name] == true end,
        bindingKeys = function(action)
            if opts.keysFail then error("keys read failed (test)") end
            return (opts.keys or {})[action]
        end,
        bindingOverride = function(key)
            if opts.overFail then error("override read failed (test)") end
            return (opts.over or {})[key]
        end,
    }
end

local SLOTS = { { label = "Rotation key", action = ACTION }, { label = "Rotation second key", action = ACTION } }

tests["click check: nothing loaded and nothing taken: no line"] = function(t)
    if not cc(t) then return end
    local read = CC().Read(client({ keys = { [ACTION] = { "F" } }, over = { F = ACTION } }), SLOTS)
    t.eq(CC().Line(read, "ZFlow"), nil)
end

tests["click check: another binding wins on your key: the line names the key and what it does"] = function(t)
    if not cc(t) then return end
    local read = CC().Read(client({ keys = { [ACTION] = { "F" } }, over = { F = OTHER } }), SLOTS)
    local line = CC().Line(read, "ZFlow")
    t.ok(type(line) == "string", "a line")
    if type(line) ~= "string" then return end
    t.ok(line:find("Rotation key", 1, true) ~= nil, line)
    t.ok(line:find(" F ", 1, true) ~= nil, line)
    t.ok(line:find(OTHER, 1, true) ~= nil, line)
    t.eq(#read.taken, 1, "one key, read once for both slots")
end

tests["click check: a click-cast add-on loaded is named, with or without a taken key"] = function(t)
    if not cc(t) then return end
    local loaded = { Clique = true }
    local soft = CC().Line(CC().Read(client({ loaded = loaded, keys = { [ACTION] = { "F" } }, over = { F = ACTION } }), SLOTS), "ZFlow")
    t.ok(type(soft) == "string" and soft:find("Clique", 1, true) ~= nil, tostring(soft))
    local hard = CC().Line(CC().Read(client({ loaded = loaded, keys = { [ACTION] = { "F" } }, over = { F = OTHER } }), SLOTS), "ZFlow")
    t.ok(type(hard) == "string" and hard:find("Clique", 1, true) ~= nil and hard:find(OTHER, 1, true) ~= nil, tostring(hard))
end

tests["click check: a read that fails is not a conflict, and raises nothing"] = function(t)
    if not cc(t) then return end
    local read = CC().Read(client({ keys = { [ACTION] = { "F" } }, overFail = true }), SLOTS)
    t.eq(#read.taken, 0)
    t.eq(read.unknown, true)
    t.eq(CC().Line(read, "ZFlow"), nil)
    local read2 = CC().Read(client({ keysFail = true }), SLOTS)
    t.eq(#read2.taken, 0)
    t.eq(CC().Line(CC().Read(nil, SLOTS), "ZFlow"), nil)
end

tests["click check: a key held only for the session is checked too"] = function(t)
    if not cc(t) then return end
    local slots = { { label = "Rotation key", action = ACTION, override = "G" } }
    local read = CC().Read(client({ keys = { [ACTION] = {} }, over = { G = OTHER } }), slots)
    t.eq(#read.taken, 1)
    local first = read.taken[1] or {}
    t.eq(first.key, "G")
end

return tests

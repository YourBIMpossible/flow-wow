-- The client side of S8 (nameplate threat and combo points; lead section
-- 178, WoW/from-lazy/RESEARCH-S8.md): the real client over a hand-built
-- environment, then ClientFake's own versions. Look only: nothing clicks,
-- targets, casts or writes a CVar.
--   c.plates(fn) -> cancel           fn("added" | "removed", "nameplateN")
--   c.canAttack(unit)                true / false / nil; target and nameplateN only
--   c.grouped()                      true / false / nil
--   c.plateLabel(unit) -> h          h.show, h.text, h.color, h.alpha,
--                                    h.threat() -> "shown", status, pct
--                                                | "hidden", status | nil
--   c.comboBar() -> h                h.hang(unit), h.sections(n), h.fill(n),
--                                    h.color, h.show,
--                                    h.fillFromGame() -> "shown", n | "hidden" | nil
--   c.combo() -> { points, max }     plain values only
--   c.comboColor() -> { r, g, b }    or nil
-- The display sink (option A): a value the game hides is written onto the
-- client's own widget and never handed back; the caller hears only
-- "hidden". Unknown stays unknown: a failed, missing, odd or secret answer
-- is nil, never 0. Every name and number is made up. Not tested in game.
local _, ns = ...

local tests = {}

-- Stands in for a value the client hides.
local SECRET = setmetatable({}, { __tostring = function() return "(a hidden value)" end })

-- issecretvalue that refuses nil, as the client's does. SECRET is hidden,
-- and anything `also(v)` says is.
local function secretEnv(env, also)
    env.issecretvalue = function(v)
        if v == nil then error("issecretvalue: nil") end
        return rawequal(v, SECRET) or (also ~= nil and also(v) == true) or false
    end
    return env
end

-- A made-up widget: every method called on it is kept in o.calls as
-- { name, arg1, ..., n = number of args } and its name in env.log.
-- env.refuse[name] = true makes that method raise.
local function widget(env, kind, parent)
    local o = { kind = kind, parent = parent, calls = {}, scripts = {}, isShown = true }
    local own = {
        GetFrameLevel = function() return 5 end,
        IsShown = function(self) return self.isShown end,
        Show = function(self) self.isShown = true end,
        Hide = function(self) self.isShown = false end,
        SetScript = function(self, what, fn) self.scripts[what] = fn end,
        CreateTexture = function(self)
            local r = widget(env, "Texture", self)
            env.regions[#env.regions + 1] = r
            return r
        end,
        CreateFontString = function(self)
            local r = widget(env, "FontString", self)
            env.regions[#env.regions + 1] = r
            return r
        end,
        GetStatusBarTexture = function(self)
            local tex = rawget(self, "tex")
            if not tex then
                tex = widget(env, "Texture", self)
                rawset(self, "tex", tex)
            end
            return tex
        end,
    }
    return setmetatable(o, { __index = function(_, name)
        if type(name) ~= "string" or not name:find("^[A-Z]") then return nil end
        return function(self, ...)
            local call = { name, ... }
            call.n = select("#", ...)
            self.calls[#self.calls + 1] = call
            env.log[#env.log + 1] = name
            if env.refuse and env.refuse[name] then error("refused: " .. name) end
            local fn = own[name]
            if fn then return fn(self, ...) end
        end
    end })
end

-- An environment that makes frames: env.made lists every frame made (with
-- .kind and .parent), env.templates the templates asked for, env.regions
-- every texture and font string.
local function frameEnv(extra)
    local env = { log = {}, made = {}, regions = {}, templates = {}, UIParent = { isParent = true } }
    function env.CreateFrame(kind, _, parent, template)
        if template ~= nil then env.templates[#env.templates + 1] = template end
        local f = widget(env, kind, parent)
        env.made[#env.made + 1] = f
        return f
    end
    for key, v in pairs(extra or {}) do env[key] = v end
    return env
end

-- Plays a client event to every frame that listens for events.
local function fire(env, event, ...)
    for _, f in ipairs(env.made) do
        local fn = f.scripts.OnEvent
        if fn then fn(f, event, ...) end
    end
end

-- A nameplate frame. parts nil: no UnitFrame; else { power = shown?,
-- health = shown? } (a part left out is not there), read when asked.
local function plateFrame(parts)
    local p = {}
    function p.GetFrameLevel() return 7 end
    if parts then
        local uf = {}
        if parts.power ~= nil then uf.powerBar = { IsShown = function() return parts.power end } end
        if parts.health ~= nil then uf.healthBar = { IsShown = function() return parts.health end } end
        p.UnitFrame = uf
    end
    return p
end

local function hasCall(o, name, ...)
    local want = { ... }
    local n = select("#", ...)
    for _, call in ipairs(o.calls) do
        if call[1] == name and call.n == n then
            local same = true
            for i = 1, n do
                if not rawequal(call[i + 1], want[i]) then same = false end
            end
            if same then return true end
        end
    end
    return false
end

local function countCalls(o, name)
    local n = 0
    for _, call in ipairs(o.calls) do
        if call[1] == name then n = n + 1 end
    end
    return n
end

local function madeUnder(env, parent, kind)
    local out = {}
    for _, f in ipairs(env.made) do
        if f.parent == parent and (kind == nil or f.kind == kind) then out[#out + 1] = f end
    end
    return out
end

local function regionOf(env, kind, parent)
    for _, r in ipairs(env.regions) do
        if r.kind == kind and r.parent == parent then return r end
    end
    return nil
end

-- ------------------------------------------------------------ plates
tests["c.plates: nameplate units come and go; nothing else is told"] = function(t)
    local env = secretEnv(frameEnv())
    local c = ns.make.client(env)
    local got = {}
    local cancel = c.plates(function(what, unit) got[#got + 1] = what .. " " .. unit end)
    t.eq(type(cancel), "function")
    c.plates(function() error("a listener that breaks") end)
    fire(env, "NAME_PLATE_UNIT_ADDED", "nameplate3")
    fire(env, "NAME_PLATE_UNIT_REMOVED", "nameplate3")
    for _, odd in ipairs({ "target", "party1", "nameplate", "Nameplate2", "nameplate2x", 7 }) do
        fire(env, "NAME_PLATE_UNIT_ADDED", odd)
    end
    fire(env, "NAME_PLATE_UNIT_ADDED")
    fire(env, "NAME_PLATE_UNIT_ADDED", SECRET)
    t.eq(got, { "added nameplate3", "removed nameplate3" })
    cancel()
    fire(env, "NAME_PLATE_UNIT_ADDED", "nameplate4")
    t.eq(#got, 2, "cancelled: told no more")
    t.eq(c.plates("not a function"), nil)
end

-- ------------------------------------------------------------ canAttack, grouped
tests["c.canAttack: only your target and enemy nameplates, asked as the player"] = function(t)
    local asked = {}
    local env = secretEnv({ UnitCanAttack = function(a, b)
        asked[#asked + 1] = a .. ">" .. b
        return b == "nameplate1"
    end })
    local c = ns.make.client(env)
    t.eq(c.canAttack("nameplate1"), true)
    t.eq(c.canAttack("nameplate2"), false)
    t.eq(c.canAttack("target"), false)
    for _, unit in ipairs({ "party1", "raid2", "focus", "mouseover", "pet", "player", "nameplate", "", 3 }) do
        t.eq(c.canAttack(unit), nil, "not asked about " .. tostring(unit))
    end
    t.eq(c.canAttack(nil), nil)
    t.eq(asked, { "player>nameplate1", "player>nameplate2", "player>target" })
end

tests["c.canAttack: not known when the client will not say"] = function(t)
    t.eq(ns.make.client({}).canAttack("nameplate1"), nil, "no call")
    t.eq(ns.make.client({ UnitCanAttack = function() error("no") end }).canAttack("nameplate1"), nil, "raised")
    t.eq(ns.make.client({ UnitCanAttack = function() return 1 end }).canAttack("nameplate1"), nil, "no yes or no")
    t.eq(ns.make.client({ UnitCanAttack = function() return nil end }).canAttack("nameplate1"), nil, "no answer")
    local secret = secretEnv({ UnitCanAttack = function() return SECRET end })
    t.eq(ns.make.client(secret).canAttack("nameplate1"), nil, "a secret answer")
end

tests["c.grouped: in a group or not, else not known"] = function(t)
    t.eq(ns.make.client(secretEnv({ IsInGroup = function() return true end })).grouped(), true)
    t.eq(ns.make.client(secretEnv({ IsInGroup = function() return false end })).grouped(), false)
    t.eq(ns.make.client({}).grouped(), nil, "no call")
    t.eq(ns.make.client({ IsInGroup = function() error("no") end }).grouped(), nil, "raised")
    t.eq(ns.make.client({ IsInGroup = function() return 1 end }).grouped(), nil, "no yes or no")
    t.eq(ns.make.client(secretEnv({ IsInGroup = function() return SECRET end })).grouped(), nil, "secret")
end

-- ------------------------------------------------------------ plate label
local function labelEnv(threat)
    local plate = plateFrame()
    local env = secretEnv(frameEnv({ STANDARD_TEXT_FONT = "Fonts\\Test.ttf" }))
    env.C_NamePlate = { GetNamePlateForUnit = function(unit) return unit == "nameplate1" and plate or nil end }
    env.threatAsked = {}
    if threat then
        env.UnitDetailedThreatSituation = function(a, b)
            env.threatAsked[#env.threatAsked + 1] = a .. ">" .. b
            return threat()
        end
    end
    return env, plate
end

tests["c.plateLabel: a small text at the right of the plate, made once for each plate"] = function(t)
    local env, plate = labelEnv()
    local c = ns.make.client(env)
    t.eq(c.plateLabel("target"), nil, "only a nameplate unit")
    t.eq(c.plateLabel("nameplate2"), nil, "no plate for it on screen")
    local h = c.plateLabel("nameplate1")
    t.ok(type(h) == "table", "a label")
    if type(h) ~= "table" then return end
    local frames = madeUnder(env, plate)
    t.eq(#frames, 1, "one frame, on the plate")
    local f = frames[1]
    t.eq(f.isShown, false, "hidden until shown")
    t.ok(hasCall(f, "SetPoint", "LEFT", plate, "RIGHT", 2, 12), "at the plate's right, raised 12")
    t.ok(hasCall(f, "SetFrameLevel", 17), "above the plate")
    local fs = regionOf(env, "FontString", f)
    t.ok(fs ~= nil and hasCall(fs, "SetFont", "Fonts\\Test.ttf", 10, "OUTLINE"), "the game's font, 10, outlined")
    t.ok(type(c.plateLabel("nameplate1")) == "table")
    t.eq(#madeUnder(env, plate), 1, "the same plate: the same frame")
    h.text("85%")
    h.color(1, 0.9, 0.2)
    h.alpha(0.5)
    h.show(true)
    t.ok(hasCall(fs, "SetText", "85%"))
    t.ok(hasCall(fs, "SetTextColor", 1, 0.9, 0.2))
    t.ok(hasCall(fs, "SetAlpha", 0.5))
    t.eq(f.isShown, true)
    h.show(false)
    t.eq(f.isShown, false)
    t.eq(ns.make.client({}).plateLabel("nameplate1"), nil, "no nameplate read")
end

tests["c.plateLabel threat: a plain share is handed back and not drawn"] = function(t)
    local answer = { true, 3, 80, 85.4, 1000 }
    local env = labelEnv(function() return unpack(answer, 1, 5) end)
    local c = ns.make.client(env)
    local h = c.plateLabel("nameplate1")
    t.eq({ h.threat() }, { "shown", 3, 85.4 }, "the raw share first")
    t.eq(env.threatAsked, { "player>nameplate1" }, "your own threat on that plate's unit")
    local fs = regionOf(env, "FontString", madeUnder(env, env.C_NamePlate.GetNamePlateForUnit("nameplate1"))[1])
    t.eq(countCalls(fs, "SetText") + countCalls(fs, "SetFormattedText"), 0, "a plain share is the caller's to draw")
    answer = { false, 1, 60, nil, nil }
    t.eq({ h.threat() }, { "shown", 1, 60 }, "no raw share: the scaled one")
    answer = { false, 7, 50, 50 }
    t.eq({ h.threat() }, { "shown", nil, 50 }, "a status that is no 0..3 is not known")
    answer = { false, 1.5, 50, 50 }
    t.eq({ h.threat() }, { "shown", nil, 50 })
    answer = { false, SECRET, 40, 40 }
    t.eq({ h.threat() }, { "shown", nil, 40 }, "a hidden status is not known; the share is plain")
    answer = { true, 3, 120, 130 }
    t.eq({ h.threat() }, { "shown", 3, 130 }, "over a hundred is kept")
end

tests["c.plateLabel threat: not on its list, or not known: nil"] = function(t)
    local answer = {}
    local env = labelEnv(function() return unpack(answer, 1, 5) end)
    local h = ns.make.client(env).plateLabel("nameplate1")
    t.eq({ h.threat() }, {}, "on no threat list")
    answer = { false, 0, nil, nil }
    t.eq({ h.threat() }, {}, "no share")
    for _, pct in ipairs({ -1, 0 / 0, math.huge, "85", true }) do
        answer = { false, 1, pct, pct }
        t.eq({ h.threat() }, {}, "an odd share: " .. tostring(pct))
    end
    local raised = labelEnv(function() error("no") end)
    t.eq({ ns.make.client(raised).plateLabel("nameplate1").threat() }, {}, "raised")
    local none = labelEnv()
    t.eq({ ns.make.client(none).plateLabel("nameplate1").threat() }, {}, "no threat read")
end

tests["c.plateLabel threat: a hidden share is written by the client and never handed back"] = function(t)
    local env, plate = labelEnv(function() return true, 3, SECRET, SECRET, SECRET end)
    local h = ns.make.client(env).plateLabel("nameplate1")
    local got = { h.threat() }
    t.eq(got, { "hidden", 3 }, "the caller hears only that it is hidden, and the plain status")
    for i = 1, 5 do t.ok(not rawequal(got[i], SECRET), "the hidden share was handed back") end
    local fs = regionOf(env, "FontString", madeUnder(env, plate)[1])
    local passed
    for _, call in ipairs(fs.calls) do
        if call[1] == "SetFormattedText" then passed = call end
    end
    t.ok(passed ~= nil, "written with SetFormattedText")
    if passed then
        t.eq(passed[2], "%.0f%%")
        t.ok(rawequal(passed[3], SECRET), "the very value the game gave, untouched")
        t.eq(passed.n, 2)
    end
end

tests["c.plateLabel threat: with no SetFormattedText, the formatted text is set"] = function(t)
    local env = labelEnv(function() return false, 1, 87.4, 87.4 end)
    secretEnv(env, function(v) return v == 87.4 end)
    env.refuse = { SetFormattedText = true }
    local plate = env.C_NamePlate.GetNamePlateForUnit("nameplate1")
    local h = ns.make.client(env).plateLabel("nameplate1")
    t.eq({ h.threat() }, { "hidden", 1 })
    local fs = regionOf(env, "FontString", madeUnder(env, plate)[1])
    t.ok(hasCall(fs, "SetText", "87%"), "string.format of the hidden share")
end

-- ------------------------------------------------------------ combo bar
local function comboEnv(extra)
    local env = secretEnv(frameEnv(extra))
    env.plates = {}
    env.C_NamePlate = { GetNamePlateForUnit = function(unit) return env.plates[unit] end }
    return env
end

local function barParts(env)
    local f = madeUnder(env, env.UIParent, "Frame")[1]
    local bars = f and madeUnder(env, f, "StatusBar") or {}
    local fill = bars[1]
    local marks = {}
    for i = 2, #bars do marks[#marks + 1] = bars[i] end
    return f, fill, marks
end

tests["c.comboBar: made hidden under the screen, with its fill"] = function(t)
    local env = comboEnv()
    local bar = ns.make.client(env).comboBar()
    t.ok(type(bar) == "table", "a bar")
    local f, fill = barParts(env)
    t.ok(f ~= nil and fill ~= nil, "a frame and a status bar in it")
    if not (f and fill) then return end
    t.eq(f.isShown, false, "hidden until shown")
    t.ok(hasCall(f, "SetSize", 110, 5), "the fallback width and the height")
    t.ok(hasCall(fill, "SetStatusBarTexture", "Interface\\TargetingFrame\\UI-StatusBar"))
    bar.show(true)
    t.eq(f.isShown, true)
    bar.color(1, 0.5, 0)
    t.ok(hasCall(fill, "SetStatusBarColor", 1, 0.5, 0))
    t.eq(ns.make.client({}).comboBar(), nil, "no frames")
end

tests["c.comboBar hang: under the power bar, else the health bar, else the plate"] = function(t)
    local env = comboEnv()
    local parts = { power = true, health = true }
    local plate = plateFrame(parts)
    env.plates.target = plate
    local bar = ns.make.client(env).comboBar()
    local f = barParts(env)
    t.eq(bar.hang("target"), "power")
    t.ok(hasCall(f, "SetParent", plate), "on the plate")
    t.ok(hasCall(f, "SetPoint", "TOPLEFT", plate.UnitFrame.powerBar, "BOTTOMLEFT", 0, -2), "right under it")
    t.ok(hasCall(f, "SetPoint", "TOPRIGHT", plate.UnitFrame.powerBar, "BOTTOMRIGHT", 0, -2), "as wide")
    t.ok(hasCall(f, "SetFrameLevel", 17))
    t.eq(bar.hang("target"), "power")
    t.eq(countCalls(f, "SetParent"), 1, "the same part: not hung again")
    parts.power = false
    t.eq(bar.hang("target"), "health", "no power bar showing")
    t.ok(hasCall(f, "SetPoint", "TOPLEFT", plate.UnitFrame.healthBar, "BOTTOMLEFT", 0, -2))
    t.eq(countCalls(f, "SetParent"), 2)
    parts.health = false
    t.eq(bar.hang("target"), "plate", "neither shows")
    local bare = plateFrame()
    env.plates.target = bare
    t.eq(bar.hang("target"), "plate", "no unit frame")
    t.ok(hasCall(f, "SetPoint", "TOP", bare, "BOTTOM", 0, -3))
    env.plates.target = nil
    t.eq(bar.hang("target"), nil, "no plate for your target on screen")
    env.plates.nameplate2 = bare
    t.eq(bar.hang("nameplate2"), "plate")
    t.eq(bar.hang("party1"), nil, "not asked about another unit")
end

tests["c.comboBar sections: one divider less than the points, each at its point"] = function(t)
    local env = comboEnv()
    local bar = ns.make.client(env).comboBar()
    t.eq(bar.sections(5), true)
    local _, fill, marks = barParts(env)
    t.ok(hasCall(fill, "SetMinMaxValues", 0, 5))
    t.eq(#marks, 4, "four unseen bars")
    for i = 1, #marks do
        t.ok(hasCall(marks[i], "SetMinMaxValues", 0, 5) and hasCall(marks[i], "SetValue", i), "divider " .. i)
    end
    t.eq(bar.sections(3), true)
    _, _, marks = barParts(env)
    t.eq(#marks, 4, "none made again")
    t.eq({ marks[3].isShown, marks[4].isShown }, { false, false }, "the dividers past 3 put away")
    t.ok(hasCall(fill, "SetMinMaxValues", 0, 3))
    for _, odd in ipairs({ 0, 11, 2.5, "5" }) do
        t.eq(bar.sections(odd), false, "no sections: " .. tostring(odd))
    end
end

tests["c.comboBar fillFromGame: a plain count is handed back and not drawn"] = function(t)
    local asked = {}
    local points = 3
    local env = comboEnv({ GetComboPoints = function(a, b)
        asked[#asked + 1] = a .. ">" .. b
        return points
    end })
    local bar = ns.make.client(env).comboBar()
    local _, fill = barParts(env)
    t.eq({ bar.fillFromGame() }, { "shown", 3 })
    t.eq(asked, { "player>target" })
    t.eq(countCalls(fill, "SetValue"), 0, "the caller draws a plain count")
    points = 0
    t.eq({ bar.fillFromGame() }, { "shown", 0 }, "a 0 the game gave is a real 0")
    bar.fill(2)
    t.ok(hasCall(fill, "SetValue", 2))
    for _, odd in ipairs({ -1, 2.5, "3", 0 / 0 }) do
        points = odd
        t.eq({ bar.fillFromGame() }, {}, "an odd count: " .. tostring(odd))
    end
end

tests["c.comboBar fillFromGame: a hidden count goes straight onto the bar"] = function(t)
    local env = comboEnv({ GetComboPoints = function() return SECRET end })
    local bar = ns.make.client(env).comboBar()
    local _, fill = barParts(env)
    local got = { bar.fillFromGame() }
    t.eq(got, { "hidden" }, "the caller hears only that it is hidden")
    t.ok(not rawequal(got[2], SECRET))
    local passed
    for _, call in ipairs(fill.calls) do
        if call[1] == "SetValue" then passed = call end
    end
    t.ok(passed ~= nil and rawequal(passed[2], SECRET) and passed.n == 1, "StatusBar:SetValue with the very value")
end

tests["c.comboBar fillFromGame: UnitPower when GetComboPoints is missing or fails"] = function(t)
    local asked = {}
    local env = comboEnv({ UnitPower = function(unit, kind)
        asked[#asked + 1] = unit .. ">" .. tostring(kind)
        return 2
    end })
    local bar = ns.make.client(env).comboBar()
    t.eq({ bar.fillFromGame() }, { "shown", 2 })
    t.eq(asked, { "player>4" }, "combo points are power type 4")
    env.Enum = { PowerType = { ComboPoints = 14 } }
    env.GetComboPoints = function() error("no") end
    t.eq({ bar.fillFromGame() }, { "shown", 2 })
    t.eq(asked[2], "player>14", "the client's own number for it when it has one")
    env.GetComboPoints = function() return nil end
    t.eq({ bar.fillFromGame() }, { "shown", 2 }, "no answer: UnitPower")
    local none = comboEnv()
    t.eq({ ns.make.client(none).comboBar().fillFromGame() }, {}, "no read at all: not known, never 0")
end

tests["c.combo: plain count and most, else not known"] = function(t)
    local points, most = 3, 5
    local env = secretEnv({ GetComboPoints = function() return points end,
        UnitPowerMax = function(unit, kind) return unit == "player" and kind == 4 and most or nil end })
    local c = ns.make.client(env)
    t.eq(c.combo(), { points = 3, max = 5 })
    points = SECRET
    t.eq(c.combo(), { max = 5 }, "a hidden count is not known here")
    points, most = 2, 0
    t.eq(c.combo(), { points = 2 }, "a most of 0 is not known")
    most = SECRET
    t.eq(c.combo(), { points = 2 })
    t.eq(ns.make.client({}).combo(), {}, "no reads")
end

tests["c.comboColor: the game's combo point colour, else not known"] = function(t)
    local env = secretEnv({ PowerBarColor = { COMBO_POINTS = { r = 1, g = 0.5, b = 0 } } })
    t.eq(ns.make.client(env).comboColor(), { r = 1, g = 0.5, b = 0 })
    env.PowerBarColor = { [4] = { r = 0.2, g = 0.4, b = 0.6 } }
    t.eq(ns.make.client(env).comboColor(), { r = 0.2, g = 0.4, b = 0.6 }, "by power type")
    for _, odd in ipairs({ { r = 2, g = 0, b = 0 }, { r = "1", g = 0, b = 0 }, { r = 1, g = 0 }, { r = SECRET, g = 0, b = 0 } }) do
        env.PowerBarColor = { COMBO_POINTS = odd }
        t.eq(ns.make.client(env).comboColor(), nil)
    end
    env.PowerBarColor = "red"
    t.eq(ns.make.client(env).comboColor(), nil)
    t.eq(ns.make.client({}).comboColor(), nil)
end

-- ------------------------------------------------------------ look only
tests["S8 client: look only - no CVar written, no secure frame, only your units named"] = function(t)
    local units, cvars = {}, 0
    local function unitRead(answer)
        return function(...)
            for i = 1, select("#", ...) do
                local v = select(i, ...)
                if type(v) == "string" then units[#units + 1] = v end
            end
            return answer
        end
    end
    local env = comboEnv({
        SetCVar = function() cvars = cvars + 1 end,
        C_CVar = { SetCVar = function() cvars = cvars + 1 end },
        UnitCanAttack = unitRead(true), IsInGroup = unitRead(true),
        GetComboPoints = unitRead(SECRET), UnitPower = unitRead(2), UnitPowerMax = unitRead(5),
        PowerBarColor = { COMBO_POINTS = { r = 1, g = 1, b = 0 } },
    })
    env.UnitDetailedThreatSituation = function(...)
        unitRead()(...)
        return true, 3, SECRET, SECRET
    end
    env.plates.nameplate1 = plateFrame({ health = true })
    env.plates.target = env.plates.nameplate1
    local c = ns.make.client(env)
    c.plates(function() end)
    fire(env, "NAME_PLATE_UNIT_ADDED", "nameplate1")
    c.canAttack("nameplate1")
    c.canAttack("target")
    c.grouped()
    local h = c.plateLabel("nameplate1")
    h.threat()
    h.text("1%")
    h.show(true)
    local bar = c.comboBar()
    bar.hang("target")
    bar.sections(5)
    bar.fillFromGame()
    bar.fill(1)
    bar.show(true)
    c.combo()
    c.comboColor()
    t.eq(cvars, 0, "no CVar written")
    t.eq(env.templates, {}, "no frame from a template (no secure one)")
    for _, name in ipairs(env.log) do
        t.ok(name ~= "SetAttribute" and name ~= "RegisterForClicks" and name ~= "Click", "acts: " .. name)
    end
    for _, f in ipairs(env.made) do
        for _, call in ipairs(f.calls) do
            if call[1] == "EnableMouse" then t.eq(call[2], false, "takes no mouse") end
        end
    end
    for _, unit in ipairs(units) do
        t.ok(unit == "player" or unit == "target" or unit:find("^nameplate%d+$") ~= nil, "a unit named: " .. unit)
    end
    t.ok(#units >= 5, "the reads named their units")
end

-- ------------------------------------------------------------ fake
tests["fake client: the S8 reads are unknown until set"] = function(t)
    local c = ns.make.fakeClient()
    t.eq({ c.canAttack("nameplate1"), c.grouped(), c.comboColor() }, {})
    t.eq(c.combo(), {})
    t.eq(c.plateLabel("nameplate1"), nil, "no plate in view")
    c.setCanAttack("nameplate1", true)
    c.setCanAttack("target", false)
    c.setGrouped(false)
    c.setCombo(3, 5)
    c.setComboColor(1, 0.5, 0)
    t.eq({ c.canAttack("nameplate1"), c.canAttack("target"), c.grouped() }, { true, false, false })
    t.eq(c.canAttack("party1"), nil, "not asked about another unit")
    t.eq(c.combo(), { points = 3, max = 5 })
    t.eq(c.comboColor(), { r = 1, g = 0.5, b = 0 })
    c.setCombo(c.SECRET, 5)
    t.eq(c.combo(), { max = 5 }, "a hidden count is not known")
    c.setCanAttack("nameplate1", nil)
    c.setGrouped(nil)
    c.setComboColor(nil)
    t.eq({ c.canAttack("nameplate1"), c.grouped(), c.comboColor() }, {})
end

tests["fake client: plates come and go with the client's events"] = function(t)
    local c = ns.make.fakeClient()
    local got = {}
    local cancel = c.plates(function(what, unit) got[#got + 1] = what .. " " .. unit end)
    c.addPlate("nameplate1")
    c.fire("NAME_PLATE_UNIT_ADDED", "target")
    c.removePlate("nameplate1")
    t.eq(got, { "added nameplate1", "removed nameplate1" })
    cancel()
    c.addPlate("nameplate2")
    t.eq(#got, 2)
end

tests["fake client: a label records what was drawn; a hidden share is passed through"] = function(t)
    local c = ns.make.fakeClient()
    c.addPlate("nameplate1")
    local h = c.plateLabel("nameplate1")
    t.eq(c.plateLabels[1], h)
    t.eq({ h.unit, h.shown, h.reads }, { "nameplate1", false, 0 })
    t.eq({ h.threat() }, {}, "not set: not known")
    c.setThreat("nameplate1", 3, 85)
    t.eq({ h.threat() }, { "shown", 3, 85 })
    t.eq(h.says, nil, "a plain share is the caller's to draw")
    h.text("85%")
    h.color(1, 0.9, 0.2)
    h.alpha(0.4)
    h.show(true)
    t.eq({ h.says, h.rgb, h.alphaNow, h.shown, h.reads }, { "85%", { 1, 0.9, 0.2 }, 0.4, true, 2 })
    c.setThreat("nameplate1", 2, c.SECRET)
    t.eq({ h.threat() }, { "hidden", 2 })
    t.ok(rawequal(h.says, c.SECRET), "the hidden value, passed through")
    t.eq(h.format, "%.0f%%")
    c.setThreat("nameplate1", c.SECRET, c.SECRET)
    t.eq({ h.threat() }, { "hidden" }, "a hidden status is not known")
    c.setThreat("nameplate1")
    t.eq({ h.threat() }, {}, "on no list")
    t.eq(c.plateLabel("target"), nil, "only a nameplate unit")
    t.ok(not pcall(function() return c.SECRET + 1 end), "the stand-in cannot be added to")
    t.ok(not pcall(function() return c.SECRET < 1 end), "nor compared")
end

tests["fake client: a combo bar records where it hangs and what fills it"] = function(t)
    local c = ns.make.fakeClient()
    local bar = c.comboBar()
    t.eq(c.comboBars[1], bar)
    t.eq(bar.hang("target"), nil, "no plate for your target")
    c.setPlate("target", "power")
    t.eq(bar.hang("target"), "power")
    t.eq({ bar.hung, bar.under }, { "target", "power" })
    t.eq({ bar.fillFromGame() }, {}, "not known")
    c.setCombo(2, 5)
    t.eq({ bar.fillFromGame() }, { "shown", 2 })
    t.eq(bar.value, nil, "the caller draws a plain count")
    bar.sections(5)
    bar.fill(2)
    bar.color(1, 0.96, 0.41)
    bar.show(true)
    t.eq({ bar.max, bar.value, bar.rgb, bar.shown }, { 5, 2, { 1, 0.96, 0.41 }, true })
    c.setCombo(c.SECRET, 5)
    t.eq({ bar.fillFromGame() }, { "hidden" })
    t.ok(rawequal(bar.value, c.SECRET), "the hidden value, passed through")
    t.eq(bar.reads, 3)
    c.setFrames(false)
    t.eq(c.comboBar(), nil)
end

return tests

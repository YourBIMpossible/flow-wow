local _, ns = ...
-- Section 246 (N63-E): no Z-Flow secure button is ever a macro. On this
-- client a macro-type secure button does not act: the press arrives with
-- the right macro and nothing is cast (legacy Flow moved Attack off the
-- macro type for the same reason). The whole add-on, loaded on a fake
-- client: a paladin with the rotation and the key frame switched on, Well
-- Fed food and the healing items (N8) in the bags. Out of a fight the food
-- is suggested and the stone goes on Alt + the rotation key; an enemy
-- targeted, Attack is suggested; then a fight with the low-health warning
-- on. Every set any secure button was given is scanned (c.secureMacros),
-- and so is every row the driver worked out for the key (view.attrs).
-- Made-up items and tooltip lines; not tested in game. N8 stays PARTLY
-- until seen in the client.
local tests = {}

local D = ns.RotationDriver
local K = ns.KeyFrame
local IDS = {
    ["Devotion Aura"] = 465, ["Seal of Righteousness"] = 21084, ["Blessing of Might"] = 19740,
    ["Attack"] = 6603, ["Judgement"] = 20271,
}
local SEALED = { ["Devotion Aura"] = true, ["Blessing of Might"] = 200, ["Seal of Righteousness"] = 25 }
local ENEMY = { exists = true, hostile = true, dead = false }

local STEW, STONE, POT = 9005, 9201, 9202 -- test values, not client data
local INFO = {
    [STEW] = { name = "Strength Stew", classID = 0, subclassID = 5 },
    [STONE] = { name = "Minor Healthstone", classID = 0, subclassID = 0, level = 10, minLevel = 0 },
    [POT] = { name = "Minor Healing Potion", classID = 0, subclassID = 1, level = 5, minLevel = 1 },
}
local LINES = {
    [STEW] = { "Strength Stew", "Use: If you spend at least 10 seconds eating you will become well fed and gain 10 Strength for 15 min." },
}

local function start(ids)
    ids = ids or IDS
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setClass("PALADIN"); c.setFaction("Alliance"); c.setLevel(10)
    c.setDead(false); c.setMounted(false); c.setOnTaxi(false); c.setFishingPole(false)
    c.setCombat(false); c.setLowHealth(false)
    for name, id in pairs(ids) do
        c.setSpellId(name, id)
        c.setSpell(id, { known = true, usable = true })
        c.setSpellCooldown(id, false)
        c.setSpellTexture(id, "tex:" .. name)
    end
    c.setBagItems({ { item = STEW, count = 2 }, { item = STONE, count = 1 }, { item = POT, count = 3 } })
    c.setItemInfo(INFO)
    for id, lines in pairs(LINES) do c.setItemLines(id, lines) end
    for id, info in pairs(INFO) do c.setItemTexture(id, "tex:" .. info.name) end
    c.setItemCooldown(STONE, 0); c.setItemCooldown(POT, 0)
    c.setPlayerBuffs(SEALED)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    addon.settings:set(D.SETTING, true)
    addon.settings:set(K.SETTING, true)
    c.advance(1, 5)
    return c, addon
end

local function view(addon)
    local use = addon.use(D.NAME)
    return type(use) == "table" and use.View() or nil
end

-- The key's own rows as the driver worked them out: attr -> value.
local function key(v)
    local out = {}
    for _, r in ipairs(type(v) == "table" and type(v.attrs) == "table" and v.attrs.button or {}) do
        out[r.attr] = r.value
    end
    return out
end

local function keyButton(c)
    for _, h in ipairs(c.secureButtons) do
        if tostring(h.spec and h.spec.name):find("RotationKey", 1, true) then return h end
    end
    return nil
end

-- A row that would make a button a macro, said in words; nil when none.
local function macroRow(attr, value)
    attr = tostring(attr)
    if attr:find("type", 1, true) and value == "macro" then return attr .. " = macro" end
    if attr:find("macrotext", 1, true) and value ~= nil then return attr .. " = " .. tostring(value) end
    if type(value) == "string" and value:sub(1, 1) == "/" then return attr .. " = " .. value end
    return nil
end

tests["no macro: rotation, key frame, food, Attack and the Alt item give no button the macro type"] = function(t)
    local c, addon = start()
    local seen = {}
    local function keep(v) if type(v) == "table" then seen[#seen + 1] = v end end

    -- Out of a fight, no target: the food on the key's rows, the stone on Alt.
    local v = view(addon)
    keep(v)
    local s = type(v) == "table" and v.suggestion or nil
    t.ok(type(s) == "table" and s.itemId == STEW, "the food is suggested: " .. tostring(s and (s.itemId or s.spell)))
    local k = key(v)
    t.eq(k.type, "item", "the food is the item type")
    t.eq(k.item, "item:" .. STEW, "the food by its id")
    t.eq(k.macrotext, nil, "no macro text")
    local h = keyButton(c)
    t.ok(h ~= nil, "the key frame made its button")
    t.eq(h and h.attrs["*type-alt"], "item", "Alt + the key: the item type")
    t.eq(h and h.attrs["*item-alt"], "item:" .. STONE, "Alt + the key: the stone")
    t.ok(h and h.attrs.type ~= "macro", "the key itself is no macro")
    t.eq(h and h.attrs.macrotext, nil, "and holds no macro text")

    -- An enemy targeted, not swinging: Attack.
    c.setTarget(ENEMY); c.setStealthed(false)
    c.setInRange(IDS["Attack"], true); c.setInRange(IDS["Judgement"], true)
    c.setCurrentSpell(IDS["Attack"], false); c.advance(1, 5)
    v = view(addon)
    keep(v)
    s = type(v) == "table" and v.suggestion or nil
    t.eq(s and s.spell, "Attack", "Attack is suggested")
    k = key(v)
    t.eq({ k.type, k.spell, k.unit, k.item, k.macrotext }, { "spell", "Judgement", nil, nil, nil },
        "Attack suggested: the key holds the fight spell (zflow-btn-pull-spell), a spell, not a macro")

    -- The fight, swinging, then the low-health warning on.
    c.setCurrentSpell(IDS["Attack"], true); c.setCombat(true); c.advance(1, 5)
    keep(view(addon))
    c.setLowHealth(true); c.advance(1, 5)
    keep(view(addon))
    c.setItemCooldown(STONE, 120); c.advance(1, 5)
    keep(view(addon))
    c.setCombat(false); c.setLowHealth(false); c.setTarget({ exists = false }); c.advance(2, 10)
    keep(view(addon))

    t.ok(#c.secureGiven > 0, "the buttons were set")
    for _, g in ipairs(c.secureMacros()) do
        t.ok(false, "a button was made a macro: " .. tostring(g.name) .. " " .. tostring(g.attr)
            .. " = " .. tostring(g.value))
    end
    for _, g in ipairs(c.secureGiven) do
        local bad = macroRow(g.attr, g.value)
        t.ok(bad == nil, "given to " .. tostring(g.name) .. ": " .. tostring(bad))
    end
    t.ok(#seen >= 3, "the driver's rows were read")
    for i, sv in ipairs(seen) do
        for _, r in ipairs(type(sv.attrs) == "table" and sv.attrs.button or {}) do
            local bad = macroRow(r.attr, r.value)
            t.ok(bad == nil, "view " .. i .. ": " .. tostring(bad))
        end
    end
end

-- Section 249 (CT-1): a client that names the swing "Auto Attack". The
-- suggestion says "Auto Attack"; the key's secure button is given the spell
-- "Attack", a name the client casts, never the suggested one.
tests["CT-1: an Auto Attack suggestion puts the spell Attack on the key button"] = function(t)
    local ids = {}
    for name, id in pairs(IDS) do ids[name] = id end
    ids["Attack"], ids["Auto Attack"] = nil, 6603
    local c, addon = start(ids)
    c.setTarget(ENEMY); c.setStealthed(false)
    c.setInRange(6603, true); c.setInRange(IDS["Judgement"], true)
    c.setCurrentSpell(6603, false); c.advance(1, 5)
    local v = view(addon)
    local s = type(v) == "table" and v.suggestion or nil
    t.eq(s and s.spell, "Auto Attack", "the suggestion names Auto Attack")
    local k = key(v)
    t.eq({ k.type, k.spell, k.unit }, { "spell", "Judgement", nil },
        "the driver's key rows: never the swing (zflow-btn-pull-spell), the fight spell")
    -- The key frame's button holds the key plan, not the live suggestion
    -- (Rotation/KeyFrame.lua). A plan slot named "Auto Attack", set on a
    -- secure button the fake client makes, is given the spell "Attack".
    local h = c.secureButton({ name = "ZFlowTestKey" })
    t.ok(type(h) == "table", "the fake client made a secure button")
    local kf = K.New({ button = h, lockdown = function() return false end })
    kf:want(ns.KeyPlan({ keys = { none = { key = "Auto Attack" } } }, {}))
    local st = kf:try()
    t.eq(st and st.state, "set", "the plan was set on the button")
    t.eq(h and h.attrs.type, "spell", "the button: the spell type")
    t.eq(h and h.attrs.spell, "Attack", "the button casts Attack")
    kf:want(ns.KeyPlan({ keys = { none = { key = "Judgement", ctrl = "Auto Attack" } } }, {}))
    st = kf:try()
    t.eq(st and st.state, "set", "the second plan was set")
    t.eq(h and h.attrs["*spell-ctrl"], "Attack", "Ctrl + the button casts Attack")
end

return tests

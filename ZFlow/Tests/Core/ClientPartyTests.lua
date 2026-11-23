-- P-PARTY: the group reads of the real client over a hand-built
-- environment, then ClientFake's twin. Read only: nothing is cast, targeted
-- or clicked. Every answer the client does not give, or gives as a secret,
-- is nil (not known), never false, 0 or "". Made-up names. Not seen in game.
--   c.party()                  -> { { unit, name, class, role, power, dead, connected }, ... } | nil
--   c.reach(spellId, unit)     -> true | false | nil   partyN only
--   c.unitDebuffTypes(unit)    -> { [type] = debuff name } | nil   player or partyN
local _, ns = ...

local tests = {}

local NAME = "Fennimore"   -- made up

-- One other player in the party, party1: a warrior, alive and online.
local function groupEnv(extra)
    local env = { asked = {} }
    local function note(fn, unit) env.asked[#env.asked + 1] = fn .. ":" .. tostring(unit) end
    env.UnitExists = function(unit) note("UnitExists", unit) return unit == "party1" end
    env.UnitName = function(unit) note("UnitName", unit) return NAME, nil end
    env.UnitClass = function(unit) return "Warrior", "WARRIOR", 1 end
    env.UnitGroupRolesAssigned = function() return "NONE" end
    env.UnitPowerType = function() return 1 end
    env.UnitIsDead = function() return false end
    env.UnitIsConnected = function() return true end
    for k, v in pairs(extra or {}) do env[k] = v end
    return env
end

-- Lead section 248 PP2-2: the realm (UnitName's second answer) and the
-- GUID, each left out when not known or secret.
tests["c.party 248: realm and GUID when the client gives them, never a secret"] = function(t)
    local secret = {}
    local env = groupEnv({ UnitName = function() return NAME, "Otherrealm" end,
        UnitGUID = function() return "Player-2-0000BBBB" end })
    local got = ns.make.client(env).party()
    t.eq(got and got[1] and { got[1].realm, got[1].guid }, { "Otherrealm", "Player-2-0000BBBB" })
    env = groupEnv({ issecretvalue = function(v) return v == secret end, UnitGUID = function() return secret end,
        UnitName = function() return NAME, "" end })
    got = ns.make.client(env).party()
    t.eq(got and got[1] and { got[1].name, got[1].realm, got[1].guid }, { NAME }, "secret GUID, empty realm: left out")
    t.ok((function()
        for _, n in ipairs(ns.Diag.NAMES) do if n == "UnitGUID" then return true end end
        return false
    end)(), "UnitGUID is in the capture's name list")
end

-- Item 19: a role read that raises leaves the role out (roster order), no error.
tests["c.party 19: the role read raises: no role, no error"] = function(t)
    local env = groupEnv({ UnitGroupRolesAssigned = function() error("x") end })
    local ok, got = pcall(ns.make.client(env).party)
    t.ok(ok, "no error")
    t.eq(got and got[1] and { got[1].unit, got[1].role }, { "party1" }, "the role left out")
end

tests["c.party: each other member, each field as the client gave it"] = function(t)
    local env = groupEnv()
    t.eq(ns.make.client(env).party(), {
        { unit = "party1", name = NAME, class = "WARRIOR", role = "NONE", power = 1, dead = false, connected = true },
    })
    for _, a in ipairs(env.asked) do
        local unit = a:match(":(.*)$")
        -- 243: raid1 is asked first, to tell a raid from a party.
        t.ok(unit:find("^party%d$") ~= nil or a == "UnitExists:raid1", "only party units are asked about: " .. a)
    end
end

tests["c.party: alone is an empty list; whether anyone is there not known is nil"] = function(t)
    t.eq(ns.make.client(groupEnv({ UnitExists = function() return false end })).party(), {}, "alone")
    t.eq(ns.make.client(groupEnv({ UnitExists = function() return nil end })).party(), nil, "no answer")
    t.eq(ns.make.client(groupEnv({ UnitExists = function() error("x") end })).party(), nil, "raised")
    t.eq(ns.make.client(groupEnv({ UnitExists = false })).party(), nil, "no such call")
end

tests["c.party: a field the client does not give is left out, never guessed"] = function(t)
    local env = groupEnv({ UnitName = function() error("x") end, UnitIsConnected = false,
        UnitIsDead = function() return nil end, UnitGroupRolesAssigned = false,
        UnitPowerType = function() return "rage" end })
    t.eq(ns.make.client(env).party(), { { unit = "party1", class = "WARRIOR" } })
    local secret = {}
    env = groupEnv({ issecretvalue = function(v) return v == secret end,
        UnitName = function() return secret end, UnitIsDead = function() return secret end })
    local got = ns.make.client(env).party()
    t.eq(got and got[1] and got[1].name, nil, "a secret name: not known")
    t.eq(got and got[1] and got[1].dead, nil, "a secret dead: not known")
end

tests["c.reach: C_Spell.IsSpellInRange with the party unit; anything else nil"] = function(t)
    local asked = {}
    local env = { C_Spell = { IsSpellInRange = function(id, unit) asked[#asked + 1] = unit return id == 1126 end } }
    local c = ns.make.client(env)
    t.eq(c.reach(1126, "party2"), true)
    t.eq(c.reach(467, "party2"), false)
    t.eq(asked, { "party2", "party2" })
    t.eq(c.reach(1126, "target"), nil, "not a party unit: not asked")
    t.eq(c.reach(1126, "player"), nil, "not a party unit: not asked")
    t.eq(c.reach("Thorns", "party1"), nil, "not an id")
    t.eq(#asked, 2, "nothing more asked")
    env.C_Spell.IsSpellInRange = function() return nil end
    t.eq(c.reach(1126, "party1"), nil, "no answer")
    env.C_Spell.IsSpellInRange = function() error("x") end
    t.eq(c.reach(1126, "party1"), nil, "raised")
    t.eq(ns.make.client({}).reach(1126, "party1"), nil, "no such call")
end

tests["c.unitDebuffTypes: the types on you or a party member, first name of each"] = function(t)
    local rows = {
        { name = "Made-up Venom", dispelName = "Poison" },
        { name = "Made-up Scratch" },
        { name = "Made-up Sting", dispelName = "Poison" },
        { name = "Made-up Hex", dispelName = "Curse" },
    }
    local asked = {}
    local env = { C_UnitAuras = { GetAuraDataByIndex = function(unit, i, filter)
        asked[#asked + 1] = unit .. "/" .. filter
        return rows[i]
    end } }
    local c = ns.make.client(env)
    t.eq(c.unitDebuffTypes("player"), { Poison = "Made-up Venom", Curse = "Made-up Hex" })
    t.eq(asked[1], "player/HARMFUL", "harmful auras of the unit asked")
    t.eq(c.unitDebuffTypes("party3"), { Poison = "Made-up Venom", Curse = "Made-up Hex" })
    t.eq(c.unitDebuffTypes("target"), nil, "not you or a party member: not asked")
    rows = {}
    t.eq(c.unitDebuffTypes("player"), {}, "nothing on you: read, empty")
    rows = { { name = "Made-up Venom", dispelName = 7 } }
    t.eq(c.unitDebuffTypes("player"), nil, "a type that is no name: not known")
    env.C_UnitAuras.GetAuraDataByIndex = function() error("x") end
    t.eq(c.unitDebuffTypes("player"), nil, "raised")
    t.eq(ns.make.client({}).unitDebuffTypes("player"), nil, "no such call")
end

tests["fake client: the group reads answer what was set, nil until set; failures raise"] = function(t)
    local c = ns.make.fakeClient()
    t.eq(c.party(), nil, "not set")
    t.eq(c.reach(1126, "party1"), nil)
    t.eq(c.unitDebuffTypes("player"), nil)
    c.setParty({ { unit = "party1", name = NAME } })
    t.eq(c.party(), { { unit = "party1", name = NAME } })
    c.setReach("party1", 1126, true)
    t.eq(c.reach(1126, "party1"), true)
    c.setUnitDebuffs("player", { Curse = "Made-up Hex" })
    t.eq(c.unitDebuffTypes("player"), { Curse = "Made-up Hex" })
    c.setPartyFails(true)
    t.ok(not pcall(c.party), "the group read raises")
    c.setPartyFails(false)
    t.ok(pcall(c.party), "and answers again")
    c.setReachFails(true)
    t.ok(not pcall(c.reach, 1126, "party1"), "the reach read raises")
    c.setReachFails(false)
    t.eq(c.reach(1126, "party1"), true)
end

-- Lead section 243 item 5: in a raid, every other raid member (raid1..40),
-- yourself left out by UnitIsUnit; not known whether one is you: nil.
local function raidEnv(extra)
    local env = groupEnv({
        UnitExists = function(unit) return unit == "raid1" or unit == "raid2" or unit == "raid3" end,
        UnitIsUnit = function(unit, other) return unit == "raid2" and other == "player" end,
    })
    for k, v in pairs(extra or {}) do env[k] = v end
    return env
end

tests["c.party 243: in a raid, the other raid members, not you"] = function(t)
    local got = ns.make.client(raidEnv()).party()
    local units = {}
    for i, m in ipairs(got or {}) do units[i] = m.unit end
    t.eq(units, { "raid1", "raid3" })
    t.eq(ns.make.client(raidEnv({ UnitIsUnit = false })).party(), nil, "not known which is you: nil")
    t.eq(ns.make.client(raidEnv({ UnitIsUnit = function() return nil end })).party(), nil, "no answer: nil")
    t.ok(ns.Diag and (function()
        for _, n in ipairs(ns.Diag.NAMES) do if n == "UnitIsUnit" then return true end end
        return false
    end)(), "UnitIsUnit is in the capture's name list")
end

tests["c.reach and c.unitDebuffTypes 243: raid units are asked too"] = function(t)
    local env = { C_Spell = { IsSpellInRange = function() return true end },
                  C_UnitAuras = { GetAuraDataByIndex = function() return nil end } }
    local c = ns.make.client(env)
    t.eq(c.reach(1126, "raid12"), true)
    t.eq(c.reach(1126, "raid41"), nil, "no raid41")
    t.eq(c.unitDebuffTypes("raid40"), {})
end

-- Lead section 243 item 1: the look-only mark on the real icon: a tint
-- over the picture, shown only for "look"; any other mark goes to the
-- icon's own (far: red; else plain).
tests["the icon's look mark 243: an overlay shown for look only"] = function(t)
    local overlay = { shown = nil }
    function overlay:SetAllPoints() end
    function overlay:SetColorTexture() self.colored = true end
    function overlay:Show() self.shown = true end
    function overlay:Hide() self.shown = false end
    local picture = { color = nil }
    function picture:SetAllPoints() end
    function picture:SetVertexColor(r, g, b) self.color = { r, g, b } end
    function picture:SetTexture() end
    local made = 0
    local frame = setmetatable({}, { __index = function() return function() return true end end })
    rawset(frame, "CreateTexture", function()
        made = made + 1
        if made == 1 then return picture end
        return overlay
    end)
    local env = { UIParent = {} }
    env.CreateFrame = function(_, name) env[name] = frame return frame end
    local h = ns.make.client(env).icon({ name = "TestIcon", size = 48 })
    t.eq(h.mark("look"), true)
    t.eq(overlay.shown, true, "look: the overlay is up")
    t.eq(picture.color, { 1, 1, 1 }, "the picture keeps its plain colour")
    t.eq(h.mark("far"), true)
    t.eq(overlay.shown, false, "far: no overlay")
    t.eq(picture.color, { 1, 0.3, 0.3 }, "far: red as before")
    h.mark(nil)
    t.eq(overlay.shown, false)
    local fake = ns.make.fakeClient().icon({ name = "TestIcon" })
    fake.mark("look")
    t.eq(fake.marked, "look", "the fake keeps the look mark")
    fake.mark(nil)
    t.eq(fake.marked, nil)
end

tests["fake client 243: a member's buff read raises while set, then answers"] = function(t)
    local c = ns.make.fakeClient()
    c.setUnitBuffs("party1", { { name = "Thorns", left = 5 } })
    c.setUnitBuffFails("party1", true)
    t.ok(not pcall(c.unitBuff, "party1", { "Thorns" }), "raises")
    t.eq(c.unitBuff("party2", { "Thorns" }), nil, "another member is not touched")
    c.setUnitBuffFails("party1", false)
    t.eq(c.unitBuff("party1", { "Thorns" }), true)
end

tests["the icon's caption: a line under the icon, live only; the fake keeps the last"] = function(t)
    local c = ns.make.fakeClient()
    local h = c.icon({ name = "TestIcon", size = 48 })
    t.ok(type(h.caption) == "function", "the fake icon has a caption")
    h.caption("Mark of the Wild on " .. NAME)
    t.eq(h.captionText, "Mark of the Wild on " .. NAME)
    h.caption(nil)
    t.eq(h.captionText, nil, "nil hides it")
    -- The real client: made on the icon's frame, found by its name.
    local texts, shown = {}, nil
    local fs = {
        SetPoint = function() end,
        SetText = function(_, text) texts[#texts + 1] = text end,
        Show = function() shown = true end, Hide = function() shown = false end,
    }
    local frame = setmetatable({ CreateFontString = function() return fs end }, { __index = function()
        return function() return true end
    end })
    local env = { UIParent = {} }
    env.CreateFrame = function(_, name)
        env[name] = frame
        return frame
    end
    local real = ns.make.client(env).icon({ name = "TestIcon", size = 48 })
    t.ok(type(real) == "table" and type(real.caption) == "function", "the real icon has a caption")
    if type(real) ~= "table" or type(real.caption) ~= "function" then return end
    t.eq(real.caption("Thorns on " .. NAME), true)
    t.eq(texts[#texts], "Thorns on " .. NAME)
    t.eq(shown, true)
    real.caption(nil)
    t.eq(texts[#texts], "", "nil: empty")
    t.eq(shown, false, "and hidden")
end

return tests

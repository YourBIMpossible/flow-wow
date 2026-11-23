local _, ns = ...
-- N64 (lead section 243): how long your buff on a party member lasts is
-- taken from the client's own answer, over the pack's guessed minutes. A
-- caster druid in a party; Mark of the Wild's row guesses 30 minutes. The
-- member's buffs read with the time left just after your cast lands: that
-- answer gives the whole length. With the buffs hidden after, the cast is
-- remembered for that length, not the guess. Made-up names, spell ids and
-- a made-up hour-long length. Not tested in game.
local tests = {}

local D = ns.RotationDriver
local MOTW, THORNS = "Mark of the Wild", "Thorns"
local IDS = { [MOTW] = 1126, [THORNS] = 467, ["Wrath"] = 5176, ["Moonfire"] = 8921, ["Attack"] = 6603 }
local NAME = "Bramblewick"   -- made up
local MEMBER = { unit = "party1", name = NAME, class = "WARRIOR", role = "NONE", power = 1, dead = false, connected = true }

local function start()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setClass("DRUID"); c.setFaction("Alliance"); c.setLevel(30); c.setDead(false)
    for name, id in pairs(IDS) do
        c.setSpellId(name, id); c.setSpell(id, { known = true, usable = true }); c.setSpellCooldown(id, false)
        c.setSpellTexture(id, "tex:" .. name)
    end
    c.setParty({ MEMBER })
    for _, id in pairs(IDS) do c.setReach("party1", id, true) end
    c.setUnitBuffs("party1", { { name = THORNS, left = 500 } })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    addon.settings:set(D.SETTING, true)
    c.setFormName(nil, true); c.setPlayerBuffs({ [MOTW] = true, [THORNS] = true })
    c.setTarget({ exists = false }); c.setCombat(false)
    c.advance(2, 10)
    return c, addon
end

local function picked(addon)
    local use = addon.use(D.NAME)
    if type(use) ~= "table" then return nil end
    local v = use.View()
    if type(v) ~= "table" or type(v.suggestion) ~= "table" then return nil end
    return v.suggestion
end

local function cast(c, id)
    c.fire("UNIT_SPELLCAST_SENT", "player", NAME, id, IDS[MOTW])
    c.fire("UNIT_SPELLCAST_SUCCEEDED", "player", id, IDS[MOTW])
end

tests["group e2e N64: the length is the client's answer just after your cast, not the guessed minutes"] = function(t)
    local c, addon = start()
    t.eq(picked(addon) and picked(addon).spell, MOTW, "Mark missing: suggested")
    t.eq(addon.PartyGroup.Length({ spell = MOTW, minutes = 30 }), 1800, "before any answer: the guess")
    cast(c, "n64-1")
    c.setUnitBuffs("party1", { { name = THORNS, left = 490 }, { name = MOTW, left = 3598 } })
    c.advance(2, 10)
    local got = addon.PartyGroup.Learned()[MOTW]
    t.ok(type(got) == "number" and got >= 3598 and got <= 3610, "learned about an hour: " .. tostring(got))
    t.eq(addon.PartyGroup.Length({ spell = MOTW, minutes = 30 }), got, "the answer over the guess")
    -- The game hides their buffs; the cast is remembered for the length read.
    c.setUnitBuffs("party1", { { name = false } })
    c.advance(1900, 60)
    t.eq(picked(addon), nil, "past the guessed 30 minutes: still covered")
    c.advance(1660, 60)
    local s = picked(addon)
    t.eq(s and { s.step, s.spell, s.unit } or nil, { "group", MOTW, "party1" }, "under a minute of the hour left: running out")
end

tests["group e2e N64: a time left read long after your cast teaches nothing"] = function(t)
    local c, addon = start()
    cast(c, "n64-2")
    c.advance(30, 10)
    c.setUnitBuffs("party1", { { name = THORNS, left = 470 }, { name = MOTW, left = 3000 } })
    c.advance(2, 10)
    t.eq(addon.PartyGroup.Learned()[MOTW], nil, "read past the window: nothing learned")
    t.eq(addon.PartyGroup.Length({ spell = MOTW, minutes = 30 }), 1800, "the guess stands")
end

tests["group e2e N64: a buff you did not cast teaches nothing"] = function(t)
    local c, addon = start()
    c.setUnitBuffs("party1", { { name = THORNS, left = 500 }, { name = MOTW, left = 3598 } })
    c.advance(5, 10)
    t.eq(addon.PartyGroup.Learned()[MOTW], nil, "no cast of yours: nothing learned")
    t.eq(picked(addon), nil, "they have it: nothing suggested")
end

-- Lead section 263 READS-2 item 4: client.buffLength, the whole length the
-- client gives (the fake: the row field length), over the time-left path.
tests["group e2e N64: the client buff length is taken, even read long after your cast"] = function(t)
    local c, addon = start()
    cast(c, "n64-4")
    c.advance(30, 10)
    c.setUnitBuffs("party1", { { name = THORNS, left = 470 }, { name = MOTW, left = 3000, length = 3600, caster = "player" } })
    c.advance(2, 10)
    t.eq(addon.PartyGroup.Learned()[MOTW], 3600, "the client length, past the window")
    t.eq(addon.PartyGroup.Length({ spell = MOTW, minutes = 30 }), 3600, "the client length over the guess")
end

tests["group e2e N64: the client buff length over a time left read just after your cast"] = function(t)
    local c, addon = start()
    cast(c, "n64-5")
    c.setUnitBuffs("party1", { { name = THORNS, left = 490 }, { name = MOTW, left = 3598, length = 3600, caster = "player" } })
    c.advance(2, 10)
    t.eq(addon.PartyGroup.Learned()[MOTW], 3600, "the client length, not the time left plus the seconds since")
end

tests["group e2e N64: a client buff length on a buff you did not cast teaches nothing"] = function(t)
    local c, addon = start()
    c.setUnitBuffs("party1", { { name = THORNS, left = 500 }, { name = MOTW, left = 3598, length = 3600 } })
    c.advance(5, 10)
    t.eq(addon.PartyGroup.Learned()[MOTW], nil, "no cast of yours: nothing learned")
end


-- Review R2-1 (READS-2): the client length is learned only from a buff you
-- cast (the fake: the row field caster, "player" for you). Another
-- player's copy, or a caster hidden or not read, teaches no length; the
-- time-left fallback stays.
tests["group e2e N64 R2-1: another player's buff length teaches nothing"] = function(t)
    local c, addon = start()
    cast(c, "r21-1")
    c.advance(30, 10)
    c.setUnitBuffs("party1", { { name = THORNS, left = 470 }, { name = MOTW, left = 3000, length = 3600, caster = "party2" } })
    c.advance(2, 10)
    t.eq(addon.PartyGroup.Learned()[MOTW], nil, "their length, past the window: nothing learned")
    t.eq(addon.PartyGroup.Length({ spell = MOTW, minutes = 30 }), 1800, "the guess stands")
end

tests["group e2e N64 R2-1: another player's buff length leaves the time-left fallback"] = function(t)
    local c, addon = start()
    cast(c, "r21-2")
    c.setUnitBuffs("party1", { { name = THORNS, left = 490 }, { name = MOTW, left = 3598, length = 7200, caster = "party2" } })
    c.advance(2, 10)
    local got = addon.PartyGroup.Learned()[MOTW]
    t.ok(type(got) == "number" and got >= 3598 and got <= 3610, "the time left plus the seconds since: " .. tostring(got))
end

tests["group e2e N64 R2-1: a caster hidden or not read teaches no length"] = function(t)
    local c, addon = start()
    cast(c, "r21-3")
    c.advance(30, 10)
    c.setUnitBuffs("party1", { { name = MOTW, left = 3000, length = 3600, caster = c.SECRET } })
    c.advance(2, 10)
    t.eq(addon.PartyGroup.Learned()[MOTW], nil, "hidden caster: nothing learned")
    c.setUnitBuffs("party1", { { name = MOTW, left = 2990, length = 3600 } })
    c.advance(2, 10)
    t.eq(addon.PartyGroup.Learned()[MOTW], nil, "caster not read: nothing learned")
end

tests["group e2e N64 R2-1 236: late data: the caster read after the length"] = function(t)
    local c, addon = start()
    cast(c, "r21-4")
    c.advance(30, 10)
    c.setUnitBuffs("party1", { { name = MOTW, left = 3000, length = 3600 } })
    c.advance(2, 10)
    t.eq(addon.PartyGroup.Learned()[MOTW], nil, "length without a caster: nothing yet")
    c.setUnitBuffs("party1", { { name = MOTW, left = 2990, length = 3600, caster = "player" } })
    c.advance(2, 10)
    t.eq(addon.PartyGroup.Learned()[MOTW], 3600, "yours, once the caster is read")
end

tests["group e2e N64 R2-1 236: reload: another player's buff still teaches nothing"] = function(t)
    start()
    local c2, addon2 = start()
    c2.setUnitBuffs("party1", { { name = MOTW, left = 3000, length = 3600, caster = "party2" } })
    cast(c2, "r21-5")
    c2.advance(30, 10)
    t.eq(addon2.PartyGroup.Learned()[MOTW], nil, "after the reload: theirs teaches nothing")
    c2.setUnitBuffs("party1", { { name = MOTW, left = 3590, length = 3600, caster = "player" } })
    c2.advance(2, 10)
    t.eq(addon2.PartyGroup.Learned()[MOTW], 3600, "after the reload: yours is learned")
end

tests["group e2e N64 R2-1 236: a length read that fails, then recovers"] = function(t)
    local c, addon = start()
    local real = c.buffLength
    c.buffLength = function() error("buffLength: refused") end
    cast(c, "r21-6")
    c.advance(30, 10)
    c.setUnitBuffs("party1", { { name = MOTW, left = 3000, length = 3600, caster = "player" } })
    c.advance(2, 10)
    t.eq(addon.PartyGroup.Learned()[MOTW], nil, "the read raised: nothing learned")
    c.buffLength = real
    c.advance(2, 10)
    t.eq(addon.PartyGroup.Learned()[MOTW], 3600, "the read back: yours is learned")
end

return tests

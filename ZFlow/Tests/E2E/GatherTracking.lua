local _, ns = ...
-- Lead sections 226/227, P-GATHER (upstream #31): a player who knows a
-- gathering tracking spell and has its profession, with that tracking off,
-- is offered it out of a fight on the rotation icon and the existing key,
-- as Flow did (Modules/Rotation/Actions.lua "gather:find"). The whole
-- add-on on a fake client (the section 187 harness), a Paladin as the
-- class. Spell ids made up. Look only: nothing is cast for the player; the
-- key casts only on the player's own press, as for any suggestion.
-- Not tested in game.
local tests = {}

local D = ns.RotationDriver
local IDS = {
    ["Devotion Aura"] = 465, ["Seal of Righteousness"] = 21084, ["Blessing of Might"] = 19740,
    ["Attack"] = 6603, ["Judgement"] = 20271,
}
local MINERALS, HERBS = "Find Minerals", "Find Herbs"
local GATHER = { [MINERALS] = 9301, [HERBS] = 9302 }
-- Every buff up: the Paladin's list has nothing to ask out of a fight.
local SEALED = { ["Devotion Aura"] = true, ["Blessing of Might"] = 200, ["Seal of Righteousness"] = 25 }
local ENEMY = { exists = true, hostile = true, dead = false }

-- opts.professions: the list the client answers (nil: not read).
-- opts.unknown: gather spells not learned. opts.tracking: { [spell] = on }.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setClass("PALADIN"); c.setFaction("Alliance"); c.setLevel(20); c.setDead(false)
    for name, id in pairs(IDS) do
        c.setSpellId(name, id); c.setSpell(id, { known = true, usable = true }); c.setSpellCooldown(id, false)
        c.setSpellTexture(id, "tex:" .. name)
    end
    for name, id in pairs(GATHER) do
        if not (opts.unknown and opts.unknown[name]) then
            c.setSpellId(name, id); c.setSpell(id, { known = true, usable = true }); c.setSpellCooldown(id, false)
        end
        c.setSpellTexture(id, "tex:" .. name)
    end
    if opts.professions ~= false then c.setProfessions(opts.professions or { "Mining" }) end
    for spell, on in pairs(opts.tracking or { [MINERALS] = false, [HERBS] = false }) do c.setTracking(spell, on) end
    -- GT-2: on foot and not flying, unless the test says otherwise.
    if opts.mounted ~= "unread" then c.setMounted(opts.mounted == true) end
    if opts.onTaxi ~= "unread" then c.setOnTaxi(opts.onTaxi == true) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    local icon
    for _, h in ipairs(c.icons) do
        if tostring(h.spec.name):find("RotationIcon", 1, true) then icon = h end
    end
    addon.settings:set(D.SETTING, true)
    c.setPlayerBuffs(SEALED); c.setTarget({ exists = false }); c.setCombat(false)
    c.advance(1, 5)
    return c, addon, icon
end

local function said(c)
    local from = #c.printed + 1
    c.slashes[ns.id.slash]("diag")
    local out = {}
    for i = from, #c.printed do
        local line = tostring(c.printed[i])
        if line:find("rotation:", 1, true) then out[#out + 1] = line end
    end
    return table.concat(out, " / ")
end

local function offered(icon, spell) return icon ~= nil and icon.shown and icon.texture == "tex:" .. spell end

tests["gather tracking: Mining known, Find Minerals off, out of a fight: offered on the icon and the key"] = function(t)
    local c, _, icon = start()
    t.ok(offered(icon, MINERALS), "the icon shows Find Minerals, got " .. tostring(icon and icon.texture))
    t.ok(said(c):find("suggesting Find Minerals", 1, true), "the diag word says it: " .. said(c))
end

tests["gather tracking: Herbalism gives Find Herbs"] = function(t)
    local _, _, icon = start({ professions = { "Herbalism" } })
    t.ok(offered(icon, HERBS), "Find Herbs, got " .. tostring(icon and icon.texture))
end

tests["gather tracking: tracking already on: nothing"] = function(t)
    local c, _, icon = start({ tracking = { [MINERALS] = true, [HERBS] = false } })
    t.ok(not offered(icon, MINERALS), "already on")
    c.setTracking(MINERALS, false); c.advance(1, 5)
    t.ok(offered(icon, MINERALS), "turned off: offered again, so this test can fail")
end

tests["gather tracking: another gathering tracking on: not switched away"] = function(t)
    local _, _, icon = start({ professions = { "Mining", "Herbalism" }, tracking = { [MINERALS] = false, [HERBS] = true } })
    t.ok(not offered(icon, MINERALS), "Find Herbs is on: Find Minerals is not offered over it")
end

tests["gather tracking: the spell not known, or the profession not had: nothing"] = function(t)
    local _, _, icon = start({ unknown = { [MINERALS] = true } })
    t.ok(not offered(icon, MINERALS), "Find Minerals not learned")
    local _, _, icon2 = start({ professions = { "Tailoring" } })
    t.ok(not offered(icon2, MINERALS), "no Mining")
    local _, _, icon3 = start({ professions = false })
    t.ok(not offered(icon3, MINERALS), "professions not read: nothing")
end

tests["gather tracking: not in a fight"] = function(t)
    local c, _, icon = start()
    t.ok(offered(icon, MINERALS), "out of a fight: offered, so this test can fail")
    c.setTarget(ENEMY); c.setCombat(true); c.advance(1, 5)
    t.ok(not offered(icon, MINERALS), "in a fight: not offered")
end

tests["gather tracking: the setting switches it off and on"] = function(t)
    local c, addon, icon = start()
    t.ok(offered(icon, MINERALS), "on by default")
    t.eq(addon.settings:set(ns.Gather.SETTING, false), true, "the row is there and takes off")
    c.advance(1, 5)
    t.ok(not offered(icon, MINERALS), "off: not offered")
    addon.settings:set(ns.Gather.SETTING, true); c.advance(1, 5)
    t.ok(offered(icon, MINERALS), "on again")
end

tests["gather tracking: the suggestion goes to the key as a spell on yourself"] = function(t)
    local s = ns.Gather.Step({ inCombat = false, gatherOn = true, professions = { Mining = true },
        trackKnown = { [MINERALS] = true }, tracking = { [MINERALS] = false } })
    -- A spell suggestion on yourself: the key (Rotation/Cast.lua Attributes)
    -- casts it as it casts a buff, a "spell" action type, nothing new.
    t.eq(type(s) == "table" and { s.spell, s.kind, s.unit } or nil, { MINERALS, "buff", "player" })
end

-- Lead section 230, MyBuddy GT-1, GT-2 and the key-attribute gap on a956ae3.

-- GT-1: Flow refused when any tracking was on (X.AnyTracked): a hunter's
-- Track Beasts or Find Fish is the player's choice and is not switched away.
tests["gather tracking GT-1: any other tracking on: nothing"] = function(t)
    local c, _, icon = start({ tracking = { [MINERALS] = false, [HERBS] = false, ["Track Beasts"] = true } })
    t.ok(not offered(icon, MINERALS), "Track Beasts is on: Find Minerals is not offered over it")
    c.setTracking("Track Beasts", false); c.advance(1, 5)
    t.ok(offered(icon, MINERALS), "nothing on now: offered, so this test can fail")
end

-- GT-2: Flow's X.TrackAllowed: not mounted, not on a flight path, not
-- eating or drinking (a cast would dismount, or stand the player up).
tests["gather tracking GT-2: mounted, on a flight path, or eating or drinking: nothing"] = function(t)
    local c, _, icon = start()
    t.ok(offered(icon, MINERALS), "on foot: offered, so this test can fail")
    c.setMounted(true); c.advance(1, 5)
    t.ok(not offered(icon, MINERALS), "mounted")
    c.setMounted(false); c.setOnTaxi(true); c.advance(1, 5)
    t.ok(not offered(icon, MINERALS), "on a flight path")
    c.setOnTaxi(false)
    for _, buff in ipairs({ "Food", "Drink" }) do
        local buffs = { [buff] = 18 }
        for k, v in pairs(SEALED) do buffs[k] = v end
        c.setPlayerBuffs(buffs); c.advance(1, 5)
        t.ok(not offered(icon, MINERALS), buff .. ": eating or drinking")
    end
    c.setPlayerBuffs(SEALED); c.advance(1, 5)
    t.ok(offered(icon, MINERALS), "done eating: offered again")
end

tests["gather tracking GT-2: mounted or flight path not read: nothing"] = function(t)
    local _, _, icon = start({ mounted = "unread" })
    t.ok(not offered(icon, MINERALS), "not known whether mounted")
    local _, _, icon2 = start({ onTaxi = "unread" })
    t.ok(not offered(icon2, MINERALS), "not known whether on a flight path")
end

-- The key: the offer reaches the key's attributes as a spell on yourself.
tests["gather tracking: the key's attributes carry the offer as a spell on yourself"] = function(t)
    local s = ns.Gather.Step({ inCombat = false, gatherOn = true, mounted = false, onTaxi = false, buffs = {},
        trackingAny = false, professions = { Mining = true },
        trackKnown = { [MINERALS] = true }, tracking = { [MINERALS] = false } })
    t.ok(type(s) == "table", "an offer")
    if type(s) ~= "table" then return end
    local attrs = ns.cast.Attributes(s, ns.KeyPlan(ns.Packs.PALADIN, nil), nil, false, 0)
    local got = {}
    for _, r in ipairs(type(attrs) == "table" and attrs.button or {}) do got[r.attr] = r.value end
    t.eq({ got.type, got.spell, got.unit }, { "spell", MINERALS, "player" }, "the key casts Find Minerals on you")
end

return tests

local _, ns = ...
-- Lead section 344 (P-PARTY item a): the group buff and cure step in a
-- raid. The whole add-on on a fake client, a caster druid out of a fight,
-- in a raid: the group read answers raid units (raid1..raid40, never you),
-- and the step must name a raid unit exactly as it names a party unit:
-- look only, the tank first, out of reach skipped, the key untouched, the
-- diag word naming the unit and never the member. Made-up names and spell
-- ids. Offline only; not tested in game (every client read is a first
-- guess, Core/Client.lua c.party, c.reach, c.unitDebuffTypes, c.unitBuff).
local tests = {}

local D = ns.RotationDriver
local MOTW, THORNS, ABOLISH = "Mark of the Wild", "Thorns", "Abolish Poison"
local IDS = {
    [MOTW] = 1126, [THORNS] = 467, ["Wrath"] = 5176, ["Moonfire"] = 8921, ["Attack"] = 6603,
    ["Remove Curse"] = 2782, [ABOLISH] = 2893, ["Cure Poison"] = 8946,
}
local BUFFED = { [MOTW] = true, [THORNS] = true }
local COVERED = { { name = MOTW, left = 1000 }, { name = THORNS, left = 500 } }
local BARE = { { name = THORNS, left = 500 } }
-- Raid units of the other members (you are raid4, so the read leaves it out).
local UNITS = { "raid1", "raid2", "raid3", "raid5", "raid9", "raid14", "raid27", "raid33", "raid40" }

local function nameOf(unit) return "Raider" .. unit:sub(5) end   -- made up

local function raider(unit, over)
    local m = { unit = unit, name = nameOf(unit), class = "WARRIOR", role = "NONE", power = 1,
        dead = false, connected = true }
    for k, v in pairs(over or {}) do m[k] = v end
    return m
end

-- opts.over[unit]: fields over the member; opts.buffs[unit]: that member's
-- buffs (default COVERED); opts.reach[unit] = false: out of reach;
-- opts.debuffs[unit]: that member's debuff types.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setClass("DRUID"); c.setFaction("Alliance"); c.setLevel(30); c.setDead(false)
    for name, id in pairs(IDS) do
        c.setSpellId(name, id); c.setSpell(id, { known = true, usable = true }); c.setSpellCooldown(id, false)
        c.setSpellTexture(id, "tex:" .. name)
    end
    local list = {}
    for _, unit in ipairs(UNITS) do
        list[#list + 1] = raider(unit, (opts.over or {})[unit])
        local inReach = not (opts.reach ~= nil and opts.reach[unit] == false)
        for _, id in pairs(IDS) do c.setReach(unit, id, inReach) end
        c.setUnitBuffs(unit, (opts.buffs or {})[unit] or COVERED)
        if opts.debuffs ~= nil and opts.debuffs[unit] ~= nil then c.setUnitDebuffs(unit, opts.debuffs[unit]) end
    end
    c.setParty(list)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    local icon
    for _, h in ipairs(c.icons) do
        if tostring(h.spec.name):find("RotationIcon", 1, true) then icon = h end
    end
    addon.settings:set(D.SETTING, true)
    c.setFormName(nil, true); c.setPlayerBuffs(BUFFED); c.setTarget({ exists = false }); c.setCombat(false)
    c.advance(2, 10)
    return c, addon, icon
end

local function view(addon)
    local use = addon.use(D.NAME)
    return type(use) == "table" and use.View() or nil
end

local function picked(addon)
    local v = view(addon)
    local s = type(v) == "table" and v.suggestion or nil
    return type(s) == "table" and s or nil
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

tests["group raid e2e: everyone in the raid covered: nothing, so the next tests can fail"] = function(t)
    local _, addon, icon = start()
    t.eq(picked(addon), nil, "no suggestion")
    t.ok(icon ~= nil and not icon.shown, "the icon is down")
end

tests["group raid e2e: a member past the first five missing Mark of the Wild: named, look only"] = function(t)
    local c, addon, icon = start({ buffs = { raid27 = BARE } })
    local s = picked(addon)
    t.eq(s and { s.step, s.spell, s.unit, s.member, s.look } or nil,
        { "group", MOTW, "raid27", nameOf("raid27"), true })
    t.eq(icon and icon.captionText, MOTW .. " on " .. nameOf("raid27"), "the caption names the member")
    local line = said(c)
    t.ok(line:find("suggesting " .. MOTW .. " for raid27 (group; look only, nothing cast)", 1, true) ~= nil,
        "the diag line names the raid unit: " .. line)
    t.ok(not line:find(nameOf("raid27"), 1, true), "and never the member")
end

tests["group raid e2e: the last raid slot, raid40, is asked too"] = function(t)
    local _, addon = start({ buffs = { raid40 = BARE } })
    local s = picked(addon)
    t.eq(s and { s.spell, s.unit } or nil, { MOTW, "raid40" })
end

tests["group raid e2e: the raid tank first, wherever the tank sits in the raid"] = function(t)
    local _, addon = start({ over = { raid33 = { role = "TANK" } }, buffs = { raid2 = BARE, raid33 = BARE } })
    local s = picked(addon)
    t.eq(s and { s.spell, s.unit } or nil, { MOTW, "raid33" }, "raid33 (the tank) before raid2")
end

tests["group raid e2e: out of reach, dead or offline raid members skipped; the next one named"] = function(t)
    local _, addon = start({
        reach = { raid1 = false },
        over = { raid2 = { dead = true }, raid3 = { connected = false } },
        buffs = { raid1 = BARE, raid2 = BARE, raid3 = BARE, raid14 = BARE },
    })
    local s = picked(addon)
    t.eq(s and { s.spell, s.unit } or nil, { MOTW, "raid14" })
end

tests["group raid e2e: a poison on a raid member: the cure on that raid unit, the key untouched"] = function(t)
    local _, addon = start({ debuffs = { raid9 = { Poison = "Made-up Venom" } } })
    local s = picked(addon)
    t.eq(s and { s.step, s.spell, s.unit, s.look } or nil, { "group", ABOLISH, "raid9", true })
    local v = view(addon)
    t.eq(v and v.attrs and v.attrs.source, "plan", "the key is the plan's")
    for _, row in ipairs(v and v.attrs and v.attrs.button or {}) do
        t.ok(row.value ~= "raid9", "the raid unit is on no attribute: " .. tostring(row.attr))
        t.ok(row.value ~= ABOLISH, "the cure is on no attribute: " .. tostring(row.attr))
    end
end

tests["group raid e2e: the raid becomes a party: the party unit named on the next read"] = function(t)
    local c, addon = start({ buffs = { raid5 = BARE } })
    local s = picked(addon)
    t.eq(s and s.unit or nil, "raid5", "in the raid: raid5")
    c.setParty({ raider("party1", { name = nameOf("raid5") }) })
    for _, id in pairs(IDS) do c.setReach("party1", id, true) end
    c.setUnitBuffs("party1", BARE)
    c.fire("GROUP_ROSTER_UPDATE"); c.advance(2, 10)
    s = picked(addon)
    t.eq(s and { s.spell, s.unit } or nil, { MOTW, "party1" }, "after the roster change: party1")
end

tests["group raid e2e: in a fight nothing for the raid; out again it is back"] = function(t)
    local c, addon = start({ buffs = { raid14 = BARE } })
    t.ok(picked(addon) ~= nil, "out of a fight: suggested")
    c.setCombat(true); c.advance(2, 10)
    t.eq(picked(addon), nil, "in a fight: nothing")
    c.setCombat(false); c.advance(2, 10)
    local s = picked(addon)
    t.eq(s and s.unit or nil, "raid14", "out again: back")
end

return tests

local _, ns = ...

-- The weapon speed line of an item tooltip (G15), as text. Pure: the
-- weapon's speed and damage per second come in as read; nothing here reads
-- the game, and nothing here changes a score.
--
--   feel = GearWeaponSpeed.Feel(speed)
--   line = GearWeaponSpeed.Line(weapon[, prefs])
--   weapon = GearWeaponSpeed.From(gear)
--
--   speed   seconds between swings, as the client gives it
--   feel    "slow" (GearWeaponSpeed.SLOW seconds or more), "fast"
--           (GearWeaponSpeed.FAST or less), "medium" between; nil for a
--           speed that is not a number above zero
--   weapon  { kind, speed, dps }: the equip location, the speed and the
--           damage per second. dps not read is left out of the line; it is
--           never shown as 0.
--   prefs   { [role] = { prefer = "slow" | "medium" | "fast" | "any", why,
--           ranged = { prefer, why }, offhand = { prefer, why } } }:
--           which speed a role likes, from the class pack's weaponSpeed;
--           `why`, when words, follows in brackets. "any" (GearWeaponSpeed.ANY):
--           speed does not matter for the role, and the line says so, the
--           reason after a colon. `ranged`, when the role has it, speaks
--           for a weapon of the ranged slot (a bow, a gun, a wand, a thrown
--           weapon) in place of the role's own entry; `offhand` for a weapon
--           that only goes in the off hand. Without prefs the line gives
--           the speed and its feel only.
--   line    { text, tone = "none" }, or nil: not a weapon, or no speed read.
--           "Speed 3.40 (slow), 60.0 damage per second; good for dps"
--           "Speed 3.00 (medium); speed does not matter for heal (stats do)"
--   gear    what client.gear(link) answers. From takes kind, `speed` (a
--           field client.gear gives for a weapon) and the damage per second
--           from the stats, when it is a plain number.
--
-- The two marks, 3.3 and 2.0 seconds, are carried over from the
-- predecessor's weapon speed note (Modules/Gear/Analyzers.lua); who chose
-- them is not recorded: a first guess. The predecessor also added up to one
-- point to an item's score for speed. That is not done here: the scorer
-- counts stats and weights and nothing else.

local W = {}
ns.GearWeaponSpeed = W

W.SLOW, W.FAST = 3.3, 2.0
W.DPS_KEY = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT"

-- The equip locations that swing or shoot. A shield, a held item and a
-- relic have no speed.
local WEAPON = {
    INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true,
    INVTYPE_WEAPONOFFHAND = true, INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true,
    INVTYPE_THROWN = true,
}
local FEELS = { slow = true, medium = true, fast = true }
W.ANY = "any"
local RANGED = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }
local OFF_HAND = "INVTYPE_WEAPONOFFHAND"

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function W.Feel(speed)
    if not finite(speed) or speed <= 0 then return nil end
    if speed >= W.SLOW then return "slow" end
    if speed <= W.FAST then return "fast" end
    return "medium"
end

-- The entry that speaks for a weapon of this kind: the role's `ranged` or
-- `offhand` part when the weapon is one and the role has that part, else
-- the role's own. nil when it names no speed.
local function entryFor(pref, kind)
    if type(pref) ~= "table" then return nil end
    local part
    if RANGED[kind] then
        part = pref.ranged
    elseif kind == OFF_HAND then
        part = pref.offhand
    end
    if type(part) == "table" then pref = part end
    if FEELS[pref.prefer] or pref.prefer == W.ANY then return pref end
    return nil
end

function W.Line(weapon, prefs)
    if type(weapon) ~= "table" or type(weapon.kind) ~= "string" or not WEAPON[weapon.kind] then return nil end
    local feel = W.Feel(weapon.speed)
    if not feel then return nil end
    local text = string.format("Speed %.2f (%s)", weapon.speed, feel)
    if finite(weapon.dps) and weapon.dps >= 0 then
        text = text .. string.format(", %.1f damage per second", weapon.dps)
    end
    if type(prefs) == "table" then
        local roles = {}
        for role, pref in pairs(prefs) do
            if type(role) == "string" and entryFor(pref, weapon.kind) then roles[#roles + 1] = role end
        end
        table.sort(roles)
        for i = 1, #roles do
            local pref = entryFor(prefs[roles[i]], weapon.kind)
            local why = type(pref.why) == "string" and pref.why ~= ""
            if pref.prefer == W.ANY then
                text = text .. "; speed does not matter for " .. roles[i] .. " (stats do)"
                if why then text = text .. ": " .. pref.why end
            else
                if pref.prefer == feel then
                    text = text .. "; good for " .. roles[i]
                else
                    text = text .. "; " .. roles[i] .. " prefers " .. pref.prefer
                end
                if why then text = text .. " (" .. pref.why .. ")" end
            end
        end
    end
    return { text = text, tone = "none" }
end

function W.From(gear)
    if type(gear) ~= "table" then return {} end
    local weapon = { kind = gear.kind, speed = gear.speed }
    if type(gear.stats) == "table" and finite(gear.stats[W.DPS_KEY]) then
        weapon.dps = gear.stats[W.DPS_KEY]
    end
    return weapon
end

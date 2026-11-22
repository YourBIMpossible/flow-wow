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
--   prefs   { [role] = { prefer = "slow" | "medium" | "fast" } }: which
--           speed a role likes, from class data when a pack has it. No pack
--           has it today, and none is made here; without it the line gives
--           the speed and its feel only.
--   line    { text, tone = "none" }, or nil: not a weapon, or no speed read.
--           "Speed 3.40 (slow), 60.0 damage per second; good for dps"
--   gear    what client.gear(link) answers. From takes kind, `speed` (a
--           field the client does not give yet) and the damage per second
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

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function W.Feel(speed)
    if not finite(speed) or speed <= 0 then return nil end
    if speed >= W.SLOW then return "slow" end
    if speed <= W.FAST then return "fast" end
    return "medium"
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
            if type(role) == "string" and type(pref) == "table" and FEELS[pref.prefer] then
                roles[#roles + 1] = role
            end
        end
        table.sort(roles)
        for i = 1, #roles do
            local prefer = prefs[roles[i]].prefer
            if prefer == feel then
                text = text .. "; good for " .. roles[i]
            else
                text = text .. "; " .. roles[i] .. " prefers " .. prefer
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

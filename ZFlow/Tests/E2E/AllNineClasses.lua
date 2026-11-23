local _, ns = ...
-- Lead section 208: the nine class packs side by side, on the whole add-on
-- loaded on the fake client. For each class token: the pack passes
-- ns.PackCheck, the add-on boots, the rotation icon stays hidden until the
-- rotation setting is switched on (even with an enemy targeted in a fight),
-- and the diag word has a rotation line: "switched off" while off, and once
-- on, a line that is neither "switched off" nor "no spell list for it".
-- Offline: the reads are the fake client's, not the game's. No pack is
-- changed here and no spell is set up, so nothing is said about what a
-- pack suggests; the per-class files (Tests/E2E/<Class>Rotation.lua) do that.
local tests = {}

local D = ns.RotationDriver
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local function start(class)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setClass(class); c.setFaction("Alliance"); c.setLevel(10); c.setDead(false)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    local icon
    for _, h in ipairs(c.icons) do
        if tostring(h.spec.name):find("RotationIcon", 1, true) then icon = h end
    end
    return c, addon, icon
end

-- The rotation lines the diag word prints now.
local function rotationLines(c)
    local from = #c.printed + 1
    c.slashes[ns.id.slash]("diag")
    local out = {}
    for i = from, #c.printed do
        local line = tostring(c.printed[i])
        if line:find("rotation:", 1, true) then out[#out + 1] = line end
    end
    return out
end

tests["all nine: every class token has a pack"] = function(t)
    local missing = {}
    for _, class in ipairs(CLASSES) do
        if type(ns.Packs) ~= "table" or type(ns.Packs[class]) ~= "table" then missing[#missing + 1] = class end
    end
    t.eq(table.concat(missing, ", "), "", "classes with no pack")
end

for _, class in ipairs(CLASSES) do
    tests["all nine: " .. class .. " pack passes PackCheck"] = function(t)
        local pack = ns.Packs and ns.Packs[class]
        t.ok(type(pack) == "table", class .. ": a pack")
        if type(pack) ~= "table" then return end
        local ok, problems = ns.PackCheck(pack)
        t.eq(table.concat(problems or {}, "; "), "", class .. ": no PackCheck problems")
        t.ok(ok, class .. ": PackCheck ok")
    end

    tests["all nine: " .. class .. " icon hidden until the setting is on; diag has a rotation line"] = function(t)
        local c, addon, icon = start(class)
        t.ok(icon ~= nil, class .. ": the icon was made at login")
        if icon == nil then return end

        -- Off by default, with an enemy targeted in a fight: nothing shown.
        c.setPlayerBuffs({}); c.setTarget({ exists = true, hostile = true, dead = false })
        c.setStealthed(false); c.setCombat(true)
        c.advance(2, 10)
        t.eq(addon.settings:get(D.SETTING) == true, false, class .. ": off by default")
        t.eq(icon.shown, false, class .. ": off: the icon is hidden")
        local off = rotationLines(c)
        t.eq(#off, 1, class .. ": one rotation line while off: " .. table.concat(off, " / "))
        t.ok((off[1] or ""):find("switched off", 1, true) ~= nil, class .. ": it says switched off: " .. tostring(off[1]))

        -- Switched on: the driver runs with this class pack.
        local ok, why = addon.settings:set(D.SETTING, true)
        c.advance(2, 10)
        t.ok(ok, class .. ": the setting is taken: " .. tostring(why))
        local on = rotationLines(c)
        t.ok(#on >= 1, class .. ": a rotation line while on")
        local first = on[1] or ""
        t.ok(first:find("switched off", 1, true) == nil, class .. ": on: not switched off: " .. first)
        t.ok(first:find("no spell list for it", 1, true) == nil, class .. ": on: the pack is found: " .. first)
        t.ok(first:find("not running", 1, true) == nil, class .. ": on: running: " .. first)

        -- Switched off again: hidden.
        addon.settings:set(D.SETTING, false); c.advance(2, 10)
        t.eq(icon.shown, false, class .. ": off again: hidden")
    end
end

return tests

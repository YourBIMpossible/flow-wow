local _, ns = ...
-- Lead, owner direction 2026-11-23: the add-on is for every class, not for
-- the two with a rotation pack. The whole add-on is started on the fake
-- client once per class and the class-independent words are used: diag,
-- the settings, the arrow. A class with no pack, or an empty one, must
-- start with no Lua problem and say so in words. Offline: the fake client,
-- not the game.
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
    return c, addon
end

local function word(c, w)
    local from = #c.printed + 1
    c.slashes[ns.id.slash](w)
    local out = {}
    for i = from, #c.printed do out[#out + 1] = tostring(c.printed[i]) end
    return out
end

-- The fake client leaves some reads out, and the add-on says so in a
-- problem line ("the client has no ..."). Those are not faults. Anything
-- else in the list is.
local function faults(addon)
    local out = {}
    for _, x in ipairs(addon.problems:list()) do
        local text = tostring(type(x) == "table" and (x.text or x.message or x.what or x.id or x[1]) or x)
        if not text:find("the client has no", 1, true) then out[#out + 1] = text end
    end
    return out
end

for _, class in ipairs(CLASSES) do
    tests["every class: " .. class .. " starts, and diag, settings and the arrow answer"] = function(t)
        local c, addon = start(class)
        local f = faults(addon)
        t.eq(#f, 0, class .. ": no fault at login: " .. table.concat(f, " | "))
        local diag = word(c, "diag")
        t.ok(#diag > 0, class .. ": diag prints")
        local rotation = false
        for _, line in ipairs(diag) do if line:find("rotation:", 1, true) then rotation = true end end
        t.ok(rotation, class .. ": diag has a rotation line, pack or none")
        -- A setting is taken and kept for any class.
        local ok, why = addon.settings:set(D.SETTING, true)
        c.advance(1, 5)
        t.ok(ok, class .. ": the rotation setting is taken: " .. tostring(why))
        t.eq(addon.settings:get(D.SETTING), true, class .. ": and read back")
        -- In a fight with the rotation on: still no problem.
        c.setPlayerBuffs({}); c.setTarget({ exists = true, hostile = true, dead = false }); c.setCombat(true)
        c.advance(2, 10)
        -- The arrow word answers.
        t.ok(#word(c, "way 45 60") > 0, class .. ": the way word answers")
        t.ok(#word(c, "arrow why") > 0, class .. ": the arrow says why")
        -- The same words the capture run uses for flights, the banker and settings.
        for _, feature in ipairs(ns.Capture.FEATURES) do
            for _, w in ipairs(feature.words) do
                local okWord, err = pcall(word, c, w)
                t.ok(okWord, class .. ": the word '" .. w .. "' runs: " .. tostring(err))
            end
        end
        c.advance(2, 10)
        f = faults(addon)
        t.eq(#f, 0, class .. ": no fault after diag, settings, a fight and the arrow: " .. table.concat(f, " | "))
    end
end

return tests

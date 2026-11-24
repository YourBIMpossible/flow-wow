-- The player's own saved waypoint: the text typed, the saved table and the
-- arrival rule. Pure: no client, no kernel.
-- Not tested in game.
local _, ns = ...

local N = ns.Nav
local W = N.Waypoint
local R = W.REASON

-- Bytes that cannot be typed here are built, never written with an escape.
local SOH, ESC, DEL = string.char(1), string.char(27), string.char(127)
local TAB, NL = string.char(9), string.char(10)

local HERE = { map = 1411, x = 0.1, y = 0.9 }

local function near(t, got, want, what)
    t.ok(type(got) == "number" and math.abs(got - want) < 1e-9,
        (what or "number") .. ": got " .. tostring(got) .. ", wanted " .. tostring(want))
end

local function refused(t, text, reason)
    local got, why = W.Parse(text)
    t.eq(got, nil, "taken: " .. tostring(text))
    t.eq(why, reason, "reason for: " .. tostring(text))
end

return {
    ["parse: way x y gives shares of the map and no label"] = function(t)
        local got, why = W.Parse("way 45.2 61.8")
        t.eq(why, nil)
        near(t, got.x, 0.452, "x")
        near(t, got.y, 0.618, "y")
        t.eq(got.label, nil, "a label was made up")
    end,

    ["parse: the rest is the label, as typed"] = function(t)
        t.eq(W.Parse("way 50 25 Copper vein  by the bridge").label, "Copper vein  by the bridge")
        t.eq(W.Parse("way 50 25 12 34").label, "12 34", "numbers after y are label, not a second point")
        t.eq(W.Parse("  way   50   25   inn   ").label, "inn")
    end,

    ["parse: the word way may be left out, in any case, with or without the slash"] = function(t)
        for _, text in ipairs({ "50 25 inn", "WAY 50 25 inn", "/way 50 25 inn",
                                "Way" .. TAB .. "50" .. TAB .. "25" .. TAB .. "inn" }) do
            local got, why = W.Parse(text)
            t.ok(got ~= nil, "turned down: " .. text .. " (" .. tostring(why) .. ")")
            if got then
                t.eq(got.x, 0.5, text)
                t.eq(got.y, 0.25, text)
                t.eq(got.label, "inn", text)
            end
        end
        t.eq(W.Parse("50 25 way home").label, "way home", "the word was taken out of a label")
    end,

    ["parse: the edges of the map are taken"] = function(t)
        local got = W.Parse("way 0 100")
        t.eq(got.x, 0)
        t.eq(got.y, 1)
        t.eq(W.Parse("way 100.0 0.0").x, 1)
    end,

    ["parse: no text or no numbers gives a reason"] = function(t)
        refused(t, nil, R.none)
        refused(t, 50, R.none)
        refused(t, {}, R.none)
        refused(t, "", R.none)
        refused(t, "   ", R.none)
        refused(t, "way", R.usage)
        refused(t, "way 50", R.usage)
        refused(t, "50", R.usage)
    end,

    ["parse: what is not a plain number is turned down, never read as one"] = function(t)
        refused(t, "way fifty 25", "x is not a number: fifty")
        refused(t, "way 50 north", "y is not a number: north")
        refused(t, "way -5 25", "x is not a number: -5")
        refused(t, "way +5 25", "x is not a number: +5")
        refused(t, "way 5e1 25", "x is not a number: 5e1")
        refused(t, "way 0x10 25", "x is not a number: 0x10")
        refused(t, "way .5 25", "x is not a number: .5")
        refused(t, "way 50. 25", "x is not a number: 50.")
        refused(t, "way 50 2.5.1", "y is not a number: 2.5.1")
        refused(t, "way 50 25inn", "y is not a number: 25inn")
        refused(t, "way inf 25", "x is not a number: inf")
        refused(t, "way nan 25", "x is not a number: nan")
        refused(t, "way way 50 25", "x is not a number: way")
    end,

    ["parse: a reason never repeats a token that holds a bar or a control character"] = function(t)
        refused(t, "way |cffff0000x 25", "x is not a number")
        refused(t, "way 50 a|nb", "y is not a number")
        refused(t, "way 5" .. SOH .. " 25", "x is not a number")
        refused(t, "way 50 2" .. DEL, "y is not a number")
        refused(t, "way " .. ESC .. "[0m 25", "x is not a number")
        local bad = { "|", "||", "|cffff0000red|r", "|Hitem:1|h[x]|h", "|T0:0|t", "5|", SOH, "a" .. SOH .. "b",
                      ESC .. "[2J", DEL }
        for _, token in ipairs(bad) do
            for _, text in ipairs({ "way " .. token .. " 25", "way 50 " .. token, token .. " " .. token,
                                    "way " .. token .. " " .. token .. " label" }) do
                local got, why = W.Parse(text)
                t.eq(got, nil, "taken")
                t.ok(type(why) == "string" and why ~= "", "a reason")
                t.ok(not why:find("[%c|]"), "the reason repeats what cannot be shown")
            end
        end
        -- A plain token is still named, so the player sees what was wrong.
        refused(t, "way fifty 25", "x is not a number: fifty")
    end,

    ["parse: a number off the map is turned down, never clamped"] = function(t)
        refused(t, "way 100.1 25", "x is outside 0 to 100: 100.1")
        refused(t, "way 50 101", "y is outside 0 to 100: 101")
        refused(t, "way 4520 6180", "x is outside 0 to 100: 4520")
        refused(t, "way " .. string.rep("9", 400) .. " 25", "x is outside 0 to 100: " .. string.rep("9", 400))
    end,

    ["parse: a comma is turned down, it could be a decimal or a separator"] = function(t)
        refused(t, "way 45,2 61,8", R.comma)
        refused(t, "way 45, 61,8", R.comma)
        -- "x, y" with a space after the comma is a pasted pair, not a decimal.
        t.eq(W.Parse("way 45, 61").label, nil)
        refused(t, "way 45 61,8", R.comma)
        refused(t, "way 45,61", R.usage)
        t.eq(W.Parse("way 45 61 ore, north side").label, "ore, north side", "a comma in the label")
    end,

    ["parse: a label that cannot be shown or is too long is turned down, never cut"] = function(t)
        refused(t, "way 50 25 |cffff0000red", R.label)
        refused(t, "way 50 25 a|nb", R.label)
        refused(t, "way 50 25 a" .. NL .. "b", R.label)
        refused(t, "way 50 25 a" .. TAB .. "b", R.label)
        local longest = string.rep("a", W.LABEL_MAX)
        t.eq(W.Parse("way 50 25 " .. longest).label, longest)
        refused(t, "way 50 25 " .. longest .. "a", R.long)
    end,

    ["parse: the label limit is counted, and told, in bytes"] = function(t)
        t.eq(W.LABEL_MAX, 40)
        t.eq(R.long, "the label is too long (40 bytes at most)")
        t.ok(not R.long:find("character", 1, true), "a letter outside ASCII is more than one byte")
        local e = string.char(195, 169)   -- one letter, two bytes
        local fits = string.rep(e, 20)
        t.eq(#fits, 40)
        t.eq(W.Parse("way 50 25 " .. fits).label, fits, "40 bytes, 20 letters")
        refused(t, "way 50 25 " .. fits .. "a", R.long)
        refused(t, "way 50 25 " .. string.rep(e, 21), R.long)
    end,

    ["no reason spells a product name"] = function(t)
        for key, reason in pairs(R) do
            t.ok(not reason:lower():find("flow", 1, true), "reason " .. key .. ": " .. reason)
        end
    end,

    ["set: the waypoint is saved on the map the player is on"] = function(t)
        local slot = {}
        local wp, why = W.Set(slot, HERE, "way 50 25 inn")
        t.eq(why, nil)
        t.eq(wp, { map = 1411, x = 0.5, y = 0.25, label = "inn" })
        t.ok(slot.waypoint == wp, "what was given back is not what was saved")
        t.eq(W.Get(slot), { map = 1411, x = 0.5, y = 0.25, label = "inn" })
        t.eq(HERE, { map = 1411, x = 0.1, y = 0.9 }, "the position handed in was changed")
        t.eq(W.Set({}, { map = "Elwynn" }, "way 1 2").map, "Elwynn")
    end,

    ["set: a new waypoint replaces the old one, whole"] = function(t)
        local slot = {}
        W.Set(slot, HERE, "way 50 25 inn")
        W.Set(slot, { map = 1412 }, "way 100 0")
        t.eq(slot.waypoint, { map = 1412, x = 1, y = 0 }, "the old label or map was kept")
    end,

    ["set: bad text or an unknown map saves nothing and keeps what was set"] = function(t)
        local slot = {}
        W.Set(slot, HERE, "way 50 25 inn")
        local kept = slot.waypoint
        local wp, why = W.Set(slot, HERE, "way 500 25")
        t.eq(wp, nil)
        t.eq(why, "x is outside 0 to 100: 500")
        t.ok(slot.waypoint == kept, "a refused text replaced the waypoint")
        for _, position in ipairs({ false, {}, { x = 0.5, y = 0.5 }, { map = "" }, { map = {} }, { map = 0 / 0 }, { map = true } }) do
            wp, why = W.Set(slot, position or nil, "way 10 20")
            t.eq(wp, nil, "a waypoint was set on a map that is not known")
            t.eq(why, R.map)
        end
        t.ok(slot.waypoint == kept)
        local empty = {}
        t.eq(select(2, W.Set(empty, nil, "way 10 20")), R.map)
        t.eq(empty, {}, "something was saved")
        t.eq(select(2, W.Set(nil, HERE, "way 10 20")), R.slot)
        t.eq(select(2, W.Set("slot", HERE, "way 10 20")), R.slot)
    end,

    ["get: nothing set and damaged saved data are told apart, and neither is a waypoint"] = function(t)
        local wp, why = W.Get({})
        t.eq(wp, nil)
        t.eq(why, R.unset)
        t.eq(select(2, W.Get(nil)), R.slot)
        local bad = {
            "text", 5, {}, { map = 1411 }, { map = 1411, x = 0.5 }, { x = 0.5, y = 0.5 },
            { map = 1411, x = "0.5", y = 0.5 }, { map = 1411, x = 1.5, y = 0.5 },
            { map = 1411, x = 0.5, y = -0.1 }, { map = 1411, x = 0 / 0, y = 0.5 },
            { map = 1411, x = 0.5, y = math.huge }, { map = 1411, x = 0.5, y = 0.5, label = 7 },
            { map = {}, x = 0.5, y = 0.5 },
        }
        for i, saved in ipairs(bad) do
            local slot = { waypoint = saved }
            wp, why = W.Get(slot)
            t.eq(wp, nil, "damaged waypoint " .. i .. " was used")
            t.eq(why, R.damaged, "damaged waypoint " .. i)
            t.ok(slot.waypoint == saved, "a read changed the saved data")
            t.eq(W.Step(slot, HERE, { cont = 1 }), nil, "damaged waypoint " .. i .. " gave a step")
            t.eq(select(2, W.Arrive(slot, 0)), R.damaged)
            t.ok(slot.waypoint == saved, "arrival cleared data it could not read")
        end
    end,

    ["clear: says whether a waypoint was there"] = function(t)
        local slot = { other = 1 }
        t.eq(W.Clear(slot), false)
        W.Set(slot, HERE, "way 50 25")
        t.eq(W.Clear(slot), true)
        t.eq(slot, { other = 1 }, "the waypoint is still there, or more than it was removed")
        t.eq(W.Clear(slot), false)
        t.eq(W.Clear(nil), false)
        slot.waypoint = "damaged"
        t.eq(W.Clear(slot), true, "damaged saved data cannot be removed")
        t.eq(slot.waypoint, nil)
    end,

    ["step: the shape the guide takes, with the near distance as its radius"] = function(t)
        local slot = {}
        W.Set(slot, HERE, "way 50 25 inn")
        t.eq(W.Step(slot, HERE, { cont = 1, zone = 1411 }),
            { label = "inn", place = { cont = 1, map = 1411, x = 0.5, y = 0.25 }, radius = W.NEAR })
        W.Set(slot, HERE, "way 50 25")
        t.eq(W.Step(slot, HERE, { cont = 1 }).label, N.WAYPOINT_LABEL, "no label typed: the plain one")
        t.eq(W.Step({}), nil)
        t.eq(W.Step(nil), nil)
        t.ok(slot.waypoint ~= nil, "making a step cleared the waypoint")
    end,

    ["step: the continent is the player's only on the player's own map"] = function(t)
        local slot = {}
        W.Set(slot, HERE, "way 50 25")
        t.eq(W.Step(slot, { map = 1412 }, { cont = 1 }).place.cont, nil, "a continent was borrowed for another map")
        t.eq(W.Step(slot, nil, { cont = 1 }).place.cont, nil)
        t.eq(W.Step(slot, HERE, nil).place.cont, nil)
        t.eq(W.Step(slot, HERE, {}).place.cont, nil)
        t.eq(W.Step(slot).place, { map = 1411, x = 0.5, y = 0.25 })
    end,

    ["arrive: within the near distance the waypoint is cleared and says arrived"] = function(t)
        for _, distance in ipairs({ 0, W.NEAR / 2, W.NEAR }) do
            local slot = { other = 1 }
            W.Set(slot, HERE, "way 50 25 inn")
            local said, why = W.Arrive(slot, distance)
            t.eq(said, "arrived", "at " .. distance)
            t.eq(why, nil)
            t.eq(slot, { other = 1 }, "the waypoint was not cleared, or more than it was")
            said, why = W.Arrive(slot, distance)
            t.eq(said, nil, "arrived twice")
            t.eq(why, R.unset)
        end
        t.eq(W.ARRIVED, "arrived")
    end,

    ["arrive: farther than the near distance keeps the waypoint"] = function(t)
        local slot = {}
        W.Set(slot, HERE, "way 50 25 inn")
        local kept = slot.waypoint
        for _, distance in ipairs({ W.NEAR + 0.001, 40, 1e9 }) do
            local said, why = W.Arrive(slot, distance)
            t.eq(said, nil, "arrived at " .. distance)
            t.eq(why, R.far)
            t.ok(slot.waypoint == kept)
        end
    end,

    ["arrive: a distance that is not known is never an arrival"] = function(t)
        local slot = {}
        W.Set(slot, HERE, "way 50 25")
        local kept = slot.waypoint
        for _, distance in ipairs({ false, "5", {}, 0 / 0, math.huge, -math.huge, -1 }) do
            local said, why = W.Arrive(slot, distance or nil)
            t.eq(said, nil, "arrived on " .. tostring(distance))
            t.eq(why, R.distance)
            t.ok(slot.waypoint == kept, "cleared on " .. tostring(distance))
        end
        t.eq(select(2, W.Arrive({}, 0)), R.unset)
        t.eq(select(2, W.Arrive(nil, 0)), R.slot)
    end,

    ["the near distance is a positive number of yards"] = function(t)
        t.ok(type(W.NEAR) == "number" and W.NEAR > 0 and W.NEAR < math.huge)
    end,

    ["slot: one table per character under state.nav, asked of the store as a method"] = function(t)
        t.eq(W.SCOPE, "char")
        t.eq(W.PATH, "state.nav")
        local saved, asked = {}, {}
        local store = { table = function(self, scope, path)
            asked[#asked + 1] = { self = self, scope = scope, path = path }
            return saved
        end }
        t.ok(W.Slot(store) == saved)
        t.eq(#asked, 1)
        t.ok(asked[1].self == store, "the store was not called as a method")
        t.eq(asked[1].scope, "char")
        t.eq(asked[1].path, "state.nav", "what changes while playing is kept under state")
        t.eq(W.Slot(nil), nil)
        t.eq(W.Slot({}), nil)
        t.eq(W.Slot({ table = function() return nil end }), nil, "a store that gives no table gives no slot")
        t.eq(W.Slot({ table = function() return "nav" end }), nil)
    end,
}

-- GK-2, GK-3, GK-4 (MyBuddy's gather-key review, lead sections 237, 238):
-- client.anyTracking() leaves out the town kinds (Flight Master, Repair,
-- Mailbox: the client's "townsfolk" or "other" type), and an entry whose
-- active is not given or hidden makes the answer "not known" (nil), never
-- "off", as Flow's X.AnyTracked (Modules/Rotation/Actions.lua:119-133,
-- Compat.lua:596-610). On the real boundary with a stand-in for C_Minimap,
-- and on the fake. No game client is involved; every call named is a first
-- guess not seen in game.
local _, ns = ...

local SECRET = setmetatable({}, { __tostring = function() return "(a hidden value)" end })

-- C_Minimap as 1.60.1 gives it: GetTrackingInfo(i) -> { name, active, type }.
local function env(entries)
    local M = {}
    function M.GetNumTrackingTypes() return #entries end
    function M.GetTrackingInfo(i) return entries[i] end
    return {
        C_Minimap = M,
        issecretvalue = function(v)
            if v == nil then error("issecretvalue: nil") end
            return rawequal(v, SECRET)
        end,
    }
end

local function any(entries) return ns.make.client(env(entries)).anyTracking() end

return {
    ["tracking GK-2: a town kind that is on does not count as your tracking"] = function(t)
        t.eq(any({ { name = "Flight Master", active = true, type = "townsfolk" },
                   { name = "Find Minerals", active = false, type = "spell" } }), false, "townsfolk")
        t.eq(any({ { name = "Repair", active = true, type = "other" },
                   { name = "Find Herbs", active = false, type = "spell" } }), false, "other")
        t.eq(any({ { name = "Repair", active = true, type = "other" } }), false, "only town kinds, all on")
    end,

    ["tracking GK-2: a spell you chose that is on still counts"] = function(t)
        t.eq(any({ { name = "Flight Master", active = true, type = "townsfolk" },
                   { name = "Find Fish", active = true, type = "spell" } }), true)
        t.eq(any({ { name = "Track Beasts", active = true } }), true, "no type given: counted as yours, as Flow")
    end,

    ["tracking GK-3: an entry whose active is not given or hidden is not known, never off"] = function(t)
        t.eq(any({ { name = "Find Herbs", type = "spell" } }), nil, "active not given")
        t.eq(any({ { name = "Find Herbs", active = SECRET, type = "spell" } }), nil, "active hidden")
        t.eq(any({ { name = "Find Herbs", active = SECRET, type = "spell" },
                   { name = "Find Fish", active = true, type = "spell" } }), true, "one known on still answers yes")
        t.eq(any({ { name = "Repair", type = "other" },
                   { name = "Find Herbs", active = false, type = "spell" } }), false,
            "a town kind not known does not make it unknown")
    end,

    ["tracking: an empty list is none on; no C_Minimap and no texture is not known"] = function(t)
        t.eq(any({}), false)
        t.eq(ns.make.client({}).anyTracking(), nil)
    end,

    ["tracking GK-4: the fake takes town and hidden entries and answers the same way"] = function(t)
        local c = ns.make.fakeClient()
        t.eq(c.anyTracking(), nil, "nothing set: not known")
        c.setTrackingList({ { name = "Flight Master", active = true, town = true },
                            { name = "Find Minerals", active = false } })
        t.eq(c.anyTracking(), false, "a town kind on is not yours")
        c.setTrackingList({ { name = "Find Herbs", active = nil } })
        t.eq(c.anyTracking(), nil, "active not known")
        c.setTrackingList({ { name = "Find Herbs" }, { name = "Find Fish", active = true } })
        t.eq(c.anyTracking(), true)
        c.setTrackingList(nil)
        c.setTracking("Find Minerals", true)
        t.eq(c.anyTracking(), true, "the old setter still works when no list is set")
    end,
}

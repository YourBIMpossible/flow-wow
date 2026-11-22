-- S26 trainer spell lists (A-D): what each trainer window offered, kept per
-- character for later. Pure: the reading comes in as the CLIENT NEED read
-- c.trainerServices() would give it; no game client.
local _, ns = ...

local UNKNOWN = "price unknown—check trainer"

local function reading(rows, npc, profession)
    return { npc = npc or "Loganaar", profession = profession, rows = rows }
end

local function rows()
    return {
        { name = "Moonfire", rank = "Rank 2", state = "available", cost = 150, level = 10 },
        { name = "Wrath", rank = "Rank 3", state = "unavailable", level = 14 },
        { name = "Rejuvenation", rank = "Rank 1", state = "known", cost = 100, level = 4 },
    }
end

return {
    ["record: a trainer's list is kept under its npc, with the time"] = function(t)
        local lists = ns.TrainerList.Record({}, reading(rows()), 1000)
        local e = lists["Loganaar|class"]
        t.ok(e, "kept under npc|class")
        t.eq(e.npc, "Loganaar")
        t.eq(e.seen, 1000)
        t.eq(#e.rows, 3)
        t.eq(e.rows[1], { name = "Moonfire", rank = "Rank 2", state = "available", cost = 150, level = 10 })
    end,

    ["record: a profession trainer is a separate entry"] = function(t)
        local lists = ns.TrainerList.Record({}, reading({ { name = "Herb Gathering", state = "known", level = 5 } }, "Mylini", "Herbalism"), 5)
        t.ok(lists["Mylini|Herbalism"], "npc|profession")
        t.eq(lists["Mylini|Herbalism"].profession, "Herbalism")
    end,

    ["record: a new visit replaces the trainer's whole list, others stay"] = function(t)
        local lists = ns.TrainerList.Record({}, reading(rows()), 1)
        lists = ns.TrainerList.Record(lists, reading({ { name = "Moonfire", rank = "Rank 2", state = "known", cost = 150, level = 10 } }), 2)
        t.eq(#lists["Loganaar|class"].rows, 1, "not merged row by row")
        t.eq(lists["Loganaar|class"].rows[1].state, "known")
        lists = ns.TrainerList.Record(lists, reading(rows(), "Other"), 3)
        t.ok(lists["Loganaar|class"] and lists["Other|class"], "both kept")
    end,

    ["record: an unreadable row drops the whole reading, never a shorter list"] = function(t)
        local bad = rows()
        bad[2] = { rank = "Rank 3", state = "available" } -- no name
        local before = { ["Loganaar|class"] = { npc = "Loganaar", seen = 1, rows = {} } }
        local lists = ns.TrainerList.Record(before, reading(bad), 9)
        t.eq(lists["Loganaar|class"].seen, 1, "old entry untouched")
        t.eq(ns.TrainerList.Record({}, nil, 1), {})
        t.eq(ns.TrainerList.Record({}, reading(rows(), ""), 1), {}, "no npc name")
        t.eq(ns.TrainerList.Record({}, reading({ { name = "X", state = "maybe" } }), 1), {}, "unknown state")
    end,

    ["record: fields the client did not give stay nil, never guessed"] = function(t)
        local lists = ns.TrainerList.Record({}, reading({ { name = "Wrath", state = "available" } }), nil)
        local r = lists["Loganaar|class"].rows[1]
        t.eq(r.rank, nil); t.eq(r.cost, nil); t.eq(r.level, nil)
        t.eq(lists["Loganaar|class"].seen, nil, "no clock, no date")
    end,

    ["lines: rank, level and cost; unknown cost uses the trainer wording"] = function(t)
        local e = ns.TrainerList.Record({}, reading(rows()), 1)["Loganaar|class"]
        t.eq(ns.TrainerList.Lines(e), {
            "Moonfire (Rank 2), level 10, 1s 50c: can learn",
            "Wrath (Rank 3), level 14, " .. UNKNOWN .. ": not yet",
            "Rejuvenation (Rank 1), level 4, 1s: known",
        })
    end,

    ["lines: no rank or level is left out, not filled in"] = function(t)
        local e = ns.TrainerList.Record({}, reading({ { name = "Wrath", state = "available" } }), 1)["Loganaar|class"]
        t.eq(ns.TrainerList.Lines(e), { "Wrath, " .. UNKNOWN .. ": can learn" })
        t.eq(ns.TrainerList.Lines(nil), {})
    end,

    ["the unknown-cost text is exactly the F-085 trainer wording"] = function(t)
        t.eq(ns.TrainerList.PRICE_UNKNOWN, UNKNOWN)
    end,
}

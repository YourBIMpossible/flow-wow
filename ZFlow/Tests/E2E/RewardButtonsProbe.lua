local _, ns = ...
-- G14 probe (lead section 275, RM-1): which choice each quest reward button
-- shows. The mark assumes choice i is button i, unseen in game; this probe
-- records, when a quest's rewards open, each reward button's own number
-- (GetID) and kind (its `type` field) in the account's diag record
-- "diag.rewardButtons", so a capture answers the question. It changes no
-- mark. Whole add-on on a fake client. Per section 236: the read absent,
-- a read that raises then recovers, a reload. Not tested in game.
local tests = {}

local function bootProbe(account)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, account or {})
    c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR")
    c.setLevel(10)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function probeRecord(c)
    local db = c.saved(ns.id.accountDB)
    if type(db.diag) ~= "table" then return nil end
    return db.diag.rewardButtons
end

-- Fails before: Core/ClientFake.lua has no setRewardButtons (an error),
-- and nothing writes diag.rewardButtons (probeRecord nil).
tests["reward buttons probe: the buttons' numbers and kinds are saved when rewards open"] = function(t)
    local c = bootProbe()
    c.setRewardButtons({ { index = 1, id = 2, kind = "choice" }, { index = 2, id = 1, kind = "choice" } })
    c.fire("QUEST_COMPLETE")
    local r = probeRecord(c)
    t.ok(type(r) == "table", "a record")
    t.eq(r and r.rows, { { index = 1, id = 2, kind = "choice" }, { index = 2, id = 1, kind = "choice" } })
    t.eq(r and r.seen, 1, "one reward window seen")
end

-- Fails before: setRewardButtons is absent.
tests["reward buttons probe: no buttons found saves that, not a guess"] = function(t)
    local c = bootProbe()
    c.setRewardButtons(nil)
    c.fire("QUEST_COMPLETE")
    local r = probeRecord(c)
    t.eq(r and r.found, false, "found = false")
    t.eq(r and r.rows, nil, "no rows")
end

-- Fails before: setRewardButtons is absent.
tests["reward buttons probe: a read that raises, then recovers"] = function(t)
    local c, addon = bootProbe()
    local before = addon.problems:count()
    local real = c.rewardButtons
    c.rewardButtons = function() error("Wolves") end
    c.fire("QUEST_COMPLETE")
    c.fire("QUEST_FINISHED")
    t.eq(probeRecord(c), nil, "nothing saved from a failed read")
    t.ok(addon.problems:count() >= before, "the add-on carries on")
    c.rewardButtons = real
    c.setRewardButtons({ { index = 1, id = 1, kind = "choice" } })
    c.fire("QUEST_COMPLETE")
    local r = probeRecord(c)
    t.eq(r and r.rows, { { index = 1, id = 1, kind = "choice" } }, "saved once it recovers")
end

-- Fails before: setRewardButtons is absent.
tests["reward buttons probe: the record survives a reload and counts on"] = function(t)
    local c = bootProbe()
    c.setRewardButtons({ { index = 1, id = 1, kind = "choice" } })
    c.fire("QUEST_COMPLETE")
    c.fire("QUEST_FINISHED")
    local again = bootProbe(c.saved(ns.id.accountDB))
    again.setRewardButtons({ { index = 1, id = 1, kind = "choice" } })
    again.fire("QUEST_COMPLETE")
    local r = probeRecord(again)
    t.eq(r and r.seen, 2, "two windows seen over the reload")
end

return tests

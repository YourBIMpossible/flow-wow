local _, ns = ...

-- Lead section 347 (P-PARTY item b): a class with no group buff or no cure
-- for others says so in words (groupsNone, dispelsNone), not a gap; the
-- group step shows that reason; PackCheck keeps the two honest.

local CLASSES = { "HUNTER", "ROGUE", "WARLOCK", "WARRIOR", "SHAMAN" }

local function words(v) return type(v) == "string" and v:find("%a") ~= nil end

local tests = {}

tests["group none: each empty group or cure row of the five classes has a reason"] = function(t)
    for _, class in ipairs(CLASSES) do
        local pack = ns.Packs[class]
        t.ok(type(pack) == "table", class .. " pack")
        if type(pack) == "table" then
            if #pack.groups == 0 then t.ok(words(pack.groupsNone), class .. ": groupsNone gives the reason") end
            if #pack.dispels == 0 then t.ok(words(pack.dispelsNone), class .. ": dispelsNone gives the reason") end
            local ok, problems = ns.PackCheck(pack)
            t.ok(ok, class .. " passes PackCheck: " .. table.concat(problems or {}, "; "))
        end
    end
end

tests["group none: PackCheck reports a reason that is not words, or a reason beside rows"] = function(t)
    local pack = {}
    for k, v in pairs(ns.Packs.ROGUE) do pack[k] = v end
    pack.groupsNone = 5
    local _, problems = ns.PackCheck(pack)
    local joined = table.concat(problems or {}, "; ")
    t.ok(joined:find("groupsNone", 1, true) ~= nil, "a reason that is not words: " .. joined)
    pack.groupsNone = "nothing for others"
    pack.groups = { { spell = "Kick", who = "all", evidence = "first guess" } }
    _, problems = ns.PackCheck(pack)
    joined = table.concat(problems or {}, "; ")
    t.ok(joined:find("groupsNone", 1, true) ~= nil, "a reason beside rows: " .. joined)
end

tests["group none: the group step shows the pack's reason when it has no rows"] = function(t)
    local s = { groupOn = true, inCombat = false, hostile = false, resting = false,
        party = { { unit = "party1", name = "A", class = "WARRIOR", alive = true } } }
    local pack = { groups = {}, dispels = {}, groupsNone = "nothing of yours reaches the group" }
    local got, note = ns.PartyGroup.Step(s, pack, {})
    t.eq(got, nil, "no suggestion")
    t.eq(note, "nothing of yours reaches the group", "the reason is the note")
end

return tests

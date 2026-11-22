-- Rank-up reminder (A-E): a higher rank of a spell the player knows, at
-- their level, at a trainer they have seen, gets one advisor prompt; it is
-- removed once the rank is learned. Pure: lists as A-D stores them, a fake
-- advisor with U-A's Add/Remove/List.
local _, ns = ...

local function fakeAdvisor()
    local items, a = {}, {}
    function a.Add(id, text, priority)
        if type(id) ~= "string" or id == "" or type(text) ~= "string" or text == "" then return false, "bad args" end
        items[id] = { id = id, text = text, priority = priority or 0 }
        return true
    end
    function a.Remove(id)
        if items[id] then items[id] = nil; return true end
        return false
    end
    function a.List()
        local out = {}
        for _, v in pairs(items) do out[#out + 1] = v end
        table.sort(out, function(x, y) return x.id < y.id end)
        return out
    end
    return a
end

local function lists(moonfireState)
    return {
        ["Loganaar|class"] = { npc = "Loganaar", rows = {
            { name = "Moonfire", rank = "Rank 1", state = "known", level = 4 },
            { name = "Moonfire", rank = "Rank 2", state = moonfireState or "available", cost = 150, level = 10 },
            { name = "Wrath", rank = "Rank 2", state = "available", level = 14 },
            { name = "Thorns", rank = "Rank 1", state = "available", level = 6 },
        } },
    }
end

return {
    ["prompts: a higher rank of a known spell at the player's level"] = function(t)
        local p = ns.TrainerListRankUp.Prompts(lists(), {}, 10)
        t.eq(#p, 1, "Wrath is above level 10; Thorns is not known at any rank")
        t.eq(p[1].id, "aps.rankup.Moonfire")
        t.eq(p[1].text, "Moonfire Rank 2 can be learned at Loganaar.")
    end,

    ["prompts: a rank the spellbook already has gives nothing"] = function(t)
        t.eq(ns.TrainerListRankUp.Prompts(lists(), { Moonfire = 2 }, 10), {})
    end,

    ["prompts: no player level, a row without a level or a rank that is not 'Rank N' gives nothing"] = function(t)
        t.eq(ns.TrainerListRankUp.Prompts(lists(), {}, nil), {})
        local l = lists()
        l["Loganaar|class"].rows[2].level = nil
        t.eq(ns.TrainerListRankUp.Prompts(l, {}, 10), {})
        l = lists()
        l["Loganaar|class"].rows[2].rank = "Superior"
        t.eq(ns.TrainerListRankUp.Prompts(l, {}, 10), {})
    end,

    ["prompts: the highest learnable rank only, trainers named in order"] = function(t)
        local l = lists()
        table.insert(l["Loganaar|class"].rows, { name = "Moonfire", rank = "Rank 3", state = "available", level = 10 })
        l["Ayanna|class"] = { npc = "Ayanna", rows = { { name = "Moonfire", rank = "Rank 3", state = "available", level = 10 } } }
        local p = ns.TrainerListRankUp.Prompts(l, {}, 10)
        t.eq(p[1].text, "Moonfire Rank 3 can be learned at Ayanna or Loganaar.")
    end,

    ["sync: added, then removed once the rank is learned"] = function(t)
        local a = fakeAdvisor()
        local shown = ns.TrainerListRankUp.Sync(a, lists(), {}, 10, nil)
        t.eq(#a.List(), 1)
        t.eq(a.List()[1].priority, ns.TrainerListRankUp.PRIORITY)
        shown = ns.TrainerListRankUp.Sync(a, lists("known"), {}, 10, shown)
        t.eq(a.List(), {}, "trainer now lists Rank 2 as known")
        t.eq(shown, {})
    end,

    ["sync: never removes a prompt it did not add; no advisor is not an error"] = function(t)
        local a = fakeAdvisor()
        a.Add("aps.prof.Cooking", "Cooking is at its cap (75/75). Trainer seen: X.", 1)
        ns.TrainerListRankUp.Sync(a, {}, {}, 10, { ["aps.rankup.Moonfire"] = true })
        t.eq(#a.List(), 1)
        local ok, shown = pcall(ns.TrainerListRankUp.Sync, nil, lists(), {}, 10, nil)
        t.ok(ok); t.eq(shown, {})
    end,

    ["refresh: the player's level comes from client.level, one read"] = function(t)
        local a, asked = fakeAdvisor(), 0
        local client = { level = function() asked = asked + 1; return 10 end }
        local shown = ns.TrainerListRankUp.Refresh(client, a, lists(), {}, nil)
        t.eq(asked, 1, "client.level read once")
        t.eq(shown, { ["aps.rankup.Moonfire"] = true })
        t.eq(a.List()[1].text, "Moonfire Rank 2 can be learned at Loganaar.")
    end,

    ["refresh: no client.level, or no answer, removes this module's prompts"] = function(t)
        local a = fakeAdvisor()
        local shown = ns.TrainerListRankUp.Refresh({ level = function() return 10 end }, a, lists(), {}, nil)
        shown = ns.TrainerListRankUp.Refresh({ level = function() return nil end }, a, lists(), {}, shown)
        t.eq(a.List(), {}, "level not known: nothing claimed")
        t.eq(ns.TrainerListRankUp.Refresh({}, a, lists(), {}, nil), {})
        t.eq(ns.TrainerListRankUp.Refresh(nil, a, lists(), {}, nil), {})
    end,
}

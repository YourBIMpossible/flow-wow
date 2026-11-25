-- The profession reminder card (G18): a profession at its cap with a known
-- trainer gets one advisor prompt. Pure: readings and trainers come in as
-- ProfSeen saves them; the advisor is a fake with U-A's Add/Remove/List.
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
        for _, v in pairs(items) do out[#out + 1] = { id = v.id, text = v.text, priority = v.priority } end
        table.sort(out, function(x, y) return x.id < y.id end)
        return out
    end
    return a
end

local function readings()
    return {
        Cooking = { line = 185, skill = 75, max = 75 },
        Mining = { line = 186, skill = 40, max = 75 },
        Tailoring = { line = 197, skill = 150, max = 150 },
    }
end

local function npcs()
    return {
        ["Daryl Riknussun"] = { roles = { trainer = true }, trains = { Cooking = true }, factions = { Alliance = true } },
        ["Brombar Higgleby"] = { roles = { trainer = true }, trains = { Mining = true }, factions = { Alliance = true } },
    }
end

return {
    ["prompts: only a profession at its cap with a known trainer"] = function(t)
        local p = ns.ProfCard.Prompts(readings(), npcs(), "Alliance")
        t.eq(#p, 1, "Mining is below its cap; Tailoring has no known trainer")
        t.eq(p[1].id, "aps.prof.Cooking")
        t.eq(p[1].text, "Cooking is at its cap (75/75). Trainer seen: Daryl Riknussun.")
    end,

    ["prompts: several trainers are named in order, the rest counted"] = function(t)
        local n = npcs()
        n["Zed"] = { trains = { Cooking = true }, factions = { Alliance = true } }
        n["Alda"] = { trains = { Cooking = true }, factions = { Alliance = true } }
        local p = ns.ProfCard.Prompts(readings(), n, "Alliance")
        t.eq(p[1].text, "Cooking is at its cap (75/75). Trainer seen: Alda, and 2 more.")
    end,

    ["prompts: missing or broken data gives no prompt, never a guess"] = function(t)
        t.eq(ns.ProfCard.Prompts(nil, npcs(), "Alliance"), {})
        t.eq(ns.ProfCard.Prompts(readings(), nil, "Alliance"), {})
        t.eq(ns.ProfCard.Prompts({ Cooking = { skill = "75", max = 75 } }, npcs(), "Alliance"), {})
        t.eq(ns.ProfCard.Prompts({ Cooking = { skill = 0, max = 0 } }, npcs(), "Alliance"), {})
    end,

    ["sync: adds the prompt to the advisor and removes it once the cap rises"] = function(t)
        local a = fakeAdvisor()
        local shown = ns.ProfCard.Sync(a, readings(), npcs(), "Alliance", nil)
        t.eq(a.List(), { { id = "aps.prof.Cooking", text = "Cooking is at its cap (75/75). Trainer seen: Daryl Riknussun.", priority = ns.ProfCard.PRIORITY } })
        t.eq(shown, { ["aps.prof.Cooking"] = true })
        local r = readings()
        r.Cooking = { line = 185, skill = 75, max = 150 }
        shown = ns.ProfCard.Sync(a, r, npcs(), "Alliance", shown)
        t.eq(a.List(), {}, "removed once no longer at its cap")
        t.eq(shown, {})
    end,

    ["sync: never removes an advisor prompt it did not add"] = function(t)
        local a = fakeAdvisor()
        a.Add("someone.else", "Repair your gear.", 5)
        ns.ProfCard.Sync(a, {}, npcs(), "Alliance", { ["aps.prof.Cooking"] = true })
        t.eq(#a.List(), 1)
        t.eq(a.List()[1].id, "someone.else")
    end,

    ["sync: no advisor is not an error"] = function(t)
        local ok, shown = pcall(ns.ProfCard.Sync, nil, readings(), npcs(), "Alliance", nil)
        t.ok(ok, "no error")
        t.eq(shown, {})
    end,

    ["faction: a trainer seen only by the other faction is not named"] = function(t)
        local n = npcs()
        n["Daryl Riknussun"].factions = { Horde = true }
        t.eq(ns.ProfCard.Prompts(readings(), n, "Alliance"), {})
    end,

    ["faction: an unknown player faction names no trainer"] = function(t)
        t.eq(ns.ProfCard.Prompts(readings(), npcs(), nil), {})
        t.eq(ns.ProfCard.Prompts(readings(), npcs(), ""), {})
    end,

    ["faction: a trainer with no saved factions is not named"] = function(t)
        local n = npcs()
        n["Daryl Riknussun"].factions = nil
        t.eq(ns.ProfCard.Prompts(readings(), n, "Alliance"), {})
        n["Daryl Riknussun"].factions = { Alliance = "yes" }
        t.eq(ns.ProfCard.Prompts(readings(), n, "Alliance"), {}, "only true counts")
    end,

    ["faction: of several trainers, only same-faction ones are named and counted"] = function(t)
        local n = npcs()
        n["Alda"] = { trains = { Cooking = true }, factions = { Horde = true } }
        n["Zed"] = { trains = { Cooking = true }, factions = { Alliance = true, Horde = true } }
        local p = ns.ProfCard.Prompts(readings(), n, "Alliance")
        t.eq(p[1].text, "Cooking is at its cap (75/75). Trainer seen: Daryl Riknussun, and 1 more.")
    end,

    -- Parity row C-50 (lead section 668), as Flow's Modules/Advisor/
    -- Builtins.lua professions source (:304-358): the next rank, from a
    -- trainer list the player opened, said before the cap when it can be
    -- learned, and when your level has reached it but your skill has not.
    -- The level and skill a rank needs are the trainer window's own numbers.
    -- Fails before: only the cap is said.
    ["next rank: can be learned before the cap, named with its trainer and cost"] = function(t)
        local lists = { k = { npc = "Brombar Higgleby", profession = "Mining", rows = {
            { name = "Mining", rank = "Journeyman", state = "available", cost = 500, level = 10, skill = 50 } } } }
        local r = readings()
        r.Mining.skill = 55
        local p = ns.ProfCard.Prompts(r, npcs(), "Alliance", lists, 12)
        local mining
        for _, x in ipairs(p) do if x.id == "aps.prof.Mining" then mining = x end end
        t.ok(mining ~= nil, "a prompt for Mining")
        t.eq(mining and mining.text,
            "Mining 55/75: you can learn Journeyman Mining now from Brombar Higgleby (" .. ns.Prices.Coin(500) .. ").")
    end,

    ["next rank: your level has reached it, your skill has not"] = function(t)
        local lists = { k = { npc = "Brombar Higgleby", profession = "Mining", rows = {
            { name = "Mining", rank = "Journeyman", state = "unavailable", cost = 500, level = 10, skill = 50 } } } }
        local p = ns.ProfCard.Prompts(readings(), npcs(), "Alliance", lists, 14)
        local mining
        for _, x in ipairs(p) do if x.id == "aps.prof.Mining" then mining = x end end
        t.eq(mining and mining.text,
            "Mining is 40, behind your level: Journeyman Mining needs 50, and you are past its level 10.")
    end,

    ["next rank: below its level, or no level or skill read, nothing is said"] = function(t)
        local row = { name = "Mining", rank = "Journeyman", state = "unavailable", cost = 500, level = 10, skill = 50 }
        local lists = { k = { npc = "Brombar Higgleby", profession = "Mining", rows = { row } } }
        local function mining(level)
            for _, x in ipairs(ns.ProfCard.Prompts(readings(), npcs(), "Alliance", lists, level)) do
                if x.id == "aps.prof.Mining" then return x end
            end
            return nil
        end
        t.eq(mining(8), nil, "below the rank's level: not behind")
        t.eq(mining(nil), nil, "your level not read")
        row.skill = nil
        t.eq(mining(14), nil, "the skill it needs not read")
        row.skill, row.level = 50, nil
        t.eq(mining(14), nil, "the level it needs not read")
    end,

    ["next rank: at the cap the cap prompt is the one, with the rank's price as before"] = function(t)
        local lists = { k = { npc = "Daryl Riknussun", profession = "Cooking", rows = {
            { name = "Cooking", rank = "Journeyman", state = "available", cost = 500, level = 10, skill = 50 } } } }
        local p = ns.ProfCard.Prompts(readings(), npcs(), "Alliance", lists, 12)
        local cooking
        for _, x in ipairs(p) do if x.id == "aps.prof.Cooking" then cooking = x end end
        t.eq(cooking and cooking.text, "Cooking is at its cap (75/75). Trainer seen: Daryl Riknussun. Journeyman costs "
            .. ns.Prices.Coin(500) .. ".")
    end,

    ["next rank: one prompt for each profession, and a known rank is no next rank"] = function(t)
        local lists = { k = { npc = "Brombar Higgleby", profession = "Mining", rows = {
            { name = "Mining", rank = "Journeyman", state = "known", cost = 500, level = 10, skill = 50 } } } }
        local r = readings()
        r.Mining.skill = 55
        t.eq(#ns.ProfCard.Prompts(r, npcs(), "Alliance", lists, 12), 1, "only Cooking, at its cap")
    end,
}

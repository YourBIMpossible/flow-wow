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
        ["Daryl Riknussun"] = { roles = { trainer = true }, trains = { Cooking = true } },
        ["Brombar Higgleby"] = { roles = { trainer = true }, trains = { Mining = true } },
    }
end

return {
    ["prompts: only a profession at its cap with a known trainer"] = function(t)
        local p = ns.ProfCard.Prompts(readings(), npcs())
        t.eq(#p, 1, "Mining is below its cap; Tailoring has no known trainer")
        t.eq(p[1].id, "aps.prof.Cooking")
        t.eq(p[1].text, "Cooking is at its cap (75/75). Trainer seen: Daryl Riknussun.")
    end,

    ["prompts: several trainers are named in order, the rest counted"] = function(t)
        local n = npcs()
        n["Zed"] = { trains = { Cooking = true } }
        n["Alda"] = { trains = { Cooking = true } }
        local p = ns.ProfCard.Prompts(readings(), n)
        t.eq(p[1].text, "Cooking is at its cap (75/75). Trainer seen: Alda, and 2 more.")
    end,

    ["prompts: missing or broken data gives no prompt, never a guess"] = function(t)
        t.eq(ns.ProfCard.Prompts(nil, npcs()), {})
        t.eq(ns.ProfCard.Prompts(readings(), nil), {})
        t.eq(ns.ProfCard.Prompts({ Cooking = { skill = "75", max = 75 } }, npcs()), {})
        t.eq(ns.ProfCard.Prompts({ Cooking = { skill = 0, max = 0 } }, npcs()), {})
    end,

    ["sync: adds the prompt to the advisor and removes it once the cap rises"] = function(t)
        local a = fakeAdvisor()
        local shown = ns.ProfCard.Sync(a, readings(), npcs(), nil)
        t.eq(a.List(), { { id = "aps.prof.Cooking", text = "Cooking is at its cap (75/75). Trainer seen: Daryl Riknussun.", priority = ns.ProfCard.PRIORITY } })
        t.eq(shown, { ["aps.prof.Cooking"] = true })
        local r = readings()
        r.Cooking = { line = 185, skill = 75, max = 150 }
        shown = ns.ProfCard.Sync(a, r, npcs(), shown)
        t.eq(a.List(), {}, "removed once no longer at its cap")
        t.eq(shown, {})
    end,

    ["sync: never removes an advisor prompt it did not add"] = function(t)
        local a = fakeAdvisor()
        a.Add("someone.else", "Repair your gear.", 5)
        ns.ProfCard.Sync(a, {}, npcs(), { ["aps.prof.Cooking"] = true })
        t.eq(#a.List(), 1)
        t.eq(a.List()[1].id, "someone.else")
    end,

    ["sync: no advisor is not an error"] = function(t)
        local ok, shown = pcall(ns.ProfCard.Sync, nil, readings(), npcs(), nil)
        t.ok(ok, "no error")
        t.eq(shown, {})
    end,
}

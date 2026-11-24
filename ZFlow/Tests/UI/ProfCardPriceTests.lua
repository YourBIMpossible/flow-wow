-- P-PROF slice 3 (Lazy, zflow-prof-lz-3): the cap prompt names the next
-- rank's price when a trainer list of that profession has shown it, as
-- Flow's SkillPlan TierPriceLine. Pure: the lists come in as
-- Spells/TrainerModule.lua saves them.
local _, ns = ...

local function readings() return { Cooking = { skill = 75, max = 75 } } end
local function npcs()
    return { ["Daryl Riknussun"] = { map = 1453, x = 0.5, y = 0.5, trains = { Cooking = true }, factions = { Alliance = true } } }
end
local function lists(rows)
    return { ["Daryl Riknussun|Cooking"] = { npc = "Daryl Riknussun", profession = "Cooking", rows = rows } }
end

return {
    ["prof card price: the next rank's price"] = function(t)
        local p = ns.ProfCard.Prompts(readings(), npcs(), "Alliance",
            lists({ { name = "Cooking", rank = "Journeyman", state = "available", cost = 500 },
                    { name = "Spiced Wolf Ribs", state = "available", cost = 100 } }))
        t.eq(p[1].text, "Cooking is at its cap (75/75). Trainer seen: Daryl Riknussun. Journeyman costs "
            .. ns.Prices.Coin(500) .. ".")
    end,
    ["prof card price: the rank in the name; known ranks are not next"] = function(t)
        local p = ns.ProfCard.Prompts(readings(), npcs(), "Alliance",
            lists({ { name = "Apprentice Cooking", state = "known", cost = 10 },
                    { name = "Journeyman Cooking", state = "unavailable", cost = 500 } }))
        t.eq(p[1].text, "Cooking is at its cap (75/75). Trainer seen: Daryl Riknussun. Journeyman costs "
            .. ns.Prices.Coin(500) .. ".")
    end,
    ["prof card price: none seen, the prompt as before"] = function(t)
        t.eq(ns.ProfCard.Prompts(readings(), npcs(), "Alliance", lists({ { name = "Cooking", rank = "Journeyman", state = "available" } }))[1].text,
            "Cooking is at its cap (75/75). Trainer seen: Daryl Riknussun.", "no cost read")
        t.eq(ns.ProfCard.Prompts(readings(), npcs(), "Alliance", nil)[1].text,
            "Cooking is at its cap (75/75). Trainer seen: Daryl Riknussun.", "no lists")
    end,
}

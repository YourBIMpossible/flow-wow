-- P-PROF slice 1 (Lazy, zflow-prof-lz-1): a recipe item in your bags that
-- the recipe book does not hold gets one look-only advisor prompt, as
-- Flow's SkillPlan RecipeWait. Pure: bags, item names and the book come in.
local _, ns = ...

local RIBS, BOOTS, ROCK = 501, 502, 503
local NAMES = { [RIBS] = "Recipe: Spiced Wolf Ribs", [BOOTS] = "Pattern: Fine Leather Boots", [ROCK] = "Rough Stone" }
local function nameOf(id) return NAMES[id] end

local function fakeAdvisor()
    local items, a = {}, {}
    function a.Add(id, text) items[id] = text; return true end
    function a.Remove(id) items[id] = nil; return true end
    function a.Items() return items end
    return a
end

return {
    ["prof learn: an unknown recipe in the bags gets a prompt"] = function(t)
        local p = ns.ProfLearn.Prompts({ { item = RIBS, count = 1 }, { item = ROCK, count = 5 } }, nameOf, {})
        t.eq(#p, 1, "one prompt")
        t.eq(p[1].id, "aps.proflearn.501")
        t.eq(p[1].text, "Recipe: Spiced Wolf Ribs is in your bags: use it to learn Spiced Wolf Ribs.")
        t.eq(p[1].look, true)
    end,
    ["prof learn: a recipe the book holds gets none"] = function(t)
        local p = ns.ProfLearn.Prompts({ { item = RIBS, count = 1 } }, nameOf, { ["Spiced Wolf Ribs"] = { id = 1 } })
        t.eq(#p, 0)
    end,
    ["prof learn: two recipes, sorted by id; one stack each"] = function(t)
        local p = ns.ProfLearn.Prompts({ { item = BOOTS, count = 1 }, { item = RIBS, count = 1 }, { item = RIBS, count = 1 } }, nameOf, nil)
        t.eq(#p, 2)
        t.eq(p[1].id, "aps.proflearn.501")
        t.eq(p[2].text, "Pattern: Fine Leather Boots is in your bags: use it to learn Fine Leather Boots.")
    end,
    ["prof learn: a name not read is no prompt"] = function(t)
        local p = ns.ProfLearn.Prompts({ { item = 999, count = 1 } }, nameOf, {})
        t.eq(#p, 0)
        t.eq(#ns.ProfLearn.Prompts(nil, nameOf, {}), 0, "no bags read")
    end,
    ["prof learn: sync adds and removes"] = function(t)
        local a = fakeAdvisor()
        local shown = ns.ProfLearn.Sync(a, { { item = RIBS, count = 1 } }, nameOf, {}, {})
        t.ok(a.Items()["aps.proflearn.501"] ~= nil, "added")
        ns.ProfLearn.Sync(a, {}, nameOf, {}, shown)
        t.eq(a.Items()["aps.proflearn.501"], nil, "removed once learned or gone")
    end,
}

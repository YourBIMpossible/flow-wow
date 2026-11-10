-- Remembers what your profession windows show: each recipe you know, its
-- colour (difficulty) at your skill then, and its reagents. The planner
-- prefers this over the guide data, because it's this client's real list.
--   ns.db.crafting[<profession>] = { rank, seenAt, recipes = { [name] = {
--       item, diff = "optimal"|"medium"|"easy"|"trivial", reagents = { [itemID] = n } } } }

local _, ns = ...
local R = {}
ns.recipes = R

local DIFF = { [0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial" }

local function itemId(link)
    return link and tonumber(link:match("item:(%d+)"))
end

-- Classic-style API (GetTradeSkillInfo and friends).
local function readClassic()
    if not (GetTradeSkillLine and GetNumTradeSkills and GetTradeSkillInfo) then return end
    local prof, rank = GetTradeSkillLine()
    if not prof or prof == "UNKNOWN" then return end
    local recipes = {}
    for i = 1, GetNumTradeSkills() do
        local name, kind = GetTradeSkillInfo(i)
        if name and kind and kind ~= "header" and kind ~= "subheader" then
            local r = { diff = kind, reagents = {} }
            r.item = GetTradeSkillItemLink and itemId(GetTradeSkillItemLink(i))
            for j = 1, (GetTradeSkillNumReagents and GetTradeSkillNumReagents(i) or 0) do
                local _, _, count = GetTradeSkillReagentInfo(i, j)
                local id = GetTradeSkillReagentItemLink and itemId(GetTradeSkillReagentItemLink(i, j))
                -- The game hadn't loaded that item yet: the list is incomplete,
                -- so Flow doesn't treat the recipe as makeable from the rest.
                if id and count then r.reagents[id] = count else r.partial = true end
            end
            recipes[name] = r
        end
    end
    return prof, rank, recipes
end

-- Newer API (C_TradeSkillUI), where the classic one is gone.
local function readModern()
    local T = C_TradeSkillUI
    if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo) then return end
    local prof, rank
    if T.GetTradeSkillLine then prof, rank = T.GetTradeSkillLine() end
    if (not prof) and T.GetBaseProfessionInfo then
        local info = T.GetBaseProfessionInfo()
        prof, rank = info and info.professionName, info and info.skillLevel
    end
    if not prof then return end
    local recipes = {}
    for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
        local info = T.GetRecipeInfo(id)
        if info and info.learned then
            local r = { diff = info.difficulty or DIFF[info.relativeDifficulty], reagents = {} }
            if T.GetRecipeItemLink then r.item = itemId(T.GetRecipeItemLink(id)) end
            if T.GetRecipeNumReagents and T.GetRecipeReagentItemLink and T.GetRecipeReagentInfo then
                for j = 1, T.GetRecipeNumReagents(id) or 0 do
                    local _, _, count = T.GetRecipeReagentInfo(id, j)
                    local rid = itemId(T.GetRecipeReagentItemLink(id, j))
                    if rid and count then r.reagents[rid] = count else r.partial = true end
                end
            end
            recipes[info.name] = r
        end
    end
    return prof, rank, recipes
end

function R:Record()
    local ok, prof, rank, recipes = pcall(readClassic)
    if not (ok and prof) then ok, prof, rank, recipes = pcall(readModern) end
    if not (ok and prof and recipes and next(recipes)) then return end
    ns.db.crafting[prof] = { rank = rank, seenAt = time(), recipes = recipes }
    if ns.nav and ns.nav.RequestCollect then ns.nav.RequestCollect() end
end

-- What Flow knows of a profession's recipes (nil if you haven't opened it yet).
function R:Known(prof)
    local d = ns.db.crafting and ns.db.crafting[prof]
    return d and d.recipes, d and d.rank
end

ns:OnLoad(function(saved) saved.crafting = saved.crafting or {} end)
-- Your recipes are your character's. From the old shared data, a character
-- takes the professions it has (checked at login, when the game knows).
ns:PerCharacter("crafting", { later = true, adopt = function(old, _, current)
    local mine = ns.api.ProfessionSet()
    if next(mine) == nil then return false end   -- no professions seen yet: try next login
    current = current or {}
    for prof, rec in pairs(old) do
        if mine[prof] and current[prof] == nil then current[prof] = rec end
    end
    current.active = current.active or {}
    for prof, want in pairs(type(old.active) == "table" and old.active or {}) do
        if mine[prof] and current.active[prof] == nil then current.active[prof] = want end
    end
    current.drops = current.drops or old.drops   -- where items drop: anyone's
    return current
end })

for _, ev in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE" }) do
    ns:On(ev, function() C_Timer.After(0.3, function() R:Record() end) end)
end

-- Learning a recipe at a trainer doesn't open the profession window, so the
-- record above wouldn't know until you next open it, and "Learn X" stops
-- stayed on the route. The game's chat line ("You have learned how to create
-- a new item: Heavy Linen Bandage.") and NEW_RECIPE_LEARNED tell us at once.
function R:MarkKnown(name)
    if not name then return false end
    local prof
    for p, g in ns:Each("profGuide") do
        for _, s in ipairs(g.steps or {}) do if s.recipe == name then prof = p end end
    end
    if not prof then
        for p, d in pairs(ns.db.crafting) do
            if type(d) == "table" and d.recipes and d.recipes[name] then prof = p end
        end
    end
    if not prof then return false end
    local d = ns.db.crafting[prof]
    if not d then
        d = { rank = nil, seenAt = time(), recipes = {} }
        ns.db.crafting[prof] = d
    end
    d.recipes = d.recipes or {}
    d.recipes[name] = d.recipes[name] or { reagents = {} }
    if ns.nav and ns.nav.RequestCollect then ns.nav.RequestCollect() end
    return true
end

-- "You have learned how to create a new item: %s." -> a Lua pattern.
local function patternFrom(fmt)
    if type(fmt) ~= "string" then return nil end
    return "^" .. fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%s", "(.+)") .. "$"
end
R._patternFrom = patternFrom  -- (tests)

ns:On("CHAT_MSG_SYSTEM", function(msg)
    for _, fmt in ipairs({ ERR_LEARN_RECIPE_S, ERR_LEARN_SPELL_S }) do
        local p = patternFrom(fmt)
        local name = p and type(msg) == "string" and msg:match(p)
        if name then R:MarkKnown(name:gsub("^|c%x+|H.-|h%[?(.-)%]?|h|r$", "%1")) return end
    end
end)

ns:On("NEW_RECIPE_LEARNED", function(recipeID)
    local name
    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
        local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
        name = ok and info and info.name
    end
    if not name and GetSpellInfo then name = GetSpellInfo(recipeID) end
    R:MarkKnown(name)
end)

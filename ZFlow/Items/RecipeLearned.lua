local _, ns = ...
-- P-PROF slice 2 (Lazy, zflow-prof-lz-2), as Flow's Recipes MarkKnown and
-- LearnedName: the game's line on learning a recipe (CHAT_MSG_SYSTEM, the
-- client's text ERR_LEARN_RECIPE_S) marks it known in the recipe book
-- (Items/RecipeBook.lua, char "learned.facts.recipeBook"), before its
-- profession window is next read. Reads and saves only.
--   R.Name(line, fmt) -> the recipe's name, or nil; fmt nil: R.ENGLISH
--   R.Mark(book, name) -> a new book with name = { learned, partial }, or
--     nil when name is already saved (nothing to write). partial: Recipes
--     and For leave it out until the window reads it whole.
-- Module R.Declare(k): client.onSystemMessage, a line at a time.
local R = {}
ns.RecipeLearned = R
R.NAME = "recipeLearned"
R.TEXT = "ERR_LEARN_RECIPE_S"
R.ENGLISH = "You have learned how to create a new item: %s."

local function pattern(fmt)
    local p = fmt:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    p = p:gsub("%%s", "(.+)")
    return "^" .. p .. "$"
end

function R.Name(line, fmt)
    if type(line) ~= "string" then return nil end
    if type(fmt) ~= "string" or not fmt:find("%s", 1, true) then fmt = R.ENGLISH end
    local name = line:match(pattern(fmt))
    if name == nil or name == "" then return nil end
    return name
end

function R.Mark(book, name)
    if type(name) ~= "string" or name == "" then return nil end
    if type(book) ~= "table" then book = {} end
    if book[name] ~= nil then return nil end
    local out = {}
    for k, v in pairs(book) do out[k] = v end
    out[name] = { learned = true, partial = true }
    return out
end

function R.Declare(k)
    local cancel = nil
    k:Module({
        name = R.NAME,
        needs = { "client", "store" },
        start = function(ctx)
            local client = ctx.client
            if type(client.onSystemMessage) ~= "function" then return end
            local fmt = nil
            if type(client.globalText) == "function" then
                local ok, v = pcall(client.globalText, R.TEXT)
                if ok then fmt = v end
            end
            cancel = client.onSystemMessage(function(line)
                local name = R.Name(line, fmt)
                if name == nil then return end
                local out = R.Mark(ctx.store:get("char", ns.RecipeBook.PATH), name)
                if out then ctx.store:set("char", ns.RecipeBook.PATH, out) end
            end)
        end,
        stop = function()
            if type(cancel) == "function" then pcall(cancel) end
            cancel = nil
        end,
    })
end

R.Declare(ns)

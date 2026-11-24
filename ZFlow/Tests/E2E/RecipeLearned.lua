local _, ns = ...

-- A recipe learned, from the game's own line (P-PROF slice 2,
-- Items/RecipeLearned.lua), end to end, on the whole add-on loaded on a
-- fake client. The real entry: the CHAT_MSG_SYSTEM line "You have learned
-- how to create a new item: <name>." (the client's text
-- ERR_LEARN_RECIPE_S; c.systemMessage). The result is in the character's
-- saved recipe book (learned.facts.recipeBook): the name marked learned,
-- in part, until its profession window is next read. Reads and saves
-- only: nothing is crafted, sold or equipped. Made-up names. Not tested
-- in game.

local tests = {}

local ENGLISH = "You have learned how to create a new item: %s."
local BOLT = "Bolt of Linen Cloth"

local function at(root, ...)
    for _, key in ipairs({ ... }) do
        if type(root) ~= "table" then return nil end
        root = root[key]
    end
    return root
end

-- opts.text: the client's ERR_LEARN_RECIPE_S (false: the client has none);
-- opts.char: the character's saved table.
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setScreen(1024, 768)
    c.setClock(1700000000)
    if opts.text ~= false then c.setGlobalText("ERR_LEARN_RECIPE_S", opts.text or ENGLISH) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

local function book(c) return at(c.saved(ns.id.charDB), "learned", "facts", "recipeBook") end

local function noneActs(t, c)
    t.eq(#c.soldSlots, 0, "nothing sold")
    t.eq(c.equipCalls, 0, "nothing equipped")
end

tests["recipe learned e2e: the game's line marks the recipe learned, in part"] = function(t)
    local c = boot()
    t.eq(book(c) and book(c)[BOLT], nil, "not known before")
    c.systemMessage("You have learned how to create a new item: " .. BOLT .. ".")
    t.eq(book(c) and book(c)[BOLT], { learned = true, partial = true })
    noneActs(t, c)
end

tests["recipe learned e2e: a recipe already in the book is left as it was"] = function(t)
    local whole = { id = 2963, makes = 2996, yield = 1, mats = { [2589] = 2 }, learned = true }
    local c = boot({ char = { learned = { facts = { recipeBook = { [BOLT] = whole } } } } })
    c.systemMessage("You have learned how to create a new item: " .. BOLT .. ".")
    t.eq(book(c)[BOLT], whole, "the whole entry stays whole")
end

tests["recipe learned e2e: the client's own wording is used"] = function(t)
    local c = boot({ text = "Neues Rezept erlernt: %s." })
    c.systemMessage("Neues Rezept erlernt: Leinenstoffballen.")
    t.eq(book(c) and book(c)["Leinenstoffballen"], { learned = true, partial = true })
    c.systemMessage("You have learned how to create a new item: " .. BOLT .. ".")
    t.eq(book(c)[BOLT], nil, "the English line is not this client's")
end

tests["recipe learned e2e: unknown lines mark nothing"] = function(t)
    -- No text from the client: the English wording stands in.
    local c = boot({ text = false })
    c.systemMessage("You have learned how to create a new item: " .. BOLT .. ".")
    t.eq(book(c) and book(c)[BOLT], { learned = true, partial = true })
    -- Other system lines, an empty name and a non-text line: nothing saved.
    local c2 = boot()
    c2.systemMessage("You have learned a new spell: Fireball.")
    c2.systemMessage("You have learned how to create a new item: .")
    c2.systemMessage(42)
    local b = book(c2)
    t.ok(b == nil or next(b) == nil, "nothing saved")
    noneActs(t, c2)
end

return tests

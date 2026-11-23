local _, ns = ...

-- Trainer and spell learning (F8), the module that joins the pieces:
--   at a trainer   the window's list is kept per trainer, for later
--                  (Spells/TrainerList.lua), and while the window is open an
--                  advisor prompt says how many spells can be learned there
--                  and names the first few, with cost
--   rank-ups       a prompt per spell with a higher rank you could learn at
--                  your level, at a trainer seen before
--                  (Spells/TrainerListRankUp.lua); kept in step at login, at
--                  every trainer visit, at a level-up and when you learn a spell
--   a new spell    one line, "New spell: Moonfire (Rank 2)" (UI/SpellCard.lua),
--                  printed when you learn it
-- Look-only: nothing is trained, bought or cast.
--
--   api = TrainerModule.Declare(k)
--     api.lists()    a copy of the kept lists ({} when none)
--     api.errors()   how many events could not be worked out
--   ns.use(TrainerModule.NAME) -> { Lists = api.lists, Errors = api.errors }
--
-- Client reads (Core/Client.lua): trainer() with its services and filter,
-- watchTrainer(), faction(), clock(), level() and onSpellLearned(fn). Each
-- one that is missing means "not known": nothing is kept and no prompt is
-- claimed for it.
--
-- Saved data: char "learned.trainerLists" (TrainerList's table, keyed by
-- TrainerList.Key, which never holds a dot).
--
-- Settings (char, on by default):
--   spells.trainerList   "What you can learn at trainers": the prompt at an
--                        open trainer, and the lists kept
--   spells.rankUp        "Rank-up reminders"
--   spells.newSpellCard  "New spell line"
--
-- The card is a printed line for now: the shared panel it will move to is
-- F9's (FEATURE-PLAN), not built yet.

local M = {}
ns.TrainerModule = M

M.NAME = "trainerLists"
M.PATH = "learned.trainerLists"
M.SETTING_LIST = "spells.trainerList"
M.SETTING_RANKUP = "spells.rankUp"
M.SETTING_CARD = "spells.newSpellCard"
M.PROMPT = "aps.trainer"
M.PRIORITY = 2
M.MAX_NAMED = 3

local function ask(client, read, ...)
    if type(client) ~= "table" or type(client[read]) ~= "function" then return nil end
    return client[read](...)
end

-- The prompt for an open trainer: how many can be learned now, and the
-- first few by name with their cost (F-085 trainer wording when unknown).
-- nil when nothing can be learned or the list cannot be read.
function M.LearnText(reading)
    if type(reading) ~= "table" or type(reading.services) ~= "table" then return nil end
    local can = {}
    for _, r in ipairs(reading.services) do
        if type(r) == "table" and r.state == "available" and type(r.name) == "string" then can[#can + 1] = r end
    end
    if #can == 0 then return nil end
    local named = {}
    for i = 1, math.min(#can, M.MAX_NAMED) do
        local r = can[i]
        local cost = (type(r.cost) == "number" and ns.Prices and ns.Prices.Coin) and ns.Prices.Coin(r.cost)
            or ns.TrainerList.PRICE_UNKNOWN
        named[i] = (type(r.rank) == "string" and (r.name .. " (" .. r.rank .. ")") or r.name) .. ", " .. cost
    end
    local text = #can .. (#can == 1 and " spell" or " spells") .. " to learn here: " .. table.concat(named, "; ")
    if #can > #named then text = text .. " and " .. (#can - #named) .. " more" end
    return text
end

local function copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copy(v) end
    return out
end

function M.Declare(k)
    local api = {}
    local errors, seen = 0, {}
    function api.errors() return errors end

    local ctxRef
    local function lists()
        if not ctxRef then return {} end
        local saved = ctxRef.store:get("char", M.PATH)
        return type(saved) == "table" and saved or {}
    end
    function api.lists() return copy(lists()) end

    local function failed(what, err)
        errors = errors + 1
        local text = tostring(err)
        if not seen[text] then
            seen[text] = true
            k.problems:add("spells", what, text)
        end
    end

    local shown, stopLearned = {}, nil
    local function refreshRankUps(ctx, advisor)
        if ctx.settings:get(M.SETTING_RANKUP) ~= true then
            shown = ns.TrainerListRankUp.Sync(advisor, {}, {}, nil, shown)
            return
        end
        shown = ns.TrainerListRankUp.Refresh(ctx.client, advisor, lists(), {}, shown)
    end

    k:Module({
        name = M.NAME,
        needs = { "client", "store", "bus", "advisor" },
        settings = {
            { key = M.SETTING_LIST, scope = "char", type = "bool", default = true,
              label = "What you can learn at trainers",
              help = "At a trainer, say what you can learn there and what it costs, and keep the list. It trains nothing.",
              group = "combat.spells", synonyms = { "trainer", "train", "spells", "cost" } },
            { key = M.SETTING_RANKUP, scope = "char", type = "bool", default = true,
              label = "Rank-up reminders",
              help = "Say when a trainer you have seen teaches a higher rank of a spell you know, at your level.",
              group = "combat.spells", synonyms = { "trainer", "rank", "spells", "reminder" } },
            { key = M.SETTING_CARD, scope = "char", type = "bool", default = true,
              label = "New spell line",
              help = "When you learn a spell, print one line with its name and rank.",
              group = "combat.spells", synonyms = { "spell", "learned", "new", "chat" } },
        },
        provides = { Lists = api.lists, Errors = api.errors },
        start = function(ctx)
            ctxRef = ctx
            local advisor = ctx.use("advisor")
            if type(ctx.client.watchTrainer) == "function" then ctx.client.watchTrainer() end

            ctx.bus:on(M.NAME, "TRAINER_SHOW", function()
                local ok, err = pcall(function()
                    if ctx.settings:get(M.SETTING_LIST) ~= true then return end
                    local reading = ask(ctx.client, "trainer")
                    if type(reading) ~= "table" then return end
                    local text = M.LearnText(reading)
                    if text and type(advisor) == "table" then advisor.Add(M.PROMPT, text, M.PRIORITY) end
                    local before = lists()
                    local after = ns.TrainerList.Record(copy(before), reading, ask(ctx.client, "clock"),
                        ask(ctx.client, "faction"))
                    ctx.store:set("char", M.PATH, after)
                end)
                if not ok then failed("trainer", err) end
                local okUp, errUp = pcall(refreshRankUps, ctx, advisor)
                if not okUp then failed("rank-up", errUp) end
            end)
            ctx.bus:on(M.NAME, "TRAINER_CLOSED", function()
                if type(advisor) == "table" then advisor.Remove(M.PROMPT) end
            end)
            ctx.bus:on(M.NAME, "PLAYER_LEVEL_UP", function()
                local ok, err = pcall(refreshRankUps, ctx, advisor)
                if not ok then failed("rank-up", err) end
            end)
            stopLearned = ask(ctx.client, "onSpellLearned", function(spell)
                if ctx.settings:get(M.SETTING_CARD) == true then
                    local lines = ns.SpellCard.Lines(ns.SpellCard.Build(spell))
                    for i = 1, #lines do ctx.client.print(k.id.title .. ": " .. lines[i]) end
                end
                local ok, err = pcall(refreshRankUps, ctx, advisor)
                if not ok then failed("rank-up", err) end
            end)

            local ok, err = pcall(refreshRankUps, ctx, advisor)
            if not ok then failed("rank-up", err) end
        end,
        stop = function()
            if type(stopLearned) == "function" then stopLearned() end
            stopLearned = nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.trainerModule = M.Declare(ns)

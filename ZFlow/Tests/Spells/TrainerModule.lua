local _, ns = ...

-- Tests for ZFlow/Spells/TrainerModule.lua (F8): the trainer prompt, the
-- kept lists, the rank-up reminders and the new-spell line, through the
-- fake client and a real kernel with the advisor.

local M = ns.TrainerModule
local A = ns.Advisor
local tests = {}

local function rows()
    return {
        { name = "Moonfire", rank = "Rank 2", state = "available", cost = 150, level = 10 },
        { name = "Wrath", rank = "Rank 3", state = "available", level = 10 },
        { name = "Thorns", rank = "Rank 1", state = "known", cost = 100, level = 6 },
        { name = "Thorns", rank = "Rank 2", state = "unavailable", cost = 900, level = 14 },
    }
end
local ALL = { available = true, unavailable = true, known = true }

local function start(level)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setLevel(level or 10)
    c.setClock(1000)
    c.setTrainer({ npc = "Bena Winterhoof", services = rows(), filter = ALL })
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    local advisor = A.Declare(k)
    local api = M.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, advisor, api
end

local function prompt(advisor, id)
    for _, p in ipairs(advisor.List()) do
        if p.id == id then return p.text end
    end
    return nil
end

tests["trainer module: an open trainer says what can be learned, with cost"] = function(t)
    local k, c, advisor = start()
    t.eq(k:ModuleState(M.NAME), "started")
    c.fire("TRAINER_SHOW")
    t.eq(prompt(advisor, M.PROMPT),
        "2 spells to learn here: Moonfire (Rank 2), " .. ns.Prices.Coin(150) .. "; Wrath (Rank 3), "
        .. ns.TrainerList.PRICE_UNKNOWN)
    c.fire("TRAINER_CLOSED")
    t.eq(prompt(advisor, M.PROMPT), nil, "gone when the window closes")
end

tests["trainer module: the list is kept per trainer, for later"] = function(t)
    local _, c, _, api = start()
    t.eq(api.lists(), {})
    c.fire("TRAINER_SHOW")
    local lists = api.lists()
    local entry = lists[ns.TrainerList.Key("Bena Winterhoof", nil)]
    t.eq(type(entry), "table")
    t.eq(entry.npc, "Bena Winterhoof")
    t.eq(#entry.rows, 4)
    t.eq(entry.complete, true)
    t.eq(entry.seen, 1000)
end

tests["trainer module: a rank-up seen at a trainer, at your level, is a reminder"] = function(t)
    local _, c, advisor = start(14)
    c.fire("TRAINER_SHOW")
    t.eq(prompt(advisor, ns.TrainerListRankUp.PREFIX .. "Thorns"), "Thorns Rank 2 can be learned at Bena Winterhoof.")
end

tests["trainer module: below the level it needs, no reminder until you level up"] = function(t)
    local _, c, advisor = start(10)
    c.fire("TRAINER_SHOW")
    t.eq(prompt(advisor, ns.TrainerListRankUp.PREFIX .. "Thorns"), nil)
    c.setLevel(14)
    c.fire("PLAYER_LEVEL_UP", 14)
    t.ok(prompt(advisor, ns.TrainerListRankUp.PREFIX .. "Thorns") ~= nil)
end

tests["trainer module: your level not known claims no reminder"] = function(t)
    local _, c, advisor = start(14)
    c.setLevel(nil)
    c.fire("TRAINER_SHOW")
    t.eq(prompt(advisor, ns.TrainerListRankUp.PREFIX .. "Thorns"), nil)
end

tests["trainer module: a list that cannot be read keeps nothing and says nothing"] = function(t)
    local _, c, advisor, api = start()
    c.setTrainer({ npc = "Bena Winterhoof" })
    c.fire("TRAINER_SHOW")
    t.eq(prompt(advisor, M.PROMPT), nil)
    t.eq(api.lists(), {})
    c.setTrainer(nil)
    c.fire("TRAINER_SHOW")
    t.eq(api.lists(), {})
end

tests["trainer module: learning a spell prints one line"] = function(t)
    local _, c = start()
    local before = #c.printed
    c.learnSpell({ id = 8921, name = "Moonfire", rank = "Rank 2" })
    t.eq(#c.printed, before + 1)
    t.ok(c.printed[#c.printed]:find("New spell: Moonfire (Rank 2)", 1, true), c.printed[#c.printed])
end

tests["trainer module: the three settings are on by default, and off works"] = function(t)
    local k, c, advisor, api = start(14)
    for _, key in ipairs({ M.SETTING_LIST, M.SETTING_RANKUP, M.SETTING_CARD }) do
        t.eq(k.settings:get(key), true, key)
        t.eq(k.settings:set(key, false), true, key)
    end
    c.fire("TRAINER_SHOW")
    t.eq(advisor.List(), {})
    t.eq(api.lists(), {})
    local before = #c.printed
    c.learnSpell({ name = "Moonfire" })
    t.eq(#c.printed, before)
end

tests["trainer module: an error is one problem and the module goes on"] = function(t)
    local k, c, _, api = start()
    c.trainer = function() error("the read broke") end
    c.fire("TRAINER_SHOW")
    c.fire("TRAINER_SHOW")
    t.eq(api.errors(), 2)
    t.eq(k.problems:count("spells"), 1)
    t.eq(k:ModuleState(M.NAME), "started")
end

tests["trainer module: it trains nothing"] = function(t)
    local _, c = start(14)
    local calls = 0
    for _, name in ipairs({ "BuyTrainerService", "CastSpellByName", "CastSpell" }) do
        c[name] = function() calls = calls + 1 end
    end
    c.fire("TRAINER_SHOW")
    c.learnSpell({ name = "Moonfire" })
    t.eq(calls, 0)
end

return tests

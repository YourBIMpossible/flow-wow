-- The profession reminder card as a module (F5, was U-F): it registers its
-- prompts through the real advisor (UI/Advisor.lua), and a prompt goes when
-- its cause goes. Fake client; not tested in game.
--
-- The saved readings are changed in place and PLAYER_ENTERING_WORLD is
-- fired: ProfSeen does not listen for it, so only the card runs.
local _, ns = ...

local P = ns.ProfCard
local ID = P.PREFIX .. "Cooking"

local function npcs()
    return {
        ["Daryl Riknussun"] = { roles = { trainer = true }, trains = { Cooking = true }, factions = { Alliance = true } },
    }
end

-- skill, max: the Cooking reading saved before the start.
local function start(skill, max)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { learned = { places = { npcs = npcs() } } })
    c.setSaved(ns.id.charDB, { learned = { facts = { profSkill = {
        Cooking = { line = 185, skill = skill, max = max },
        Mining = { line = 186, skill = 40, max = 75 },
    } } } })
    c.setFaction("Alliance")
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    local advisor = ns.Advisor.Declare(k)
    ns.ProfSeen.Declare(k)
    local api = P.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    local function prompt(id)
        for _, p in ipairs(advisor.List()) do
            if p.id == id then return p end
        end
        return nil
    end
    -- The Cooking reading as saved, to change in place.
    local function cooking()
        return c.saved(ns.id.charDB).learned.facts.profSkill.Cooking
    end
    return k, c, api, prompt, cooking
end

return {
    ["profession card module: started, and the capped profession is one advisor prompt"] = function(t)
        local k, _, api, prompt = start(75, 75)
        t.eq((k:ModuleState(P.NAME)), "started")
        local p = prompt(ID)
        t.ok(p ~= nil, "registered through the advisor")
        if not p then return end
        t.eq(p.text, "Cooking is at its cap (75/75). Trainer seen: Daryl Riknussun.")
        t.eq(p.priority, P.PRIORITY)
        t.eq(prompt(P.PREFIX .. "Mining"), nil, "below its cap: no prompt")
        t.eq(api.shown(), { [ID] = true })
        t.eq(k.problems:count(), 0)
    end,

    ["profession card module: the prompt goes when the cap is raised"] = function(t)
        local k, c, api, prompt, cooking = start(75, 75)
        t.ok(prompt(ID) ~= nil, "there at the start")
        cooking().max = 150      -- trained the next rank
        c.fire("PLAYER_ENTERING_WORLD")
        t.eq(prompt(ID), nil, "its cause is gone, so it is gone")
        t.eq(api.shown(), {})
        t.eq(k.problems:count(), 0)
    end,

    ["profession card module: a prompt appears when the skill reaches its cap"] = function(t)
        local k, c, api, prompt, cooking = start(60, 75)
        t.eq(prompt(ID), nil)
        t.eq(api.shown(), {})
        cooking().skill = 75
        c.fire("PLAYER_ENTERING_WORLD")
        t.ok(prompt(ID) ~= nil, "at its cap now")
        t.eq(api.shown(), { [ID] = true })
        t.eq(k.problems:count(), 0)
    end,

    ["profession card module: the events ProfSeen saves on do not raise"] = function(t)
        local k, c = start(75, 75)
        t.eq(pcall(c.fire, ns.ProfSeen.RECIPES_EVENT), true)
        t.eq(pcall(c.fire, ns.ProfSeen.TRAINER_EVENT), true)
        t.eq(k.problems:count(), 0)
    end,

    ["profession card module: the list given by shown() is a copy"] = function(t)
        local _, _, api = start(75, 75)
        local shown = api.shown()
        shown[ID] = nil
        t.eq(api.shown(), { [ID] = true })
    end,

    ["profession card module: the one of the addon is declared"] = function(t)
        t.ok(type(ns.profCard) == "table")
        t.ok(type(ns.profCard.shown) == "function")
    end,
}

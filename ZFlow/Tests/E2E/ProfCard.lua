local _, ns = ...
-- The profession reminder card (UI/ProfCard.lua), on the whole add-on
-- loaded on a fake client, through the real entry: a profession at its cap
-- (saved reading) and a trainer met at TRAINER_SHOW (saved by
-- Nav/ProfSeen.lua) give one advisor prompt; a later window read above the
-- cap takes it away. Look only: nothing trains or buys. Made-up names; not
-- tested in game.
local tests = {}

local MINING, MAP, NPC = 186, 1411, "Test Trainer"
local ID = "aps.prof.Mining"
local TEXT = "Mining is at its cap (75/75). Trainer seen: " .. NPC .. "."

local SEEN = { learned = { places = { npcs = {
    [NPC] = { map = MAP, x = 0.4, y = 0.6, trains = { Mining = true }, factions = { Horde = true }, seen = 10 },
} } } }

-- opts.account: the account saved table; opts.faction: the player's faction.
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, { learned = { facts = { profSkill = {
        Mining = { line = MINING, skill = 75, max = 75 } } } } })
    c.setZone(1, MAP); c.setPosition(MAP, 0.4, 0.6)
    c.setFaction(opts.faction)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function prompt(addon)
    local advisor = addon.use("advisor")
    if type(advisor) ~= "table" or type(advisor.List) ~= "function" then return nil end
    for _, p in ipairs(advisor.List()) do
        if p.id == ID then return p end
    end
    return nil
end

tests["prof card: a capped profession and a trainer met give one prompt; a raised cap removes it"] = function(t)
    local c, addon = boot({ faction = "Horde" })
    t.eq(prompt(addon), nil, "no trainer seen yet: no prompt")
    c.setTrainer({ profession = "Mining", npc = NPC })
    c.fire("TRAINER_SHOW"); c.advance(2, 4)
    local p = prompt(addon)
    t.eq(p and p.text, TEXT, "the card names the profession, the cap and the trainer")
    c.setRecipes({ profession = MINING, name = "Mining", skill = 75, max = 150, recipes = {} })
    c.fire("TRADE_SKILL_LIST_UPDATE"); c.advance(2, 4)
    t.eq(prompt(addon), nil, "the cap was raised: the prompt goes")
    t.eq(#c.crafts, 0, "nothing is crafted")
end

tests["prof card: a trainer saved before shows on entering the world"] = function(t)
    local c, addon = boot({ faction = "Horde", account = SEEN })
    local p = prompt(addon)
    t.eq(p and p.text, TEXT)
    t.eq(#c.crafts, 0, "nothing is crafted")
end

tests["prof card: an unknown faction or another faction's trainer names nobody"] = function(t)
    local _, addon = boot({ account = SEEN })
    t.eq(prompt(addon), nil, "the faction is not known: no prompt")
    local _, other = boot({ faction = "Alliance", account = SEEN })
    t.eq(prompt(other), nil, "a Horde trainer is no target for an Alliance player")
end

return tests

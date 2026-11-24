local _, ns = ...
-- Riding step (G45) end to end, on the whole add-on loaded on a fake
-- client. A level 40 player with no riding skill opens a riding trainer's
-- window that shows the price; the advisor then says riding can be
-- learned, for that price, at that trainer, and how much more money is
-- needed, and the arrow's route step points at the trainer. Look only:
-- nothing trains, buys or mounts. Made-up npc, place and price. Not tested
-- in game.
local tests = {}

local RIDER = "Test Rider"
local PRICE = 200000

local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR")
    c.setLevel(opts.level or 40)
    c.setFaction("Alliance")
    c.setMoney(opts.money or 150000)
    c.setPosition(1453, 0.3, 0.6)
    c.setSkillRanks(opts.skills or { Defense = { rank = 200, max = 200 } })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function prompt(addon)
    local S = ns.RidingStep or {}
    for _, p in ipairs(addon.advisor.List()) do
        if p.id == S.PROMPT then return p.text end
    end
    return nil
end

local function step(addon)
    local api = addon.use("ridingStep")
    if type(api) ~= "table" or type(api.Step) ~= "function" then return nil end
    return api.Step()
end

local function openRider(c)
    c.setTrainer({ npc = RIDER, services = {
        { name = "Horse Riding", rank = "Apprentice", state = "available", cost = PRICE, level = 40 } } })
    c.fire("TRAINER_SHOW")
end

tests["riding step: level 40, no riding, the trainer seen with its price - the line and the step"] = function(t)
    local c, addon = boot()
    t.eq(prompt(addon), "You can learn riding now (price not seen yet). Ask a city guard for the riding trainer."
        .. " Then buy a mount from a mount vendor (a city guard knows where).", "before the trainer is seen")
    openRider(c)
    c.setTrainer(nil)
    c.fire("TRAINER_CLOSED")
    c.setPosition(1453, 0.6, 0.6)
    -- Money is read again when a window that changes it closes, never on
    -- PLAYER_MONEY (the info bar alone listens to that, Tests/E2E/InfoBar.lua).
    c.fire("MERCHANT_CLOSED")
    t.eq(prompt(addon), "You can learn riding now: about 20g at the riding trainer " .. RIDER .. "."
        .. " You need 5g more. Then buy a mount from a mount vendor (a city guard knows where).")
    local s = step(addon)
    t.eq(s and s.kind, "riding")
    t.eq(s and s.place, { map = 1453, x = 0.3, y = 0.6 }, "a place: the arrow has a needle")
    t.eq(s and s.label, "Riding trainer: " .. RIDER)
end

tests["riding step: nothing below level 40, nothing once riding is learned"] = function(t)
    local _, a1 = boot({ level = 39 })
    t.eq(prompt(a1), nil, "level 39")
    t.eq(step(a1), nil)
    local c2, a2 = boot()
    t.ok(prompt(a2) ~= nil, "due at 40")
    c2.setSkillRanks({ ["Horse Riding"] = { rank = 75, max = 75 } })
    c2.fire("SKILL_LINES_CHANGED")
    t.eq(prompt(a2), nil, "learned: the line goes")
    t.eq(step(a2), nil)
end

tests["riding step: level 60 with the first tier says faster riding"] = function(t)
    local _, addon = boot({ level = 60, skills = { ["Horse Riding"] = { rank = 75, max = 75 } } })
    t.eq(prompt(addon), "You can learn faster riding now (price not seen yet). Ask a city guard for the riding"
        .. " trainer. Then buy a fast mount from a mount vendor.")
end

-- The riding step does not listen to PLAYER_MONEY: the info bar's own
-- event (Tests/E2E/InfoBar.lua: a hidden bar listens to nothing of its own).
tests["riding step: it never listens to PLAYER_MONEY"] = function(t)
    local c = boot()
    for _, ev in ipairs(c.events()) do t.ok(ev ~= "PLAYER_MONEY", "PLAYER_MONEY not listened to") end
end

return tests

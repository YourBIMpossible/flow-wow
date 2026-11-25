local _, ns = ...
-- FLOW-PARITY B-25 (lead section 460) end to end, on the whole add-on on a
-- fake client: the save-up line before riding (price seen, or not seen),
-- the "Learn riding" step with its price at the trainer, then the mount
-- until the player is seen mounted. Look only. Made-up npc, place and
-- price. Not tested in game.
local tests = {}

local RIDER, PRICE, MAP = "Test Rider", 200000, 1453

local function seenRider()
    return { learned = { places = { npcs = { [RIDER] = {
        roles = { ridingTrainer = true }, ridingCosts = { [40] = PRICE }, map = MAP, x = 0.3, y = 0.6 } } } } }
end

local function boot(opts)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setFaction("Alliance")
    c.setLevel(opts.level); c.setMoney(opts.money or 150000)
    c.setPosition(MAP, 0.5, 0.6)
    c.setSkillRanks(opts.skills or { Defense = { rank = 200, max = 200 } })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(ns.Nav.MountMilestone.EVERY + 1, 20)
    return c, addon
end

local function prompt(addon)
    for _, p in ipairs(addon.advisor.List()) do
        if p.id == ns.Nav.MountMilestone.PROMPT then return p.text end
    end
    return nil
end

local function use(addon) return addon.use("mountMilestone") end

tests["mount milestone: five levels before riding, a seen price: the save-up line"] = function(t)
    local _, addon = boot({ level = 36, account = seenRider() })
    t.eq(prompt(addon), "Riding at level 40 costs about 20g; you have 15g. Start saving for it.")
    local _, a2 = boot({ level = 36 })
    t.eq(prompt(a2), "Riding at level 40 (price not seen yet): start saving for it.", "a price not seen stays unknown")
    local _, a3 = boot({ level = 34, account = seenRider() })
    t.eq(prompt(a3), nil, "too early")
end

tests["mount milestone: at 40 the Learn riding step with its price, then the mount until seen mounted"] = function(t)
    local _, addon = boot({ level = 40, account = seenRider() })
    local s = use(addon).Step()
    t.eq(s and s.label, "Learn riding (20g)")
    t.eq(s and s.place, { map = MAP, x = 0.3, y = 0.6 })
    local c, a2 = boot({ level = 41, skills = { ["Horse Riding"] = { rank = 75, max = 75 } } })
    t.eq(prompt(a2), "Next: buy your first mount from a mount vendor (price not seen yet).")
    t.eq(use(a2).Step(), nil, "riding known: no riding step")
    c.setMounted(true); c.advance(ns.Nav.MountMilestone.EVERY + 1, 10)
    t.eq(prompt(a2), nil, "seen mounted: the milestone is done")
end

tests["mount milestone: the pure order and an unknown price"] = function(t)
    local M = ns.Nav.MountMilestone
    t.eq(M.Next({ level = 35, rank = 0 }), "save")
    t.eq(M.Next({ level = 40, rank = 0 }), "riding")
    t.eq(M.Next({ level = 40, rank = 75 }), "mount")
    t.eq(M.Next({ level = 40, rank = 75, mountSeen = true }), nil)
    t.eq(M.Next({ level = 40 }), nil, "riding not read: nothing claimed")
    t.eq(M.Cost({}), nil)
    t.eq(M.Step("riding", { place = { map = MAP, x = 0.1, y = 0.2 } }, nil).label, "Learn riding (price not seen yet)")
    t.eq(M.Step("riding", {}, PRICE), nil, "no trainer place: no step")
end

tests["mount milestone: a seen price with money not readable says so, not price unknown"] = function(t)
    local M = ns.Nav.MountMilestone
    t.eq(M.Lines("save", 200000, nil)[1], M.SAVE_NO_MONEY:format(M.LEVEL, ns.Prices.Coin(200000)))
    t.eq(M.Lines("save", 200000, nil)[1], "Riding at level 40 costs about 20g (money not readable): start saving for it.")
    t.eq(M.Lines("save", nil, 5)[1], M.SAVE_UNKNOWN:format(M.LEVEL), "no price seen: price not seen yet")
end

return tests

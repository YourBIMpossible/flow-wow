-- Riding step (G45): the pure decision. A player at the level for riding
-- (or for the next riding tier) who does not have it is told so, with the
-- cost and the trainer only when the game showed them. Made-up names,
-- places and prices, test only. Nothing here trains, buys or mounts.
-- Not seen in game.
local _, ns = ...

local T = {}

local function R() return ns.RidingStep end

local HERE = { map = 1453, x = 0.5, y = 0.5 }

T["riding step: the names agreed"] = function(t)
    local S = R()
    t.ok(type(S) == "table", "the module is there")
    if type(S) ~= "table" then return end
    t.eq(S.NAME, "ridingStep")
    t.eq(S.SETTING, "nav.ridingStep")
    t.eq(S.KIND, "riding")
end

T["riding step: below the level, nothing is due"] = function(t)
    local S = R()
    if type(S) ~= "table" then return t.ok(false, "no module") end
    t.eq(S.Due(39, {}), nil, "level 39, no riding")
    t.eq(S.Due(nil, {}), nil, "level not known")
    t.eq(S.Due(40, nil), nil, "skills not read: not known, nothing said")
end

T["riding step: at the level and not learned, the first tier is due"] = function(t)
    local S = R()
    if type(S) ~= "table" then return t.ok(false, "no module") end
    local due = S.Due(40, { Defense = { rank = 200, max = 200 } })
    t.eq(due and due.tier, 1)
    t.eq(due and due.level, 40)
    t.eq(due and due.words, "riding")
end

T["riding step: learned, nothing is due until the next tier's level"] = function(t)
    local S = R()
    if type(S) ~= "table" then return t.ok(false, "no module") end
    t.eq(S.Due(45, { ["Horse Riding"] = { rank = 75, max = 75 } }), nil, "level 45, riding known")
    t.eq(S.Due(60, { ["Horse Riding"] = { rank = 150, max = 150 } }), nil, "level 60, both tiers known")
    t.eq(S.Due(40, { ["Horse Riding"] = { max = 75 } }), nil, "a riding line with no rank read: not known")
end

T["riding step: tier 2 at level 60 with the first tier only"] = function(t)
    local S = R()
    if type(S) ~= "table" then return t.ok(false, "no module") end
    local due = S.Due(60, { ["Wolf Riding"] = { rank = 75, max = 75 } })
    t.eq(due and due.tier, 2)
    t.eq(due and due.level, 60)
    t.eq(due and due.words, "faster riding")
end

T["riding step: no trainer seen, the one thing to do and no needle"] = function(t)
    local S = R()
    if type(S) ~= "table" then return t.ok(false, "no module") end
    local step = S.Of(S.Due(40, {}), HERE, nil, 100)
    t.eq(step.kind, "riding")
    t.eq(step.place, nil)
    t.eq(S.Lines(step), {
        "You can learn riding now (price not seen yet). Ask a city guard for the riding trainer.",
        "Then buy a mount from a mount vendor (a city guard knows where).",
    })
    t.eq(S.Of(nil, HERE, nil, 100), nil, "nothing due, no step")
end

T["riding step: a trainer seen with its price, short of money"] = function(t)
    local S = R()
    if type(S) ~= "table" then return t.ok(false, "no module") end
    local npcs = {
        ["Test Rider"] = { map = 1453, x = 0.3, y = 0.6, roles = { ridingTrainer = true },
                           ridingCosts = { [40] = 200000 } },
        ["Test Smith"] = { map = 1453, x = 0.5, y = 0.5, roles = { trainer = true } },
    }
    local step = S.Of(S.Due(40, {}), HERE, npcs, 150000)
    t.eq(step.place, { map = 1453, x = 0.3, y = 0.6 })
    t.eq(step.label, "Riding trainer: Test Rider")
    t.eq(S.Lines(step), {
        "You can learn riding now: about 20g at the riding trainer Test Rider.",
        "You need 5g more.",
        "Then buy a mount from a mount vendor (a city guard knows where).",
    })
    local rich = S.Of(S.Due(40, {}), HERE, npcs, 900000)
    t.eq(#S.Lines(rich), 2, "enough money: no line for it")
end

T["riding step: a trainer seen on another map is named, with no needle; price not seen"] = function(t)
    local S = R()
    if type(S) ~= "table" then return t.ok(false, "no module") end
    local npcs = { ["Test Rider"] = { map = 1411, x = 0.3, y = 0.6, roles = { ridingTrainer = true } } }
    local step = S.Of(S.Due(60, { ["Horse Riding"] = { rank = 75 } }), HERE, npcs, nil)
    t.eq(step.place, nil)
    t.eq(S.Lines(step), {
        "You can learn faster riding now at the riding trainer Test Rider (price not seen yet).",
        "Then buy a fast mount from a mount vendor.",
    })
end

T["riding step: a riding service is known by its name"] = function(t)
    local S = R()
    if type(S) ~= "table" then return t.ok(false, "no module") end
    t.eq(S.IsRiding("Horse Riding"), true)
    t.eq(S.IsRiding("Riding"), true)
    t.eq(S.IsRiding("Undead Horsemanship"), true)
    t.eq(S.IsRiding("Mechanostrider Piloting"), true)
    t.eq(S.IsRiding("Swords"), false)
    t.eq(S.IsRiding(nil), false)
end

return T

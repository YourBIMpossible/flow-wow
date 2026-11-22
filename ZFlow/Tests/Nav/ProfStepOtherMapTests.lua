-- The profession step for a trainer on another map (owner decision D10):
-- text only. The label says so, there is no place to point at (so no needle
-- and no distance), and where the trainer was seen is kept beside it. It is
-- said only when the map the player is on is known. Pure: no game client.
local _, ns = ...

local N = ns.Nav

local DASH = "\226\128\148"

local function here(over)
    local h = {
        position = { map = 1411, x = 0.5, y = 0.5 },
        zone = { cont = 1, zone = 1411 },
        faction = "Horde",
        mapSize = function(map)
            if map == 1411 then return { w = 1000, h = 500 } end
            return nil
        end,
    }
    for k, v in pairs(over or {}) do
        if v == false then h[k] = nil else h[k] = v end
    end
    return h
end

local function trainer(map, x, y, prof)
    return { map = map, x = x, y = y, roles = { trainer = true }, trains = { [prof or "Cooking"] = true },
             factions = { Horde = true }, id = 3026, seen = 100, n = 1 }
end

local function capped() return { line = 185, skill = 75, max = 75, at = 50 } end

local T = {}

T["other map: the step is the text, with no place and no radius"] = function(t)
    local npcs = { Aska = trainer(1412, 0.3, 0.4) }
    local step, why = N.ProfStep({ Cooking = capped() }, npcs, {}, here())
    t.eq(why, nil)
    t.eq(step, { label = "Cooking trainer " .. DASH .. " other map", still = true,
                 elsewhere = { map = 1412, x = 0.3, y = 0.4 } })
end

T["other map: the dash is the one long dash, three bytes"] = function(t)
    t.eq(N.PROF_OTHER_MAP, " " .. DASH .. " other map")
    t.eq(#N.PROF_OTHER_MAP, 14)
end

T["other map: the step shares nothing with the saved entry"] = function(t)
    local npcs = { Aska = trainer(1412, 0.3, 0.4) }
    local step = N.ProfStep({ Cooking = capped() }, npcs, {}, here())
    step.elsewhere.x = 0
    t.eq(npcs.Aska.x, 0.3)
end

T["other map: the guide gives it no distance, no turn and no needle"] = function(t)
    local step = N.ProfStep({ Cooking = capped() }, { Aska = trainer(1412, 0.3, 0.4) }, {}, here())
    local state = N.Guide({
        position = { map = 1411, x = 0.5, y = 0.5 }, zone = { cont = 1, zone = 1411 }, facing = 0,
        link = { [1411] = { w = 1000, h = 500 }, [1412] = { w = 800, h = 800 } },
        prof = step,
    })
    t.eq(state.prof.hasStep, true)
    t.eq(state.prof.label, "Cooking trainer " .. DASH .. " other map")
    t.eq(state.prof.distance, nil, "even with the sizes of both maps known")
    t.eq(state.prof.turn, nil)
end

T["other map: the map the player is on is not known, so it is not said"] = function(t)
    local npcs = { Aska = trainer(1412, 0.3, 0.4) }
    local want = { label = "Cooking trainer", place = { map = 1412, x = 0.3, y = 0.4 }, radius = N.PROF_NEAR }
    t.eq(N.ProfStep({ Cooking = capped() }, npcs, {}, here({ position = false })), want, "no position")
    t.eq(N.ProfStep({ Cooking = capped() }, npcs, {}, here({ position = { x = 0.5, y = 0.5 } })), want,
        "a position with no map")
    t.eq(N.ProfStep({ Cooking = capped() }, npcs, {}, here({ position = "here" })), want, "not a table")
end

T["other map: a label over the limit is left out, never cut, and the step is still text only"] = function(t)
    local long = ("Tinkering"):rep(3)        -- 27 bytes; with " trainer" and the rest: 49
    local npcs = { Aska = trainer(1412, 0.3, 0.4, long) }
    local step = N.ProfStep({ [long] = capped() }, npcs, {}, here())
    t.eq(step, { still = true, elsewhere = { map = 1412, x = 0.3, y = 0.4 } })
end

T["other map: a label that just fits is kept whole"] = function(t)
    -- 18 + 8 (" trainer") + 14 = 40 bytes, the limit.
    local name = ("A"):rep(18)
    local step = N.ProfStep({ [name] = capped() }, { Aska = trainer(1412, 0.3, 0.4, name) }, {}, here())
    t.eq(step.label, name .. " trainer " .. DASH .. " other map")
    t.eq(#step.label, 40)
end

T["this map: the step is as before"] = function(t)
    local step = N.ProfStep({ Cooking = capped() }, { Aska = trainer(1411, 0.6, 0.5) }, {}, here())
    t.eq(step, { label = "Cooking trainer", place = { cont = 1, map = 1411, x = 0.6, y = 0.5 },
                 radius = N.PROF_NEAR })
end

T["one here and one elsewhere: the one here is the step"] = function(t)
    local npcs = { Aska = trainer(1412, 0.1, 0.1), Zed = trainer(1411, 0.2, 0.2) }
    local step = N.ProfStep({ Cooking = capped() }, npcs, {}, here())
    t.eq(step.label, "Cooking trainer")
    t.eq(step.place.map, 1411)
    t.eq(step.elsewhere, nil)
end

return T

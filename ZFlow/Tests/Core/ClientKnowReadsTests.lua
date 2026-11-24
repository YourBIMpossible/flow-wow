local _, ns = ...
-- The KNOW lane's three client reads (lead section 487) on the real client
-- made over a made-up environment: unspentTalents, actionSpells and
-- talentRanks. Each answers nil ("not known") when its call is absent,
-- raises or is hidden, and reads only. Made-up spells and talents. Not
-- tested in game.
local tests = {}

local function made(env) return ns.make.client(env) end

tests["client know reads: unspent talent points - a count, or not known"] = function(t)
    t.eq(made({}).unspentTalents(), nil, "no call")
    t.eq(made({ UnitCharacterPoints = function() return 3, 0 end }).unspentTalents(), 3)
    t.eq(made({ UnitCharacterPoints = function() return 0 end }).unspentTalents(), 0)
    t.eq(made({ UnitCharacterPoints = function() error("no") end }).unspentTalents(), nil, "raises")
    t.eq(made({ UnitCharacterPoints = function() return "3" end }).unspentTalents(), nil, "not a count")
    t.eq(made({ UnitCharacterPoints = function() return -1 end }).unspentTalents(), nil, "below 0")
    t.eq(made({ UnitCharacterPoints = function() return 3 end,
                issecretvalue = function() return true end }).unspentTalents(), nil, "hidden")
end

local function barEnv(slots, state)
    return {
        HasAction = function(slot)
            if state and state.raise then error("bars not ready") end
            return slots[slot] ~= nil
        end,
        GetActionInfo = function(slot)
            local s = slots[slot]
            if not s then return nil end
            return s[1], s[2]
        end,
        GetSpellInfo = function(id) return ({ [11] = "Test Strike", [12] = "Test Shout", [13] = "Test Form" })[id] end,
    }
end

tests["client know reads: the spells on the bars by name, the lowest slot first"] = function(t)
    t.eq(made({}).actionSpells(), nil, "no calls")
    local env = barEnv({ [2] = { "spell", 11 }, [3] = { "item", 12 }, [40] = { "spell", 11 }, [61] = { "spell", 12 } })
    t.eq(made(env).actionSpells(), { ["Test Strike"] = 2, ["Test Shout"] = 61 })
    t.eq(made(barEnv({})).actionSpells(), {}, "empty bars are known to be empty")
    env.GetNumShapeshiftForms = function() return 1 end
    env.GetShapeshiftFormInfo = function() return "icon", true, true, 13 end
    t.eq(made(env).actionSpells()["Test Form"], 0, "a stance bar spell is slot 0")
end

-- A read that raises is "not known", and the answer comes back once it stops.
tests["client know reads: bars that raise are not known, then read again"] = function(t)
    local state = { raise = true }
    local c = made(barEnv({ [1] = { "spell", 11 } }, state))
    t.eq(c.actionSpells(), nil, "raises: not known, never an empty bar")
    state.raise = false
    t.eq(c.actionSpells(), { ["Test Strike"] = 1 })
    local hid = barEnv({ [1] = { "spell", 11 } })
    hid.issecretvalue = function() return true end
    t.eq(made(hid).actionSpells(), nil, "hidden")
end

local function talentEnv(tabs, state)
    return {
        GetNumTalentTabs = function() return #tabs end,
        GetNumTalents = function(tab) return #tabs[tab] end,
        GetTalentInfo = function(tab, i)
            if state and state.raise then error("talents not ready") end
            local row = tabs[tab][i]
            return row[1], "icon", 1, i, row[2], 5
        end,
    }
end

tests["client know reads: the talents the player has, by name"] = function(t)
    t.eq(made({}).talentRanks(), nil, "no calls")
    local tabs = { { { "Test Wrath", 5 }, { "Test Grasp", 0 } }, { { "Test Fury", 2 } } }
    t.eq(made(talentEnv(tabs)).talentRanks(), { ["Test Wrath"] = 5, ["Test Grasp"] = 0, ["Test Fury"] = 2 })
    t.eq(made(talentEnv({})).talentRanks(), nil, "no talent named: not known")
    local state = { raise = true }
    local c = made(talentEnv(tabs, state))
    t.eq(c.talentRanks(), nil, "raises")
    state.raise = false
    t.eq(c.talentRanks()["Test Fury"], 2, "read again once it answers")
end

return tests

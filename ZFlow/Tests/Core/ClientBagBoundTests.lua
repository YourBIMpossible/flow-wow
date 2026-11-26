-- c.bagItems() says whether each stack is soulbound (E-new-8): bound =
-- true|false from C_Container.GetContainerItemInfo(bag, slot).isBound,
-- absent when the client does not say. The real client over a hand-built
-- environment, then ClientFake's own rows. Made-up items, test only. Not
-- seen on 16001 that isBound is there.
local _, ns = ...

local tests = {}

-- slots[bag][slot] = the slot's ContainerItemInfo; opts.secret: the one
-- value issecretvalue calls secret (it refuses nil).
local function newEnv(slots, opts)
    opts = opts or {}
    local env = { NUM_BAG_SLOTS = 1 }
    function env.issecretvalue(v)
        if v == nil then error("issecretvalue: nil") end
        return opts.secret ~= nil and v == opts.secret
    end
    env.C_Container = {
        GetContainerNumSlots = function(bag) return #(slots[bag] or {}) end,
        GetContainerItemInfo = function(bag, slot)
            local row = (slots[bag] or {})[slot]
            if row == false then return nil end
            return row
        end,
    }
    return env
end

tests["client bagItems: bound from isBound, absent when not said"] = function(t)
    local env = newEnv({
        [0] = { { itemID = 6948, stackCount = 1, isBound = true }, false, { itemID = 2589, stackCount = 12, isBound = false } },
        [1] = { { itemID = 2318, stackCount = 4 } },
    })
    t.eq(ns.make.client(env).bagItems(), {
        { item = 6948, count = 1, bound = true },
        { item = 2589, count = 12, bound = false },
        { item = 2318, count = 4 },
    })
end

tests["client bagItems: a hidden or odd isBound is left out; the bank rows have no bound"] = function(t)
    local env = newEnv({ [0] = { { itemID = 1, stackCount = 1, isBound = "yes" } }, [1] = {} })
    t.eq(ns.make.client(env).bagItems(), { { item = 1, count = 1 } })
    local secret = newEnv({ [0] = { { itemID = 1, stackCount = 1, isBound = true } }, [1] = {} }, { secret = true })
    t.eq(ns.make.client(secret).bagItems(), { { item = 1, count = 1 } })
    t.eq(ns.make.client(secret).bagSlots(), { { bag = 0, slot = 1, item = 1, count = 1 } }, "bagSlots unchanged")
end

tests["fake bagItems: bound passes through when set, absent otherwise"] = function(t)
    local c = ns.make.fakeClient()
    c.setBagItems({ { item = 6948, count = 1, bound = true }, { item = 2318, count = 4 } })
    t.eq(c.bagItems(), { { item = 6948, count = 1, bound = true }, { item = 2318, count = 4 } })
end

return tests

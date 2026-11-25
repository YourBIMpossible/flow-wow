-- C-42: c.equipmentSets() reads the player's saved equipment sets
-- (C_EquipmentSet), read only. The real client over a hand-built
-- environment, then ClientFake's twin.
local _, ns = ...

local tests = {}

-- opts.secret: the one value issecretvalue calls secret.
local function newEnv(opts)
    opts = opts or {}
    local env = { calls = {} }
    local function note(name) env.calls[#env.calls + 1] = name end
    function env.issecretvalue(v)
        if v == nil then error("issecretvalue: nil") end
        return opts.secret ~= nil and v == opts.secret
    end
    local info = {
        [3] = { "Tank", 132341, 3, true },
        [5] = { "Heal", 135907, 5, false },
    }
    local items = {
        [3] = { [1] = 7001, [5] = 7005, [6] = 0 },
        [5] = { [16] = 9016 },
    }
    env.C_EquipmentSet = {
        GetEquipmentSetIDs = function() note("ids") return opts.ids or { 3, 5 } end,
        GetEquipmentSetInfo = function(id)
            note("info")
            local i = info[id]
            if i == nil then return nil end
            return i[1], i[2], i[3], i[4]
        end,
        GetItemIDs = function(id) note("items") return items[id] end,
        UseEquipmentSet = function() note("UseEquipmentSet") end,
        SaveEquipmentSet = function() note("SaveEquipmentSet") end,
        CreateEquipmentSet = function() note("CreateEquipmentSet") end,
    }
    return env
end

tests["client equipmentSets: each set's id, name, icon, worn and items by slot"] = function(t)
    local env = newEnv()
    local sets = ns.make.client(env).equipmentSets()
    t.eq(sets, {
        { id = 3, name = "Tank", icon = 132341, worn = true, items = { [1] = 7001, [5] = 7005 } },
        { id = 5, name = "Heal", icon = 135907, worn = false, items = { [16] = 9016 } },
    })
end

tests["client equipmentSets: read only - never uses, saves or makes a set"] = function(t)
    local env = newEnv()
    ns.make.client(env).equipmentSets()
    for _, name in ipairs(env.calls) do
        t.ok(name == "ids" or name == "info" or name == "items", "asked only to read: " .. name)
    end
end

tests["client equipmentSets: no C_EquipmentSet or no list is nil; none saved is {}"] = function(t)
    t.eq(ns.make.client({}).equipmentSets(), nil)
    local broken = newEnv()
    broken.C_EquipmentSet.GetEquipmentSetIDs = function() error("no") end
    t.eq(ns.make.client(broken).equipmentSets(), nil)
    t.eq(ns.make.client(newEnv({ ids = {} })).equipmentSets(), {})
end

tests["client equipmentSets: a secret name skips the set; a secret icon is left out"] = function(t)
    t.eq(#ns.make.client(newEnv({ secret = "Tank" })).equipmentSets(), 1)
    local sets = ns.make.client(newEnv({ secret = 132341 })).equipmentSets()
    t.eq(sets[1].icon, nil)
    t.eq(sets[1].name, "Tank")
    t.eq(#ns.make.client(newEnv({ ids = { 3, 99 } })).equipmentSets(), 1, "a set that will not say is skipped")
end

tests["fake equipmentSets: nil until set, then copies"] = function(t)
    local c = ns.make.fakeClient()
    t.eq(c.equipmentSets(), nil)
    local list = { { id = 1, name = "A", icon = 5, worn = true, items = { [1] = 10 } } }
    c.setEquipmentSets(list)
    local got = c.equipmentSets()
    list[1].items[1] = 99
    t.eq(got, { { id = 1, name = "A", icon = 5, worn = true, items = { [1] = 10 } } })
end

return tests

-- Parity row C-42, read only (lead section 789): the game's own equipment
-- sets (the Equipment Manager), listed beside Z-Flow's saved sets, each
-- with a role you give it, as Flow's sets per role (Modules/Gear/KeepSets.lua
-- :277-311). The read is a CLIENT NEED (client.equipmentSets: C_EquipmentSet
-- GetEquipmentSetIDs, GetEquipmentSetInfo, GetItemIDs, on warcraft.wiki.gg
-- for forever 1.60.1; from-zen/zflow-equipment-manager.md). Nothing creates,
-- saves or equips a game set; the role is Z-Flow's own saved data. Made-up
-- sets. Not tested in game. Fails before: the game's sets were never read.
local _, ns = ...
local tests = {}

local Sets = ns.GearSets

local GAME = {
    { id = 2, name = "Tank", icon = 1, worn = true, items = { [1] = 1001, [5] = 1002, [16] = 1003 } },
    { id = 1, name = "Dps", icon = 2, worn = false, items = { [16] = 1004 } },
}

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, opts.char or {})
    if opts.game ~= false then c.setEquipmentSets(opts.game or GAME) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

tests["gear sets C-42: the game's sets, by name, with their pieces and the one you wear"] = function(t)
    t.eq(type(Sets.Game), "function")
    if type(Sets.Game) ~= "function" then return end
    t.eq(Sets.Game(GAME, {}), {
        { name = "Dps", pieces = 1, worn = false },
        { name = "Tank", pieces = 3, worn = true },
    })
    t.eq(Sets.Game(GAME, { Tank = "tank" })[2].role, "tank", "the role you gave it")
    t.eq(Sets.Game(nil, {}), nil, "the game's sets not read")
    t.eq(Sets.Game({}, {}), {}, "read: none")
end

tests["gear sets C-42: the set word lists the game's sets too"] = function(t)
    if type(Sets.Game) ~= "function" then return t.ok(false, "no Game") end
    local _, addon = start({ char = { state = { gearSetRoles = { Tank = "tank" } } } })
    local lines = Sets.Run(addon, "")
    local all = table.concat(lines or {}, " / ")
    t.ok(all:find(Sets.GAME_HEAD, 1, true) ~= nil, all)
    t.ok(all:find("Tank (3 pieces, worn, tank)", 1, true) ~= nil, all)
    t.ok(all:find("Dps (1 piece)", 1, true) ~= nil, all)
    local _, none = start({ game = false })
    t.eq(table.concat(Sets.Run(none, "") or {}, " / "):find(Sets.GAME_HEAD, 1, true), nil, "not read: not listed")
end

tests["gear sets C-42: a role for a game set is Z-Flow's own data; nothing in the game changes"] = function(t)
    if type(Sets.Game) ~= "function" then return t.ok(false, "no Game") end
    local c, addon = start()
    local lines, changed = Sets.Run(addon, "role Tank tank")
    t.eq(changed, true, table.concat(lines or {}, " / "))
    t.eq(addon.store:get("char", Sets.ROLES_PATH), { Tank = "tank" })
    _, changed = Sets.Run(addon, "role Tank none")
    t.eq(changed, true)
    t.eq(addon.store:get("char", Sets.ROLES_PATH), {}, "none takes it off")
    _, changed = Sets.Run(addon, "role Nope tank")
    t.eq(changed, false, "no game set of that name")
    _, changed = Sets.Run(addon, "role Tank wizard")
    t.eq(changed, false, "not a role")
    t.eq(c.equipmentSetCalls or 0, 0, "no set made, saved or put on")
end

return tests

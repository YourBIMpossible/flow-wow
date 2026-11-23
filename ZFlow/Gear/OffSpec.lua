local _, ns = ...

-- GearOffSpec (package P-SETS, G13): the keep-off-spec rule's facts for
-- Disposition. Gear in the bags that is an upgrade for another role of your
-- class is kept "better for <role>" (Disposition's laterOrOtherRole), while
-- the setting gear.keepOffspec (account, default on; Flow's own switch of
-- the same name is imported to it) holds. An upgrade for the chosen role
-- (spec.role) is kept as one.
--
--   facts = GearOffSpec.Facts(client, store, packs, stacks)
--     -> { gear = { [item key] = { canUse = true, diffs = { [role] = n } } },
--          role, keptRoles = { [role] = true } or nil (the setting off),
--          roleNames = { [role] = "Protection" } }, or nil when the class or
--          its pack's weights are not known.
--   GearOffSpec.Apply(context, client, store, packs, stacks)
--     the same facts written into a Disposition context; a read that raises
--     leaves the context as it was (nothing more is kept, nothing sold).
--
-- diffs[role] is the score gain over what is worn (Gear/Score.lua delta),
-- only for a role whose verdict says you can use the item. Gear facts are
-- given only for items that are gear you can use: context.gearRead is never
-- set here, so the "not gear" fallback keeps nothing new.
-- The roles are the pack's weights (all nine class packs have them); a
-- class with one role has no other role to keep for.
-- LOOK ONLY. Nothing is equipped, moved or sold; it reads the bags, the
-- item reads and the saved settings.

local O = {}
ns.GearOffSpec = O

O.NAME = "gearOffSpec"
O.SETTING = "gear.keepOffspec"
O.PATH = "settings.gear.keepOffspec"   -- account
O.ROLE_PATH = "settings.spec.role"     -- char (Rotation/Role.lua's spec.role)
O.DEFAULT = true
O.GEAR_CLASSES = { [2] = true, [4] = true }   -- the game's weapon and armour item classes

local function ask(client, read, ...)
    if type(client) ~= "table" or type(client[read]) ~= "function" then return nil end
    return client[read](...)
end

local function saved(store, scope, path)
    if type(store) ~= "table" or type(store.get) ~= "function" then return nil end
    local ok, v = pcall(store.get, store, scope, path)
    if not ok then return nil end
    return v
end

local function rolesOf(pack)
    local out = {}
    for role, w in pairs(pack.weights) do
        if type(role) == "string" and type(w) == "table" then out[#out + 1] = role end
    end
    table.sort(out)
    return out
end

local function nameOf(pack, role)
    local row = nil
    if type(pack.roles) == "table" then row = pack.roles[role] end
    if type(row) == "table" and type(row.name) == "string" and row.name ~= "" then return row.name end
    if type(ns.RotationRole) == "table" and type(ns.RotationRole.WORDS) == "table"
        and type(ns.RotationRole.WORDS[role]) == "string" then return ns.RotationRole.WORDS[role] end
    return role
end

local function plain(n)
    return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- One item's gear facts, or nil when it is not gear you can use.
local function factsOf(client, link, who, roles)
    local gear = ask(client, "gear", link)
    if type(gear) ~= "table" then return nil end
    local diffs, canUse = {}, false
    for i = 1, #roles do
        who.role = roles[i]
        local lines, detail = ns.GearVerdict.Lines(gear, who)
        if lines == nil then return nil end
        local use, result = nil, nil
        if type(detail) == "table" then use, result = detail.use, detail.result end
        if type(use) == "table" and use.can == true then
            canUse = true
            if type(result) == "table" and plain(result.delta) then diffs[roles[i]] = result.delta end
        end
    end
    if not canUse then return nil end
    return { canUse = true, diffs = diffs }
end

function O.Facts(client, store, packs, stacks)
    local class = ask(client, "class")
    local pack = nil
    if type(packs) == "table" and class ~= nil then pack = packs[class] end
    if type(pack) ~= "table" or type(pack.weights) ~= "table" then return nil end
    local roles = rolesOf(pack)
    if #roles == 0 then return nil end

    local out = { gear = {}, roleNames = {} }
    for i = 1, #roles do out.roleNames[roles[i]] = nameOf(pack, roles[i]) end
    local role = saved(store, "char", O.ROLE_PATH)
    if type(role) == "string" and type(pack.weights[role]) == "table" then out.role = role end
    if saved(store, "account", O.PATH) ~= false then
        out.keptRoles = {}
        for i = 1, #roles do out.keptRoles[roles[i]] = true end
    end

    local who = { pack = pack, level = ask(client, "level") }
    local okSkills, skills = pcall(ask, client, "weaponSkills")
    if okSkills and type(skills) == "table" then who.skills = skills end
    local info = nil
    if type(client) == "table" and type(client.itemInfo) == "function" then info = client.itemInfo end
    for _, s in ipairs(type(stacks) == "table" and stacks or {}) do
        local link, key = nil, nil
        if type(s) == "table" then link = s.item end
        if type(link) == "string" and link ~= "" then key = ns.Items.Key(link) end
        if key ~= nil and out.gear[key] == nil then
            local gearClass = true
            if info then
                local okI, i = pcall(info, link)
                if okI and type(i) == "table" and type(i.classID) == "number" then
                    gearClass = O.GEAR_CLASSES[i.classID] == true
                end
            end
            if gearClass then
                local f = factsOf(client, link, who, roles)
                if f then out.gear[key] = f end
            end
        end
    end
    return out
end

function O.Apply(context, client, store, packs, stacks)
    if type(context) ~= "table" then return false end
    local ok, facts = pcall(O.Facts, client, store, packs, stacks)
    if not ok or type(facts) ~= "table" then return false end
    context.gear = facts.gear
    context.role = facts.role
    context.keptRoles = facts.keptRoles
    context.roleNames = facts.roleNames
    return true
end

-- The setting row. Declared on kernel k when this file loads.
function O.Declare(k)
    k:Module({
        name = O.NAME,
        needs = { "settings" },
        settings = { {
            key = O.SETTING, scope = "account", type = "bool", default = O.DEFAULT,
            label = "Keep gear for your other roles",
            help = "Gear in your bags that is an upgrade for another role of your class (tanking, healing) is "
                .. "kept, never offered for sale. Off: only your chosen role counts.",
            group = "gear", synonyms = { "offspec", "off-spec", "spec", "role", "keep", "dual" },
        } },
        start = function() end,
    })
end

O.Declare(ns)

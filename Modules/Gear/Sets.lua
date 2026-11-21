-- Gear sets per role. Item scores are compared against the set for each
-- role, not just what you're wearing: a shield is judged against your Tank
-- set even while you're in your DPS gear.
--
-- Where sets come from (first match wins):
--   1. The game's Equipment Manager (character window), if this client has it.
--      Set names containing tank/prot, heal/holy, dps/ret are matched to roles
--      automatically; /flow gear set <role> <set name> picks one explicitly.
--   2. Flow's own saved sets: /flow gear save <role> saves what you're wearing.
-- Roles without a set are compared against what you're wearing.

local _, ns = ...
local G = ns.gear
local S = {}
G.sets = S

local ROLES = { "dps", "heal", "tank" }
local KEYWORDS = {
    tank = { "tank", "prot" },
    heal = { "heal", "holy" },
    dps  = { "dps", "ret", "damage" },
}

local blizz = {}   -- role -> { id, name, items = { [slot] = itemID } }

function S:HasEquipmentManager()
    return C_EquipmentSet ~= nil and C_EquipmentSet.GetEquipmentSetIDs ~= nil
end

local function bagLinkFor(itemID)
    local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local idOf = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
    local linkOf = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
    if not numSlots then return nil end
    for bag = 0, 4 do
        for slot = 1, numSlots(bag) or 0 do
            if idOf(bag, slot) == itemID then return linkOf(bag, slot) end
        end
    end
end

function S:Refresh()
    wipe(blizz)
    if not self:HasEquipmentManager() then return end
    local chosen = ns.db.gear.setRoles or {}
    local sets = {}
    for _, id in ipairs(C_EquipmentSet.GetEquipmentSetIDs() or {}) do
        local name = C_EquipmentSet.GetEquipmentSetInfo(id)
        if name then sets[#sets + 1] = { id = id, name = name } end
    end
    -- Explicit choices first, then name keywords for roles still free.
    for _, role in ipairs(ROLES) do
        for _, s in ipairs(sets) do
            if chosen[role] and s.name == chosen[role] then blizz[role] = s end
        end
    end
    for _, role in ipairs(ROLES) do
        if not blizz[role] then
            for _, s in ipairs(sets) do
                local lname = s.name:lower()
                for _, w in ipairs(KEYWORDS[role]) do
                    if not blizz[role] and lname:find(w, 1, true) then blizz[role] = s end
                end
            end
        end
    end
    for _, s in pairs(blizz) do
        s.items = C_EquipmentSet.GetItemIDs(s.id) or {}
    end
end

-- Name of the set used for a role, and where it comes from; nil if none.
function S:SetFor(role)
    if blizz[role] then return blizz[role].name, "Equipment Manager" end
    local mine = ns.db.gear.mySets and ns.db.gear.mySets[role]
    if mine then return ns.ROLE_LABEL[role] .. " (saved in Flow)", "Flow" end
end

function S:Has(role) return self:SetFor(role) ~= nil end
-- The game's own set used for a role ({ id, name, items }), or nil.
function S:GameSet(role) return blizz[role] end

-- Link of the item a role's set has in a slot; nil = slot empty in that set.
function S:Link(role, slot)
    local s = blizz[role]
    if s then
        local id = s.items[slot]
        if not id or id <= 1 then return nil end
        local worn = GetInventoryItemLink("player", slot)
        if worn and GetInventoryItemID("player", slot) == id then return worn end
        return bagLinkFor(id) or ("item:" .. id)
    end
    local mine = ns.db.gear.mySets and ns.db.gear.mySets[role]
    return mine and mine[slot] or nil
end

-- Roles whose set contains this item (by item ID).
function S:RolesContaining(link)
    local id = link and tonumber(link:match("item:(%d+)"))
    local out = {}
    if not id then return out end
    for _, role in ipairs(ROLES) do
        local found = false
        if blizz[role] then
            for _, itemID in pairs(blizz[role].items) do if itemID == id then found = true end end
        elseif ns.db.gear.mySets and ns.db.gear.mySets[role] then
            for _, l in pairs(ns.db.gear.mySets[role]) do
                if tonumber(l:match("item:(%d+)")) == id then found = true end
            end
        end
        if found then out[#out + 1] = role end
    end
    return out
end

local function saveWorn(role)
    ns.db.gear.mySets = ns.db.gear.mySets or {}
    local set = {}
    for slot = 1, 19 do
        local link = GetInventoryItemLink("player", slot)
        if link then set[slot] = link end
    end
    ns.db.gear.mySets[role] = set
end

ns:OnLoad(function(saved)
    saved.gear.setRoles = saved.gear.setRoles or {}
end)
-- Pure: the old (pre-split, shared) role choices that name one of this
-- character's own sets, added to what it has chosen since; nil = none (F-013).
function S.AdoptSetRoles(old, names, current)
    local have, out, any = {}, {}, false
    for _, n in ipairs(names or {}) do have[n] = true end
    for role, name in pairs(current or {}) do out[role] = name; any = true end
    for role, name in pairs(old or {}) do
        if out[role] == nil and have[name] then out[role] = name; any = true end
    end
    return any and out or nil
end

-- Equipment sets are per character: an alt keeps only the old roles that
-- name a set it has (another character's "Tank" set isn't its own). At
-- login, once the game can list its sets; no sets listed yet = try again.
ns:PerCharacter("gear.setRoles", { later = true, adopt = function(old, _, current)
    if not S:HasEquipmentManager() then return nil end
    local names = {}
    for _, id in ipairs(C_EquipmentSet.GetEquipmentSetIDs() or {}) do
        local name = C_EquipmentSet.GetEquipmentSetInfo(id)
        if name then names[#names + 1] = name end
    end
    if #names == 0 then return false end
    return S.AdoptSetRoles(old, names, current)
end })

for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "EQUIPMENT_SETS_CHANGED",
                      "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED" }) do
    ns:On(ev, function() S:Refresh() end)
end

-- /flow gear sets | set <role> <name> | save <role> | forget <role>
function S:Command(arg)
    local cmd, role, rest = (arg or ""):match("^(%S*)%s*(%S*)%s*(.-)$")
    role = role and role:lower()
    local valid = role == "dps" or role == "heal" or role == "tank"
    if cmd == "set" and valid and rest ~= "" then
        ns.db.gear.setRoles[role] = rest
        self:Refresh()
        ns:Print(string.format("%s gear is compared with the set '%s'%s", ns.ROLE_LABEL[role], rest,
            blizz[role] and "" or " (no Equipment Manager set by that name yet)"))
    elseif cmd == "save" and valid then
        saveWorn(role)
        ns:Print("saved what you're wearing as your " .. ns.ROLE_LABEL[role] .. " set (in Flow)")
    elseif cmd == "forget" and valid then
        ns.db.gear.setRoles[role] = nil
        if ns.db.gear.mySets then ns.db.gear.mySets[role] = nil end
        self:Refresh()
        ns:Print("forgot the " .. ns.ROLE_LABEL[role] .. " set")
    else
        ns:Print("gear sets (Equipment Manager available: " .. (self:HasEquipmentManager() and "yes" or "no") .. "):")
        for _, r in ipairs(ROLES) do
            local name, from = self:SetFor(r)
            print(string.format("  |cff%s%s|r: %s", ns.ROLE_COLOR[r], ns.ROLE_LABEL[r],
                name and (name .. " (" .. from .. ")") or "none, compared with what you wear"))
        end
        print("  /flow gear set <dps|heal|tank> <set name>   use an Equipment Manager set")
        print("  /flow gear save <dps|heal|tank>              save what you wear as that set")
    end
end

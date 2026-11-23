local _, ns = ...

-- N8 (lead section 238): healing items in a fight, as legacy Flow
-- (Modules/Rotation/BuffItems.lua: HealKind, rankOf, PickEmergency).
-- It only reads: nothing is used here.
--
--   HI.Kind(info) -> "healthstone", "potion" or nil
--       "Healthstone" in the name; "Healing Potion" in the name, or class
--       0 (consumable), subclass HI.POTION_SUB with "Healing" in the name.
--       Flow's rules; first guesses on this client, not seen in game.
--   HI.Rank(info) -> number   item level + required level / 1000
--   HI.Read(client) -> pick, partial
--       pick = { stone, stoneName, potion, potionName }: the best of each
--       in your bags by rank ({} when there is neither); nil when the bags
--       were not read. partial: true when some item's info was not read
--       yet (section 236), so the pick may change when it arrives.
local HI = {}
ns.HealItems = HI

HI.POTION_SUB = 1

local function has(name, word) return string.find(name, word, 1, true) ~= nil end

function HI.Kind(info)
    if type(info) ~= "table" or type(info.name) ~= "string" then return nil end
    local name = info.name
    if has(name, "Healthstone") then return "healthstone" end
    if has(name, "Healing Potion") then return "potion" end
    if info.classID == 0 and info.subclassID == HI.POTION_SUB and has(name, "Healing") then return "potion" end
    return nil
end

function HI.Rank(info)
    if type(info) ~= "table" then return 0 end
    local level = type(info.level) == "number" and info.level or 0
    local need = type(info.minLevel) == "number" and info.minLevel or 0
    return level + need / 1000
end

function HI.Read(client)
    if type(client) ~= "table" or type(client.bagItems) ~= "function"
        or type(client.itemInfo) ~= "function" then
        return nil, false
    end
    local ok, stacks = pcall(client.bagItems)
    if not ok or type(stacks) ~= "table" then return nil, false end
    local best, seen, partial = {}, {}, false
    for _, st in ipairs(stacks) do
        local id = type(st) == "table" and ns.Items.Id(st.item) or nil
        local count = type(st) == "table" and st.count or nil
        local some = count == nil or (type(count) == "number" and count > 0)
        if id and some and not seen[id] then
            seen[id] = true
            local okI, info = pcall(client.itemInfo, id)
            if not okI or type(info) ~= "table" or type(info.name) ~= "string" then
                partial = true
            else
                local kind = HI.Kind(info)
                if kind then
                    local rank, b = HI.Rank(info), best[kind]
                    if not b or rank > b.rank or (rank == b.rank and id < b.id) then
                        best[kind] = { id = id, name = info.name, rank = rank }
                    end
                end
            end
        end
    end
    local pick = {}
    if best.healthstone then pick.stone, pick.stoneName = best.healthstone.id, best.healthstone.name end
    if best.potion then pick.potion, pick.potionName = best.potion.id, best.potion.name end
    return pick, partial
end

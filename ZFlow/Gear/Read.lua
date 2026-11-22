local _, ns = ...

-- Gear read: turns what the client answered about items into the shapes
-- Gear/Score.lua takes. Pure: every value comes in as data, already read by
-- someone else. Nothing here calls the game, and nothing is made up for a
-- value that was not read.
--
--   stats, unmapped          = GearRead.Stats(raw)
--   item, unmapped           = GearRead.Item(kind, raw)
--   equipped, unmapped, ignored = GearRead.Equipped(worn)
--   can                      = GearRead.Can(dualWield)
--   out                      = GearRead.Shapes(input)
--   yes                      = GearRead.Known(key)
--
--   raw    an item's stats as the client's item-stats call answers them:
--          { [key] = number }, keyed by the client's own names
--          ("ITEM_MOD_STRENGTH_SHORT", "RESISTANCE0_NAME"). nil, or anything
--          that is not a table: the stats were not read.
--   kind   the item's equip location as the client names it
--          ("INVTYPE_HEAD"). Not a non-empty string: not read.
--   worn   what is worn, by the client's inventory slot number:
--          { [id] = { kind, stats = raw } for an item,
--            [id] = false for a slot read and found empty }.
--          A slot with no entry was not read. It stays absent in `equipped`:
--          it is never turned into false, because false means "empty" to
--          the scorer and an empty slot makes every item an upgrade. An
--          entry that is neither a table nor false was not read either.
--   dualWield   true or false as read; anything else: not known.
--   input  { kind, stats = raw, worn, dualWield }: one candidate item and
--          everything else at once.
--   out    { candidate, equipped, can, unmapped, ignored }: the three
--          arguments of GearScore.Compare, and the two lists below.
--
-- Stats keep the client's own keys: the class weights (ZFlow/Classes) are
-- written with those same keys, so no name is translated and none can be
-- translated wrongly. A value that is not a plain number is kept as false,
-- "on the item but not read", which the scorer never counts as 0.
--
-- unmapped: the keys in the stats that are not in GearRead.KEYS, sorted,
--   each once. Such a key is still kept in the stats (leaving it out would
--   read as "the item does not have it"); it is named so that a stat no
--   weight table knows about is seen and not lost. A key that is not a name
--   at all (a number, say) cannot be a stat: it is named and left out.
-- ignored: the entries of `worn` that are not a slot the scorer compares
--   (the shirt, the tabard, any other number or name), as text, sorted.
--
-- What the caller is expected to have read (the wiring is Core/Client.lua's,
-- not this file's; each is a first guess until seen on the client):
--   raw        C_Item.GetItemStats(link), or GetItemStats(link)
--   kind       the equip location answer of GetItemInfoInstant(link)
--   worn[id]   GetInventoryItemLink("player", id) and the two reads above
--              for that link; false only when the client says plainly that
--              the slot holds nothing (GetInventoryItemID("player", id) is
--              nil). A link that is not loaded yet is "not read": no entry.
--   dualWield  whether you can hold a weapon in the off hand (CanDualWield()
--              or the dual wield spell being known); no answer: leave it out.

local G = {}
ns.GearRead = G

-- The stat keys Z-Flow's weight tables name. Origin: every key used in the
-- weights of ZFlow/Classes/Druid.lua and ZFlow/Classes/Paladin.lua at fork
-- zflow 752445a, which took them from the predecessor's class data. They
-- are the client's names; no value belongs to any of them here.
G.KEYS = {
    "ITEM_MOD_AGILITY_SHORT",
    "ITEM_MOD_ATTACK_POWER_SHORT",
    "ITEM_MOD_BLOCK_RATING_SHORT",
    "ITEM_MOD_BLOCK_VALUE_SHORT",
    "ITEM_MOD_CRIT_RATING_SHORT",
    "ITEM_MOD_DAMAGE_PER_SECOND_SHORT",
    "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT",
    "ITEM_MOD_DODGE_RATING_SHORT",
    "ITEM_MOD_HASTE_RATING_SHORT",
    "ITEM_MOD_HIT_RATING_SHORT",
    "ITEM_MOD_INTELLECT_SHORT",
    "ITEM_MOD_MANA_REGENERATION_SHORT",
    "ITEM_MOD_MASTERY_RATING_SHORT",
    "ITEM_MOD_PARRY_RATING_SHORT",
    "ITEM_MOD_SPELL_HEALING_DONE_SHORT",
    "ITEM_MOD_SPELL_POWER_SHORT",
    "ITEM_MOD_SPIRIT_SHORT",
    "ITEM_MOD_STAMINA_SHORT",
    "ITEM_MOD_STRENGTH_SHORT",
    "ITEM_MOD_VERSATILITY",
    "RESISTANCE0_NAME",
}

local KNOWN = {}
for i = 1, #G.KEYS do KNOWN[G.KEYS[i]] = true end

-- The client's inventory slot numbers, to the scorer's slot names
-- (GearScore.SLOTS). 4 is the shirt and 19 the tabard: not compared.
G.SLOT_OF = {
    [1] = "head", [2] = "neck", [3] = "shoulder", [5] = "chest", [6] = "waist", [7] = "legs",
    [8] = "feet", [9] = "wrist", [10] = "hands", [11] = "finger1", [12] = "finger2",
    [13] = "trinket1", [14] = "trinket2", [15] = "back", [16] = "mainHand", [17] = "offHand",
    [18] = "ranged",
}

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Adds each name of `more` to the list `into` once (seen: what is in it).
local function gather(into, seen, more)
    for i = 1, #more do
        if not seen[more[i]] then
            seen[more[i]] = true
            into[#into + 1] = more[i]
        end
    end
end

function G.Known(key)
    return KNOWN[key] == true
end

function G.Stats(raw)
    if type(raw) ~= "table" then return nil, {} end
    local stats, unmapped = {}, {}
    for key, value in pairs(raw) do
        if type(key) == "string" then
            stats[key] = finite(value) and value or false
            if not KNOWN[key] then unmapped[#unmapped + 1] = key end
        else
            unmapped[#unmapped + 1] = tostring(key)
        end
    end
    table.sort(unmapped)
    return stats, unmapped
end

function G.Item(kind, raw)
    local stats, unmapped = G.Stats(raw)
    local item = { stats = stats }
    if type(kind) == "string" and kind ~= "" then item.kind = kind end
    return item, unmapped
end

function G.Equipped(worn)
    local equipped, unmapped, ignored = {}, {}, {}
    if type(worn) ~= "table" then return equipped, unmapped, ignored end
    local seen = {}
    for id, entry in pairs(worn) do
        local slot = G.SLOT_OF[id]
        if not slot then
            ignored[#ignored + 1] = tostring(id)
        elseif entry == false then
            equipped[slot] = false
        elseif type(entry) == "table" then
            local item, more = G.Item(entry.kind, entry.stats)
            equipped[slot] = item
            gather(unmapped, seen, more)
        end
        -- Anything else was not read: the slot stays absent.
    end
    table.sort(unmapped)
    table.sort(ignored)
    return equipped, unmapped, ignored
end

function G.Can(dualWield)
    local can = {}
    if type(dualWield) == "boolean" then can.dualWield = dualWield end
    return can
end

function G.Shapes(input)
    input = type(input) == "table" and input or {}
    local candidate, fromItem = G.Item(input.kind, input.stats)
    local equipped, fromWorn, ignored = G.Equipped(input.worn)
    local unmapped, seen = {}, {}
    gather(unmapped, seen, fromItem)
    gather(unmapped, seen, fromWorn)
    table.sort(unmapped)
    return { candidate = candidate, equipped = equipped, can = G.Can(input.dualWield),
             unmapped = unmapped, ignored = ignored }
end

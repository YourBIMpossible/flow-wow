local _, ns = ...

-- Parity row A2-12 (lead section 794): a step with no place says which mobs
-- drop what it needs and how often, as Flow's Modules/Nav/Goals.lua
-- (ns.quests.DropRate :440 and MobLines :452), but from the player's own
-- loot record (Items/Drops.lua, char "learned.drops": { [npc id] = { name,
-- looted, items = { [item key] = { count, times } } } }), never a table or
-- another add-on's rate (owner section 611). A share is said only from
-- Drops.MIN_SAMPLES loots of that creature on, as Drops itself says; below
-- it, the counts. A mob's level, when the caller knows it (the player's own
-- Questie), is put after its name.
--   rows  = DL.Rows(book, itemName, nameOf)  { { npc, name, times, looted,
--           share } } most often first; nameOf(item key) -> the item's name
--   lines = DL.Lines(rows, levelOf)          at most MAX; levelOf(npc) ->
--           min, max (or nil)
-- Pure. Showing the lines on the words-only step (Nav/QuestSource.lua's
-- worded step, shown by UI/Arrow.lua) needs the store and the item read
-- there: a LEAD NEED. Not tested in game.
ns.Nav = ns.Nav or {}
local DL = {}
ns.Nav.DropLines = DL

DL.MAX = 6           -- as Flow's MOB_LINES
DL.LINE = "%s: %d of your %d loots"
DL.SHARE = " (%d%%)"

local function count(v) return type(v) == "number" and v == v and v >= 0 and v ~= math.huge end

local function minSamples()
    local D = ns.Drops
    if type(D) == "table" and count(D.MIN_SAMPLES) then return D.MIN_SAMPLES end
    return 30
end

function DL.Rows(book, itemName, nameOf)
    local out = {}
    if type(book) ~= "table" or type(itemName) ~= "string" or itemName == "" or type(nameOf) ~= "function" then
        return out
    end
    local need = minSamples()
    for npc, e in pairs(book) do
        if type(e) == "table" and type(e.items) == "table" and count(e.looted) and e.looted > 0 then
            local times = 0
            for key, it in pairs(e.items) do
                local ok, name = pcall(nameOf, key)
                if ok and name == itemName and type(it) == "table" and count(it.times) then times = times + it.times end
            end
            if times > 0 then
                local row = { npc = npc, name = tostring(e.name or ("creature " .. tostring(npc))), times = times,
                              looted = e.looted }
                if e.looted >= need then row.share = math.floor(times / e.looted * 100 + 0.5) end
                out[#out + 1] = row
            end
        end
    end
    table.sort(out, function(a, b)
        if a.times ~= b.times then return a.times > b.times end
        return a.name < b.name
    end)
    return out
end

function DL.Lines(rows, levelOf)
    local out = {}
    if type(rows) ~= "table" then return out end
    for i = 1, math.min(#rows, DL.MAX) do
        local r = rows[i]
        local name = r.name
        if type(levelOf) == "function" then
            local ok, lo, hi = pcall(levelOf, r.npc)
            if ok and count(lo) then
                if count(hi) and hi ~= lo then name = name .. " (" .. lo .. "-" .. hi .. ")"
                else name = name .. " (" .. lo .. ")" end
            end
        end
        local line = DL.LINE:format(name, r.times, r.looted)
        if r.share then line = line .. DL.SHARE:format(r.share) end
        out[#out + 1] = line
    end
    return out
end

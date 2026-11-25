local _, ns = ...
-- Parity row A2-12 (lead section 794): a step with no place says which mobs
-- drop what it needs and how often, as Flow's Modules/Nav/Goals.lua
-- (ns.quests.DropRate :440, MobLines :452), but from the player's own loot
-- record (Items/Drops.lua, char "learned.drops"), never a table or another
-- add-on's rate. A share is said only from Drops.MIN_SAMPLES loots of that
-- creature on; below it, the counts. A mob's level comes from the caller
-- (the player's own Questie). Made-up mobs and items. Not tested in game.
-- Fails before: no such file.
local tests = {}

local function DL() return ns.Nav and ns.Nav.DropLines end

local PAW = 3001
local BOOK = {
    [101] = { name = "Gnoll Brute", looted = 40, items = { [PAW] = { count = 5, times = 4 } } },
    [102] = { name = "Gnoll Runt", looted = 12, items = { [PAW] = { count = 3, times = 3 } } },
    [103] = { name = "Wolf", looted = 50, items = { [9] = { count = 1, times = 1 } } },
}
local function nameOf(key) if key == PAW then return "Gnoll Paw" end return "Other" end

tests["drop lines: the mobs that dropped the item for you, most often first"] = function(t)
    t.eq(type(DL()), "table", "loaded")
    if type(DL()) ~= "table" then return end
    local rows = DL().Rows(BOOK, "Gnoll Paw", nameOf)
    t.eq(#rows, 2, "the wolf never dropped it")
    t.eq({ rows[1].npc, rows[1].name, rows[1].times, rows[1].looted }, { 101, "Gnoll Brute", 4, 40 })
    t.eq(rows[1].share, 10, "40 loots: a share, in percent")
    t.eq(rows[2].share, nil, "12 loots: too few for a share")
    t.eq(DL().Rows(BOOK, "Nothing", nameOf), {})
    t.eq(DL().Rows(nil, "Gnoll Paw", nameOf), {})
end

tests["drop lines: the words, with a level when known"] = function(t)
    if type(DL()) ~= "table" then return t.ok(false, "not loaded") end
    local rows = DL().Rows(BOOK, "Gnoll Paw", nameOf)
    local function levelOf(npc) if npc == 101 then return 12, 14 end return nil end
    local lines = DL().Lines(rows, levelOf)
    t.eq(lines[1], "Gnoll Brute (12-14): 4 of your 40 loots (10%)")
    t.eq(lines[2], "Gnoll Runt: 3 of your 12 loots")
    t.eq(DL().Lines({}, levelOf), {}, "none: no lines")
    local many = {}
    for i = 1, 8 do many[i] = { npc = i, name = "Mob " .. i, times = 1, looted = 2 } end
    -- Lead section 808: past MAX, one more line says how many are left out
    -- (as Flow's Goals.lua:467-469); our own words.
    local lines8 = DL().Lines(many, nil)
    t.eq(#lines8, DL().MAX + 1, "MAX lines, then how many more")
    t.eq(lines8[DL().MAX + 1], "2 more mobs also drop it")
    t.eq(#DL().Lines({ many[1], many[2] }, nil), 2, "under MAX: no such line")
    local six = {}
    for i = 1, DL().MAX do six[i] = many[i] end
    t.eq(#DL().Lines(six, nil), DL().MAX, "exactly MAX: no such line")
    -- Nit: a level is shown only when it is above 0.
    local function zero() return 0, 0 end
    t.eq(DL().Lines({ many[1] }, zero)[1], "Mob 1: 1 of your 2 loots", "level 0: none shown")
    local function low() return 0, 5 end
    t.eq(DL().Lines({ many[1] }, low)[1], "Mob 1: 1 of your 2 loots", "a low end of 0: none shown")
end

return tests

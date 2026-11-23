-- The Dungeon Quests window's Bosses tab (lead section 303 item 8 (e)), end
-- to end on the whole add-on loaded on a fake client: the bosses of the
-- picked dungeon with the loot this account has seen from them
-- (UI/BossLoot.lua's learned.bossLoot), each item a kit item line that
-- carries the item, so the kit shows the game's own item tooltip on hover.
-- No loot table: only what this account saw. A made-up Questie and made-up
-- loot. Not tested in game.
local _, ns = ...
local tests = {}

local ID = "dungeons"
local DM = 1581

local function questie()
    local quests = {
        [101] = { Id = 101, name = "Red Silk", level = 18, requiredLevel = 14, zoneOrSort = DM,
            Starts = { NPC = { 501 } } },
    }
    local npcs = {
        [501] = { name = "Gryan", friendlyToFaction = "A" },
        [601] = { name = "Cookie", spawns = { [DM] = { { 20, 20 } } } },
    }
    local db = { QuestPointers = { [101] = true } }
    function db.GetQuest(id) return quests[id] end
    function db.GetNPC(id) return npcs[id] end
    function db.QueryQuestSingle(id, field)
        local q = quests[id]
        if not q then return nil end
        if field == "questLevel" then return q.level end
        return q[field]
    end
    function db.QueryNPCSingle(id, field)
        local n = npcs[id]
        return n and n[field] or nil
    end
    local zones = {}
    function zones:GetDungeons() return { [DM] = { "The Deadmines" } } end
    return db, zones
end

-- The loot this account saw, as UI/BossLoot.lua keeps it.
local BOOK = {
    ["e:1001"] = { name = "Cookie", kills = 3, npcs = { [601] = true },
        items = { ["item:5197"] = { times = 2 }, ["item:5198"] = { times = 1 } } },
}

local function boot(book)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { learned = { bossLoot = book } }); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setRaceId(1); c.setFaction("Alliance"); c.setLevel(18)
    c.setQuestDone(101, false)
    c.setItemInfo({ [5197] = { name = "Cookie's Tenderizer", quality = 2 }, [5198] = { name = "Cookie's Stirring Rod", quality = 2 } })
    c.setItemTexture(5197, "tex:tenderizer")
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(2, 10)
    -- The tree the kit draws, kept as it is drawn and redrawn.
    local last
    local real = c.kitWindow
    c.kitWindow = function(id, tree, extra)
        last = tree
        local h = real(id, tree, extra)
        if type(h) == "table" then
            local update = h.update
            h.update = function(now)
                last = now
                return update(now)
            end
        end
        return h
    end
    c.slashes[ns.id.slash]("dungeons")
    c.advance(2, 20)
    c.kitSelect(ID, "dungeons", 1)
    c.kitSelect(ID, "tabs", 2)
    return c, function() return last end
end

local function parts(tree, kind)
    local out = {}
    ns.Kit.Each(tree, function(part)
        if part.kind == kind then out[#out + 1] = part end
    end)
    return out
end

tests["dungeon bosses: the boss with its kills, each item seen as an item line, most seen first"] = function(t)
    local _, tree = boot(BOOK)
    local sections = parts(tree(), "section")
    t.eq(sections[1] and sections[1].text, "Cookie (3 kills)")
    local items = parts(tree(), "itemLine")
    t.eq(#items, 2)
    t.eq({ items[1].name, items[1].quality, items[1].icon }, { "Cookie's Tenderizer", 2, "tex:tenderizer" })
    t.eq(items[1].note, "seen 2 times")
    t.eq(items[2].note, "seen 1 time")
end

tests["dungeon bosses: each item line carries its item, so the kit shows the game's tooltip"] = function(t)
    local _, tree = boot(BOOK)
    local items = parts(tree(), "itemLine")
    t.eq(items[1] and items[1].item, 5197)
    t.eq(items[2] and items[2].item, 5198)
end

tests["dungeon bosses: no loot seen says so, and no Show on map footer on this tab"] = function(t)
    local c, tree = boot(nil)
    local empty = parts(tree(), "empty")
    t.eq(empty[1] and empty[1].text, ns.DungeonRead.WHY_NO_LOOT[1])
    t.eq(#parts(tree(), "footer"), 0)
    t.ok(c.kitWindows()[ID].shown, "the window stays open")
end

return tests

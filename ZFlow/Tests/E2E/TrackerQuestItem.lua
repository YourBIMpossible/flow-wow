local _, ns = ...

-- End to end (S42, P-TRIP): the quest's own item on the route tracker, on
-- the whole add-on with a fake client. A quest whose item is in the bags
-- and can be used gets a line under the current step: its icon, its name,
-- how many. The line names the item only: it is no button and uses
-- nothing. Made-up quests, items and places; not tested in game.

local tests = {}

local MAP = 1436
local WHISTLE = 7001

local function questie()
    local quests = {
        [401] = { ObjectiveData = { { Type = "monster", Id = 9101 } } },
        [402] = { ObjectiveData = { { Type = "monster", Id = 9102 } } },
    }
    local npcs = {
        [9101] = { name = "Boar", spawns = { [40] = { { 55, 50 } } } },
        [9102] = { name = "Herb Thing", spawns = { [40] = { { 20, 50 } } } },
    }
    local db = {}
    function db.GetQuest(id) return quests[id] end
    function db.GetNPC(id) return npcs[id] end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [40] = MAP })[area] end
    return db, zones
end

local BOARS = { id = 401, title = "Boars", objectives = { { text = "Boars called: 0/4" } } }
local HERBS = { id = 402, title = "Herbs", objectives = { { text = "Herbs: 0/5" } } }

-- opts: count (of the whistle in the bags), use (can it be used), item
-- (false: the quest has no item)
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setFaction("Alliance"); c.setLevel(18)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 0)
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog({ BOARS, HERBS })
    if opts.item ~= false then
        c.setQuestItem(401, WHISTLE)
        c.setItemCount(WHISTLE, opts.count == nil and 1 or opts.count)
        c.setItemUse(WHISTLE, opts.use == nil or opts.use)
        c.setItemInfo({ [WHISTLE] = { name = "Test Whistle", quality = 1 } })
        c.setItemTexture(WHISTLE, 134400)
    end
    local seen = {}
    local real = c.kitWindow
    c.kitWindow = function(id, tree, extra)
        local h = real(id, tree, extra)
        if id == ns.RouteTracker.ID then
            seen.tree = tree
            if type(h) == "table" and type(h.update) == "function" then
                local update = h.update
                h.update = function(now) seen.tree = now; return update(now) end
            end
        end
        return h
    end
    c.trackerSeen = seen
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    c.slashes[ns.id.slash]("route")
    c.advance(2, 10)
    return c, addon
end

-- What the fake client lacks for other modules is recorded at start, with
-- or without a quest item: the tracker must add nothing to it.
local BASE = 2

-- The tracker's parts as the kit was last given them (the fake client's
-- window record keeps only kind, key and text; boot keeps the tree itself).
local function parts(c)
    local w = c.kitWindows()[ns.RouteTracker.ID]
    local tree = c.trackerSeen and c.trackerSeen.tree or nil
    return tree and tree.children or {}, w
end

local function part(c, key)
    for i, p in ipairs((parts(c))) do
        if p.key == key then return p, i end
    end
    return nil
end

local function problems(addon)
    local n = 0
    for _, p in ipairs(addon.problems:list()) do n = n + (p.count or 1) end
    return n
end

tests["tracker quest item: the current quest's item is shown under the current step"] = function(t)
    local c, addon = boot()
    local _, w = parts(c)
    t.eq(w and w.shown, true, "the tracker is up")
    local cur, at = part(c, "current")
    t.eq(cur and cur.text, "Boars 0/4", "the nearer quest is the current step (A2-18: its count beside the label)")
    local item, where = part(c, "questItem")
    t.ok(item ~= nil, "the item's line is there")
    t.eq(where, at and at + 1, "right under the current step")
    t.eq(item and item.kind, "itemLine")
    t.eq(item and item.name, "Test Whistle")
    t.eq(item and item.icon, 134400, "its own icon")
    t.eq(item and item.quality, 1, "its rarity, for the name's colour")
    t.eq(item and item.note, ns.RouteTracker.ITEM_NOTE)
    t.eq(item and item.onClick, nil, "a line, not a button: it uses nothing")
    t.eq(problems(addon), BASE, "nothing new went wrong")
end

tests["tracker quest item: three in the bags shows the count"] = function(t)
    local c = boot({ count = 3 })
    local item = part(c, "questItem")
    t.eq(item and item.count, 3)
end

tests["tracker quest item: a quest with no item has no such line"] = function(t)
    local c, addon = boot({ item = false })
    t.ok(part(c, "current") ~= nil, "the route is shown")
    t.eq(part(c, "questItem"), nil)
    t.eq(problems(addon), BASE, "nothing new went wrong")
end

tests["tracker quest item: an item not in the bags, or one that cannot be used, is not shown"] = function(t)
    local c = boot({ count = 0 })
    t.eq(part(c, "questItem"), nil, "not in the bags")
    c = boot({ use = false })
    t.eq(part(c, "questItem"), nil, "nothing to use")
end

tests["tracker quest item: the line goes when the route moves on to a quest without one"] = function(t)
    local c = boot()
    t.ok(part(c, "questItem") ~= nil)
    c.setQuestLog({ HERBS })
    c.advance(5, 60)
    local cur = part(c, "current")
    t.eq(cur and cur.text, "Herbs 0/5", "the route moved on (A2-18: its count beside the label)")
    t.eq(part(c, "questItem"), nil, "the other quest's item is not shown")
end

return tests

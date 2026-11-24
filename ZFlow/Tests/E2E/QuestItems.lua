local _, ns = ...

-- The quest's own item on the quest arrow (S42, Nav/QuestItems.lua), on the
-- whole add-on loaded on a fake client. The real entry: the arrow's quest
-- step goes through ns.use("questItems").With, which adds one line
-- "Use <item> (in your bags)" when the quest's item is in the bags and has
-- a use; and the word "questitems" lists the quests with their item. Words
-- only: nothing uses the item. Made-up quests, items and names. Not tested
-- in game.

local tests = {}
local QI = ns.Nav.QuestItems

local MAP, QUEST, ITEM, NAME = 1411, 303, 5001, "Test Totem"
local LINE = QI.LINE:format(NAME)

local function questie()
    local db = {}
    function db.GetQuest(id)
        if id == QUEST then return { ObjectiveData = { { Type = "monster", Id = 9002 } } } end
    end
    function db.GetNPC(id)
        if id == 9002 then return { name = "Near Wolf", spawns = { [12] = { { 90, 50 } } } } end
    end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [12] = MAP })[area] end
    return db, zones
end

-- opts.count / opts.use / opts.name: what the client gives for the item
-- (nil: not known); opts.none: the quest has no item.
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, {})
    c.setZone(1, MAP); c.setPosition(MAP, 0.1, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 1)
    c.setClass("WARRIOR"); c.setFaction("Horde"); c.setLevel(20)
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog({ { id = QUEST, title = "Wolves", objectives = { { text = "Wolves slain: 0/4" } } } })
    if not opts.none then c.setQuestItem(QUEST, ITEM) end
    c.setItemCount(ITEM, opts.count)
    c.setItemUse(ITEM, opts.use)
    if opts.name then c.setItemInfo({ [ITEM] = { name = opts.name } }) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

local function lines(c)
    local a = c.arrows[1]
    return a and a.lines or {}
end

local function has(list, text)
    for _, l in ipairs(list) do
        if l == text then return true end
    end
    return false
end

local function said(c, text)
    for _, line in ipairs(c.printed or {}) do
        if tostring(line):find(text, 1, true) then return true end
    end
    return false
end

local function useLine(list)
    for _, l in ipairs(list) do
        if type(l) == "string" and l:sub(1, 4) == "Use " and l:find("(in your bags)", 1, true) then return l end
    end
    return nil
end

tests["quest items: the quest's item in the bags is named under the quest"] = function(t)
    local c = boot({ count = 1, use = true, name = NAME })
    t.eq(c.arrows[1] and c.arrows[1].shown, true, "the quest arrow is shown")
    t.eq(lines(c)[1], "Wolves")
    t.ok(has(lines(c), LINE), "the use line")
end

tests["quest items: the word lists the quest with its item"] = function(t)
    local c = boot({ count = 2, use = true, name = NAME })
    c.slashes[ns.id.slash](QI.WORD)
    t.ok(said(c, ns.id.title .. ": quests with their own item:"), "the heading")
    t.ok(said(c, "  Wolves: " .. NAME .. " (2 in your bags)"), "the quest's row")
end

tests["quest items: the item used up leaves the arrow when the bags change"] = function(t)
    local c = boot({ count = 1, use = true, name = NAME })
    t.ok(has(lines(c), LINE), "first in the bags")
    c.setItemCount(ITEM, 0)
    c.fire("BAG_UPDATE_DELAYED")
    c.advance(10, 40)
    t.eq(lines(c)[1], "Wolves")
    t.eq(useLine(lines(c)), nil, "no use line")
    c.slashes[ns.id.slash](QI.WORD)
    t.ok(said(c, "  Wolves: not shown (not in your bags)"), "the word says why")
end

tests["quest items: an item used on something else is not shown"] = function(t)
    local c = boot({ count = 1, use = false, name = NAME })
    t.eq(useLine(lines(c)), nil)
    c.slashes[ns.id.slash](QI.WORD)
    t.ok(said(c, "  Wolves: not shown (no use)"))
end

tests["quest items: a quest with no item says nothing of one"] = function(t)
    local c = boot({ none = true, count = 1, use = true, name = NAME })
    t.eq(useLine(lines(c)), nil)
    c.slashes[ns.id.slash](QI.WORD)
    t.ok(said(c, "  none in your log"), "no quest listed")
end

tests["quest items: unknown data says nothing wrong"] = function(t)
    -- The count not known: never read as in the bags.
    local c = boot({ count = nil, use = true, name = NAME })
    t.eq(lines(c)[1], "Wolves")
    t.eq(useLine(lines(c)), nil, "count unknown: no line")
    c.slashes[ns.id.slash](QI.WORD)
    t.ok(said(c, "  Wolves: not shown (count unknown)"))
    -- The use not known: never read as usable.
    c = boot({ count = 1, use = nil, name = NAME })
    t.eq(useLine(lines(c)), nil, "use unknown: no line")
    c.slashes[ns.id.slash](QI.WORD)
    t.ok(said(c, "  Wolves: not shown (use unknown)"))
    -- The name not known: the plain line, never an item number.
    c = boot({ count = 1, use = true })
    t.ok(has(lines(c), QI.PLAIN), "the plain line")
    t.ok(useLine(lines(c)) == nil or not useLine(lines(c)):find(tostring(ITEM), 1, true), "no item number")
end

return tests

-- The Dungeon Quests window (lead sections 303 item 6 and 318), end to end
-- on the whole add-on loaded on a fake client: opened by the slash word and
-- by the arrow menu, a dungeon picked from the list, Show on map sets the
-- player's waypoint, the search narrows the list, the tabs, the empty
-- panes, and close. Built from the kit's parts only (UI/Kit.lua). A
-- made-up Questie; no quest data of any add-on. Not tested in game.
local _, ns = ...
local tests = {}

local ID = "dungeons"
local DM, SFK = 1581, 209

local function questie()
    local quests = {
        [101] = { Id = 101, name = "Red Silk", level = 18, requiredLevel = 14, zoneOrSort = DM,
            Starts = { NPC = { 501 } } },
        [103] = { Id = 103, name = "The Defias Brotherhood", level = 22, requiredLevel = 20, zoneOrSort = DM,
            Starts = { NPC = { 501 } }, preQuestSingle = { 101 }, nextQuestInChain = 0 },
        [201] = { Id = 201, name = "Arugal Must Die", level = 27, requiredLevel = 18, zoneOrSort = SFK,
            Starts = { NPC = { 503 } } },
    }
    local npcs = { [501] = { name = "Gryan", friendlyToFaction = "A" }, [503] = { name = "Sorcerer", friendlyToFaction = "AH" } }
    local db = { QuestPointers = {} }
    for id in pairs(quests) do db.QuestPointers[id] = true end
    function db.GetQuest(id) return quests[id] end
    function db.GetNPC(id) return npcs[id] end
    function db.QueryQuestSingle(id, field)
        local q = quests[id]
        if not q then return nil end
        if field == "questLevel" then return q.level end
        return q[field]
    end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [40] = 1436 })[area] end
    function zones:GetDungeons()
        return { [DM] = { "The Deadmines", {}, nil, { { 40, 42.5, 71.8 } } }, [SFK] = { "Shadowfang Keep" } }
    end
    return db, zones
end

-- opts: questie (false: none), account (the saved account table).
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setRaceId(1); c.setFaction("Alliance"); c.setLevel(18)
    for _, id in ipairs({ 101, 103, 201 }) do c.setQuestDone(id, false) end
    c.setZone(1, 1436); c.setPosition(1436, 0.5, 0.5)
    if opts.questie ~= false then
        local db, zones = questie()
        c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(2, 10)
    return c, addon
end

local function open(c)
    c.slashes[ns.id.slash]("dungeons")
    c.advance(2, 20)   -- the index is built in slices
    return c.kitWindows()[ID]
end

local function texts(rec)
    local out = {}
    for _, p in ipairs(rec and rec.parts or {}) do
        if p.text ~= nil then out[#out + 1] = tostring(p.text) end
    end
    return table.concat(out, " | ")
end

local function hasKind(rec, kind)
    for _, p in ipairs(rec and rec.parts or {}) do
        if p.kind == kind then return true end
    end
    return false
end

-- A topic list always has one picked (UI/Kit.lua: the first unless told),
-- so the window opens on the lowest-level dungeon, its Quests tab.
tests["dungeon window: the slash word opens it, built from kit parts, on the first dungeon's Quests"] = function(t)
    local c = boot()
    local rec = open(c)
    t.ok(rec ~= nil, "a kit window")
    t.eq(rec and rec.shown, true, "shown")
    t.ok(hasKind(rec, "topicList"), "the dungeon list on the left")
    t.ok(hasKind(rec, "tabs"), "the tabs")
    t.ok(hasKind(rec, "header"), "the header with search")
    local words = texts(rec)
    t.ok(words:find("Red Silk", 1, true) ~= nil, "the Deadmines first: " .. words)
end

tests["dungeon window: a dungeon picked shows its quests by group; Show on map sets the waypoint"] = function(t)
    local c, addon = boot()
    open(c)
    t.eq(c.kitSelect(ID, "dungeons", 1), true, "the Deadmines, lowest level first")
    local words = texts(c.kitWindows()[ID])
    t.ok(words:find("Red Silk", 1, true) ~= nil, words)
    t.ok(words:find("Pick up before you go", 1, true) ~= nil, words)
    t.ok(words:find("Later", 1, true) ~= nil, words)
    t.eq(c.kitClick(ID, "showOnMap"), true, "the button is there and live")
    local slot = addon.store:get("char", ns.Nav.Waypoint.PATH)
    local wp = type(slot) == "table" and slot.waypoint or nil
    t.ok(wp ~= nil, "a waypoint is set")
    t.eq(wp and { wp.map, wp.x, wp.y, wp.label }, { 1436, 0.425, 0.718, "The Deadmines" })
    t.ok(texts(c.kitWindows()[ID]):find("Waypoint set", 1, true) ~= nil, "and the window says so")
end

tests["dungeon window: search narrows the list"] = function(t)
    local c = boot()
    open(c)
    t.eq(c.kitType(ID, "header", "shadow"), true)
    t.eq(c.kitSelect(ID, "dungeons", 2), false, "one dungeon left")
    t.eq(c.kitSelect(ID, "dungeons", 1), true)
    t.ok(texts(c.kitWindows()[ID]):find("Arugal Must Die", 1, true) ~= nil, "Shadowfang Keep's quest")
    c.kitType(ID, "header", "zzz")
    t.ok(texts(c.kitWindows()[ID]):find(ns.DungeonRead.WHY_NO_MATCH[1], 1, true) ~= nil, "nothing found says so")
end

tests["dungeon window: Bosses with no loot seen, and Map with no entrance, say why"] = function(t)
    local c = boot()
    open(c)
    c.kitType(ID, "header", "shadow")
    c.kitSelect(ID, "dungeons", 1)
    t.eq(c.kitSelect(ID, "tabs", 2), true)
    t.ok(texts(c.kitWindows()[ID]):find(ns.DungeonRead.WHY_NO_LOOT[1], 1, true) ~= nil, "no loot seen")
    t.eq(c.kitSelect(ID, "tabs", 3), true)
    t.ok(texts(c.kitWindows()[ID]):find(ns.DungeonRead.WHY_NO_ENTRANCE[1], 1, true) ~= nil, "no entrance")
end

tests["dungeon window: without Questie the window opens and says what is missing"] = function(t)
    local c = boot({ questie = false })
    local rec = open(c)
    t.eq(rec and rec.shown, true)
    t.ok(texts(rec):find(ns.DungeonStates.WHY.noQuestie[1], 1, true) ~= nil, texts(rec))
end

tests["dungeon window: close, and open again from the arrow menu"] = function(t)
    local c = boot()
    open(c)
    t.eq(c.kitClose(ID), true)
    t.eq(c.kitWindows()[ID].shown, false)
    c.slashes[ns.id.slash]("arrow demo")
    c.advance(0.1, 2)
    local q = c.arrows[1]
    t.ok(q ~= nil, "an arrow to right-click")
    if q then
        q.click("right")
        t.eq(q.pickRow("dungeons"), true, "the menu has the row")
    end
    t.eq(c.kitWindows()[ID].shown, true, "open again")
end

-- Lead section 319: the Z-Flow (arrow) menu row is the main way in; the
-- slash word is the shortcut. Opened first from the menu, nothing before.
tests["dungeon window 319: the Z-Flow menu row opens it the first time"] = function(t)
    local c = boot()
    t.eq(c.kitWindows()[ID], nil, "not made before it is asked for")
    c.slashes[ns.id.slash]("arrow demo")
    c.advance(0.1, 2)
    local q = c.arrows[1]
    t.ok(q ~= nil, "an arrow to right-click")
    if not q then return end
    q.click("right")
    t.eq(q.pickRow("dungeons"), true, "the menu has the Dungeon quests row")
    c.advance(2, 20)
    local rec = c.kitWindows()[ID]
    t.eq(rec and rec.shown, true, "open from the menu")
    t.ok(texts(rec):find("Red Silk", 1, true) ~= nil, "with the first dungeon's quests: " .. texts(rec))
end

-- Twin review 18:06, F1: the window has a name (so the game's Escape list
-- can close it; the kit wires Escape for a named window) and its place is
-- kept when moved, and given back at the next open.
tests["dungeon window F1: a name for Escape, and its place kept over a reload"] = function(t)
    local c, addon = boot()
    local asked
    local real = c.kitWindow
    c.kitWindow = function(id, tree, extra)
        asked = extra
        return real(id, tree, extra)
    end
    open(c)
    t.eq(asked and asked.name, ns.id.framePrefix .. "DungeonWindow", "a name of its own")
    t.ok(asked and type(asked.onMoved) == "function", "told when moved")
    t.eq(c.kitDrag(ID, { "CENTER", "CENTER", 30, -40 }, 720, 520), true)
    local saved = addon.store:get("account", ns.DungeonWindow.PATH)
    t.eq(saved, { point = { "CENTER", "CENTER", 30, -40 }, width = 720, height = 520 })
    local c2 = boot({ account = c.saved(ns.id.accountDB) })
    local rec = open(c2)
    t.eq(rec and rec.point, { "CENTER", "CENTER", 30, -40 }, "where it was left")
    t.eq(rec and { rec.width, rec.height }, { 720, 520 }, "the size it was left at")
end

-- Twin review, F3 (lead section 303 item 6): an icon on each quest line,
-- the kit's quest pictures (UI/Kit/Theme.lua Kit.look.icon), by group.
tests["dungeon window F3: each quest line carries the kit's icon for its group"] = function(t)
    local c = boot()
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
    open(c)
    local icons = {}
    ns.Kit.Each(last, function(part)
        if part.kind == "line" and type(part.text) == "string" then icons[part.text] = part.icon end
    end)
    local look = ns.Kit.look.icon
    t.eq(icons["Red Silk"], look.questAvailable, "a pickup: available")
    t.eq(icons["The Defias Brotherhood"], look.questLater, "a later quest: later")
end

-- Lead DISPATCH 343: the look of the game's dungeon journal. The list
-- shows each dungeon's level range with its name; above the tabs a
-- summary line names the dungeon, its range at the right and its quest
-- count below (all worked out by Nav/DungeonStates.lua).
local function capture(c)
    local box = {}
    local real = c.kitWindow
    c.kitWindow = function(id, tree, extra)
        box.tree = tree
        local h = real(id, tree, extra)
        if type(h) == "table" then
            local update = h.update
            h.update = function(now)
                box.tree = now
                return update(now)
            end
        end
        return h
    end
    return box
end

local function partByKey(tree, key)
    local found
    ns.Kit.Each(tree, function(part)
        if part.key == key then found = part end
    end)
    return found
end

tests["dungeon window 343: the list shows each dungeon's level range"] = function(t)
    local c = boot()
    local box = capture(c)
    open(c)
    local list = partByKey(box.tree, "dungeons")
    t.eq(list and list.items, { "The Deadmines (18-22)", "Shadowfang Keep (27)" })
end

tests["dungeon window 343: a summary line above the tabs: name, level range, quest count"] = function(t)
    local c = boot()
    local box = capture(c)
    open(c)
    local s = partByKey(box.tree, "summary")
    t.ok(s ~= nil, "a summary line")
    t.eq(s and { s.kind, s.text, s.right, s.sub }, { "line", "The Deadmines", "Levels 18-22", "2 quests" })
    local order = {}
    ns.Kit.Each(box.tree, function(part)
        if part.key == "summary" or part.key == "tabs" then order[#order + 1] = part.key end
    end)
    t.eq(order, { "summary", "tabs" }, "the summary stands above the tabs")
    c.kitType(ID, "header", "shadow")
    s = partByKey(box.tree, "summary")
    t.eq(s and { s.text, s.right, s.sub }, { "Shadowfang Keep", "Level 27", "1 quest" }, "follows the pick")
end

return tests

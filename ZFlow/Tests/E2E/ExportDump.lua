local _, ns = ...
-- The export word (S25, UI/Export.lua) on the whole add-on loaded on a fake
-- client, through its real entry: the slash word "export" and "export
-- dump". The player reads what is said in chat and the lines the
-- character's saved file keeps. One case with nothing readable: nothing is
-- written as 0 or as a guess. Offline: the fake client's reads, not the
-- game's. Not tested in game. Made-up names only.
local tests = {}

local QUEST = { id = 4711, title = "Hollow Wolves", complete = false,
    objectives = { { text = "Hollow wolf slain: 3/8", done = false } } }

-- opts.known: the client answers every read the export asks for.
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setVersion("0.1.0")
    if opts.known then
        c.setClass("WARRIOR")
        c.setFaction("Alliance")
        c.setLevel(12)
        c.setMoney(12345)
        c.setBags({ { free = 3, total = 16, family = 0 }, { free = 5, total = 10, family = 0 } })
        c.setZone(1, 1411)
        c.setMapSize(1411, 1000, 500)
        c.setPosition(1411, 0.452, 0.618)
        c.setClock(7200)
        c.setXp({ cur = 300, max = 1200, rested = 150 })
        c.setBindLocation("Brightwood")
        c.setHearthCooldown(0)
        c.setQuestLog({ QUEST })
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

-- What the slash word says, line by line.
local function said(c, rest)
    local before = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = before + 1, #c.printed do out[#out + 1] = c.printed[i] end
    return out
end

-- The records printed by "export dump", by kind (the first of each kind).
local function records(lines)
    local byKind, all = {}, {}
    for _, l in ipairs(lines) do
        local rec = ns.Export.Parse(l)
        if rec then
            all[#all + 1] = rec
            if byKind[rec.kind] == nil then byKind[rec.kind] = rec end
        end
    end
    return byKind, all
end

local function count(list)
    local n = 0
    for _ in pairs(list or {}) do n = n + 1 end
    return n
end

tests["export: the slash word says the count, keeps the lines for this character, and dump prints them"] = function(t)
    local c, addon = boot({ known = true })
    local boxes = count(c.copyBoxes)

    local out = said(c, "export")
    t.eq(#out, 1, "the word alone says one line: the count")
    local head = ns.id.title .. ": export: "
    t.eq(out[1] and out[1]:sub(1, #head), head, "said under the add-on's title: " .. tostring(out[1]))
    local n = tonumber(tostring(out[1]):match("export: (%d+) lines"))
    t.ok(n ~= nil and n >= 5, "a count of lines: " .. tostring(n))
    t.ok(tostring(out[1]):find("saved for this character", 1, true) ~= nil, "and that it is kept")

    local kept = addon.store:get("char", ns.Export.PATH)
    t.ok(type(kept) == "table" and type(kept.lines) == "table", "the character's saved file holds the lines")
    if type(kept) ~= "table" or type(kept.lines) ~= "table" then return end
    t.eq(#kept.lines, n, "as many as were said")
    t.eq(kept.at, 7200, "with the game time")

    local dump = said(c, "export dump")
    t.eq(#dump, 1 + n, "dump says the count, then every line")
    local lines = {}
    for i = 2, #dump do lines[#lines + 1] = dump[i] end
    t.eq(lines, kept.lines, "the printed lines are the kept ones")

    local rec = records(lines)
    t.eq(lines[1] and lines[1]:sub(1, 2), "E^", "each line is a record")
    t.eq({ rec.export and rec.export.v, rec.export and rec.export.at, rec.export and rec.export.addon },
        { "1", "7200", ns.id.addon }, "the format, the game time and the add-on")
    local you = rec.you or {}
    t.eq({ you.class, you.faction, you.level, you.money, you.bagsfree },
        { "WARRIOR", "Alliance", "12", "12345", "8" }, "class, faction, level, money and bag room")
    t.eq({ you.cont, you.zone, you.map, you.x, you.y }, { "1", "1411", "1411", "45.2", "61.8" }, "where you are, in percent")
    t.eq({ you.xp, you.xpmax, you.rested, you.hearthleft, you.hearth },
        { "300", "1200", "150", "0", "Brightwood" }, "experience and the hearthstone")
    local quest = rec.quest or {}
    t.eq({ quest.id, quest.complete, quest.n, quest.title, quest.failed }, { "4711", "0", "1", QUEST.title, nil }, "the quest")
    local obj = rec.obj or {}
    t.eq({ obj.quest, obj.i, obj.done, obj.text }, { "4711", "1", "0", "Hollow wolf slain: 3/8" }, "its objective")
    t.eq(lines[#lines], "E^end^lines=" .. #lines, "the last line counts them all")

    -- Read only: nothing in the game was changed and no window was made.
    t.eq(c.money(), 12345, "no money moved")
    t.eq(#(c.questLog() or {}), 1, "the quest log is as it was")
    t.eq(count(c.copyBoxes), boxes, "no copy box was opened")
end

tests["export: with nothing readable no field is written as 0 or guessed, and no quest is made up"] = function(t)
    local c, addon = boot()
    local dump = said(c, "export dump")
    t.ok(#dump >= 4, "still a count and the records: " .. #dump)
    local lines = {}
    for i = 2, #dump do lines[#lines + 1] = dump[i] end
    local rec, all = records(lines)
    t.eq(#all, #lines, "every printed line after the count is a record")
    t.ok(rec.export ~= nil and rec.you ~= nil and rec["end"] ~= nil, "the export, you and end records are there")
    t.eq(rec.export and rec.export.at, nil, "no game time read: none written")
    local you = rec.you or {}
    t.eq({ you.class, you.faction, you.level, you.money, you.bagsfree },
        { nil, nil, nil, nil, nil }, "nothing about you was read, nothing is written")
    t.eq({ you.cont, you.zone, you.map, you.x, you.y }, { nil, nil, nil, nil, nil }, "no place")
    t.eq({ you.xp, you.xpmax, you.rested, you.hearthleft, you.hearth }, { nil, nil, nil, nil, nil }, "no experience, no hearthstone")
    t.eq(rec.quest, nil, "no quest line")
    t.eq(rec.obj, nil, "no objective line")
    t.eq(rec.skill, nil, "no profession line")
    for _, l in ipairs(lines) do
        t.ok(not l:find("=0^", 1, true) and l:sub(-2) ~= "=0", "no field said as 0: " .. l)
    end
    local kept = addon.store:get("char", ns.Export.PATH)
    t.eq(type(kept) == "table" and kept.lines, lines, "what was printed is what is kept")
end

return tests

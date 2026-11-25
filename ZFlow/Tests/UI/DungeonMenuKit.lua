-- The Dungeon Quests menu (DISPATCH §652, slice 1), on the whole add-on
-- loaded on a fake client: the card grid of dungeons, the detail view with
-- the B-55 badge and the Solo/Group toggle, the Quests tab, and the footer.
-- A made-up Questie; no quest data of any add-on. Not tested in game.
--
-- Red before the code: the menu asks for no kit window, so c.kitWindows()
-- holds none and every test here fails its first check.
local _, ns = ...
local tests = {}

local M = ns.DungeonMenuWindow
local ID = "dungeonMenu"
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

-- opts: ratios ({ [dungeon name] = ratio } for a fake dungeonVisit module).
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setRaceId(1); c.setFaction("Alliance"); c.setLevel(18)
    for _, id in ipairs({ 101, 103, 201 }) do c.setQuestDone(id, false) end
    c.setZone(1, 1436); c.setPosition(1436, 0.5, 0.5)
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    if opts.ratios then
        local ratios = opts.ratios
        k:Module({
            name = "dungeonVisit",
            provides = { Ratio = function(name) return ratios[name] end },
            start = function() end,
        })
    end
    local api = M.Declare(k, ns.diag)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api
end

-- The tree the kit was last handed for this window, kept as it is drawn and
-- redrawn (the record's parts keep only kind, text and note).
local function keepTree(c)
    local last
    local real = c.kitWindow
    c.kitWindow = function(id, tree, extra)
        if id == ID then last = tree end
        local h = real(id, tree, extra)
        if id == ID and type(h) == "table" and type(h.update) == "function" then
            local update = h.update
            h.update = function(now)
                last = now
                return update(now)
            end
        end
        return h
    end
    return function() return last end
end

local function open(c, api)
    api.Open()
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

local function partByKey(tree, key)
    local found
    ns.Kit.Each(tree, function(part)
        if part.key == key then found = part end
    end)
    return found
end

function tests.opensWithCardGrid(t)
    local _, c, api = boot()
    local rec = open(c, api)
    t.ok(rec ~= nil, "the menu opens a kit window")
    t.ok(rec.shown == true, "the window is shown")
    t.ok(hasKind(rec, "scroll"), "the card grid is a scroll")
    local words = texts(rec)
    t.ok(words:find("The Deadmines", 1, true) ~= nil, "the Deadmines card is there: " .. words)
    t.ok(words:find("Shadowfang Keep", 1, true) ~= nil, "the Shadowfang Keep card is there: " .. words)
end

function tests.cardCarriesLevelCountAndBadge(t)
    local _, c, api = boot()
    local drawn = keepTree(c)
    open(c, api)
    local card = partByKey(drawn(), "dungeon." .. DM)
    t.ok(card ~= nil, "the Deadmines card is found")
    t.ok(card.sub ~= nil and card.sub:find("18", 1, true) ~= nil and card.sub:find("22", 1, true) ~= nil,
        "the card says the level range: " .. tostring(card.sub))
    t.ok(card.sub ~= nil and card.sub:find("2 quests", 1, true) ~= nil,
        "the card says the quest count: " .. tostring(card.sub))
    t.eq(card.right, "?", "no measured run, so the badge says ?")
    t.ok(card.tone == nil, "an unmeasured badge carries no good tone")
end

function tests.cardBadgeShowsMeasuredRatio(t)
    local _, c, api = boot({ ratios = { ["The Deadmines"] = 2.5 } })
    local drawn = keepTree(c)
    open(c, api)
    local card = partByKey(drawn(), "dungeon." .. DM)
    t.ok(card ~= nil, "the Deadmines card is found")
    t.eq(card.right, "2.5x", "a measured run shows its ratio")
    t.ok(card.tone == nil, "solo, a measured badge carries no good tone")
    t.eq(c.kitSelect(ID, "party", 2), true, "the toggle takes Group")
    card = partByKey(drawn(), "dungeon." .. DM)
    t.eq(card.tone, "good", "in a group a measured run is good")
end

function tests.detailViewShowsBadgeAndPartyToggle(t)
    local _, c, api = boot({ ratios = { ["The Deadmines"] = 2.5 } })
    local drawn = keepTree(c)
    open(c, api)
    local heading = partByKey(drawn(), "detail")
    t.ok(heading ~= nil and heading.kind == "section" and heading.big == true,
        "the detail view has a big section heading")
    t.eq(heading.text, "The Deadmines", "the heading names the picked dungeon")
    local facts = partByKey(drawn(), "facts")
    t.ok(facts ~= nil, "the facts line is there")
    t.eq(facts.right, "2.5x", "the facts line carries the badge")
    t.ok(facts.tone == nil, "solo, the facts badge carries no good tone")
    local party = partByKey(drawn(), "party")
    t.ok(party ~= nil and party.kind == "choice", "the Solo/Group toggle is a choice")
    t.eq(table.concat(party.items, " | "), "Solo | Group", "the toggle offers Solo and Group")
    t.eq(party.selected, 1, "Solo is the default")
end

function tests.partyToggleMutesTheBadge(t)
    local _, c, api = boot({ ratios = { ["The Deadmines"] = 2.5 } })
    local drawn = keepTree(c)
    open(c, api)
    t.eq(c.kitSelect(ID, "party", 2), true, "the toggle takes Group")
    local facts = partByKey(drawn(), "facts")
    t.eq(facts.right, "2.5x", "the badge still shows the ratio in a group")
    t.eq(facts.tone, "good", "in a group the badge is good")
    t.eq(c.kitSelect(ID, "party", 1), true, "the toggle takes Solo")
    facts = partByKey(drawn(), "facts")
    t.ok(facts.tone == nil, "solo, the badge carries no good tone")
    t.ok(facts.tooltip ~= nil and facts.tooltip:find("Needs a group", 1, true) ~= nil,
        "solo, the badge says it needs a group: " .. tostring(facts.tooltip))
end

function tests.questsPaneShowsGroups(t)
    local _, c, api = boot()
    local rec = open(c, api)
    local words = texts(rec)
    t.ok(words:find("Pick up before you go", 1, true) ~= nil, "the pickup group is there: " .. words)
    t.ok(words:find("Red Silk", 1, true) ~= nil, "Red Silk is listed")
    t.ok(words:find("The Defias Brotherhood", 1, true) ~= nil, "The Defias Brotherhood is listed")
    t.ok(hasKind(rec, "scroll"), "the Quests tab is a scroll")
end

function tests.footerHasShowOnMapAndPlanRun(t)
    local _, c, api = boot()
    local drawn = keepTree(c)
    open(c, api)
    local foot = partByKey(drawn(), "footer")
    t.ok(foot ~= nil and foot.kind == "footer", "the footer is there")
    local names = {}
    for _, b in ipairs(foot.buttons or {}) do names[#names + 1] = b.text end
    t.eq(table.concat(names, " | "), "Show on map | Plan the run", "the footer buttons")
    t.eq(c.kitClick(ID, "showOnMap"), true, "the Show on map button is there and live")
end

function tests.searchNarrowsTheGrid(t)
    local _, c, api = boot()
    open(c, api)
    t.eq(c.kitType(ID, "header", "shadow"), true, "the search box takes text")
    local words = texts(c.kitWindows()[ID])
    t.ok(words:find("Shadowfang Keep", 1, true) ~= nil, "Shadowfang Keep is left: " .. words)
    t.ok(words:find("The Deadmines", 1, true) == nil, "The Deadmines is gone: " .. words)
end

function tests.pickingACardChangesTheDetail(t)
    local _, c, api = boot()
    local drawn = keepTree(c)
    open(c, api)
    t.eq(c.kitClick(ID, "dungeon." .. SFK), true, "the Shadowfang Keep card is clickable")
    local heading = partByKey(drawn(), "detail")
    t.eq(heading.text, "Shadowfang Keep", "the detail view follows the picked card")
    local words = texts(c.kitWindows()[ID])
    t.ok(words:find("Arugal Must Die", 1, true) ~= nil, "Shadowfang Keep's quest shows: " .. words)
end

return tests

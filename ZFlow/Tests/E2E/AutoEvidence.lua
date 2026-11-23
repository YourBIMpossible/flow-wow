local _, ns = ...
-- P-EVIDENCE+ (lead DISPATCH sections 247 item 4, 252, 262 and 355): look-only
-- capture fields collected in normal play, with no player step, saved
-- bounded under the account's diag table so the lead can read them after
-- the owner plays:
--   diag.bossLoot.gaps        seconds from each boss kill to each roll and
--                             loot line after it (numbers only)
--   diag.trackingList         the minimap tracking list as the client
--                             returns it, at login, 5 s later and on
--                             MINIMAP_UPDATE_TRACKING
--   diag.recipeBookAnswers    RB4-2: headers expanded and the two filter
--                             reads, when the profession window opens and
--                             when its list changes
-- Each record says when it was read (seconds since login) and whether the
-- read answered, was empty or was not there, so an early empty answer is
-- not taken for a limit. The whole add-on on a fake client. Made-up
-- bosses, items and players. Not tested in game.
local tests = {}

local ENC, BOSS = 501, "Gravelmaw the Unfed"            -- made up
local GUID = "Creature-0-0-0-0-7001-00000A"
local LOOTER = "Bramblewick"                            -- made up, never to be saved
local ITEM = "item:4001:0:0:0:0:0:0:0"

local function start(setup)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setClass("PALADIN"); c.setFaction("Alliance"); c.setLevel(60); c.setDead(false)
    if setup then setup(c) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(1, 2)
    c.setTarget({ exists = false }); c.setCombat(false)
    return c, addon
end

local function diag(c)
    local d = c.saved(ns.id.accountDB).diag
    return type(d) == "table" and d or {}
end

local function holds(v, text, depth)
    depth = depth or 0
    if depth > 20 then return false end
    if type(v) == "string" then return v:find(text, 1, true) ~= nil end
    if type(v) ~= "table" then return false end
    for key, value in pairs(v) do
        if holds(key, text, depth + 1) or holds(value, text, depth + 1) then return true end
    end
    return false
end

local function onlyNumbers(list)
    if type(list) ~= "table" then return false end
    for key, v in pairs(list) do
        if type(key) ~= "number" or type(v) ~= "number" then return false end
    end
    return true
end

local function kill(c)
    c.setBossUnit({ exists = true, guid = GUID, name = BOSS })
    c.fire("ENCOUNTER_START", ENC, BOSS, 1, 5)
    c.setCombat(true)
    c.fire("ENCOUNTER_END", ENC, BOSS, 1, 5, 1)
    c.setBossUnit({ exists = false })
    c.setCombat(false)
end

-- diag.bossLoot.gaps ----------------------------------------------------------

-- Fails before: UI/BossLoot.lua only names the field in a comment.
tests["evidence: the seconds from a kill to each roll and loot line are saved, numbers only"] = function(t)
    local c = start()
    local line = LOOTER .. " receives loot: " .. ITEM .. "."
    c.setLootLine(function(text) if text == line then return ITEM, 1 end end)
    kill(c)
    c.advance(12, 2)
    c.offerRoll(1, ITEM)
    c.advance(30, 2)
    c.fire("CHAT_MSG_LOOT", line)
    -- Long after the 180 s first guess: still measured, that is the point.
    c.advance(300, 5)
    c.offerRoll(2, ITEM)
    local gaps = diag(c).bossLoot and diag(c).bossLoot.gaps
    t.ok(type(gaps) == "table", "diag.bossLoot.gaps")
    gaps = gaps or {}
    t.eq(gaps.rolls, { 12, 342 }, "roll gaps")
    t.eq(gaps.lines, { 42 }, "loot line gaps")
    t.ok(onlyNumbers(gaps.rolls) and onlyNumbers(gaps.lines), "numbers only")
    t.ok(not holds(c.saved(ns.id.accountDB), LOOTER), "no player name saved")
end

-- Fails before: no gaps field at all.
tests["evidence: no kill yet, a roll is no gap; the gaps are bounded to the last 50"] = function(t)
    local c = start()
    c.offerRoll(1, ITEM)
    local d = diag(c)
    t.eq(d.bossLoot and d.bossLoot.gaps and d.bossLoot.gaps.rolls, nil, "no kill: nothing")
    kill(c)
    for i = 1, 60 do
        c.advance(1)
        c.offerRoll(i + 1, ITEM)
    end
    local rolls = diag(c).bossLoot and diag(c).bossLoot.gaps and diag(c).bossLoot.gaps.rolls or {}
    t.eq(#rolls, 50, "bounded")
    t.eq(rolls[50], 60, "the newest kept")
    t.eq(rolls[1], 11, "the oldest dropped")
end

-- diag.trackingList ---------------------------------------------------------------

local LIST = {
    count = 3,
    entries = {
        { form = "table", kind = "spell", name = "Find Minerals", hasActive = true, active = false, spellId = 2580 },
        { form = "table", kind = "townsfolk", name = "Flight Master", hasActive = true, active = true },
        { form = "table", kind = "other", name = "Mailbox", hasActive = false },
    },
}

-- Fails before: no tracking list read (client.trackingRaw) and no record.
tests["evidence: the tracking list is saved at login as the client returned it, town kinds and active present"] = function(t)
    local c = start(function(cl) cl.setTrackingRaw(LIST) end)
    local list = diag(c).trackingList
    t.ok(type(list) == "table" and #list >= 1, "diag.trackingList")
    local r = type(list) == "table" and list[1] or {}
    t.eq(r.why, "login")
    t.eq(r.state, "answered")
    t.eq(type(r.at), "number", "seconds since login")
    t.eq(r.count, 3)
    t.eq(r.entries, LIST.entries)
end

-- Fails before: nothing listens to MINIMAP_UPDATE_TRACKING for the record.
tests["evidence: an early empty tracking list is saved as empty, the later answer beside it"] = function(t)
    local c = start(function(cl) cl.setTrackingRaw({ count = 0, entries = {} }) end)
    c.setTrackingRaw(LIST)
    c.advance(5, 5)
    c.fire("MINIMAP_UPDATE_TRACKING")
    local list = diag(c).trackingList or {}
    local whys, states = {}, {}
    for i, r in ipairs(list) do whys[i], states[i] = r.why, r.state end
    t.eq(whys, { "login", "later", "event" })
    t.eq(states, { "empty", "answered", "answered" })
    t.ok(list[3] and list[2] and list[3].at >= list[2].at, "times in order")
end

-- Fails before: no record at all.
tests["evidence: a client with no tracking list read is saved as absent; the records are bounded"] = function(t)
    local c = start()
    for _ = 1, 30 do c.fire("MINIMAP_UPDATE_TRACKING") end
    local list = diag(c).trackingList or {}
    t.eq(list[1] and list[1].state, "absent")
    t.eq(#list, 20, "bounded")
end

-- diag.recipeBookAnswers (RB4-2) --------------------------------------------------

-- Fails before: no read of the raw answers (client.tradeSkillAnswers), no record.
tests["evidence: the profession window's header and filter answers are saved when it opens and changes"] = function(t)
    local c = start()
    c.setTradeSkillAnswers({ open = true, rows = 0, headers = 0, expanded = 0, collapsed = 0, unknown = 0,
                             subClass = "nil", invSlot = "nil" })
    c.fire("TRADE_SKILL_SHOW")
    c.setTradeSkillAnswers({ open = true, rows = 12, headers = 3, expanded = 2, collapsed = 1, unknown = 0,
                             subClass = "1", invSlot = "true" })
    c.advance(2, 2)
    c.fire("TRADE_SKILL_LIST_UPDATE")
    local list = diag(c).recipeBookAnswers or {}
    t.eq(#list, 2)
    local a, b = list[1] or {}, list[2] or {}
    t.eq({ a.why, a.state, a.after }, { "show", "empty", 0 })
    t.eq({ b.why, b.state, b.after }, { "update", "answered", 2 })
    t.eq({ b.rows, b.headers, b.expanded, b.collapsed, b.unknown, b.allExpanded, b.subClass, b.invSlot },
         { 12, 3, 2, 1, 0, false, "1", "true" })
    t.eq(type(b.at), "number", "seconds since login")
end

-- Fails before: no record.
tests["evidence: every header expanded reads true; a header that says nothing reads not known"] = function(t)
    local c = start()
    c.setTradeSkillAnswers({ open = true, rows = 5, headers = 2, expanded = 2, collapsed = 0, unknown = 0,
                             subClass = "true", invSlot = "true" })
    c.fire("TRADE_SKILL_SHOW")
    c.setTradeSkillAnswers({ open = true, rows = 5, headers = 2, expanded = 1, collapsed = 0, unknown = 1,
                             subClass = "true", invSlot = "absent" })
    c.fire("TRADE_SKILL_LIST_UPDATE")
    c.setTradeSkillAnswers(nil)
    c.fire("TRADE_SKILL_LIST_UPDATE")
    local list = diag(c).recipeBookAnswers or {}
    t.eq(list[1] and list[1].allExpanded, true)
    t.eq(list[2] and list[2].allExpanded, nil)
    t.eq(list[2] and list[2].invSlot, "absent")
    t.eq(list[3] and list[3].state, "absent")
end

-- Look only -------------------------------------------------------------------------

-- Fails before: the module is absent.
tests["evidence: the collector starts, says nothing in chat and makes no problem"] = function(t)
    local c, addon = start(function(cl) cl.setTrackingRaw(LIST) end)
    t.eq((addon:ModuleState("autoEvidence")), "started")
    c.fire("MINIMAP_UPDATE_TRACKING"); c.fire("TRADE_SKILL_SHOW")
    t.ok(not holds(c.printed, "evidence"), "nothing printed about it")
    t.eq(#addon.problems:list("autoEvidence"), 0, "no problem")
end

return tests

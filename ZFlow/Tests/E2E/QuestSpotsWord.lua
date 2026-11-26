local _, ns = ...

-- C-08 end to end (Twin's review of c2d480af, lead section 622): the word
-- "spots" typed after the add-on's own command, on the whole add-on loaded
-- the way the game loads it (ns.offline.addon) on a fake client. What is
-- printed is the list QS.Lines gives for the saved spots, the first line
-- after the add-on's name; with the setting off the "learning is off" line
-- (QS.OFF) follows, and with it on it does not. The words themselves are
-- not tested here: the lines are compared with the module's own answer and
-- constant. Made-up quests and places. Not tested in game.

local tests = {}

local MAP = 1429
local BOOK = {
    [7] = { [2] = { { map = MAP, x = 0.412, y = 0.65, n = 3 } } },
    [12] = { [0] = { { map = MAP, x = 0.5, y = 0.25, n = 1 } } },
}

local function QS() return ns.Nav.QuestSpots end

local function boot(book)
    local c = ns.make.fakeClient()
    local account = { layout = { arrowIntroSeen = true } }
    if book then account.learned = { places = { questSpots = book } } end
    c.setSaved(ns.id.accountDB, account)
    c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setFaction("Alliance"); c.setLevel(10)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000)
    c.setMapName(MAP, "Test Vale")
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(2, 10)
    return c, addon
end

-- What the word printed: the lines added to chat by typing it.
local function typed(c)
    local from = #c.printed
    c.slashes[ns.id.slash](QS().WORD)
    local out = {}
    for i = from + 1, #c.printed do out[#out + 1] = c.printed[i] end
    return out
end

-- The lines the word should print for book: QS.Lines's own answer, the
-- first one after the add-on's name.
local function wanted(book)
    local lines = QS().Lines(book, {}, function(m)
        if m == MAP then return "Test Vale" end
        return nil
    end)
    local out = { ns.id.title .. ": " .. lines[1] }
    for i = 2, #lines do out[#out + 1] = lines[i] end
    return out
end

tests["quest spots word: the word prints the learned spots, one line a quest"] = function(t)
    local c, addon = boot(BOOK)
    local before = addon.problems:count()
    local got = typed(c)
    local want = wanted(BOOK)
    t.eq(#want, 3, "a head line and one line for each of the two quests")
    t.eq(got, want, "what the word printed")
    t.eq(addon.problems:count(), before, "no problem raised")
end

-- Lead section 863.2: "spots" is F-new-4's word (Nav/LearnedForget.lua,
-- LF.SPOTS_WORD); C-08's list has a word of its own, and typing it still
-- prints the list, not F-new-4's count. Red before: both were "spots".
tests["quest spots word: its own word, not F-new-4's"] = function(t)
    local LF = ns.Nav.LearnedForget
    t.ok(type(LF) == "table" and type(LF.SPOTS_WORD) == "string", "F-new-4's word is there")
    t.ok(type(QS().WORD) == "string" and QS().WORD ~= "", "C-08's word is there")
    if type(LF) ~= "table" then return end
    t.ok(QS().WORD ~= LF.SPOTS_WORD, "not the same word: " .. tostring(QS().WORD))
    t.ok(QS().WORD ~= LF.PLACES_WORD, "nor F-new-4's other word")
    local c = boot(BOOK)
    t.eq(typed(c), wanted(BOOK), "typing C-08's word prints the list")
end

tests["quest spots word: with nothing learned it says so, in one line"] = function(t)
    local c = boot(nil)
    local got = typed(c)
    t.eq(got, { ns.id.title .. ": " .. QS().NONE })
end

tests["quest spots word: with the setting off the learning-is-off line follows, with it on it does not"] = function(t)
    local c, addon = boot(BOOK)
    t.ok(type(QS().OFF) == "string" and QS().OFF ~= "", "the module has its learning-is-off line")
    local on = typed(c)
    for _, line in ipairs(on) do
        t.ok(line ~= QS().OFF, "setting on: the line is not said")
    end
    local ok = addon.settings:set(QS().SETTING, false)
    t.ok(ok ~= false, "the setting is switched off")
    local off = typed(c)
    local want = wanted(BOOK)
    want[#want + 1] = QS().OFF
    t.eq(off, want, "the list still shows, then the learning-is-off line")
end

return tests

local _, ns = ...

-- Flow parity A2-21: the game's own quest tracker and Questie's tracker,
-- each switched on or off by its own settings row (UI/QuestTrackers.lua).
-- Offline, over the fake client. The two client calls the module asks for
-- do not exist in Core/Client.lua yet (CLIENT NEED): each test attaches a
-- made-up one to its own fake client and records what was asked. None of
-- this was looked at in game.
--
-- Red before the code: there is no ns.QuestTrackers and neither row.

local tests = {}

local RAISE = {}

local function put(root, key, value)
    local parts = {}
    for part in key:gmatch("[^.]+") do parts[#parts + 1] = part end
    local at = root
    for i = 1, #parts - 1 do
        at[parts[i]] = at[parts[i]] or {}
        at = at[parts[i]]
    end
    at[parts[#parts]] = value
end

-- o.saved:   { [setting key] = value } saved in the account before login
-- o.calls:   false for a client without the two calls
-- o.questie: false for no Questie; else a made-up QuestieTracker module
-- o.answer:  { [which] = a reason } the made-up call refuses with at first
local function boot(t, o)
    o = o or {}
    if type(ns.offline) ~= "table" or type(ns.offline.addon) ~= "function" then
        t.skip("no whole add-on offline")
        return nil
    end
    local Q = ns.QuestTrackers
    local c = ns.make.fakeClient()
    local account = { layout = { arrowIntroSeen = true } }
    for key, value in pairs(o.saved or {}) do put(account, "settings." .. key, value) end
    c.setSaved(ns.id.accountDB, account)
    c.setSaved(ns.id.charDB, {})
    c.setScreen(1024, 768)
    c.setClass("MAGE")
    local w = { c = c, asks = {}, answer = o.answer or {}, touched = 0 }
    local function made(which)
        return function(on)
            local word = "?"
            if on == true then word = Q.SHOW end
            if on == false then word = Q.HIDE end
            w.asks[#w.asks + 1] = which .. ":" .. word
            local a = w.answer[which]
            if a == RAISE then error("a made-up failure") end
            if a ~= nil then return false, a end
            return true
        end
    end
    if o.calls ~= false then
        c[Q.CALL[Q.GAME]] = made(Q.GAME)
        c[Q.CALL[Q.QUESTIE]] = made(Q.QUESTIE)
    else
        -- The fake has both names (lead section 702); this client has neither.
        c[Q.CALL[Q.GAME]] = nil
        c[Q.CALL[Q.QUESTIE]] = nil
    end
    if o.questie ~= false then
        local function touch() w.touched = w.touched + 1 end
        w.module = { Collapse = touch, Expand = touch, Update = touch, Enable = touch, Disable = touch }
        c.setQuestieModule(Q.QUESTIE_MODULE, w.module)
    end
    w.addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    return w
end

local function said(w) return table.concat(w.asks, " ") end
local function ask(which, what) return which .. ":" .. what end
local function fight(w)
    w.c.setCombat(true)
    w.c.setCombat(false)
end

-- ------------------------------------------------------------------- pure
tests["quest trackers: what to ask for one tracker, from its setting and what was asked before"] = function(t)
    local Q = ns.QuestTrackers
    t.eq(Q.Ask(true, nil, nil), nil, "on and never asked: left to the game")
    t.eq(Q.Ask(nil, nil, nil), nil, "not read: left to the game")
    t.eq(Q.Ask(false, nil, nil), Q.HIDE, "off: hide it")
    t.eq(Q.Ask(false, Q.HIDE, true), nil, "hidden and kept by the client: not asked twice")
    t.eq(Q.Ask(false, Q.HIDE, false), Q.HIDE, "refused: asked again")
    t.eq(Q.Ask(true, Q.HIDE, true), Q.SHOW, "on again: show it")
    t.eq(Q.Ask(true, Q.HIDE, false), Q.SHOW, "on again after a refused hide: show it all the same")
    t.eq(Q.Ask(true, Q.SHOW, false), Q.SHOW, "a refused show is asked again")
    t.eq(Q.Ask(true, Q.SHOW, true), nil, "shown: nothing more")
    t.eq(Q.Ask(false, Q.SHOW, true), Q.HIDE, "off again: hide it")
end

tests["quest trackers: the two settings each give their own ask"] = function(t)
    local Q = ns.QuestTrackers
    local none = Q.Asks({ [Q.GAME] = true, [Q.QUESTIE] = true }, {})
    t.eq(none[Q.GAME], nil)
    t.eq(none[Q.QUESTIE], nil)
    local game = Q.Asks({ [Q.GAME] = false, [Q.QUESTIE] = true }, {})
    t.eq(game[Q.GAME], Q.HIDE)
    t.eq(game[Q.QUESTIE], nil, "the game's row does not move Questie's tracker")
    local questie = Q.Asks({ [Q.GAME] = true, [Q.QUESTIE] = false }, nil)
    t.eq(questie[Q.GAME], nil, "Questie's row does not move the game's tracker")
    t.eq(questie[Q.QUESTIE], Q.HIDE)
    local back = Q.Asks({ [Q.GAME] = true, [Q.QUESTIE] = false },
        { [Q.GAME] = { asked = Q.HIDE, settled = true }, [Q.QUESTIE] = { asked = Q.HIDE, settled = true } })
    t.eq(back[Q.GAME], Q.SHOW)
    t.eq(back[Q.QUESTIE], nil)
    t.eq(Q.Asks(nil, nil)[Q.GAME], nil, "nothing read: nothing asked")
end

-- ----------------------------------------------------------- whole add-on
tests["quest trackers: both rows exist, each with its own account key, on at first"] = function(t)
    local w = boot(t)
    if not w then return end
    local Q = ns.QuestTrackers
    local keys = { Q.SETTING[Q.GAME], Q.SETTING[Q.QUESTIE] }
    t.ok(type(keys[1]) == "string" and type(keys[2]) == "string" and keys[1] ~= keys[2], "two keys, not one")
    for _, key in ipairs(keys) do
        local row = w.addon.settings:row(key)
        t.ok(type(row) == "table", tostring(key) .. " is a declared row")
        if type(row) == "table" then
            t.eq(row.scope, "account", key)
            t.eq(row.type, "bool", key)
            t.eq(row.default, true, key .. ": on at first")
            t.eq(w.addon.settings:get(key), true, key .. ": read as on with nothing saved")
            t.ok(w.addon.Settings.Topics.Find(row.group) ~= nil, key .. " names a topic of the one list")
            t.ok(type(row.label) == "string" and row.label ~= "", key .. " has a label")
            t.ok(type(row.help) == "string" and row.help ~= "", key .. " has a help line")
            local n = 0
            for r in w.addon.settings:each() do
                if r.key == key then n = n + 1 end
            end
            t.eq(n, 1, key .. ": declared once")
        end
    end
    local a, b = w.addon.settings:row(keys[1]), w.addon.settings:row(keys[2])
    t.ok(type(a) == "table" and type(b) == "table" and a.label ~= b.label, "two rows a player can tell apart")
end

tests["quest trackers: with both rows as they came the client is asked nothing"] = function(t)
    local w = boot(t)
    if not w then return end
    local Q = ns.QuestTrackers
    w.c.advance(Q.LATER + 5, 20)
    fight(w)
    w.c.fire("PLAYER_ENTERING_WORLD")
    w.c.advance(Q.LATER + 5, 20)
    t.eq(said(w), "", "a player who never changed a row sees no change")
    t.eq(w.touched, 0, "nothing of Questie's was called")
end

tests["quest trackers: the game's row off hides its tracker, on again shows it, and Questie's is left alone"] = function(t)
    local w = boot(t)
    if not w then return end
    local Q = ns.QuestTrackers
    t.eq((w.addon.settings:set(Q.SETTING[Q.GAME], false)), true)
    t.eq(said(w), ask(Q.GAME, Q.HIDE))
    fight(w)
    w.c.fire("PLAYER_ENTERING_WORLD")
    t.eq(said(w), ask(Q.GAME, Q.HIDE), "the client keeps it hidden: asked once")
    w.addon.settings:set(Q.SETTING[Q.GAME], true)
    t.eq(said(w), ask(Q.GAME, Q.HIDE) .. " " .. ask(Q.GAME, Q.SHOW))
    fight(w)
    t.eq(#w.asks, 2, "shown: nothing more")
end

tests["quest trackers: Questie's row off hides Questie's tracker, on again shows it, and the game's is left alone"] = function(t)
    local w = boot(t)
    if not w then return end
    local Q = ns.QuestTrackers
    w.addon.settings:set(Q.SETTING[Q.QUESTIE], false)
    t.eq(said(w), ask(Q.QUESTIE, Q.HIDE))
    w.addon.settings:set(Q.SETTING[Q.QUESTIE], true)
    t.eq(said(w), ask(Q.QUESTIE, Q.HIDE) .. " " .. ask(Q.QUESTIE, Q.SHOW))
    t.eq(w.touched, 0, "asked of the client only: nothing of Questie's was called")
    local n = 0
    for _ in pairs(w.module) do n = n + 1 end
    t.eq(n, 5, "and nothing was written into Questie's module")
end

tests["quest trackers: a row saved off is applied at login, once"] = function(t)
    local Q = ns.QuestTrackers
    local w = boot(t, { saved = { [Q.SETTING[Q.GAME]] = false } })
    if not w then return end
    t.eq(said(w), ask(Q.GAME, Q.HIDE), "hidden at login; Questie's row is on and is not asked")
    w.c.advance(Q.LATER + 5, 20)
    t.eq(#w.asks, 1, "done: not asked again later")
end

tests["quest trackers: a row saved on is left to the game at login"] = function(t)
    local Q = ns.QuestTrackers
    local w = boot(t, { saved = { [Q.SETTING[Q.GAME]] = true, [Q.SETTING[Q.QUESTIE]] = true } })
    if not w then return end
    w.c.advance(Q.LATER + 5, 20)
    t.eq(said(w), "", "on, even when saved as on, touches nothing")
end

tests["quest trackers: a refusal in a fight is asked again when the fight ends"] = function(t)
    local w = boot(t)
    if not w then return end
    local Q = ns.QuestTrackers
    w.c.setCombat(true)
    w.answer[Q.GAME] = "lockdown"
    w.addon.settings:set(Q.SETTING[Q.GAME], false)
    t.eq(#w.asks, 1, "asked, and refused")
    w.answer[Q.GAME] = nil
    w.c.setCombat(false)
    t.eq(said(w), ask(Q.GAME, Q.HIDE) .. " " .. ask(Q.GAME, Q.HIDE), "asked again at the end of the fight")
    fight(w)
    t.eq(#w.asks, 2, "done then: the next fight asks nothing")
end

tests["quest trackers: switched back on in a fight after a refused hide, the client is asked to show it"] = function(t)
    local w = boot(t)
    if not w then return end
    local Q = ns.QuestTrackers
    w.c.setCombat(true)
    w.answer[Q.QUESTIE] = "lockdown"
    w.addon.settings:set(Q.SETTING[Q.QUESTIE], false)
    w.addon.settings:set(Q.SETTING[Q.QUESTIE], true)
    t.eq(said(w), ask(Q.QUESTIE, Q.HIDE) .. " " .. ask(Q.QUESTIE, Q.SHOW))
    w.answer[Q.QUESTIE] = nil
    w.c.setCombat(false)
    t.eq(w.asks[3], ask(Q.QUESTIE, Q.SHOW), "the refused show is asked again after the fight")
    t.eq(#w.asks, 3)
end

tests["quest trackers: a tracker the game has not made yet at login is asked for again a little later"] = function(t)
    local Q = ns.QuestTrackers
    local w = boot(t, { saved = { [Q.SETTING[Q.GAME]] = false }, answer = { [Q.GAME] = "no frame" } })
    if not w then return end
    local before = #w.asks
    t.ok(before >= 1, "asked at login")
    w.answer[Q.GAME] = nil
    w.c.advance(Q.LATER + 1, 20)
    t.eq(#w.asks, before + 1, "asked once more, " .. Q.LATER .. " seconds on")
    t.eq(w.asks[#w.asks], ask(Q.GAME, Q.HIDE))
    w.c.advance(Q.LATER + 5, 20)
    t.eq(#w.asks, before + 1, "and then no more")
end

tests["quest trackers: a client without the two calls changes nothing and says so on the rows"] = function(t)
    local w = boot(t, { calls = false })
    if not w then return end
    local Q = ns.QuestTrackers
    local before = #w.addon.problems:list()
    w.addon.settings:set(Q.SETTING[Q.GAME], false)
    w.addon.settings:set(Q.SETTING[Q.QUESTIE], false)
    fight(w)
    w.c.advance(Q.LATER + 5, 20)
    w.addon.settings:set(Q.SETTING[Q.GAME], true)
    t.eq(#w.asks, 0)
    t.eq(w.touched, 0)
    t.eq(#w.addon.problems:list(), before, "no problem raised")
    t.eq(w.addon.settings:available(Q.SETTING[Q.GAME]), false, "the row cannot be set: nothing is promised")
    t.eq(w.addon.settings:available(Q.SETTING[Q.QUESTIE]), false)
    local api = w.addon.use(Q.NAME)
    t.eq(api.Asked(Q.GAME), nil, "nothing is said as done")
end

tests["quest trackers: without Questie its row does nothing; the game's row still works"] = function(t)
    local w = boot(t, { questie = false })
    if not w then return end
    local Q = ns.QuestTrackers
    local before = #w.addon.problems:list()
    w.addon.settings:set(Q.SETTING[Q.QUESTIE], false)
    fight(w)
    w.addon.settings:set(Q.SETTING[Q.QUESTIE], true)
    t.eq(said(w), "", "no Questie: its tracker is not asked for")
    t.eq(w.addon.settings:available(Q.SETTING[Q.QUESTIE]), false)
    t.eq(w.addon.settings:available(Q.SETTING[Q.GAME]), true)
    w.addon.settings:set(Q.SETTING[Q.GAME], false)
    t.eq(said(w), ask(Q.GAME, Q.HIDE))
    t.eq(#w.addon.problems:list(), before, "no problem raised")
end

tests["quest trackers: a client call that raises is a recorded problem, not an error in the game"] = function(t)
    local w = boot(t)
    if not w then return end
    local Q = ns.QuestTrackers
    local before = #w.addon.problems:list()
    w.answer[Q.GAME] = RAISE
    local ok, set = pcall(w.addon.settings.set, w.addon.settings, Q.SETTING[Q.GAME], false)
    t.eq(ok, true, "nothing raised into the game")
    t.eq(set, true, "the setting is kept")
    t.eq(#w.asks, 1)
    t.eq(#w.addon.problems:list(), before + 1, "one problem")
    fight(w)
    t.eq(#w.asks, 1, "a call that raised is not hammered at every fight")
    t.eq(w.addon:ModuleState(Q.NAME), "started", "the module stays on")
    w.answer[Q.GAME] = nil
    w.addon.settings:set(Q.SETTING[Q.QUESTIE], false)
    t.eq(w.asks[#w.asks], ask(Q.QUESTIE, Q.HIDE), "the other row still works")
end

tests["quest trackers: what was asked and whether the client did it can be read back"] = function(t)
    local w = boot(t)
    if not w then return end
    local Q = ns.QuestTrackers
    local api = w.addon.use(Q.NAME)
    t.eq(api.Asked(Q.GAME), nil, "nothing asked yet")
    w.answer[Q.GAME] = "lockdown"
    w.addon.settings:set(Q.SETTING[Q.GAME], false)
    local asked, done, why = api.Asked(Q.GAME)
    t.eq(asked, Q.HIDE)
    t.eq(done, false, "refused: not said as done")
    t.eq(why, "lockdown")
    w.answer[Q.GAME] = nil
    fight(w)
    asked, done, why = api.Asked(Q.GAME)
    t.eq(asked, Q.HIDE)
    t.eq(done, true)
    t.eq(why, nil)
    t.eq(api.Asked(Q.QUESTIE), nil, "Questie's was never asked")
end

return tests

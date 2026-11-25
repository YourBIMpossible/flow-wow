local _, ns = ...

-- QuestTrackers (old-Flow parity A2-21): the game's own quest tracker (the
-- list of tracked quests under the minimap) and Questie's tracker, each
-- switched on or off by its own settings row.
--
-- On (as it comes): the tracker is left to the game, or to Questie. A row
-- that was never switched off never asks the client for anything, at login
-- or later: a player who never changes it sees no change.
-- Off: the client is asked to hide that tracker and to keep it hidden.
-- On again: the client is asked to show it.
--
-- From Flow (Modules/Nav/RouteTracker.lua at a529eea, lines 18-159): hidden
-- at login and once more 3 seconds later for a tracker made late; hidden
-- again each time it comes up; in a fight it waits for the fight to end.
-- Not from Flow: Flow switched Questie's tracker by writing Questie's own
-- saved setting (Questie.db.profile.trackerEnabled, line 43). This file
-- writes nothing of Questie's: it only asks the client to hide the frame.
--
-- ACTING is the client's, not this file's. The two calls below are a
-- CLIENT NEED: Core/Client.lua does not have them yet. While the client
-- lacks one, its row cannot be set (the settings page greys it and says
-- why), nothing is asked and nothing is said as done.
--
--   client.showQuestWatch(on)      -> true | false, reason
--   client.showQuestieTracker(on)  -> true | false, reason
--     on = false: hide the tracker and keep it hidden until asked to show
--     it; on = true: stop keeping it hidden and show it. In a fight, where
--     the frame cannot be hidden or shown: false, "lockdown". Any false is
--     asked again when the fight ends (PLAYER_REGEN_ENABLED), at
--     PLAYER_ENTERING_WORLD, and once Q.LATER seconds after login.
--
--   Q.Ask(value, asked, settled) -> Q.HIDE | Q.SHOW | nil
--   Q.Asks(values, state)        -> { [Q.GAME] = ask, [Q.QUESTIE] = ask }
--   Q.Declare(k) -> api;  api.Asked(which) -> asked, done, why
--   ns.use(Q.NAME) -> { Asked = api.Asked }
--
-- Not seen in game: none of it. The client calls do not exist yet.

local Q = ns.QuestTrackers or {}
ns.QuestTrackers = Q

Q.NAME = "questTrackers"
Q.GAME = "game"
Q.QUESTIE = "questie"
Q.ORDER = { Q.GAME, Q.QUESTIE }
Q.HIDE = "hide"
Q.SHOW = "show"
Q.GAME_SETTING = "nav.gameTracker"
Q.QUESTIE_SETTING = "nav.questieTracker"
Q.SETTING = { [Q.GAME] = Q.GAME_SETTING, [Q.QUESTIE] = Q.QUESTIE_SETTING }
Q.CALL = { [Q.GAME] = "showQuestWatch", [Q.QUESTIE] = "showQuestieTracker" }
-- Questie's module that owns its tracker, asked through the client
-- (client.questieModule): nil means Questie is not there.
Q.QUESTIE_MODULE = "QuestieTracker"
-- Flow asked once more this long after login, for a tracker made late.
Q.LATER = 3

Q.LABEL = {
    [Q.GAME] = "Show the game's quest tracker",
    [Q.QUESTIE] = "Show Questie's quest tracker",
}
Q.HELP = {
    [Q.GAME] = "Turn this off to hide the game's own list of tracked quests and keep it hidden. "
        .. "In a fight it is hidden when the fight ends. Turn it on to show the list again.",
    [Q.QUESTIE] = "Turn this off to hide Questie's quest tracker and keep it hidden. In a fight it is "
        .. "hidden when the fight ends. Turn it on to show it again. Questie's own settings are not changed.",
}
-- Why a row cannot be set (the settings page shows it on the greyed row).
Q.NO_CALL = "This cannot be switched yet: the add-on has no way to hide or show this tracker in this version."
Q.NO_QUESTIE = "Questie is not loaded."

-- What to ask of the client for one tracker, or nil for nothing.
--   value:   the row's value; only a plain false hides.
--   asked:   what the client was last asked for this tracker (Q.HIDE,
--            Q.SHOW or nil for never).
--   settled: true when the client did that last ask.
-- A tracker that was never asked to hide is never asked to show.
function Q.Ask(value, asked, settled)
    local want
    if value == false then
        want = Q.HIDE
    elseif asked ~= nil then
        want = Q.SHOW
    end
    if want == nil then return nil end
    if asked == want and settled == true then return nil end
    return want
end

-- The same for both trackers. values: { [Q.GAME] = value, [Q.QUESTIE] =
-- value }; state: { [which] = { asked =, settled = } }. Each tracker is
-- read from its own value only.
function Q.Asks(values, state)
    local out = {}
    if type(values) ~= "table" then return out end
    for _, which in ipairs(Q.ORDER) do
        local asked, settled
        local s = type(state) == "table" and state[which]
        if type(s) == "table" then asked, settled = s.asked, s.settled end
        out[which] = Q.Ask(values[which], asked, settled)
    end
    return out
end

function Q.Declare(k)
    local api = {}
    local ctx, later
    local cancels = {}
    local state = { [Q.GAME] = {}, [Q.QUESTIE] = {} }

    -- The client's call for that tracker, or nil and why there is none.
    -- For Questie's, nil too while Questie is not there.
    local function call(which)
        local c = k.client
        if type(c) ~= "table" then return nil, Q.NO_CALL end
        local fn = c[Q.CALL[which]]
        if type(fn) ~= "function" then return nil, Q.NO_CALL end
        if which == Q.QUESTIE then
            if type(c.questieModule) ~= "function" then return nil, Q.NO_QUESTIE end
            local ok, mod = pcall(c.questieModule, Q.QUESTIE_MODULE)
            if not ok or type(mod) ~= "table" then return nil, Q.NO_QUESTIE end
        end
        return fn
    end

    -- Asks the client for what the two rows want now. true when an ask was
    -- refused, so it is still to do.
    local function apply()
        if not ctx then return false end
        local values = {
            [Q.GAME] = ctx.settings:get(Q.GAME_SETTING),
            [Q.QUESTIE] = ctx.settings:get(Q.QUESTIE_SETTING),
        }
        local asks = Q.Asks(values, state)
        local open = false
        for _, which in ipairs(Q.ORDER) do
            local want = asks[which]
            local fn = want and call(which)
            if fn then
                local s = state[which]
                local ok, done, why = pcall(fn, want == Q.SHOW)
                s.asked, s.why = want, nil
                if not ok then
                    -- A call that raised is not asked again until the row
                    -- changes: recorded, never thrown into the game.
                    s.settled, s.failed = true, true
                    k.problems:add(Q.NAME, which, tostring(done))
                elseif done == true then
                    s.settled, s.failed = true, nil
                else
                    s.settled, s.failed = false, nil
                    if why ~= nil then s.why = tostring(why) end
                    open = true
                end
            end
        end
        return open
    end

    -- At login: now, and once more a little later while an ask is refused
    -- (a tracker the game makes late).
    local function look()
        if not apply() or later or not ctx then return end
        later = ctx.sched:after(Q.NAME, Q.LATER, function()
            later = nil
            apply()
        end)
    end

    -- What the client was last asked for that tracker (Q.HIDE, Q.SHOW or
    -- nil for never), whether it did it, and its reason when it did not.
    function api.Asked(which)
        local s = state[which]
        if type(s) ~= "table" or s.asked == nil then return nil end
        return s.asked, s.settled == true and s.failed ~= true, s.why
    end

    -- A row can be set only while the client can do what it says. It leans
    -- on no other row, so its `needs` is an empty list (a row with a
    -- requires names what it needs: Tests/E2E/SettingsTopics.lua).
    local function can(which)
        return function()
            local fn, why = call(which)
            if fn then return true end
            return false, why
        end
    end

    k:Setting({ key = Q.GAME_SETTING, scope = "account", type = "bool", default = true,
        label = Q.LABEL[Q.GAME], group = "travel.route", help = Q.HELP[Q.GAME],
        synonyms = { "quest tracker", "tracker", "quest list", "tracked quests", "objectives", "hide" },
        needs = {}, requires = can(Q.GAME) })

    k:Setting({ key = Q.QUESTIE_SETTING, scope = "account", type = "bool", default = true,
        label = Q.LABEL[Q.QUESTIE], group = "travel.route", help = Q.HELP[Q.QUESTIE],
        synonyms = { "quest tracker", "tracker", "questie", "tracked quests", "objectives", "hide" },
        needs = {}, requires = can(Q.QUESTIE) })

    k:Module({
        name = Q.NAME,
        needs = { "client", "store", "settings", "sched" },
        provides = { Asked = api.Asked },
        events = {
            PLAYER_ENTERING_WORLD = function() look() end,
            PLAYER_REGEN_ENABLED = function() apply() end,
        },
        start = function(c)
            ctx = c
            for _, which in ipairs(Q.ORDER) do
                local row = c.settings:row(Q.SETTING[which])
                if type(row) == "table" then
                    local cancel = c.store:watch(row.scope, row.path or ("settings." .. row.key), function() apply() end)
                    if type(cancel) == "function" then cancels[#cancels + 1] = cancel end
                end
            end
            look()
        end,
        stop = function()
            for i = 1, #cancels do pcall(cancels[i]) end
            cancels = {}
            if later then pcall(later) end
            later, ctx = nil, nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.questTrackers = Q.Declare(ns)

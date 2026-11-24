local _, ns = ...
-- N68 (research order 8, row 13): selective state-change alerts. A prompt
-- that turns up on the Advisor is a rule that turned true (repair, a
-- trainer, a profession step, the bank, a vendor upgrade, setup, an
-- attunement). With alerts on, and that kind of prompt on, one chat line
-- says it; with the sound on as well, one sound plays with it.
--   alerts.on      off by default: nothing is said until the player turns it on.
--                  Legacy Flow matched (lead section 294): it had no line for
--                  a prompt that turned up. Its only chat lines of its own
--                  were the list once at login and at a level-up
--                  (flow-wow Modules/Advisor/Advisor.lua lines 333-341), and
--                  its advisor.enabled, on by default (line 320), showed
--                  the advice button only (line 288).
--   alerts.sound   off by default: the one sound with each line
--   alerts.<kind>  on by default: each kind of prompt can be left out
--   alerts.dungeon off by default (lead section 303, item 8c): with alerts
--                  on as well, one line when you go into a dungeon or a
--                  raid and one when you come out. Read from
--                  client.instance() after PLAYER_ENTERING_WORLD and
--                  ZONE_CHANGED_NEW_AREA; only a change from a place that
--                  was read is said, so nothing at login and nothing while
--                  the client does not say. A battleground is not one.
--   alerts.list    on by default (P-QOL, as Flow's advisor.enabled, line
--                  320): the top LIST_LOGIN_TOP ways to improve said
--                  LIST_LOGIN seconds after login when there are any, and
--                  the top LIST_LEVEL_TOP LIST_LEVEL seconds after a
--                  level-up, or that there is nothing (lines 333-341).
-- Nothing at login (prompts there before SETTLE seconds have passed are
-- the state the player logged in to, not a change), nothing for a replaced
-- text (the same rule, still true), and nothing for the same prompt again
-- within QUIET seconds (a rule that flickers says it once).
-- Says and plays only: nothing acts in the game and nothing runs beyond
-- the line and the sound. The sound is client.playAlert (PlaySound with
-- the raid warning sound the game names); a game without it plays nothing
-- and says so once.
-- Needs game test: the sound, and how a line reads next to the chat of the
-- game.
local A = {}
ns.Alerts = A

A.NAME = "alerts"
A.SETTING = "alerts.on"
A.SOUND = "alerts.sound"
A.SETTLE = 10   -- seconds after start: prompts before this are the login state
A.QUIET = 60    -- seconds: the same prompt is not said again within this
A.NO_SOUND = "Alert sound not played"
A.DUNGEON = "alerts.dungeon"
A.ENTERED = "You entered a dungeon."
A.LEFT = "You left the dungeon."
-- The kinds of instance, as the game names them, that count as a dungeon.
A.DUNGEON_KINDS = { party = true, raid = true }
A.DUNGEON_EVENTS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }
A.LIST = "alerts.list"
A.LIST_LOGIN, A.LIST_LOGIN_TOP = 6, 3
A.LIST_LEVEL, A.LIST_LEVEL_TOP = 2, 5
A.LIST_HEAD = "Ways to improve:"
A.LIST_NONE = "Nothing to improve right now."

-- The chat lines for the advisor's list: the head, then the first n
-- numbered; nil for an empty list.
function A.ListLines(list, n)
    if type(list) ~= "table" or #list == 0 then return nil end
    local out = { A.LIST_HEAD }
    for i = 1, math.min(n, #list) do
        out[#out + 1] = "  " .. i .. ". " .. tostring(list[i].text)
    end
    return out
end

-- Whether an instance read is inside a dungeon: true, false, or nil when
-- the client did not say.
function A.InDungeon(read)
    if type(read) ~= "table" or type(read.inside) ~= "boolean" then return nil end
    return read.inside and A.DUNGEON_KINDS[read.kind] == true
end

-- The kinds, by the id prefix each source gives its prompt (whole parts
-- only: "aps.prof." is a profession, "aps.profx" is not). The last kind,
-- other, takes every id no source here gives.
A.KINDS = {
    { kind = "repair", prefixes = { "l6c." }, label = "Repair",
        synonyms = { "repair", "durability", "broken" } },
    { kind = "trainer", prefixes = { "aps.trainer", "aps.classQuest", "aps.rankup." }, label = "Trainer and class quests",
        synonyms = { "trainer", "spells", "class quest", "training" } },
    { kind = "professions", prefixes = { "aps.prof." }, label = "Professions",
        synonyms = { "profession", "crafting", "skill" } },
    { kind = "bank", prefixes = { "l6d." }, label = "Bank",
        synonyms = { "bank", "reagents", "storage" } },
    { kind = "vendor", prefixes = { "gear.merchant." }, label = "Vendor upgrades",
        synonyms = { "vendor", "merchant", "upgrade", "gear" } },
    { kind = "setup", prefixes = { "setup." }, label = "Setup",
        synonyms = { "setup", "first steps", "keys" } },
    { kind = "attune", prefixes = { "attune." }, label = "Attunements",
        synonyms = { "attunement", "attune", "raid access" } },
    { kind = "other", prefixes = {}, label = "Other prompts",
        synonyms = { "other", "everything else", "misc" } },
}

function A.KindKey(kind) return "alerts." .. tostring(kind) end

-- A prefix ending in "." matches the start of the id; one without matches
-- the whole id or the id followed by ".".
local function matches(id, prefix)
    if prefix:sub(-1) == "." then return id:sub(1, #prefix) == prefix end
    return id == prefix or id:sub(1, #prefix + 1) == prefix .. "."
end

function A.KindOf(id)
    if type(id) ~= "string" then return "other" end
    for _, kind in ipairs(A.KINDS) do
        for _, prefix in ipairs(kind.prefixes) do
            if matches(id, prefix) then return kind.kind end
        end
    end
    return "other"
end

-- The rule: true, or false and why ("off", "kind off", "at login", "said
-- lately"). on and kindOn are the settings (only true is on); settled is
-- whether login is over; quiet whether the same prompt was said lately.
function A.Decide(on, kindOn, settled, quiet)
    if on ~= true then return false, "off" end
    if kindOn ~= true then return false, "kind off" end
    if settled ~= true then return false, "at login" end
    if quiet == true then return false, "said lately" end
    return true
end

local WHY = {
    noCall = "the game has no call for it here",
    raised = "the game refused it",
}

function A.Declare(k)
    local ctx, cancelWatch, cancelSettle
    local cancels = {}        -- of the dungeon events
    local inDungeon           -- true, false, or nil while never read
    local settled = false
    local quiet = {}          -- by prompt id: cancel of the quiet timer
    local soundSaid = false
    local api = {}

    local function say(text)
        if not ctx or type(ctx.client.print) ~= "function" then return end
        local id = k.id or ns.id
        ctx.client.print(id.title .. ": " .. text)
    end

    local function sound()
        local ok, done, why = pcall(ctx.client.playAlert)
        if not ok then done, why = nil, "raised" end
        if done == true or soundSaid then return end
        soundSaid = true
        say(A.NO_SOUND .. " (" .. (WHY[why] or WHY.raised) .. ").")
    end

    local function heard(id, text)
        if not ctx then return end
        local on = ctx.settings:get(A.SETTING)
        local kindOn = ctx.settings:get(A.KindKey(A.KindOf(id)))
        if not A.Decide(on, kindOn, settled, quiet[id] ~= nil) then return end
        quiet[id] = ctx.sched:after(A.NAME, A.QUIET, function() quiet[id] = nil end)
        say(text)
        if ctx.settings:get(A.SOUND) == true then sound() end
    end

    -- The list in chat; empty says so only when asked (a level-up).
    local function sayList(n, sayEmpty)
        if not ctx or ctx.settings:get(A.LIST) ~= true then return end
        local list = ctx.use("advisor").List()
        local out = A.ListLines(list, n)
        if not out then
            if sayEmpty then say(A.LIST_NONE) end
            return
        end
        say(out[1])
        for i = 2, #out do ctx.client.print(out[i]) end
    end

    local function readDungeon()
        if not ctx or type(ctx.client.instance) ~= "function" then return nil end
        local ok, read = pcall(ctx.client.instance)
        if not ok then return nil end
        return A.InDungeon(read)
    end

    -- A read not answered keeps what was known; the first answer is where
    -- the player is, not a change.
    local function moved()
        local now = readDungeon()
        if now == nil or now == inDungeon then return end
        local before = inDungeon
        inDungeon = now
        if before == nil then return end
        local id, text = "dungeon.left", A.LEFT
        if now then id, text = "dungeon.entered", A.ENTERED end
        local on = ctx.settings:get(A.SETTING)
        if not A.Decide(on, ctx.settings:get(A.DUNGEON), settled, quiet[id] ~= nil) then return end
        quiet[id] = ctx.sched:after(A.NAME, A.QUIET, function() quiet[id] = nil end)
        say(text)
        if ctx.settings:get(A.SOUND) == true then sound() end
    end

    -- Named settings so the settings check reads the two fixed rows here.
    local settings = {
        { key = "alerts.on", scope = "account", type = "bool", default = false, group = "general",
            label = "Alerts in chat",
            help = "Says in chat when a new prompt turns up on the advisor panel. Off until you turn it on.",
            synonyms = { "alerts", "alert", "notify", "notifications", "tell me" } },
        { key = "alerts.sound", scope = "account", type = "bool", default = false, group = "general",
            label = "Alert sound",
            help = "Plays one sound with each alert line. Off until you turn it on.",
            synonyms = { "sound", "alert sound", "ping", "noise" } },
        { key = "alerts.dungeon", scope = "account", type = "bool", default = false, group = "general",
            label = "Alerts: entering and leaving a dungeon",
            help = "With alerts on, says in chat when you go into a dungeon or a raid and when you come out. "
                .. "Off until you turn it on.",
            synonyms = { "dungeon", "instance", "raid", "enter", "leave", "zone in" } },
        { key = "alerts.list", scope = "account", type = "bool", default = true, group = "general",
            label = "Ways to improve in chat at login and level-up",
            help = "Says the top ways to improve your character in chat a few seconds after you log in "
                .. "(when there are any) and after each level-up.",
            synonyms = { "advice", "improve", "login", "level up", "list" } },
    }
    for _, kind in ipairs(A.KINDS) do
        settings[#settings + 1] = {
            key = A.KindKey(kind.kind), scope = "account", type = "bool", default = true, group = "general",
            label = "Alerts: " .. kind.label,
            help = "With alerts on, says when a new " .. kind.label:lower() .. " prompt turns up.",
            synonyms = kind.synonyms,
        }
    end

    function api.status()
        return { running = ctx ~= nil, settled = settled }
    end

    k:Module({
        name = A.NAME,
        needs = { "client", "store", "bus", "settings", "sched", "advisor" },
        settings = settings,
        provides = { Status = api.status },
        start = function(c)
            ctx = c
            settled = false
            soundSaid = false
            cancelSettle = c.sched:after(A.NAME, A.SETTLE, function() settled = true end)
            cancelWatch = c.use("advisor").Watch(heard)
            inDungeon = readDungeon()
            cancels[#cancels + 1] = c.sched:after(A.NAME, A.LIST_LOGIN, function()
                local ok, err = pcall(sayList, A.LIST_LOGIN_TOP, false)
                if not ok then k.problems:add(A.NAME, "list", tostring(err)) end
            end)
            cancels[#cancels + 1] = c.bus:on(A.NAME, "PLAYER_LEVEL_UP", function()
                c.sched:after(A.NAME, A.LIST_LEVEL, function()
                    local ok, err = pcall(sayList, A.LIST_LEVEL_TOP, true)
                    if not ok then k.problems:add(A.NAME, "list", tostring(err)) end
                end)
            end)
            for _, event in ipairs(A.DUNGEON_EVENTS) do
                cancels[#cancels + 1] = c.bus:on(A.NAME, event, function()
                    local ok, err = pcall(moved)
                    if not ok then k.problems:add(A.NAME, event, tostring(err)) end
                end)
            end
        end,
        stop = function()
            if type(cancelWatch) == "function" then cancelWatch() end
            if type(cancelSettle) == "function" then cancelSettle() end
            for i = 1, #cancels do pcall(cancels[i]) end
            cancels = {}
            inDungeon = nil
            for id, cancel in pairs(quiet) do
                if type(cancel) == "function" then cancel() end
                quiet[id] = nil
            end
            cancelWatch, cancelSettle = nil, nil
            settled = false
            ctx = nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.alerts = A.Declare(ns)

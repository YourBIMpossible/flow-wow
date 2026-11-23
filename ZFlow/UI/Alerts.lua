local _, ns = ...
-- N68 (research order 8, row 13): selective state-change alerts. A prompt
-- that turns up on the Advisor is a rule that turned true (repair, a
-- trainer, a profession step, the bank, a vendor upgrade, setup, an
-- attunement). With alerts on, and that kind of prompt on, one chat line
-- says it; with the sound on as well, one sound plays with it.
--   alerts.on      off by default: nothing is said until the player turns it on
--   alerts.sound   off by default: the one sound with each line
--   alerts.<kind>  on by default: each kind of prompt can be left out
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

-- The kinds, by the id prefix each source gives its prompt (whole parts
-- only: "aps.prof." is a profession, "aps.profx" is not). The last kind,
-- other, takes every id no source here gives.
A.KINDS = {
    { kind = "repair", prefixes = { "l6c." }, label = "Repair",
        synonyms = { "repair", "durability", "broken" } },
    { kind = "trainer", prefixes = { "aps.trainer", "aps.classQuest" }, label = "Trainer and class quests",
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
        needs = { "client", "store", "settings", "sched", "advisor" },
        settings = settings,
        provides = { Status = api.status },
        start = function(c)
            ctx = c
            settled = false
            soundSaid = false
            cancelSettle = c.sched:after(A.NAME, A.SETTLE, function() settled = true end)
            cancelWatch = c.use("advisor").Watch(heard)
        end,
        stop = function()
            if type(cancelWatch) == "function" then cancelWatch() end
            if type(cancelSettle) == "function" then cancelSettle() end
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

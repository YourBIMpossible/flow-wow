local _, ns = ...

-- NpcSpeech (G60): when an NPC's window opens - gossip, a quest greeting,
-- a quest's story, "how is it going" or the thank-you at the end - its
-- words are read aloud through the game's text-to-speech voice, once; the
-- voice stops when the window closes. Off by default: sound is intrusive.
--
-- Plays on the player's own speakers only. Nothing here clicks, accepts,
-- completes or chooses anything: it reads what the window shows.
--
-- Behaviour from Flow's Modules/Bonus.lua "Spoken" extra, built in this
-- add-on's shape. Its master switch (Bonus mode) is the setting
-- "general.bonus" here: on by default, off turns every bonus extra off at
-- once; today the only extra is this one.
--
-- Pure parts:
--   NpcSpeech.Clean(text) -> the words only (no colour codes, links,
--     textures; "$B" breaks as spaces), or nil when nothing is left.
--   NpcSpeech.Voice(speech) -> the voice to use from client.speech(): the
--     first one, or nil.
--
-- Module: NpcSpeech.Declare(k) -> api. Listens to GOSSIP_SHOW,
--   QUEST_GREETING, QUEST_DETAIL, QUEST_PROGRESS, QUEST_COMPLETE (speak)
--   and GOSSIP_CLOSED, QUEST_FINISHED (stop). A window whose text is not
--   read yet is asked again every RETRY seconds, up to TRIES times, while
--   it is open. A speak call that raises is a recorded problem; the next
--   window is read as usual.
-- Settings "general.npcSpeech" (bool, default false) and "general.bonus"
--   (bool, default true). The speech row is greyed with its reason while
--   the client has no speech call or the bonus switch is off.
-- Not seen in game: the client's speech names are first guesses.

local S = {}
ns.NpcSpeech = S

S.NAME = "npcSpeech"
S.SETTING = "general.npcSpeech"
S.BONUS = "general.bonus"
S.NO_CALL = "Your game client has no text-to-speech call"
S.BONUS_OFF = "Bonus extras are off"
S.RETRY = 0.5
S.TRIES = 10

-- The window events that open NPC words, and the npcText kind of each.
S.OPEN = {
    GOSSIP_SHOW = "gossip", QUEST_GREETING = "greeting", QUEST_DETAIL = "detail",
    QUEST_PROGRESS = "progress", QUEST_COMPLETE = "reward",
}
S.CLOSE = { "GOSSIP_CLOSED", "QUEST_FINISHED" }

function S.Clean(text)
    if type(text) ~= "string" then return nil end
    local s = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    s = s:gsub("|r", "")
    s = s:gsub("|H.-|h(.-)|h", "%1")
    s = s:gsub("|T.-|t", "")
    s = s:gsub("%$[Bb]", " ")
    s = s:gsub("%s+", " ")
    s = s:match("^%s*(.-)%s*$")
    if s == "" then return nil end
    return s
end

function S.Voice(speech)
    if type(speech) ~= "table" or type(speech.voices) ~= "table" then return nil end
    local v = speech.voices[1]
    if type(v) ~= "table" then return nil end
    return v
end

function S.Declare(k)
    local api = {}
    local ctx
    local pending, tries = nil, 0   -- an open window's kind whose text is not read yet
    local speaking = false

    local function fail(where, err)
        if k.problems and type(k.problems.add) == "function" then
            k.problems:add(S.NAME, where, tostring(err))
        end
    end

    local function ask(read, ...)
        if not ctx or type(ctx.client[read]) ~= "function" then return nil end
        local ok, v = pcall(ctx.client[read], ...)
        if not ok then return nil end
        return v
    end

    local function present()
        return type(ask("speech")) == "table"
    end

    local function on()
        if not ctx or not ctx.settings then return false end
        return ctx.settings:get(S.SETTING) == true and ctx.settings:get(S.BONUS) ~= false and present()
    end

    local function stop()
        pending = nil
        if not speaking then return end
        speaking = false
        local ok, err = pcall(ctx.client.stopSpeech)
        if not ok then fail("stop", err) end
    end

    local function say(kind)
        pending = nil
        if not on() then return end
        local text = S.Clean(ask("npcText", kind))
        if not text then
            pending = kind
            return
        end
        stop()   -- one voice at a time: the new window's words replace the last
        local ok, said, why = pcall(ctx.client.speak, text, S.Voice(ask("speech")))
        if not ok then fail(kind, said) return end
        if said ~= true then fail(kind, why) return end
        speaking = true
    end

    local function opened(kind)
        tries = 0
        say(kind)
    end

    local function retry()
        if speaking and not on() then stop() end
        if not pending then return end
        tries = tries + 1
        if tries > S.TRIES then
            pending = nil
            return
        end
        say(pending)
    end

    function api.speaking() return speaking end

    k:Setting({ key = S.BONUS, scope = "account", type = "bool", default = true,
        label = "Bonus extras", group = "general",
        help = "The optional extras just for fun. Off turns every one of them off at once; "
            .. "today that is NPCs reading their words aloud.",
        synonyms = { "bonus", "extras", "fun" } })

    k:Setting({ key = S.SETTING, scope = "account", type = "bool", default = false,
        label = "NPCs read their words aloud", group = "general",
        help = "When you talk to an NPC, the game's text-to-speech voice reads what they say "
            .. "on your own speakers. It stops when you close the window. Off by default.",
        synonyms = { "speech", "voice", "read aloud", "tts", "npc", "text to speech", "talk" },
        needs = S.BONUS,
        requires = function(settings)
            if not present() then return false, S.NO_CALL end
            if settings:get(S.BONUS) == false then return false, S.BONUS_OFF end
            return true
        end })

    local events = {}
    for event, kind in pairs(S.OPEN) do
        events[event] = function() opened(kind) end
    end
    for _, event in ipairs(S.CLOSE) do
        events[event] = function() stop() end
    end

    k:Module({
        name = S.NAME,
        needs = { "client", "settings" },
        provides = { Speaking = api.speaking },
        events = events,
        ticks = { { every = S.RETRY, when = "always", run = function() retry() end } },
        start = function(c) ctx = c end,
        stop = function()
            if ctx and speaking then pcall(ctx.client.stopSpeech) end
            speaking, pending, ctx = false, nil, nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads. Silent until the
-- setting is turned on.
ns.npcSpeech = S.Declare(ns)

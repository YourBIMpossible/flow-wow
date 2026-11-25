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
-- "general.bonus" here: off by default, as Flow's (F-22, lead section 794;
-- a saved choice is kept), and off turns every bonus extra off at once;
-- today the only extra is this one. The word S.BONUS_WORD turns it on or
-- off and says where it stands, with each extra (Flow's `/flow bonus`).
--
-- Pure parts:
--   NpcSpeech.Clean(text) -> the words only (no colour codes, links,
--     textures; "$B" breaks as spaces), or nil when nothing is left.
--   NpcSpeech.Voice(speech[, sex]) -> the voice to use from
--     client.speech(): for sex "female" or "male" the first voice whose
--     name is a woman's or a man's (P-QOL, as Flow picks), else the first
--     one; nil when there is none.
--
-- Module: NpcSpeech.Declare(k) -> api. Listens to GOSSIP_SHOW,
--   QUEST_GREETING, QUEST_DETAIL, QUEST_PROGRESS, QUEST_COMPLETE (speak)
--   and GOSSIP_CLOSED, QUEST_FINISHED (stop). A window whose text is not
--   read yet is asked again every RETRY seconds, up to TRIES times, while
--   it is open. A speak call that raises is a recorded problem; the next
--   window is read as usual. A computer with no voices is said once, in
--   chat.
-- Word (P-QOL): "speech" says where it stands, "speech on|off" sets the
--   setting, "speech say" speaks a test line.
-- Settings "general.npcSpeech" (bool, default false) and "general.bonus"
--   (bool, default true). The speech row is greyed with its reason while
--   the client has no speech call or the bonus switch is off.
-- Not seen in game: the client's speech names are first guesses.

local S = {}
ns.NpcSpeech = S

S.NAME = "npcSpeech"
S.SETTING = "general.npcSpeech"
-- When it appears, in one line (lead section 296): its settings row and the
-- buttons word say it, so a player who sees nothing can find out why.
S.WHEN = "Off by default and needs Bonus extras on; when on, speaks as an NPC's talk window opens."
S.BONUS = "general.bonus"
S.NO_CALL = "Your game client has no text-to-speech call"
S.NO_DEST = "Your game client gives no local playback destination for speech"
S.BONUS_OFF = "Bonus extras are off"
S.BONUS_WORD = "bonus"
S.BONUS_HELP = "bonus extras just for fun: bonus on | off"
S.BONUS_IS_ON = "Bonus extras are on (bonus on | off). Each extra has its own switch:"
S.BONUS_IS_OFF = "Bonus extras are off (bonus on | off). With them on, each extra has its own switch:"
S.EXTRA_LINE = "%s: %s"
S.EXTRA_SPEECH = "NPCs read their words aloud"

-- The bonus word's lines: where Bonus mode stands, then each extra and its
-- own switch.
function S.BonusLines(bonusOn, speechOn)
    local head = S.BONUS_IS_OFF
    if bonusOn == true then head = S.BONUS_IS_ON end
    local state = "off"
    if speechOn == true then state = "on" end
    return { head, S.EXTRA_LINE:format(S.EXTRA_SPEECH, state) }
end
S.NO_VOICE = "This computer has no text-to-speech voices, so NPCs cannot be read aloud."
S.WORD = "speech"
S.HELP = "NPCs reading their words aloud: where it stands; on, off, or say for a test line"
S.TEST = "Hello, traveller. NPC speech is working."
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

-- Words in a voice's name that tell a woman's from a man's (Windows names
-- its voices "Microsoft Zira", "Microsoft David", ...). "female" holds
-- "male", so a man's voice is never one with "female" in its name.
local NAMES = {
    female = { "zira", "hazel", "susan", "eva", "helena", "female", "samantha", "victoria", "karen" },
    male = { "david", "mark", "george", "james", "male", "alex", "daniel", "fred" },
}

function S.Voice(speech, sex)
    if type(speech) ~= "table" or type(speech.voices) ~= "table" then return nil end
    local voices = speech.voices
    local want
    if type(sex) == "string" then want = NAMES[sex] end
    if want then
        for i = 1, #voices do
            local v = voices[i]
            if type(v) == "table" and type(v.name) == "string" then
                local name = v.name:lower()
                if not (sex == "male" and name:find("female", 1, true)) then
                    for j = 1, #want do
                        if name:find(want[j], 1, true) then return v end
                    end
                end
            end
        end
    end
    local v = voices[1]
    if type(v) ~= "table" then return nil end
    return v
end

function S.Declare(k, diag)
    local api = {}
    local ctx
    local told = false   -- the no-voice line, once a session
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

    -- Why the client cannot speak to the player's speakers, or nil when it
    -- can. localPlayback unknown (nil) counts as not there (lead section 270).
    local function blocked()
        local sp = ask("speech")
        if type(sp) ~= "table" then return S.NO_CALL end
        if sp.localPlayback ~= true then return S.NO_DEST end
        return nil
    end

    local function on()
        if not ctx or not ctx.settings then return false end
        return ctx.settings:get(S.SETTING) == true and ctx.settings:get(S.BONUS) == true and blocked() == nil
    end

    local function stop()
        pending = nil
        if not speaking then return end
        speaking = false
        local ok, err = pcall(ctx.client.stopSpeech)
        if not ok then fail("stop", err) end
    end

    -- Speak these words in the voice for the open window's NPC. where: the
    -- name a problem is recorded under. No voice: said once, nothing asked.
    local function speak(where, text)
        local voice = S.Voice(ask("speech"), ask("npcSex"))
        if not voice then
            if not told then
                told = true
                ctx.client.print(ns.id.title .. ": " .. S.NO_VOICE)
            end
            return
        end
        stop()   -- one voice at a time: the new window's words replace the last
        local ok, said, why = pcall(ctx.client.speak, text, voice)
        if not ok then fail(where, said) return end
        if said ~= true then fail(where, why) return end
        speaking = true
    end

    local function say(kind)
        pending = nil
        if not on() then return end
        local text = S.Clean(ask("npcText", kind))
        if not text then
            pending = kind
            return
        end
        speak(kind, text)
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

    -- Where it stands: { on, why, voices }. why: the reason it cannot
    -- speak (no call, no destination, bonus off), or nil.
    function api.status()
        local out = { on = false, voices = 0 }
        if not ctx then return out end
        out.why = blocked()
        if out.why == nil and ctx.settings:get(S.BONUS) ~= true then out.why = S.BONUS_OFF end
        out.on = ctx.settings:get(S.SETTING) == true
        local sp = ask("speech")
        if type(sp) == "table" and type(sp.voices) == "table" then out.voices = #sp.voices end
        return out
    end

    -- What the word prints, in one line.
    function api.line()
        local st = api.status()
        if st.why then return "NPC speech cannot play: " .. st.why .. "." end
        if not st.on then return "NPC speech is off (" .. S.WORD .. " on | off | say)." end
        if st.voices == 0 then return "NPC speech is on. " .. S.NO_VOICE end
        return string.format("NPC speech is on, %d voices found (%s on | off | say).", st.voices, S.WORD)
    end

    k:Setting({ key = S.BONUS, scope = "account", type = "bool", default = false,
        label = "Bonus extras", group = "general",
        help = "The optional extras just for fun. Off turns every one of them off at once; "
            .. "today that is NPCs reading their words aloud.",
        synonyms = { "bonus", "extras", "fun" } })

    k:Setting({ key = S.SETTING, scope = "account", type = "bool", default = false,
        label = "NPCs read their words aloud", group = "general",
        help = "When you talk to an NPC, the game's text-to-speech voice reads what they say "
            .. "on your own speakers. It stops when you close the window. " .. S.WHEN,
        synonyms = { "speech", "voice", "read aloud", "tts", "npc", "text to speech", "talk" },
        needs = S.BONUS,
        requires = function(settings)
            local why = blocked()
            if why then return false, why end
            if settings:get(S.BONUS) ~= true then return false, S.BONUS_OFF end
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
        provides = { Speaking = api.speaking, Status = api.status },
        events = events,
        ticks = { { every = S.RETRY, when = "always", run = function() retry() end } },
        start = function(c) ctx = c end,
        stop = function()
            if ctx and speaking then pcall(ctx.client.stopSpeech) end
            speaking, pending, ctx = false, nil, nil
        end,
    })

    if diag and type(diag.commands) == "table" then
        diag.commands[S.WORD] = function(rest)
            if not ctx then return end
            local word = tostring(rest or ""):lower():match("^%s*(%S*)")
            if word == "on" or word == "off" then
                ctx.settings:set(S.SETTING, word == "on")
                if word == "off" then stop() end
            elseif word == "say" and on() then
                speak("say", S.TEST)
                return
            end
            ctx.client.print(ns.id.title .. ": " .. api.line())
        end
        if type(diag.help) == "table" then diag.help[S.WORD] = S.HELP end
        diag.commands[S.BONUS_WORD] = function(rest)
            if not ctx then return end
            local word = tostring(rest or ""):lower():match("^%s*(%S*)")
            if word == "on" or word == "off" then
                ctx.settings:set(S.BONUS, word == "on")
                if word == "off" then stop() end
            end
            local lines = S.BonusLines(ctx.settings:get(S.BONUS) == true, ctx.settings:get(S.SETTING) == true)
            ctx.client.print(ns.id.title .. ": " .. lines[1])
            for i = 2, #lines do ctx.client.print("  " .. lines[i]) end
        end
        if type(diag.help) == "table" then diag.help[S.BONUS_WORD] = S.BONUS_HELP end
    end
    return api
end

-- The addon's own: declared when this file loads. Silent until the
-- setting is turned on.
ns.npcSpeech = S.Declare(ns, ns.diag)

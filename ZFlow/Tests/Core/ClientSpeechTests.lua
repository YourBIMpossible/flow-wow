local _, ns = ...
-- The client's speech reads and calls (G60), on a made-up environment:
-- c.speech(), c.speak(text, voice), c.stopSpeech(), c.npcText(kind).
-- The names (C_VoiceChat.GetTtsVoices, C_VoiceChat.SpeakText,
-- C_VoiceChat.StopSpeakingText, TextToSpeech_Speak, the quest and gossip
-- text reads) are first guesses, none seen in game on 16001.
local tests = {}

local function voiceChat(log, opts)
    opts = opts or {}
    return {
        GetTtsVoices = function()
            if opts.voicesFail then error("voices failed (test)") end
            return { { voiceID = 3, name = "Voice A" } }
        end,
        SpeakText = function(...) log[#log + 1] = { ... } end,
        StopSpeakingText = function() log.stops = (log.stops or 0) + 1 end,
    }
end

tests["client speech: absent - speech nil, speak and stop refuse, nothing raises"] = function(t)
    local c = ns.make.client({})
    t.eq(c.speech(), nil)
    local ok, why = c.speak("Hello.", { voiceID = 3 })
    t.eq(ok, false)
    t.ok(type(why) == "string", "a reason")
    t.eq(c.stopSpeech(), false)
end

tests["client speech: the voices, and a raising read gives nil"] = function(t)
    local c = ns.make.client({ C_VoiceChat = voiceChat({}) })
    t.eq(c.speech(), { voices = { { voiceID = 3, name = "Voice A" } } })
    local bad = ns.make.client({ C_VoiceChat = voiceChat({}, { voicesFail = true }) })
    t.eq(bad.speech(), nil)
end

tests["client speech: SpeakText gets voice, text, local playback, rate 0, volume 100"] = function(t)
    local log = {}
    local c = ns.make.client({ C_VoiceChat = voiceChat(log),
        Enum = { VoiceTtsDestination = { LocalPlayback = 1 } } })
    t.eq(c.speak("Hello.", { voiceID = 3 }), true)
    t.eq(log[1], { 3, "Hello.", 1, 0, 100 })
    t.eq(c.stopSpeech(), true)
    t.eq(log.stops, 1)
end

tests["client speech: with no local playback value known, SpeakText is not called - no guessed destination"] = function(t)
    local log = {}
    local c = ns.make.client({ C_VoiceChat = voiceChat(log) })
    local ok, why = c.speak("Hello.", { voiceID = 3 })
    t.eq(ok, false, "a guessed number could be another destination on this client")
    t.ok(type(why) == "string", "a reason")
    t.eq(#log, 0, "nothing was spoken")
end

tests["client speech: the game's own helper is used when it is there"] = function(t)
    local log, got = {}, nil
    local c = ns.make.client({ C_VoiceChat = voiceChat(log),
        TextToSpeech_Speak = function(text, voice) got = { text, voice and voice.voiceID } end })
    t.eq(c.speak("Hello.", { voiceID = 3 }), true)
    t.eq(got, { "Hello.", 3 })
    t.eq(#log, 0, "not straight to the API")
end

tests["client speech: npc text reads, the quest detail with its objective"] = function(t)
    local c = ns.make.client({
        C_GossipInfo = { GetText = function() return "Well met." end },
        GetQuestText = function() return "Wolves." end,
        GetObjectiveText = function() return "Slay 4." end,
        GetProgressText = function() return "" end,
        GetRewardText = function() error("not open (test)") end,
    })
    t.eq(c.npcText("gossip"), "Well met.")
    t.eq(c.npcText("detail"), "Wolves. Slay 4.")
    t.eq(c.npcText("progress"), nil, "empty text is not read yet")
    t.eq(c.npcText("reward"), nil, "a raising read gives nil")
    t.eq(c.npcText("greeting"), nil, "absent")
end

return tests

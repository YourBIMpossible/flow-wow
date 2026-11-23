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
    t.eq(c.speech(), { voices = { { voiceID = 3, name = "Voice A" } }, localPlayback = false })
    local bad = ns.make.client({ C_VoiceChat = voiceChat({}, { voicesFail = true }) })
    t.eq(bad.speech(), nil)
end

-- Lead sections 270 and 274: whether the local playback destination is
-- known. True only with Enum.VoiceTtsDestination.LocalPlayback a number;
-- the TextToSpeech_Speak helper alone does not count (its destination on
-- this client is unseen) - never a guessed value.
tests["client speech: localPlayback says whether the destination is known"] = function(t)
    local withEnum = ns.make.client({ C_VoiceChat = voiceChat({}),
        Enum = { VoiceTtsDestination = { LocalPlayback = 1 } } })
    t.eq(withEnum.speech().localPlayback, true)
    local withHelper = ns.make.client({ C_VoiceChat = voiceChat({}),
        TextToSpeech_Speak = function() end })
    t.eq(withHelper.speech().localPlayback, false, "the helper alone: destination unseen")
    local noValue = ns.make.client({ C_VoiceChat = voiceChat({}),
        Enum = { VoiceTtsDestination = { LocalPlayback = "one" } } })
    t.eq(noValue.speech().localPlayback, false)
    t.eq(ns.make.client({ C_VoiceChat = voiceChat({}) }).speech().localPlayback, false)
end

-- NS-1a (lead section 275): a secret LocalPlayback number is not a
-- destination - not known, and nothing is spoken to it.
tests["client speech: a secret LocalPlayback value is not a destination"] = function(t)
    local log = {}
    local c = ns.make.client({ C_VoiceChat = voiceChat(log),
        Enum = { VoiceTtsDestination = { LocalPlayback = 1 } },
        issecretvalue = function(v) return v == 1 end })
    t.eq(c.speech().localPlayback, false)
    local ok = c.speak("Hello.", { voiceID = 3 })
    t.eq(ok, false)
    t.eq(#log, 0, "nothing was spoken")
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

-- NS-3 (lead section 274): helper present, enum absent -> refused, and
-- neither the helper nor SpeakText is called.
tests["client speech: helper present, enum absent - refused, nothing called"] = function(t)
    local log, helped = {}, 0
    local c = ns.make.client({ C_VoiceChat = voiceChat(log),
        TextToSpeech_Speak = function() helped = helped + 1 end })
    local ok, why = c.speak("Hello.", { voiceID = 3 })
    t.eq(ok, false)
    t.eq(why, "no local playback destination")
    t.eq(helped, 0, "the helper is not called")
    t.eq(#log, 0, "SpeakText is not called")
end

tests["client speech: the game's own helper is used when the destination is known"] = function(t)
    local log, got = {}, nil
    local c = ns.make.client({ C_VoiceChat = voiceChat(log),
        Enum = { VoiceTtsDestination = { LocalPlayback = 1 } },
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

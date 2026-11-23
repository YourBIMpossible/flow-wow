local _, ns = ...
-- NPC speech (P-QOL): the voice is picked to match the NPC, as Flow's
-- Spoken extra does, by the voice's name. Made-up voices. Not tested in
-- game: the client's speech and NPC names are first guesses.
local tests = {}

local S = ns.NpcSpeech

local function speech(...)
    local voices = {}
    for i, name in ipairs({ ... }) do voices[i] = { voiceID = i, name = name } end
    return { voices = voices, localPlayback = true }
end

tests["npc voice: a woman's voice for a female NPC, a man's for a male one"] = function(t)
    local sp = speech("Microsoft David", "Microsoft Zira")
    t.eq(S.Voice(sp, "female").voiceID, 2)
    t.eq(S.Voice(sp, "male").voiceID, 1)
end

tests["npc voice: a voice named female is never taken as a man's"] = function(t)
    local sp = speech("English Female", "English Male")
    t.eq(S.Voice(sp, "male").voiceID, 2)
    t.eq(S.Voice(sp, "female").voiceID, 1)
end

tests["npc voice: the sex not known, or no voice of that kind - the first one"] = function(t)
    local sp = speech("Voice A", "Microsoft Zira")
    t.eq(S.Voice(sp).voiceID, 1)
    t.eq(S.Voice(sp, "male").voiceID, 1)
    t.eq(S.Voice(sp, "something").voiceID, 1)
    t.eq(S.Voice(speech("Voice A"), "female").voiceID, 1)
end

tests["npc voice: no voices, or a voice without a name - nothing raised"] = function(t)
    t.eq(S.Voice(nil, "female"), nil)
    t.eq(S.Voice({ voices = {} }, "female"), nil)
    local sp = { voices = { { voiceID = 4 }, { voiceID = 5, name = "Hazel" } } }
    t.eq(S.Voice(sp, "female").voiceID, 5)
    t.eq(S.Voice(sp, "male").voiceID, 4)
end

tests["npc voice: the client says the NPC's sex from UnitSex, or nothing"] = function(t)
    local asked
    local c = ns.make.client({ UnitSex = function(unit) asked = unit return 3 end })
    t.eq(c.npcSex(), "female")
    t.eq(asked, "npc")
    t.eq(ns.make.client({ UnitSex = function() return 2 end }).npcSex(), "male")
    t.eq(ns.make.client({ UnitSex = function() return 1 end }).npcSex(), nil, "1 is neither")
    t.eq(ns.make.client({ UnitSex = function() error("no npc (test)") end }).npcSex(), nil)
    t.eq(ns.make.client({}).npcSex(), nil, "absent")
end

return tests

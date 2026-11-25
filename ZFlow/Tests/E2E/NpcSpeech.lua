local _, ns = ...
-- NPC text aloud (G60) end to end, on the whole add-on loaded on a fake
-- client. With the setting on, a quest's text is read aloud through the
-- client's text-to-speech call once when its window opens, and stopped when
-- it closes. Per lead section 236: the speech call absent (greyed row,
-- nothing called), the text not read yet then read, the speak call raising
-- once then fine, and a reload keeping the setting. Made-up text and
-- voices. Not tested in game: the client's speech names are first guesses.
local tests = {}

local SETTING, BONUS = "general.npcSpeech", "general.bonus"
local NO_CALL = "Your game client has no text-to-speech call"
local STORY = "Wolves have been taking our sheep. Slay 4 of them."
local NO_DEST = "Your game client gives no local playback destination for speech"
local VOICES = { voices = { { voiceID = 7, name = "Voice A" }, { voiceID = 8, name = "Voice B" } },
                 localPlayback = true }
local NO_LOCAL = { voices = VOICES.voices, localPlayback = false }

-- opts: account, char (saved tables), speech (false: the call absent), on.
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setClass("WARRIOR")
    c.setLevel(10)
    if opts.speech == "noLocal" then
        c.setSpeech(NO_LOCAL)
    elseif opts.speech ~= false then
        c.setSpeech(VOICES)
    end
    if opts.before then opts.before(c) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    if opts.on then
        addon.settings:set(BONUS, true)
        addon.settings:set(SETTING, true)
    end
    return c, addon
end

local function entry(addon)
    local found = addon.SettingsPage.Search(addon, "tts")
    for _, e in ipairs(found and found.results or {}) do
        if e.key == SETTING then return e end
    end
    return nil
end

tests["npc speech: off by default, filed under general, found by its words"] = function(t)
    local c, addon = boot()
    local row = addon.settings:row(SETTING)
    t.eq(row and row.type, "bool")
    t.eq(row and row.group, "general")
    t.eq(addon.settings:get(SETTING), false)
    local words = table.concat(row and row.synonyms or {}, " ")
    for _, w in ipairs({ "speech", "voice", "read aloud", "tts", "npc" }) do
        t.ok(words:find(w, 1, true) ~= nil, "synonym " .. w .. ": " .. words)
    end
    c.setNpcText("detail", STORY)
    c.fire("QUEST_DETAIL")
    t.eq(#c.spoken(), 0, "off: nothing read aloud")
end

tests["npc speech: on, a quest detail opens - speak once with its text"] = function(t)
    local c = boot({ on = true })
    c.setNpcText("detail", STORY)
    c.fire("QUEST_DETAIL")
    local said = c.spoken()
    t.eq(#said, 1)
    t.eq(said[1] and said[1].text, STORY)
    t.eq(said[1] and said[1].voice and said[1].voice.voiceID, 7)
    c.advance(5, 20)
    t.eq(#c.spoken(), 1, "said once, not again on the ticks")
end

tests["npc speech: the window closes - the voice stops"] = function(t)
    local c = boot({ on = true })
    c.setNpcText("detail", STORY)
    c.fire("QUEST_DETAIL")
    local before = c.speechStops()
    c.fire("QUEST_FINISHED")
    t.eq(c.speechStops(), before + 1, "quest window closed")
    c.setNpcText("gossip", "Well met.")
    c.fire("GOSSIP_SHOW")
    t.eq(c.spoken()[2] and c.spoken()[2].text, "Well met.")
    local mid = c.speechStops()
    c.fire("GOSSIP_CLOSED")
    t.eq(c.speechStops(), mid + 1, "gossip window closed")
end

tests["npc speech: the speech call absent - greyed row, nothing called, nothing raised"] = function(t)
    local c, addon = boot({ speech = false, on = true })
    local e = entry(addon)
    t.ok(e ~= nil, "the row is found by tts")
    t.eq(e and e.available, false)
    t.ok(e and type(e.because) == "string" and e.because:find(NO_CALL, 1, true) ~= nil,
        "the reason: " .. tostring(e and e.because))
    c.setNpcText("detail", STORY)
    c.fire("QUEST_DETAIL")
    c.fire("QUEST_FINISHED")
    t.eq(#c.spoken(), 0)
    t.eq(c.speechStops(), 0)
    t.eq(c.speakCalls(), 0, "speak never asked")
end

tests["npc speech: the text not read yet, then read"] = function(t)
    local c = boot({ on = true })
    c.fire("QUEST_DETAIL")
    t.eq(#c.spoken(), 0, "no text yet: nothing said")
    c.setNpcText("detail", STORY)
    c.advance(1, 5)
    t.eq(#c.spoken(), 1, "the text arrives while the window is open")
    t.eq(c.spoken()[1] and c.spoken()[1].text, STORY)
end

tests["npc speech: the speak call raising once, then fine"] = function(t)
    local c = boot({ on = true, before = function(x) x.setSpeakFails(1) end })
    c.setNpcText("detail", STORY)
    c.fire("QUEST_DETAIL")
    t.eq(#c.spoken(), 0, "the call raised: nothing said")
    c.fire("QUEST_FINISHED")
    c.fire("QUEST_DETAIL")
    t.eq(#c.spoken(), 1, "the next window is read")
end

tests["npc speech: the bonus master switch off silences it"] = function(t)
    local c, addon = boot({ on = true })
    t.eq(addon.settings:get(BONUS), true, "turned on by this test's boot")
    addon.settings:set(BONUS, false)
    t.eq(addon.settings:available(SETTING), false, "greyed under the master switch")
    c.setNpcText("detail", STORY)
    c.fire("QUEST_DETAIL")
    t.eq(#c.spoken(), 0)
end

tests["npc speech: a reload keeps the setting"] = function(t)
    local c = boot({ on = true })
    local c2, addon2 = boot({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    t.eq(addon2.settings:get(SETTING), true)
    c2.setNpcText("progress", "Have you slain them yet?")
    c2.fire("QUEST_PROGRESS")
    t.eq(c2.spoken()[1] and c2.spoken()[1].text, "Have you slain them yet?")
end

-- Lead section 270: the call is there but the local destination is not known.
tests["npc speech: no local playback destination - greyed row with its reason, nothing spoken"] = function(t)
    local c, addon = boot({ speech = "noLocal", on = true })
    local e = entry(addon)
    t.ok(e ~= nil, "the row is found by tts")
    t.eq(e and e.available, false)
    t.ok(e and type(e.because) == "string" and e.because:find(NO_DEST, 1, true) ~= nil,
        "the reason: " .. tostring(e and e.because))
    t.eq(addon.settings:available(SETTING), false)
    c.setNpcText("detail", STORY)
    c.fire("QUEST_DETAIL")
    c.advance(5, 20)
    t.eq(#c.spoken(), 0)
    t.eq(c.speakCalls(), 0, "speak never asked")
end

tests["npc speech: call and destination both there - the row is usable"] = function(t)
    local _, addon = boot()
    local e = entry(addon)
    t.eq(e and e.available, true)
    t.eq(e and e.because, nil)
end

-- F-22 (lead sections 792, 794): Bonus mode, as Flow's (Modules/Bonus.lua;
-- Settings.lua:783-795): off by default, a word that turns it on or off and
-- says where it stands, with each extra and its own switch. A saved choice
-- is kept. Fails before: the default is on and there is no bonus word.
local function said(c, from)
    local out = {}
    for i = from + 1, #c.printed do out[#out + 1] = tostring(c.printed[i]) end
    return out
end

tests["npc speech: bonus mode is off by default; with no choice saved, nothing is read aloud"] = function(t)
    local c, addon = boot()
    t.eq(addon.settings:get(BONUS), false, "off by default, as Flow")
    addon.settings:set(SETTING, true)
    c.setNpcText("detail", STORY)
    c.fire("QUEST_DETAIL")
    t.eq(#c.spoken(), 0, "speech on but bonus mode off: nothing said")
end

tests["npc speech: a saved bonus choice is kept"] = function(t)
    local c, addon = boot({ account = { settings = { general = { bonus = true } } } })
    t.eq(addon.settings:get(BONUS), true, "the saved on stays on")
    addon.settings:set(SETTING, true)
    c.setNpcText("detail", STORY)
    c.fire("QUEST_DETAIL")
    t.eq(#c.spoken(), 1)
end

tests["npc speech: the bonus word"] = function(t)
    local S = ns.NpcSpeech
    t.eq(type(S.BonusLines), "function", "S.BonusLines")
    if type(S.BonusLines) ~= "function" then return end
    t.eq(S.BonusLines(false, false), { S.BONUS_IS_OFF, S.EXTRA_LINE:format(S.EXTRA_SPEECH, "off") })
    t.eq(S.BonusLines(true, true), { S.BONUS_IS_ON, S.EXTRA_LINE:format(S.EXTRA_SPEECH, "on") })
    local c, addon = boot()
    local n = #c.printed
    c.slashes[ns.id.slash]("bonus")
    t.eq(said(c, n), { ns.id.title .. ": " .. S.BONUS_IS_OFF, "  " .. S.EXTRA_LINE:format(S.EXTRA_SPEECH, "off") })
    c.slashes[ns.id.slash]("bonus on")
    t.eq(addon.settings:get(BONUS), true, "bonus on")
    c.slashes[ns.id.slash]("bonus off")
    t.eq(addon.settings:get(BONUS), false, "bonus off")
end

return tests

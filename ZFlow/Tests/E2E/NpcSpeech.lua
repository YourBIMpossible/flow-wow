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
local VOICES = { voices = { { voiceID = 7, name = "Voice A" }, { voiceID = 8, name = "Voice B" } } }

-- opts: account, char (saved tables), speech (false: the call absent), on.
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setClass("WARRIOR")
    c.setLevel(10)
    if opts.speech ~= false then c.setSpeech(VOICES) end
    if opts.before then opts.before(c) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    if opts.on then addon.settings:set(SETTING, true) end
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
    t.eq(addon.settings:get(BONUS), true, "bonus extras on by default")
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

return tests

local _, ns = ...
-- NPC speech (P-QOL) end to end on the whole add-on and a fake client: the
-- voice matches the NPC, a computer with no voices is said once, and the
-- word says where the extra stands and speaks a test line. Made-up text
-- and voices. Not tested in game.
local tests = {}

local S = ns.NpcSpeech
local SETTING = "general.npcSpeech"
local STORY = "Wolves have been taking our sheep. Slay 4 of them."
local VOICES = { voices = { { voiceID = 7, name = "Microsoft David" }, { voiceID = 8, name = "Microsoft Zira" } },
                 localPlayback = true }

local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR")
    c.setLevel(10)
    if opts.speech ~= false then c.setSpeech(opts.speech or VOICES) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    -- Lead section 852: the voice needs Bonus extras on too, now it is off
    -- by default (as Tests/E2E/NpcSpeech.lua does).
    if opts.on then
        addon.settings:set("general.bonus", true)
        addon.settings:set(SETTING, true)
    end
    return c, addon
end

local function printed(c, from)
    local out = {}
    for i = (from or 0) + 1, #c.printed do out[#out + 1] = tostring(c.printed[i]) end
    return table.concat(out, "\n")
end

local function count(text, needle)
    local n, at = 0, 1
    while true do
        local a, b = text:find(needle, at, true)
        if not a then return n end
        n, at = n + 1, b + 1
    end
end

tests["npc speech voice: a female NPC is read in a woman's voice, a male one in a man's"] = function(t)
    local c = boot({ on = true })
    c.setNpcText("detail", STORY)
    c.setNpcSex("female")
    c.fire("QUEST_DETAIL")
    c.fire("QUEST_FINISHED")
    c.setNpcSex("male")
    c.fire("QUEST_DETAIL")
    local said = c.spoken()
    t.eq(#said, 2)
    t.eq(said[1] and said[1].voice and said[1].voice.voiceID, 8)
    t.eq(said[2] and said[2].voice and said[2].voice.voiceID, 7)
end

tests["npc speech voice: the NPC's sex not known - the first voice, as before"] = function(t)
    local c = boot({ on = true })
    c.setNpcText("gossip", STORY)
    c.fire("GOSSIP_SHOW")
    local said = c.spoken()
    t.eq(said[1] and said[1].voice and said[1].voice.voiceID, 7)
end

tests["npc speech voice: no voices on this computer is said once, and nothing is spoken"] = function(t)
    local c = boot({ on = true, speech = { voices = {}, localPlayback = true } })
    local from = #c.printed
    c.setNpcText("detail", STORY)
    c.fire("QUEST_DETAIL")
    c.fire("QUEST_FINISHED")
    c.fire("QUEST_DETAIL")
    c.advance(5, 20)
    t.eq(#c.spoken(), 0)
    t.eq(c.speakCalls(), 0, "the speak call is not asked without a voice")
    t.eq(count(printed(c, from), S.NO_VOICE), 1, "said once")
end

tests["npc speech word: says off, then on, with the voices found"] = function(t)
    local c, addon = boot()
    -- Lead section 872: the voice needs Bonus extras on, now off by default.
    addon.settings:set("general.bonus", true)
    local from = #c.printed
    c.slashes[ns.id.slash](S.WORD)
    t.ok(printed(c, from):find("off", 1, true) ~= nil, printed(c, from))
    from = #c.printed
    c.slashes[ns.id.slash](S.WORD .. " on")
    t.eq(addon.settings:get(SETTING), true)
    local text = printed(c, from)
    t.ok(text:find("on", 1, true) ~= nil, text)
    t.ok(text:find("2 voices", 1, true) ~= nil, text)
    c.slashes[ns.id.slash](S.WORD .. " off")
    t.eq(addon.settings:get(SETTING), false)
end

tests["npc speech word: say speaks the test line when on, and says why when it cannot"] = function(t)
    local c = boot({ on = true })
    c.slashes[ns.id.slash](S.WORD .. " say")
    local said = c.spoken()
    t.eq(#said, 1)
    t.eq(said[1] and said[1].text, S.TEST)

    local off = boot()
    local from = #off.printed
    off.slashes[ns.id.slash](S.WORD .. " say")
    t.eq(#off.spoken(), 0, "off: nothing spoken")
    t.ok(printed(off, from):find("off", 1, true) ~= nil, printed(off, from))

    local none = boot({ speech = false })
    from = #none.printed
    none.slashes[ns.id.slash](S.WORD .. " say")
    t.eq(none.speakCalls(), 0)
    t.ok(printed(none, from):find(S.NO_CALL, 1, true) ~= nil, printed(none, from))
end

tests["npc speech word: the word and its help are given to the slash command"] = function(t)
    local k = ns.Kernel({}, ns.make.fakeClient())
    local diag = { commands = {}, help = {} }
    S.Declare(k, diag)
    t.eq(type(diag.commands[S.WORD]), "function")
    t.eq(type(S.HELP), "string")
    t.eq(diag.help[S.WORD], S.HELP)
end

return tests

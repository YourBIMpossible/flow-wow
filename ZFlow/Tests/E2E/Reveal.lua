local _, ns = ...
-- G55 staged reveal (lead sections 228-230, 236), on the whole add-on loaded
-- on a fake client. A new player's surfaces come in one at a time, each on
-- its own trigger, as legacy Flow's Modules/Reveal.lua did:
--   arrow    walked 10 yards from where they stood, or a quest accepted
--   tracker  no tracker in this add-on yet: the stage is skipped
--   icon     a live hostile target, or a fight starts
--   advice   a level up, or ten minutes after the arrow came in
-- The stages are saved per character. "reveal all" shows everything now,
-- "reveal reset" starts over. A player whose saved data is from before
-- (the account's saved table was there at login) sees everything. The
-- login intro waits until the arrow is in (legacy Splash.lua:211).
-- Offline: the fake client, not the game. Made-up places and names.
local tests = {}

local R = ns.Reveal

local function questie()
    local db = {}
    function db.GetQuest(id)
        if id == 303 then return { ObjectiveData = { { Type = "monster", Id = 9002 } } } end
    end
    function db.GetNPC(id)
        if id == 9002 then return { name = "Far Wolf", spawns = { [40] = { { 50, 50 } } } } end
    end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [12] = 1411, [40] = 1420 })[area] end
    return db, zones
end

-- opts: account, char (saved tables; left out: none saved before, a new
-- player), early(c, addon) runs after the files load and before login,
-- staged (false: leave the setting at its default). Lead section 294 made
-- the setting off by default; these tests are of the stages, so they turn
-- it on as a player would, after login.
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    if opts.account then c.setSaved(ns.id.accountDB, opts.account) end
    if opts.char then c.setSaved(ns.id.charDB, opts.char) end
    c.setZone(1, 1411); c.setPosition(1411, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(1411, 1000, 500); c.setMapCont(1411, 1)
    c.setMapSize(1420, 1000, 1000); c.setMapCont(1420, 1)
    c.setMapCorners(1411, { cont = 1, ox = 1000, oy = 2000, ex = 0, ey = -1000, sx = -500, sy = 0 })
    c.setMapCorners(1420, { cont = 1, ox = 1000, oy = 1000, ex = 0, ey = -1000, sx = -1000, sy = 0 })
    c.setClass("WARRIOR"); c.setFaction("Horde"); c.setLevel(1)
    c.setDead(false)
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog({ { id = 303, title = "Wolves", objectives = { { text = "Wolves slain: 0/4" } } } })
    c.setWorldPosition(1, 100, 100)
    c.setTarget({ exists = false })
    c.setSpellId("Rend", 772); c.setSpellTexture(772, "tex:Rend")
    local addon = ns.offline.addon(c)
    if opts.early then opts.early(c, addon) end
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    if opts.staged ~= false then addon.settings:set(ns.Reveal.SETTING, true) end
    c.advance(10, 40)
    return c, addon
end

local function named(list, suffix)
    for _, h in ipairs(list or {}) do
        if type(h.spec) == "table" and h.spec.name == ns.id.framePrefix .. suffix then return h end
    end
    return nil
end

local function arrowShown(c)
    c.advance(2, 8)
    local a = named(c.arrows, "QuestArrow")
    return a ~= nil and a.shown == true
end

-- The rotation icon given a suggestion now: shown or not.
local function iconShown(c, addon)
    local D = addon.RotationDriver
    addon.settings:set(D.SETTING, true)
    addon.bus:emit(D.EVENT, { suggestion = { spell = "Rend" } })
    local icon = named(c.icons, "RotationIcon")
    return icon ~= nil and icon.shown == true
end

-- The advice panel with one prompt in it: shown or not.
local function adviceShown(c, addon)
    addon.advisor.Add("revealTest", "Train your weapon skill.", 1)
    -- Drawn by the kit (UI/Advisor.lua); the plain panel when the kit
    -- window is refused.
    local w = type(c.kitWindows) == "function" and c.kitWindows().Advisor
    if type(w) == "table" and w.shown == true then return true end
    local p = named(c.panels, "Advisor")
    return p ~= nil and p.shown == true
end

local function said(c, rest)
    local before = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = before + 1, #c.printed do out[#out + 1] = tostring(c.printed[i]) end
    return out
end

local function anyHas(lines, text)
    for _, l in ipairs(lines or {}) do
        if tostring(l):find(text, 1, true) then return true end
    end
    return false
end

local function printedSince(c, from)
    local out = {}
    for i = from + 1, #c.printed do out[#out + 1] = tostring(c.printed[i]) end
    return out
end

local function revealProblems(addon)
    local n = 0
    for _, p in ipairs(addon.problems:list()) do
        local text = tostring(p.kind) .. " " .. tostring(p.owner) .. " " .. tostring(p.text)
        if text:find(R.NAME, 1, true) then n = n + (p.count or 1) end
    end
    return n
end

local function walk(c, yards)
    c.setWorldPosition(1, 100, 100 + yards)
    c.advance(1, 4)
end

tests["reveal 236: a new player sees no arrow, icon or advice at login; the tracker stage is skipped"] = function(t)
    local c, addon = boot()
    t.eq((addon:ModuleState(R.NAME)), "started")
    t.eq(arrowShown(c), false, "no arrow yet")
    t.eq(iconShown(c, addon), false, "no icon yet")
    t.eq(adviceShown(c, addon), false, "no advice panel yet")
    t.eq(addon.revealed("tracker"), true, "no tracker here: nothing to hold back")
    t.eq(addon.store:get("char", R.PATH), {}, "the character's stages: none yet")
    local lines = said(c, R.WORD)
    t.ok(anyHas(lines, "arrow (not yet)"), "the status names the arrow: " .. table.concat(lines, " / "))
    t.ok(anyHas(lines, "tracker (no tracker yet)"), "the tracker stage says it is skipped")
    t.eq(revealProblems(addon), 0)
end

tests["reveal 236: the arrow comes in after walking 10 yards, with one line saying what it is"] = function(t)
    local c, addon = boot()
    walk(c, 6)
    t.eq(arrowShown(c), false, "6 yards: not yet")
    local from = #c.printed
    walk(c, 11)
    t.eq(arrowShown(c), true, "11 yards: the arrow")
    t.eq(addon.store:get("char", R.PATH .. ".arrow"), true, "saved for the character")
    t.ok(anyHas(printedSince(c, from), "arrow points to your next step"), "one line says what it is")
    t.eq(iconShown(c, addon), false, "the icon still waits for its own trigger")
end

tests["reveal 236: accepting a quest brings the arrow in"] = function(t)
    local c, addon = boot()
    c.fire("QUEST_ACCEPTED", 1, 303)
    t.eq(arrowShown(c), true)
    t.eq(addon.revealed("arrow"), true)
end

tests["reveal 236: a live hostile target or a fight brings the icon in"] = function(t)
    local c, addon = boot()
    c.setTarget({ exists = true, hostile = false, dead = false })
    c.fire("PLAYER_TARGET_CHANGED")
    t.eq(addon.revealed("icon"), false, "a friendly target: not yet")
    c.setTarget({ exists = true, hostile = true, dead = true })
    c.fire("PLAYER_TARGET_CHANGED")
    t.eq(addon.revealed("icon"), false, "a dead enemy: not yet")
    c.setTarget({ exists = true, hostile = true, dead = false })
    c.fire("PLAYER_TARGET_CHANGED")
    t.eq(addon.revealed("icon"), true, "a live enemy: the icon")
    t.eq(iconShown(c, addon), true)

    local c2, addon2 = boot()
    c2.setCombat(true)
    t.eq(addon2.revealed("icon"), true, "a fight starts: the icon")
    t.eq(iconShown(c2, addon2), true)
end

tests["reveal 236: a level up brings the advice panel in; so do ten minutes after the arrow"] = function(t)
    local c, addon = boot()
    c.fire("PLAYER_LEVEL_UP", 2)
    t.eq(adviceShown(c, addon), true, "level up: the advice panel")

    local c2, addon2 = boot()
    walk(c2, 12)
    c2.advance(300, 20)
    t.eq(addon2.revealed("advice"), false, "five minutes after the arrow: not yet")
    c2.advance(310, 20)
    t.eq(adviceShown(c2, addon2), true, "ten minutes after the arrow: the advice panel")
end

tests["reveal 236: a reload keeps the revealed stages"] = function(t)
    local c, addon = boot()
    c.fire("QUEST_ACCEPTED", 1, 303)
    t.eq(addon.revealed("arrow"), true)
    local account, char = c.saved(ns.id.accountDB), c.saved(ns.id.charDB)
    local c2, addon2 = boot({ account = account, char = char })
    t.eq(arrowShown(c2), true, "the arrow is still in")
    t.eq(addon2.revealed("icon"), false, "the icon still waits")
    t.eq(iconShown(c2, addon2), false)
end

-- RV-1 (lead section 274): when the arrow came in is saved with the
-- stages, as the client's clock gives it, so a reload does not restart
-- the ten-minute wait for the advice panel.
tests["reveal 236: a reload keeps the ten-minute wait: advice at T+600 s, not T+900 s"] = function(t)
    local T = 50000
    local c, addon = boot({ early = function(c0) c0.setClock(T) end })
    c.fire("QUEST_ACCEPTED", 1, 303)
    c.advance(1, 4)
    t.eq(addon.revealed("arrow"), true, "the arrow at T")
    t.eq(addon.store:get("char", R.PATH .. ".arrowAt"), T, "saved with the stages")
    local account, char = c.saved(ns.id.accountDB), c.saved(ns.id.charDB)
    local c2, addon2 = boot({ account = account, char = char, early = function(c0) c0.setClock(T + 300) end })
    t.eq(addon2.revealed("advice"), false, "reloaded at T+300 s: not yet")
    c2.setClock(T + 590)
    c2.advance(1, 4)
    t.eq(addon2.revealed("advice"), false, "T+590 s: not yet")
    c2.setClock(T + 601)
    c2.advance(1, 4)
    t.eq(addon2.revealed("advice"), true, "T+600 s: the advice panel, not T+900 s")
    t.eq(adviceShown(c2, addon2), true)
end

tests["reveal: with no clock known the wait is this session's, as before"] = function(t)
    local c, addon = boot()
    c.fire("QUEST_ACCEPTED", 1, 303)
    c.advance(1, 4)
    t.eq(addon.store:get("char", R.PATH .. ".arrowAt"), nil, "nothing saved without a clock")
    c.advance(610, 20)
    t.eq(addon.revealed("advice"), true, "ten minutes of this session: the advice panel")
end

tests["reveal 236: reveal all shows everything now; reveal reset starts over"] = function(t)
    local c, addon = boot()
    local lines = said(c, R.WORD .. " all")
    t.ok(anyHas(lines, "everything is on screen now"), "said: " .. table.concat(lines, " / "))
    t.eq(arrowShown(c), true)
    t.eq(iconShown(c, addon), true)
    t.eq(adviceShown(c, addon), true)
    t.eq(addon.store:get("char", R.PATH .. ".all"), true)

    lines = said(c, R.WORD .. " RESET")
    t.ok(anyHas(lines, "one at a time again"), "said: " .. table.concat(lines, " / "))
    t.eq(addon.store:get("char", R.PATH), {}, "the stages are cleared")
    t.eq(arrowShown(c), false, "the arrow waits again")
    t.eq(iconShown(c, addon), false, "the icon waits again")
    t.eq(adviceShown(c, addon), false, "the advice panel waits again")
    walk(c, 12)
    t.eq(arrowShown(c), true, "walking brings the arrow in again")
end

tests["reveal 236: an existing player's saved data: everything shown"] = function(t)
    local account = { schema = 1, settings = { general = { npcSpeech = false } }, layout = { arrowIntroSeen = true } }
    local char = { schema = 1, state = { intro = { seen = true } } }
    local c, addon = boot({ account = account, char = char })
    t.eq(addon.store:get("char", R.PATH .. ".all"), true, "migrated as fully revealed")
    t.eq(arrowShown(c), true)
    t.eq(iconShown(c, addon), true)
    t.eq(adviceShown(c, addon), true)

    -- A new character of a player who already uses the add-on: the same.
    local c2, addon2 = boot({ account = { schema = 1 } })
    t.eq(addon2.store:get("char", R.PATH .. ".all"), true, "a new character of an existing account")
    t.eq(arrowShown(c2), true)
end

tests["reveal 236: a trigger arriving before the module starts"] = function(t)
    local early = {}
    local c, addon = boot({ early = function(c0, a0)
        early.asked = a0.revealed("arrow")
        early.shown = a0.reveal.Show("arrow")
        c0.fire("QUEST_ACCEPTED", 1, 303)
        c0.fire("PLAYER_LEVEL_UP", 2)
    end })
    t.eq(early.asked, true, "asked before the saved data is open: open")
    t.eq(early.shown, false, "a stage cannot be shown before the saved data is open")
    t.eq(addon.store:get("char", R.PATH), {}, "nothing kept from before the start")
    t.eq(arrowShown(c), false)
    t.eq(revealProblems(addon), 0, "nothing raised")
    c.fire("QUEST_ACCEPTED", 1, 303)
    t.eq(arrowShown(c), true, "the next trigger works")
end

tests["reveal 236: a read raising then recovering"] = function(t)
    local c, addon = boot()
    -- While broken, the read raises for every caller; then it answers again.
    local broken, raised = true, 0
    local realPos, realTarget = c.worldPosition, c.target
    c.worldPosition = function(...)
        if broken then raised = raised + 1; error("position not ready") end
        return realPos(...)
    end
    c.target = function(...)
        if broken then raised = raised + 1; error("target not ready") end
        return realTarget(...)
    end
    c.setWorldPosition(1, 100, 112)
    c.setTarget({ exists = true, hostile = true, dead = false })
    c.advance(1, 4)
    c.fire("PLAYER_TARGET_CHANGED")
    t.ok(raised >= 2, "the reads raised: " .. raised)
    t.eq(addon.revealed("arrow"), false, "no position: not yet")
    t.eq(addon.revealed("icon"), false, "no target: not yet")
    broken = false
    c.advance(1, 4)
    t.eq(addon.revealed("arrow"), true, "answered again: the arrow")
    c.fire("PLAYER_TARGET_CHANGED")
    t.eq(addon.revealed("icon"), true, "answered again: the icon")
    t.eq((addon:ModuleState(R.NAME)), "started", "still running")
    t.eq(revealProblems(addon), 0)
end

-- Lead section 294: staging must not hold back the arrow, the icon or the
-- advice on any character unless the player turned it on.
tests["reveal 294: off by default: a new player at a default profile sees the arrow, the icon and the advice"] = function(t)
    local c, addon = boot({ staged = false })
    t.eq(addon.settings:get(R.SETTING), false, "the default")
    t.eq(arrowShown(c), true, "the arrow")
    t.eq(iconShown(c, addon), true, "the icon")
    t.eq(adviceShown(c, addon), true, "the advice panel")
end

-- A saved setting means the account table was there before this login,
-- so the stages are not held for this character anyway (UI/Reveal.lua
-- R.Initial); what is checked is that the saved on is read as on.
tests["reveal 294: an account that turned staging on keeps it"] = function(t)
    local _, addon = boot({ staged = false, account = { settings = { general = { reveal = true } } },
        char = {} })
    t.eq(addon.settings:get(R.SETTING), true, "the saved choice")
end

tests["reveal: the setting turns staging off (everything shown); filed under general with its words"] = function(t)
    local c, addon = boot()
    local row = addon.settings:row(R.SETTING)
    t.eq(row and row.type, "bool")
    t.eq(row and row.group, "general")
    t.eq(row and row.default, false, "off by default (lead section 294)")
    local words = table.concat(row and row.synonyms or {}, " ")
    for _, w in ipairs({ "reveal", "new player", "stages", "intro" }) do
        t.ok(words:find(w, 1, true) ~= nil, "synonym " .. w .. ": " .. words)
    end
    t.eq(arrowShown(c), false)
    addon.settings:set(R.SETTING, false)
    t.eq(arrowShown(c), true, "off: the arrow")
    t.eq(iconShown(c, addon), true, "off: the icon")
    t.eq(adviceShown(c, addon), true, "off: the advice panel")
    addon.settings:set(R.SETTING, true)
    t.eq(arrowShown(c), false, "on again: the stages as saved")
end

tests["reveal: the word has its help line"] = function(t)
    local c, addon = boot()
    t.ok(type(addon.diag.commands[R.WORD]) == "function", "the word is registered")
    local help = addon.diag.help[R.WORD]
    t.ok(type(help) == "string" and help:find("all", 1, true) ~= nil and help:find("reset", 1, true) ~= nil,
        "the help names all and reset: " .. tostring(help))
    local lines = said(c, "help " .. R.WORD)
    t.eq(#lines, 1)
end

-- Lead section 294 (Twin checks 16:58): staging is off by default, so a
-- new install gets the intro at its first login. The old case (the intro
-- waits for the arrow) needs staging on before the first login, which a
-- new install cannot have: its saved setting would make it an existing
-- account (UI/Reveal.lua R.Initial). Staging switched on later is pinned
-- by the stage tests above.
tests["reveal 294: staging off by default: a new install gets the intro at first login; the intro word shows it again"] = function(t)
    local c = boot({ staged = false })
    -- Drawn by the kit (UI/Intro.lua): the window "Intro".
    local function shown()
        local w = type(c.kitWindows) == "function" and c.kitWindows().Intro
        return type(w) == "table" and w.shown == true
    end
    t.ok(named(c.panels, "Intro") ~= nil, "the intro's plain panel is made, behind the kit")
    t.eq(shown(), true, "first login of a new install: the intro")
    t.eq(type(c.kitClose) == "function" and c.kitClose("Intro"), true, "the player closes it")
    t.eq(shown(), false, "closed")
    said(c, "intro")
    t.eq(shown(), true, "asked for: shown again")
end

tests["reveal: walking is measured on one continent only"] = function(t)
    t.eq(R.Moved({ cont = 1, wx = 0, wy = 0 }, { cont = 1, wx = 6, wy = 8 }, 10), true, "10 yards")
    t.eq(R.Moved({ cont = 1, wx = 0, wy = 0 }, { cont = 1, wx = 6, wy = 7 }, 10), false, "under 10")
    t.eq(R.Moved({ cont = 1, wx = 0, wy = 0 }, { cont = 2, wx = 60, wy = 80 }, 10), false, "another continent")
    t.eq(R.Moved(nil, { cont = 1, wx = 60, wy = 80 }, 10), false, "no start")
    t.eq(R.Initial({ account = false }), {}, "a new install: the stages")
    t.eq(R.Initial({ account = true }), { all = true }, "an existing account: everything")
    t.eq(R.Initial(nil), { all = true }, "not known: everything")
end

return tests

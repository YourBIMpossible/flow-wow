-- The two guide arrows on screen: the quest arrow and, behind it or on its
-- own, the translucent profession needle.
--
-- This file makes no frame and decides no layout rule. The client boundary
-- makes the frames (client.arrow); Nav/ArrowView.lua says what each arrow
-- shows and where; Nav/ArrowLayout.lua's ArrowApply turns a drag or a
-- command into the next saved layout; Nav/ArrowMotion.lua turns and fades
-- the drawn arrow. What it saves, per account:
--   layout.arrows       (the shape is in Nav/ArrowLayout.lua)
--   layout.arrowStyle   "3d" or "flat"; nothing: the modern arrow
--   layout.arrowModern  true once the one-time move to the modern arrow ran
--
-- A guide hands its current steps in with setGuide(fn): fn() returns what
-- Nav/ViewState.lua takes ({ quest, prof, view, link }; a step may carry
-- lines = { ... } to show). With no guide the arrows have nothing to point
-- at and stay hidden. The demo is for checking
-- the frames by eye on the real client: the quest arrow points north, the
-- needle east, both from the player's real facing.
--
--   <slash> arrow demo             demo on / off
--   <slash> arrow near             demo: the quest step reached / not
--   <slash> arrow separate | stack | reset
--   <slash> arrow hide quest|prof  <slash> arrow text quest|prof   (toggles)
--   <slash> arrow modern | 3d | flat   the quest arrow's style
local _, ns = ...

local Arrow = {}
ns.Arrow = Arrow

Arrow.PATH = "layout.arrows"
Arrow.RELAYOUT = 0.25          -- seconds between layouts while shown
Arrow.LINE_HEIGHT = 14
-- With no known turn (facing or bearing unknown) an arrow still shows, but
-- faded to this share of its opacity and with this line, so a frozen
-- direction is never read as a live one.
Arrow.LOST_ALPHA = 0.35
Arrow.UNKNOWN_TURN = "direction unknown"
Arrow.DEMO = {
    questDistance = 300, nearDistance = 10, profDistance = 150,
    own = { 0.55, 0.8, 1 },    -- the needle's own colour while stacked
    questBearing = 0,          -- north
    profBearing = math.pi / 2, -- east
}

-- The setting row the saved layout is read and written through. It names
-- Arrow.PATH as its place: the layout stays where it always was.
Arrow.SETTING = "arrow.layout"

-- The kernels that refused the row, so each is asked once.
local refused = setmetatable({}, { __mode = "k" })

-- The row on kernel k, declared the first time it is asked for. nil when the
-- kernel refused it: a problem of kind "setting" says why, one problem of
-- the arrow says the layout is not kept, and that kernel is not asked again.
function Arrow.Row(k)
    local row = k.settings:row(Arrow.SETTING)
    if row or refused[k] then return row end
    row = k:Setting({
        key = Arrow.SETTING, scope = "account", type = "table", path = Arrow.PATH,
        label = "Arrow positions", group = "travel.arrow", synonyms = { "arrow", "position", "move", "stack" }, keepOnResetAll = true,
        help = "Where the arrows stand and whether they are stacked. Resetting puts them back.",
    })
    if not row then
        refused[k] = true
        k.problems:add("arrow", "row", "the layout row was refused; the layout is not kept")
    end
    return row
end

-- The quest arrow's style (Nav/ArrowStyles.lua): a setting row of its own.
-- The needle keeps its pictures in every style. Both places are authored
-- here; the mark is not a setting, it is written once.
Arrow.STYLE = "arrow.style"
Arrow.STYLE_PATH = "layout.arrowStyle"
Arrow.STYLE_MARK_PATH = "layout.arrowModern"

local styleRefused = setmetatable({}, { __mode = "k" })

-- The style row on kernel k, declared the first time it is asked for; nil
-- when the kernel refused it (asked once, one problem of the arrow).
function Arrow.StyleRow(k)
    local row = k.settings:row(Arrow.STYLE)
    if row or styleRefused[k] then return row end
    local choices = {}
    for i = 1, #ns.Nav.ARROW_STYLES do choices[i] = ns.Nav.ARROW_STYLES[i][1] end
    row = k:Setting({
        key = Arrow.STYLE, scope = "account", type = "choice", choices = choices,
        default = choices[1], path = Arrow.STYLE_PATH,
        label = "Arrow style", group = "travel.arrow", synonyms = { "arrow", "look", "style", "3d" },
        help = "How the quest arrow is drawn: the modern arrow, the 3D arrow with pillars, or flat lines.",
    })
    if not row then
        styleRefused[k] = true
        k.problems:add("arrow", "row", "the style row was refused; the style is not kept")
    end
    return row
end

-- The palette of the arrow colours (G56): a setting row of its own. It
-- picks which colours stand for the meanings (N.ARROW_PALETTES); what each
-- colour means does not change.
Arrow.PALETTE = "arrow.palette"
Arrow.PALETTE_PATH = "layout.arrowPalette"

local paletteRefused = setmetatable({}, { __mode = "k" })

-- The palette row on kernel k, declared the first time it is asked for; nil
-- when the kernel refused it (asked once, one problem of the arrow).
function Arrow.PaletteRow(k)
    local row = k.settings:row(Arrow.PALETTE)
    if row or paletteRefused[k] then return row end
    local choices = {}
    for i = 1, #ns.Nav.ARROW_PALETTES do choices[i] = ns.Nav.ARROW_PALETTES[i][1] end
    row = k:Setting({
        key = Arrow.PALETTE, scope = "account", type = "choice", choices = choices,
        default = choices[1], path = Arrow.PALETTE_PATH,
        label = "Arrow colours", group = "travel.arrow", synonyms = { "arrow", "colour", "color", "colorblind" },
        help = "The colours the arrow uses: the standard ones, or ones picked to be told apart by colour-blind players.",
    })
    if not row then
        paletteRefused[k] = true
        k.problems:add("arrow", "row", "the palette row was refused; the palette is not kept")
    end
    return row
end

-- The colours picked on kernel k: the N.ARROW_PALETTE row of the saved
-- word, the standard one for no word or a word that is no choice.
function Arrow.Palette(k)
    return ns.Nav.ArrowPaletteOf(k.store:get("account", Arrow.PALETTE_PATH),
        k.store:get("account", Arrow.BY_DISTANCE_PATH) ~= false)
end

-- N43: the arrow's colour by distance, a setting row of its own. On (the
-- default, as the predecessor's "distance" arrow colour was) the colour
-- runs far to near; off it is the palette's near colour whatever the
-- distance. Away, here and the corpse keep their colours either way.
Arrow.BY_DISTANCE = "arrow.byDistance"
Arrow.BY_DISTANCE_PATH = "layout.arrowByDistance"

local byDistanceRefused = setmetatable({}, { __mode = "k" })

-- The row on kernel k, declared the first time it is asked for; nil when
-- the kernel refused it (asked once, one problem of the arrow).
function Arrow.ByDistanceRow(k)
    local row = k.settings:row(Arrow.BY_DISTANCE)
    if row or byDistanceRefused[k] then return row end
    row = k:Setting({
        key = Arrow.BY_DISTANCE, scope = "account", type = "bool", default = true,
        path = Arrow.BY_DISTANCE_PATH,
        label = "Arrow colour by distance", group = "travel.arrow",
        synonyms = { "arrow", "colour", "color", "distance", "near", "far" },
        help = "The arrow's colour shows how far the step is: far, then nearer, then near. Off: one colour.",
    })
    if not row then
        byDistanceRefused[k] = true
        k.problems:add("arrow", "row", "the colour by distance row was refused; it is not kept")
    end
    return row
end

-- The styles for a menu, in order: { key, label, on } with `on` the one
-- named by `using`.
function Arrow.Styles(using)
    local out = {}
    for i = 1, #ns.Nav.ARROW_STYLES do
        local s = ns.Nav.ARROW_STYLES[i]
        out[i] = { key = s[1], label = s[2], on = s[1] == using }
    end
    return out
end

-- The saved layout, as ArrowView and ArrowApply take it: { arrows = ... }.
function Arrow.Saved(k)
    Arrow.Row(k)
    return { arrows = k.settings:get(Arrow.SETTING) }
end

-- The demo's arrow source: ArrowView's state plus the turns and lines.
-- near: the quest step reached. palette (optional): the N.ARROW_PALETTE row
-- the arrows are painted from; none is the standard one.
function Arrow.DemoSource(client, layout, near, palette)
    local D, N = Arrow.DEMO, ns.Nav
    local here = client.zone()
    local facing = client.facing()
    local w, h = client.screen()
    local qd = near and D.nearDistance or D.questDistance
    local questTurn = N.ArrowTurn(D.questBearing, facing)
    local profTurn = N.ArrowTurn(D.profBearing, facing)
    local qLines = { "Demo: north", ("%d yd"):format(qd) }
    if facing == nil then qLines[#qLines + 1] = "facing unknown" end
    local pLines = { "Demo: east" }
    return {
        view = {
            layout = layout, screenW = w, screenH = h, gate = "open", palette = palette,
            player = here, facingKnown = facing ~= nil,
            quest = { hasStep = true, target = here, distance = qd,
                      textHeight = #qLines * Arrow.LINE_HEIGHT },
            prof = { on = true, hasStep = true, target = here, distance = D.profDistance,
                     bearingKnown = true, own = D.own, textHeight = #pLines * Arrow.LINE_HEIGHT },
        },
        turns = { quest = questTurn, prof = profTurn },
        lines = { quest = qLines, prof = pLines },
    }
end

-- The lines each arrow shows for one view: the profession lines go under
-- the quest arrow's when its text is drawn on the quest arrow.
-- lost (optional): { quest = true, prof = true } for each arrow whose last
-- line is the unknown-direction line (GuideSource's lost). That line is left
-- out for an arrow drawn as the ring, which points nowhere, and where the
-- stack it would join already has one: once per stack of text.
-- The lines of a profession needle that is bare (off, with a step: owner
-- decision D2) are shown like those of one that is drawn.
-- -> out, kept. kept = { quest = n, prof = n }: how many of each arrow's own
-- lines are in out, wherever they are drawn; no entry for an arrow whose
-- text is not shown.
function Arrow.Lines(view, lines, lost)
    local out = { quest = {}, prof = {} }
    local said, kept = {}, {}
    local function add(key, to)
        local list = lines[key] or {}
        local n = #list
        local unknown = type(lost) == "table" and lost[key] == true
        kept[key] = 0
        for i = 1, n do
            local isUnknown = unknown and i == n
            if not (isUnknown and (view[key].mode == "ring" or said[to])) then
                out[to][#out[to] + 1] = list[i]
                kept[key] = kept[key] + 1
                if isUnknown then said[to] = true end
            end
        end
    end
    if view.quest.shown and view.quest.text.shown then add("quest", "quest") end
    local pt = view.prof.text
    if (view.prof.shown or view.prof.bare) and pt.shown then
        add("prof", pt.to == "quest" and "quest" or "prof")
    end
    return out, kept
end

-- One read of the client: nil when there is no such read or it fails.
local function ask(client, name)
    local f = client[name]
    if type(f) ~= "function" then return nil end
    local ok, v = pcall(f)
    if ok then return v end
    return nil
end

-- The step that stands in for the quest step while the gate is "corpse".
-- Never the quest step: that is not where to go.
--   client.ghost a plain false (dead, not released): no place, and the
--     lines are the label and the release hint. A corpse place the client gives is not
--     pointed at. The step is still.
--   otherwise (a ghost, or not known), by client.corpse:
--     a place: the corpse there.
--     false (the client answered: on no position of the player's map) and
--       client.ghost a plain true: no place, the lines are the label and
--       the other-map line, and the step is still.
--     false with the ghost read not known: the same as cannot tell. The
--       other-map line is not said on a read that may be of a player who
--       has not released, whose body is where they stand.
--     nil, absent, failing or no place (cannot tell): the label alone, no
--       place and not still, so the unknown-direction line is added.
-- Nothing is guessed. step.still: the step has nowhere to turn to, so no
-- unknown-direction line is added and the frame is not faded. It counts
-- only on a step with no place: a step with a place has a direction, and
-- when that is unknown it is said and the frame is faded.
local function corpseStep(client)
    local ghost = ask(client, "ghost")
    if ghost == false then
        return { label = Arrow.RELEASE_LABEL, lines = { Arrow.CORPSE_LABEL, Arrow.RELEASE_HINT }, still = true }
    end
    local step = { label = Arrow.CORPSE_LABEL, corpse = true }
    local ok, at = false, nil
    if type(client.corpse) == "function" then ok, at = pcall(client.corpse) end
    if not ok then return step end
    if type(at) == "table" and type(at.map) == "number" and type(at.x) == "number" and type(at.y) == "number" then
        local zone = ask(client, "zone")
        -- The player's continent is given on the word of the real client's
        -- c.corpse, which answers only for the player's own map (R5). A
        -- client.corpse put in its place is not held to that here.
        step.place = { cont = type(zone) == "table" and zone.cont or nil, map = at.map, x = at.x, y = at.y }
    elseif at == false and ghost == true then
        step.lines = { Arrow.CORPSE_LABEL, Arrow.CORPSE_ELSEWHERE }
        step.still = true
    end
    return step
end

-- Player-visible words. The corpse run's are Flow's (N:ShowCorpse, parity
-- row A1-14): "Your corpse" over the release hint while not released, over
-- the other-map line, over the yards, and CORPSE_HERE at the corpse.
Arrow.CORPSE_LABEL = "Your corpse"
Arrow.RELEASE_LABEL = "Release your spirit"
Arrow.RELEASE_HINT = "Release your spirit, then follow the red arrow"
Arrow.CORPSE_ELSEWHERE = "On another map: follow the graveyard path"
Arrow.CORPSE_HERE = "Here: resurrect"
-- Within N.AREA_YARDS of an area step's nearest point (parity row A1-09).
Arrow.AREA_TEXT = "You're in the area"
-- The distance line (G40): the yards, then the compass word when there is
-- one. Inside the arrival radius the line is HERE_TEXT and no distance.
Arrow.DISTANCE_TEXT = "%d yd"
Arrow.DISTANCE_COMPASS_TEXT = "%d yd %s"
Arrow.HERE_TEXT = "you're here"
-- The time to arrive (G40), after the distance: "100 yd N, about 15 sec".
-- A straight line at the speed the player moves now; standing still, at
-- Arrow.RUN_SPEED (running on foot: a first guess, not measured in game).
-- Seconds go up in fives, a minute and over in whole minutes, so the line
-- does not flicker. No speed read (nil): no time is said.
Arrow.RUN_SPEED = 7
Arrow.ETA_JOIN = "%s, %s"
Arrow.ETA_SEC = "about %d sec"
Arrow.ETA_MIN = "about %d min"

function Arrow.EtaText(distance, speed)
    if type(distance) ~= "number" or type(speed) ~= "number" then return nil end
    if distance ~= distance or speed ~= speed or distance < 0 or speed < 0 then return nil end
    if distance == math.huge or speed == math.huge then return nil end
    if speed < 1 then speed = Arrow.RUN_SPEED end
    local seconds = distance / speed
    if seconds < 60 then
        return Arrow.ETA_SEC:format(math.max(5, math.ceil(seconds / 5) * 5))
    end
    return Arrow.ETA_MIN:format(math.floor(seconds / 60 + 0.5))
end

-- The arrow source for a guide's steps: ViewState's state and turns, with
-- this install's saved layout and screen. A step's lines are its own lines,
-- else its label and its distance line: the yards and the compass word of
-- where the step lies ("100 yd N"; the word does not turn with the player),
-- or Arrow.HERE_TEXT inside the arrival radius (the step's own radius, else
-- N.AT_POINT: where the arrow becomes the ring). No distance: no such line. The gate is the guide's own, else
-- N.ArrowGate over what the client says: shut with no position, "corpse"
-- while the player is dead or a ghost (a plain true from client.dead or
-- from client.ghost; either read may be the one that answers), else open. While the gate is "corpse" the quest arrow's step is
-- the corpse.
--
-- intro (optional): { title } while the intro is playing, fed to
-- N.ArrowGate as its intro argument. While the gate it gives is "intro" the
-- quest arrow stands upright with the title as its one line. A guide's own
-- gate still wins.
-- palette (optional): the N.ARROW_PALETTE row the arrows are painted from,
-- used where the guide names none of its own.
function Arrow.GuideSource(client, layout, guide, intro, palette)
    local N = ns.Nav
    local w, h = client.screen()
    local view = {}
    for key, v in pairs(type(guide.view) == "table" and guide.view or {}) do view[key] = v end
    if view.palette == nil then view.palette = palette end
    view.layout, view.screenW, view.screenH = layout, w, h
    local given = { quest = guide.quest, prof = guide.prof, separate = guide.separate,
                    link = guide.link, view = view }
    local state, more = N.ViewState(client, given)
    local gate = state.gate
    local playing = false
    if gate == nil then
        local hasPos = state.player ~= nil and client.position() ~= nil
        gate = N.ArrowGate(true, true, type(intro) == "table", hasPos,
            ask(client, "dead") == true or ask(client, "ghost") == true)
        playing = gate == "intro"
    end
    if gate == "corpse" then
        given.quest = corpseStep(client)
        state, more = N.ViewState(client, given)
    end
    state.gate = gate
    local lines, lost, still, auto = {}, {}, {}, {}
    for _, key in ipairs(N.ARROW_KEYS) do
        local step = type(given[key]) == "table" and given[key] or {}
        local out = {}
        -- At the step (inside its arrival radius) the arrow is the ring,
        -- which points nowhere: there is no direction to call unknown.
        local d = state[key] and state[key].distance
        local arrived = type(d) == "number" and (state[key].here or N.AtPoint(d)) and true or false
        if playing and key == "quest" then
            if intro.title ~= nil then out[1] = tostring(intro.title) end
        elseif type(step.lines) == "table" then
            for i = 1, #step.lines do out[i] = tostring(step.lines[i]) end
            -- How to get there, or why there is no way (section 286).
            if step.hint ~= nil then out[#out + 1] = tostring(step.hint) end
            -- The quest's own item in words (S42, Nav/QuestItems.lua): last.
            if step.use ~= nil then out[#out + 1] = tostring(step.use) end
        else
            local label = more[key].label or step.label
            if label ~= nil then out[#out + 1] = tostring(label) end
            -- A step may say one more line of its own under its label (S43).
            if step.detail ~= nil then out[#out + 1] = tostring(step.detail) end
            -- Lead section 416 item 2: the other professions' next steps
            -- (Nav/ProfFeed.lua F.Also), one line each. Not tested in game.
            if type(step.also) == "table" then
                for i = 1, #step.also do out[#out + 1] = tostring(step.also[i]) end
            end
            -- How to get there, or why there is no way (section 286).
            if step.hint ~= nil then out[#out + 1] = tostring(step.hint) end
            -- The quest's own item in words (S42, Nav/QuestItems.lua).
            if step.use ~= nil then out[#out + 1] = tostring(step.use) end
            if type(d) == "number" then
                local word = more[key].compass
                if arrived then
                    out[#out + 1] = step.corpse and Arrow.CORPSE_HERE or Arrow.HERE_TEXT
                elseif step.area == true and d < N.AREA_YARDS then
                    out[#out + 1] = Arrow.AREA_TEXT
                else
                    local far = word ~= nil
                        and Arrow.DISTANCE_COMPASS_TEXT:format(math.floor(d + 0.5), word)
                        or Arrow.DISTANCE_TEXT:format(math.floor(d + 0.5))
                    local eta = Arrow.EtaText(d, ask(client, "speed"))
                    out[#out + 1] = eta and Arrow.ETA_JOIN:format(far, eta) or far
                end
            end
        end
        -- still is honoured only on a step with no place.
        local isStill = step.still and step.place == nil
        if type(given[key]) == "table" and more[key].turn == nil and not isStill and not arrived
            and not (playing and key == "quest") then
            out[#out + 1] = Arrow.UNKNOWN_TURN
            lost[key] = true          -- the last line is the unknown-direction line
        end
        -- A still step has nowhere to turn to: its missing turn is not "lost".
        if isStill and not (playing and key == "quest") then still[key] = true end
        lines[key] = out
        -- No height given: the height of these lines. That is a first
        -- count: Arrow.Lines may leave the unknown-direction line out, and
        -- the caller then counts again from what is kept (auto says where).
        if state[key] and state[key].textHeight == nil then
            state[key].textHeight = #out * Arrow.LINE_HEIGHT
            auto[key] = true
        end
    end
    return { view = state, turns = { quest = playing and 0 or more.quest.turn, prof = more.prof.turn },
             lines = lines, lost = lost, still = still, auto = auto, intro = playing }
end

-- The intro: the quest arrow upright with the addon's title, once, for an
-- install that has not seen it. It waits for the loading screen to end: it
-- is shown only once PLAYER_ENTERING_WORLD has been seen, and its clock
-- starts, and seen is saved, at the first frame drawn with it shown, so
-- none of it plays out unseen. Seen is a plain true saved at
-- Arrow.INTRO_PATH. Both values are authored here, not taken from the game.
-- First guess on 16001, not observed in a client: that the event is named
-- PLAYER_ENTERING_WORLD, and that no frame is drawn to this add-on under
-- the loading screen. Needs an in-game check (MR2-1).
-- Docs (warcraft.wiki.gg, Event PLAYER_ENTERING_WORLD): the name matches; it is
-- told isInitialLogin, isReloadingUi. What is drawn under the loading screen
-- is not in the docs.
Arrow.INTRO_PATH = "layout.arrowIntroSeen"
Arrow.INTRO_SECONDS = 3

-- F-new-3 (lead section 872.2): the intro's length. With the short, still
-- login intro on (UI/LoginIntro.lua: the LI.SHORT setting), the arrows'
-- intro lasts as long as that one, LI.Times(true): its show plus its fade.
-- Otherwise, or when that file or the setting cannot be read,
-- INTRO_SECONDS. Read once, when the intro's clock starts.
function Arrow.IntroSeconds(k)
    local LI = ns.LoginIntro
    if type(LI) ~= "table" or type(LI.Times) ~= "function" or type(LI.SHORT) ~= "string" then
        return Arrow.INTRO_SECONDS
    end
    local s = type(k) == "table" and k.settings
    if type(s) ~= "table" or type(s.get) ~= "function" then return Arrow.INTRO_SECONDS end
    local okS, short = pcall(s.get, s, LI.SHORT)
    if not okS or short ~= true then return Arrow.INTRO_SECONDS end
    local okT, show, tail = pcall(LI.Times, true)
    if not okT or type(show) ~= "number" or type(tail) ~= "number" then return Arrow.INTRO_SECONDS end
    local total = show + tail
    -- (Not a number, not above 0 or endless: passed over too.)
    if total ~= total or total <= 0 or total == math.huge then return Arrow.INTRO_SECONDS end
    return total
end

-- Whether the player's own quests may be the quest step (S43): the
-- setting row N.QuestSource.SETTING, on unless it says a plain false (the
-- row is the lead's to add; with no such row the answer is on).
function Arrow.QuestArrowOn(k)
    local s = type(k) == "table" and k.settings or nil
    local Q = ns.Nav and ns.Nav.QuestSource
    if type(s) ~= "table" or type(s.get) ~= "function" or not Q then return true end
    local ok, v = pcall(s.get, s, Q.SETTING)
    return not (ok and v == false)
end

-- Lead section 294 item 5: with no quest step the quest arrow stays up and
-- says why in one line, unless the player hid it or turned the quest arrow
-- setting off (those choices are read, never written). NO_QUEST: the quest
-- log has no quest in it, or it is not known. NO_ROUTE: the log has quests
-- and none gives a step (no objective left to go to and not complete).
-- NO_DIRECTIONS over INSTALL_QUESTIE: the log has quests and Questie's
-- QuestieDB is not there (Arrow.HasQuestie).
Arrow.NO_QUEST = "No quest tracked"
Arrow.NO_ROUTE = "No route known to this objective"
-- Quests in the log and no places read for them (Questie not there or not
-- ready): Flow's pair (parity row A1-16).
Arrow.NO_DIRECTIONS = "No directions yet"
Arrow.INSTALL_QUESTIE = "Install Questie + QuestieDB for quest locations"

-- Whether the client gives Questie's QuestieDB module (client.questieModule).
-- A failing or absent read is no.
function Arrow.HasQuestie(k)
    local c = type(k) == "table" and k.client or nil
    if type(c) ~= "table" or type(c.questieModule) ~= "function" then return false end
    local ok, m = pcall(c.questieModule, "QuestieDB")
    return ok and m ~= nil
end

-- Parity row A1-28 (lead section 794): Hide this step on a route step also
-- keeps that quest step off the next route, saved per character by
-- Nav/HiddenSteps.lua. Without that file it does nothing, and Hide this step
-- only skips, as before. Answers whether the step was kept hidden.
function Arrow.KeepHidden(step, store)
    local HS = ns.Nav and ns.Nav.HiddenSteps
    if type(HS) ~= "table" or type(HS.Hide) ~= "function" or type(HS.KeyOf) ~= "function" then return false end
    if type(step) ~= "table" then return false end
    local okKey, key = pcall(HS.KeyOf, step)
    if not okKey or key == nil then return false end
    local ok, done = pcall(HS.Hide, store, key, step.label)
    return ok and done == true
end

-- Parity row A2-12 (lead section 794): a quest step with no place (words
-- only, Nav/QuestSource.lua rule 3) also says which creatures dropped the
-- thing it needs, from the player's own loot record, through
-- Nav/DropLines.lua. Without that file, or with nothing recorded, the step is
-- as before. book: the character's learned.drops; nameOf(item key) -> the
-- item's plain name. Answers the step, or a copy with the lines added.
function Arrow.DropWords(step, book, nameOf)
    local DL = ns.Nav and ns.Nav.DropLines
    if type(DL) ~= "table" or type(DL.Rows) ~= "function" or type(DL.Lines) ~= "function" then return step end
    if type(step) ~= "table" or step.quest == nil or step.still ~= true or step.place ~= nil then return step end
    if type(step.lines) ~= "table" or type(step.detail) ~= "string" then return step end
    -- The objective names the thing: "Stringy Wolf Meat: 0/6".
    local item = step.detail:match("^%s*(.-)%s*:%s*%d+%s*/%s*%d+%s*$")
    if item == nil or item == "" then return step end
    local ok, lines = pcall(function() return DL.Lines(DL.Rows(book, item, nameOf)) end)
    if not ok or type(lines) ~= "table" or #lines == 0 then return step end
    local copy = {}
    for key, v in pairs(step) do copy[key] = v end
    copy.lines = {}
    for i = 1, #step.lines do copy.lines[i] = step.lines[i] end
    for i = 1, #lines do copy.lines[#copy.lines + 1] = tostring(lines[i]) end
    return copy
end

-- The why step for the quest arrow, or nil when the player chose not to see
-- it. quests: the N.QuestWatch the step was asked of (nil: not loaded).
function Arrow.WhyStep(k, quests, prof)
    if not Arrow.QuestArrowOn(k) then return nil end
    local N = ns.Nav
    local okSaved, saved = pcall(N.ArrowSaved, Arrow.Saved(k))
    if not okSaved or type(saved) ~= "table" then return nil end
    if type(saved.hidden) == "table" and saved.hidden.quest == true then return nil end
    -- Stacked, a profession step takes the stack's place (Nav/ArrowLayout.lua)
    -- and the stack is not silent: the why line would push it under. Apart,
    -- the quest arrow has its own frame and says why.
    if prof ~= nil and saved.mode ~= "separate" then return nil end
    local rows
    if type(quests) == "table" and type(quests.state) == "function" then
        local okState, st = pcall(quests.state)
        if okState and type(st) == "table" then rows = st.rows end
    end
    if type(rows) == "number" and rows > 0 and not Arrow.HasQuestie(k) then
        return { still = true, lines = { Arrow.NO_DIRECTIONS, Arrow.INSTALL_QUESTIE }, why = true }
    end
    local text = (type(rows) == "number" and rows > 0) and Arrow.NO_ROUTE or Arrow.NO_QUEST
    return { still = true, lines = { text }, why = true }
end

-- Whether what is left on this map comes before the quest log order (lead
-- section 187): the setting row ns.Nav.LEAVING_SETTING, on unless it says
-- a plain false.
function Arrow.ZoneFirstOn(k)
    local s = type(k) == "table" and k.settings or nil
    local key = ns.Nav and ns.Nav.LEAVING_SETTING
    if type(s) ~= "table" or type(s.get) ~= "function" or key == nil then return true end
    local ok, v = pcall(s.get, s, key)
    return not (ok and v == false)
end

-- The name the arrows are declared under as a module.
Arrow.NAME = "arrow"

-- Starts the arrows on kernel k; diag (optional) gains the word "arrow".
-- Returns { handles = { quest, prof } or nil, relayout = fn, state = fn,
--           setGuide = fn(fn or nil) }.
-- own (optional) is who registers for the arrows; Arrow.Declare gives the
-- module's. { listen = fn(event, fn), frame = fn(fn) -> cancel,
-- live = fn() -> false once the arrows are switched off, loaded = true when
-- the login is already under way, script = fn(label, fn) -> fn: what a frame
-- script runs of the arrows, run as the owner's work, off = fn(err):
-- a frame error, for the owner to switch the arrows off (it calls stop) }.
-- Whether the arrows are off is the owner's to say, through live: they keep
-- no flag of their own beside it. Without an owner the arrows register with
-- the client themselves, wait for the login, and a frame error stops them
-- for the session.
function Arrow.Start(k, diag, own)
    local client, id, N, M = k.client, k.id, ns.Nav, ns.ArrowMenu
    own = type(own) == "table" and own or {}
    local listen = own.listen or client.listen
    local onFrame = own.frame or client.onFrame
    -- Only arrows without an owner stop themselves; with one, live is the
    -- owner's answer and nothing here is kept beside it.
    local stopped = false
    local live = own.live or function() return not stopped end
    local script = own.script or function(_, fn) return fn end
    local spec = function(name, level)
        return { name = id.framePrefix .. name, size = N.ARROW_SIZE, art = N.ARROW_ART,
                 artPath = "Interface\\AddOns\\" .. id.addon .. "\\Art\\",
                 needle = { N.NEEDLE_W, N.NEEDLE_H }, level = level,
                 halo = { N.HALO_W, N.HALO_H, N.HALO_Y }, beam = { N.BEAM_W, N.BEAM_H },
                 beamUp = { N.BeamCoords(false) }, beamDown = { N.BeamCoords(true) } }
    end
    local quest = client.arrow(spec("QuestArrow", 6))
    local prof = quest and client.arrow(spec("ProfArrow", 6)) or nil
    local handles = (quest and prof) and { quest = quest, prof = prof } or nil
    local motion = { quest = N.ArrowMotion(), prof = N.ArrowMotion() }
    local ready, demo, near = false, false, false
    -- drawn: the style the quest arrow is drawn in, read again at each
    -- layout. shaped: its handle holds lines. moved: the one-time move to
    -- the modern arrow was looked at.
    local drawn, shaped, moved = "modern", false, false
    -- B-13, B-14: the world map switches' menu rows (Nav/MapToggles.lua),
    -- or none.
    local function mapRows()
        local MT = k.use and k.use("mapToggles")
        if type(MT) ~= "table" or type(MT.MenuItems) ~= "function" then return {} end
        local ok, rows = pcall(MT.MenuItems)
        if ok and type(rows) == "table" then return rows end
        return {}
    end
    local function canShapes()
        local q = handles and handles.quest
        return q ~= nil and type(q.shapes) == "function"
            and type(q.canShapes) == "function" and q.canShapes() == true
    end
    -- The style in use: the saved one where this client can draw it.
    local function style()
        if not ready or not canShapes() then return "modern" end
        return N.ArrowStyle(k.store:get("account", Arrow.STYLE_PATH))
    end
    local current, cancelTick, since = nil, nil, 0
    -- shownLines: each arrow's lines as the source gave them at the last
    -- layout, for the tooltip. drawer: what a left click opens, when set.
    local shownLines, drawer = nil, nil
    local stop
    local guideFn = nil
    -- The player's own quests (S43, Nav/QuestRead.lua): the quest step when
    -- there is no waypoint. Read-only; nil when that file is not loaded.
    local quests = N.QuestWatch and N.QuestSource
        and N.QuestWatch(client, { zoneFirst = function() return Arrow.ZoneFirstOn(k) end,
            -- A1-24: the route planned by itself, from this kernel's own
            -- trip route module (lead item 28), not a file-wide one.
            trip = function()
                if not k.use then return nil end
                return k.use("tripRoute")
            end,
            -- S43: the spots this player learned, where Questie gives none.
            learned = function()
                local QS = N.QuestSpots
                return QS and k.store:get("account", QS.PATH) or nil
            end }) or nil
    -- introWanted: this install has not seen the intro and it has not ended.
    -- entered: the world has been entered. introShown: the last layout had
    -- the intro on the quest arrow. introUntil: when it ends, nil until the
    -- first frame with it shown.
    local introAsked, introWanted, entered, introShown, introUntil = false, false, false, false, nil

    -- { title } while the intro is waiting for its first frame or playing,
    -- else nil. Once started it ends by the clock.
    local function intro()
        if not introWanted or not entered then return nil end
        if introUntil == nil then return { title = id.title } end
        local now = client.now()
        if type(now) ~= "number" or now >= introUntil then
            introWanted = false
            return nil
        end
        return { title = id.title }
    end

    -- The demo, else the guide that was set, else the player's own map
    -- waypoint as the quest step together with the profession step this
    -- player's saved readings give (Nav/ProfStep.lua; none: the needle is
    -- off). The two are handed in as one guide, so the profession step
    -- never takes the waypoint's place. A guide that was set wins whole,
    -- even when it answers nothing: nothing is added to it. The intro
    -- plays over whichever it is.
    -- The player's own waypoint (G35, Nav/Waypoint.lua) is the quest step
    -- while it is set: it wins over the pin on the game's map. It is only
    -- read here: looking makes no saved table. mine: the quest step of the
    -- last source was the player's own waypoint.
    local W = N.Waypoint
    local mine = false
    -- from: where the quest step of the last source came from, for the
    -- arrow's own report (arrow why).
    local from = "not asked yet"
    -- stepName: the label of the quest arrow's step in the last source, or
    -- nil (none, the demo, or the words-only why line). The menu's first
    -- row (UI/ArrowMenu.lua M.StepRow, lead section 387 R3).
    local stepName = nil
    -- heading: the place of the quest arrow's step in the last source, as
    -- { cont, map, x, y }, or nil (none, the demo, or a step with no map
    -- place). Heading() gives a copy (lead section 169 B: Nav/Legs.lua
    -- reads it to know which step the player is going to).
    local heading = nil
    -- family: the family of the quest arrow's step in the last source
    -- ("waypoint" or "profession", else nil), by the ViewState rule
    -- (Nav/ViewState.lua:89-92): qs.family, else qs.kind. Family() gives
    -- it (R7, lead section 570: the map lines read it to colour the
    -- first leg the same as the arrow).
    local family = nil
    -- saying: the quest step of the last source is the why line (lead
    -- section 294 item 5): words only, no needle drawn.
    local saying = false
    local function placeOf(step)
        local p = type(step) == "table" and step.place or nil
        if type(p) ~= "table" or p.map == nil or type(p.x) ~= "number" or type(p.y) ~= "number" then return nil end
        if p.x ~= p.x or p.y ~= p.y then return nil end
        return { cont = p.cont, map = p.map, x = p.x, y = p.y }
    end
    local function source()
        mine = false
        saying = false
        from = "demo"
        heading = nil
        family = nil
        if demo then return Arrow.DemoSource(client, Arrow.Saved(k), near, Arrow.Palette(k)) end
        local playing = intro()
        local guide
        if guideFn then
            guide = guideFn()
            from = "a guide"
        else
            -- A travel preview (Nav/Try.lua, <slash> try) wins over every
            -- step of the player's own while it is on. It is not the
            -- player's waypoint: reaching it clears nothing.
            local step
            local preview = k.use and k.use("try")
            if preview and type(preview.Step) == "function" then
                local okPreview, s = pcall(preview.Step)
                if okPreview and type(s) == "table" then step = s end
            end
            -- Then the party member the player chose to point at (G47,
            -- Nav/Follow.lua): only while their position is known.
            local followed = false
            local follow = step == nil and k.use and k.use("follow") or nil
            if follow and type(follow.Step) == "function" then
                local okFollow, f = pcall(follow.Step)
                if okFollow and type(f) == "table" then
                    step = f
                    followed = true
                end
            end
            if followed then
                from = "a party member you point at"
            elseif step then
                from = N.Try and N.Try.FROM or "a preview"
            else
                step = W and W.Step(k.store:get(W.SCOPE, W.PATH), ask(client, "position"), ask(client, "zone"))
                from = "nothing"
                if step then
                    mine, from = true, "your own waypoint"
                    -- One picked on another map (Alt + click on the world
                    -- map, a pasted map number): that map's own continent,
                    -- where the client says it.
                    local to = step.place
                    if to.cont == nil and type(client.mapCont) == "function" then
                        local okC, cont = pcall(client.mapCont, to.map)
                        if okC and type(cont) == "number" then to.cont = cont end
                    end
                else
                    step = N.WaypointStep(client)
                    if step then from = "the map pin" end
                end
            end
            -- Then the route the player planned (P-TRIP, Nav/TripRoute.lua):
            -- the quest route of the route word, or a dungeon run from the
            -- Dungeon Quests window. Waypoints only.
            local trip = k.use and k.use("tripRoute")
            if step == nil and trip and type(trip.Step) == "function" then
                local okTrip, s = pcall(trip.Step)
                if okTrip and type(s) == "table" then
                    step = s
                    from = "your route"
                end
            end
            -- Then the errand stop the player asked for (Nav/Errand.lua), when there is one.
            local errand = k.use and k.use("errand")
            if step == nil and errand and errand.Step then
                step = errand.Step()
                if step then from = "an errand stop" end
            end
            -- Then the repair stop (Nav/RepairStep.lua), while the gear is low and a
            -- repair vendor is known. Look only: it points, it never repairs.
            local repair = k.use and k.use("repairStep")
            if step == nil and repair and repair.Step then
                step = repair.Step()
                if step then from = "a repair stop" end
            end
            -- Then the inn to set the hearthstone at (B-34, Nav/HearthAdvice.lua),
            -- after the planned route, errand and repair (lead section 466): a spoken-to innkeeper only. Points only.
            local hearth = k.use and k.use("hearthAdvice")
            if step == nil and hearth and type(hearth.Step) == "function" then
                local okH, hs = pcall(hearth.Step)
                if okH and type(hs) == "table" and type(hs.place) == "table" then
                    step = hs
                    from = "a hearthstone to set"
                end
            end
            -- Then the weapon master stop (G16, Nav/WeaponMasterStep.lua), only
            -- when a weapon master is saved: a words-only step has no needle.
            local weaponMaster = k.use and k.use("weaponMasterStep")
            if step == nil and weaponMaster and weaponMaster.Step then
                local ok, wm = pcall(weaponMaster.Step)
                if ok and type(wm) == "table" and type(wm.place) == "table" then
                    step = wm
                    from = "a weapon master stop"
                end
            end
            -- Then the profession trainer stop the player put on the route
            -- (G17, UI/ProfPick.lua), only when its trainer is saved.
            local profPick = k.use and k.use("profPick")
            if step == nil and profPick and profPick.Step then
                local ok, pp = pcall(profPick.Step)
                if ok and type(pp) == "table" and type(pp.place) == "table" then
                    step = pp
                    from = "a profession trainer stop"
                end
            end
            -- Then the riding trainer stop (G45, Nav/RidingStep.lua), only when
            -- a riding trainer is saved on this map: words only have no needle.
            local riding = k.use and k.use("ridingStep")
            if step == nil and riding and riding.Step then
                local ok, rs = pcall(riding.Step)
                if ok and type(rs) == "table" and type(rs.place) == "table" then
                    step = rs
                    from = "a riding trainer stop"
                end
            end
            -- Then the class trainer stop (G44, Nav/ClassTrainerStep.lua): new
            -- class spells at the level and a class trainer saved on this map.
            local classTrainer = k.use and k.use("classTrainerStep")
            if step == nil and classTrainer and classTrainer.Step then
                local ok, ct = pcall(classTrainer.Step)
                if ok and type(ct) == "table" and type(ct.place) == "table" then
                    step = ct
                    from = "a class trainer stop"
                end
            end
            -- Then a flight path to learn (S30, Nav/FlightStep.lua), only while
            -- its master is a short detour away. Look only: it points.
            local flightStep = k.use and k.use("flightStep")
            if step == nil and flightStep and flightStep.Step then
                local ok, fs = pcall(flightStep.Step)
                if ok and type(fs) == "table" and type(fs.place) == "table" then
                    step = fs
                    from = "a flight path to learn"
                end
            end
            -- The player's own pin (/way, then the map pin) wins over the player's quests.
            if step == nil and quests and Arrow.QuestArrowOn(k) then
                step = quests.step()
                if step then from = "your quests" end
            end
            -- The quest's own item, named under the objective (S42,
            -- Nav/QuestItems.lua): "Use <item> (in your bags)". Words only:
            -- nothing here uses the item.
            local questItems = k.use and k.use("questItems")
            if step ~= nil and from == "your quests" and questItems and type(questItems.With) == "function" then
                local ok, with = pcall(questItems.With, step)
                if ok and type(with) == "table" then step = with end
            end
            -- A2-25 (Nav/MobHopStep.lua): a kill step points at the mob group being worked, then the next.
            local mobHop = k.use and k.use("mobHopStep")
            if step ~= nil and from == "your quests" and mobHop and type(mobHop.Refine) == "function" then
                local okHop, hopped = pcall(mobHop.Refine, step)
                if okHop and type(hopped) == "table" then step = hopped end
            end
            -- A target past a path the player walked into a cave (G38,
            -- Nav/Trails.lua) is pointed at along that path, one point at a
            -- time. Reaching a trail point clears no waypoint.
            local trails = k.use and k.use("trails")
            if step ~= nil and not followed and trails and type(trails.Refine) == "function" then
                local okTrail, refined = pcall(trails.Refine, step)
                if okTrail and type(refined) == "table" and refined ~= step then
                    -- (A step that only gained the cave line is still the waypoint.)
                    if refined.trail then
                        mine = false
                        from = from .. ", along a trail you walked"
                    end
                    step = refined
                end
            end
            -- The way there, when it is a cast, the hearthstone, a ride or a
            -- gate (Nav/Travel.lua, S33 + S35): that takes the step's place
            -- and the step is said next. A step it puts in is not the
            -- player's own waypoint: reaching a gate clears nothing.
            local travel = k.use and k.use("travel")
            if step ~= nil and travel and type(travel.Via) == "function" then
                local ok, via = pcall(travel.Via, step)
                if ok and type(via) == "table" and via ~= step then
                    step = via
                    -- (A step that only gained a line is still the waypoint.)
                    if via.via ~= nil then
                        mine = false
                        from = from .. ", by way of travel"
                    end
                end
            end
            -- The profession step (Nav/ProfStep.lua), behind its module:
            -- with nav.profArrow off it gives none.
            local profStep = k.use and k.use(N.PROF_STEP)
            local prof = nil
            if profStep and type(profStep.Step) == "function" then
                local okProf, got = pcall(profStep.Step)
                if okProf then prof = got end
            end
            -- No quest step: the quest arrow says why (lead section 294 item 5),
            -- once the world is entered (nothing is shown under the loading
            -- screen).
            if step == nil and entered then
                local okWhy, why = pcall(Arrow.WhyStep, k, quests, prof)
                if okWhy and why then
                    step = why
                    saying = true
                end
            end
            guide = (step or prof) and { quest = step, prof = prof } or nil
        end
        if type(guide) ~= "table" then
            if not playing then return nil end
            guide = {}
        end
        -- A2-12: a words-only quest step gets the drop lines; never the why line.
        if not saying and type(guide.quest) == "table" and guide.quest.still == true then
            local path = "learned.drops"
            if ns.Drops and ns.Drops.PATH then path = ns.Drops.PATH end
            local okBook, book = pcall(k.store.get, k.store, "char", path)
            local names
            if ns.ItemPresent and type(client) == "table" then names = ns.ItemPresent.Names(client.itemInfo) end
            local function plainName(key)
                if not names then return nil end
                return ns.ItemPresent.Plain(names(key))
            end
            if okBook and type(book) == "table" then
                local worded = Arrow.DropWords(guide.quest, book, plainName)
                if worded ~= guide.quest then
                    -- A copy: the guide handed in (a preview, a test's) is not changed.
                    local copy = {}
                    for key, v in pairs(guide) do copy[key] = v end
                    copy.quest = worded
                    guide = copy
                end
            end
        end
        heading = placeOf(guide.quest)
        -- R7: the step's family, by the ViewState rule (qs.family, else
        -- qs.kind), kept with the heading and cleared with it.
        local qs = guide.quest
        if type(qs) == "table" and type(qs.family) == "string" then family = qs.family
        elseif type(qs) == "table" and type(qs.kind) == "string" then family = qs.kind
        else family = nil end
        stepName = nil
        if not saying and type(guide.quest) == "table" and type(guide.quest.label) == "string" then
            stepName = guide.quest.label
        end
        return Arrow.GuideSource(client, Arrow.Saved(k), guide, playing, Arrow.Palette(k))
    end

    local function hideAll()
        if not handles then return end
        handles.quest.show(false)
        handles.prof.show(false)
    end

    -- Which frames are up: an arrow that is shown, or a bare one (D2) that
    -- has lines of its own to show.
    local up = { quest = false, prof = false }

    -- A fresh layout: what is shown, where, at what scale and opacity.
    local function relayout()
        if not handles or not ready then return end
        introShown = false
        drawn = style()
        -- A frame error stops the arrows for the session, and so does the
        -- kernel switching them off: nothing here, a loading screen or a
        -- command, shows them again.
        if not live() then
            current = nil
            hideAll()
            return
        end
        -- G55 (UI/Reveal.lua): a new player's arrow waits for its stage.
        -- No reveal module, or any doubt: shown.
        if type(ns.Reveal) == "table" and type(ns.Reveal.Open) == "function" and ns.Reveal.Open(k, "arrow") == false then
            current = nil
            hideAll()
            return
        end
        local src = source()
        -- Arrival at the player's own waypoint: it is cleared, that is said
        -- once, and the layout is made from what is left. Not while the
        -- corpse stands in for the quest step: that distance is not the
        -- waypoint's. A distance that is not known clears nothing.
        if src and mine and type(src.view) == "table" and src.view.gate ~= "corpse"
            and type(src.view.quest) == "table"
            and W.Arrive(k.store:get(W.SCOPE, W.PATH), src.view.quest.distance) == W.ARRIVED then
            client.print(id.title .. ": waypoint reached.")
            src = source()
        end
        if not src then
            current = nil
            hideAll()
            return
        end
        local view = N.ArrowView(src.view)
        local lines, kept = Arrow.Lines(view, src.lines, src.lost)
        -- A height the source counted itself is counted again from the
        -- lines kept: a dropped line takes no room, so the text side is
        -- chosen for what is shown. Which lines are kept does not depend on
        -- the height, so once is enough.
        local refit = false
        for _, key in ipairs(N.ARROW_KEYS) do
            local need = kept[key] and kept[key] * Arrow.LINE_HEIGHT
            if type(src.auto) == "table" and src.auto[key] and need and type(src.view[key]) == "table"
                and src.view[key].textHeight ~= need then
                src.view[key].textHeight = need
                refit = true
            end
        end
        if refit then
            view = N.ArrowView(src.view)
            lines = Arrow.Lines(view, src.lines, src.lost)
        end
        -- FLOW-PARITY B-40: the party route line under the quest arrow's
        -- lines (Nav/PartyRoute.lua). It says only; nothing is sent.
        local party = k.use and k.use("partyRoute")
        if type(party) == "table" and type(party.Line) == "function" and type(lines.quest) == "table"
            and #lines.quest > 0 then
            local okLine, line = pcall(party.Line)
            if okLine and type(line) == "string" then lines.quest[#lines.quest + 1] = line end
        end
        for _, key in ipairs(N.ARROW_KEYS) do
            local ops, h = view[key], handles[key]
            -- A bare needle keeps its frame for its text when the lines are
            -- its own (stacked, that is when they stand opposite the quest
            -- lines); when they are in the quest arrow's stack no second
            -- frame is put up.
            local shown = (ops.shown or (ops.bare and #lines[key] > 0)) and true or false
            up[key] = shown
            h.show(shown)
            if shown then
                h.look(ops.look)
                -- An arrow the player is dragging is left where the hand has it.
                local held = type(h.dragging) == "function" and h.dragging() == true
                if not held then
                    if ops.anchor == "quest" then h.attach(handles.quest) else h.place(ops.point) end
                end
                h.scale(ops.scale)
                -- Faded means only "direction unknown". The ring points
                -- nowhere and a still step has nowhere to turn to: neither
                -- is faded.
                local lost = src.turns[key] == nil and ops.mode ~= "ring"
                    and not (type(src.still) == "table" and src.still[key])
                h.alpha(lost and type(ops.alpha) == "number" and ops.alpha * Arrow.LOST_ALPHA or ops.alpha)
                h.behind(ops.behind)
                local textPoint = ops.text.point
                if key == "quest" and (view.prof.shown or view.prof.bare) and view.prof.text.shown
                    and view.prof.text.to == "quest" then
                    textPoint = view.prof.text.point   -- one stack of lines: the stack's gap
                end
                h.text(lines[key], textPoint)
                -- Direction unknown, or a needle that is off: the art is
                -- not drawn (D2). The faded frame and the text stay.
                N.ArrowAim(motion[key], { turn = src.turns[key], colour = ops.colour,
                                          arrived = ops.mode == "ring",
                                          bare = (lost or ops.bare or (key == "quest" and saying)) and true or false })
            else
                -- A frame taken down says nothing: its last lines do not
                -- stay on it (the needle's own lines, with the profession
                -- arrow turned off during play).
                h.text(nil)
            end
        end
        current = view
        shownLines = src.lines
        introShown = src.intro == true and view.quest.shown == true
    end

    -- The first frame drawn with the intro shown: its clock starts and it is
    -- saved as seen. Without a clock it is dropped, and not saved.
    local function startIntro()
        local now = client.now()
        if type(now) ~= "number" then
            introWanted = false
            relayout()
            return
        end
        introUntil = now + Arrow.IntroSeconds(k)
        local ok, reason = k.store:set("account", Arrow.INTRO_PATH, true)
        if not ok then k.problems:add("arrow", "save", reason) end
    end

    -- One frame's work. A function of its own, made once: frame() makes
    -- none per frame.
    local function step(elapsed)
        if introWanted and introShown and introUntil == nil then startIntro() end
        since = since + (tonumber(elapsed) or 0)
        if since >= Arrow.RELAYOUT then
            since = 0
            relayout()
        end
        if not current then return end
        local now = client.now()
        for _, key in ipairs(N.ARROW_KEYS) do
            if up[key] then
                local h = handles[key]
                if key == "quest" and drawn ~= "modern" then
                    shaped = true
                    h.shapes(N.ArrowShapes(drawn, motion[key], elapsed, now))
                else
                    if key == "quest" and shaped then
                        shaped = false
                        h.shapes(nil)
                    end
                    h.draw(N.ArrowStep(motion[key], elapsed, now))
                end
            end
        end
    end

    local function frame(elapsed)
        if not live() then return end
        local ok, err = pcall(step, elapsed)
        if not ok then
            -- A broken arrow is taken off the screen, not left frozen on it.
            current = nil
            pcall(hideAll)
            k.problems:add("arrow", "frame", err)
            -- The owner switches the arrows off, and its switch is what
            -- stops them. Without an owner they stop themselves.
            if own.off then
                own.off(err)
            else
                stopped = true
                stop()
            end
        end
    end

    local function tick(on)
        if on and not cancelTick then
            cancelTick = onFrame(frame)
        elseif not on and cancelTick then
            cancelTick()
            cancelTick = nil
        end
    end

    local function write(layout)
        Arrow.Row(k)
        local ok, reason = k.settings:set(Arrow.SETTING, layout.arrows)
        if not ok then k.problems:add("arrow", "save", reason) end
        return ok
    end

    local function ctx()
        local w, h = client.screen()
        return { screenW = w, screenH = h, size = N.ARROW_SIZE, snap = N.STACK_SNAP }
    end

    local function act(action)
        local ok = write(N.ArrowApply(Arrow.Saved(k), action, ctx()))
        relayout()
        return ok
    end

    local function apply()
        if not introAsked then
            introAsked = true
            introWanted = k.store:get("account", Arrow.INTRO_PATH) ~= true
        end
        ready = true
        if not moved then
            -- Once per install: a "3d" saved before the modern arrow was the
            -- default of its day, not a choice.
            moved = true
            local was = k.store:get("account", Arrow.STYLE_PATH)
            local now, mark = N.ArrowStyleMigrate(was, k.store:get("account", Arrow.STYLE_MARK_PATH))
            if mark then
                local ok, reason = true, nil
                if was ~= nil and now ~= N.ArrowStyle(was) then
                    ok, reason = k.store:set("account", Arrow.STYLE_PATH, nil)
                end
                if ok then ok, reason = k.store:set("account", Arrow.STYLE_MARK_PATH, true) end
                if not ok then k.problems:add("arrow", "save", reason) end
            end
        end
        relayout()
        tick(true)
    end
    -- The loading screen is over, or about to be: the intro may show.
    local function enterWorld()
        entered = true
        apply()
    end

    -- Under an owner an error in a handler is the owner's to count: the
    -- arrows are taken off the screen first, not left frozen on it, and the
    -- error goes on to the owner.
    local function guarded(fn)
        if not own.listen then return fn end
        return function(...)
            local ok, err = pcall(fn, ...)
            if not ok then
                current = nil
                pcall(hideAll)
                error(err, 0)
            end
        end
    end

    local function say(text) client.print(id.title .. ": " .. text) end
    local setStyle

    -- What the menu and the tooltip are made from (UI/ArrowMenu.lua).
    local function menuState()
        local saved = N.ArrowSaved(Arrow.Saved(k))
        local Feedback = ns.Feedback
        local feedback = type(Feedback) == "table" and k.use(Feedback.NAME) ~= nil
        -- G47: the party members the follow row offers (Nav/Follow.lua).
        local follow = k.use and k.use("follow")
        local party
        if follow and type(follow.Members) == "function" then
            local okParty, list = pcall(follow.Members)
            if okParty and type(list) == "table" then party = list end
        end
        -- Lead section 382: the Professions tick (Nav/ProfFeed.lua's setting).
        local professions
        local okProf, profOn = pcall(k.settings.get, k.settings, N.ProfFeed and N.ProfFeed.SETTING or "nav.professions")
        if okProf then professions = profOn end
        -- Lead section 387, R3: the step, the kinds with a place known
        -- (Nav/Errand.lua E.Find), and the waypoint. Lead section 628: asked
        -- with the module lookup, as the errand click asks, so a live row is
        -- one the click can follow and a greyed row one it could not.
        local nearest = {}
        local E = ns.Errand
        if type(E) == "table" and type(E.Find) == "function" and type(M.NEAREST_KINDS) == "table" then
            for _, n in ipairs(M.NEAREST_KINDS) do
                local okFind, place = pcall(E.Find, n.kind, client, k.store, k.use)
                if okFind and type(place) == "table" then nearest[n.kind] = true end
            end
        end
        -- Parity B-30: the step's shortcut, for the walk row.
        local travel
        local tr = k.use and k.use("travel")
        if type(tr) == "table" and type(tr.State) == "function" then
            local okTravel, st = pcall(tr.State)
            if okTravel then travel = st end
        end
        local waypoint = false
        if W and W.Get(k.store:get(W.SCOPE, W.PATH)) then waypoint = true end
        if not waypoint and N.WaypointStep and N.WaypointStep(client) then waypoint = true end
        return { stacked = saved.mode ~= "separate", hidden = saved.hidden, text = saved.text,
                 styles = Arrow.Styles(style()), canShapes = canShapes(), feedback = feedback,
                 party = party, step = { name = stepName, from = from, open = drawer ~= nil },
                 nearest = nearest, waypoint = waypoint, professions = professions,
                 travel = travel, mapToggles = mapRows() }
    end
    -- The tooltip's lines for one arrow, or nil when none is on the screen.
    -- The lines are the step's own, also for an arrow whose text is off.
    local function tip(key)
        if not handles or not ready or not live() or not current then return nil end
        -- P-TRIP slice 2: the planned route's stops (Nav/Trip.lua), on the
        -- quest arrow's tooltip.
        local route
        local trip = key == "quest" and k.use and k.use("trip") or nil
        if trip and type(trip.Tip) == "function" then
            local okTrip, lines = pcall(trip.Tip)
            if okTrip and type(lines) == "table" then route = lines end
        end
        -- R-09 (section 835): arrived, the other route steps in the area
        -- (Nav/AlsoHere.lua), as Flow's hover did (Nav.lua:4385-4405).
        -- Arrived is the quest arrow drawn as the ring (Nav/ArrowView.lua).
        local here
        local also
        if key == "quest" and type(current.quest) == "table" and current.quest.mode == "ring" and k.use then
            also = k.use("alsoHere")
        end
        if type(also) == "table" and type(also.Lines) == "function" then
            local okHere, found = pcall(also.Lines)
            if okHere and type(found) == "table" then here = found end
        end
        return M.Tip({ key = key, stacked = current.prof.behind == true,
                       both = current.quest.shown == true and current.prof.shown == true,
                       drawer = drawer ~= nil, lines = shownLines, route = route, here = here })
    end
    -- Lead section 387 R3: the trip list, the stops the arrow walks and the
    -- Suggest dungeons switch, for the menu's Route level. Read only.
    local function routeState()
        local out = {}
        local trip, walk = k.use and k.use("trip"), k.use and k.use("tripRoute")
        if type(trip) == "table" and type(trip.List) == "function" then
            local ok, list = pcall(trip.List)
            if ok and type(list) == "table" then out.all = list end
        end
        if type(walk) == "table" and type(walk.Current) == "function" then
            local ok, current = pcall(walk.Current)
            if ok and type(current) == "table" and type(current.stops) == "table" then out.on = current.stops end
        end
        if k.settings and k.settings:row(M.SUGGEST_SETTING) then out.suggest = k.settings:get(M.SUGGEST_SETTING) == true end
        return out
    end
    -- The menu's state with the route added (kept apart from menuState so
    -- each hunk stays small).
    local baseState = menuState
    menuState = function()
        local st = baseState()
        st.route = routeState()
        return st
    end
    -- Lead section 387 R3: the Buttons level (UI/WindowButtons.lua's
    -- windows and their settings) and the Flow windows that are ready.
    -- Read only.
    local withRoute = menuState
    menuState = function()
        local st = withRoute()
        local buttons, windows = {}, {}
        local WB = ns.WindowButtons
        for _, win in ipairs(type(WB) == "table" and type(WB.WINDOWS) == "table" and WB.WINDOWS or {}) do
            if type(win) == "table" and type(win.key) == "string" and type(win.setting) == "string" then
                local there = k.settings ~= nil and k.settings:row(win.setting) ~= nil
                buttons[#buttons + 1] = { key = win.key, text = win.label, setting = win.setting,
                    there = there, on = there and k.settings:get(win.setting) == true }
            end
        end
        for _, w in ipairs(M.FLOW_WINDOWS or {}) do
            local mod
            if k.use then mod = k.use(w.name) end
            if type(mod) == "table" and type(mod[w.open]) == "function" then windows[w.name] = true end
        end
        st.buttons, st.windows = buttons, windows
        return st
    end
    -- The menu row with this key was clicked. A row that is not there or
    -- not offered asks for nothing.
    -- The menu is shown one level at a time (UI/ArrowMenu.lua, N57): a row
    -- that opens a level shows it on the same arrow, and a row that opens
    -- the settings asks the settings page. Neither saves anything.
    local choose, routeChoose
    local function showMenu(h, level)
        local items = M.Items(menuState())
        local path = nil
        if level then
            path = { level }
            if M.PathTo then path = M.PathTo(items, level) or path end
        end
        h.menu(M.Level(items, path),
            script("menu", guarded(function(key) choose(key, h) end)))
    end
    local function openSettings(topic)
        local name = ns.SettingsPanel and ns.SettingsPanel.NAME or nil
        local page = name and k.use and k.use(name) or nil
        if not page or type(page.Show) ~= "function" then
            say("the settings page is not ready.")
            return
        end
        local ok, err = pcall(page.Show, topic ~= true and topic or nil)
        if not ok then k.problems:add("arrow", "settings", err) end
    end
    -- Lead section 387, R3: Hide this step, Go to the nearest..., Your
    -- waypoint. Each drops or picks what the arrow points at; nothing is
    -- bought, flown, cast or used.
    local function using(name, fn)
        if not k.use then return nil end
        local mod = k.use(name)
        if type(mod) ~= "table" or type(mod[fn]) ~= "function" then return nil end
        return mod[fn]
    end
    local function run(what, fn, ...)
        if not fn then
            say(what .. " is not ready.")
            return false
        end
        local ok, err = pcall(fn, ...)
        if not ok then k.problems:add("arrow", what, err) end
        return ok
    end
    function routeChoose(action)
        if action.hide == "route" then
            -- The step being skipped is read first, so it can be kept hidden.
            -- (A route planned by itself answers through AutoStep, A1-24.)
            local step = nil
            for _, ask in ipairs({ "Step", "AutoStep" }) do
                local current = using("tripRoute", ask)
                if step == nil and current then
                    local okStep, got = pcall(current)
                    if okStep and type(got) == "table" then step = got end
                end
            end
            if step then Arrow.KeepHidden(step, k.store) end
            run("the route", using("tripRoute", "Skip"))
        elseif action.hide == "errand" then
            run("the errand stop", using("errand", "Clear"))
        elseif action.hide == "follow" then
            run("pointing at a party member", using("follow", "Stop"))
        elseif action.hide == "waypoint" then
            local slot = W and W.Slot(k.store)
            if slot then W.Clear(slot) end
        elseif action.nearest then
            local pick = using("errand", "Choose")
            if pick then
                local ok, place = pcall(pick, action.nearest)
                if not ok or place == nil then say("no " .. action.nearest .. " you have seen is on this map.") end
            else
                say("the nearest stop is not ready.")
            end
        elseif action.waypoint then
            -- Your own waypoint is the quest step once nothing set by hand
            -- is in front of it: a party member, an errand stop.
            local stopFollow = using("follow", "Stop")
            if stopFollow then pcall(stopFollow) end
            local clear = using("errand", "Clear")
            if clear then pcall(clear) end
        end
        relayout()
    end
    choose = function(key, h)
        if not ready or not live() then return end
        local action = M.Action(key, menuState())
        if not action then return end
        if action.open ~= nil then
            if h and type(h.menu) == "function" then showMenu(h, action.open or nil) end
        elseif action.settings then
            openSettings(action.settings)
        elseif action.feedback then
            -- Row N73: the feedback window. It opens its own plain frame.
            local name
            if ns.Feedback then name = ns.Feedback.NAME end
            local feedback
            if name and k.use then feedback = k.use(name) end
            if type(feedback) == "table" and type(feedback.Open) == "function" then
                local ok, err = pcall(feedback.Open)
                if not ok then k.problems:add("arrow", "feedback", err) end
            else
                say("feedback is not ready.")
            end
        elseif action.setting then
            -- Lead section 387 R3: the Suggest dungeons switch; the level stays open.
            local ok, why = k.settings:set(action.setting, action.on)
            if not ok then say(tostring(why) .. ".") end
            if h and type(h.menu) == "function" then showMenu(h, M.ROUTE) end
        elseif action.button then
            -- Lead section 387 R3: a button's own setting; UI/WindowButtons.lua
            -- shows or hides it. The Buttons level stays open.
            local ok, why = k.settings:set(action.button, action.on)
            if not ok then say(tostring(why) .. ".") end
            if h and type(h.menu) == "function" then showMenu(h, M.BUTTONS) end
        elseif action.flowWindow then
            -- Lead section 387 R3: open the window, or close it when it says it is open.
            local spec
            for _, w in ipairs(M.FLOW_WINDOWS) do
                if w.name == action.flowWindow then spec = w end
            end
            local win
            if spec and k.use then win = k.use(spec.name) end
            if type(win) == "table" and type(win[spec.open]) == "function" then
                local open = true
                if spec.close and type(win[spec.close]) == "function" and type(win[spec.shown]) == "function" then
                    local okShown, shown = pcall(win[spec.shown])
                    open = not (okShown and shown == true)
                end
                local ok, err
                if open then ok, err = pcall(win[spec.open]) else ok, err = pcall(win[spec.close]) end
                if not ok then k.problems:add("arrow", "window", err) end
            else
                say("that window is not ready.")
            end
        elseif action.window then
            -- Lead section 318: a window of its own module (UI/ArrowMenu.lua M.WINDOWS).
            local win = k.use and k.use(action.window) or nil
            if type(win) == "table" and type(win.Open) == "function" then
                local ok, err = pcall(win.Open)
                if not ok then k.problems:add("arrow", "window", err) end
            else
                say("that window is not ready.")
            end
        elseif action.follow ~= nil then
            -- G47: point at a party member, or stop (Nav/Follow.lua).
            local follow = k.use and k.use("follow") or nil
            if type(follow) == "table" and type(follow.Pick) == "function" and type(follow.Stop) == "function" then
                local ok, err
                if action.follow == false then ok, err = pcall(follow.Stop) else ok, err = pcall(follow.Pick, action.follow) end
                if not ok then k.problems:add("arrow", "follow", err) end
            else
                say("pointing at a party member is not ready.")
            end
        elseif action.professions ~= nil then
            -- Lead section 382: the Professions tick (Nav/ProfFeed.lua).
            local ok, err = pcall(k.settings.set, k.settings,
                N.ProfFeed and N.ProfFeed.SETTING or "nav.professions", action.professions)
            if not ok then k.problems:add("arrow", "professions", err) end
        elseif action.walk ~= nil then
            -- Parity B-30: Walk there instead (Nav/Travel.lua).
            run("walking", using("travel", "Walk"))
            relayout()
        elseif action.mapToggle ~= nil then
            -- B-13, B-14: the world map switches (Nav/MapToggles.lua).
            local toggle = using("mapToggles", "Toggle")
            if toggle then
                local ok, err = pcall(toggle, action.mapToggle)
                if not ok then k.problems:add("arrow", "mapToggle", err) end
            else
                say("the world map switches are not ready.")
            end
        elseif action.wayPrompt then
            -- Parity A1-40: "Set a waypoint..." opens the waypoint box
            -- (Nav/WayWords.lua api.Prompt); its own line says why when
            -- the box cannot open.
            local prompt = using("wayWords", "Prompt")
            if prompt then
                local okP, shown, line = pcall(prompt)
                if not okP then
                    k.problems:add("arrow", "wayPrompt", shown)
                elseif shown ~= true then
                    say(tostring(line))
                end
            else
                say("waypoints are not ready.")
            end
        elseif action.wayAt then
            -- Lead section 465 (A1-42): "Waypoint at <name>".
            local at = using("wayWords", "At")
            if at then
                local okW, done, line = pcall(at, action.wayAt)
                if okW then say(tostring(line)) else k.problems:add("arrow", "wayAt", done) end
            else
                say("waypoints are not ready.")
            end
            relayout()
        elseif action.drawer then
            -- Lead section 387, R3: Open it, as a left click on the quest arrow.
            local ok, err = pcall(drawer, "quest")
            if not ok then k.problems:add("arrow", "drawer", err) end
        elseif action.hide or action.nearest or action.waypoint then
            routeChoose(action)
        elseif action.style then
            local ok, reason = setStyle(action.style)
            if not ok then say(tostring(reason) .. ".") end
        else
            act(action)
        end
    end

    -- Opens the menu on the first arrow that has one, as a right click on
    -- it does (the world-map button asks for this). false when there is
    -- no arrow to open it on.
    local function openMenu()
        if not handles or not ready or not live() then return false end
        for _, key in ipairs(N.ARROW_KEYS) do
            local h = handles[key]
            if h and type(h.menu) == "function" then
                showMenu(h)
                return true
            end
        end
        return false
    end

    if handles then
        hideAll()
        for _, key in ipairs(N.ARROW_KEYS) do
            local h = handles[key]
            -- The frame scripts that run the arrows' own code: the end of a
            -- drag, a click, the pointer coming and going, and a menu row.
            -- (The start of a drag runs only the client's code.)
            h.onMoved(script("drag", guarded(function(point)
                if not ready or not live() then return end
                act({ op = "drop", key = key, point = point })
            end)))
            -- AM5. A right click opens the menu. A left click opens the
            -- drawer when one was set (setDrawer); there is none yet, so it
            -- does nothing that can be seen. No click acts on the game
            -- world. A drawer that breaks is listed and the arrows stay.
            if type(h.onClick) == "function" and type(h.menu) == "function" and type(h.tip) == "function" then
                h.onClick(script("click", guarded(function(button)
                    if not ready or not live() then return end
                    if button == "right" then
                        h.tip(nil)
                        showMenu(h)
                    elseif button == "left" and drawer then
                        local ok, err = pcall(drawer, key)
                        if not ok then k.problems:add("arrow", "drawer", err) end
                    end
                end)))
            end
            if type(h.onHover) == "function" and type(h.tip) == "function" then
                h.onHover(script("hover", guarded(function(on)
                    if on then h.tip(tip(key)) else h.tip(nil) end
                end)))
            end
            -- A1-22 (section 844): the profession arrow's text, as Flow's
            -- (b657e6e5 Modules/Nav/Nav.lua:4415-4431): a left click opens
            -- the step, a right click the menu, a hover the step's lines.
            -- The answers are Nav/ProfArrowText.lua's; the hit is the
            -- client's (h.onTextClick / h.onTextHover), when it has one.
            local PT = ns.Nav and ns.Nav.ProfArrowText
            if key == "prof" and PT and type(h.onTextClick) == "function" then
                local function textState()
                    if not current or not shownLines then return {} end
                    local lines = shownLines.prof
                    if type(lines) ~= "table" or #lines == 0 then return {} end
                    return { step = { lines = lines } }
                end
                h.onTextClick(script("textClick", guarded(function(button)
                    if not ready or not live() then return end
                    local what = PT.Click(button, textState())
                    if what == "menu" then
                        h.tip(nil)
                        showMenu(h)
                    elseif what == "open" and drawer then
                        local ok, err = pcall(drawer, key)
                        if not ok then k.problems:add("arrow", "drawer", err) end
                    end
                end)))
                if type(h.onTextHover) == "function" and type(h.tip) == "function" then
                    h.onTextHover(script("textHover", guarded(function(on)
                        if on and ready and live() then h.tip(PT.Tip(textState(), drawer ~= nil)) else h.tip(nil) end
                    end)))
                end
            end
        end
        if own.loaded then apply() else listen("PLAYER_LOGIN", apply) end
        listen("PLAYER_ENTERING_WORLD", guarded(enterWorld))
        if quests then
            -- The quest log or the zone changed: read both again, then lay out.
            local changed = guarded(function()
                quests.refresh()
                relayout()
            end)
            listen("QUEST_LOG_UPDATE", changed)
            listen("ZONE_CHANGED_NEW_AREA", changed)
            -- The quest the player follows changed, or a quest came or went
            -- (sections 131 and 133). The names are on warcraft.wiki.gg, each
            -- listed for this client; none has been seen to fire in game:
            -- needs game test. A name this client does not have is not
            -- registered and costs nothing.
            listen("SUPER_TRACKING_CHANGED", changed)
            listen("QUEST_WATCH_LIST_CHANGED", changed)
            listen("QUEST_ACCEPTED", changed)
            listen("QUEST_REMOVED", changed)
            listen("QUEST_TURNED_IN", changed)
            listen("UNIT_QUEST_LOG_CHANGED", changed)
        end
    end

    local USAGE = id.slash .. " arrow demo | near | separate | stack | reset | hide quest|prof | text quest|prof"
        .. " | modern | 3d | flat | why"

    -- arrow why: says what the quest arrow is made from right now. It only
    -- reads and prints; nothing is changed. Each read it names needs game
    -- test: this is how they get seen.
    local function one(v)
        if v == nil then return "no such read" end
        if v == false then return "none" end
        return tostring(v)
    end
    local function why()
        say("quest step from " .. from .. "; quest arrow setting " .. (Arrow.QuestArrowOn(k) and "on" or "off") .. ".")
        local st = quests and quests.state and quests.state() or nil
        if type(st) ~= "table" or st.rows == nil then
            say("quest log: not read.")
        else
            say("quest log: " .. st.rows .. " read; Questie places " .. (st.places and "ready" or "not ready")
                .. "; map " .. one(st.map) .. ".")
            say(st.quest and ("quest " .. tostring(st.quest) .. ", chosen from "
                .. (st.from == "picked" and "your focus" or st.from == "watched" and "your watch list" or "the whole log")
                .. ".") or "no quest step.")
        end
        local reads = ask(client, "questFocusReads")
        if type(reads) ~= "table" then
            say("focus reads: none on this client.")
        else
            say("focus reads: super track " .. one(reads.superTrack) .. "; Questie focus " .. one(reads.questie)
                .. "; watch list " .. (type(reads.watched) == "table" and (#reads.watched .. " quests") or "no such read")
                .. ".")
        end
        local faults = ask(client, "listenFaults")
        local missing = type(faults) == "table" and type(faults.notRegistered) == "table" and faults.notRegistered or {}
        local names = {}
        for _, name in ipairs(missing) do names[#names + 1] = tostring(name) end
        say(#names > 0 and ("events the client refused: " .. table.concat(names, ", ") .. ".")
            or "events: none refused.")
    end

    -- Saves the style and draws in it. true, or false and why.
    function setStyle(key)
        if not handles then return false, "this client cannot draw the arrows" end
        if not ready then return false, "the arrows are not ready until login" end
        if not live() then return false, "the arrows are switched off until the next reload" end
        if key ~= "modern" and key ~= "3d" and key ~= "flat" then return false, "no such arrow style" end
        if key ~= "modern" and not canShapes() then return false, "this client cannot draw that style" end
        local ok, reason
        if Arrow.StyleRow(k) then
            ok, reason = k.settings:set(Arrow.STYLE, key)
        else
            ok, reason = k.store:set("account", Arrow.STYLE_PATH, key)
        end
        if not ok then
            k.problems:add("arrow", "save", reason)
            return false, tostring(reason)
        end
        relayout()
        return true
    end

    if diag and type(diag.commands) == "table" then
        if type(diag.help) == "table" then
            diag.help.arrow = "the arrows: why, demo, near, separate, stack, reset, modern|3d|flat, hide|text quest|prof"
        end
        diag.commands.arrow = function(rest)
            local word, key = (rest or ""):match("^(%S*)%s*(%S*)")
            if word == "why" then
                why()
            elseif not handles then
                say("this client cannot draw the arrows.")
            elseif not live() then
                say("the arrows are switched off until the next reload.")
            elseif not ready then
                say("the arrows are not ready until login.")
            elseif word == "demo" then
                demo, near = not demo, false
                relayout()
                say("arrow demo " .. (demo and "on: quest arrow north, needle east." or "off."))
            elseif word == "near" then
                near = not near
                relayout()
                say("demo quest step " .. (near and "reached." or "not reached."))
            elseif word == "separate" or word == "stack" then
                act({ op = "mode", mode = word == "separate" and "separate" or "stacked" })
                say("arrows " .. (word == "separate" and "separated." or "stacked."))
            elseif word == "reset" then
                act({ op = "reset" })
                say("arrows back to their first place.")
            elseif word == "modern" or word == "3d" or word == "flat" then
                local ok, reason = setStyle(word)
                say(ok and ("arrow style: " .. N.ArrowStyleLabel(word) .. ".") or (reason .. "."))
            elseif (word == "hide" or word == "text") and (key == "quest" or key == "prof") then
                local saved = N.ArrowSaved(Arrow.Saved(k))
                local on
                if word == "hide" then on = not saved.hidden[key] else on = saved.text[key] == false end
                act({ op = word, key = key, on = on })
                say(key .. (word == "hide" and (on and " arrow hidden." or " arrow shown.")
                    or (on and " text shown." or " text hidden.")))
            else
                say(USAGE)
            end
        end
    end

    -- The player's own waypoint (G35): "/way x y [label]", "/way clear",
    -- and the same after the addon's own command and the word "way" (there
    -- the text arrives lower-cased, so a label typed that way is too).
    -- Nothing is saved until one is set. Look-only: it points, no more.
    -- "/way" is claimed only while no other addon owns it; wayHeld says
    -- whether it is ours. The addon's own command works either way.
    local wayHeld = false
    local function way(rest)
        local text = type(rest) == "string" and rest:match("^%s*(.-)%s*$") or ""
        local cmd = wayHeld and "/way" or (id.slash .. " way")
        local HOW = cmd .. " x y [label] sets a waypoint on the map you are on; " .. cmd .. " clear removes it. "
            .. "Or hold Alt and click a spot on the world map."
        if not W then
            say("waypoints are not loaded.")
        elseif not ready then
            say("waypoints are not ready until login.")
        elseif text == "" then
            local wp = W.Get(k.store:get(W.SCOPE, W.PATH))
            local at = wp and W.Text(wp) or nil
            say(at and ("waypoint: " .. at .. ". " .. HOW) or HOW)
        elseif text:lower() == "clear" then
            if W.Clear(k.store:get(W.SCOPE, W.PATH)) then
                relayout()
                say("waypoint cleared.")
            else
                say(W.REASON.unset .. ".")
            end
        else
            -- Lead section 465 (A1-39/41/42): zone names, place words and
            -- party members (Nav/WayWords.lua) first; the rest as before.
            local words = k.use and k.use("wayWords")
            if type(words) == "table" and type(words.Take) == "function" then
                local okW, took, line = pcall(words.Take, text)
                if not okW then k.problems:add("arrow", "way", took) end
                if okW and took then
                    say(tostring(line))
                    relayout()
                    return
                end
            end
            local here = ask(client, "position")
            local okN, zoneName = pcall(function() return client.mapName(here.map) end)
            local wp, why = W.Set(W.Slot(k.store), here, text, okN and zoneName or nil)
            if wp then
                say("waypoint set: " .. tostring(W.Text(wp)) .. ".")
                relayout()
            else
                say(tostring(why) .. "; nothing changed.")
            end
        end
    end
    if diag and type(diag.commands) == "table" then diag.commands.way = way end
    if diag and type(diag.help) == "table" then diag.help.way = "way x y [label]: point at your own waypoint; way clear removes it" end
    -- Only when free, as legacy Flow did (Modules/Nav/Waypoint.lua:260-262):
    -- another addon's "/way" (TomTom, legacy Flow) is never overwritten.
    -- Asked when this file loads and again at login, since an addon may
    -- claim it in between; then ours is given back. A client that cannot
    -- say who owns it is treated as before. Needs game test.
    local WAY_TAG = id.bindingHeader .. "WAY"
    local function claimWay()
        if type(client.slash) ~= "function" then return end
        local taken = type(client.slashTaken) == "function" and client.slashTaken("/way", WAY_TAG) == true
        if taken then
            if wayHeld and type(client.unslash) == "function" then client.unslash(WAY_TAG) end
            wayHeld = false
        elseif not wayHeld then
            wayHeld = client.slash(WAY_TAG, "/way", way) ~= false
        end
    end
    claimWay()
    listen("PLAYER_LOGIN", claimWay)

    -- Alt + click on the world map sets the same waypoint at that spot
    -- (G35). It only points: the map's own click is left as it is.
    local function mapWay(map, x, y)
        if not W or not ready then return end
        local wp, why = W.SetAt(W.Slot(k.store), map, x, y)
        if wp then
            local okN, name = pcall(function() return client.mapName(map) end)
            local where = okN and type(name) == "string" and (" in " .. name) or ""
            say("waypoint set: " .. tostring(W.Text(wp)) .. where .. ". "
                .. (wayHeld and "/way" or (id.slash .. " way")) .. " clear removes it.")
            relayout()
        else
            say(tostring(why) .. "; nothing changed.")
        end
    end
    local mapHooked = false
    local function hookMap()
        if mapHooked or type(client.mapClick) ~= "function" then return end
        local ok, done = pcall(client.mapClick, mapWay)
        mapHooked = ok and done == true
    end
    hookMap()
    listen("PLAYER_LOGIN", hookMap)

    local function setGuide(fn)
        guideFn = type(fn) == "function" and fn or nil
        relayout()
    end

    -- What the owner calls when the arrows are switched off: off the screen,
    -- and no more frames asked for.
    function stop()
        current = nil
        if handles then pcall(hideAll) end
        if cancelTick then
            cancelTick()
            cancelTick = nil
        end
    end

    return { handles = handles, relayout = relayout, setGuide = setGuide, stop = stop,
             style = style, setStyle = setStyle,
             styles = function() return Arrow.Styles(style()) end,
             menu = function() return M.Items(menuState()) end,
             tip = tip,
             openMenu = openMenu,
             setDrawer = function(fn) drawer = type(fn) == "function" and fn or nil end,
             state = function() return { ready = ready, demo = demo, near = near, view = current } end,
             heading = function()
                 if not heading then return nil end
                 return { cont = heading.cont, map = heading.map, x = heading.x, y = heading.y }
             end,
             family = function() return family end }
end

-- Declares the arrows on kernel k as the module Arrow.NAME. Nothing is made
-- here: the frames, the event, the frame work and the word "arrow" all come
-- with the module's start, so beside the predecessor (the load is paused and
-- no module starts) there is none of them. The event and the frame work are
-- registered under the module's name: when the kernel switches the module
-- off they stop with it, and the module's stop hides the frames. What a
-- frame script runs of the arrows (the end of a drag, a click, the pointer
-- coming and going, a menu row) is run through the
-- kernel's meter under the module's name, and its error is one of the
-- module's: five switch the arrows off. A frame error switches the module
-- off at once, through the kernel (k:SwitchOff): the kernel's state is the
-- one record that the arrows are off, and its stop is what stops them.
-- Returns what Arrow.Start returns, usable at once: before the start (and
-- for a declaration the kernel refused) relayout does nothing, state is
-- not ready, handles is nil, and a guide that is set is kept for the start;
-- style is "modern" and setStyle answers false; menu gives the rows of a
-- fresh layout, tip gives nil, and a drawer that is set is kept for the
-- start.
function Arrow.Declare(k, diag)
    local inner, pending, pendingDrawer = nil, nil, nil
    local api = {}
    Arrow.Row(k)
    Arrow.StyleRow(k)
    Arrow.PaletteRow(k)
    Arrow.ByDistanceRow(k)
    -- Before the start the style in use is the modern one and none is set.
    function api.style()
        if inner then return inner.style() end
        return "modern"
    end
    function api.styles()
        if inner then return inner.styles() end
        return Arrow.Styles("modern")
    end
    function api.setStyle(key)
        if inner then return inner.setStyle(key) end
        return false, "the arrows are not started"
    end
    -- The right-click menu's rows as they would be now (UI/ArrowMenu.lua).
    function api.menu()
        if inner then return inner.menu() end
        return ns.ArrowMenu.Items({ styles = Arrow.Styles("modern") })
    end
    -- The tooltip's lines for "quest" or "prof", or nil when that arrow is
    -- not on the screen.
    function api.tip(key)
        if inner then return inner.tip(key) end
        return nil
    end
    -- fn(key) is what a left click on an arrow opens; nil takes it away.
    -- Until one is set a left click does nothing that can be seen.
    function api.setDrawer(fn)
        pendingDrawer = type(fn) == "function" and fn or nil
        if inner then inner.setDrawer(pendingDrawer) end
    end
    -- Opens the right-click menu without a click on an arrow. false before
    -- the start and when there is no arrow to open it on.
    function api.openMenu()
        if inner then return inner.openMenu() end
        return false
    end
    function api.relayout()
        if inner then inner.relayout() end
    end
    function api.setGuide(fn)
        pending = type(fn) == "function" and fn or nil
        if inner then inner.setGuide(pending) end
    end
    function api.state()
        if inner then return inner.state() end
        return { ready = false, demo = false, near = false }
    end
    -- The place the quest arrow points the player to now, { cont, map, x,
    -- y } (shares of map), or nil: before the start, with nothing shown,
    -- in the demo, or for a step with no map place. A copy each time.
    function api.heading()
        if inner and inner.heading then return inner.heading() end
        return nil
    end
    -- The family of the step the quest arrow points at now, or nil (R7).
    function api.family()
        if inner and inner.family then return inner.family() end
        return nil
    end
    k:Module({
        name = Arrow.NAME,
        needs = { "client", "store", "bus", "sched" },
        provides = { OpenMenu = function() return api.openMenu() end,
                     Heading = function() return api.heading() end,
                     Family = function() return api.family() end,
                     -- Lead section 466: a chat-link click (Nav/PartyRoute.lua)
                     -- redraws at once, as a slash word's pass does.
                     Redraw = function() return api.relayout() end },
        start = function(ctx)
            local own = { loaded = true }
            function own.listen(event, fn) ctx.bus:on(Arrow.NAME, event, fn) end
            -- The scheduler has no job for every frame and gives a job no
            -- elapsed time: a next-frame job that asks for itself again,
            -- with the time between two frames read from the clock.
            function own.frame(fn)
                local on, last = true, ctx.client.now()
                local function run()
                    if not on then return end
                    local now = ctx.client.now()
                    local elapsed = 0
                    if type(now) == "number" and type(last) == "number" then elapsed = now - last end
                    -- A clock that steps back gives the frame no time.
                    if elapsed < 0 then elapsed = 0 end
                    last = now
                    ctx.sched:nextFrame(Arrow.NAME, run)
                    fn(elapsed)
                end
                ctx.sched:nextFrame(Arrow.NAME, run)
                return function() on = false end
            end
            function own.live() return k:ModuleState(Arrow.NAME) ~= "off" end
            function own.off(err) k:SwitchOff(Arrow.NAME, "frame error: " .. tostring(err)) end
            function own.script(label, fn)
                return function(...)
                    if not own.live() then return end
                    local ok, err = k.meter:run(Arrow.NAME, "script", label, fn, ...)
                    if not ok then k.fault(Arrow.NAME, err) end
                end
            end
            inner = Arrow.Start(k, diag, own)
            api.handles = inner.handles
            if pending then inner.setGuide(pending) end
            if pendingDrawer then inner.setDrawer(pendingDrawer) end
        end,
        stop = function()
            if inner then inner.stop() end
        end,
    })
    return api
end

-- The addon's own arrows: declared when this file loads, made and placed
-- when the kernel starts the module at login.
ns.arrow = Arrow.Declare(ns, ns.diag)

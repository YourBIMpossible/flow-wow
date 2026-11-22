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
        label = "Arrow positions", group = "Arrows", keepOnResetAll = true,
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
        label = "Arrow style", group = "Arrows",
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
        label = "Arrow colours", group = "Arrows",
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
    return ns.Nav.ArrowPaletteOf(k.store:get("account", Arrow.PALETTE_PATH))
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
--   client.ghost a plain false (dead, not released): no place, and the one
--     line is the release label. A corpse place the client gives is not
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
        return { label = Arrow.RELEASE_LABEL, lines = { Arrow.RELEASE_LABEL }, still = true }
    end
    local step = { label = Arrow.CORPSE_LABEL }
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

-- Player-visible words, authored here (not taken from the game or from Flow).
Arrow.CORPSE_LABEL = "Corpse"
Arrow.RELEASE_LABEL = "Release your spirit"
Arrow.CORPSE_ELSEWHERE = "corpse is on another map"
-- The distance line (G40): the yards, then the compass word when there is
-- one. Inside the arrival radius the line is HERE_TEXT and no distance.
Arrow.DISTANCE_TEXT = "%d yd"
Arrow.DISTANCE_COMPASS_TEXT = "%d yd %s"
Arrow.HERE_TEXT = "you're here"

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
        else
            local label = more[key].label or step.label
            if label ~= nil then out[#out + 1] = tostring(label) end
            -- A step may say one more line of its own under its label (S43).
            if step.detail ~= nil then out[#out + 1] = tostring(step.detail) end
            if type(d) == "number" then
                local word = more[key].compass
                if arrived then
                    out[#out + 1] = Arrow.HERE_TEXT
                elseif word ~= nil then
                    out[#out + 1] = Arrow.DISTANCE_COMPASS_TEXT:format(math.floor(d + 0.5), word)
                else
                    out[#out + 1] = Arrow.DISTANCE_TEXT:format(math.floor(d + 0.5))
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
    local quests = N.QuestWatch and N.QuestSource and N.QuestWatch(client) or nil
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
    local function source()
        mine = false
        from = "demo"
        if demo then return Arrow.DemoSource(client, Arrow.Saved(k), near, Arrow.Palette(k)) end
        local playing = intro()
        local guide
        if guideFn then
            guide = guideFn()
            from = "a guide"
        else
            local step = W and W.Step(k.store:get(W.SCOPE, W.PATH), ask(client, "position"), ask(client, "zone"))
            from = "nothing"
            if step then
                mine, from = true, "your own waypoint"
            else
                step = N.WaypointStep(client)
                if step then from = "the map pin" end
            end
            -- Then the errand stop the player asked for (Nav/Errand.lua), when there is one.
            local errand = k.use and k.use("errand")
            if step == nil and errand and errand.Step then
                step = errand.Step()
                if step then from = "an errand stop" end
            end
            -- The player's own pin (/way, then the map pin) wins over the player's quests.
            if step == nil and quests and Arrow.QuestArrowOn(k) then
                step = quests.step()
                if step then from = "your quests" end
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
            local prof = N.ProfStepFrom(client, k.store)
            guide = (step or prof) and { quest = step, prof = prof } or nil
        end
        if type(guide) ~= "table" then
            if not playing then return nil end
            guide = {}
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
        for _, key in ipairs(N.ARROW_KEYS) do
            local ops, h = view[key], handles[key]
            -- A bare needle keeps its frame for its text when the lines are
            -- its own: stacked under a shown quest arrow they are in that
            -- arrow's stack, and no second frame is put up.
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
                                          bare = (lost or ops.bare) and true or false })
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
        introUntil = now + Arrow.INTRO_SECONDS
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
        return { stacked = saved.mode ~= "separate", hidden = saved.hidden, text = saved.text,
                 styles = Arrow.Styles(style()), canShapes = canShapes() }
    end
    -- The tooltip's lines for one arrow, or nil when none is on the screen.
    -- The lines are the step's own, also for an arrow whose text is off.
    local function tip(key)
        if not handles or not ready or not live() or not current then return nil end
        return M.Tip({ key = key, stacked = current.prof.behind == true,
                       both = current.quest.shown == true and current.prof.shown == true,
                       drawer = drawer ~= nil, lines = shownLines })
    end
    -- The menu row with this key was clicked. A row that is not there or
    -- not offered asks for nothing.
    local function choose(key)
        if not ready or not live() then return end
        local action = M.Action(key, menuState())
        if not action then return end
        if action.style then
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
                h.menu(M.Items(menuState()), script("menu", guarded(choose)))
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
                        h.menu(M.Items(menuState()), script("menu", guarded(choose)))
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
    local function way(rest)
        local text = type(rest) == "string" and rest:match("^%s*(.-)%s*$") or ""
        local HOW = "/way x y [label] sets a waypoint on the map you are on; /way clear removes it."
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
            local wp, why = W.Set(W.Slot(k.store), ask(client, "position"), text)
            if wp then
                say("waypoint set: " .. tostring(W.Text(wp)) .. ".")
                relayout()
            else
                say(tostring(why) .. "; nothing changed.")
            end
        end
    end
    if diag and type(diag.commands) == "table" then diag.commands.way = way end
    if type(client.slash) == "function" then
        client.slash(id.bindingHeader .. "WAY", "/way", way)
    end

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
             state = function() return { ready = ready, demo = demo, near = near, view = current } end }
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
    k:Module({
        name = Arrow.NAME,
        needs = { "client", "store", "bus", "sched" },
        provides = { OpenMenu = function() return api.openMenu() end },
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

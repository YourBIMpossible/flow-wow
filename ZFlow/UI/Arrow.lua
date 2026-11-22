-- The two guide arrows on screen: the quest arrow and, behind it or on its
-- own, the translucent profession needle.
--
-- This file makes no frame and decides no layout rule. The client boundary
-- makes the frames (client.arrow); Nav/ArrowView.lua says what each arrow
-- shows and where; Nav/ArrowLayout.lua's ArrowApply turns a drag or a
-- command into the next saved layout; Nav/ArrowMotion.lua turns and fades
-- the drawn arrow. What it saves, per account:
--   layout.arrows   (the shape is in Nav/ArrowLayout.lua)
--
-- Until the guide reads its steps into an arrow source (Nav ViewState) the
-- arrows have nothing to point at and stay hidden. The demo is for checking
-- the frames by eye on the real client: the quest arrow points north, the
-- needle east, both from the player's real facing.
--
--   <slash> arrow demo             demo on / off
--   <slash> arrow near             demo: the quest step reached / not
--   <slash> arrow separate | stack | reset
--   <slash> arrow hide quest|prof  <slash> arrow text quest|prof   (toggles)
local _, ns = ...

local Arrow = {}
ns.Arrow = Arrow

Arrow.PATH = "layout.arrows"
Arrow.RELAYOUT = 0.25          -- seconds between layouts while shown
Arrow.LINE_HEIGHT = 14
Arrow.DEMO = {
    questDistance = 300, nearDistance = 10, profDistance = 150,
    own = { 0.55, 0.8, 1 },    -- the needle's own colour while stacked
    questBearing = 0,          -- north
    profBearing = math.pi / 2, -- east
}

-- The saved layout, as ArrowView and ArrowApply take it: { arrows = ... }.
function Arrow.Saved(k)
    local raw = k.store:get("account", Arrow.PATH)
    return { arrows = type(raw) == "table" and raw or nil }
end

-- The demo's arrow source: ArrowView's state plus the turns and lines.
-- near: the quest step reached.
function Arrow.DemoSource(client, layout, near)
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
            layout = layout, screenW = w, screenH = h, gate = "open",
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
function Arrow.Lines(view, lines)
    local out = { quest = {}, prof = {} }
    local function add(to, list)
        for i = 1, #(list or {}) do to[#to + 1] = list[i] end
    end
    if view.quest.shown and view.quest.text.shown then add(out.quest, lines.quest) end
    local pt = view.prof.text
    if view.prof.shown and pt.shown then
        add(pt.to == "quest" and out.quest or out.prof, lines.prof)
    end
    return out
end

-- Starts the arrows on kernel k; diag (optional) gains the word "arrow".
-- Returns { handles = { quest, prof } or nil, relayout = fn, state = fn }.
function Arrow.Start(k, diag)
    local client, id, N = k.client, k.id, ns.Nav
    local spec = function(name, level)
        return { name = id.framePrefix .. name, size = N.ARROW_SIZE, art = N.ARROW_ART,
                 artPath = "Interface\\AddOns\\" .. id.addon .. "\\Art\\",
                 needle = { N.NEEDLE_W, N.NEEDLE_H }, level = level }
    end
    local quest = client.arrow(spec("QuestArrow", 6))
    local prof = quest and client.arrow(spec("ProfArrow", 6)) or nil
    local handles = (quest and prof) and { quest = quest, prof = prof } or nil
    local motion = { quest = N.ArrowMotion(), prof = N.ArrowMotion() }
    local ready, demo, near = false, false, false
    local current, cancelTick, since, broken = nil, nil, 0, false

    local function source()
        if demo then return Arrow.DemoSource(client, Arrow.Saved(k), near) end
        return nil
    end

    local function hideAll()
        if not handles then return end
        handles.quest.show(false)
        handles.prof.show(false)
    end

    -- A fresh layout: what is shown, where, at what scale and opacity.
    local function relayout()
        if not handles or not ready then return end
        local src = source()
        if not src then
            current = nil
            hideAll()
            return
        end
        local view = N.ArrowView(src.view)
        local lines = Arrow.Lines(view, src.lines)
        for _, key in ipairs(N.ARROW_KEYS) do
            local ops, h = view[key], handles[key]
            h.show(ops.shown)
            if ops.shown then
                h.look(ops.look)
                if ops.anchor == "quest" then h.attach(handles.quest) else h.place(ops.point) end
                h.scale(ops.scale)
                h.alpha(ops.alpha)
                h.behind(ops.behind)
                local textPoint = ops.text.point
                if key == "quest" and view.prof.shown and view.prof.text.shown and view.prof.text.to == "quest" then
                    textPoint = view.prof.text.point   -- one stack of lines: the stack's gap
                end
                h.text(lines[key], textPoint)
                N.ArrowAim(motion[key], { turn = src.turns[key], colour = ops.colour,
                                          arrived = ops.mode == "ring" })
            end
        end
        current = view
    end

    local function frame(elapsed)
        if broken then return end
        local ok, err = pcall(function()
            since = since + (tonumber(elapsed) or 0)
            if since >= Arrow.RELAYOUT then
                since = 0
                relayout()
            end
            if not current then return end
            local now = client.now()
            for _, key in ipairs(N.ARROW_KEYS) do
                if current[key].shown then
                    handles[key].draw(N.ArrowStep(motion[key], elapsed, now))
                end
            end
        end)
        if not ok then
            broken = true
            k.problems:add("arrow", "frame", err)
        end
    end

    local function tick(on)
        if on and not cancelTick then
            cancelTick = client.onFrame(frame)
        elseif not on and cancelTick then
            cancelTick()
            cancelTick = nil
        end
    end

    local function write(layout)
        local ok, reason = k.store:set("account", Arrow.PATH, layout.arrows)
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
        ready = true
        relayout()
        tick(true)
    end

    if handles then
        hideAll()
        for _, key in ipairs(N.ARROW_KEYS) do
            handles[key].onMoved(function(point)
                if not ready then return end
                act({ op = "drop", key = key, point = point })
            end)
        end
        client.listen("PLAYER_LOGIN", apply)
        client.listen("PLAYER_ENTERING_WORLD", apply)
    end

    local function say(text) client.print(id.title .. ": " .. text) end
    local USAGE = id.slash .. " arrow demo | near | separate | stack | reset | hide quest|prof | text quest|prof"

    if diag and type(diag.commands) == "table" then
        diag.commands.arrow = function(rest)
            local word, key = (rest or ""):match("^(%S*)%s*(%S*)")
            if not handles then
                say("this client cannot draw the arrows.")
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

    return { handles = handles, relayout = relayout,
             state = function() return { ready = ready, demo = demo, near = near, view = current } end }
end

-- The addon's own arrows, made when this file loads and placed at login.
ns.arrow = Arrow.Start(ns, ns.diag)

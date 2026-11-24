local _, ns = ...

-- HoverBind (reconcile row G34; legacy Flow's Modules/BindMode.lua): put a
-- key on an action button by pointing at it. `/zflow bind` covers each
-- action button on the screen; the player holds the mouse over one and
-- presses a key. Each press is only listed in a small window, with what the
-- key does now when it already does something. Nothing is written until the
-- player clicks Save, and Cancel or Escape leaves every key as it was.
--
-- ACTING, and only at Save: the keys are put on with the game's own
-- SetBinding, one per listed line, then SaveBindings. When one write fails
-- the ones before it are put back and nothing is saved. It is refused in
-- combat (the game locks the keys), and a fight starting closes the mode
-- with nothing changed. It presses no key, casts nothing and clicks no
-- button for the player.
--
-- A right click on a covered button lists its keys to be taken off. Ctrl+Z
-- takes the last line back. A key listed twice counts once: the newest.
-- Mouse buttons are not taken as keys.
--
--   HoverBind.Targets() -> { { frame, id, label } }  every bar slot asked for
--   HoverBind.Label(id) -> "Action Bar 1, slot 2" | nil
--   HoverBind.Stage(staged, change) -> staged   (the newest of a key wins)
--   HoverBind.Lines(staged) -> the kit lines
--   HoverBind.Declare(k, diag) -> api
--     api.Open() -> true | false, why;  api.Close();  api.Shown()
--     api.Staged() -> a copy of the listed changes
--     api.Save() -> true | false, why
--   ns.use(HoverBind.NAME) -> { Open, Close, Shown, Staged }
--
-- Not seen in game: the covers over the real action buttons, the keyboard
-- taken by the full-screen frame, the bar frame names on this client, and
-- SetBinding with the game's commands. First guesses.

local H = ns.HoverBind or {}
ns.HoverBind = H

H.NAME = "hoverBind"
H.ID = "hoverBind"
H.WORD = "bind"
H.PATH = "layout.hoverBind"
H.HELP = "put keys on your action buttons: hover a button, press a key"
H.TITLE = "Bind keys"
H.INTRO = "Hold the mouse over an action button and press a key."
H.INTRO_SUB = "Right-click a button to take its keys off. Nothing changes until you click Save."
H.NONE = "No key picked yet."
H.SAVE, H.UNDO, H.CANCEL = "Save", "Undo", "Cancel"
H.UNDO_KEY = "CTRL-Z"
H.LOCKED = "Keys can't change in combat."
H.UNREAD = "The game did not say what your keys do, so they are left alone."
H.NO_DRAW = "This client cannot show the bind mode."
H.NO_BUTTONS = "No action button is on the screen to put a key on."
H.NO_KEYS = "That button has no key to take off."
H.FIGHT = "Bind mode closed: a fight started. Nothing was changed."
H.CANCELLED = "Bind mode closed. Nothing was changed."
H.AGAIN = "Press Escape again to throw away %d change(s)."
H.SAVED = "Saved %d key change(s)."
H.FAILED = "The game refused a key, so every key was put back. Nothing was changed."
H.NOT_KEPT = "The game did not save the keys, so every key was put back. Nothing was changed."
H.NOW = "Now: %s. It will stop doing that."
H.SAME = "Already on this button."
H.OFF = "nothing"
H.WAS = "Was: %s."
H.EARLIER = "... and %d earlier"
H.SHOWN = 8
H.WIDTH, H.HEAD, H.ROW, H.FOOT = 400, 96, 34, 44

-- The bars legacy Flow covered. frame prefix, the game's binding command
-- prefix, the name the player reads, how many slots.
H.BARS = {
    { "ActionButton", "ACTIONBUTTON", "Action Bar 1", 12 },
    { "MultiBarBottomLeftButton", "MULTIACTIONBAR1BUTTON", "Bottom Left Bar", 12 },
    { "MultiBarBottomRightButton", "MULTIACTIONBAR2BUTTON", "Bottom Right Bar", 12 },
    { "MultiBarRightButton", "MULTIACTIONBAR3BUTTON", "Right Bar", 12 },
    { "MultiBarLeftButton", "MULTIACTIONBAR4BUTTON", "Right Bar 2", 12 },
    { "MultiBar5Button", "MULTIACTIONBAR5BUTTON", "Action Bar 6", 12 },
    { "MultiBar6Button", "MULTIACTIONBAR6BUTTON", "Action Bar 7", 12 },
    { "MultiBar7Button", "MULTIACTIONBAR7BUTTON", "Action Bar 8", 12 },
    { "StanceButton", "SHAPESHIFTBUTTON", "Stance Bar", 10 },
}

local targets, labels

function H.Targets()
    if targets then return targets end
    targets, labels = {}, {}
    for _, bar in ipairs(H.BARS) do
        for slot = 1, bar[4] do
            local id = bar[2] .. slot
            local label = string.format("%s, slot %d", bar[3], slot)
            targets[#targets + 1] = { frame = bar[1] .. slot, id = id, label = label }
            labels[id] = label
        end
    end
    return targets
end

function H.Label(id)
    H.Targets()
    return labels[id]
end

-- What a key does now, in words: one of the buttons here by its name, else
-- the game's own name for it.
local function nameOf(action)
    return H.Label(action) or tostring(action)
end

-- change = { key, id (the button's command; nil to take the key off), was }
function H.Stage(staged, change)
    local out = {}
    for _, s in ipairs(type(staged) == "table" and staged or {}) do
        if type(change) ~= "table" or s.key ~= change.key then out[#out + 1] = s end
    end
    if type(change) == "table" and type(change.key) == "string" and change.key ~= "" then
        out[#out + 1] = { key = change.key, id = change.id, was = change.was }
    end
    return out
end

function H.Lines(staged)
    local lines = {}
    staged = type(staged) == "table" and staged or {}
    local first = math.max(1, #staged - H.SHOWN + 1)
    if first > 1 then
        lines[#lines + 1] = { kind = "line", key = "earlier", text = string.format(H.EARLIER, first - 1) }
    end
    for i = first, #staged do
        local s = staged[i]
        local line = { kind = "line", key = "change" .. i }
        if s.id == nil then
            line.text = s.key .. " -> " .. H.OFF
            line.sub = string.format(H.WAS, nameOf(s.was))
        else
            line.text = s.key .. " -> " .. nameOf(s.id)
            if s.was == s.id then
                line.sub = H.SAME
            elseif type(s.was) == "string" and s.was ~= "" then
                line.sub, line.tone = string.format(H.NOW, nameOf(s.was)), "warn"
            end
        end
        lines[#lines + 1] = line
    end
    if #staged == 0 then lines[1] = { kind = "line", key = "none", text = H.NONE } end
    return lines
end

function H.Declare(k, diag)
    local api = {}
    local ctx, handle, hover
    local staged, on, armed = {}, false, false
    local id = k.id or ns.id

    local function client() return ctx and ctx.client or nil end

    -- A read: nil when the client has no such function or it raised.
    local function ask(name, ...)
        local c = client()
        if type(c) ~= "table" or type(c[name]) ~= "function" then return nil end
        local got = { pcall(c[name], ...) }
        if not got[1] then return nil end
        return got[2], got[3]
    end

    -- A write: true only when the client said so.
    local function write(name, ...)
        local c = client()
        if type(c) ~= "table" or type(c[name]) ~= "function" then return false, "absent" end
        local ok, done, why = pcall(c[name], ...)
        if not ok then return false, tostring(done) end
        if done ~= true then return false, tostring(why) end
        return true
    end

    local function say(text)
        local c = client()
        if type(c) == "table" and type(c.print) == "function" then pcall(c.print, id.title .. ": " .. text) end
    end

    local function tree()
        local kids = { { kind = "header", key = "header", title = H.TITLE },
            { kind = "line", key = "intro", text = H.INTRO, sub = H.INTRO_SUB } }
        local lines = H.Lines(staged)
        for _, line in ipairs(lines) do kids[#kids + 1] = line end
        kids[#kids + 1] = { kind = "footer", key = "footer",
            text = armed and string.format(H.AGAIN, #staged) or nil,
            buttons = {
                { kind = "button", key = "save", text = H.SAVE, enabled = #staged > 0, onClick = function() api.Save() end },
                { kind = "button", key = "undo", text = H.UNDO, enabled = #staged > 0, onClick = function() api.Undo() end },
                { kind = "button", key = "cancel", text = H.CANCEL, onClick = function() api.Close(H.CANCELLED) end },
            } }
        local height = H.HEAD + #lines * H.ROW + H.FOOT
        return ns.Kit.Window({ id = H.ID, title = id.title .. ": " .. H.TITLE, width = H.WIDTH, height = height,
            closable = true, escape = false, children = kids }), height
    end

    -- The key each covered button will have: the listed one, else its own.
    local function coverTexts()
        local texts = {}
        for _, target in ipairs(H.Targets()) do
            local keys = ask("bindingKeys", target.id)
            if type(keys) == "table" and type(keys[1]) == "string" then texts[target.id] = keys[1] end
        end
        for _, s in ipairs(staged) do
            if s.id ~= nil then texts[s.id] = s.key end
        end
        return texts
    end

    local function draw()
        local c = client()
        local t, height = tree()
        if not t then
            k.problems:add(H.NAME, "tree", tostring(height))
            return false
        end
        if handle then
            handle.update(t)
        else
            local point, width = ns.Kit.Place(k.store:get("account", H.PATH), t)
            handle = c.kitWindow(H.ID, t, {
                name = id.framePrefix .. "HoverBind",
                point = point, width = width, height = height,
                onMoved = function(at)
                    if type(at) ~= "table" then return end
                    local ok, why = k.store:set("account", H.PATH, { point = { at[1], at[2], at[3], at[4] } })
                    if not ok then k.problems:add(H.NAME, "place", tostring(why)) end
                end,
                -- The window's own X: the same as Cancel.
                onClose = function() if on then api.Close(H.CANCELLED, true) end end,
                failed = function(err) k.problems:add(H.NAME, "draw", tostring(err)) end,
            })
            if not handle then
                k.problems:add(H.NAME, "window", "the client could not draw the window")
                return false
            end
        end
        handle.show(true)
        if hover then pcall(hover.labels, coverTexts()) end
        return true
    end

    local function stage(change)
        staged, armed = H.Stage(staged, change), false
        draw()
    end

    local function onKey(chord, target)
        if not on or type(chord) ~= "string" or chord == "" then return end
        if chord == H.UNDO_KEY then return api.Undo() end
        if type(target) ~= "string" or H.Label(target) == nil then return end
        local was = ask("bindingAction", chord, target)
        if type(was) ~= "string" then return say(H.UNREAD) end
        stage({ key = chord, id = target, was = was })
    end

    local function onClear(target)
        if not on or H.Label(target) == nil then return end
        local keys = ask("bindingKeys", target)
        if type(keys) ~= "table" then return say(H.UNREAD) end
        if #keys == 0 then return say(H.NO_KEYS) end
        for _, key in ipairs(keys) do
            staged = H.Stage(staged, { key = key, was = target })
        end
        armed = false
        draw()
    end

    local function onCancel()
        if not on then return end
        if #staged > 0 and not armed then
            armed = true
            draw()
            return
        end
        api.Close(H.CANCELLED)
    end

    function api.Shown() return on end

    function api.Staged()
        local out = {}
        for i, s in ipairs(staged) do out[i] = { key = s.key, id = s.id, was = s.was } end
        return out
    end

    -- why: the line the player reads, or nil for none. fromWindow: the
    -- window is closing itself already.
    function api.Close(why, fromWindow)
        if not on then return end
        on, staged, armed = false, {}, false
        if hover then pcall(hover.stop) end
        if handle and not fromWindow and handle.shown() then handle.close() end
        if type(why) == "string" then say(why) end
    end

    function api.Undo()
        if not on or #staged == 0 then return false end
        staged[#staged] = nil
        armed = false
        draw()
        return true
    end

    function api.Open()
        local c = client()
        if type(c) ~= "table" then return false, "not started" end
        if on then return true end
        if ask("combatLockdown") ~= false then
            say(H.LOCKED)
            return false, "lockdown"
        end
        if type(c.kitWindow) ~= "function" or type(c.bindHover) ~= "function"
            or type(c.setBinding) ~= "function" then
            say(H.NO_DRAW)
            return false, "absent"
        end
        -- One read to learn whether the keys can be read at all.
        if type(ask("bindingKeys", H.Targets()[1].id)) ~= "table" then
            say(H.UNREAD)
            return false, "unread"
        end
        if not hover then
            local ok, made = pcall(c.bindHover, { name = id.framePrefix .. "HoverBindKeys" })
            hover = ok and type(made) == "table" and made or nil
        end
        if not hover then
            say(H.NO_DRAW)
            return false, "absent"
        end
        local ok, n = pcall(hover.start, H.Targets(), onKey, onCancel, onClear)
        if not ok or type(n) ~= "number" or n < 1 then
            pcall(hover.stop)
            say(H.NO_BUTTONS)
            return false, "no buttons"
        end
        on, staged, armed = true, {}, false
        if not draw() then
            api.Close(H.NO_DRAW)
            return false, "absent"
        end
        return true
    end

    -- Puts back what was written, newest first.
    local function restore(done)
        for i = #done, 1, -1 do
            local s = done[i]
            if type(s.was) == "string" and s.was ~= "" then
                write("setBinding", s.key, s.was)
            else
                write("clearBinding", s.key, s.id)
            end
        end
    end

    -- The player's click on Save. Every line, in order; all or nothing.
    function api.Save()
        if not on or #staged == 0 then return false, "nothing" end
        if ask("combatLockdown") ~= false then
            say(H.LOCKED)
            return false, "lockdown"
        end
        local done = {}
        for _, s in ipairs(staged) do
            local ok
            if s.id == nil then
                ok = write("clearBinding", s.key, s.was)
            elseif s.was == s.id then
                ok = true
            else
                ok = write("setBinding", s.key, s.id)
            end
            if not ok then
                restore(done)
                say(H.FAILED)
                return false, "refused"
            end
            if s.id == nil or s.was ~= s.id then done[#done + 1] = s end
        end
        if not write("saveBindings") then
            restore(done)
            say(H.NOT_KEPT)
            return false, "not saved"
        end
        local n = #staged
        api.Close(string.format(H.SAVED, n))
        return true
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[H.WORD] = function() api.Open() end
        if type(diag.help) == "table" then diag.help[H.WORD] = H.HELP end
    end

    k:Module({
        name = H.NAME,
        needs = { "client", "store", "bus" },
        provides = { Open = api.Open, Close = api.Close, Shown = api.Shown, Staged = api.Staged },
        start = function(c)
            ctx = c
            ctx.bus:on(H.NAME, "PLAYER_REGEN_DISABLED", function()
                if on then api.Close(H.FIGHT) end
            end)
        end,
        stop = function()
            api.Close()
            if handle then handle.close() end
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.hoverBind = H.Declare(ns, ns.diag)

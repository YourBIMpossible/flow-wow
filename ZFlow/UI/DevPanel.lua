-- Dev panel: a small movable box of build and state text, for development
-- builds. It is the first thing this addon draws, and it is there to prove
-- frame creation, text, dragging and a saved place on the real client.
--
-- This file decides what the panel says and where it stands. It makes no
-- frame: the client boundary does (client.panel), and a client that cannot
-- make one leaves this file with nothing to do and nothing saved.
--
-- Like the diagnostic collector it runs when the load guard has paused the
-- addon: a paused addon says why on the panel. It only reads, apart from
-- its own place and shown / hidden flag, kept per account:
--   layout.devPanel = { point = { anchor, relative anchor, x, y }, hidden = true }
-- Both are left out at their defaults. The point has the shape and rules of
-- the arrows' saved points (Nav/ArrowLayout.lua).
--
--   <slash> panel          show or hide it
--   <slash> panel reset    back to where it first stood
local _, ns = ...

local DevPanel = {}
ns.DevPanel = DevPanel

DevPanel.WIDTH, DevPanel.HEIGHT = 250, 84
DevPanel.DEFAULT_POINT = { "TOPLEFT", "TOPLEFT", 20, -160 }
DevPanel.PATH = "layout.devPanel"
DevPanel.REFRESH = 1 -- seconds between rewrites of the text while it is shown

-- What is saved, read safely: { point = a usable point or nil, hidden = bool }.
function DevPanel.Saved(k)
    local raw = k.store:get("account", DevPanel.PATH)
    if type(raw) ~= "table" then raw = {} end
    return { point = ns.Nav.ClampPoint(raw.point), hidden = raw.hidden == true }
end

-- Where the panel stands for that saved data on a screen of that size: the
-- saved point, else the default, moved back onto the screen when its size
-- is known and left exactly as it is when it is not.
function DevPanel.Position(saved, screenW, screenH)
    local w, h = DevPanel.WIDTH, DevPanel.HEIGHT
    return ns.Nav.ClampPoint(saved and saved.point, w, screenW, screenH, h)
        or ns.Nav.ClampPoint(DevPanel.DEFAULT_POINT, w, screenW, screenH, h)
end

-- The text, top to bottom. diag is what Diag.Start returned, or nil.
function DevPanel.Lines(k, diag)
    local client, id = k.client, k.id
    local version = client.version(id.addon)
    local lines = { id.title .. (version and (" " .. version) or "") }
    if k.paused then
        lines[#lines + 1] = "Paused: " .. tostring(k.pausePanel and k.pausePanel.text or "no reason given")
    else
        lines[#lines + 1] = "State: " .. tostring(k.phase)
    end
    if diag then
        local errors = type(diag.timing) == "table" and diag.timing.errors or {}
        local times = 0
        for i = 1, #errors do times = times + (tonumber(errors[i].count) or 0) end
        lines[#lines + 1] = "Lua errors: " .. #errors .. (times > #errors and (" (" .. times .. " times)") or "")
        lines[#lines + 1] = "Snapshots: " .. (tonumber(k.store:get("account", "diag.count")) or 0)
    end
    lines[#lines + 1] = "Problems: " .. k.problems:count()
    -- nil: the client could not tell. That is not "out of combat".
    local combat = client.inCombat()
    lines[#lines + 1] = combat == nil and "Combat unknown" or (combat and "In combat" or "Out of combat")
    return lines
end

-- Starts the panel on kernel k. diag (optional) is what Diag.Start returned:
-- its counts are shown and its slash command gains the word "panel".
-- Returns { panel = the client's handle or nil, refresh = fn }.
function DevPanel.Start(k, diag)
    local client, id = k.client, k.id
    local panel = client.panel({ name = id.framePrefix .. "DevPanel",
        width = DevPanel.WIDTH, height = DevPanel.HEIGHT })
    -- Not ready until the client has loaded saved data: before that a read
    -- sees nothing and a write is thrown away.
    local ready, hidden = false, false
    local cancelTick

    local function refresh()
        if not panel or not ready then return end
        local ok, lines = pcall(DevPanel.Lines, k, diag)
        if ok then panel.setLines(lines) else k.problems:add("devpanel", "lines", lines) end
    end

    -- The text is rewritten on a slow tick of the client's own, not the
    -- scheduler's: a paused addon has no scheduler. Only while shown.
    local function tick(on)
        if on and not cancelTick then
            local since = 0
            cancelTick = client.onFrame(function(elapsed)
                since = since + (tonumber(elapsed) or 0)
                if since >= DevPanel.REFRESH then
                    since = 0
                    refresh()
                end
            end)
        elseif not on and cancelTick then
            cancelTick()
            cancelTick = nil
        end
    end

    local function show()
        refresh()
        panel.show(not hidden)
        tick(not hidden)
    end

    local function write(saved)
        local value = {}
        if saved.point then value.point = saved.point end
        if saved.hidden then value.hidden = true end
        local ok, reason = k.store:set("account", DevPanel.PATH, next(value) and value or nil)
        if not ok then k.problems:add("devpanel", "save", reason) end
        return ok
    end

    local function apply()
        ready = true
        local saved = DevPanel.Saved(k)
        hidden = saved.hidden
        panel.place(DevPanel.Position(saved, client.screen()))
        show()
    end

    if panel then
        panel.show(false)
        panel.onMoved(function(point)
            if not ready then return end
            local w, h = client.screen()
            local to = ns.Nav.ClampPoint(point, DevPanel.WIDTH, w, h, DevPanel.HEIGHT)
            if not to then return end
            local saved = DevPanel.Saved(k)
            saved.point = to
            write(saved)
            panel.place(to)
        end, function(err) k.problems:add("devpanel", "drag", err) end)
        -- Saved data is in by login. Entering the world is taken too: by
        -- then the kernel has loaded or paused whatever order the login
        -- listeners ran in, and a later one (a zone change) puts the panel
        -- back on a screen whose size has changed.
        client.listen("PLAYER_LOGIN", apply)
        client.listen("PLAYER_ENTERING_WORLD", apply)
        client.listen("PLAYER_REGEN_DISABLED", refresh)
        client.listen("PLAYER_REGEN_ENABLED", refresh)
    end

    if diag and type(diag.commands) == "table" then
        diag.commands.panel = function(rest)
            if not panel then
                client.print(id.title .. ": this client cannot draw the panel.")
            elseif not ready then
                client.print(id.title .. ": the panel is not ready until login.")
            elseif rest == "reset" then
                local saved = DevPanel.Saved(k)
                saved.point = nil
                write(saved)
                panel.place(DevPanel.Position(saved, client.screen()))
                client.print(id.title .. ": panel back to its first place.")
            elseif rest == "" then
                local saved = DevPanel.Saved(k)
                saved.hidden = not saved.hidden
                write(saved)
                hidden = saved.hidden
                show()
                client.print(id.title .. ": panel " .. (hidden and "hidden." or "shown."))
            else
                client.print(id.title .. ": " .. id.slash .. " panel, or " .. id.slash .. " panel reset.")
            end
        end
        if type(diag.help) == "table" then diag.help.panel = "show or hide the dev panel; panel reset puts it back" end
    end

    return { panel = panel, refresh = refresh }
end

-- The addon's own panel, made when this file loads and placed at login.
ns.devPanel = DevPanel.Start(ns, ns.diag)

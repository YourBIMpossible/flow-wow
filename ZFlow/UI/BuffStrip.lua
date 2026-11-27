local _, ns = ...

-- BuffStrip (old-Flow parity R6): your own class buffs with the time left,
-- in a small strip under the player frame. A buff close to running out says
-- so, and one that ran out stays named for a while, so a new player knows
-- which buff to cast again and when. LOOK ONLY: it casts nothing and holds
-- no spell; the buff button (Rotation/FlowButton.lua) is where a buff is
-- cast, by the player's own click.
--
-- Which buffs: the class pack's own list, options.selfBuffs.rows (read,
-- never changed). What is on you and for how long: client.playerBuffs().
-- A buff the game gives no time for shows as on, with no time; a read that
-- did not answer hides the strip, it is never shown as "missing".
--
-- The strip is shown only while it has something to say: a class buff on
-- you, or one that just ran out. A buff counts as run out only when it was
-- last seen with BuffStrip.SOON seconds or less: one you replaced or
-- clicked off is not nagged about.
--
-- Where: under the player frame (client.frameRect), until the player drags
-- it; the dragged place is saved (account, BuffStrip.PATH).
--
--   BuffStrip.Time(seconds) -> "12 min" | "40 s" | nil (no time to show)
--   BuffStrip.Rows(names, buffs, gone, peaks) -> { { name, left, soon, gone, full } }
--   BuffStrip.Children(rows, about, icons) -> the kit parts
--   BuffStrip.Dock(rect, screenW, screenH, height) -> point | nil
--   BuffStrip.Declare(k) -> api;  api.Refresh(), api.Shown(), api.rows()
--   ns.use(BuffStrip.NAME) -> { Rows = api.rows, Shown = api.Shown }
--
-- Not seen in game: where the strip stands against the real player frame,
-- and whether every class buff here is in the game's buff list by the name
-- the class pack uses.

local B = ns.BuffStrip or {}
ns.BuffStrip = B

B.NAME = "buffStrip"
B.ID = "buffStrip"
B.SETTING = "combat.buffStrip"
B.PATH = "layout.buffStrip"
B.FRAME = "PlayerFrame"
B.HEADER = "Your buffs"
B.EVERY = 1
B.SOON = 60
B.KEEP = 120
B.GAP = 4
B.WIDTH, B.HEAD, B.ROW = 220, 34, 30
B.BAR = 18     -- the room a timed buff's bar stands in (bar and its gap)
B.ON = "on"
B.SOON_TEXT = "Runs out soon. Cast it again."
B.GONE = "ran out"
B.GONE_TEXT = "Cast it again."
B.LABEL = "Show your class buffs and their time left"
-- Owner's report (lead section 561 item 6): "I have no idea what these are
-- or why they're there." The strip says what it is in one line every time
-- it shows (lead section 578 point A), and it can be closed: closing it
-- switches the setting off and one chat line says how to turn it back on,
-- by the click and by the word.
B.ABOUT = "Your own class buffs and the time each has left. Close this to switch it off."
B.CLOSED = "\"%s\" is switched off. To show it again, left-click the minimap button (or type %s"
    .. " settings) and turn on \"%s\" under Combat."
B.ABOUT_ROWS = 2     -- rows of room for the one line, which may wrap
B.HELP = "A small strip under your player frame lists your own class buffs with the time left, and names one that ran out so you can cast it again."

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function B.Time(seconds)
    if not finite(seconds) or seconds < 0 then return nil end
    if seconds >= 3600 then return string.format("%d h", math.floor(seconds / 3600 + 0.5)) end
    if seconds >= 90 then return string.format("%d min", math.floor(seconds / 60 + 0.5)) end
    return string.format("%d s", math.floor(seconds + 0.5))
end

-- names: the class buffs, in the pack's order. buffs: client.playerBuffs()
-- ({ [name] = seconds left, math.huge (no end) or true (time not known) }).
-- gone: { [name] = true } for those that ran out. peaks: { [name] =
-- seconds }, the longest time each buff has been seen with — a timed
-- row carries it as `full`, the bar's full length. Up first, then run
-- out.
function B.Rows(names, buffs, gone, peaks)
    local out = {}
    if type(names) ~= "table" or type(buffs) ~= "table" then return out end
    for _, name in ipairs(names) do
        local left = type(name) == "string" and buffs[name] or nil
        if left ~= nil and left ~= false then
            local secs = finite(left) and left or nil
            local row = { name = name, left = secs, soon = secs ~= nil and secs <= B.SOON }
            if secs ~= nil and type(peaks) == "table" then
                local peak = peaks[name]
                if finite(peak) and peak > 0 then row.full = peak end
            end
            out[#out + 1] = row
        end
    end
    if type(gone) == "table" then
        for _, name in ipairs(names) do
            if type(name) == "string" and gone[name] == true and buffs[name] == nil then
                out[#out + 1] = { name = name, gone = true }
            end
        end
    end
    return out
end

-- The buff bar (all-windows row 2): one row per buff with the spell's
-- own icon; a timed buff has the time at its right and a thin bar
-- under it that drains (the bar's words are the time left); an aura
-- stands faded with "on"; one that ran out says what to do where its
-- timer was, and stands dimmed. No header repeats the title — the
-- window's title already says "Your buffs".
-- about: the one line that says what the strip is, or nil — it stands
-- last, faded. icons: { [name] = texture }, or nil.
function B.Children(rows, about, icons)
    local kids = {}
    local function iconOf(name)
        if type(icons) == "table" then return icons[name] end
        return nil
    end
    for i, r in ipairs(type(rows) == "table" and rows or {}) do
        if r.gone then
            kids[#kids + 1] = { kind = "line", key = "buff" .. i, text = tostring(r.name),
                icon = iconOf(r.name), right = B.GONE_TEXT, tone = "bad", enabled = false }
        elseif r.left ~= nil then
            local line = { kind = "line", key = "buff" .. i, text = tostring(r.name),
                icon = iconOf(r.name), right = B.Time(r.left) or B.ON }
            if r.soon then line.tone, line.sub = "warn", B.SOON_TEXT end
            kids[#kids + 1] = line
            local full = r.full
            if not finite(full) or full <= 0 then full = r.left end
            local bar = { kind = "bar", key = "bar" .. i, text = B.Time(r.left) or B.ON,
                value = r.left, max = full }
            if r.soon then bar.tone = "warn" end
            kids[#kids + 1] = bar
        else
            kids[#kids + 1] = { kind = "fadedLine", key = "buff" .. i, text = tostring(r.name),
                icon = iconOf(r.name), right = B.ON }
        end
    end
    if type(about) == "string" and about ~= "" then
        kids[#kids + 1] = { kind = "fadedLine", key = "about", text = about, wrap = true }
    end
    return kids
end

function B.Height(rows, about)
    local n = 0
    for _, r in ipairs(type(rows) == "table" and rows or {}) do
        n = n + B.ROW
        if r.left ~= nil and not r.gone then n = n + B.BAR end
    end
    if type(about) == "string" and about ~= "" then n = n + B.ABOUT_ROWS * B.ROW end
    return B.HEAD + n
end

-- Under the frame, left edges in line. nil when the frame or the screen is
-- not read or there is no room under it: the strip keeps its own place.
function B.Dock(rect, screenW, screenH, height)
    if type(rect) ~= "table" or not (finite(rect.l) and finite(rect.r) and finite(rect.b) and finite(rect.t)) then
        return nil
    end
    if not (finite(screenW) and finite(screenH) and finite(height)) then return nil end
    if rect.r <= rect.l or rect.t <= rect.b then return nil end
    local top = rect.b - B.GAP
    if top - height < 0 or B.WIDTH > screenW then return nil end
    return { "TOPLEFT", "BOTTOMLEFT", math.max(0, math.min(rect.l, screenW - B.WIDTH)), top }
end

function B.Declare(k)
    local api = {}
    local ctx, handle, rows
    local seen, gone = {}, {}
    local peak = {}         -- { [name] = seconds }: the longest time seen

    local function ask(name, ...)
        local c = ctx and ctx.client
        if type(c) ~= "table" or type(c[name]) ~= "function" then return nil end
        local got = { pcall(c[name], ...) }
        if not got[1] then return nil end
        return got[2], got[3]
    end

    local function names()
        local class = ask("class")
        local pack = type(ns.Packs) == "table" and type(class) == "string" and ns.Packs[class] or nil
        local own = type(pack) == "table" and type(pack.options) == "table" and pack.options.selfBuffs or nil
        return type(own) == "table" and type(own.rows) == "table" and own.rows or nil
    end

    local function hide()
        rows = nil
        if handle and handle.shown() then handle.close() end
    end

    -- What ran out: on last time with little left, not on now. The
    -- longest time each buff has been seen with is kept beside it, as
    -- the bar's full length; it goes when the run-out note does.
    local function track(list, buffs, now)
        for _, name in ipairs(list) do
            local left = buffs[name]
            if left ~= nil and left ~= false then
                seen[name] = finite(left) and left or false
                if finite(left) and (peak[name] == nil or left > peak[name]) then peak[name] = left end
                gone[name] = nil
            else
                if finite(seen[name]) and seen[name] <= B.SOON + B.EVERY and finite(now) then gone[name] = now end
                seen[name] = nil
                if gone[name] ~= nil and (not finite(now) or now - gone[name] > B.KEEP) then
                    gone[name] = nil
                    peak[name] = nil
                end
            end
        end
        local out = {}
        for name in pairs(gone) do out[name] = true end
        return out
    end

    -- The spell's own picture for a buff name, the read the buff
    -- button uses; nil when the game does not answer.
    local function icons(list)
        local out = {}
        for _, name in ipairs(list) do
            local id = ask("spellId", name)
            if id ~= nil then
                local tex = ask("spellTexture", id)
                if type(tex) == "string" then out[name] = tex end
            end
        end
        return out
    end

    local function open(tree, height)
        local c = ctx.client
        if type(c.kitWindow) ~= "function" then return false end
        if handle then
            handle.update(tree)
            handle.show(true)
            return true
        end
        local id = k.id or ns.id
        local saved = k.store:get("account", B.PATH)
        local point, width = ns.Kit.Place(saved, tree)
        if type(saved) ~= "table" then
            local w, h = ask("screen")
            point = B.Dock(ask("frameRect", B.FRAME), w, h, height) or point
        end
        handle = c.kitWindow(B.ID, tree, {
            name = id.framePrefix .. "BuffStrip",
            point = point, width = width, height = height,
            onMoved = function(at)
                if type(at) ~= "table" then return end
                local ok, why = k.store:set("account", B.PATH, { point = { at[1], at[2], at[3], at[4] } })
                if not ok then k.problems:add(B.NAME, "place", tostring(why)) end
            end,
            -- Closed by the player: the setting goes off, so it stays
            -- closed, and one line says how to get it back.
            onClose = function()
                local ok, why = ctx.settings:set(B.SETTING, false)
                if ok == false then
                    k.problems:add(B.NAME, "close", tostring(why))
                    return
                end
                if type(c.print) == "function" then
                    c.print(id.title .. ": " .. B.CLOSED:format(B.HEADER, tostring(id.slash), B.LABEL))
                end
            end,
            failed = function(err) k.problems:add(B.NAME, "draw", tostring(err)) end,
        })
        if not handle then
            k.problems:add(B.NAME, "window", "the client could not draw the window")
            return false
        end
        handle.show(true)
        return true
    end

    function api.Refresh()
        if not ctx then return end
        if ctx.settings:get(B.SETTING) == false then return hide() end
        local list, buffs = names(), ask("playerBuffs")
        if type(list) ~= "table" or type(buffs) ~= "table" or ask("dead") == true then return hide() end
        rows = B.Rows(list, buffs, track(list, buffs, ask("now")), peak)
        if #rows == 0 then return hide() end
        -- Every time it shows it says what it is (section 578 point A).
        local about = B.ABOUT
        local height = B.Height(rows, about)
        local tree, why = ns.Kit.Window({ id = B.ID, title = (k.id or ns.id).title .. ": " .. B.HEADER,
            width = B.WIDTH, height = height, closable = true, escape = false, children = B.Children(rows, about, icons(list)) })
        if not tree then
            k.problems:add(B.NAME, "tree", tostring(why))
            return
        end
        open(tree, height)
    end

    function api.Shown() return handle ~= nil and handle.shown() == true end
    function api.rows() return rows end

    k:Setting({ key = B.SETTING, scope = "account", type = "bool", default = true,
        label = B.LABEL, group = "combat", help = B.HELP,
        synonyms = { "buff", "buffs", "reminder", "time left", "player frame", "strip" } })

    k:Module({
        name = B.NAME,
        needs = { "client", "store", "settings" },
        provides = { Rows = api.rows, Shown = api.Shown },
        ticks = { { every = B.EVERY, when = "always", run = function() api.Refresh() end } },
        start = function(c) ctx = c end,
        stop = function()
            if handle then handle.close() end
            seen, gone, peak, rows = {}, {}, {}, nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.buffStrip = B.Declare(ns)

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
--   BuffStrip.Rows(names, buffs, gone) -> { { name, left, soon, gone } }
--   BuffStrip.Children(rows) -> the kit parts
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
B.ON = "on"
B.SOON_TEXT = "Runs out soon. Cast it again."
B.GONE = "ran out"
B.GONE_TEXT = "Cast it again."
B.LABEL = "Show your class buffs and their time left"
-- Owner's report (lead section 561 item 6): "I have no idea what these are
-- or why they're there." The strip says what it is in one line the first
-- time it shows (this session only; B.EXPLAINED keeps that it was said),
-- and it can be closed: closing it switches the setting off and one chat
-- line says how to turn it back on.
B.ABOUT = "Your own class buffs and the time each has left. Close this to switch it off."
B.CLOSED = "\"%s\" is switched off. To show it again, open the settings (%s settings) and turn on \"%s\" under Combat."
B.EXPLAINED = "layout.explained.buffStrip"
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
-- gone: { [name] = true } for those that ran out. Up first, then run out.
function B.Rows(names, buffs, gone)
    local out = {}
    if type(names) ~= "table" or type(buffs) ~= "table" then return out end
    for _, name in ipairs(names) do
        local left = type(name) == "string" and buffs[name] or nil
        if left ~= nil and left ~= false then
            local secs = finite(left) and left or nil
            out[#out + 1] = { name = name, left = secs, soon = secs ~= nil and secs <= B.SOON }
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

-- about: the one line that says what the strip is, or nil.
function B.Children(rows, about)
    local kids = { { kind = "header", key = "header", title = B.HEADER } }
    if type(about) == "string" and about ~= "" then
        kids[#kids + 1] = { kind = "line", key = "about", text = about, wrap = true }
    end
    for i, r in ipairs(type(rows) == "table" and rows or {}) do
        local line = { kind = "line", key = "buff" .. i, text = tostring(r.name) }
        if r.gone then
            line.right, line.tone, line.sub = B.GONE, "bad", B.GONE_TEXT
        else
            line.right = B.Time(r.left) or B.ON
            if r.soon then line.tone, line.sub = "warn", B.SOON_TEXT end
        end
        kids[#kids + 1] = line
    end
    return kids
end

function B.Height(rows, about)
    local n = type(rows) == "table" and #rows or 0
    if type(about) == "string" and about ~= "" then n = n + B.ABOUT_ROWS end
    return B.HEAD + n * B.ROW
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
    local about            -- nil: not looked up yet; false: said before; else the line
    local seen, gone = {}, {}

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

    -- What ran out: on last time with little left, not on now.
    local function track(list, buffs, now)
        for _, name in ipairs(list) do
            local left = buffs[name]
            if left ~= nil and left ~= false then
                seen[name] = finite(left) and left or false
                gone[name] = nil
            else
                if finite(seen[name]) and seen[name] <= B.SOON + B.EVERY and finite(now) then gone[name] = now end
                seen[name] = nil
                if gone[name] ~= nil and (not finite(now) or now - gone[name] > B.KEEP) then gone[name] = nil end
            end
        end
        local out = {}
        for name in pairs(gone) do out[name] = true end
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
        rows = B.Rows(list, buffs, track(list, buffs, ask("now")))
        if #rows == 0 then return hide() end
        -- The first time it shows it says what it is, for this session.
        if about == nil then
            about = false
            local okE, said = pcall(k.store.get, k.store, "account", B.EXPLAINED)
            if okE and said ~= true then
                about = B.ABOUT
                pcall(k.store.set, k.store, "account", B.EXPLAINED, true)
            end
        end
        local height = B.Height(rows, about)
        local tree, why = ns.Kit.Window({ id = B.ID, title = (k.id or ns.id).title .. ": " .. B.HEADER,
            width = B.WIDTH, height = height, closable = true, escape = false, children = B.Children(rows, about) })
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
            seen, gone, rows = {}, {}, nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.buffStrip = B.Declare(ns)

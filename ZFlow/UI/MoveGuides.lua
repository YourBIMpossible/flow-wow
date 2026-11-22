local _, ns = ...

-- Alignment guides while the player moves Z-Flow's things on the screen
-- (S29): the middle of the screen both ways, and the edges and middle of the
-- other things that are on the screen. Closer than SNAP pixels lines up; at
-- the release the thing settles exactly on the line.
--
-- The pure core is ported from legacy Flow's Modules/MoveGuides.lua
-- (0.35.327 and 0.35.330), which ran on this client: the same marks, the
-- same nearest rule, the same snap and line reach. Research:
-- WoW/from-plexy/RESEARCH-move-guides.md. The module at the end draws the
-- lines while the rotation icon or an arrow is Ctrl-dragged and snaps at the
-- release, through three client reads added at the end of Core/Client.lua
-- (frameRect, watchMoves, guideLines; the screen from client.screen); the handles that move
-- the frames are not changed. Setting ui.moveGuides, on by default.
--
--   MoveGuides.Lines(snap, screen) -> x, ylo, yhi, y, xlo, xhi
--   MoveGuides.Declare(k) -> api   (api.watched() -> { [frame name] = true })
--
--   MoveGuides.Marks(rect) -> xs { l, c, r }, ys { b, c, t }
--   MoveGuides.Nearest(mine, theirs, snap) -> move, at, src   (nil: none near)
--   MoveGuides.Snap(rect, screen, others, snap) -> { dx, dy, x, y, xSrc, ySrc, rect }
--   MoveGuides.Span(lo1, hi1, lo2, hi2, reach) -> from, to
--   MoveGuides.Visible(rects, moving) -> others: the rectangles to line up with
--
--   rect    { l, r, b, t } in the screen's own units; `middle = true` offers
--           only its middle (a frame whose box the player cannot see)
--   screen  { w, h }
-- A rectangle with any side that is not a plain number is left out, never
-- guessed.
local G = {}
ns.MoveGuides = G

G.SNAP = 8      -- pixels: closer than this lines up
G.REACH = 14    -- how far a line to another thing runs past the two

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function usable(r)
    return type(r) == "table" and finite(r.l) and finite(r.r) and finite(r.b) and finite(r.t)
end

function G.Marks(r)
    return { r.l, (r.l + r.r) / 2, r.r }, { r.b, (r.b + r.t) / 2, r.t }
end

function G.Nearest(mine, theirs, snap)
    snap = finite(snap) and snap or G.SNAP
    local best, bestAt, bestSrc
    for _, m in ipairs(mine or {}) do
        for _, at in ipairs(theirs or {}) do
            local v = type(at) == "table" and at.v or at
            if finite(v) and finite(m) then
                local d = v - m
                if math.abs(d) <= snap and (not best or math.abs(d) < math.abs(best)) then
                    best, bestAt, bestSrc = d, v, type(at) == "table" and at.src or nil
                end
            end
        end
    end
    return best, bestAt, bestSrc
end

function G.Snap(rect, screen, others, snap)
    if not usable(rect) then return nil end
    local xs, ys = {}, {}
    if type(screen) == "table" and finite(screen.w) and finite(screen.h) then
        xs[1], ys[1] = screen.w / 2, screen.h / 2
    end
    for _, o in ipairs(type(others) == "table" and others or {}) do
        if usable(o) then
            local ox, oy = G.Marks(o)
            for i = 1, 3 do
                if not o.middle or i == 2 then
                    xs[#xs + 1] = { v = ox[i], src = o }
                    ys[#ys + 1] = { v = oy[i], src = o }
                end
            end
        end
    end
    local mx, my = G.Marks(rect)
    local dx, x, xSrc = G.Nearest(mx, xs, snap)
    local dy, y, ySrc = G.Nearest(my, ys, snap)
    return { dx = dx or 0, dy = dy or 0, x = x, y = y, xSrc = xSrc, ySrc = ySrc, rect = rect }
end

function G.Span(lo1, hi1, lo2, hi2, reach)
    reach = finite(reach) and reach or G.REACH
    return math.min(lo1, lo2) - reach, math.max(hi1, hi2) + reach
end

-- What the moving thing may line up with: every other rectangle handed in
-- that is usable, by name. Legacy Flow's 0.35.330 lesson: only what is on
-- the screen, never the thing being moved, and never something docked to it
-- (rect.dockedTo == moving).
--   rects   { [name] = rect }   moving   the name of the thing being moved
function G.Visible(rects, moving)
    local names = {}
    for name in pairs(type(rects) == "table" and rects or {}) do
        if type(name) == "string" then names[#names + 1] = name end
    end
    table.sort(names)
    local out = {}
    for _, name in ipairs(names) do
        local r = rects[name]
        if name ~= moving and usable(r) and r.dockedTo ~= moving then
            out[#out + 1] = { l = r.l, r = r.r, b = r.b, t = r.t, middle = r.middle == true, name = name }
        end
    end
    return out
end

-- Where the two lines go for a snap (G.Snap's answer): x, ylo, yhi, y, xlo,
-- xhi, each pair nil when nothing lines up that way. A line to another
-- thing runs past both (G.Span); one to the screen's middle crosses the
-- whole screen.
function G.Lines(s, screen)
    if type(s) ~= "table" or not usable(s.rect) then return nil end
    local r, x, ylo, yhi, y, xlo, xhi = s.rect, nil, nil, nil, nil, nil, nil
    local sw = type(screen) == "table" and finite(screen.w) and finite(screen.h)
    if finite(s.x) then
        if usable(s.xSrc) then
            x = s.x
            ylo, yhi = G.Span(r.b + s.dy, r.t + s.dy, s.xSrc.b, s.xSrc.t)
        elseif sw then
            x, ylo, yhi = s.x, 0, screen.h
        end
    end
    if finite(s.y) then
        if usable(s.ySrc) then
            y = s.y
            xlo, xhi = G.Span(r.l + s.dx, r.r + s.dx, s.ySrc.l, s.ySrc.r)
        elseif sw then
            y, xlo, xhi = s.y, 0, screen.w
        end
    end
    return x, ylo, yhi, y, xlo, xhi
end

-------------------------------------------------------------------------------
-- The module: lines while the player Ctrl-drags the rotation icon or an
-- arrow, and the snap at the release. The frames are found by the names
-- their handles give them (UI/RotationIcon.lua, UI/Arrow.lua); an arrow
-- offers only its middle, as in legacy Flow (its box cannot be seen).
-- Frames that do not exist yet are looked for again every RETRY seconds,
-- up to TRIES times (an arrow is made when it is first needed).
-------------------------------------------------------------------------------
G.NAME = "moveGuides"
G.SETTING = "ui.moveGuides"
G.RETRY, G.TRIES = 5, 24
G.FRAMES = {
    { key = "RotationIcon" },
    { key = "QuestArrow", middle = true },
    { key = "ProfArrow", middle = true },
}

function G.Declare(k)
    local api = {}
    local ctx, lines, tries = nil, nil, 0
    local watched = {}
    function api.watched() return watched end

    local function on() return ctx ~= nil and ctx.settings:get(G.SETTING) == true end

    local function rects()
        local out = {}
        for _, fr in ipairs(G.FRAMES) do
            local name = k.id.framePrefix .. fr.key
            local r = ctx.client.frameRect(name)
            if type(r) == "table" then
                r.middle = fr.middle == true
                out[name] = r
            end
        end
        return out
    end

    local function screen()
        local w, h = ctx.client.screen()
        if type(w) == "number" and type(h) == "number" then return { w = w, h = h } end
        return nil
    end

    local function snap(name, rect)
        local all = rects()
        local mine = all[name]
        local others = G.Visible(all, name)
        -- Not the thing the moving one hangs from either.
        if mine and mine.dockedTo then
            local kept = {}
            for _, o in ipairs(others) do
                if o.name ~= mine.dockedTo then kept[#kept + 1] = o end
            end
            others = kept
        end
        return G.Snap(rect, screen(), others)
    end

    local function moved(name, rect)
        if not lines then return end
        if not on() then lines.hide() return end
        local s = snap(name, rect)
        local x, ylo, yhi, y, xlo, xhi = G.Lines(s, screen())
        if x == nil and y == nil then lines.hide() return end
        lines.show(x, ylo, yhi, y, xlo, xhi)
    end

    local function dropped(name, rect)
        if lines then lines.hide() end
        if not on() then return 0, 0 end
        local s = snap(name, rect)
        if not s then return 0, 0 end
        return s.dx, s.dy
    end

    local function hook()
        local missing = false
        for _, fr in ipairs(G.FRAMES) do
            local name = k.id.framePrefix .. fr.key
            if not watched[name] then
                local ok = type(ctx.client.watchMoves) == "function"
                    and ctx.client.watchMoves(name, function(r) moved(name, r) end, function(r) return dropped(name, r) end)
                if ok then watched[name] = true else missing = true end
            end
        end
        tries = tries + 1
        if missing and tries < G.TRIES then ctx.sched:after(G.NAME, G.RETRY, hook) end
    end

    k:Module({
        name = G.NAME,
        needs = { "client", "settings", "sched" },
        settings = { {
            key = G.SETTING, scope = "account", type = "bool", default = true,
            label = "Alignment lines while you Ctrl-drag the arrows or the rotation icon",
            help = "While you move one, a line shows when it lines up with the middle of the screen or with the other one; "
                .. "let go near a line and it settles on it.",
            group = "Other",
        } },
        provides = { Watched = api.watched },
        start = function(c)
            ctx = c
            if type(c.client.guideLines) == "function" then lines = c.client.guideLines() end
            tries = 0
            hook()
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.moveGuides = G.Declare(ns)

-- Arrow views: one small table per arrow, made by one factory (P5, PR A),
-- and the pure layout sums for stacked and separate arrows (P5, PR B's
-- first half: nothing calls those yet).
--
-- Today there are two arrows: the quest arrow (the solid one in front, the
-- frame FlowNavArrow) and the profession arrow (the long faint needle drawn
-- behind it). This file builds their frames; Nav.lua's buildArrow puts the
-- clicks, the drag and the tooltips on them, and its updateProf tells the
-- profession view what to show. Nothing about how they look or behave is
-- decided here that Nav.lua did not decide before: same frames, same sizes,
-- same anchors, same order.
--
--   local V = N:ArrowView(key)   -- "quest" or "professions"; built once
--   V.key, V.frame
--   V.pointer                    -- the full pointer        (quest)
--   V.needle, V.ring             -- the long faint pointer  (professions)
--   V.text, V.sub, V.hit
--   V:Show(look) / V:Hide()
--
-- N.arrowFrame is the quest view's frame and N.arrowFrame.prof the
-- profession view's frame, as before: every older reader keeps working.

local _, ns = ...
local N = ns.nav
if not N then return end

N.ARROW_LEADER = "quest"                       -- the arrow that carries the stack
N.ARROW_SIZE = 56
N.ARROW_DEFAULT_POINT = { "TOP", "TOP", 0, -120 }
N.PROF_HOLDER_ALPHA = 0.85                     -- the profession arrow: a little see-through
N.STACK_SNAP = 40                              -- drop an arrow this near the leader: it stacks
N.ARROW_BESIDE_GAP = 8

-------------------------------------------------------------------------------
-- The views
-------------------------------------------------------------------------------

-- A view's parts live on its frame under the names older code reads
-- (f.arrow, f.prof.arrow, ...). The view reads them from there each time, so
-- a part that is rebuilt (N:SetArrowStyle swaps the pointers) is never stale.
local PARTS = {
    quest = { pointer = "arrow", text = "text", sub = "sub", hit = "textHit" },
    professions = { needle = "arrow", ring = "ring", text = "text", hit = "hit" },
}

local View = {}

function View:Hide() self.frame:Hide() end

-- look: what to draw. The quest view takes none (Nav.lua's update draws on
-- its frame directly). The profession view: { mode = "arrow" | "ring" | "off"
-- (N.ProfArrowMode), angle = radians when mode is "arrow", text = its line,
-- or nil for no text }.
function View:Show(look)
    local h = self.frame
    if self.key == "professions" and look then
        h.mode = look.mode
        if h.ring then h.ring:SetShown(look.mode == "ring") end
        if look.mode == "arrow" then
            h.arrow:SetRotation(look.angle)
            h.arrow:Show()
        else
            h.arrow:Hide()
        end
        if look.text then
            h.text:SetText(look.text)
            h.text:Show(); h.hit:Show()
        else
            h.text:Hide(); h.hit:Hide()
        end
    end
    h:Show()
end

local viewMeta = {
    __index = function(v, k)
        local m = View[k]
        if m ~= nil then return m end
        local part = PARTS[rawget(v, "key")]
        part = part and part[k]
        if part then return rawget(v, "frame")[part] end
        return nil
    end,
}

local views = {}

-- Builds both arrows' frames, in the order Nav.lua always built them.
local function build()
    local ring = N.ARROW_RING
    local f = CreateFrame("Button", "FlowNavArrow", UIParent)
    f:SetSize(N.ARROW_SIZE, N.ARROW_SIZE)
    f:SetFrameStrata("HIGH")
    local p = ns.db.nav.point
    if p then f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        local d = N.ARROW_DEFAULT_POINT
        f:SetPoint(d[1], UIParent, d[2], d[3], d[4])
    end
    -- The faint profession needle sits under the main arrow (a lower frame
    -- level, a little see-through), its step name and distance in small grey
    -- text above, opposite the main arrow's text.
    f.prof = CreateFrame("Frame", nil, f)
    f.prof:SetAllPoints(f)
    f.prof:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))
    f.prof:SetAlpha(N.PROF_HOLDER_ALPHA)
    f.prof.arrow = N:MakeProfArrow(f.prof)
    -- At the profession step: a faint see-through ring where the arrow was,
    -- with none of the main arrow's beam or bouncing icon (those mean "your
    -- main step").
    f.prof.ring = f.prof:CreateTexture(nil, "BACKGROUND", nil, 2)
    f.prof.ring:SetTexture(ring.texture)
    f.prof.ring:SetBlendMode("ADD")
    f.prof.ring:SetSize(ring.w, ring.h)
    f.prof.ring:SetPoint("CENTER", f.prof, "CENTER", 0, ring.y)
    f.prof.ring:SetAlpha(N.PROF_RING_ALPHA)
    f.prof.ring:Hide()
    f.prof.text = f.prof:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.prof.text:SetPoint("BOTTOM", f, "TOP", 0, N.NeedleClearance(f))
    f.prof.text:SetWidth(260)
    f.prof.text:SetWordWrap(false)
    do local c = ns.theme.muted; f.prof.text:SetTextColor(c[1], c[2], c[3]) end
    f.prof:Hide()
    f.arrow = N:MakeArrow(f)
    N.arrowFrame = f
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.text:SetPoint("TOP", f, "BOTTOM", 0, -2)
    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.sub:SetPoint("TOP", f.text, "BOTTOM", 0, -2)
    -- (Its script, the lines stacked by length, is set in Nav.lua.)
    f.linesDriver = CreateFrame("Frame", nil, f)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    -- The text under the arrow (step name, distance) clicks like the arrow.
    f.textHit = CreateFrame("Button", nil, f)
    f.textHit:SetPoint("TOP", f, "BOTTOM", 0, 0)
    f.textHit:SetSize(240, 34)
    f.textHit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- The faint arrow's text: its own click area.
    f.prof.hit = CreateFrame("Button", nil, f.prof)
    f.prof.hit:SetPoint("BOTTOM", f, "TOP", 0, N.NeedleClearance(f) - 2)
    f.prof.hit:SetSize(240, 16)
    f.prof.hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    views.quest = setmetatable({ key = "quest", frame = f }, viewMeta)
    views.professions = setmetatable({ key = "professions", frame = f.prof }, viewMeta)
end

-- The view for one arrow. Built the first time, the same one afterwards;
-- nil for a key Flow has no arrow for.
function N:ArrowView(key)
    if not PARTS[key] then return nil end
    if not views[key] then build() end
    return views[key]
end

-------------------------------------------------------------------------------
-- Pure layout (plain tables in, plain tables out; no frame, no saved data
-- written, no game call). The frame code of PR B carries out what these say.
--
--   saved = { point = nav.point, arrows = nav.arrows, profArrowText = nav.profArrowText }
--     arrows = { mode = "stacked" | "separate" (nil: stacked),
--                points = { [key] = { a, r, x, y } }, hidden = { [key] = true },
--                text = { [key] = bool } }
--   lanes = { { key, order, hasStep, overlay, mode }, ... }
--     mode: what N.ProfArrowMode said for a stacked needle ("arrow" / "ring" /
--     "off"); nil counts as "arrow".
--   ctx   = { gate, screenW, screenH, size, defaultPoint, keys, snap }
--     keys: the arrows other than the leader, for N.ArrowApply.
-------------------------------------------------------------------------------

-- Why no arrow may show, from the arrow update's early returns, in their
-- order: "off" (switched off, not revealed yet, or no position), "intro"
-- (the login intro is playing on the leader), "corpse" (dead), else "open".
function N.ArrowGate(enabled, revealShown, intro, hasPos, dead)
    if not enabled or not revealShown then return "off" end
    if intro then return "intro" end
    if not hasPos then return "off" end
    if dead then return "corpse" end
    return "open"
end

-- Dropped within `snap` of the leader, centre to centre (dx, dy apart)?
function N.StackSnap(dx, dy, snap)
    snap = snap or N.STACK_SNAP
    return (dx or 0) ^ 2 + (dy or 0) ^ 2 < snap * snap
end

-- Where on a box an anchor name sits: share of the width, share of the height.
local SPOT = {
    TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 },
    LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
    BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}

-- The left and bottom edge of a size x size arrow saved at `point` on a
-- screenW x screenH screen; nil when that can't be worked out.
local function corner(point, size, screenW, screenH)
    if not (point and screenW and screenH) then return nil end
    local a, r = SPOT[point[1]], SPOT[point[2] or point[1]]
    if not (a and r) then return nil end
    return r[1] * screenW + (point[3] or 0) - a[1] * size,
           r[2] * screenH + (point[4] or 0) - a[2] * size
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end

-- A saved point brought back on screen: the same anchors, moved just far
-- enough that the whole arrow shows. Always a new table.
function N.ClampPoint(point, size, screenW, screenH)
    if not point then return nil end
    size = size or N.ARROW_SIZE
    local out = { point[1], point[2] or point[1], point[3] or 0, point[4] or 0 }
    local left, bottom = corner(out, size, screenW, screenH)
    if not left then return out end
    local toLeft = math.min(math.max(left, 0), math.max(0, screenW - size))
    local toBottom = math.min(math.max(bottom, 0), math.max(0, screenH - size))
    out[3], out[4] = out[3] + (toLeft - left), out[4] + (toBottom - bottom)
    return out
end

-- Where an arrow with no place of its own first lands: beside the leader,
-- on the right unless the leader is at the right edge (N.DrawerSide's edges),
-- never on top of it and never under it, where its text and toggles hang.
function N.ArrowBeside(leaderPoint, size, screenW, screenH)
    size = size or N.ARROW_SIZE
    local step = size + N.ARROW_BESIDE_GAP
    local lp = leaderPoint or N.ARROW_DEFAULT_POINT
    local left, bottom = corner(lp, size, screenW, screenH)
    if not left then return { lp[1], lp[2] or lp[1], (lp[3] or 0) + step, lp[4] or 0 } end
    local side = N.DrawerSide(left, bottom, size, size, screenW, screenH, size, size)
    if side ~= "left" and left + step + size > screenW then side = "left" end
    left = left + (side == "left" and -step or step)
    return N.ClampPoint({ "BOTTOMLEFT", "BOTTOMLEFT", left, bottom }, size, screenW, screenH)
end

local function textOn(saved, key)
    local t = saved.arrows and saved.arrows.text
    if t and t[key] ~= nil then return t[key] and true or false end
    if key == "professions" then return saved.profArrowText ~= false end
    return true
end

local function byOrder(a, b)
    if (a.order or 0) ~= (b.order or 0) then return (a.order or 0) < (b.order or 0) end
    return tostring(a.key) < tostring(b.key)
end

-- What is on screen: one entry per lane given.
--   shown      bool
--   anchor     "screen" (at `point`) or "leader" (on the leader's frame)
--   point      { a, r, x, y } on screen, already clamped; nil when on the leader
--   look       "pointer" (a full arrow), "needle" (the long faint one behind
--              the leader) or "text" (a line only)
--   behind     drawn behind the leader, one frame level lower
--   small      the leader, shrunk over a stacked needle
--   scale, alpha    what that comes to
--   colourRule "quest" (the quest arrow's colour meanings) or "profession"
--              (the one faint colour, ns.theme.profPointer)
--   emphasis   "primary" (the leader) or "secondary"
--   text       its text shows
function N.ArrowLayout(saved, lanes, ctx)
    saved, ctx = saved or {}, ctx or {}
    local arrows = saved.arrows or {}
    local hidden, points = arrows.hidden or {}, arrows.points or {}
    local separate = arrows.mode == "separate"
    local gate = ctx.gate or "open"
    local size = ctx.size or N.ARROW_SIZE
    local sw, sh = ctx.screenW, ctx.screenH
    local stackPoint = N.ClampPoint(saved.point or ctx.defaultPoint or N.ARROW_DEFAULT_POINT, size, sw, sh)
    local order, leader = {}, nil
    for _, lane in ipairs(lanes or {}) do
        if lane.key == N.ARROW_LEADER then leader = lane else order[#order + 1] = lane end
    end
    table.sort(order, byOrder)

    local out = {}
    -- The leader: the corpse and the intro are drawn on it whatever the
    -- route holds; otherwise it needs a step or an overlay, and not to be hidden.
    local leaderShown = false
    if leader then
        if gate == "intro" or gate == "corpse" then
            leaderShown = true
        elseif gate == "open" then
            leaderShown = not hidden[leader.key] and (leader.hasStep or leader.overlay) and true or false
        end
        out[leader.key] = {
            shown = leaderShown, anchor = "screen", point = stackPoint, look = "pointer",
            behind = false, small = false, scale = 1, alpha = 1,
            colourRule = "quest", emphasis = "primary", text = textOn(saved, leader.key),
        }
    end
    -- The others. Only while the gate is open, with a step, and not hidden.
    local needle, standIn = false, false
    for _, lane in ipairs(order) do
        local key = lane.key
        local L = {
            shown = gate == "open" and not hidden[key] and lane.hasStep and true or false,
            behind = false, small = false, scale = 1, alpha = N.PROF_HOLDER_ALPHA,
            emphasis = "secondary", text = textOn(saved, key),
        }
        if separate then
            -- Its own place, a full arrow: the quest arrow's colour meanings,
            -- still the fainter of the two.
            L.anchor, L.look, L.colourRule = "screen", "pointer", "quest"
            L.point = N.ClampPoint(points[key], size, sw, sh) or N.ArrowBeside(stackPoint, size, sw, sh)
        elseif gate == "open" and not leaderShown then
            -- Stacked, but nothing to stand behind: the first one is a full
            -- arrow at the stack's place, any more a line of text there.
            L.anchor, L.point, L.colourRule = "screen", stackPoint, "quest"
            L.look = (L.shown and standIn) and "text" or "pointer"
            if L.shown then standIn = true end
        else
            -- Stacked on the leader: the first is the needle behind it, any
            -- more a line of text.
            L.anchor, L.behind, L.colourRule = "leader", true, "profession"
            L.look = (L.shown and needle) and "text" or "needle"
            if L.shown and L.look == "needle" then
                needle = true
                if leader and (lane.mode == nil or lane.mode == "arrow") then
                    local Q = out[leader.key]
                    Q.small, Q.scale, Q.alpha = true, N.ON_NEEDLE_SCALE, N.ON_NEEDLE_ALPHA
                end
            end
        end
        out[key] = L
    end
    return out
end

local function fillPoints(s, ctx)
    local size, sw, sh = ctx.size or N.ARROW_SIZE, ctx.screenW, ctx.screenH
    local stackPoint = N.ClampPoint(s.point or ctx.defaultPoint or N.ARROW_DEFAULT_POINT, size, sw, sh)
    for _, key in ipairs(ctx.keys or {}) do
        if key ~= N.ARROW_LEADER and not s.arrows.points[key] then
            s.arrows.points[key] = N.ArrowBeside(stackPoint, size, sw, sh)
        end
    end
end

-- What a control does: the saved table as it should be afterwards. Always a
-- new table; `saved` is not changed, nothing is written anywhere.
--   { type = "mode", mode = "stacked" | "separate" }   separate: every arrow in ctx.keys gets a place
--   { type = "move", key = k, point = { a, r, x, y } } the leader: the stack moves; another: it stands alone there
--   { type = "drop", key = k, point = ..., leader = { x, y }, at = { x, y } }
--        a drag ended. Within the snap of the leader's centre: it stacks and
--        keeps the place it had. `at` is its centre (worked out from `point`
--        and the screen size when left out). Otherwise the same as "move".
--   { type = "hide", key = k, on = bool }
--   { type = "text", key = k, on = bool }
--   { type = "reset" }                                  stacked, default place, all shown; text switches kept
function N.ArrowApply(saved, action, ctx)
    local s = copy(saved or {})
    action, ctx = action or {}, ctx or {}
    local kind, key = action.type, action.key
    if kind == "reset" then
        s.point = nil
        if s.arrows then s.arrows.mode, s.arrows.points, s.arrows.hidden = nil, nil, nil end
        return s
    end
    s.arrows = s.arrows or {}
    local A = s.arrows
    A.points = A.points or {}
    if kind == "drop" and key and key ~= N.ARROW_LEADER and action.leader then
        local size = ctx.size or N.ARROW_SIZE
        local ax, ay = action.at and action.at[1], action.at and action.at[2]
        if not ax then
            local left, bottom = corner(action.point, size, ctx.screenW, ctx.screenH)
            if left then ax, ay = left + size / 2, bottom + size / 2 end
        end
        if ax and N.StackSnap(ax - action.leader[1], ay - action.leader[2], ctx.snap) then
            A.mode = "stacked"
            return s
        end
        kind = "move"
    elseif kind == "drop" then
        kind = "move"
    end
    if kind == "mode" then
        A.mode = action.mode == "separate" and "separate" or "stacked"
        if A.mode == "separate" then fillPoints(s, ctx) end
    elseif kind == "move" and key and action.point then
        if key == N.ARROW_LEADER then
            s.point = copy(action.point)
        else
            A.points[key] = copy(action.point)
            A.mode = "separate"
            fillPoints(s, ctx)
        end
    elseif kind == "hide" and key then
        A.hidden = A.hidden or {}
        A.hidden[key] = action.on and true or nil
    elseif kind == "text" and key then
        A.text = A.text or {}
        A.text[key] = action.on and true or false
    end
    return s
end

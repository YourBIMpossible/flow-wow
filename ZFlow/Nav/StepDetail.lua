local _, ns = ...

-- Parity row A1-10, the data half (lead section 749): what the arrow's
-- details drawer says, as Flow's Modules/Nav/Nav.lua showPanel (:4169-
-- 4232). Pure: no client read, nothing drawn. From Nav/TripRoute.lua
-- View() ({ stops = { { label, title, detail, details, held, place } } }).
-- View keeps held steps; the arrow walks the first one not held (Flow's
-- drawer reads current.goal, Nav.lua:4177; Zen-3, lead section 753), so
-- that one is the drawer's step; with every step held, the first.
--   SD.Rows(view[, opts]) -> rows, top to bottom, each { kind, text }:
--     "title"     the step's title, when it differs from its label
--     "blocked"   "Blocked: <why>", only when the drawer's own step is held
--                 (Flow's g.blockedBy)
--     "detail"    its detail lines, but not "Quest: ..." or "Objective:
--                 ..." (as Flow)
--     "then"      "Then (N steps)": the other steps (Flow also gave the
--                 yards; View() carries none)
--     "stop"      "  i. <label>" by route place, up to the 10th, a held one
--                 with its reason: "  1. <label> (<why>)"
--     "more"      "  ..." when there are more
--     "along"     "Along the way", then "alongItem" rows: opts.along, the
--                 things to pick up as you go (Flow's N.alongGoals; Z-Flow
--                 has no such list yet: a LEAD NEED)
-- The left click that opens it is UI/Arrow.lua's (the lead's); the drawing
-- is the drawing lane's (a MUSE NEED). Flow's colours, its air, port, ride
-- and hearth hints and its closing hint line are left to those.
-- Not tested in game.
ns.Nav = ns.Nav or {}
local SD = {}
ns.Nav.StepDetail = SD

SD.LAST = 10       -- as Flow: the 2nd to the 10th step, then "..."
SD.THEN = "Then (%d steps)"
SD.BLOCKED = "Blocked: %s"
SD.ALONG = "Along the way"
SD.MORE = "  ..."

local function text(v)
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

local function shown(line)
    return not line:find("^Quest: ") and not line:find("^Objective: ")
end

function SD.Rows(view, opts)
    local rows = {}
    local list = nil
    if type(view) == "table" and type(view.stops) == "table" then list = view.stops end
    if not list or #list == 0 then return rows end
    local function add(kind, words) rows[#rows + 1] = { kind = kind, text = words } end
    local at = 1
    for i, st in ipairs(list) do
        if type(st) == "table" and (st.held == nil or st.held == false) then
            at = i
            break
        end
    end
    local s = list[at]
    if type(s) == "table" then
        local title = text(s.title)
        if title and title ~= s.label then add("title", title) end
        local held = s.held
        if held ~= nil and held ~= false then add("blocked", SD.BLOCKED:format(tostring(held))) end
        local d = text(s.detail)
        if d and shown(d) then add("detail", d) end
        if type(s.details) == "table" then
            for _, l in ipairs(s.details) do
                if text(l) and shown(l) then add("detail", l) end
            end
        end
    end
    if #list > 1 then
        add("then", SD.THEN:format(#list - 1))
        for i = 1, #list do
            if i > SD.LAST then
                add("more", SD.MORE)
                break
            end
            if i ~= at then
                local st = list[i]
                local label = "?"
                if type(st) == "table" and text(st.label) then label = st.label end
                local line = "  " .. i .. ". " .. label
                if type(st) == "table" and st.held ~= nil and st.held ~= false then
                    line = line .. " (" .. tostring(st.held) .. ")"
                end
                add("stop", line)
            end
        end
    end
    local along = nil
    if type(opts) == "table" and type(opts.along) == "table" then along = opts.along end
    if along and #along > 0 then
        add("along", SD.ALONG)
        for _, a in ipairs(along) do
            local words = "?"
            if type(a) == "table" then words = text(a.text) or text(a.title) or "?" end
            add("alongItem", "  " .. words)
        end
    end
    return rows
end

local _, ns = ...

-- RecipeColours: the colour each learned recipe had in this player's own
-- profession window, by the skill it was seen at. Lead section 413.
--
-- The profession plan (Items/ProfPlan.lua) only counts a recipe as worth a
-- skill point when its colour at the player's skill is saved under
--   char "learned.recipeColors"[recipe][difficulty] = { lo, hi }
-- and until now nothing in the add-on wrote that: only tests did. In the
-- game the plan therefore never named a craft, and the profession arrow
-- only ever said "Open your ... window once" or, at the cap, the trainer.
-- This is the writer.
--
-- When a profession window answers (client.recipes(), else the classic
-- client.tradeSkillRows()), each learned recipe in it with a name and a
-- colour (optimal, medium, easy, trivial) is saved as seen at the window's
-- skill: that colour's span is widened to hold the skill. A colour only
-- goes down as skill goes up, so a harder colour saved at or above this
-- skill is cut to end below it, and an easier one saved at or below it to
-- start above it. A read that changes nothing writes nothing.
--
-- Read at once when the window opens (TRADE_SKILL_SHOW) and when its list
-- changes (TRADE_SKILL_LIST_UPDATE: a craft that gave a point), so the plan
-- has the new skill's colours with the new skill, and once more
-- RecipeColours.SETTLE seconds after the last of them, for a window that
-- was not ready at the event.
--
--   RecipeColours.Seen(saved, name, difficulty, skill) -> changed
--     pure but for the saved table it writes into
--   RecipeColours.Read(client, store) -> report { ok, reason, seen, changed }
--   RecipeColours.Declare(k) -> api   (api.last())
--   ns.use(RecipeColours.NAME) -> { Last }
--
-- This only reads the client and saves what the player's own window
-- showed: no recipe, colour or skill range is shipped. Not tested in game.
local RecipeColours = ns.RecipeColours or {}
ns.RecipeColours = RecipeColours

RecipeColours.NAME = "recipeColours"
RecipeColours.PATH = "learned.recipeColors"
RecipeColours.SHOW = "TRADE_SKILL_SHOW"
RecipeColours.EVENT = "TRADE_SKILL_LIST_UPDATE"
RecipeColours.CLOSE = "TRADE_SKILL_CLOSE"
RecipeColours.SETTLE = 1
-- Hardest first: a recipe moves down this list as skill rises.
RecipeColours.ORDER = { "optimal", "medium", "easy", "trivial" }

local RANK = {}
for i, d in ipairs(RecipeColours.ORDER) do RANK[d] = i end

local function whole(n)
    return type(n) == "number" and n == n and n < math.huge and n == math.floor(n) and n >= 0
end

local function span(s)
    return type(s) == "table" and whole(s.lo) and whole(s.hi) and s.lo <= s.hi
end

function RecipeColours.Seen(saved, name, difficulty, skill)
    if type(saved) ~= "table" or type(name) ~= "string" or name == "" then return false end
    local rank = RANK[difficulty]
    if rank == nil or not whole(skill) then return false end
    local changed = false
    local spans = saved[name]
    if type(spans) ~= "table" then
        spans = {}
        saved[name] = spans
        changed = true
    end
    for _, d in ipairs(RecipeColours.ORDER) do
        local s = spans[d]
        if d == difficulty then
            if not span(s) then
                spans[d] = { lo = skill, hi = skill }
                changed = true
            elseif skill < s.lo then
                s.lo = skill
                changed = true
            elseif skill > s.hi then
                s.hi = skill
                changed = true
            end
        elseif s ~= nil then
            if not span(s) then
                spans[d] = nil
                changed = true
            elseif RANK[d] < rank and s.hi >= skill then
                -- A harder colour ends below the skill this one was seen at.
                if s.lo >= skill then spans[d] = nil else s.hi = skill - 1 end
                changed = true
            elseif RANK[d] > rank and s.lo <= skill then
                -- An easier colour starts above it.
                if s.hi <= skill then spans[d] = nil else s.lo = skill + 1 end
                changed = true
            end
        end
    end
    return changed
end

local function ask(client, read)
    if type(client) ~= "table" or type(client[read]) ~= "function" then return nil end
    local ok, v = pcall(client[read])
    if ok and type(v) == "table" then return v end
    return nil
end

-- The open window as { skill, rows = { { name, difficulty } } }, the modern
-- read first; nil when no window answers with a skill.
local function window(client)
    local m = ask(client, "recipes")
    if m ~= nil and whole(m.skill) and type(m.recipes) == "table" and #m.recipes > 0 then
        local rows = {}
        for _, r in ipairs(m.recipes) do
            if type(r) == "table" and r.learned == true then rows[#rows + 1] = r end
        end
        return { skill = m.skill, rows = rows }
    end
    local c = ask(client, "tradeSkillRows")
    if c ~= nil and whole(c.skill) and type(c.rows) == "table" then
        return { skill = c.skill, rows = c.rows }
    end
    return nil
end

local function copy(t)
    local out = {}
    for name, spans in pairs(t) do
        if type(name) == "string" and type(spans) == "table" then
            local o = {}
            for d, s in pairs(spans) do
                if RANK[d] ~= nil and span(s) then o[d] = { lo = s.lo, hi = s.hi } end
            end
            out[name] = o
        end
    end
    return out
end

function RecipeColours.Read(client, store)
    local report = { seen = 0, changed = false }
    local w = window(client)
    if w == nil then
        report.ok, report.reason = false, "no profession window answered"
        return report
    end
    if type(store) ~= "table" or type(store.get) ~= "function" or type(store.set) ~= "function" then
        report.ok, report.reason = false, "the recipe colours cannot be saved"
        return report
    end
    local cur = store:get("char", RecipeColours.PATH)
    local saved = copy(type(cur) == "table" and cur or {})
    for _, r in ipairs(w.rows) do
        if type(r) == "table" and type(r.name) == "string" and r.name ~= "" and RANK[r.difficulty] ~= nil then
            report.seen = report.seen + 1
            if RecipeColours.Seen(saved, r.name, r.difficulty, w.skill) then report.changed = true end
        end
    end
    if report.changed and store:set("char", RecipeColours.PATH, saved) ~= true then
        report.ok, report.reason = false, "the recipe colours cannot be saved"
        return report
    end
    report.ok = true
    return report
end

function RecipeColours.Declare(k)
    local api = {}
    local last, pending
    function api.last() return last end
    local function cancel()
        if pending then pending() end
        pending = nil
    end
    k:Module({
        name = RecipeColours.NAME,
        needs = { "client", "store", "bus", "sched" },
        provides = { Last = api.last },
        start = function(ctx)
            local function read()
                last = RecipeColours.Read(ctx.client, ctx.store)
            end
            local function heard()
                cancel()
                read()
                pending = ctx.sched:after(RecipeColours.NAME, RecipeColours.SETTLE, function()
                    pending = nil
                    read()
                end)
            end
            ctx.bus:on(RecipeColours.NAME, RecipeColours.SHOW, heard)
            ctx.bus:on(RecipeColours.NAME, RecipeColours.EVENT, heard)
            ctx.bus:on(RecipeColours.NAME, RecipeColours.CLOSE, cancel)
        end,
        stop = cancel,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.recipeColours = RecipeColours.Declare(ns)

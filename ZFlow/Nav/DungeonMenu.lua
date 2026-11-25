local _, ns = ...
-- The arrow menu's "Dungeons" section (FLOW-PARITY B-53), the logic half: a
-- port of legacy Flow's Modules/Nav/Dungeons.lua D:MenuItems and runMenu
-- (:1829-1898). The menu itself is UI/ArrowMenu.lua's (lead-owned), which
-- lists these items and passes a click's action back; nothing here draws.
-- Pure Lua 5.1: no client calls, no saved data.
--
-- Everything shown comes from the player's Questie and log (the dungeon
-- pane, Nav/DungeonRead.lua R.Pane) and the player's own measured XP rate
-- (Nav/DungeonVisit.lua RateLine); owner section 611.
--
--   DM.Counts(pane) -> { on, missing, inside, total }
--     on: "log" rows; missing: "pickup" rows; inside: "inside" rows
--   DM.CountText(counts) -> "2 of 6 in your log"
--   DM.Section(state) -> items
--     state = { reading, list = { { key, name, counts, rate } }, prepared }
--     a run row: { text, tipLines, checked, action = "open", key }
--   DM.RunItems(run, s) -> items
--     s = { prepared, only, entrance }
--     actions: "only" (route: only this run, checked while on it),
--       "prepare" or "cancel", "entrance" (straight to the entrance;
--       disabled with no entrance known)
-- Flow's "Include long lead-ins", "Ask my group" and "Share quests" rows
-- are left out: no lead-in choice exists here, and the two group rows act
-- in chat (FLOW-PARITY B-51, held).
local DM = {}
ns.DungeonMenu = DM

DM.TITLE = "Dungeons"
DM.READING = "Reading Questie's dungeons..."
DM.NONE = "No dungeon quests at your level"
DM.MAX_RUNS = 6
DM.ONLY = "Route: only this run (its quest givers, then the entrance)"
DM.PREPARE = "Prepare this run"
DM.CANCEL = "Cancel this run"
DM.ENTRANCE = "Straight to the entrance"

local function count(g)
    if type(g) == "table" and type(g.rows) == "table" then return #g.rows end
    return 0
end

function DM.Counts(pane)
    local c = { on = 0, missing = 0, inside = 0 }
    local groups = type(pane) == "table" and type(pane.groups) == "table" and pane.groups or {}
    for _, g in ipairs(groups) do
        if type(g) == "table" then
            if g.id == "log" then c.on = c.on + count(g)
            elseif g.id == "pickup" then c.missing = c.missing + count(g)
            elseif g.id == "inside" then c.inside = c.inside + count(g) end
        end
    end
    c.total = c.on + c.missing + c.inside
    return c
end

function DM.CountText(c)
    c = type(c) == "table" and c or {}
    return string.format("%d of %d in your log", tonumber(c.on) or 0, tonumber(c.total) or 0)
end

local function tipLines(run)
    local c = type(run.counts) == "table" and run.counts or {}
    local out = { tostring(run.name) }
    out[#out + 1] = string.format("- %d in your log", tonumber(c.on) or 0)
    out[#out + 1] = string.format("- %d to pick up outside", tonumber(c.missing) or 0)
    if (tonumber(c.inside) or 0) > 0 then out[#out + 1] = string.format("- %d start inside", c.inside) end
    if type(run.rate) == "string" then out[#out + 1] = run.rate end
    return out
end

function DM.Section(state)
    state = type(state) == "table" and state or {}
    local items = { { sep = true }, { title = true, text = DM.TITLE } }
    if state.reading == true or type(state.list) ~= "table" then
        items[#items + 1] = { text = DM.READING, disabled = true }
        return items
    end
    if #state.list == 0 then
        items[#items + 1] = { text = DM.NONE, disabled = true }
        return items
    end
    for i, run in ipairs(state.list) do
        if i > DM.MAX_RUNS then break end
        items[#items + 1] = { text = string.format("%s: %s", tostring(run.name), DM.CountText(run.counts)),
            tipLines = tipLines(run), checked = state.prepared ~= nil and state.prepared == run.key,
            action = "open", key = run.key }
    end
    return items
end

function DM.RunItems(run, s)
    if type(run) ~= "table" then return {} end
    s = type(s) == "table" and s or {}
    local items = { { title = true, text = tostring(run.name) } }
    for i, line in ipairs(tipLines(run)) do
        if i > 1 then items[#items + 1] = { text = line, disabled = true } end
    end
    items[#items + 1] = { sep = true }
    items[#items + 1] = { text = DM.ONLY, action = "only", checked = s.prepared == true and s.only == true }
    if s.prepared == true then
        items[#items + 1] = { text = DM.CANCEL, action = "cancel" }
    else
        items[#items + 1] = { text = DM.PREPARE, action = "prepare" }
    end
    items[#items + 1] = { text = DM.ENTRANCE, action = "entrance", disabled = s.entrance ~= true }
    return items
end

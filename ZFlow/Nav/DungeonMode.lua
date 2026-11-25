local _, ns = ...
-- The dungeon route's line under the arrow and its choices (FLOW-PARITY
-- B-50), the logic half: a port of legacy Flow's Modules/Nav/Dungeons.lua
-- ModeText (:1593), Counts/CountLines (:1569-1590) and ModeItems (:1600).
-- While a dungeon run is prepared, one line under the arrow says it, and
-- clicking it opens a few choices. Showing the line is UI/Arrow.lua's (a
-- lead-owned hook) and drawing the menu is Muse's; this file only says
-- what they show. Pure Lua 5.1: no client calls, no saved data.
--
--   M.Line(name, on, done, total) -> line | nil
--     name: the prepared run (nil: none); on: you walk only its steps;
--     done, total: its quests done and in all
--   M.CountLines(name, counts) -> lines
--     counts = { done, on, missing, inside }
--   M.Items(state) -> items
--     state = { name, on, prep, canAsk, counts }; nil or no name: {}
--     each item: { title = true, text } | { text, disabled = true }
--       | { sep = true } | { text, action[, checked] }
--     action: "leave" (back to your usual route; the run is kept),
--       "back" (only this run's steps), "ask" (ask your group in chat who
--       has its quests: FLOW-PARITY B-51, held, so only with canAsk),
--       "prep" (get ready on the way, checked by prep), "cancel".
local M = {}
ns.DungeonMode = M

M.RUN = "Dungeon run"
M.LEAVE = "Leave the dungeon route (back to your usual route; the run is kept)"
M.BACK = "Back on the dungeon route (only this run's steps)"
M.ASK = "Ask my group in chat who has its quests"
M.PREP = "Get ready on the way: training, selling and repairs, your bank"
M.CANCEL = "Cancel this run"

function M.Line(name, on, done, total)
    if type(name) ~= "string" then return nil end
    if on ~= true then return string.format("%s prepared (your usual route)", name) end
    return string.format("Dungeon route: %s, %d of %d", name, tonumber(done) or 0, tonumber(total) or 0)
end

local function quests(n)
    if n == 1 then return "1 quest" end
    return n .. " quests"
end

function M.CountLines(name, counts)
    local c = type(counts) == "table" and counts or {}
    local done, on = tonumber(c.done) or 0, tonumber(c.on) or 0
    local missing, inside = tonumber(c.missing) or 0, tonumber(c.inside) or 0
    local out = { type(name) == "string" and name or M.RUN }
    out[#out + 1] = string.format("- %s completed", quests(done))
    out[#out + 1] = string.format("- You're on %s", quests(on))
    local outside = ""
    if missing > 0 then outside = " (to pick up outside)" end
    out[#out + 1] = string.format("- You're missing %s%s", quests(missing), outside)
    if inside == 1 then
        out[#out + 1] = "- 1 starts inside the dungeon"
    elseif inside > 1 then
        out[#out + 1] = string.format("- %d start inside the dungeon", inside)
    end
    out[#out + 1] = string.format("- %s in all", quests(done + on + missing + inside))
    return out
end

function M.Items(state)
    if type(state) ~= "table" or type(state.name) ~= "string" then return {} end
    local items = { { title = true, text = state.name } }
    if type(state.counts) == "table" then
        for i, line in ipairs(M.CountLines(state.name, state.counts)) do
            if i > 1 then items[#items + 1] = { text = line, disabled = true } end
        end
        items[#items + 1] = { sep = true }
    end
    if state.on == true then
        items[#items + 1] = { text = M.LEAVE, action = "leave" }
    else
        items[#items + 1] = { text = M.BACK, action = "back" }
    end
    if state.canAsk == true then items[#items + 1] = { text = M.ASK, action = "ask" } end
    items[#items + 1] = { text = M.PREP, action = "prep", checked = state.prep == true }
    items[#items + 1] = { text = M.CANCEL, action = "cancel" }
    return items
end

local _, ns = ...
-- The dungeon key badge (FLOW-PARITY B-55), the logic half: a port of
-- legacy Flow's Modules/Nav/Dungeons.lua status() (:1907-1927). A small
-- badge by the quest list shows a run worth doing, or the one prepared:
-- its XP ratio as "2.5x", a tooltip, and a click that prepares or cancels
-- it. Drawing the badge is Muse's; nothing here draws. Pure Lua 5.1.
--
-- The ratio is the player's own measured one (Nav/DungeonVisit.lua
-- V.Ratio: this character's last run of that dungeon against its questing
-- XP per hour), so a run never measured shows "?" and is never suggested;
-- owner section 611. Flow estimated unmeasured runs; that is left out.
--
--   B.Best(list) -> the run with the highest measured ratio, or nil
--     list: { { key, name, ratio } }
--   B.Status(s) -> badge | nil
--     s = { inside, prepared = run, best = run, solo, tip = lines }
--     badge = { key, text, tone ("good" | "muted"), tip, action
--               ("prepare" | "cancel"), clickText }
local B = {}
ns.DungeonBadge = B

B.PREPARE = "Prepare this run"
B.CANCEL = "Cancel this run"
B.NEEDS_GROUP = "Needs a group."
B.UNKNOWN = "?"

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function B.Best(list)
    local best
    for _, run in ipairs(type(list) == "table" and list or {}) do
        if type(run) == "table" and finite(run.ratio) and run.ratio > 0 then
            if not best or run.ratio > best.ratio then best = run end
        end
    end
    return best
end

function B.Status(s)
    if type(s) ~= "table" or s.inside == true then return nil end
    local run, action, clickText = s.prepared, "cancel", B.CANCEL
    if type(run) ~= "table" then run, action, clickText = s.best, "prepare", B.PREPARE end
    if type(run) ~= "table" or run.key == nil then return nil end
    local text = B.UNKNOWN
    if finite(run.ratio) then text = string.format("%.1fx", run.ratio) end
    local tip = {}
    for _, line in ipairs(type(s.tip) == "table" and s.tip or {}) do tip[#tip + 1] = line end
    local tone = "good"
    if s.solo == true then
        tone = "muted"
        tip[#tip + 1] = B.NEEDS_GROUP
    end
    return { key = run.key, text = text, tone = tone, tip = tip, action = action, clickText = clickText }
end

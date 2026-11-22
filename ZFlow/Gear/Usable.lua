local _, ns = ...

-- Can you use this piece of gear, by what the game itself reports (G12).
-- Pure: the list of requirements the game marks as not met on the item's
-- tooltip comes in as data, in the game's own words; nothing here reads the
-- game and no class table is consulted.
--
--   answer = GearUsable.Check(unmet)
--   answer = GearUsable.Best(clientAnswer, packAnswer)
--   text   = GearUsable.Clean(text)
--
--   unmet   the requirement lines the game marks as not met for you ("Plate",
--           "Requires Level 40"), as a list. An empty list: the game marks
--           nothing. Not a list: the marks were not read.
--   answer  the shape Gear/CanUse.lua gives, so Gear/Tooltip.lua takes
--           either: { can, why, reason, source }
--     can     true (nothing marked), false (something marked), nil (not read)
--     why     "ok", "client" or "unknown"
--     reason  from GearUsable.REASON; for a no, followed by the game's own
--             lines, the first GearUsable.MAX of them, then "and N more"
--     source  "client" on an answer made from the game's marks
--
-- The game marks a kind your class can never use and a skill you have not
-- trained in the same way, so this cannot tell them apart and does not try:
-- the line shows the game's words.
--
-- Clean: the game's text made safe to show: colour codes taken off, spaces
-- trimmed. nil for anything that is not text, is empty, or still holds a
-- bar or a control character. A mark that cannot be shown still counts.
--
-- Best: which answer the verdict goes by. The game's own, when it was read
-- (yes or no); else the class pack's table (Gear/CanUse.lua), which is a
-- first guess: its no is shown, labelled so on the line; its yes is not
-- taken (it cannot know a skill you have not trained) and reads "not
-- confirmed by the game"; else "not known".

local U = {}
ns.GearUsable = U

U.MAX = 3

U.REASON = {
    ok = "the game marks nothing you lack",
    unmet = "the game marks in red",
    marked = "the game marks a requirement you do not meet",
    unread = "what the game requires for it was not read",
    unconfirmed = "not confirmed by the game: what it marks on the item was not read",
}
local R = U.REASON

function U.Clean(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" or text:find("[|%c]") then return nil end
    return text
end

function U.Check(unmet)
    if type(unmet) ~= "table" then
        return { can = nil, why = "unknown", reason = R.unread }
    end
    local shown, seen, hidden = {}, {}, 0
    for i = 1, #unmet do
        local text = U.Clean(unmet[i])
        if not text then
            hidden = hidden + 1
        elseif not seen[text] then
            seen[text] = true
            shown[#shown + 1] = text
        end
    end
    if #shown == 0 and hidden == 0 then
        return { can = true, why = "ok", reason = R.ok, source = "client" }
    end
    if #shown == 0 then
        return { can = false, why = "client", reason = R.marked, source = "client" }
    end
    local first = {}
    for i = 1, math.min(#shown, U.MAX) do first[i] = shown[i] end
    local more = #shown - #first + hidden
    local reason = R.unmet .. ": " .. table.concat(first, "; ")
    if more > 0 then reason = reason .. " and " .. more .. " more" end
    return { can = false, why = "client", reason = reason, source = "client" }
end

function U.Best(clientAnswer, packAnswer)
    if type(clientAnswer) == "table" and clientAnswer.can ~= nil then return clientAnswer end
    if type(packAnswer) == "table" then
        -- The table says what a class can ever equip. It does not know a
        -- weapon skill you have not trained, or armour you learn later, so
        -- its yes alone is not a yes. Its no stands, with its label.
        if packAnswer.can == true then
            return { can = nil, why = "unknown", reason = R.unconfirmed }
        end
        return packAnswer
    end
    if type(clientAnswer) == "table" then return clientAnswer end
    return { can = nil, why = "unknown", reason = R.unread }
end

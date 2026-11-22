local _, ns = ...

-- The "what would be done with it" line of an item tooltip (G4), as text.
-- Pure: a decision from Items/Disposition.lua comes in, lines go out.
-- Nothing here decides anything, reads the game or touches an item.
--
--   lines = TooltipDisposition.Lines(decision[, more])
--
--   decision  what Disposition.Decide answered: { action, count, reason,
--             basis, reasons, rest }
--   more      { bank }: a bank note for the item from whoever picks what to
--             bank. A string is the reason; true is a note with no reason.
--             Disposition has no "bank" action of its own.
--   lines     { { text, tone } ... }, or nil for what is not a decision.
--
-- What is said:
--   keep      "Keep: <every keep reason, the deciding one first>", up to
--             TooltipDisposition.MAX of them, then "and N more"
--   anything else   "Would sell: <reason>", "Would auction: ...", "Would
--             disenchant: ...", "Would equip: ...". "Would", because the
--             line is a look at the decision: nothing is done, and whether
--             anything ever is done for the player is a setting elsewhere,
--             off by default.
--   basis     a recommendation is marked "(suggested)" and a decision made
--             with nothing known "(not known)". A choice of yours or a fact
--             the game states is not marked.
--   split     a decision that keeps part and does something else with the
--             rest (decision.rest) gives one line for each part, with its
--             count where the count is known: "Keep 8: ...", "Would sell
--             4: ...". No count is shown on a decision that is not split,
--             and none is made up.
--   a reason that is not plain text (empty, not a string, or holding a bar
--   or a control character) is left out; the action is still said.

local T = {}
ns.TooltipDisposition = T

T.MAX = 4     -- keep reasons listed
T.PARTS = 4   -- parts of a split decision shown

local WORD = {
    keep = "Keep", sell = "Would sell", auction = "Would auction",
    disenchant = "Would disenchant", equip = "Would equip",
}
local TONE = { keep = "same", equip = "good" }
local BASIS = { recommendation = " (suggested)", unknown = " (not known)" }

local function plain(text)
    return type(text) == "string" and text ~= "" and not text:find("[|%c]")
end

local function isCount(n)
    return type(n) == "number" and n == n and n >= 0 and n < math.huge
end

local function isDecision(d)
    return type(d) == "table" and WORD[d.action] ~= nil
end

-- The reasons to show for one part: the deciding one first, each once.
local function reasonsOf(d)
    local out, seen = {}, {}
    local function add(text)
        if plain(text) and not seen[text] then
            seen[text] = true
            out[#out + 1] = text
        end
    end
    add(d.reason)
    if d.action == "keep" and type(d.reasons) == "table" then
        for i = 1, #d.reasons do add(d.reasons[i]) end
    end
    return out
end

local function partLine(d, withCount)
    local text = WORD[d.action]
    if withCount and isCount(d.count) then text = text .. " " .. d.count end
    local reasons = reasonsOf(d)
    if #reasons > 0 then
        local shown = {}
        for i = 1, math.min(#reasons, T.MAX) do shown[i] = reasons[i] end
        text = text .. ": " .. table.concat(shown, "; ")
        if #reasons > #shown then text = text .. " and " .. (#reasons - #shown) .. " more" end
    end
    text = text .. (BASIS[d.basis] or "")
    return { text = text, tone = TONE[d.action] or "none" }
end

function T.Lines(decision, more)
    if not isDecision(decision) then return nil end
    local split = isDecision(decision.rest)
    local lines, seen, d = {}, {}, decision
    while isDecision(d) and not seen[d] and #lines < T.PARTS do
        seen[d] = true
        lines[#lines + 1] = partLine(d, split)
        d = d.rest
    end
    local bank = type(more) == "table" and more.bank or nil
    if plain(bank) then
        lines[#lines + 1] = { text = "Would bank: " .. bank, tone = "none" }
    elseif bank == true then
        lines[#lines + 1] = { text = "Would bank", tone = "none" }
    end
    return lines
end

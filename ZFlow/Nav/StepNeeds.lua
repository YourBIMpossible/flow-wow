local _, ns = ...
-- Why a quest is locked, in words (FLOW-PARITY A2-17), after legacy Flow's
-- Modules/Nav/Needs.lua ("after Bear Form" on a step that needs something
-- first). Pure Lua 5.1: no client calls, no saved data, no shipped table.
--
-- Where the facts come from (owner section 611): the quest's own Questie
-- fields, read from the player's Questie at runtime: preQuestGroup (every
-- one must be done), preQuestSingle (any one is enough) and requiredSpell
-- (a spell id; a negative one is a spell the player must NOT have, which
-- is not a need and is passed over). Names are the game's and Questie's:
-- ctx.questName(id), ctx.spellName(id). Nothing is said from a list of
-- Flow's.
--
--   SN.Why(q, ctx) -> nil (not locked, or it cannot be told)
--                   | { kind = "quest" | "spell", id, text }
--     q:   a Questie quest ({ Id, preQuestGroup, preQuestSingle, requiredSpell })
--     ctx: { done = fn(id) -> true | false | nil (not known),
--            log = { [id] = true }, questName = fn(id) -> name | nil,
--            spellKnown = fn(id) -> true | false | nil,
--            spellName = fn(id) -> name | nil }
--     An earlier quest is looked at before the spell. A quest or a spell the
--     game does not answer for (nil) never holds a step: the same rule as
--     Nav/RoutePickups.lua P.Candidate, so the two cannot disagree.
--   SN.Line(label, why) -> "label (after ...)" or the label alone
ns.Nav = ns.Nav or {}
local N = ns.Nav
local SN = {}
N.StepNeeds = SN

SN.AFTER = "after %s"
SN.IN_LOG = " (in your log)"
SN.A_QUEST = "an earlier quest"
SN.LEARN = "after you learn %s"
SN.A_SPELL = "a spell"

local function list(v)
    if type(v) == "table" then return v end
    return {}
end

local function call(fn, id)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, id)
    if ok then return v end
    return nil
end

local function questWords(ctx, id)
    local name = call(ctx.questName, id)
    if type(name) ~= "string" or name == "" then return SN.A_QUEST end
    if type(ctx.log) == "table" and ctx.log[id] then return name .. SN.IN_LOG end
    return name
end

function SN.Why(q, ctx)
    if type(q) ~= "table" or type(ctx) ~= "table" then return nil end
    for _, id in ipairs(list(q.preQuestGroup)) do
        if call(ctx.done, id) == false then
            return { kind = "quest", id = id, text = SN.AFTER:format(questWords(ctx, id)) }
        end
    end
    local single = list(q.preQuestSingle)
    if #single > 0 then
        local any, names = false, {}
        for _, id in ipairs(single) do
            if call(ctx.done, id) == false then
                names[#names + 1] = questWords(ctx, id)
            else
                any = true
            end
        end
        if not any then
            return { kind = "quest", id = single[1], text = SN.AFTER:format(table.concat(names, " or ")) }
        end
    end
    local spell = tonumber(q.requiredSpell)
    if spell and spell > 0 and call(ctx.spellKnown, spell) == false then
        local name = call(ctx.spellName, spell)
        if type(name) ~= "string" or name == "" then name = SN.A_SPELL end
        return { kind = "spell", id = spell, text = SN.LEARN:format(name) }
    end
    return nil
end

function SN.Line(label, why)
    if type(why) == "table" and type(why.text) == "string" then
        return tostring(label) .. " (" .. why.text .. ")"
    end
    return tostring(label)
end

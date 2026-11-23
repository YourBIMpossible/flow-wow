local _, ns = ...

-- The gear line of an item tooltip, as text. Pure: the scorer's answer
-- (Gear/Score.lua) and the can-use answer (Gear/CanUse.lua) come in; lines
-- go out. Nothing here touches a tooltip: whoever shows the lines does.
--
--   lines = GearTooltip.Lines(result, use[, opts])
--   what  = GearTooltip.What(result)   the slot it was held up to, in words
--
--   result  what GearScore.Compare answered
--   use     what GearCanUse.Check answered
--   opts    { role }: the role the weights were for, named on the line
--           when it is a non-empty string
--   lines   { { text, tone } ... }, one or two. tone is "good", "same",
--           "bad" or "none", for whoever colours the line.
--
-- What is said, first that holds:
--   you cannot use it     "Can't use: <reason>". Never an upgrade, and no
--                         number, whatever the scorer answered (G12). A
--                         "your class cannot" resting on a table marked
--                         with its evidence says so in brackets.
--   not known whether you can   "No verdict: <reason>". Not a yes.
--   no recommendation     "No verdict: <the scorer's reason>".
--   upgrade / same / worse   the slot it was held up to, and the gain or
--                         loss: whole, or to one decimal place.
-- The scorer's note (dual wield not known) is a second line under a verdict
-- or a "no verdict", not under a "can't use".

local T = {}
ns.GearTooltip = T

-- A gain or loss smaller than this is shown as the same: it would print as
-- +0.0 or -0.0, and fractional weights leave residues that small.
T.SAME = 0.05

T.REASON = {
    result = "the item could not be compared",
    use = "not known whether you can use it",
}

-- The scorer's slot names, in words.
local PLACE = {
    head = "head piece", neck = "neck", shoulder = "shoulders", back = "back", chest = "chest",
    wrist = "wrists", hands = "hands", waist = "waist", legs = "legs", feet = "feet",
    finger1 = "first ring", finger2 = "second ring", trinket1 = "first trinket", trinket2 = "second trinket",
    mainHand = "main hand", offHand = "off hand", ranged = "ranged slot",
}

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function words(v)
    return type(v) == "string" and v ~= ""
end

-- A gain or loss with its sign: "+6", "-8", "+2.3".
local function signed(n)
    local size = math.abs(n)
    local text = size == math.floor(size) and string.format("%d", size) or string.format("%.1f", size)
    return (n < 0 and "-" or "+") .. text
end

local function capital(text)
    return text:sub(1, 1):upper() .. text:sub(2)
end

local function line(text, tone)
    return { text = text, tone = tone }
end

-- What the scorer held the item up to, in words: "your chest", "your main
-- hand and off hand", or "what you wear" for a slot with no name here.
function T.What(result)
    if type(result) ~= "table" then return "what you wear" end
    if result.pair == true then return "your main hand and off hand" end
    local place = PLACE[result.slot]
    if place then return "your " .. place end
    return "what you wear"
end

function T.Lines(result, use, opts)
    if type(use) ~= "table" or use.can == nil then
        local reason = type(use) == "table" and words(use.reason) and use.reason or T.REASON.use
        return { line("No verdict: " .. reason, "none") }
    end
    -- G16: a weapon skill not trained yet (Gear/WeaponSkill.lua): "yet", not "your class".
    if use.can == false and use.why == "untrained" and words(use.reason) then
        return { line("Can't use yet: " .. use.reason, "bad") }
    end
    if use.can ~= true then
        local text = "Can't use: " .. (words(use.reason) and use.reason or T.REASON.use)
        if use.why == "class" and words(use.evidence) then text = text .. " (" .. use.evidence .. ")" end
        return { line(text, "bad") }
    end

    result = type(result) == "table" and result or {}
    local verdict = result.verdict
    -- A gain or loss that would print as 0.0 is the same, not an upgrade.
    if (verdict == "upgrade" or verdict == "worse") and finite(result.delta)
        and math.abs(result.delta) < T.SAME then
        verdict = "same"
    end
    local known = (verdict == "upgrade" or verdict == "same" or verdict == "worse") and finite(result.delta)
    local lines = {}
    if not known then
        local reason = verdict == "none" and words(result.reason) and result.reason or T.REASON.result
        lines[1] = line("No verdict: " .. reason, "none")
    else
        local what = T.What(result)
        local role = type(opts) == "table" and words(opts.role) and opts.role or nil
        if verdict == "same" then
            lines[1] = line("Same as " .. what .. (role and (" (" .. role .. ")") or ""), "same")
        else
            local tail = " (" .. signed(result.delta) .. (role and (", " .. role) or "") .. ")"
            if verdict == "upgrade" then
                lines[1] = line("Upgrade for " .. what .. tail, "good")
            else
                lines[1] = line("Not an upgrade for " .. what .. tail, "bad")
            end
        end
    end
    if words(result.note) then lines[2] = line(capital(result.note), "none") end
    return lines
end

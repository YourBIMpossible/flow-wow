-- Setup suggestions (U-B, G53): on a character's first login with Z-Flow,
-- the advisor (UI/Advisor.lua) offers up to three suggested settings, each
-- as one line of text ending in the exact command that would make it:
--   "<why> Type: /zflow setting <key> on"
--
-- IT CHANGES NOTHING BY ITSELF. The settings are read through the public
-- settings:get only; nothing here sets, resets or applies a setting. The
-- player decides by typing the command. The one write is Z-Flow's own mark
-- that this character has been offered its suggestions, in the character's
-- saved state at Setup.OFFERED_PATH.
--
--   Setup.SUGGESTIONS                  the shipped list, in the order offered:
--                                      { { key =, value =, why = }, ... }
--     key    a setting row's key; a key with no row is never offered
--     value  what to suggest: true/false, a number, or one of a choice
--            row's choices (a text or table row cannot be set from the
--            chat line, so it is never offered)
--     why    one short sentence the player reads before the command
--   Setup.Pick(settings, list) -> picks   pure; at most Setup.MAX picks, in
--                                      list order, each { key, value, why,
--                                      command, text }. Skipped: bad entries,
--                                      keys with no row (get answers nil),
--                                      values already in place, and values
--                                      of another type than the row's.
--   Setup.Command(key, value) -> "/zflow setting <key> <on|off|value>"
--   Setup.Declare(k [, list]) -> api   declares the module on kernel k
--     api.offered()   copies of what this session offered ({} when nothing)
--
-- Offered once per character: a character already marked offers nothing.
-- A login with nothing to offer leaves the character unmarked, so a list
-- shipped later is still offered. The prompts stay on the advisor for the
-- session (ids "setup.<key>").
local _, ns = ...

local Setup = ns.Setup or {}
ns.Setup = Setup

Setup.NAME = "setup"
Setup.MAX = 3
Setup.PRIORITY = 1
Setup.OFFERED_PATH = "state.setup.offered"
-- The slash word comes from Core/Identity.lua (identity rule; lead, U-B merge).
Setup.SLASH = ns.id.slash .. " setting"

-- The shipped suggestions. Which settings to suggest is the lead's and the
-- owner's call; none is chosen here. Each entry is { key, value, why }.
Setup.SUGGESTIONS = {}

local function valid(entry)
    if type(entry) ~= "table" then return false end
    if type(entry.key) ~= "string" or entry.key == "" then return false end
    if type(entry.why) ~= "string" or not entry.why:find("%S") then return false end
    local v = entry.value
    if type(v) == "number" then return v == v and v ~= math.huge and v ~= -math.huge end
    return type(v) == "boolean" or (type(v) == "string" and v:find("%S") ~= nil)
end

function Setup.Command(key, value)
    local word
    if value == true then
        word = "on"
    elseif value == false then
        word = "off"
    else
        word = tostring(value)
    end
    return Setup.SLASH .. " " .. tostring(key) .. " " .. word
end

function Setup.Pick(settings, list)
    local picks = {}
    if type(settings) ~= "table" or type(settings.get) ~= "function" or type(list) ~= "table" then
        return picks
    end
    for _, entry in ipairs(list) do
        if #picks >= Setup.MAX then break end
        if valid(entry) then
            local current = settings:get(entry.key)
            if current ~= nil and type(current) == type(entry.value) and current ~= entry.value then
                local command = Setup.Command(entry.key, entry.value)
                picks[#picks + 1] = {
                    key = entry.key, value = entry.value, why = entry.why,
                    command = command, text = entry.why .. " Type: " .. command,
                }
            end
        end
    end
    return picks
end

-- Declares the module on kernel k, offering from `list` (the shipped
-- Setup.SUGGESTIONS when not given).
function Setup.Declare(k, list)
    local api = {}
    local offered = {}
    function api.offered()
        local out = {}
        for i, p in ipairs(offered) do
            out[i] = { key = p.key, value = p.value, why = p.why, command = p.command, text = p.text }
        end
        return out
    end

    k:Module({
        name = Setup.NAME,
        needs = { "advisor", "store", "settings" },
        provides = { Offered = api.offered },
        start = function(ctx)
            if ctx.store:get("char", Setup.OFFERED_PATH) == true then return end
            local advisor = ctx.use("advisor")
            local picks = Setup.Pick(ctx.settings, list or Setup.SUGGESTIONS)
            for _, p in ipairs(picks) do
                if advisor.Add("setup." .. p.key, p.text, Setup.PRIORITY) then
                    offered[#offered + 1] = p
                end
            end
            if #offered > 0 then ctx.store:set("char", Setup.OFFERED_PATH, true) end
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.setup = Setup.Declare(ns)

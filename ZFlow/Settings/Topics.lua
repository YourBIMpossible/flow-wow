local _, ns = ...
-- Topics: the one list of the topics the settings are filed under (lead
-- sections 238 and 239, rows N56 and N57), and the search over them. Pure
-- Lua 5.1: no frames, no client calls, no saved variable.
--
-- Every setting row names its topic in `group`: a topic's id ("travel"),
-- or the id and one of that topic's listed sections ("travel.flights").
-- Nothing else is a topic: a row whose group is missing or is not in this
-- list stands under Topics.UNFILED on the page, so it is never hidden, and
-- Tests/E2E/SettingsTopics.lua fails on it.
--
-- A row may also carry
--   synonyms = { "sell", "junk" }   more words the search finds it by
--   needs = "rotation.enabled"      the row (or rows) its `requires` leans
--                                   on, named when it cannot be set
-- Neither is stored and neither changes what the row holds.
--
-- To add a topic or a section: add it here. The page, the search, the menu
-- and the slash word are all made from this list and the rows.
--
--   Topics.LIST                   the topics, in the order shown
--   Topics.Find(group)            -> topic, section; nil for none or unknown
--   Topics.Of(row)                -> topic (UNFILED when not filed), section
--   Topics.Fold(text)             -> lower case, accents and marks taken off
--   Topics.Words(text)            -> the folded words of a search
--   Topics.Match(row, words)      -> a score when every word is found, else nil
--   Topics.Pick(text)             -> the topic a typed name means, or nil
--   Topics.MENU, Topics.MENU_MAX  the menus' own headings and the most rows
--                                 one level of a menu may hold
ns.Settings = ns.Settings or {}
local T = {}
ns.Settings.Topics = T

T.LIST = {
    { id = "general", name = "General and Appearance", sections = {
        { id = "windows", name = "Windows and buttons" },
    } },
    { id = "travel", name = "Travel and Questing", sections = {
        { id = "arrow", name = "The arrow" },
        { id = "route", name = "The way there" },
        { id = "flights", name = "Flights and crossings" },
    } },
    { id = "combat", name = "Combat and Class", sections = {
        { id = "rotation", name = "Next spell" },
        { id = "plates", name = "Nameplates" },
        { id = "spells", name = "Spells and trainers" },
    } },
    { id = "buffs", name = "Buffs and Recovery", sections = {} },
    { id = "gear", name = "Gear and Loot", sections = {
        { id = "loot", name = "Loot" },
    } },
    { id = "bags", name = "Bags, Vendors and Bank", sections = {} },
    { id = "professions", name = "Professions and Crafting", sections = {} },
    { id = "auctions", name = "Auctions and Prices", sections = {} },
    { id = "party", name = "Party and Dungeons", sections = {} },
    { id = "advanced", name = "Advanced and Diagnostics", sections = {} },
}

-- Where a row stands that names no topic of the list. Not a topic a row may
-- name: it marks a row still to be filed.
T.UNFILED = { id = "unfiled", name = "Not filed yet", sections = {} }

-- The menus' own headings (UI/ArrowMenu.lua), kept beside the topics so a
-- menu and the settings page are named from one place.
T.MENU = {
    layout = "Layout",
    show = "Show",
    style = "Style",
    back = "Back",
    settings = "All settings",
    topicSettings = " settings",
}
-- The most rows one level of any menu may hold, headings, dividers and the
-- way back counted.
T.MENU_MAX = 10

local byId = {}
for i = 1, #T.LIST do
    local topic = T.LIST[i]
    topic.at = i
    byId[topic.id] = topic
end
T.UNFILED.at = #T.LIST + 1

local function sectionOf(topic, id)
    for i = 1, #topic.sections do
        if topic.sections[i].id == id then return topic.sections[i] end
    end
    return nil
end

function T.Find(group)
    if type(group) ~= "string" or group == "" then return nil end
    local id, sec = group:match("^([^.]+)%.(.+)$")
    local topic = byId[id or group]
    if not topic then return nil end
    if not sec then return topic end
    local section = sectionOf(topic, sec)
    if not section then return nil end
    return topic, section
end

function T.Of(row)
    local topic, section = T.Find(type(row) == "table" and row.group or nil)
    if not topic then return T.UNFILED, nil end
    return topic, section
end

-- Letters U+00C0 to U+00FF as plain ones, by the second byte of their two
-- (\195 then \128 to \191). A space where there is no letter to give.
local LATIN = "aaaaaaaceeeeiiiidnooooo ouuuuyts" .. "aaaaaaaceeeeiiiidnooooo ouuuuyty"

function T.Fold(text)
    if type(text) ~= "string" then return "" end
    local s = text:gsub("\195([\128-\191])", function(b)
        local at = b:byte() - 127
        return LATIN:sub(at, at)
    end)
    s = s:gsub("\197[\146\147]", "oe")
    s = s:gsub("\197[\160\161]", "s")
    s = s:gsub("\197[\189\190]", "z")
    s = s:gsub("\197\184", "y")
    -- Marks written after their letter (U+0300 to U+036F) are dropped.
    s = s:gsub("\204[\128-\191]", "")
    s = s:gsub("\205[\128-\175]", "")
    s = s:lower():gsub("[^%w]+", " ")
    s = s:gsub("^ +", "")
    s = s:gsub(" +$", "")
    return s
end

function T.Words(text)
    local out = {}
    for word in T.Fold(text):gmatch("%S+") do out[#out + 1] = word end
    return out
end

-- What a row is found by, folded: its label; its synonyms and the names of
-- its topic and section; its description and its key.
local function haystack(row)
    local topic, section = T.Of(row)
    local extra = { topic.name }
    if section then extra[#extra + 1] = section.name end
    if type(row.synonyms) == "table" then
        for i = 1, #row.synonyms do
            if type(row.synonyms[i]) == "string" then extra[#extra + 1] = row.synonyms[i] end
        end
    end
    return T.Fold(row.label),
        T.Fold(table.concat(extra, " ")),
        T.Fold((type(row.help) == "string" and row.help or "") .. " " .. tostring(row.key))
end

-- Every word must be found somewhere. A word in the label counts most, one
-- in the synonyms or the topic's name next, one in the description least.
function T.Match(row, words)
    if type(row) ~= "table" or type(words) ~= "table" or #words == 0 then return nil end
    local label, extra, rest = haystack(row)
    local score = 0
    for i = 1, #words do
        local word = words[i]
        if label:find(word, 1, true) then
            score = score + 4
        elseif extra:find(word, 1, true) then
            score = score + 2
        elseif rest:find(word, 1, true) then
            score = score + 1
        else
            return nil
        end
    end
    return score
end

function T.Pick(text)
    local want = T.Fold(text)
    if want == "" then return nil end
    for i = 1, #T.LIST do
        local topic = T.LIST[i]
        if topic.id == want or T.Fold(topic.name) == want then return topic end
    end
    local words = T.Words(want)
    for i = 1, #T.LIST do
        local topic = T.LIST[i]
        local hay = T.Fold(topic.name) .. " " .. topic.id
        local all = true
        for w = 1, #words do
            if not hay:find(words[w], 1, true) then all = false break end
        end
        if all then return topic end
    end
    return nil
end

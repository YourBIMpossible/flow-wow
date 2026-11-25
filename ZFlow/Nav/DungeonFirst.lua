local _, ns = ...
-- Dungeon steps first (FLOW-PARITY A1-31), the data half: two rules of
-- legacy Flow, as pure functions the quest route calls.
--   * A dungeon run prepared (legacy Flow Modules/Nav/Nav.lua:3396-3405):
--     the run's own steps, its quest pick-ups and then its entrance, come
--     before the rest of the route; not when the player picked a step or a
--     tour (:3398), and never a step the run marks optional (:3400).
--     Get-ready steps (training, repair, bank) are not the run's own here,
--     as in Flow where they are errands of their own. A pick-up the route
--     already has for one of the run's quests is not said twice.
--   * Inside a dungeon (legacy Flow Modules/Nav/Dungeons.lua:1205-1223,
--     FilterInside): only the stops of quests filed under that dungeon are
--     routed, and party stops. When none of the route's quests is filed
--     under it (DF.NONE_HERE), or the dungeon's quests are not read yet
--     (DF.NOT_READ), the route is kept whole and the reason is given.
-- Which dungeon a quest is filed under is Nav/DungeonRead.lua's index of the
-- player's Questie (st.dungeonOf); the run's steps are R.Run's. Nothing
-- here reads the client. The caller is the quest route (Nav/TripRoute.lua
-- api.Plan), hooked there in its own change.
--
--   DF.First(stops, runSteps, opts) -> stops
--     opts.picked: true when the player picked a step or a tour
--   DF.Inside(stops, dungeonOf, here, ready) -> stops, why | nil
--     ready: false while the dungeon index (DungeonRead st.state) is not read
--     dungeonOf(questId) -> dungeon key | nil; here: the dungeon key the
--     player is in, or nil outside
ns.Nav = ns.Nav or {}
local N = ns.Nav
local DF = {}
N.DungeonFirst = DF

DF.RUN_KINDS = { giver = true, entrance = true }
DF.KEEP_INSIDE = { party = true }
-- The fact behind both: Questie files each quest under one zone or dungeon
-- (its zoneOrSort), as Nav/DungeonRead.lua indexes it.
DF.NONE_HERE = "Your route is not cut to this dungeon: Questie files none of your quests under it."
DF.NOT_READ = "Your route is not cut to this dungeon yet: its quests are still being read from Questie."

local function list(v)
    if type(v) == "table" then return v end
    return {}
end

function DF.First(stops, runSteps, opts)
    if type(opts) == "table" and opts.picked == true then return list(stops) end
    local first, covered = {}, {}
    local givers, entrance = {}, {}
    for _, s in ipairs(list(runSteps)) do
        if type(s) == "table" and DF.RUN_KINDS[s.kind] and s.optional ~= true then
            if s.kind == "entrance" then
                entrance[#entrance + 1] = s
            else
                givers[#givers + 1] = s
                if s.quest ~= nil then covered[s.quest] = true end
            end
        end
    end
    for _, s in ipairs(givers) do first[#first + 1] = s end
    for _, s in ipairs(entrance) do first[#first + 1] = s end
    for _, s in ipairs(list(stops)) do
        if not (type(s) == "table" and s.kind == "pickup" and s.quest ~= nil and covered[s.quest]) then
            first[#first + 1] = s
        end
    end
    return first
end

function DF.Inside(stops, dungeonOf, here, ready)
    stops = list(stops)
    if here == nil or type(dungeonOf) ~= "function" then return stops end
    if ready == false then return stops, DF.NOT_READ end
    local out, any = {}, false
    for _, s in ipairs(stops) do
        if type(s) == "table" then
            local at
            if s.quest ~= nil then
                local ok, v = pcall(dungeonOf, s.quest)
                if ok then at = v end
            end
            if at ~= nil and at == here then
                out[#out + 1] = s
                any = true
            elseif DF.KEEP_INSIDE[s.kind] then
                out[#out + 1] = s
            end
        end
    end
    if not any then return stops, DF.NONE_HERE end
    return out
end

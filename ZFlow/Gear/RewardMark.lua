local _, ns = ...

-- The quest reward mark (G14): when a quest is handed in and the game offers
-- a choice of rewards, the choice that is the biggest upgrade for the role
-- you chose carries a mark on its button. The player picks. Look only:
-- nothing here takes a reward, completes a quest or clicks anything.
-- Legacy Flow's Modules/Gear/QuestRewards.lua drew the same green arrow on
-- the best pick (and more marks this does not draw).
--
--   pick, why = GearRewardMark.Pick(client, packs, role)
--   api       = GearRewardMark.Declare(k[, packs])
--     api.marked()   the choice marked now, or nil
--     api.errors()   how many times the pick could not be worked out
--   ns.use(GearRewardMark.NAME) -> { Marked = api.marked, Errors = api.errors }
--
-- Pick: the index of the choice to mark, or nil and why (GearRewardMark.WHY).
--   client.questChoices()  { { index, link } ... } for the open choice; nil
--                          when it cannot be read. A link not given yet is
--                          a choice not read.
--   client.gear(link), class(), level(), weaponSkills(): as the tooltip
--   verdict reads them (Gear/Verdict.lua), with the class pack's weights.
--   role  spec.role (Rotation/Role.lua). One the pack has weights for: only
--         that role counts. None chosen: the biggest upgrade for any role.
-- No pick when: fewer than two choices; any choice is not read yet or has
-- no verdict (never a guess while one could be better); nothing is an
-- upgrade; or two choices are the same biggest upgrade. An item you cannot
-- use is never the pick. What is not gear is passed over.
--
-- The module: on QUEST_COMPLETE the pick is marked (client.markRewardChoice)
-- and worked out again every TICK seconds while the window is open, so an
-- item loaded late or a role changed moves the mark. QUEST_FINISHED clears
-- it. An error working it out shows no mark, is counted, and is kept as one
-- "gear" problem per distinct error.
-- Setting: gear.rewardMark (bool, account, on by default).
-- Not tested in game: QUEST_COMPLETE, QUEST_FINISHED and the client reads
-- are first guesses on 16001 (Core/Client.lua questChoices, Diag.NAMES).

local RM = {}
ns.GearRewardMark = RM

RM.NAME = "gearRewardMark"
RM.SETTING = "gear.rewardMark"
RM.PROBE_PATH = "diag.rewardButtons"  -- account: the G14 reward button probe
RM.ROLE = "spec.role"           -- Rotation/Role.lua's setting
RM.TICK = 1

RM.WHY = {
    unread = "the reward choices could not be read",
    single = "fewer than two choices",
    waiting = "a choice is not read yet",
    unknown = "a choice has no verdict",
    none = "no choice is an upgrade",
    tie = "two choices are the same upgrade",
}

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function ask(client, read, ...)
    if type(client) ~= "table" or type(client[read]) ~= "function" then return nil end
    return client[read](...)
end

-- The roles to score by: the chosen one when the pack has weights for it,
-- else every role the pack has weights for, sorted.
local function rolesFor(pack, role)
    local weights = type(pack) == "table" and type(pack.weights) == "table" and pack.weights or {}
    if type(role) == "string" and role ~= "" and type(weights[role]) == "table" then return { role } end
    local out = {}
    for r, w in pairs(weights) do
        if type(r) == "string" and type(w) == "table" then out[#out + 1] = r end
    end
    table.sort(out)
    return out
end

function RM.Pick(client, packs, role)
    local rows = ask(client, "questChoices")
    if type(rows) ~= "table" then return nil, RM.WHY.unread end
    if #rows < 2 then return nil, RM.WHY.single end
    local class = ask(client, "class")
    local pack
    if type(packs) == "table" and class ~= nil then pack = packs[class] end
    local roles = rolesFor(pack, role)
    if #roles == 0 then return nil, RM.WHY.unknown end
    local level = ask(client, "level")
    local skills
    local okSkills, readSkills = pcall(ask, client, "weaponSkills")
    if okSkills and type(readSkills) == "table" then skills = readSkills end

    local best, bestDelta, tie = nil, nil, false
    for i = 1, #rows do
        local row = type(rows[i]) == "table" and rows[i] or {}
        local index = i
        if finite(row.index) then index = row.index end
        local link = row.link
        if type(link) ~= "string" or link == "" then return nil, RM.WHY.waiting end
        local gear = ask(client, "gear", link)
        if type(gear) ~= "table" then return nil, RM.WHY.waiting end
        for r = 1, #roles do
            local lines, detail = ns.GearVerdict.Lines(gear, { pack = pack, role = roles[r], level = level,
                                                                skills = skills })
            if lines == nil then
                -- Not gear: passed over once the item's kind was read.
                if not finite(gear.classID) then return nil, RM.WHY.waiting end
                break
            end
            local can
            if type(detail) == "table" and type(detail.use) == "table" then can = detail.use.can end
            if can == false then break end
            if can ~= true then return nil, RM.WHY.unknown end
            local res = type(detail.result) == "table" and detail.result or {}
            local v = res.verdict
            if v ~= "upgrade" and v ~= "same" and v ~= "worse" then return nil, RM.WHY.unknown end
            if v == "upgrade" and finite(res.delta) and res.delta >= ns.GearTooltip.SAME then
                if bestDelta == nil or res.delta > bestDelta then
                    best, bestDelta, tie = index, res.delta, false
                elseif res.delta == bestDelta and best ~= index then
                    tie = true
                end
            end
        end
    end
    if best == nil then return nil, RM.WHY.none end
    if tie then return nil, RM.WHY.tie end
    return best
end

function RM.Declare(k, packs)
    local api = {}
    local ctx, open, tick, marked, errors = nil, false, nil, nil, 0
    local seen = {}
    function api.marked() return marked end
    function api.errors() return errors end

    local function show(index)
        marked = nil
        local mark = ctx and ctx.client.markRewardChoice
        if type(mark) ~= "function" then return end
        local ok, done = pcall(mark, index)
        if not ok then
            errors = errors + 1
            local text = tostring(done)
            if not seen[text] then
                seen[text] = true
                k.problems:add("gear", "reward mark", text)
            end
            return
        end
        if index ~= nil and done == true then marked = index end
    end

    local function update()
        if not open then return end
        if ctx.settings:get(RM.SETTING) ~= true then
            show(nil)
            return
        end
        local ok, pick = pcall(RM.Pick, ctx.client, packs or ns.Packs, ctx.settings:get(RM.ROLE))
        if not ok then
            errors = errors + 1
            local text = tostring(pick)
            if not seen[text] then
                seen[text] = true
                k.problems:add("gear", "reward mark", text)
            end
            show(nil)
            return
        end
        show(pick)
    end

    -- RM-2: fewer than 2 choices read - nothing to choose between, so no
    -- repeat. Not read (nil, or the read raised) is not "few": it repeats.
    local function fewChoices()
        local okC, list = pcall(ctx.client.questChoices)
        return okC and type(list) == "table" and #list < 2
    end

    -- G14 probe (RM-1): each reward button's own number and kind, saved
    -- once per reward window in account RM.PROBE_PATH, so a capture says
    -- whether choice i is button i. It changes no mark. A read that is
    -- absent or raises saves nothing.
    local function probe()
        if type(ctx.client.rewardButtons) ~= "function" then return end
        local okR, rows = pcall(ctx.client.rewardButtons)
        if not okR then return end
        local old = ctx.store:get("account", RM.PROBE_PATH)
        local seen = 0
        if type(old) == "table" and type(old.seen) == "number" then seen = old.seen end
        local record = { seen = seen + 1, found = type(rows) == "table" }
        if type(rows) == "table" then
            record.rows = {}
            for i = 1, math.min(#rows, 10) do
                local r = type(rows[i]) == "table" and rows[i] or {}
                record.rows[i] = { index = r.index, id = r.id, kind = r.kind }
            end
        end
        ctx.store:set("account", RM.PROBE_PATH, record)
    end

    local function close()
        open = false
        if tick then tick() end
        tick = nil
        if ctx then show(nil) end
    end

    k:Module({
        name = RM.NAME,
        needs = { "client", "settings", "bus", "sched", "store" },
        settings = { {
            key = RM.SETTING, scope = "account", type = "bool", default = true,
            label = "Mark the best quest reward",
            help = "When a quest offers a choice of rewards, mark the biggest upgrade for your role."
                .. " You pick; it takes nothing.",
            group = "gear", synonyms = { "reward", "quest", "choice", "mark", "upgrade" },
        } },
        provides = { Marked = api.marked, Errors = api.errors },
        start = function(c)
            ctx = c
            -- The repeat starts once 2 or more choices are read (LF-1): a
            -- count read late, on an item's data arriving, starts it too.
            local function repeatIfMany()
                if open and not tick and not fewChoices() then tick = c.sched:every(RM.NAME, RM.TICK, update) end
            end
            c.bus:on(RM.NAME, "QUEST_COMPLETE", function()
                open = true
                local okP, why = pcall(probe)
                if not okP and not seen[tostring(why)] then
                    seen[tostring(why)] = true
                    k.problems:add("gear", "reward buttons probe", tostring(why))
                end
                update()
                repeatIfMany()
            end)
            c.bus:on(RM.NAME, "GET_ITEM_INFO_RECEIVED", function()
                if not open or tick then return end
                update()
                repeatIfMany()
            end)
            c.bus:on(RM.NAME, "QUEST_FINISHED", close)
        end,
        stop = function() close() end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.gearRewardMark = RM.Declare(ns)

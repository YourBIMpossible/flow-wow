local _, ns = ...

-- Class quests (lead section 242, DRUID-2): the quests a class trainer sends
-- you on for a spell (Bear Form, Aquatic Form for a Druid), learned from the
-- quest log of the player, never from a table of ids.
--   before any is seen  one advisor prompt in words only:
--                       "Bear Form: ask your class trainer at level 10"
--                       (the level is the pack spell level)
--   when it is learned  a class-quest spell is learned (onSpellLearned)
--                       within M.WINDOW seconds of exactly one quest leaving
--                       the log, in either order: that quest is kept for the
--                       account under learned.classQuests.<CLASS>[id] =
--                       { title, spell }. None, or more than one gone at
--                       once, keeps nothing: unknown stays unknown.
--   after               a later character of that class on the account is
--                       told the quest by the title kept, or that it is in
--                       the log.
-- The class-quest spells are the pack spells whose note is "class quest".
-- Look-only: nothing is accepted, handed in or trained.
-- Needs game test: the order of the hand-in, QUEST_LOG_UPDATE and the spell
-- learned event, and how far apart they come; both orders are taken here.
--
-- Pure parts:
--   M.Spells(pack)              { { name, level }, ... } lowest level first
--   M.Gone(before, now)         the rows of before whose id is not in now
--   M.Text(spell, kept, inLog)  the prompt words for one spell
--
-- Saved data: account "learned.classQuests" = { [CLASS] = { [questId] =
-- { title, spell } } }.
-- Setting (char, on by default): spells.classQuests "Class quest reminders".

local M = {}
ns.ClassQuests = M

M.NAME = "classQuests"
M.PATH = "learned.classQuests"
M.SETTING = "spells.classQuests"
M.PROMPT = "aps.classQuest"
M.PRIORITY = 2
M.NOTE = "class quest"
-- Seconds a quest gone from the log and a spell learned may be apart and
-- still be matched.
M.WINDOW = 5

M.ASK_LEVEL = "%s: ask your class trainer at level %d"
M.ASK_QUEST = "%s: ask your class trainer for %s"
M.IN_LOG = "%s: %s is in your quest log"

function M.Spells(pack)
    local out = {}
    local spells = type(pack) == "table" and type(pack.spells) == "table" and pack.spells or {}
    for name, s in pairs(spells) do
        if type(name) == "string" and type(s) == "table" and s.note == M.NOTE and type(s.level) == "number" then
            out[#out + 1] = { name = name, level = s.level }
        end
    end
    table.sort(out, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        return a.name < b.name
    end)
    return out
end

function M.Gone(before, now)
    local out = {}
    if type(before) ~= "table" or type(now) ~= "table" then return out end
    local still = {}
    for _, r in ipairs(now) do
        if type(r) == "table" and r.id ~= nil then still[r.id] = true end
    end
    for _, r in ipairs(before) do
        if type(r) == "table" and r.id ~= nil and not still[r.id] then out[#out + 1] = r end
    end
    return out
end

-- kept: { [questId] = { title, spell } }; inLog: { [questId] = true }.
function M.Text(spell, kept, inLog)
    if type(spell) ~= "table" or type(spell.name) ~= "string" then return nil end
    local found
    for id, q in pairs(type(kept) == "table" and kept or {}) do
        if type(q) == "table" and q.spell == spell.name and type(q.title) == "string" then
            if type(inLog) == "table" and inLog[id] then return M.IN_LOG:format(spell.name, q.title) end
            found = found or q.title
        end
    end
    if found then return M.ASK_QUEST:format(spell.name, found) end
    return M.ASK_LEVEL:format(spell.name, spell.level)
end

local function ask(client, read, ...)
    if type(client) ~= "table" or type(client[read]) ~= "function" then return nil end
    local ok, v = pcall(client[read], ...)
    if not ok then return nil end
    return v
end

local LOG_EVENTS = { "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" }

function M.Declare(k)
    local api = {}
    local stopLearned

    k:Module({
        name = M.NAME,
        needs = { "client", "store", "bus", "settings", "advisor" },
        settings = { {
            key = M.SETTING, scope = "char", type = "bool", default = true,
            label = "Class quest reminders",
            help = "Says when your class trainer has a quest for a new form, and keeps which quest it was "
                .. "for your other characters of that class. It reads your quest log only.",
            group = "combat.spells",
            synonyms = { "quest", "form", "trainer" },
        } },
        start = function(ctx)
            local client = ctx.client
            local advisor = ctx.use("advisor")
            local class = ask(client, "class")
            local spells = M.Spells(type(ns.Packs) == "table" and ns.Packs[class] or nil)
            if #spells == 0 then return end
            -- The last log read that answered; the quests that left it most
            -- recently, and a class-quest spell learned with no quest yet,
            -- each with the time it was seen.
            local last, gone, pending = nil, nil, nil
            local shown

            local function now() return tonumber(ask(client, "now")) or 0 end
            local function fresh(x) return x ~= nil and now() - x.at <= M.WINDOW end

            local function keep(row, spell)
                local all = ctx.store:table("account", M.PATH)
                if type(all) ~= "table" then return end
                if type(all[class]) ~= "table" then all[class] = {} end
                all[class][row.id] = { title = row.title, spell = spell }
            end

            local function known(name)
                local id = ask(client, "spellId", name)
                if id == nil then return false end
                local s = ask(client, "spell", id)
                return type(s) == "table" and s.known == true
            end

            -- One prompt: the lowest-level class-quest spell due and not known.
            local function refresh()
                local text
                local level = ask(client, "level")
                if ctx.settings:get(M.SETTING) ~= false and type(level) == "number" then
                    local inLog = {}
                    for _, r in ipairs(last or {}) do inLog[r.id] = true end
                    local saved = ctx.store:get("account", M.PATH)
                    local mine = type(saved) == "table" and type(saved[class]) == "table" and saved[class] or {}
                    for _, s in ipairs(spells) do
                        if not text and level >= s.level and not known(s.name) then
                            text = M.Text(s, mine, inLog)
                        end
                    end
                end
                if type(advisor) ~= "table" or text == shown then return end
                if text then advisor.Add(M.PROMPT, text, M.PRIORITY) else advisor.Remove(M.PROMPT) end
                shown = text
            end

            -- A quest gone and a spell learned meet: kept only when exactly
            -- one quest went.
            local function match(rows, spell)
                if #rows == 1 then keep(rows[1], spell) end
                gone, pending = nil, nil
            end

            local function readLog()
                local rows = ns.Nav.QuestLogRows(client)
                if type(rows) ~= "table" then return end
                local left = M.Gone(last, rows)
                last = rows
                if #left == 0 then return end
                if fresh(pending) then
                    match(left, pending.spell)
                else
                    gone, pending = { rows = left, at = now() }, nil
                end
            end

            local function learned(spell)
                local name = type(spell) == "table" and spell.name or nil
                for _, s in ipairs(spells) do
                    if s.name == name then
                        readLog()
                        if fresh(gone) then
                            match(gone.rows, name)
                        else
                            gone, pending = nil, { spell = name, at = now() }
                        end
                    end
                end
                refresh()
            end

            for _, ev in ipairs(LOG_EVENTS) do
                ctx.bus:on(M.NAME, ev, function()
                    readLog()
                    refresh()
                end)
            end
            ctx.bus:on(M.NAME, "PLAYER_LEVEL_UP", refresh)
            stopLearned = ask(client, "onSpellLearned", learned)
            readLog()
            refresh()
        end,
        stop = function()
            if type(stopLearned) == "function" then stopLearned() end
            stopLearned = nil
        end,
    })
    return api
end

ns.classQuests = M.Declare(ns)

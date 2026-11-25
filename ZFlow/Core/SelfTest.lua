local _, ns = ...

-- SelfTest (parity row F-04; lead section 660): `<slash> selftest` asks the
-- client each of its guarded reads once and says, read by read, whether it
-- answered. For telling in the game which reads this client really gives,
-- without a reload and without the saved file.
--
-- LOOK ONLY. Every name in SelfTest.READS is a read of Core/Client.lua
-- that takes nothing and changes nothing: no window is opened, nothing is
-- clicked, cast, bound, bought or written. No answer is printed, only
-- whether there was one: a line never holds a name, a place or a number
-- of the player's.
--
-- From Flow (Modules/Tests.lua:91, `/flow test` at a529eea): a word that
-- runs checks in the game and prints a head line and a line for each.
-- Flow's runs its whole test list, which opens windows and sets keys, so
-- it is refused in a fight. This one only reads, so it runs anywhere.
--
-- A read's result is one of:
--   pass     the client has the read and it did not raise. With an answer,
--            SelfTest.ANSWERED; with none (nil: the client did not say),
--            SelfTest.SILENT. A guarded read that the game does not answer
--            is the read working, so it is a pass, and said apart.
--   fail     the read raised. A guarded read never should.
--   missing  this client has no read of that name.
--
-- Pure:
--   SelfTest.Run(client[, names]) -> rows, counts
--     rows   = { { name, result = "pass" | "fail" | "missing",
--                  answered = true | false (pass only),
--                  why = text (fail only) }, ... } in the order of names
--     counts = { pass, fail, missing, silent }
--   SelfTest.Lines(rows, counts) -> the lines to print, the head first
-- Module "selfTest" provides Run() -> rows, counts for the kernel's client.
-- The word: SelfTest.WORD. Not tested in game.

local SelfTest = {}
ns.SelfTest = SelfTest

SelfTest.NAME = "selfTest"
SelfTest.WORD = "selftest"
SelfTest.HELP = "ask the game each thing the add-on reads, and say which answered. It only reads."
SelfTest.PASS, SelfTest.FAIL, SelfTest.MISSING = "pass", "fail", "missing"
SelfTest.ANSWERED = "pass"
SelfTest.SILENT = "pass, no answer now"
SelfTest.HEAD = "self-test: %d pass (%d with no answer now), %d fail, %d missing"
SelfTest.LINE = "  %s: %s"
SelfTest.LINE_WHY = "  %s: fail (%s)"
SelfTest.WHY_MAX = 80
-- The add-on's name before the head line, when the identity handed in gives
-- none: the add-on's own identity title (Core/Identity.lua loads first).
SelfTest.TITLE = ns.id.title

-- The reads asked, in this order. Each takes nothing and only reads.
SelfTest.READS = {
    "now", "clock", "uptime", "inCombat", "combatLockdown", "money", "class", "faction", "level",
    "raceId", "realm", "position", "zone", "worldPosition", "facing", "moving", "mounted", "onTaxi",
    "dead", "ghost", "stealthed", "form", "bags", "durability", "professions", "questLog",
    "bindLocation", "hearthCooldown", "anyTracking", "minimap", "screen",
}

function SelfTest.Run(client, names)
    local rows = {}
    local counts = { pass = 0, fail = 0, missing = 0, silent = 0 }
    if type(names) ~= "table" then names = SelfTest.READS end
    for _, name in ipairs(names) do
        local row = { name = name }
        local fn
        if type(client) == "table" then fn = client[name] end
        if type(fn) ~= "function" then
            row.result = SelfTest.MISSING
            counts.missing = counts.missing + 1
        else
            local ok, answer = pcall(fn)
            if ok then
                row.result = SelfTest.PASS
                row.answered = answer ~= nil
                counts.pass = counts.pass + 1
                if not row.answered then counts.silent = counts.silent + 1 end
            else
                row.result = SelfTest.FAIL
                row.why = tostring(answer):sub(1, SelfTest.WHY_MAX)
                counts.fail = counts.fail + 1
            end
        end
        rows[#rows + 1] = row
    end
    return rows, counts
end

function SelfTest.Lines(rows, counts)
    local lines = {}
    if type(rows) ~= "table" then return lines end
    if type(counts) ~= "table" then counts = {} end
    lines[1] = SelfTest.HEAD:format(counts.pass or 0, counts.silent or 0, counts.fail or 0, counts.missing or 0)
    for _, row in ipairs(rows) do
        if type(row) == "table" then
            if row.result == SelfTest.FAIL then
                lines[#lines + 1] = SelfTest.LINE_WHY:format(tostring(row.name), tostring(row.why))
            elseif row.result == SelfTest.MISSING then
                lines[#lines + 1] = SelfTest.LINE:format(tostring(row.name), SelfTest.MISSING)
            elseif row.answered then
                lines[#lines + 1] = SelfTest.LINE:format(tostring(row.name), SelfTest.ANSWERED)
            else
                lines[#lines + 1] = SelfTest.LINE:format(tostring(row.name), SelfTest.SILENT)
            end
        end
    end
    return lines
end

function SelfTest.Declare(k, diag)
    local api = {}

    function api.Run()
        return SelfTest.Run(k.client)
    end

    if type(diag) == "table" and type(diag.commands) == "table" then
        diag.commands[SelfTest.WORD] = function()
            local client = k.client
            if type(client) ~= "table" or type(client.print) ~= "function" then return end
            -- Lead section 671: an identity with no title of its own still
            -- gets a head line that names the add-on.
            local id = k.id
            if type(id) ~= "table" then id = ns.id end
            local title = SelfTest.TITLE
            if type(id) == "table" and type(id.title) == "string" and id.title ~= "" then title = id.title end
            local rows, counts = api.Run()
            for i, line in ipairs(SelfTest.Lines(rows, counts)) do
                if i == 1 then line = title .. ": " .. line end
                client.print(line)
            end
        end
        if type(diag.help) == "table" then diag.help[SelfTest.WORD] = SelfTest.HELP end
    end

    k:Module({
        name = SelfTest.NAME,
        needs = { "client" },
        provides = { Run = api.Run },
    })
    return api
end

-- The addon's own: declared when this file loads.
ns.selfTest = SelfTest.Declare(ns, ns.diag)

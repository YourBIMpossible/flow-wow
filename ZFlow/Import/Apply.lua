local _, ns = ...

-- Import from Flow, for real (CAPABILITY-RECONCILE 2026-11-24 row A10).
-- The one place the earlier add-on's saved data is copied into this one's,
-- and only on the player's own word:
--   <slash> import        the dry run (Core/Diag.lua), unchanged, plus one
--                         line naming the word below when there is data
--   <slash> import now    copies it in, and says how much
-- Any other rest goes to the word's old work ("import settings" is
-- UI/SettingsShare.lua's).
--
-- What "now" does: Import.FromFlow reads COPIES of the earlier add-on's
-- tables, Import.Merge lays the result under COPIES of this add-on's saved
-- tables (a value the player already has is never replaced; a vendor
-- automation the earlier add-on had on stays off, since nobody confirmed
-- it here), and only when the merge says ok is the outcome written into
-- the saved tables, in place. A failure writes nothing. The earlier
-- add-on's tables are never written.
--
-- The earlier add-on's data is only loaded while it is switched on, and
-- then this add-on is paused (Core/Guard.lua), so the copy takes effect
-- after the player turns the earlier add-on off and reloads. The line says
-- so.
--
--   A.Sync(live, want) -> n     make live equal to want, in place: tables
--                               met on both sides are kept and walked.
--                               n: how many single values were set or
--                               removed (an empty table counts as none).
--   A.Run(client, id, problems) -> true when something was written
--
-- Reads: client.savedExists, client.saved. Writes: this add-on's two saved
-- tables (account and character). Not tested in game.

local A = {}
ns.Import = ns.Import or {}
ns.Import.Apply = A

A.NOW = "now"
A.HELP = "import now: copy the earlier addon's saved data in; your own choices are kept"
A.HINT = "to copy it in, type %s."
A.NO_DATA = "no %s data is loaded. Turn %s on beside this add-on, reload, then type %s."
A.NOT_LOADED = "the import is not loaded."
A.UNREADABLE = "the import could not be read; nothing was copied."
A.FAILED = "nothing was copied: %s."
A.DONE = "copied %d saved values from %s; %d of your own were kept."
A.SAME = "everything %s had is already here; nothing new was copied."
A.VENDOR = " %d vendor automation(s) %s had on stay off here; turn them on in the options if you want them."
A.NEXT = " Now turn %s off and reload."

local function leaves(v, seen)
    if type(v) ~= "table" then return 1 end
    seen = seen or {}
    if seen[v] then return 0 end
    seen[v] = true
    local n = 0
    for _, x in pairs(v) do n = n + leaves(x, seen) end
    return n
end

function A.Sync(live, want, seen)
    if type(live) ~= "table" or type(want) ~= "table" then return 0 end
    seen = seen or {}
    if seen[live] then return 0 end
    seen[live] = true
    local n = 0
    for key in pairs(live) do
        if want[key] == nil then
            live[key] = nil
            n = n + 1
        end
    end
    for key, value in pairs(want) do
        if type(value) == "table" and type(live[key]) == "table" then
            n = n + A.Sync(live[key], value, seen)
        elseif live[key] ~= value then
            live[key] = value
            n = n + leaves(value)
        end
    end
    return n
end

local function text(v)
    return (tostring(v):gsub("|", "||"))
end

function A.Run(client, id, problems)
    local function say(line) client.print(id.title .. ": " .. line) end
    local word = id.slash .. " import " .. A.NOW
    local Import = ns.Import
    if not (type(Import.FromFlow) == "function" and type(Import.Merge) == "function") then
        say(A.NOT_LOADED)
        return false
    end
    if not client.savedExists(id.predecessorDB) then
        say(A.NO_DATA:format(id.predecessor, id.predecessor, word))
        return false
    end
    local copy = ns.make.deepCopy
    local charName = id.predecessorCharDB
    local ok, account, char, report = pcall(function()
        local result = Import.FromFlow(copy(client.saved(id.predecessorDB)),
            client.savedExists(charName) and copy(client.saved(charName)) or nil)
        if type(result) ~= "table" or result.ok ~= true then
            return nil, nil, { ok = false, reason = type(result) == "table" and result.reason or nil }
        end
        -- No automation is confirmed here, so each one stays off.
        return Import.Merge(copy(client.saved(id.accountDB)), copy(client.saved(id.charDB)), result, nil, {})
    end)
    if not ok then
        if problems and type(problems.add) == "function" then problems:add("diag", "import", account) end
        say(A.UNREADABLE)
        return false
    end
    if type(report) ~= "table" or report.ok ~= true or type(account) ~= "table" or type(char) ~= "table" then
        say(A.FAILED:format(text(type(report) == "table" and report.reason or "no reason given")))
        return false
    end
    -- The record of the import is written apart, so it is not counted as
    -- something copied: typed again, the count is 0.
    local live = client.saved(id.accountDB)
    local imports = account.imports
    account.imports = live.imports
    local added = A.Sync(live, account) + A.Sync(client.saved(id.charDB), char)
    live.imports = imports
    local counts = type(report.counts) == "table" and report.counts or {}
    local kept = tonumber(counts.kept) or 0
    local line
    if added > 0 then
        line = A.DONE:format(added, id.predecessor, kept)
    else
        line = A.SAME:format(id.predecessor)
    end
    local off = type(report.vendorLeftOff) == "table" and #report.vendorLeftOff or 0
    if off > 0 then line = line .. A.VENDOR:format(off, id.predecessor) end
    say(line .. A.NEXT:format(id.predecessor))
    return true
end

-- The word: "now" is this file's; any other rest goes to the old work.
function A.Declare(k, diag)
    if not (diag and type(diag.commands) == "table") then return end
    local prior = diag.commands.import
    diag.commands.import = function(rest)
        local client, id = k.client, k.id or ns.id
        local first = type(rest) == "string" and rest:match("^(%S+)") or nil
        if first == A.NOW then
            if type(client) == "table" then A.Run(client, id, k.problems) end
            return
        end
        if type(prior) == "function" then prior(rest) end
        if first == nil and type(client) == "table" and client.savedExists(id.predecessorDB) then
            client.print(id.title .. ": " .. A.HINT:format(id.slash .. " import " .. A.NOW))
        end
    end
    if type(diag.help) == "table" then
        local was = diag.help.import
        diag.help.import = (type(was) == "string" and was ~= "") and (was .. "; " .. A.HELP) or A.HELP
    end
end

A.Declare(ns, ns.diag)

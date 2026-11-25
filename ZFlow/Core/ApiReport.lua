local _, ns = ...

-- The client check report (FLOW-PARITY F-03; lead sections 580 item 7, 850):
-- what the "api" word prints, as Flow's /flow api (Core.lua:330-421) says
-- which client names this client has. Read only, and only from what the
-- diagnostics already save: diag.names (Diag.Save: each name in Diag.NAMES
-- and its type, with the build) and diag.reads (Diag.SaveReads: the newest
-- run of Diag.Reads). Nothing here calls the game.
--
--   ApiReport.Lines(diag) -> lines   diag as saved, or nil
--   ApiReport.Run(client, id) -> lines   the account's saved diag
-- The word itself is registered in Core/Diag.lua (a lead patch).

local AR = {}
ns.ApiReport = AR

AR.MISSING_MAX = 12
AR.NONE = "No client check is saved yet. It is taken when you log in or reload: /reload, then ask again."
AR.BUILD = "Client check of build %s."
AR.COUNT = "%d of %d client names this add-on asks about are there."
AR.ALL_THERE = "Every one of them is there."
AR.MISSING = "Not there: "
AR.MORE = "(%d more not shown)"
AR.SECRET_YES = "This client hides some values from add-ons (secret values)."
AR.SECRET_NO = "This client does not hide values from add-ons."
AR.SECRET_UNKNOWN = "Whether this client hides values from add-ons is not known."
AR.FAILED = "Reads that failed: "
AR.READS_OK = "Every read the check tried answered."
AR.NO_READS = "No reads saved yet."

local function newestReads(diag)
    local list = diag.reads
    if type(list) ~= "table" then return nil end
    local last = list[#list]
    if type(last) ~= "table" or type(last.reads) ~= "table" then return nil end
    return last.reads
end

function AR.Lines(diag)
    if type(diag) ~= "table" or type(diag.names) ~= "table" or type(diag.names.names) ~= "table" then
        return { AR.NONE }
    end
    local lines = {}
    local build = diag.names.build
    if type(build) ~= "string" or build == "" then build = "unknown" end
    lines[#lines + 1] = AR.BUILD:format(build)
    local total, missing = 0, {}
    for name, kind in pairs(diag.names.names) do
        if type(name) == "string" then
            total = total + 1
            if kind == nil or kind == "nil" or kind == false then missing[#missing + 1] = name end
        end
    end
    table.sort(missing)
    lines[#lines + 1] = AR.COUNT:format(total - #missing, total)
    if #missing == 0 then
        lines[#lines + 1] = AR.ALL_THERE
    else
        local shown = {}
        for i = 1, math.min(#missing, AR.MISSING_MAX) do shown[i] = missing[i] end
        local line = AR.MISSING .. table.concat(shown, ", ")
        if #missing > AR.MISSING_MAX then line = line .. " " .. AR.MORE:format(#missing - AR.MISSING_MAX) end
        lines[#lines + 1] = line
    end
    local reads = newestReads(diag)
    if not reads then
        lines[#lines + 1] = AR.NO_READS
        return lines
    end
    -- F-03 CHANGES-1 (lead section 856): "no" only when the client said it
    -- has no issecretvalue; any other answer, or none, is not known (611).
    if reads.secretFn == "function" then
        lines[#lines + 1] = AR.SECRET_YES
    elseif reads.secretFn == "nil" then
        lines[#lines + 1] = AR.SECRET_NO
    else
        lines[#lines + 1] = AR.SECRET_UNKNOWN
    end
    local failed = {}
    for key, v in pairs(reads) do
        if type(key) == "string" and type(v) == "table" and v.failed == true then failed[#failed + 1] = key end
    end
    table.sort(failed)
    if #failed == 0 then
        lines[#lines + 1] = AR.READS_OK
    else
        lines[#lines + 1] = AR.FAILED .. table.concat(failed, ", ")
    end
    return lines
end

function AR.Run(client, id)
    if type(client) ~= "table" or type(client.saved) ~= "function" or type(id) ~= "table" then
        return { AR.NONE }
    end
    local ok, db = pcall(client.saved, id.accountDB)
    if not ok or type(db) ~= "table" then return { AR.NONE } end
    return AR.Lines(db.diag)
end

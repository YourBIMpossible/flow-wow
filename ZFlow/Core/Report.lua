-- Problems and timing: where the kernel records what went wrong and what
-- each owner cost, instead of raising an error that stops a file loading.
local _, ns = ...
ns.make = ns.make or {}

-- problems:add(kind, owner, text[, detail]); a repeat of the same problem
-- raises its count instead of growing the list.
function ns.make.problems()
    local list, index = {}, {}
    local P = {}

    function P:add(kind, owner, text, detail)
        kind, owner, text = tostring(kind), tostring(owner), tostring(text)
        local id = kind .. "\0" .. owner .. "\0" .. text .. "\0" .. tostring(detail)
        local entry = index[id]
        if entry then
            entry.count = entry.count + 1
            return entry
        end
        entry = { kind = kind, owner = owner, text = text, detail = detail, count = 1 }
        index[id] = entry
        list[#list + 1] = entry
        return entry
    end

    -- All problems, or only those of one kind, oldest first.
    function P:list(kind)
        local out = {}
        for i = 1, #list do
            if kind == nil or list[i].kind == kind then out[#out + 1] = list[i] end
        end
        return out
    end

    function P:count(kind)
        return #self:list(kind)
    end

    return P
end

-- meter:run(owner, kind, detail, fn, ...) calls fn under pcall, adds the
-- call and its time to the owner's row, and records an error as a problem
-- of `kind`. Returns ok, err.
function ns.make.meter(k)
    local rows = {}
    local M = {}

    function M:run(owner, kind, detail, fn, ...)
        local row = rows[owner]
        if not row then
            row = { calls = 0, ms = 0, errors = 0 }
            rows[owner] = row
        end
        local clock = k.client.clockMs
        local t0 = clock()
        local ok, err = pcall(fn, ...)
        row.calls = row.calls + 1
        row.ms = row.ms + (clock() - t0)
        if not ok then
            row.errors = row.errors + 1
            k.problems:add(kind, owner, err, detail)
        end
        return ok, err
    end

    -- A copy: { [owner] = { calls, ms, errors } }.
    function M:report()
        local out = {}
        for owner, row in pairs(rows) do
            out[owner] = { calls = row.calls, ms = row.ms, errors = row.errors }
        end
        return out
    end

    return M
end

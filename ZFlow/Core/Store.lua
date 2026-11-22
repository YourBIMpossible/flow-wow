-- Store: the only access to saved data. Two scopes, "account" and "char",
-- each a real saved table written as the player plays (nothing is moved at
-- logout). Paths are dotted strings: "settings.sell.autoJunk". Every
-- segment is a string key; data keyed by number lives in a store:table.
--
--   store:get(scope, path)            -> value or nil
--   store:set(scope, path, value)     -> true, or false and a reason
--   store:watch(scope, path, fn)      -> cancel; fn(value, old, scope, path)
--   store:table(scope, path)          -> the table at path, made if absent
--   store:open()                      -> runs the schema ladder; true if clean
--
-- Schema ladder: store.steps[scope][n] is a function (db) -> db that takes
-- a copy of the data at schema n and returns it at schema n + 1. It is empty
-- at schema 1. A missing or failing step leaves the saved table exactly as
-- it was and blocks writes to that scope for the session.
--
-- A skeleton section that holds something other than a table is replaced
-- with an empty table when the store opens. What was there is kept once,
-- in the same scope's saved data under recovered.<key> (so
-- store:get(scope, "recovered.<key>") reads it), and the problem row says
-- where. A value already kept there is never overwritten.
local _, ns = ...
ns.make = ns.make or {}

local SKELETON = {
    account = { "settings", "layout", "learned", "imports" },
    char = { "settings", "layout", "learned", "state" },
}

local function split(path)
    if type(path) ~= "string" or path == "" then return nil end
    local parts = {}
    for seg in (path .. "."):gmatch("(.-)%.") do
        if seg == "" then return nil end
        parts[#parts + 1] = seg
    end
    return parts
end

local function deepCopy(v, seen)
    if type(v) ~= "table" then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local out = {}
    seen[v] = out
    for key, value in pairs(v) do out[deepCopy(key, seen)] = deepCopy(value, seen) end
    return out
end
ns.make.deepCopy = deepCopy

function ns.make.store(k)
    local store = { schema = 1, steps = { account = {}, char = {} }, blocked = {}, opened = false }
    local names = { account = k.id.accountDB, char = k.id.charDB }
    local watchers = {}

    local function root(scope)
        local name = names[scope]
        if not name then return nil end
        return k.client.saved(name)
    end

    function store:get(scope, path)
        local at, parts = root(scope), split(path)
        if not at or not parts then return nil end
        for i = 1, #parts do
            if type(at) ~= "table" then return nil end
            at = at[parts[i]]
        end
        return at
    end

    function store:set(scope, path, value)
        local at, parts = root(scope), split(path)
        if not at then return false, "unknown scope " .. tostring(scope) end
        if not parts then return false, "bad path " .. tostring(path) end
        if self.blocked[scope] then return false, self.blocked[scope] end
        if #parts == 1 and parts[1] == "schema" then return false, "schema is set by the store" end
        for i = 1, #parts - 1 do
            local nxt = at[parts[i]]
            if nxt == nil then
                nxt = {}
                at[parts[i]] = nxt
            elseif type(nxt) ~= "table" then
                return false, "path " .. path .. " is blocked at " .. parts[i]
            end
            at = nxt
        end
        local leaf = parts[#parts]
        local old = at[leaf]
        at[leaf] = value
        if old ~= value then
            local list = watchers[scope .. ":" .. path]
            if list then
                local snapshot = {}
                for i = 1, #list do snapshot[i] = list[i] end
                for i = 1, #snapshot do
                    if not snapshot[i].dead then
                        local ok, err = pcall(snapshot[i].fn, value, old, scope, path)
                        if not ok then k.problems:add("watch", scope .. ":" .. path, err) end
                    end
                end
            end
        end
        return true
    end

    function store:watch(scope, path, fn)
        if not names[scope] or not split(path) or type(fn) ~= "function" then
            k.problems:add("store", tostring(scope), "bad watch on " .. tostring(path))
            return function() end
        end
        local id = scope .. ":" .. path
        local list = watchers[id] or {}
        watchers[id] = list
        local entry = { fn = fn }
        list[#list + 1] = entry
        return function()
            entry.dead = true
            for i = #list, 1, -1 do
                if list[i] == entry then table.remove(list, i) end
            end
        end
    end

    function store:table(scope, path)
        local v = self:get(scope, path)
        if type(v) == "table" then return v end
        if v == nil then
            v = {}
            if self:set(scope, path, v) then return v end
        end
        k.problems:add("store", tostring(scope), "no table at " .. tostring(path))
        return nil
    end

    local function block(scope, reason)
        store.blocked[scope] = reason
        k.problems:add("schema", scope, reason)
    end

    -- Keeps what a skeleton section held before it is replaced. Answers the
    -- end of the problem text: where the old value is, or why it is lost.
    local function keep(scope, db, key)
        local at = "recovered." .. key .. " in the " .. scope .. " data"
        local kept = db.recovered
        if kept == nil then
            kept = {}
            db.recovered = kept
        elseif type(kept) ~= "table" then
            return "the old value is lost: recovered is not a table"
        end
        if kept[key] ~= nil then
            return "the old value is lost: " .. at .. " already holds an older one"
        end
        kept[key] = db[key]
        return "the old value is kept under " .. at
    end

    local function migrate(scope, db)
        local have, want = db.schema, store.schema
        if have == nil then
            db.schema = want
            return
        end
        if type(have) ~= "number" or have % 1 ~= 0 or have < 1 then
            return block(scope, "saved schema is not a whole number: " .. tostring(have))
        end
        if have > want then
            return block(scope, "saved schema " .. have .. " is newer than this build's " .. want)
        end
        if have == want then return end
        local work = deepCopy(db)
        for n = have, want - 1 do
            local step = store.steps[scope][n]
            if type(step) ~= "function" then
                return block(scope, "no migration step from schema " .. n)
            end
            local ok, out = pcall(step, work)
            if not ok then
                return block(scope, "migration step from schema " .. n .. " failed: " .. tostring(out))
            end
            if type(out) ~= "table" then
                return block(scope, "migration step from schema " .. n .. " returned no table")
            end
            work = out
            work.schema = n + 1
        end
        for key in pairs(db) do db[key] = nil end
        for key, value in pairs(work) do db[key] = value end
    end

    -- Call once the client has loaded saved data.
    function store:open()
        self.blocked = {}
        for scope, tables in pairs(SKELETON) do
            local db = root(scope)
            migrate(scope, db)
            if not self.blocked[scope] then
                for i = 1, #tables do
                    local key = tables[i]
                    local was = type(db[key])
                    if was ~= "table" then
                        -- Something else was saved there: keep it once, and
                        -- say where it is (or that it is lost).
                        if was ~= "nil" then
                            k.problems:add("store", scope, key .. " was a " .. was
                                .. ", not a table; it was replaced with an empty table; "
                                .. keep(scope, db, key))
                        end
                        db[key] = {}
                    end
                end
            end
        end
        self.opened = true
        return next(self.blocked) == nil
    end

    return store
end

-- Lead section 188: the capture sanitizer. Lua 5.1.
--   lua5.1 tools/offline/zflow-sanitize.lua <capture> <out> [<capture> <out> ...]
--
-- A capture is a saved-variables file as the game writes it (ZFlow.lua:
-- ZFlowDB = { ... }; the per-character file: ZFlowCharDB = { ... }). The
-- sanitizer gives a copy in which every character, realm, guild and
-- account name, and every chat or mail text, is replaced by a fixed
-- made-up one. Everything else is copied as it was.
--
-- It fails closed. Every field of the capture must be in the schema
-- (zflow-sanitize-schema.lua) with its kind. A field the schema does not
-- know, a value of the wrong type, a global other than the saved tables,
-- or text that is not saved-variables data stops the run: nothing is
-- written, and the error names the path of the field, never its value.
--
-- The file is parsed, never run as Lua. The copy is written only when the
-- whole capture was understood. <out> must not be <capture>, and an <out>
-- that already exists is not overwritten.
--
-- Made-up names: the same real name always gets the same made-up one, in
-- order of first sight, the capture walked in sorted key order:
--   character  Character1, Character2 ...   realm    Realm1 ...
--   guild      Guild1 ...                    account  ACCOUNT1 ...
--   chat       chat text 1 ...               mail     mail text 1 ...
--   free text  text 1 ...
-- "Name-Realm" (a character with its realm) becomes "Character1-Realm1";
-- "Realm-Faction" (the auction price keys) becomes "Realm1-Alliance".
-- Text the schema marks "free" (error lines, log lines, labels, export
-- lines, keys of the open-ended tables) is replaced whole by a made-up
-- "text 1", "text 2" ... (the same text, the same made-up one), unless it
-- holds no letter at all (numbers, times, versions such as 1.16.1), which
-- is kept. Section 190: a name that is only ever in free text cannot be
-- told from the other words, and a name of one or two letters cannot be
-- found in text without breaking ordinary words, so free text is not
-- searched for names; it is not kept.
--
-- Section 192 (S6): a character, realm, guild or account name is matched in
-- any case and with spaces, punctuation and hyphens ignored, so "Cinder
-- Reach", "CinderReach" and "cinder-reach" are one realm with one made-up
-- name. Text that is kept as it is ("str", a text "scalar", a key of an open
-- table) is replaced whole like free text when it holds a known name: the
-- whole text is the name, a word of it is the name (any length, so a name
-- of one or two letters is caught as a word), or a name of four letters or
-- more is inside it with spaces and punctuation ignored. This replaces more
-- than it must (an item or a word that is also a name); that is the side it
-- errs on. Letters above ASCII are matched as bytes, not by case.
--
-- Exit code: 0 = written, 1 = refused (a field, type or global the schema
-- does not know), 2 = could not run (bad arguments, no capture, not
-- saved-variables data, <out> exists).
local S = {}

-- ------------------------------------------------------------------ parse

local function parseError(pos, what)
    error({ sanitize = "parse", msg = "not saved-variables data at byte " .. pos .. ": " .. what }, 0)
end

local ESC = {
    n = "\n", t = "\t", r = "\r", a = "\a", b = "\b", f = "\f", v = "\v",
    ["\\"] = "\\", ["\""] = "\"", ["'"] = "'", ["\n"] = "\n",
}

-- S.parse(text) -> { [globalName] = value }, order
--   Accepts only Name = value, where a value is a string, a number, true,
--   false, nil or a table of ["key"] = value, [number] = value, key = value
--   and bare values, with -- comments. Anything else is an error.
function S.parse(text)
    local pos, len = 1, #text
    local function skip()
        while pos <= len do
            local c = text:sub(pos, pos)
            if c:match("%s") then pos = pos + 1
            elseif text:sub(pos, pos + 1) == "--" then
                local e = text:find("\n", pos, true)
                pos = e and e + 1 or len + 1
            else break end
        end
    end
    local value
    local function str()
        local q = text:sub(pos, pos)
        pos = pos + 1
        local out = {}
        while true do
            if pos > len then parseError(pos, "a string not closed") end
            local c = text:sub(pos, pos)
            if c == q then pos = pos + 1; break end
            if c == "\n" then parseError(pos, "a line end inside a string") end
            if c == "\\" then
                local n = text:sub(pos + 1, pos + 1)
                if ESC[n] then out[#out + 1] = ESC[n]; pos = pos + 2
                elseif n == "\r" and text:sub(pos + 2, pos + 2) == "\n" then out[#out + 1] = "\n"; pos = pos + 3
                elseif n:match("%d") then
                    local d = text:match("^%d%d?%d?", pos + 1)
                    local code = tonumber(d)
                    if code > 255 then parseError(pos, "an escape past 255") end
                    out[#out + 1] = string.char(code); pos = pos + 1 + #d
                else parseError(pos, "an unknown escape") end
            else out[#out + 1] = c; pos = pos + 1 end
        end
        return table.concat(out)
    end
    local function num()
        local h = text:match("^%-?0[xX]%x+", pos)
        if h then pos = pos + #h; return tonumber(h) end
        local s = text:match("^%-?%d+%.?%d*[eE][%+%-]?%d+", pos) or text:match("^%-?%d+%.?%d*", pos)
            or text:match("^%-?%.%d+[eE][%+%-]?%d+", pos) or text:match("^%-?%.%d+", pos)
        if not s then parseError(pos, "a value expected") end
        local n = tonumber(s)
        if n == nil then parseError(pos, "a number that does not read") end
        pos = pos + #s
        return n
    end
    local function tbl()
        pos = pos + 1
        local t, n = {}, 0
        while true do
            skip()
            if pos > len then parseError(pos, "a table not closed") end
            local c = text:sub(pos, pos)
            if c == "}" then pos = pos + 1; return t end
            local key
            if c == "[" then
                pos = pos + 1
                key = value()
                if type(key) ~= "string" and type(key) ~= "number" then parseError(pos, "a key that is not text or a number") end
                skip()
                if text:sub(pos, pos) ~= "]" then parseError(pos, "] expected") end
                pos = pos + 1; skip()
                if text:sub(pos, pos) ~= "=" then parseError(pos, "= expected") end
                pos = pos + 1
            elseif text:match("^[%a_][%w_]*%s*=[^=]", pos) then
                key = text:match("^[%a_][%w_]*", pos)
                pos = pos + #key; skip(); pos = pos + 1
            else
                n = n + 1
                key = n
            end
            local v = value()
            if t[key] ~= nil then parseError(pos, "a key given twice") end
            t[key] = v
            skip()
            local d = text:sub(pos, pos)
            if d == "," or d == ";" then pos = pos + 1
            elseif d ~= "}" then parseError(pos, ", or } expected") end
        end
    end
    value = function()
        skip()
        local c = text:sub(pos, pos)
        if c == "\"" or c == "'" then return str() end
        if c == "{" then return tbl() end
        if text:match("^true%f[^%w_]", pos) then pos = pos + 4; return true end
        if text:match("^false%f[^%w_]", pos) then pos = pos + 5; return false end
        if text:match("^nil%f[^%w_]", pos) then pos = pos + 3; return nil end
        return num()
    end
    local globals, order, seen = {}, {}, {}
    while true do
        skip()
        if pos > len then break end
        local name = text:match("^[%a_][%w_]*", pos)
        if not name then parseError(pos, "a global name expected") end
        pos = pos + #name; skip()
        if text:sub(pos, pos) ~= "=" then parseError(pos, "= expected") end
        pos = pos + 1
        if seen[name] then parseError(pos, "a global given twice") end
        seen[name] = true
        globals[name] = value()
        order[#order + 1] = name
    end
    return globals, order
end

-- ------------------------------------------------------------------ write

local function quote(s)
    return (string.format("%q", s):gsub("\\\n", "\\n"):gsub("\r", "\\r"):gsub("%z", "\\0"))
end

-- Number keys first, in order, then text keys, sorted.
local function sortedKeys(t)
    local nums, strs = {}, {}
    for k in pairs(t) do
        if type(k) == "number" then nums[#nums + 1] = k else strs[#strs + 1] = k end
    end
    table.sort(nums); table.sort(strs)
    for _, k in ipairs(strs) do nums[#nums + 1] = k end
    return nums
end
S.sortedKeys = sortedKeys

local function scalar(v)
    if type(v) == "string" then return quote(v) end
    if type(v) == "number" then
        if v ~= v then return "0/0" end
        if v == math.huge then return "math.huge" end
        if v == -math.huge then return "-math.huge" end
        if v == math.floor(v) and math.abs(v) < 2 ^ 53 then return string.format("%d", v) end
        return string.format("%.17g", v)
    end
    return tostring(v)
end

local function writeValue(out, v, indent)
    if type(v) ~= "table" then out[#out + 1] = scalar(v); return end
    out[#out + 1] = "{\n"
    local inner = indent .. "\t"
    for _, k in ipairs(sortedKeys(v)) do
        out[#out + 1] = inner .. "[" .. scalar(k) .. "] = "
        writeValue(out, v[k], inner)
        out[#out + 1] = ",\n"
    end
    out[#out + 1] = indent .. "}"
end

-- S.write(globals, order) -> text in the saved-variables shape, keys sorted.
function S.write(globals, order)
    local out = {}
    for _, name in ipairs(order) do
        out[#out + 1] = name .. " = "
        writeValue(out, globals[name], "")
        out[#out + 1] = "\n"
    end
    return table.concat(out)
end

-- ------------------------------------------------------------- the walk
-- A spec is one of:
--   "num" "bool" "str" "scalar"   kept as it is ("str": text that is never
--                                 a name: an item, a spell, a setting value,
--                                 a fixed word of the add-on)
--   "char" "realm" "guild" "account" "chat" "mail"   replaced
--   "charRealm"                   "Name-Realm", both halves replaced
--   "realmFaction"                "Realm-Faction", the realm replaced, the
--                                 faction (after the last "-") kept
--   "free"                        replaced whole ("text 1" ...), unless
--                                 it holds no letter: then kept
--   "fieldKey"                    a key of an open table: kept when it is
--                                 a lower-case-first ASCII word (an add-on
--                                 field such as money or lastSeen; a
--                                 character or realm name always starts
--                                 with a capital) and holds no known name,
--                                 else as "free"
-- Kept text ("str", text "scalar", a kept "fieldKey") that holds a known
-- name is replaced as "free" (S6).
--   "nothing"                     never saved: refused when present
--   { fields = { key = spec }, open = spec }   a table with these text
--                                 keys; open: any other key, of that spec
--   { list = spec }               entries 1..n, nothing else
--   { map = spec, key = keySpec } any keys (keySpec "str", "num", "scalar",
--                                 "char", "realm", "charRealm" ...)
--   { any = { spec, ... } }       the first of these whose type fits

local NAME_KINDS = {
    char = "Character", realm = "Realm", guild = "Guild", account = "ACCOUNT",
    chat = "chat text ", mail = "mail text ", free = "text ",
}
S.NAME_KINDS = NAME_KINDS

-- The kinds matched in any spelling (S6), and in kept text.
local FOLDED = { char = true, realm = true, guild = true, account = true }

-- norm(text) -> lower case, every ASCII space, control and punctuation byte
-- removed. Bytes above 127 are kept as they are.
local function norm(s)
    return (s:lower():gsub("[%c%p%s]", ""))
end
S.norm = norm

local function refuse(path, what) error({ sanitize = "refuse", msg = what .. " at " .. path }, 0) end

-- A path names keys that are fixed words; a key that is data is <key>,
-- so a refusal never prints a name.
local function pathOf(path, k, keyIsData)
    if type(k) == "number" then return path .. "[" .. k .. "]" end
    if not keyIsData and type(k) == "string" and k:match("^[%a_][%w_]*$") and #k <= 40 then return path .. "." .. k end
    return path .. "[<key>]"
end

-- S.new() -> a run: run.names[kind][real] = made-up, filled in order.
function S.new()
    local run = { names = {}, counts = {} }
    for kind in pairs(NAME_KINDS) do run.names[kind] = {}; run.counts[kind] = 0 end
    return run
end

-- madeUp: a name kind is keyed by norm(real), so every spelling of one
-- name gets one made-up name; chat, mail and free text are keyed as they are.
local function madeUp(run, kind, real)
    if real == "" then return "" end
    local key = real
    if FOLDED[kind] then
        key = norm(real)
        if key == "" then key = real end
    end
    local got = run.names[kind][key]
    if got then return got end
    run.counts[kind] = run.counts[kind] + 1
    got = NAME_KINDS[kind] .. run.counts[kind]
    run.names[kind][key] = got
    return got
end

-- S.know(run): after pass one, the names found, for holdsName.
function S.know(run)
    local set, long = {}, {}
    for kind in pairs(FOLDED) do
        for key in pairs(run.names[kind]) do
            if not set[key] then
                set[key] = true
                if #key >= 4 then long[#long + 1] = key end
            end
        end
    end
    table.sort(long)
    run.known = { set = set, long = long }
end

-- holdsName(run, text) -> true when the text is a known name, a word of it
-- is one, or a known name of four bytes or more is inside it, all compared
-- through norm. False before S.know.
local function holdsName(run, text)
    local k = run.known
    if not k then return false end
    local n = norm(text)
    if k.set[n] then return true end
    for w in text:gmatch("[^%c%p%s]+") do
        if k.set[w:lower()] then return true end
    end
    for _, name in ipairs(k.long) do
        if n:find(name, 1, true) then return true end
    end
    return false
end
S.holdsName = holdsName

local function charRealm(run, v)
    local name, realm = v:match("^([^%-]+)%-(.+)$")
    if not name then return madeUp(run, "char", v) end
    return madeUp(run, "char", name) .. "-" .. madeUp(run, "realm", realm)
end

local function realmFaction(run, v)
    local realm, faction = v:match("^(.+)%-([^%-]*)$")
    if not realm then return madeUp(run, "realm", v) end
    return madeUp(run, "realm", realm) .. "-" .. faction
end

local function isList(t)
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then return false end
        n = n + 1
    end
    return n == #t
end

-- S.free(run, text) -> text kept when it holds only digits, ASCII
-- punctuation and spaces (no letter, so no name: any byte above 127 counts
-- as a letter); else its made-up "text N".
function S.free(run, text)
    if text:match("^[%d%p%s]*$") then return text end
    return madeUp(run, "free", text)
end

local function fits(spec, v)
    if type(spec) == "table" then return type(v) == "table" end
    if spec == "num" then return type(v) == "number" end
    if spec == "bool" then return type(v) == "boolean" end
    if spec == "scalar" then return type(v) ~= "table" end
    if spec == "nothing" then return false end
    return type(v) == "string"
end

local walk

local function leaf(run, spec, v, path, copy)
    local tv = type(v)
    if spec == "nothing" then refuse(path, "a field that is never saved") end
    if spec == "num" or spec == "bool" or spec == "scalar" then
        if not fits(spec, v) then refuse(path, "a " .. tv .. " where " .. spec .. " is saved") end
        if copy and tv == "string" and holdsName(run, v) then return S.free(run, v) end
        return v
    end
    if tv ~= "string" then refuse(path, "a " .. tv .. " where text is saved") end
    if spec == "str" then
        if copy and holdsName(run, v) then return S.free(run, v) end
        return v
    end
    -- Before the name kinds: "free" is one of them, but text with no
    -- letter is kept.
    if spec == "free" then return S.free(run, v) end
    if spec == "fieldKey" then
        if v:match("^%l[%w_]*$") and not (copy and holdsName(run, v)) then return v end
        return S.free(run, v)
    end
    if NAME_KINDS[spec] then return madeUp(run, spec, v) end
    if spec == "charRealm" then return charRealm(run, v) end
    if spec == "realmFaction" then return realmFaction(run, v) end
    refuse(path, "a schema kind the sanitizer does not know")
end

walk = function(run, spec, v, path, copy)
    if type(spec) == "table" and spec.any then
        for _, s in ipairs(spec.any) do
            if fits(s, v) then return walk(run, s, v, path, copy) end
        end
        refuse(path, "a " .. type(v) .. " the schema does not allow")
    end
    if type(spec) ~= "table" then return leaf(run, spec, v, path, copy) end
    if type(v) ~= "table" then refuse(path, "a " .. type(v) .. " where a table is saved") end
    local out = {}
    if spec.list then
        if not isList(v) then refuse(path, "a key that is not a list index") end
        for i = 1, #v do out[i] = walk(run, spec.list, v[i], pathOf(path, i), copy) end
        return out
    end
    if spec.map then
        local keySpec = spec.key or "str"
        for _, k in ipairs(sortedKeys(v)) do
            -- A map key is data: never printed in a refusal.
            local kp = pathOf(path, k, true)
            local nk = walk(run, keySpec, k, path .. "[<key>]", copy)
            if out[nk] ~= nil then refuse(kp, "two keys that become the same made-up key") end
            out[nk] = walk(run, spec.map, v[k], kp, copy)
        end
        return out
    end
    if spec.fields then
        for _, k in ipairs(sortedKeys(v)) do
            local s = type(k) == "string" and spec.fields[k] or nil
            local known = s ~= nil
            if s == nil then s = spec.open end
            if s == nil then refuse(pathOf(path, k, true), "a field the schema does not know") end
            out[k] = walk(run, s, v[k], pathOf(path, k, not known), copy)
        end
        return out
    end
    refuse(path, "a schema entry with no fields, list or map")
end

-- S.sanitize(globals, order, schema) -> copy, run   (raises { sanitize, msg })
--   schema.globals[name] is the spec of that saved table; any other global
--   is refused. Pass one finds every name and numbers them; pass two
--   copies with the numbers pass one gave, and replaces kept text that
--   holds a name pass one found (S6).
function S.sanitize(globals, order, schema)
    for _, name in ipairs(order) do
        if not schema.globals[name] then refuse("<global>", "a global the schema does not know") end
    end
    local run = S.new()
    for _, name in ipairs(order) do walk(run, schema.globals[name], globals[name], name, false) end
    S.know(run)
    local copy = {}
    for _, name in ipairs(order) do copy[name] = walk(run, schema.globals[name], globals[name], name, true) end
    return copy, run
end

-- S.texts(texts, schema) -> { sanitized text, ... }, or nil, kind, message
--   The files of one capture (ZFlow.lua and the character file), sanitized
--   in one run: a name gets the same made-up name in every file, and free
--   text gets the same made-up text in every file. A global saved
--   in two files is refused.
--   kind: "parse" (not saved-variables data), "refuse" (the schema), "bug"
function S.texts(texts, schema)
    local ok, a = pcall(function()
        local all, allOrder, orders = {}, {}, {}
        for i, text in ipairs(texts) do
            local g, order = S.parse(text)
            for _, name in ipairs(order) do
                if all[name] ~= nil then refuse("<global>", "a global saved in two files") end
                all[name] = g[name]
                allOrder[#allOrder + 1] = name
            end
            orders[i] = order
        end
        local copy = S.sanitize(all, allOrder, schema)
        local outs = {}
        for i, order in ipairs(orders) do outs[i] = S.write(copy, order) end
        return outs
    end)
    if ok then return a end
    if type(a) == "table" and a.sanitize then return nil, a.sanitize, a.msg end
    return nil, "bug", tostring(a)
end

-- S.text(text, schema) -> sanitized text, or nil, kind, message
function S.text(text, schema)
    local outs, kind, msg = S.texts({ text }, schema)
    if not outs then return nil, kind, msg end
    return outs[1]
end

-- -------------------------------------------------------------------- cli
--   zflow-sanitize.lua <capture> <out> [<capture> <out> ...]
-- One pair for each file of the capture; every pair in one run.

local function main(argv)
    local here = (argv[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
    local n = #argv
    if n == 0 or n % 2 ~= 0 then
        io.stderr:write("usage: zflow-sanitize.lua <capture> <out> [<capture> <out> ...]\n")
        return 2
    end
    local inputs, outputs, seen = {}, {}, {}
    for i = 1, n, 2 do
        inputs[#inputs + 1], outputs[#outputs + 1] = argv[i], argv[i + 1]
    end
    for i, output in ipairs(outputs) do
        for _, input in ipairs(inputs) do
            if input == output then io.stderr:write("zflow-sanitize: an <out> must not be a capture\n"); return 2 end
        end
        if seen[output] then io.stderr:write("zflow-sanitize: an <out> given twice\n"); return 2 end
        seen[output] = true
        local exists = io.open(output, "rb")
        if exists then exists:close(); io.stderr:write("zflow-sanitize: <out> " .. i .. " exists; not overwritten\n"); return 2 end
    end
    local texts = {}
    for i, input in ipairs(inputs) do
        local f = io.open(input, "rb")
        if not f then io.stderr:write("zflow-sanitize: no capture at path " .. i .. "\n"); return 2 end
        texts[i] = f:read("*a")
        f:close()
    end
    local schema = dofile(here .. "/zflow-sanitize-schema.lua")
    local outs, kind, msg = S.texts(texts, schema)
    if not outs then
        io.stderr:write("zflow-sanitize: " .. kind .. ": " .. tostring(msg) .. "; nothing written\n")
        return kind == "refuse" and 1 or 2
    end
    for i, output in ipairs(outputs) do
        local w = io.open(output, "wb")
        if not w then io.stderr:write("zflow-sanitize: cannot write <out> " .. i .. "\n"); return 2 end
        w:write(outs[i])
        w:close()
    end
    print("zflow-sanitize: written " .. #outputs)
    return 0
end

if arg and arg[0] and arg[0]:match("zflow%-sanitize%.lua$") then os.exit(main(arg)) end
return S

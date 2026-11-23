local _, ns = ...
-- UI/SettingsShare.lua's text format, read as data only (row N70). Pure:
-- no add-on is booted. Made-up keys and values.
local tests = {}

local FORBIDDEN = { "loadstring", "load", "setfenv", "dofile", "loadfile", "getfenv", "require" }

-- Every function the module holds, and the ones they make (string.dump
-- writes a function with every function inside it, and every global name
-- it reads is a constant there). A name found in that text is a name the
-- module's code reads.
local function dumps(S)
    local out = {}
    for name, fn in pairs(S) do
        if type(fn) == "function" then out[#out + 1] = { name = name, text = string.dump(fn) } end
    end
    return out
end

-- Fails before: ns.SettingsShare is absent.
tests["settings share: the module never names loadstring, load, setfenv, dofile or loadfile"] = function(t)
    local S = ns.SettingsShare
    t.ok(type(S) == "table", "the module is loaded")
    if type(S) ~= "table" then return end
    local all = dumps(S)
    t.ok(#all >= 6, "its functions are read: " .. #all)
    for _, d in ipairs(all) do
        for _, word in ipairs(FORBIDDEN) do
            -- As a whole name: "load" inside "loaded" or "upload" is not it.
            local hit = false
            local from = 1
            while true do
                local a, b = d.text:find(word, from, true)
                if not a then break end
                local before, after = d.text:sub(a - 1, a - 1), d.text:sub(b + 1, b + 1)
                if not before:find("[%w_]") and not after:find("[%w_]") then hit = true end
                from = b + 1
            end
            t.eq(hit, false, d.name .. " names " .. word)
        end
    end
end

-- Fails before: ns.SettingsShare is absent.
-- Code in the text stays text: it comes back as a choice's words, or is
-- skipped, and is never anything but a string, a number or true/false.
tests["settings share: code in a pasted text comes back as plain data"] = function(t)
    local S = ns.SettingsShare
    t.ok(type(S) == "table" and type(S.Decode) == "function", "the decoder is there")
    if type(S) ~= "table" or type(S.Decode) ~= "function" then return end
    local ok, got = pcall(S.Decode, S.HEADER .. ";account:x.y=choice:return%20os.exit()%3B;END:1")
    t.eq(ok, true, "the decoder does not raise")
    t.eq(got and got.items, { { scope = "account", key = "x.y", type = "choice", value = "return os.exit();" } },
        "the code is a choice's text, nothing more")
    local ok2, none, why = pcall(S.Decode, "return os.exit()")
    t.eq({ ok2, none, why }, { true, nil, S.NOT_EXPORT }, "a bare chunk is not an export")
    local ok3, nums = pcall(S.Decode, S.HEADER .. ";account:a.b=num:0x10;account:c.d=num:1e309;END:2")
    t.eq(ok3, true)
    t.eq(nums and #nums.items, 0, "hex and infinite numbers are skipped")
end

-- The wire text is fixed (lead section 258): an export made today must
-- read in every later version.
tests["settings share: the wire header is exactly ZFLOW-EXPORT:1"] = function(t)
    local S = ns.SettingsShare
    t.eq(S and S.HEADER, "ZFLOW-EXPORT:1")
    t.eq(S and S.Encode({}), "ZFLOW-EXPORT:1;END:0", "an empty export, byte for byte")
    t.eq(S and S.Encode({ { scope = "char", key = "a.b", type = "choice", value = "x y" } }),
        "ZFLOW-EXPORT:1;char:a.b=choice:x%20y;END:1", "a setting, byte for byte")
end

-- Fails before: ns.SettingsShare is absent.
tests["settings share: encode then decode gives the same items; escapes, numbers and limits"] = function(t)
    local S = ns.SettingsShare
    if type(S) ~= "table" or type(S.Encode) ~= "function" then
        t.ok(false, "the module is loaded")
        return
    end
    local items = {
        { scope = "account", key = "nav.crossings", type = "bool", value = false },
        { scope = "char", key = "advisor.panel", type = "bool", value = true },
        { scope = "account", key = "repair.warnBelow", type = "number", value = 0.35 },
        { scope = "account", key = "a.b", type = "number", value = -12 },
        { scope = "account", key = "arrow.style", type = "choice", value = "flat; odd|c=word%" },
    }
    local text = S.Encode(items)
    t.eq(text:find("|", 1, true), nil, "no bar: the game reads it as a code")
    t.eq(text:find("%s"), nil, "one line, no spaces")
    local got, why = S.Decode(text)
    t.eq(why, nil)
    t.eq(got and got.items, items, "the same items come back")
    t.eq(got and #got.skipped, 0)

    local bad = S.Decode(S.HEADER .. ";account:a.b=num:0x10;account:c.d=num:1e309;account:e.f=choice:%zz;"
        .. "account:g.h=bool:yes;nowhere:i.j=bool:1;account:a.b=bool:1;END:6")
    t.eq(bad and #bad.items, 0, "nothing of that is a value")
    t.eq(bad and #bad.skipped, 6, "all six are skipped and counted")

    t.eq(select(2, S.Decode(string.rep("a", S.MAX_BYTES + 1))), S.TOO_LONG)
    local many = { S.HEADER }
    for i = 1, S.MAX_ITEMS + 1 do many[#many + 1] = "account:k" .. i .. "=bool:1" end
    many[#many + 1] = "END:" .. (S.MAX_ITEMS + 1)
    local long = table.concat(many, ";")
    if #long <= S.MAX_BYTES then
        t.eq(select(2, S.Decode(long)), S.TOO_MANY)
    else
        t.eq(select(2, S.Decode(long)), S.TOO_LONG)
    end
    t.eq(select(2, S.Decode("ZFLOW-EXPORT:2;END:0")), S.NOT_EXPORT, "another version is not read")
    t.ok(S.Decode(S.HEADER .. ";END:0") ~= nil, "an empty export reads")
end

return tests

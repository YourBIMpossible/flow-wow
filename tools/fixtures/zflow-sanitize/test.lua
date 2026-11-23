-- Lead section 188: tests of tools/offline/zflow-sanitize.lua on made-up
-- captures. Every name here is made up. Run by run.ps1:
--   lua5.1 tools/fixtures/zflow-sanitize/test.lua
-- Prints PASS or FAIL for each case; exit 0 when all pass, 1 when not.
local here = (arg[0]:match("^(.*)[/\\][^/\\]*$") or ".")
local offline = here .. "/../../offline"
local S = dofile(offline .. "/zflow-sanitize.lua")
local schema = dofile(offline .. "/zflow-sanitize-schema.lua")

local function read(path)
    local f = assert(io.open(path, "rb"))
    local t = f:read("*a")
    f:close()
    return t
end

local failed, cases = 0, 0
local function case(name, fn)
    cases = cases + 1
    local why = {}
    local t = {
        ok = function(v, msg) if not v then why[#why + 1] = msg or "not ok" end end,
        has = function(text, part, msg)
            if not text or not text:find(part, 1, true) then why[#why + 1] = (msg or "missing") .. ": " .. part end
        end,
        hasNot = function(text, part, msg)
            if text and text:find(part, 1, true) then why[#why + 1] = (msg or "must not hold") .. ": " .. part end
        end,
    }
    local ok, err = pcall(fn, t)
    if not ok then why[#why + 1] = "raised: " .. tostring(err) end
    if #why == 0 then print("PASS " .. name) return end
    failed = failed + 1
    print("FAIL " .. name .. ": " .. table.concat(why, "; "))
end

-- Every kind of name the sanitizer replaces, in one made-up capture with
-- its own schema (ZFlow saves no guild, account, chat or mail text; the
-- engine still knows those kinds).
local KINDS = {
    globals = {
        Kinds = {
            fields = {
                char = "char", realm = "realm", guild = "guild", account = "account",
                chat = { list = "chat" }, mail = "mail", who = "charRealm",
                again = "char", note = "free",
                byChar = { map = "num", key = "char" },
            },
        },
    },
}
local KINDS_TEXT = table.concat({
    "Kinds = {",
    "[\"char\"] = \"Aldwynne\",",
    "[\"realm\"] = \"Mossvale\",",
    "[\"guild\"] = \"Order of the Pale Lantern\",",
    "[\"account\"] = \"WREN1234#5678\",",
    "[\"chat\"] = { \"lfg deadmines, whisper Aldwynne\", \"selling copper\", },",
    "[\"mail\"] = \"Thanks for the bags. Brannoch\",",
    "[\"who\"] = \"Brannoch-Cinder-Reach\",",
    "[\"again\"] = \"Aldwynne\",",
    "[\"note\"] = \"Aldwynne of Mossvale, Order of the Pale Lantern, WREN1234#5678, Brannoch\",",
    "[\"byChar\"] = { [\"Kestrelle\"] = 3, },",
    "}",
}, "\n")
local REAL = {
    "Aldwynne", "Mossvale", "Order of the Pale Lantern", "WREN1234", "lfg deadmines",
    "selling copper", "Thanks for the bags", "Brannoch", "Cinder-Reach", "Kestrelle",
}

case("every kind of name is replaced by its made-up one", function(t)
    local out, kind, msg = S.text(KINDS_TEXT, KINDS)
    t.ok(out ~= nil, "refused: " .. tostring(kind) .. " " .. tostring(msg))
    for _, real in ipairs(REAL) do t.hasNot(out, real, "a real name left") end
    for _, fake in ipairs({ "Character1", "Realm1", "Guild1", "ACCOUNT1", "chat text 1", "chat text 2",
            "mail text 1", "Character3-Realm2" }) do
        t.has(out, fake)
    end
end)

case("the same name gets the same made-up name; a second run gives the same bytes", function(t)
    local out = S.text(KINDS_TEXT, KINDS)
    local g = S.parse(out)
    t.ok(g.Kinds.char == g.Kinds.again, "char and again differ")
    t.ok(out == S.text(KINDS_TEXT, KINDS), "two runs differ")
end)

case("free text is scrubbed of every name found, the longest first", function(t)
    local g = S.parse(S.text(KINDS_TEXT, KINDS))
    t.ok(g.Kinds.note == "Character1 of Realm1, Guild1, ACCOUNT1, Character3", "note: " .. tostring(g.Kinds.note))
end)

-- The ZFlow capture: both files in one run, the real schema.
local ACCOUNT = read(here .. "/capture/ZFlow.lua")
local CHAR = read(here .. "/capture/ZFlowChar.lua")
local CAPTURE_NAMES = { "Aldwynne", "Mossvale", "Brannoch", "Cinder-Reach", "Kestrelle" }

case("ZFlow capture: no made-up real name left in either file; the shapes kept", function(t)
    local outs, kind, msg = S.texts({ ACCOUNT, CHAR }, schema)
    t.ok(outs ~= nil, "refused: " .. tostring(kind) .. " " .. tostring(msg))
    if not outs then return end
    for _, out in ipairs(outs) do
        for _, real in ipairs(CAPTURE_NAMES) do t.hasNot(out, real, "a real name left") end
    end
    local a, c = S.parse(outs[1]), S.parse(outs[2])
    local snap = a.ZFlowDB.diag.snaps[1]
    t.ok(snap.timing.character == "Character1", "character: " .. tostring(snap.timing.character))
    t.ok(snap.timing.realm == "Realm1", "realm: " .. tostring(snap.timing.realm))
    t.ok(snap.shapes.fullName.values.v1 == "Character1", "fullName v1")
    t.ok(snap.shapes.fullName.values.v2 == "Realm1", "fullName v2")
    t.ok(snap.reads.money == 987654, "a number kept")
    t.ok(snap.shapes.build.values.v1 == "1.16.1", "game text kept")
    t.ok(a.ZFlowDB.learned.prices.auction["Realm1-Alliance"] ~= nil, "auction key: realm replaced, faction kept")
    t.ok(a.ZFlowDB.learned.prices.auctionHistory["Realm2-Horde"] ~= nil, "a realm with a hyphen in it")
    t.has(snap.timing.errors[1].text, "Character1-Realm1 has no guild", "error text")
    t.ok(c.ZFlowCharDB.state.nav.waypoint.label == "meet Character2 here",
        "a name from the account file scrubbed in the character file: " .. tostring(c.ZFlowCharDB.state.nav.waypoint.label))
    t.ok(c.ZFlowCharDB.learned.fights.mobs["Kobold Miner"] == nil, "mob keys treated as names")
    t.ok(c.ZFlowCharDB.export.lines[1] == "E^quest^title=The Realm1 Road", "export line scrubbed")
end)

case("a field the schema does not know is refused, and its value is not in the message", function(t)
    local text = ACCOUNT:gsub("%[\"schema\"%] = 1,", "[\"schema\"] = 1,\n[\"guildRoster\"] = { \"Fenwick\", },", 1)
    local out, kind, msg = S.texts({ text }, schema)
    t.ok(out == nil, "written")
    t.ok(kind == "refuse", "kind: " .. tostring(kind))
    t.has(msg, "a field the schema does not know")
    t.hasNot(msg, "Fenwick")
    t.hasNot(msg, "guildRoster", "a data key printed")
end)

case("a field the schema does not know deep in diag is refused", function(t)
    local text = ACCOUNT:gsub("%[\"start\"%] = 6,", "[\"start\"] = 6,\n[\"guild\"] = \"Order of the Pale Lantern\",", 1)
    local out, kind = S.texts({ text }, schema)
    t.ok(out == nil and kind == "refuse", "kind: " .. tostring(kind))
end)

case("a wrong type is refused", function(t)
    local text = ACCOUNT:gsub("%[\"character\"%] = \"Aldwynne\",", "[\"character\"] = { \"Aldwynne\", },", 1)
    local out, kind, msg = S.texts({ text }, schema)
    t.ok(out == nil and kind == "refuse", "kind: " .. tostring(kind))
    t.hasNot(msg, "Aldwynne")
end)

case("a global the schema does not know is refused", function(t)
    local out, kind = S.texts({ ACCOUNT .. "\nOtherAddonDB = { [\"owner\"] = \"Aldwynne\", }\n" }, schema)
    t.ok(out == nil and kind == "refuse", "kind: " .. tostring(kind))
end)

case("the same global in two files is refused", function(t)
    local out, kind = S.texts({ ACCOUNT, ACCOUNT }, schema)
    t.ok(out == nil and kind == "refuse", "kind: " .. tostring(kind))
end)

case("text that is not saved-variables data is not parsed: calls, cut off files", function(t)
    for _, text in ipairs({
        "ZFlowDB = os.execute(\"x\")",
        "ZFlowDB = {",
        "ZFlowDB = { [\"a\"] = 1 [\"b\"] = 2 }",
        "ZFlowDB = { [\"a\"] = 1, [\"a\"] = 2, }",
        "ZFlowDB = { [\"a\"] = \"open",
    }) do
        local out, kind = S.texts({ text }, schema)
        t.ok(out == nil and kind == "parse", "not refused as parse: " .. text)
    end
end)

case("two keys that become the same key are refused", function(t)
    -- An open subtree keyed by free text: "Brannoch" becomes "Character2",
    -- which is already a key there.
    local text = CHAR:gsub("%[\"nav\"%] = {",
        "[\"notes\"] = { [\"Brannoch\"] = 1, [\"Character2\"] = 2, },\n[\"nav\"] = {", 1)
    local out, kind = S.texts({ ACCOUNT, text }, schema)
    t.ok(out == nil and kind == "refuse", "kind: " .. tostring(kind))
end)

case("the output reads back the same through the parser", function(t)
    local outs = S.texts({ ACCOUNT, CHAR }, schema)
    t.ok(outs ~= nil, "refused")
    if not outs then return end
    local again = S.texts({ outs[1], outs[2] }, schema)
    t.ok(again ~= nil, "the copy itself refused")
    t.ok(again and again[1] == outs[1] and again[2] == outs[2], "a second pass changed the copy")
end)

print(string.format("%d of %d cases passed", cases - failed, cases))
os.exit(failed == 0 and 0 or 1)

-- Feedback (row N73, lead sections 247 and 251): the report as plain text,
-- the in-game cleaner and the caps (UI/Feedback.lua Build, Clean,
-- CleanTyped, CutPaths, Mask, Field, Clip). Pure: no client, no kernel.
-- Made-up words, names and paths only.
-- Fails before section 251's rework: Feedback.Clean, CleanTyped and
-- CutPaths are absent, and the diagnostics block was built from Diag's
-- error list and a whole-report name mask.
local _, ns = ...

local F = ns.Feedback
local ADDON = ns.id.addon

local function has(t)
    local ok = type(F) == "table" and type(F.Build) == "function" and type(F.Clean) == "function"
        and type(F.CleanTyped) == "function" and type(F.CutPaths) == "function" and type(F.Mask) == "function"
    t.ok(ok, "ns.Feedback answers Build, Clean, CleanTyped, CutPaths and Mask")
    return ok
end

local function lines(text)
    local out = {}
    for line in tostring(text):gmatch("[^\n]+") do out[#out + 1] = line end
    return out
end

-- What Feedback.Collect answers, with three entries the allowlist does not
-- name (a read flag, a read and a read holding text).
local DIAG = {
    version = "0.1.0", build = "1.16.1 (7777)", at = 12.7, clock = true, namesAsked = 180, namesMissing = 23,
    known = { { "money", true }, { "bags", false }, { "plumtree", true } },
    reads = { { "in combat", false }, { "bag stacks", 12 }, { "plumtree", 3 }, { "bank open", "plumtree" } },
    phase = "running", paused = false, loaded = true, eventsNot = 0, eventsAbsent = 2, noEventFrame = false,
    noTickFrame = false, starts = 3, count = 17, readRecords = 2,
    problems = { "arrow, row: refused (x1)" }, problemCount = 1, dropped = false, texts = true,
}

-- Every string held anywhere in a table, three levels down.
local function strings(tbl, out, depth)
    out, depth = out or {}, depth or 0
    for _, v in pairs(tbl) do
        if type(v) == "string" then
            out[#out + 1] = v
        elseif type(v) == "table" and depth < 3 then
            strings(v, out, depth + 1)
        end
    end
    return out
end

return {
    ["feedback report: each kind has its heading and the description; only a problem has the two more fields"] = function(t)
        if not has(t) then return end
        local form = { kind = "problem", description = "The arrow spins", happened = "It turned twice",
            expected = "It should point at the quest" }
        t.eq(F.Build(form, nil, {}, "T", ADDON), "T feedback: Problem report\nDescription: The arrow spins\n"
            .. "What happened: It turned twice\nWhat was expected: It should point at the quest")
        form.kind = "suggest"
        t.eq(F.Build(form, nil, {}, "T", ADDON), "T feedback: Suggested improvement\nDescription: The arrow spins",
            "what happened and what was expected are a problem's")
        form.kind = "idea"
        t.eq(F.Build(form, nil, {}, "T", ADDON), "T feedback: Idea\nDescription: The arrow spins")
        t.eq(F.Build({ kind = "problem", description = "Only this" }, nil, {}, "T", ADDON),
            "T feedback: Problem report\nDescription: Only this", "an optional field left empty has no line")
    end,

    ["feedback report: with no diagnostics attached there is no diagnostics line at all"] = function(t)
        if not has(t) then return end
        local text = F.Build({ kind = "idea", description = "A thought" }, nil, {}, "T", ADDON)
        t.eq(#lines(text), 2)
        t.eq(text:find(F.DIAG_HEAD, 1, true), nil)
        t.eq(text:find(F.NO_DIAG, 1, true), nil)
        t.eq(text:find("Version", 1, true), nil)
    end,

    -- Lead section 251: an allowlist. Every line is numbers, yes or no, or
    -- fixed words; what the list does not name is not printed.
    ["feedback report: the diagnostics block is the allowlisted values, as numbers, yes or no and fixed words"] = function(t)
        if not has(t) then return end
        t.eq(lines(F.Build({ kind = "idea", description = "A thought" }, DIAG, {}, "T", ADDON)), {
            "T feedback: Idea",
            "Description: A thought",
            F.DIAG_HEAD,
            "Version: 0.1.0; game build: 1.16.1 (7777)",
            "Snapshot: seconds since start 12; wall clock: yes",
            "Client names asked: 180; missing: 23",
            "Reads known: money yes, bags no",
            "Reads: in combat no; bag stacks 12",
            "State: running; paused: no; saved data loaded: yes",
            "Events not registered: 0; expected absent: 2; event frame missing: no; tick frame missing: no",
            "Snapshots: starts 3; kept 17; read records 2",
            "The add-on's own problems, newest first: 1",
            "  arrow, row: refused (x1)",
        })
        local odd = { version = 7, build = { "x" }, at = "plumtree", clock = "plumtree", namesAsked = "plumtree",
            phase = "plumtree", paused = "plumtree", starts = "plumtree", problems = { { "plumtree" }, 4 },
            problemCount = "plumtree", known = "plumtree", reads = { "plumtree" }, texts = true }
        local text = F.Build({ kind = "idea", description = "A thought" }, odd, {}, "T", ADDON)
        t.eq(text:find("plumtree", 1, true), nil, "a value of the wrong kind is never printed: " .. text)
        t.ok(text:find("State: other; paused: no", 1, true) ~= nil, "a phase that is not one of the kernel's reads other")
    end,

    ["feedback report: diagnostics that could not be collected leave the feedback whole, with one line saying so"] = function(t)
        if not has(t) then return end
        t.eq(lines(F.Build({ kind = "problem", description = "It broke", happened = "A box" }, false, {}, "T", ADDON)), {
            "T feedback: Problem report",
            "Description: It broke",
            "What happened: A box",
            F.NO_DIAG,
        })
        local dropped = { phase = "running", problems = { "kept, one: fine (x1)" }, problemCount = 2, dropped = true,
            texts = true }
        local got = lines(F.Build({ kind = "idea", description = "d" }, dropped, {}, "T", ADDON))
        t.eq(got[#got], F.ERROR_DROPPED, "a line the cleaner could not do is said, once")
        t.eq(got[#got - 1], "  kept, one: fine (x1)", "and the others are there")
        local counted = { phase = "running", problems = {}, problemCount = 2, texts = false }
        got = lines(F.Build({ kind = "idea", description = "d" }, counted, {}, "T", ADDON))
        t.eq(got[#got], F.TEXTS_OUT, "problems only counted say why")
    end,

    -- The in-game cleaner (lead section 251).
    ["feedback cleaner: a path is cut to the part from the add-on's folder on; any other path is dropped whole"] = function(t)
        if not has(t) then return end
        t.eq(F.Clean("Interface\\AddOns\\" .. ADDON .. "\\UI\\Made.lua:12: it broke", {}, ADDON),
            ADDON .. "\\UI\\Made.lua:12: it broke")
        t.eq(F.Clean("C:\\Users\\Marlowe Finch\\WoW\\Interface\\AddOns\\" .. ADDON .. "\\Core\\X.lua:3: it broke", {}, ADDON),
            ADDON .. "\\Core\\X.lua:3: it broke", "a folder name with a blank in it goes too")
        t.eq(F.Clean("Interface/AddOns/" .. ADDON .. "/UI/A.lua:1: it broke", {}, ADDON), ADDON .. "/UI/A.lua:1: it broke")
        t.eq(F.Clean("read C:\\Users\\Marlowe Finch\\Documents\\notes.txt and stopped", {}, ADDON),
            "read " .. F.PATH .. " and stopped")
        t.eq(F.Clean("Interface\\AddOns\\Elsewhere\\Other.lua:9: theirs", {}, ADDON), F.PATH .. " theirs")
        t.eq(F.Clean("no path here", {}, ADDON), "no path here")
        t.eq(F.CutPaths("a b", ADDON, false), "a b")
    end,

    ["feedback cleaner: links, quoted text and the player's own names are replaced by fixed words; the line is cut"] = function(t)
        if not has(t) then return end
        t.eq(F.Clean("bad |cff0070dd|Hitem:4321:0:0|h[Blade of Brannoch]|h|r here", {}, ADDON), "bad " .. F.LINK .. " here")
        t.eq(F.Clean("saw item:4321:55:0 twice", {}, ADDON), "saw " .. F.LINK .. " twice", "a bare item string")
        t.eq(F.Clean('it said "meet Brannoch at dusk" and left', {}, ADDON), "it said " .. F.QUOTED .. " and left")
        t.eq(F.Clean("field 'bag' is nil", {}, ADDON), "field " .. F.QUOTED .. " is nil")
        t.eq(F.Clean("Zarkon of STORMRAGE in Knights of Zar", { "Knights of Zar", "Stormrage", "Zarkon" }, ADDON),
            F.HIDDEN .. " of " .. F.HIDDEN .. " in " .. F.HIDDEN)
        t.eq(F.Clean("two\nlines", {}, ADDON), "two lines", "one line")
        t.ok(type(F.MAX_ERROR_CHARS) == "number", "the cap is a constant")
        t.eq(#F.Clean(string.rep("word ", 200), {}, ADDON), F.MAX_ERROR_CHARS)
        local all = F.Clean("Interface\\AddOns\\" .. ADDON .. "\\UI\\Made.lua:12: Zarkon said \"hello Brannoch\" of |Hitem:1|h[x]|h",
            { "Zarkon" }, ADDON)
        t.eq(all, ADDON .. "\\UI\\Made.lua:12: " .. F.HIDDEN .. " said " .. F.QUOTED .. " of " .. F.LINK)
    end,

    ["feedback typed text: the player's own names and a file path are taken out; no other word is altered"] = function(t)
        if not has(t) then return end
        t.eq(F.CleanTyped("it is on/off near Zarkon, see C:\\Users\\Marlowe\\shot.png", { "Zarkon" }, ADDON),
            "it is on/off near " .. F.HIDDEN .. ", see " .. F.PATH)
        t.eq(F.CleanTyped('he said "hi" about item 4321 and 1/2 of it', {}, ADDON), 'he said "hi" about item 4321 and 1/2 of it',
            "quotes, numbers and a slash in ordinary words stay")
        t.eq(F.CleanTyped("saved at d:/games/shot.png", {}, ADDON), "saved at " .. F.PATH, "a drive letter")
        local report = F.Build({ kind = "problem", description = "Zarkon cannot loot", happened = "in STORMRAGE",
            expected = "see C:\\Users\\Marlowe\\x.txt" }, nil, { "Stormrage", "Zarkon" }, "T", ADDON)
        local low = report:lower()
        for _, word in ipairs({ "zarkon", "stormrage", "marlowe", "users" }) do
            t.eq(low:find(word, 1, true), nil, word .. " is not in the report: " .. report)
        end
        t.ok(report:find(F.HIDDEN .. " cannot loot", 1, true) ~= nil, "the rest of the words are there")
    end,

    ["feedback mask: a name is replaced wherever it stands, whatever its capitals"] = function(t)
        if not has(t) then return end
        local text, n = F.Mask("Zarkon met ZARKON of Stormrage; zarkon's guild", { "Zarkon", "Stormrage" })
        t.eq(text, F.HIDDEN .. " met " .. F.HIDDEN .. " of " .. F.HIDDEN .. "; " .. F.HIDDEN .. "'s guild")
        t.eq(n, 4)
        t.eq((F.Mask("nothing here", { "Zarkon" })), "nothing here")
        t.eq((F.Mask("a b", { "a", "", 7 })), "a b", "a one-letter name, an empty one and a number are not names")
    end,

    ["feedback caps: a typed field, a diagnostics line, the problem list and the whole report are each cut at a fixed size"] = function(t)
        if not has(t) then return end
        for _, name in ipairs({ "MAX_FIELD", "MAX_LINE", "MAX_ERRORS", "MAX_ERROR_CHARS", "MAX_DIAG_LINES", "MAX_BYTES" }) do
            t.ok(type(F[name]) == "number" and F[name] >= 1, name .. " is a number")
        end
        t.eq(#F.Field(string.rep("a", F.MAX_FIELD + 50)), F.MAX_FIELD)
        t.eq(F.Field("  two\nlines\there  "), "two lines here", "one plain line")
        t.eq(F.Field(nil), "")
        t.eq(F.Clip("ab\195\169", 3), "ab", "never cut inside a letter of two bytes")
        t.eq(F.Clip("abc", 5), "abc")
        local many = { version = "1", build = "2", phase = "running", loaded = true, problems = {}, problemCount = 30,
            texts = true }
        for i = 1, 30 do many.problems[i] = "p" .. i .. " " .. string.rep("x", 400) end
        local all = lines(F.Build({ kind = "idea", description = "d" }, many, {}, "T", ADDON))
        local listed = 0
        for i = 3, #all do
            t.ok(#all[i] <= F.MAX_LINE, "line " .. i .. " is cut: " .. #all[i])
            if all[i]:sub(1, 3) == "  p" then listed = listed + 1 end
        end
        t.eq(listed, F.MAX_ERRORS, "the list is cut")
        t.ok(#all - 2 <= F.MAX_DIAG_LINES, "the diagnostics block has its most lines")
        local long = { kind = "problem", description = string.rep("d", 900), happened = string.rep("h", 900),
            expected = string.rep("e", 900) }
        local big = F.Build(long, many, {}, "T", ADDON)
        t.ok(#big <= F.MAX_BYTES, "the whole report: " .. #big)
        local last = lines(big)
        t.eq(last[#last], F.CUT, "and it says it was cut")
        t.ok(#F.Build({ kind = "idea", description = "d" }, nil, {}, "T", ADDON) < 100, "a short one is not touched")
    end,

    ["feedback wording: nothing says Sent or Submitted; the button says Copy report; no address is set"] = function(t)
        if not has(t) then return end
        local all = strings(F)
        t.ok(#all >= 30, "the module's words were read: " .. #all)
        all[#all + 1] = F.Build({ kind = "problem", description = "d", happened = "h", expected = "e" }, DIAG, {}, "T", ADDON)
        all[#all + 1] = F.Build({ kind = "idea", description = "d" }, false, {}, "T", ADDON)
        for _, text in ipairs(all) do
            local low = " " .. text:lower() .. " "
            t.eq(low:find("%Asent%A"), nil, text)
            t.eq(low:find("submitted", 1, true), nil, text)
            t.eq(low:find("upload", 1, true), nil, text)
        end
        t.eq(F.COPY, "Copy report")
        t.eq(F.DESTINATION, "", "where a report goes is not decided yet")
    end,
}

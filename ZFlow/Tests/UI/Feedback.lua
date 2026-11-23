-- Feedback (row N73, lead section 247): the report as plain text, the name
-- mask and the caps (UI/Feedback.lua Build, Mask, Field, Clip). Pure: no
-- client, no kernel. Made-up words and names only.
-- Fails before: UI/Feedback.lua is absent (ns.Feedback is nil).
local _, ns = ...

local F = ns.Feedback

local function has(t)
    local ok = type(F) == "table" and type(F.Build) == "function" and type(F.Mask) == "function"
        and type(F.Field) == "function" and type(F.Clip) == "function"
    t.ok(ok, "ns.Feedback answers Build, Mask, Field and Clip")
    return ok
end

local function lines(text)
    local out = {}
    for line in tostring(text):gmatch("[^\n]+") do out[#out + 1] = line end
    return out
end

local DIAG = {
    version = "0.1.0", build = "1.16.1 (7777)",
    errors = { { text = "a.lua:1: oops", count = 2 } }, errorCount = 1,
    phase = "running", paused = false, loaded = true,
    problems = { { kind = "arrow", owner = "row", text = "refused", count = 1 } }, problemCount = 1,
    texts = true,
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
        t.eq(F.Build(form, nil, {}, "T"), "T feedback: Problem report\nDescription: The arrow spins\n"
            .. "What happened: It turned twice\nWhat was expected: It should point at the quest")
        form.kind = "suggest"
        t.eq(F.Build(form, nil, {}, "T"), "T feedback: Suggested improvement\nDescription: The arrow spins",
            "what happened and what was expected are a problem's")
        form.kind = "idea"
        t.eq(F.Build(form, nil, {}, "T"), "T feedback: Idea\nDescription: The arrow spins")
        t.eq(F.Build({ kind = "problem", description = "Only this" }, nil, {}, "T"),
            "T feedback: Problem report\nDescription: Only this", "an optional field left empty has no line")
    end,

    ["feedback report: with no diagnostics attached there is no diagnostics line at all"] = function(t)
        if not has(t) then return end
        local text = F.Build({ kind = "idea", description = "A thought" }, nil, {}, "T")
        t.eq(#lines(text), 2)
        t.eq(text:find(F.DIAG_HEAD, 1, true), nil)
        t.eq(text:find(F.NO_DIAG, 1, true), nil)
        t.eq(text:find("Version", 1, true), nil)
    end,

    ["feedback report: attached diagnostics are the version and build, the add-on's errors and a short state"] = function(t)
        if not has(t) then return end
        t.eq(lines(F.Build({ kind = "idea", description = "A thought" }, DIAG, {}, "T")), {
            "T feedback: Idea",
            "Description: A thought",
            F.DIAG_HEAD,
            "Version: 0.1.0; game build: 1.16.1 (7777)",
            "The add-on's own recent errors: 1",
            "  a.lua:1: oops (x2)",
            "State: running; paused: no; saved data loaded: yes",
            "Problems the add-on listed: 1",
            "  arrow / row: refused (x1)",
        })
    end,

    ["feedback report: diagnostics that could not be collected leave the feedback whole, with one line saying so"] = function(t)
        if not has(t) then return end
        t.eq(lines(F.Build({ kind = "problem", description = "It broke", happened = "A box" }, false, {}, "T")), {
            "T feedback: Problem report",
            "Description: It broke",
            "What happened: A box",
            F.NO_DIAG,
        })
    end,

    ["feedback mask: a name is taken out wherever it stands, whatever its capitals, typed text included"] = function(t)
        if not has(t) then return end
        local text, n = F.Mask("Zarkon met ZARKON of Stormrage; zarkon's guild", { "Zarkon", "Stormrage" })
        t.eq(text, F.HIDDEN .. " met " .. F.HIDDEN .. " of " .. F.HIDDEN .. "; " .. F.HIDDEN .. "'s guild")
        t.eq(n, 4)
        t.eq((F.Mask("nothing here", { "Zarkon" })), "nothing here")
        t.eq((F.Mask("a b", { "a", "", 7 })), "a b", "a one-letter name, an empty one and a number are not names")
        t.eq((F.Mask("WTF\\Account\\MYLOGIN\\x.lua and Account/Other/y", {})),
            "WTF\\Account\\" .. F.HIDDEN .. "\\x.lua and Account/" .. F.HIDDEN .. "/y", "the account's folder in a path")
        local report = F.Build({ kind = "problem", description = "Zarkon cannot loot", happened = "in STORMRAGE" },
            { version = "1", build = "2", errors = { { text = "x.lua:1: Zarkon is nil", count = 1 } }, errorCount = 1,
              phase = "running", loaded = true, problems = { { kind = "k", owner = "Zarkon", text = "Knights of Zar", count = 1 } },
              problemCount = 1, texts = true },
            { "Knights of Zar", "Stormrage", "Zarkon" }, "T")
        local low = report:lower()
        for _, name in ipairs({ "zarkon", "stormrage", "knights of zar" }) do
            t.eq(low:find(name, 1, true), nil, name .. " is not in the report")
        end
        t.ok(report:find(F.HIDDEN .. " cannot loot", 1, true) ~= nil, "the typed text is masked too: " .. report)
    end,

    ["feedback caps: a typed field, a diagnostics line, the lists and the whole report are each cut at a fixed size"] = function(t)
        if not has(t) then return end
        for _, name in ipairs({ "MAX_FIELD", "MAX_LINE", "MAX_ERRORS", "MAX_PROBLEMS", "MAX_DIAG_LINES", "MAX_BYTES" }) do
            t.ok(type(F[name]) == "number" and F[name] >= 1, name .. " is a number")
        end
        t.eq(#F.Field(string.rep("a", F.MAX_FIELD + 50)), F.MAX_FIELD)
        t.eq(F.Field("  two\nlines\there  "), "two lines here", "one plain line")
        t.eq(F.Field(nil), "")
        t.eq(F.Clip("ab\195\169", 3), "ab", "never cut inside a letter of two bytes")
        t.eq(F.Clip("abc", 5), "abc")
        local many = { version = "1", build = "2", errors = {}, errorCount = 30, phase = "running", loaded = true,
            problems = {}, problemCount = 30, texts = true }
        for i = 1, 30 do
            many.errors[i] = { text = "e" .. i .. " " .. string.rep("x", 400), count = 1 }
            many.problems[i] = { kind = "k", owner = "o", text = "p" .. i, count = 1 }
        end
        local text = F.Build({ kind = "idea", description = "d" }, many, {}, "T")
        local all = lines(text)
        t.eq(#all, 2 + 4 + F.MAX_ERRORS + F.MAX_PROBLEMS, "the lists are cut")
        t.ok(#all - 2 <= F.MAX_DIAG_LINES, "the diagnostics block has its most lines")
        for i = 3, #all do t.ok(#all[i] <= F.MAX_LINE, "line " .. i .. " is cut: " .. #all[i]) end
        local long = { kind = "problem", description = string.rep("d", 900), happened = string.rep("h", 900),
            expected = string.rep("e", 900) }
        local big = F.Build(long, many, {}, "T")
        t.ok(#big <= F.MAX_BYTES, "the whole report: " .. #big)
        local last = lines(big)
        t.eq(last[#last], F.CUT, "and it says it was cut")
        t.ok(#F.Build({ kind = "idea", description = "d" }, nil, {}, "T") < 100, "a short one is not touched")
    end,

    ["feedback wording: nothing says Sent or Submitted; the button says Copy report; no address is set"] = function(t)
        if not has(t) then return end
        local all = strings(F)
        t.ok(#all >= 30, "the module's words were read: " .. #all)
        all[#all + 1] = F.Build({ kind = "problem", description = "d", happened = "h", expected = "e" }, DIAG, {}, "T")
        all[#all + 1] = F.Build({ kind = "idea", description = "d" }, false, {}, "T")
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

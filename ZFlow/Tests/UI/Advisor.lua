local _, ns = ...

-- Tests for ZFlow/UI/Advisor.lua (U-A, G32): the advisor panel. Other
-- modules register short prompts with Add(id, text, priority) and take them
-- back with Remove(id); the panel lists them, highest priority first, and is
-- hidden when there are none. The setting row "advisor.panel" turns it off.
-- The prompts here come from a fake prompt source: a test module that needs
-- the advisor and registers through it, the way L6-C, L6-D and A-B will.
-- Fake client; not tested in game.

local A = ns.Advisor
local tests = {}

-- opts: setting (true / false / nil: no row declared), noFrames,
-- prompts (list of { id, text, priority } the fake source adds at its start).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    if opts.noFrames then c.setFrames(false) end
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    if opts.setting ~= nil then
        k:Setting({ key = A.SETTING, scope = "char", type = "bool", default = true, label = "Advisor panel" })
    end
    local api = A.Declare(k)
    local source = {}
    k:Module({
        name = "fakePromptSource",
        needs = { A.NAME },
        start = function(ctx)
            source.advisor = ctx.use(A.NAME)
            for _, p in ipairs(opts.prompts or {}) do
                source.advisor.Add(p[1], p[2], p[3])
            end
        end,
    })
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    if opts.setting == false then k.settings:set(A.SETTING, false) end
    return k, c, api, source
end

local function panelOf(c)
    for _, p in ipairs(c.panels) do
        if type(p.spec) == "table" and p.spec.name == ns.id.framePrefix .. "Advisor" then return p end
    end
    return nil
end

tests["advisor panel: declared, started, and hidden while it has no prompts"] = function(t)
    local k, c, api = start()
    t.eq((k:ModuleState(A.NAME)), "started")
    local p = panelOf(c)
    t.ok(p ~= nil, "the panel is made")
    t.eq(p.shown, false, "hidden with no prompts")
    t.eq(api.List(), {}, "no prompts")
    t.ok(type(ns.advisor) == "table", "the addon's own is declared")
    t.eq(ns.Advisor.Add, ns.advisor.Add, "Advisor.Add is the addon's own")
    t.eq(ns.Advisor.Remove, ns.advisor.Remove, "Advisor.Remove is the addon's own")
end

tests["advisor panel: prompts from another module show, highest priority first"] = function(t)
    local _, c, _, source = start({ prompts = {
        { "repair", "Your gear is badly damaged: repair at the next vendor.", 20 },
        { "bank", "Bank your reagents at the next banker.", 50 },
    } })
    t.ok(type(source.advisor) == "table", "the source reached the advisor through its needs")
    local p = panelOf(c)
    t.eq(p.shown, true, "shown")
    t.eq(p.lines, {
        "Bank your reagents at the next banker.",
        "Your gear is badly damaged: repair at the next vendor.",
    }, "priority 50 above priority 20")
end

tests["advisor panel: equal priority keeps the order added; adding an id again replaces it"] = function(t)
    local _, c, api = start()
    t.eq(api.Add("a", "First.", 10), true)
    t.eq(api.Add("b", "Second.", 10), true)
    t.eq(panelOf(c).lines, { "First.", "Second." }, "added order on a tie")
    t.eq(api.Add("a", "First, changed.", 5), true)
    t.eq(panelOf(c).lines, { "Second.", "First, changed." }, "replaced text and priority, no second line")
    t.eq(#api.List(), 2, "still two prompts")
end

tests["advisor panel: Remove takes a prompt back, and the last one hides the panel"] = function(t)
    local _, c, api = start()
    api.Add("a", "First.", 1)
    api.Add("b", "Second.", 2)
    t.eq(api.Remove("b"), true, "removed")
    t.eq(panelOf(c).lines, { "First." })
    t.eq(api.Remove("b"), false, "an id that is not there")
    t.eq(api.Remove("a"), true)
    t.eq(panelOf(c).shown, false, "hidden when empty")
    t.eq(api.List(), {})
end

tests["advisor panel: a missing priority is 0; bad arguments are refused and change nothing"] = function(t)
    local _, c, api = start()
    t.eq(api.Add("plain", "No priority given."), true, "priority may be left out")
    t.eq(api.List()[1].priority, 0, "and is then 0")
    local bad = {
        { nil, "text", 1 },
        { "", "text", 1 },
        { 7, "text", 1 },
        { "id", nil, 1 },
        { "id", "", 1 },
        { "id", {}, 1 },
        { "id", "text", "high" },
        { "id", "text", 0 / 0 },
    }
    for i, b in ipairs(bad) do
        local ok, why = api.Add(b[1], b[2], b[3])
        t.eq(ok, false, "refused: case " .. i)
        t.ok(type(why) == "string" and why ~= "", "with a reason: case " .. i)
    end
    t.eq(#api.List(), 1, "only the good one")
    t.eq(panelOf(c).lines, { "No priority given." })
    local ok = api.Remove(nil)
    t.eq(ok, false, "Remove(nil) is refused")
end

tests["advisor panel: it lists at most MAX_SHOWN prompts and says how many more there are"] = function(t)
    local _, c, api = start()
    local n = A.MAX_SHOWN + 2
    for i = 1, n do api.Add("p" .. i, "Prompt " .. i .. ".", i) end
    local lines = panelOf(c).lines
    t.eq(#lines, A.MAX_SHOWN + 1, "the shown prompts and one more line")
    t.eq(lines[1], "Prompt " .. n .. ".", "the highest first")
    t.eq(lines[#lines], "and 2 more", "the rest are counted")
    t.eq(#api.List(), n, "List holds every prompt")
end

tests["advisor panel: on by default, also before the lead's settings row exists"] = function(t)
    local _, c = start({ setting = true, prompts = { { "a", "A prompt.", 1 } } })
    t.eq(panelOf(c).shown, true, "row declared, default on: shown")
    local _, c2 = start({ prompts = { { "a", "A prompt.", 1 } } })
    t.eq(panelOf(c2).shown, true, "no row yet: shown")
    t.eq(A.SETTING, "advisor.panel", "the settings row's name")
end

tests["advisor panel: advisor.panel off hides it at once and keeps the prompts"] = function(t)
    local k, c, api = start({ setting = true, prompts = { { "a", "A prompt.", 1 } } })
    k.settings:set(A.SETTING, false)
    t.eq(panelOf(c).shown, false, "hidden when turned off")
    t.eq(api.Add("b", "Another.", 2), true, "prompts are still taken")
    t.eq(panelOf(c).shown, false, "and not shown while off")
    t.eq(#api.List(), 2, "both kept")
    k.settings:set(A.SETTING, true)
    t.eq(panelOf(c).shown, true, "shown again when turned on")
    t.eq(panelOf(c).lines, { "Another.", "A prompt." })
end

tests["advisor panel: off from the start never shows"] = function(t)
    local _, c, api = start({ setting = false })
    api.Add("a", "A prompt.", 1)
    t.eq(panelOf(c).shown, false, "not shown")
end

tests["advisor panel: a prompt added before login shows once the panel starts"] = function(t)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    local api = A.Declare(k)
    t.eq(api.Add("early", "Added while files load.", 3), true, "taken before start")
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    local p = panelOf(c)
    t.eq(p.shown, true, "shown at start")
    t.eq(p.lines, { "Added while files load." })
end

tests["advisor panel: a client that cannot draw still keeps the prompts"] = function(t)
    local k, c, api = start({ noFrames = true })
    t.eq((k:ModuleState(A.NAME)), "started", "still started")
    t.eq(api.Add("a", "A prompt.", 1), true)
    t.eq(#c.panels, 0, "no panel")
    t.eq(#api.List(), 1, "kept")
end

tests["advisor panel: List gives copies in shown order"] = function(t)
    local _, _, api = start()
    api.Add("a", "A.", 1)
    api.Add("b", "B.", 9)
    local list = api.List()
    t.eq(list, { { id = "b", text = "B.", priority = 9 }, { id = "a", text = "A.", priority = 1 } })
    list[1].text = "changed"
    t.eq(api.List()[1].text, "B.", "changing the copy changes nothing")
end

tests["advisor panel: look only - no buttons, no clicks, no acting functions"] = function(t)
    local _, c, api = start({ prompts = { { "a", "A prompt.", 1 } } })
    local p = panelOf(c)
    for field in pairs(p.spec) do
        local f = tostring(field):lower()
        t.ok(not (f:find("button") or f:find("click") or f:find("secure")), "no acting field on the panel: " .. f)
    end
    for _, tbl in ipairs({ A, api }) do
        for name in pairs(tbl) do
            local n = tostring(name):lower()
            t.ok(not (n:find("sell") or n:find("buy") or n:find("click") or n:find("cast") or n:find("secure")),
                "no acting function: " .. n)
        end
    end
end

return tests

local _, ns = ...

-- The advisor drawn by the shared kit (lead sections 297 item 5 and 322
-- line 4). The prompts other modules add (the profession picker and the
-- profession card among them) are the lines of one kit window, "Advisor";
-- the plain panel is what is left when the kit or the client refuses the
-- window. The older cases (Tests/UI/Advisor.lua) refuse the kit window in
-- their setup and are the plain panel cases.
-- Fake client; not tested in game.
--
-- Red before the code: the advisor asks for no kit window, so
-- c.kitWindows() holds none and every test here fails its first check.

local A = ns.Advisor
local tests = {}

local ID = "Advisor"

-- opts: setting (true: the row is declared), noFrames, kitFails (how many
-- kit windows the client refuses), prompts ({ id, text, priority } added by
-- a module that needs the advisor).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    if opts.noFrames then c.setFrames(false) end
    if opts.kitFails and type(c.setKitFails) == "function" then c.setKitFails(opts.kitFails) end
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    if opts.setting ~= nil then
        k:Setting({ key = A.SETTING, scope = "char", type = "bool", default = true, label = "Advisor panel" })
    end
    local api = A.Declare(k)
    k:Module({
        name = "fakePromptSource",
        needs = { A.NAME },
        start = function(ctx)
            local advisor = ctx.use(A.NAME)
            for _, p in ipairs(opts.prompts or {}) do advisor.Add(p[1], p[2], p[3]) end
        end,
    })
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api
end

local function kit(c)
    if type(c.kitWindows) ~= "function" then return nil end
    return c.kitWindows()[ID]
end

local function kitShown(c)
    local w = kit(c)
    return w ~= nil and w.shown == true
end

-- The words of the window's lines, in drawing order.
local function lines(c)
    local out = {}
    local w = kit(c)
    for _, p in ipairs(w and w.parts or {}) do
        if p.kind == "line" then out[#out + 1] = p.text end
    end
    return out
end

local function panelOf(c)
    for _, p in ipairs(c.panels) do
        if type(p.spec) == "table" and p.spec.name == ns.id.framePrefix .. "Advisor" then return p end
    end
    return nil
end

local function hostProblems(k)
    local kind = ns.KitHost and ns.KitHost.PROBLEM or "kitHost"
    return k.problems:count(kind)
end

tests["advisor kit: the prompts are the lines of one kit window, highest priority first"] = function(t)
    local k, c = start({ prompts = {
        { "repair", "Your gear is badly damaged: repair at the next vendor.", 20 },
        { "bank", "Bank your reagents at the next banker.", 50 },
    } })
    t.eq(kitShown(c), true, "the kit window is shown")
    t.eq(lines(c), {
        "Bank your reagents at the next banker.",
        "Your gear is badly damaged: repair at the next vendor.",
    }, "priority 50 above priority 20")
    local p = panelOf(c)
    t.ok(p ~= nil, "the plain panel is still made, behind the kit")
    t.eq(p and p.shown, false, "and is not shown")
    t.eq(hostProblems(k), 0, "no problem")
end

tests["advisor kit: nothing to say, no window shown; the last prompt taken back hides it"] = function(t)
    local _, c, api = start()
    t.eq(kitShown(c), false, "no prompts: nothing shown")
    t.eq(api.Add("a", "First.", 1), true)
    t.eq(kitShown(c), true, "a prompt: shown")
    t.eq(api.Remove("a"), true)
    t.eq(kitShown(c), false, "hidden when empty")
end

tests["advisor kit: a replaced text is drawn in its line, no second line"] = function(t)
    local _, c, api = start()
    api.Add("a", "First.", 10)
    api.Add("b", "Second.", 10)
    t.eq(lines(c), { "First.", "Second." }, "added order on a tie")
    api.Add("a", "First, changed.", 5)
    t.eq(lines(c), { "Second.", "First, changed." })
end

tests["advisor kit: at most MAX_SHOWN prompts, then how many more"] = function(t)
    local _, c, api = start()
    local n = A.MAX_SHOWN + 2
    for i = 1, n do api.Add("p" .. i, "Prompt " .. i .. ".", i) end
    local got = lines(c)
    t.eq(#got, A.MAX_SHOWN + 1, "the shown prompts and one more line")
    t.eq(got[1], "Prompt " .. n .. ".", "the highest first")
    t.eq(got[#got], "and 2 more", "the rest are counted")
end

tests["advisor kit: advisor.panel off hides the window at once; on shows the kept prompts"] = function(t)
    local k, c, api = start({ setting = true, prompts = { { "a", "A prompt.", 1 } } })
    t.eq(kitShown(c), true, "on by default")
    k.settings:set(A.SETTING, false)
    t.eq(kitShown(c), false, "hidden when turned off")
    api.Add("b", "Another.", 2)
    t.eq(kitShown(c), false, "and not shown while off")
    k.settings:set(A.SETTING, true)
    t.eq(kitShown(c), true, "shown again when turned on")
    t.eq(lines(c), { "Another.", "A prompt." })
end

tests["advisor kit: closed by the player it stays closed for the prompts read; a new prompt opens it"] = function(t)
    local _, c, api = start({ prompts = { { "a", "A prompt.", 1 } } })
    t.eq(kitShown(c), true, "shown")
    t.eq(type(c.kitClose) == "function" and c.kitClose(ID), true, "the player closes it")
    t.eq(kitShown(c), false, "closed")
    api.Add("a", "A prompt, changed.", 1)
    t.eq(kitShown(c), false, "a text replaced is not new: still closed")
    api.Add("b", "Something new.", 2)
    t.eq(kitShown(c), true, "a new prompt opens it")
    t.eq(lines(c), { "Something new.", "A prompt, changed." })
end

tests["advisor kit: a refused kit window hands over to the plain panel, with one problem line"] = function(t)
    local k, c, api = start({ kitFails = math.huge, prompts = { { "a", "A prompt.", 1 } } })
    t.eq(kit(c), nil, "no kit window")
    local p = panelOf(c)
    t.ok(p ~= nil, "the plain panel")
    if p == nil then return end
    t.eq(p.shown, true, "shown in its place")
    t.eq(p.lines, { "A prompt." })
    t.eq(hostProblems(k), 1, "one line says the plain panel is used")
    api.Add("b", "Another.", 2)
    t.eq(p.lines, { "Another.", "A prompt." }, "and it goes on drawing")
    t.eq(hostProblems(k), 1, "said once")
end

tests["advisor kit: a client that cannot draw keeps the prompts and is no kit problem"] = function(t)
    local k, c, api = start({ noFrames = true })
    t.ok(type(ns.KitHost) == "table", "the kit host is loaded")
    t.eq(api.Add("a", "A prompt.", 1), true)
    t.eq(#api.List(), 1, "kept")
    t.eq(kit(c), nil, "no kit window")
    t.eq(hostProblems(k), 0, "no plain panel to hand over to: nothing to report")
end

tests["advisor kit: the view is a window the kit takes, and has nothing to press"] = function(t)
    t.ok(type(A.View) == "function", "Advisor.View")
    if type(A.View) ~= "function" then return end
    local view = A.View({ "First.", "Second.", "and 2 more" })
    local tree, why = ns.Kit.Window(view)
    t.ok(type(tree) == "table", "the kit takes it: " .. tostring(why))
    if type(tree) ~= "table" then return end
    local seen = {}
    ns.Kit.Each(tree, function(part)
        seen[#seen + 1] = part.kind
        t.ok(part.kind ~= "button" and part.onClick == nil, "nothing to press: " .. tostring(part.kind))
    end)
    t.ok(#seen >= 3, "its lines are parts")
    local empty, whyEmpty = ns.Kit.Window(A.View({}))
    t.ok(type(empty) == "table", "no lines is still a window: " .. tostring(whyEmpty))
    local odd, whyOdd = ns.Kit.Window(A.View({ "", 7, "Kept." }))
    t.ok(type(odd) == "table", "a line that is no text does not cost the window: " .. tostring(whyOdd))
end

return tests

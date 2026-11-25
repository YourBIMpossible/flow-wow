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

-- The plain panel's first line is the advisor's title since lead sections
-- 340/341 (the owner saw an untitled box): the lines below start with it.
local TITLE = ns.id.title .. ": Advice"

-- opts: setting (true / false / nil: no row declared), noFrames,
-- prompts (list of { id, text, priority } the fake source adds at its start).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    -- opts.char: the character's saved data (C-46 keeps what was hidden there).
    if opts.char ~= nil then c.setSaved(ns.id.charDB, opts.char) end
    -- The plain panel cases: the kit window is refused, so the advisor
    -- draws on the plain panel (Tests/UI/AdvisorKit.lua has the kit's).
    if type(c.setKitFails) == "function" then c.setKitFails(math.huge) end
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
    t.eq(p.lines, { TITLE,
        "Bank your reagents at the next banker.",
        "Your gear is badly damaged: repair at the next vendor.",
    }, "priority 50 above priority 20")
end

tests["advisor panel: equal priority keeps the order added; adding an id again replaces it"] = function(t)
    local _, c, api = start()
    t.eq(api.Add("a", "First.", 10), true)
    t.eq(api.Add("b", "Second.", 10), true)
    t.eq(panelOf(c).lines, { TITLE, "First.", "Second." }, "added order on a tie")
    t.eq(api.Add("a", "First, changed.", 5), true)
    t.eq(panelOf(c).lines, { TITLE, "Second.", "First, changed." }, "replaced text and priority, no second line")
    t.eq(#api.List(), 2, "still two prompts")
end

tests["advisor panel: Remove takes a prompt back, and the last one hides the panel"] = function(t)
    local _, c, api = start()
    api.Add("a", "First.", 1)
    api.Add("b", "Second.", 2)
    t.eq(api.Remove("b"), true, "removed")
    t.eq(panelOf(c).lines, { TITLE, "First." })
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
    t.eq(panelOf(c).lines, { TITLE, "No priority given." })
    local ok = api.Remove(nil)
    t.eq(ok, false, "Remove(nil) is refused")
end

tests["advisor panel: it lists at most MAX_SHOWN prompts and says how many more there are"] = function(t)
    local _, c, api = start()
    local n = A.MAX_SHOWN + 2
    for i = 1, n do api.Add("p" .. i, "Prompt " .. i .. ".", i) end
    local lines = panelOf(c).lines
    t.eq(lines[1], TITLE, "the title first (sections 340/341)")
    t.eq(#lines, A.MAX_SHOWN + 2, "the title, the shown prompts and one more line")
    t.eq(lines[2], "Prompt " .. n .. ".", "the highest first")
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
    t.eq(panelOf(c).lines, { TITLE, "Another.", "A prompt." })
end

tests["advisor panel: off from the start never shows"] = function(t)
    local _, c, api = start({ setting = false })
    api.Add("a", "A prompt.", 1)
    t.eq(panelOf(c).shown, false, "not shown")
end

tests["advisor panel: a prompt added before login shows once the panel starts"] = function(t)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    -- The plain panel cases: the kit window is refused, so the advisor
    -- draws on the plain panel (Tests/UI/AdvisorKit.lua has the kit's).
    if type(c.setKitFails) == "function" then c.setKitFails(math.huge) end
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
    t.eq(p.lines, { TITLE, "Added while files load." })
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

-- N68: Watch(fn) tells fn(id, text) when a prompt id that was not there is
-- added (a prompt turned true). A replaced text is not new; a prompt taken
-- back and added again is. Returns a cancel function.
tests["advisor panel: Watch hears a new prompt once, not a replaced one, and again after Remove"] = function(t)
    local _, _, api = start()
    if type(api.Watch) ~= "function" then t.ok(false, "api.Watch"); return end
    local heard = {}
    local cancel = api.Watch(function(id, text) heard[#heard + 1] = { id, text } end)
    t.eq(type(cancel), "function", "a cancel function")
    api.Add("a", "First.", 1)
    api.Add("a", "First, changed.", 2)
    t.eq(heard, { { "a", "First." } }, "the replaced text is not new")
    api.Remove("a")
    api.Add("a", "Back.", 1)
    t.eq(heard, { { "a", "First." }, { "a", "Back." } }, "taken back and added again is new")
    api.Add("", "Bad.", 1)
    t.eq(#heard, 2, "a refused prompt is not heard")
    cancel()
    api.Add("b", "Second.", 1)
    t.eq(#heard, 2, "nothing after the cancel")
end

tests["advisor panel: Watch refuses a non-function; a watcher that raises breaks nothing"] = function(t)
    local _, c, api = start()
    if type(api.Watch) ~= "function" then t.ok(false, "api.Watch"); return end
    t.eq(api.Watch("not a function"), nil, "refused")
    local after = {}
    api.Watch(function() error("boom") end)
    api.Watch(function(id) after[#after + 1] = id end)
    t.eq(api.Add("a", "First.", 1), true, "still added")
    t.eq(panelOf(c).lines, { TITLE, "First." }, "still shown")
    t.eq(after, { "a" }, "the next watcher still hears it")
end

tests["advisor panel: Watch is reached through needs and is the addon's own"] = function(t)
    local _, _, _, source = start()
    t.eq(type(source.advisor.Watch), "function", "through needs")
    t.eq(ns.Advisor.Watch, ns.advisor.Watch, "Advisor.Watch is the addon's own")
end

-- Parity row C-44 (lead section 660): an advice row carries how pressing it
-- is. As Flow's Modules/Advisor/Advisor.lua (Adv.Urgency): three levels,
-- said by whoever adds the prompt; here "info", "soon" and "now" (Flow's
-- later, soon, now). Data only: the colour is drawn by another lane.
-- Fails before: Add takes no level and a row has none.
local function levelOf(api, id)
    for _, row in ipairs(api.List()) do
        if row.id == id then return A.Urgency(row), row.urgency end
    end
    return nil
end

tests["advisor urgency: a prompt added with no level is info, and its row is as it always was"] = function(t)
    local _, _, api = start()
    t.eq(api.Add("plain", "Sell your grey items.", 1), true)
    t.eq(api.List(), { { id = "plain", text = "Sell your grey items.", priority = 1 } }, "no new field on the row")
    t.eq(levelOf(api, "plain"), "info")
end

tests["advisor urgency: info said outright is the same as none"] = function(t)
    local _, _, api = start()
    t.eq(api.Add("plain", "Sell your grey items.", 1, "info"), true)
    local level, kept = levelOf(api, "plain")
    t.eq(level, "info")
    t.eq(kept, nil, "info is not kept on the row")
end

tests["advisor urgency: soon is carried on the row"] = function(t)
    local _, _, api = start()
    t.eq(api.Add("bags", "Your bags are nearly full.", 5, "soon"), true)
    local level, kept = levelOf(api, "bags")
    t.eq(level, "soon")
    t.eq(kept, "soon")
end

tests["advisor urgency: now is carried on the row"] = function(t)
    local _, _, api = start()
    t.eq(api.Add("cap", "Your Mining is at its cap: train the next rank.", 5, "now"), true)
    t.eq(levelOf(api, "cap"), "now")
end

tests["advisor urgency: a level that is none of the three is refused and changes nothing"] = function(t)
    local _, _, api = start()
    for _, bad in ipairs({ "later", "red", "", 3, true }) do
        local ok, why = api.Add("x", "A line.", 1, bad)
        t.eq(ok, false, "refused: " .. tostring(bad))
        t.ok(type(why) == "string" and why ~= "", "with a reason")
    end
    t.eq(api.List(), {}, "nothing was added")
    api.Add("x", "A line.", 1, "soon")
    t.eq(api.Add("x", "Another line.", 1, "purple"), false)
    t.eq(api.List()[1].text, "A line.", "the prompt is as it was")
    t.eq(levelOf(api, "x"), "soon")
end

tests["advisor urgency: adding the same prompt again replaces its level"] = function(t)
    local _, _, api = start()
    api.Add("cap", "Your Mining is 10 points under its cap.", 5, "soon")
    api.Add("cap", "Your Mining is at its cap.", 5, "now")
    t.eq(levelOf(api, "cap"), "now")
    api.Add("cap", "Your Mining is fine.", 5)
    local level, kept = levelOf(api, "cap")
    t.eq(level, "info", "no level said: info again")
    t.eq(kept, nil)
    t.eq(#api.List(), 1, "still one row")
end

tests["advisor urgency: the level does not change the order, which is the priority's"] = function(t)
    local _, _, api = start()
    api.Add("low", "Low.", 1, "now")
    api.Add("high", "High.", 9)
    t.eq(api.List()[1].id, "high")
    t.eq(api.List()[2].id, "low")
end

tests["advisor urgency: the pure rule reads a row, and anything else is info"] = function(t)
    t.eq(A.Urgency({ urgency = "now" }), "now")
    t.eq(A.Urgency({ urgency = "soon" }), "soon")
    t.eq(A.Urgency({ urgency = "info" }), "info")
    t.eq(A.Urgency({}), "info")
    t.eq(A.Urgency({ urgency = "later" }), "info", "a word that is no level")
    t.eq(A.Urgency(nil), "info")
    t.eq(A.LEVELS, { "info", "soon", "now" }, "the three levels, least pressing first")
end

tests["advisor urgency: the window's line carries the level, for whoever draws its colour"] = function(t)
    local view = A.View({ "First.", "Second.", "Third." }, "Advice", nil, { nil, "soon", "now" })
    t.eq(view.children[1].urgency, nil, "info: the line as it always was")
    t.eq(view.children[2].urgency, "soon")
    t.eq(view.children[3].urgency, "now")
    local plain = A.View({ "First." }, "Advice")
    t.eq(plain.children[1], { kind = "line", key = "prompt1", text = "First.", wrap = true }, "no levels given")
end

-- Parity row C-46, the data half (lead section 660): a row can be hidden,
-- the hidden ones listed, and one brought back; kept for the character.
-- As Flow's Modules/Advisor/Advisor.lua:83-112 (Adv.KeyOf, Hide, Unhide,
-- Split): the key ignores numbers, so "Train 2 spells" stays hidden as
-- "Train 3 spells". The buttons are another lane's.
-- Fails before: there is no Hide, Unhide or Hidden.
local function ids(list)
    local out = {}
    for i, row in ipairs(list) do out[i] = row.id end
    return out
end

tests["advisor hide: the key of a prompt ignores its numbers"] = function(t)
    t.eq(A.KeyOf("train.2"), A.KeyOf("train.31"))
    t.eq(A.KeyOf("l6c.repair"), "l6c.repair")
    t.ok(A.KeyOf("train.2") ~= A.KeyOf("bags.2"), "another prompt, another key")
    t.eq(A.KeyOf(""), nil)
    t.eq(A.KeyOf(7), nil)
end

tests["advisor hide: a hidden row leaves the list and the panel, and is listed as hidden"] = function(t)
    local _, c, api = start({ char = {} })
    api.Add("repair", "Repair your gear.", 5)
    api.Add("bags", "Your bags are nearly full.", 1, "soon")
    t.eq(api.Hide("repair"), true)
    t.eq(ids(api.List()), { "bags" }, "not among the shown")
    local hidden = api.Hidden()
    t.eq(#hidden, 1)
    t.eq(hidden[1].key, A.KeyOf("repair"))
    t.eq(hidden[1].id, "repair")
    t.eq(hidden[1].text, "Repair your gear.")
    t.eq(hidden[1].applies, true, "the prompt is still there")
    local p = panelOf(c)
    t.eq(p.lines, { TITLE, "Your bags are nearly full." }, "the panel shows the other one only")
    api.Hide("bags")
    t.eq(panelOf(c).shown, false, "nothing left to show: the panel hides")
end

tests["advisor hide: bringing one back shows it again"] = function(t)
    local _, c, api = start({ char = {} })
    api.Add("repair", "Repair your gear.", 5)
    api.Hide("repair")
    t.eq(api.Unhide(A.KeyOf("repair")), true)
    t.eq(ids(api.List()), { "repair" })
    t.eq(api.Hidden(), {})
    t.eq(panelOf(c).shown, true)
    t.eq(api.Unhide(A.KeyOf("repair")), false, "nothing hidden under that key")
    t.eq(api.Unhide(nil), false)
end

tests["advisor hide: what cannot be hidden is refused with a reason"] = function(t)
    local _, _, api = start({ char = {} })
    local ok, why = api.Hide("nothing")
    t.eq(ok, false, "no such prompt")
    t.ok(type(why) == "string" and why ~= "")
    t.eq((api.Hide("")), false)
    t.eq((api.Hide(nil)), false)
    api.Add("repair", "Repair your gear.", 5)
    api.Hide("repair")
    t.eq((api.Hide("repair")), false, "hidden already")
end

tests["advisor hide: it is kept for the character and holds after a reload"] = function(t)
    local _, c, api = start({ char = {} })
    api.Add("train.2", "Train 2 spells.", 5)
    api.Hide("train.2")
    local kept = c.saved(ns.id.charDB)
    local _, _, api2 = start({ char = kept })
    api2.Add("train.3", "Train 3 spells.", 5)
    t.eq(api2.List(), {}, "still hidden, though its number changed")
    local hidden = api2.Hidden()
    t.eq(hidden[1] and hidden[1].text, "Train 3 spells.", "listed with the words it has now")
    local _, _, api3 = start({ char = kept })
    local gone = api3.Hidden()
    t.eq(#gone, 1, "listed though the prompt is not there now")
    t.eq(gone[1].applies, false)
    t.eq(gone[1].id, nil)
    t.eq(gone[1].text, "Train 2 spells.", "with the words it had when hidden")
    t.eq(api3.Unhide(gone[1].key), true, "and it can be brought back")
    api3.Add("train.4", "Train 4 spells.", 5)
    t.eq(ids(api3.List()), { "train.4" })
end

tests["advisor hide: a hidden prompt added again tells no watcher and opens no window"] = function(t)
    local _, c, api = start({ char = {} })
    api.Add("repair", "Repair your gear.", 5)
    api.Hide("repair")
    api.Remove("repair")
    local told = 0
    api.Watch(function() told = told + 1 end)
    api.Add("repair", "Repair your gear.", 5)
    t.eq(told, 0, "no watcher is told of a hidden prompt")
    t.eq(panelOf(c).shown, false)
    api.Add("bags", "Your bags are nearly full.", 1)
    t.eq(told, 1, "one that is not hidden is told as before")
end

tests["advisor hide: saved data that is not a table hides nothing and is not written over"] = function(t)
    local _, c, api = start({ char = { state = { advisor = { hidden = "broken" } } } })
    api.Add("repair", "Repair your gear.", 5)
    t.eq(ids(api.List()), { "repair" })
    t.eq(api.Hidden(), {})
    local ok, why = api.Hide("repair")
    t.eq(ok, false, "refused: what is saved there is not understood")
    t.ok(type(why) == "string" and why ~= "")
    t.eq(c.saved(ns.id.charDB).state.advisor.hidden, "broken", "left as it was")
end

tests["advisor hide: no more than the cap is kept"] = function(t)
    local hidden = {}
    for i = 1, A.MAX_HIDDEN do hidden["k" .. string.rep("x", i)] = { text = "t", at = 0 } end
    local _, _, api = start({ char = { state = { advisor = { hidden = hidden } } } })
    api.Add("repair", "Repair your gear.", 5)
    local ok, why = api.Hide("repair")
    t.eq(ok, false, "past the cap")
    t.ok(type(why) == "string" and why ~= "")
    t.eq(ids(api.List()), { "repair" }, "still shown")
end

return tests

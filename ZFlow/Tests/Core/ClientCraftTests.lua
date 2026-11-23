-- The client reads and the bar the craft queue needs (P-CRAFT, lead section
-- 226: #34 Smelt All, G21 the craft bar). The real client over a
-- hand-built environment; ClientFake's own versions are checked after.
--   c.recipeUsable(id)   -> true | false, why | nil
--   c.moving()           -> true | false | nil
--   c.rowPanel(spec)     -> h: draw(rows, act), show(on), shown(), place(point), onClose
--   c.craftRecipe(id, n) -> true | nil, why   (acts: the player's own click only)
--   c.stopCraftRepeat()  -> true | nil, why   (stops the game repeat; not a craft)
-- Unknown stays unknown: nil is never "nothing needed", "usable" or "still".
-- Needs game test: every call here is a first guess on 16001.
local _, ns = ...

local tests = {}

local function info(row)
    return { C_TradeSkillUI = { GetRecipeInfo = function(id) if id == 2657 then return row end end } }
end

tests["c.recipeUsable: usable, not usable with the reason, or not known"] = function(t)
    t.eq({ ns.make.client(info({ learned = true, disabled = false })).recipeUsable(2657) }, { true })
    t.eq({ ns.make.client(info({ learned = true, disabled = true, disabledReason = "Requires Anvil" })).recipeUsable(2657) },
        { false, "Requires Anvil" })
    t.eq({ ns.make.client(info({ disabled = true })).recipeUsable(2657) }, { false }, "no reason given")
    t.eq({ ns.make.client(info({ learned = false, disabled = false })).recipeUsable(2657) }, { false }, "not learned")
    t.eq(ns.make.client(info({ learned = true })).recipeUsable(2657), nil, "disabled not given: not known")
    t.eq(ns.make.client(info(nil)).recipeUsable(2657), nil, "no answer")
    t.eq(ns.make.client({}).recipeUsable(2657), nil, "no such call")
    t.eq(ns.make.client({ C_TradeSkillUI = { GetRecipeInfo = function() error("no") end } }).recipeUsable(2657), nil)
end

tests["c.moving: from the speed, else the moving flag, or not known"] = function(t)
    local unit
    t.eq(ns.make.client({ GetUnitSpeed = function(u) unit = u; return 7 end }).moving(), true)
    t.eq(unit, "player")
    t.eq(ns.make.client({ GetUnitSpeed = function() return 0 end }).moving(), false)
    t.eq(ns.make.client({ IsPlayerMoving = function() return true end }).moving(), true)
    t.eq(ns.make.client({ IsPlayerMoving = function() return false end }).moving(), false)
    t.eq(ns.make.client({ GetUnitSpeed = function() return nil end, IsPlayerMoving = function() return false end }).moving(),
        false, "a speed not read: the flag")
    t.eq(ns.make.client({}).moving(), nil, "neither call")
    t.eq(ns.make.client({ GetUnitSpeed = function() error("no") end }).moving(), nil)
    t.eq(ns.make.client({ IsPlayerMoving = function() return 1 end }).moving(), nil, "not a plain yes or no")
end

-- A stand-in for the client's frames: every frame made is in env.frames.
local function gameEnv()
    local env = { frames = {}, UIParent = {} }
    function env.CreateFrame(kind, name, parent, template)
        local f = { kind = kind, name = name, parent = parent, template = template, scripts = {}, shown = true,
            enabled = true }
        function f:SetScript(script, fn) self.scripts[script] = fn end
        function f:IsShown() return self.shown end
        function f:Show() self.shown = true end
        function f:Hide()
            local was = self.shown
            self.shown = false
            if was and self.scripts.OnHide then self.scripts.OnHide(self) end
        end
        function f:SetText(s) self.text = s end
        function f:Enable() self.enabled = true end
        function f:Disable() self.enabled = false end
        function f:CreateFontString()
            local fs = { kind = "FontString", parent = self, shown = true }
            function fs:SetText(s) self.text = s end
            function fs:Show() self.shown = true end
            function fs:Hide() self.shown = false end
            env.frames[#env.frames + 1] = fs
            return fs
        end
        env.frames[#env.frames + 1] = f
        if name ~= nil and env[name] == nil then env[name] = f end
        return f
    end
    return env
end

-- The shown buttons on the bar whose text is `label`.
local function buttons(env, label)
    local out = {}
    for _, f in ipairs(env.frames) do
        if f.kind == "Button" and f.shown and f.text == label then out[#out + 1] = f end
    end
    return out
end

local function texts(env)
    local out = {}
    for _, f in ipairs(env.frames) do
        if f.kind == "FontString" and f.shown and type(f.text) == "string" and f.text ~= "" then out[#out + 1] = f.text end
    end
    return out
end

local function has(list, want)
    for _, v in ipairs(list) do if v == want then return true end end
    return false
end

tests["c.rowPanel: rows are drawn, and a click says which row and what it asks"] = function(t)
    local env = gameEnv()
    local h = ns.make.client(env).rowPanel({ name = "TestRows", width = 260 })
    if not h then t.ok(false, "no row panel") return end
    local acts = {}
    h.draw({
        { kind = "info", text = "Making Copper Bar: 0 of 3" },
        { kind = "number", key = "count:2657", label = "Copper Bar", value = 3, min = 0, max = 999 },
        { kind = "button", key = "start", label = "Start", enabled = true },
        { kind = "button", key = "clear", label = "Clear", enabled = false },
    }, function(key, value) acts[#acts + 1] = { key, value } end)
    local shown = texts(env)
    t.ok(has(shown, "Making Copper Bar: 0 of 3"), "the info line")
    t.ok(has(shown, "Copper Bar: 3"), "the number row: " .. table.concat(shown, " | "))
    local start, clear = buttons(env, "Start")[1], buttons(env, "Clear")[1]
    local plus, minus = buttons(env, "+")[1], buttons(env, "-")[1]
    if not (start and clear and plus and minus) then t.ok(false, "a button is missing") return end
    t.eq(clear.enabled, false, "a button not enabled")
    plus.scripts.OnClick(plus)
    minus.scripts.OnClick(minus)
    start.scripts.OnClick(start)
    t.eq(acts, { { "count:2657", 4 }, { "count:2657", 2 }, { "start" } })
end

tests["c.rowPanel: a number is held between its least and its most"] = function(t)
    local env = gameEnv()
    local h = ns.make.client(env).rowPanel({ name = "TestRowsMinMax" })
    if not h then t.ok(false, "no row panel") return end
    local acts = {}
    h.draw({ { kind = "number", key = "n", label = "A", value = 0, min = 0, max = 1 } },
        function(_, value) acts[#acts + 1] = value end)
    buttons(env, "-")[1].scripts.OnClick()
    buttons(env, "+")[1].scripts.OnClick()
    t.eq(acts, { 1 }, "below the least is not asked; one up is")
end

tests["c.rowPanel: a second draw replaces the rows, and an error in act stays in the bar"] = function(t)
    local env = gameEnv()
    local h = ns.make.client(env).rowPanel({ name = "TestRowsTwo" })
    if not h then t.ok(false, "no row panel") return end
    h.draw({ { kind = "button", key = "a", label = "First", enabled = true } }, function() end)
    h.draw({ { kind = "button", key = "b", label = "Second", enabled = true } }, function() error("broken") end)
    t.eq(#buttons(env, "First"), 0, "the old row is gone")
    local b = buttons(env, "Second")[1]
    t.ok(b ~= nil and pcall(b.scripts.OnClick, b), "a click whose act raises does not raise into the client")
end

tests["c.rowPanel: shown, closed by the player, and not made without frames"] = function(t)
    local env = gameEnv()
    local h = ns.make.client(env).rowPanel({ name = "TestRowsShow" })
    if not h then t.ok(false, "no row panel") return end
    t.eq(h.shown(), false, "a new bar is hidden")
    h.show(true)
    t.eq(h.shown(), true)
    local closed = 0
    h.onClose(function() closed = closed + 1 end)
    env.TestRowsShow:Hide()
    t.eq(closed, 1, "the player closed it")
    t.eq(h.shown(), false)
    h.show(false)
    t.eq(closed, 1, "a hide by the add-on is not the player closing it")
    t.eq(ns.make.client({}).rowPanel({ name = "TestNoFrames" }), nil)
end

tests["c.craftRecipe: crafts by recipe number, out of combat only"] = function(t)
    local calls = {}
    local env = { InCombatLockdown = function() return false end,
        C_TradeSkillUI = { CraftRecipe = function(...) calls[#calls + 1] = { ... } end } }
    t.eq({ ns.make.client(env).craftRecipe(2657, 1) }, { true })
    t.eq(calls, { { 2657, 1 } })
    env.InCombatLockdown = function() return true end
    t.eq({ ns.make.client(env).craftRecipe(2657, 1) }, { nil, "combat" })
    env.InCombatLockdown = nil
    t.eq({ ns.make.client(env).craftRecipe(2657, 1) }, { nil, "combat" }, "combat not known: no craft")
    t.eq(#calls, 1, "nothing asked in combat")
end

tests["c.craftRecipe: refuses what it cannot ask"] = function(t)
    local calls = 0
    local env = { InCombatLockdown = function() return false end,
        C_TradeSkillUI = { CraftRecipe = function() calls = calls + 1 end } }
    local c = ns.make.client(env)
    for _, bad in ipairs({ { "2657", 1 }, { 0, 1 }, { 2657.5, 1 }, { 2657, 0 }, { 2657, 1.5 }, { false, 1 } }) do
        t.eq({ c.craftRecipe(bad[1], bad[2]) }, { nil, "bad" }, tostring(bad[1]) .. " x " .. tostring(bad[2]))
    end
    t.eq(calls, 0)
    t.eq({ ns.make.client({ InCombatLockdown = function() return false end }).craftRecipe(2657, 1) }, { nil, "noCall" })
    env.C_TradeSkillUI.CraftRecipe = function() error("no") end
    t.eq({ ns.make.client(env).craftRecipe(2657, 1) }, { nil, "raised" })
end

tests["c.stopCraftRepeat: asks the game to stop the repeat, never a craft"] = function(t)
    local stops, crafts = 0, 0
    local env = { InCombatLockdown = function() return true end,
        C_TradeSkillUI = { StopRecipeRepeat = function() stops = stops + 1 end,
            CraftRecipe = function() crafts = crafts + 1 end } }
    t.eq({ ns.make.client(env).stopCraftRepeat() }, { true }, "a stop is asked in combat too")
    t.eq(stops, 1)
    t.eq(crafts, 0)
    t.eq({ ns.make.client({}).stopCraftRepeat() }, { nil, "noCall" })
    env.C_TradeSkillUI.StopRecipeRepeat = function() error("no") end
    t.eq({ ns.make.client(env).stopCraftRepeat() }, { nil, "raised" })
end

-- Lead section 237, section 236 item 2: the craft calls are names the
-- capture records, so the next login shows which the client has.
tests["diag: the craft and repeat names are recorded at login"] = function(t)
    local listed = {}
    for _, name in ipairs(ns.Diag.NAMES) do listed[name] = true end
    for _, name in ipairs({ "C_TradeSkillUI.CraftRecipe", "C_TradeSkillUI.StopRecipeRepeat",
        "C_TradeSkillUI.IsRecipeRepeating" }) do
        t.ok(listed[name] == true, name)
    end
end

tests["fake client: a stop of the repeat is counted"] = function(t)
    local c = ns.make.fakeClient()
    t.eq(c.repeatStops, 0)
    t.eq({ c.stopCraftRepeat() }, { true })
    t.eq(c.repeatStops, 1)
    t.eq(#c.crafts, 0)
end

tests["fake client: the craft reads are unknown until set, and crafts are logged"] = function(t)
    local c = ns.make.fakeClient()
    t.eq(c.recipeUsable(2657), nil)
    c.setRecipeUsable(2657, false, "Requires Anvil")
    t.eq({ c.recipeUsable(2657) }, { false, "Requires Anvil" })
    t.eq(c.moving(), nil)
    c.setMoving(true)
    t.eq(c.moving(), true)
    t.eq({ c.craftRecipe(2657, 1) }, { true })
    t.eq(c.crafts, { { id = 2657, n = 1 } })
    c.setCombat(true)
    t.eq({ c.craftRecipe(2657, 1) }, { nil, "combat" })
    c.setCombat(false)
    c.setCraftFails("noCall")
    t.eq({ c.craftRecipe(2657, 1) }, { nil, "noCall" })
    t.eq(#c.crafts, 1, "a refused craft is not logged")
end

tests["fake client: a row panel records its rows and presses as the player"] = function(t)
    local c = ns.make.fakeClient()
    local h = c.rowPanel({ name = "TestRows" })
    if not h then t.ok(false, "no row panel") return end
    local got
    h.draw({ { kind = "button", key = "start", label = "Start", enabled = true },
        { kind = "button", key = "off", label = "Off", enabled = false } }, function(key, value) got = { key, value } end)
    t.eq(c.rowPanels[1], h)
    t.eq(#h.rows, 2)
    t.eq(h.press("start"), true)
    t.eq(got, { "start" })
    got = nil
    t.eq(h.press("off"), false, "a button not enabled cannot be pressed")
    t.eq(got, nil)
    t.eq(h.press("none"), false)
end

return tests

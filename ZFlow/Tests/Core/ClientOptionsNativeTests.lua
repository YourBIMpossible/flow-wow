-- c.optionsNative (lead section 410): the add-on's settings as the game's
-- own rows. The real client over a hand-built environment; the game's
-- Settings table is a recording stand-in written from the call shapes the
-- client code expects, NOT from this client: nothing here shows 16001 has
-- these calls.
local _, ns = ...

-- opts: order = "new" | "old" | "none" (which RegisterProxySetting argument
-- order reads back), without = name of a Settings function to leave out,
-- oldNames = true for CreateCheckBox / CreateDropDown.
local function gameEnv(opts)
    opts = opts or {}
    local env = { log = {}, listed = nil, opened = {}, settings = {}, inits = {} }
    local nextId = 10
    local function category(name, parent)
        nextId = nextId + 1
        local cat = { name = name, parent = parent, id = nextId }
        function cat:GetID() return self.id end
        local layout = { cat = cat, inits = {} }
        function layout:AddInitializer(init)
            self.inits[#self.inits + 1] = init
            env.inits[#env.inits + 1] = { cat = cat, init = init }
        end
        cat.layout = layout
        return cat, layout
    end
    local function initializer(kind, cat, setting, extra, tip)
        local init = { kind = kind, setting = setting, extra = extra, tip = tip, tags = {} }
        function init:AddModifyPredicate(fn) self.can = fn end
        function init:AddSearchTags(...) self.tags = { ... } end
        env.inits[#env.inits + 1] = { cat = cat, init = init }
        return init
    end
    local S = {}
    S.VarType = { Boolean = "boolean", Number = "number", String = "string" }
    function S.RegisterVerticalLayoutCategory(name)
        env.log[#env.log + 1] = "category " .. tostring(name)
        local cat, layout = category(name)
        env.parent = cat
        return cat, layout
    end
    function S.RegisterVerticalLayoutSubcategory(parent, name)
        env.log[#env.log + 1] = "sub " .. tostring(name)
        return category(name, parent)
    end
    function S.RegisterAddOnCategory(cat)
        env.log[#env.log + 1] = "listed"
        env.listed = cat
    end
    local function made(cat, variable, varType, name, default, get, set)
        local setting = { cat = cat, variable = variable, varType = varType, name = name, default = default }
        function setting:GetValue() return get() end
        function setting:SetValue(v) return set(v) end
        env.settings[variable] = setting
        return setting
    end
    function S.RegisterProxySetting(cat, variable, a, b, c, d, e, f)
        if opts.order == "none" then error("no such order") end
        if opts.order == "old" then
            if type(a) ~= "table" then error("old order wants the table") end
            return made(cat, variable, b, c, d, e, f)
        end
        if type(a) ~= "string" then error("new order wants the type") end
        return made(cat, variable, a, b, c, d, e)
    end
    function S.OpenToCategory(id) env.opened[#env.opened + 1] = id end
    function S.CreateSliderOptions(min, max, step)
        local o = { min = min, max = max, step = step }
        function o:SetLabelFormatter(side) self.side = side end
        return o
    end
    function S.CreateControlTextContainer()
        local box = { data = {} }
        function box:Add(value, label) self.data[#self.data + 1] = { value = value, label = label } end
        function box:GetData() return self.data end
        return box
    end
    function S.CreateSlider(cat, setting, options, tip) return initializer("slider", cat, setting, options, tip) end
    local function check(cat, setting, tip) return initializer("checkbox", cat, setting, nil, tip) end
    local function drop(cat, setting, options, tip) return initializer("dropdown", cat, setting, options, tip) end
    if opts.oldNames then
        S.CreateCheckBox, S.CreateDropDown = check, drop
    else
        S.CreateCheckbox, S.CreateDropdown = check, drop
    end
    if opts.without then S[opts.without] = nil end
    env.Settings = S
    env.MinimalSliderWithSteppersMixin = { Label = { Right = "right" } }
    function env.CreateSettingsListSectionHeaderInitializer(text) return { kind = "header", text = text } end
    function env.CreateSettingsButtonInitializer(label, text, run, tip, search)
        return { kind = "button", label = label, text = text, run = run, tip = tip, search = search }
    end
    return env
end

local function spec(values, sets)
    values = values or { flag = true, count = 2, mode = "low" }
    sets = sets or {}
    local function row(kind, key, label, default, more)
        local r = { kind = kind, key = key, label = label, tip = label .. " tip", default = default,
            get = function() return values[key] end,
            set = function(v) values[key] = v; sets[#sets + 1] = { key, v } end,
            can = function() return values.locked ~= true end, tags = { "word" } }
        for name, value in pairs(more or {}) do r[name] = value end
        return r
    end
    return {
        title = "Z-Flow", name = "ZFlowOptions",
        rows = { { kind = "button", label = "Use suggestions", text = "Choose", run = function() sets[#sets + 1] = { "pressed" } end } },
        topics = {
            { id = "general", name = "General", rows = {
                { kind = "header", text = "First" },
                row("toggle", "flag", "A flag", false),
                row("number", "count", "A count", 2, { min = 1, max = 3, step = 1 }),
            } },
            { id = "advanced", name = "Advanced", rows = {
                row("choice", "mode", "A mode", "low", { choices = { { value = "low", label = "Low" }, { value = "high", label = "High" } } }),
            } },
        },
    }, values, sets
end

local function initOf(env, kind)
    for _, e in ipairs(env.inits) do
        if e.init.kind == kind then return e.init, e.cat end
    end
    return nil
end

local NEEDED = { "RegisterVerticalLayoutCategory", "RegisterVerticalLayoutSubcategory", "RegisterAddOnCategory",
    "RegisterProxySetting", "OpenToCategory", "CreateSlider", "CreateSliderOptions", "CreateControlTextContainer",
    "CreateCheckbox", "CreateDropdown" }

return {
    ["options native: no Settings table, or one call missing, is nil and nothing is registered"] = function(t)
        t.eq(ns.make.client({}).optionsNative((spec())), nil)
        for _, name in ipairs(NEEDED) do
            local env = gameEnv({ without = name })
            t.eq(ns.make.client(env).optionsNative((spec())), nil, name)
            t.eq(env.listed, nil, name .. ": no entry in the list")
            t.eq(#env.log, 0, name .. ": nothing was asked of the game")
        end
    end,

    ["options native: the add-on's entry, one entry a topic, and a game row for each setting"] = function(t)
        local env = gameEnv()
        local h = ns.make.client(env).optionsNative((spec()))
        t.ok(h ~= nil)
        t.eq(env.log, { "category Z-Flow", "sub General", "sub Advanced", "listed" }, "listed last")
        t.eq(env.listed, env.parent)
        t.eq(h.order(), "new")
        t.eq(h.count(), 4, "three settings and the button; the header is not counted")
        local check, cat = initOf(env, "checkbox")
        t.eq(cat.name, "General")
        t.eq(check.setting.name, "A flag", "the short name is the label")
        t.eq(check.tip, "A flag tip", "the explanation is the tooltip")
        t.eq(check.setting.varType, "boolean")
        t.eq(check.setting.default, false)
        t.eq(check.tags, { "word" })
        local slider = initOf(env, "slider")
        t.eq({ slider.extra.min, slider.extra.max, slider.extra.step, slider.extra.side }, { 1, 3, 1, "right" })
        t.eq(slider.setting.varType, "number")
        local drop, dropCat = initOf(env, "dropdown")
        t.eq(dropCat.name, "Advanced")
        t.eq(drop.extra(), { { value = "low", label = "Low" }, { value = "high", label = "High" } })
        local header = initOf(env, "header")
        t.eq(header.text, "First")
        local button, buttonCat = initOf(env, "button")
        t.eq({ button.label, button.text }, { "Use suggestions", "Choose" })
        t.eq(buttonCat, env.parent, "the page's buttons are on the add-on's own entry")
    end,

    ["options native: a row reads and writes through the functions it was given"] = function(t)
        local env = gameEnv()
        local s, values, sets = spec()
        ns.make.client(env).optionsNative(s)
        local setting = env.settings["ZFlowOptions_flag"]
        t.eq(setting:GetValue(), true)
        setting:SetValue(false)
        t.eq(values.flag, false)
        t.eq(sets[1], { "flag", false })
        values.flag = nil
        t.eq(setting:GetValue(), false, "nothing known reads as the default")
        local check = initOf(env, "checkbox")
        t.eq(check.can(), true)
        values.locked = true
        t.eq(check.can(), false)
        initOf(env, "button").run()
        t.eq(sets[#sets], { "pressed" })
    end,

    ["options native: the older argument order is found by the unseen first setting"] = function(t)
        local env = gameEnv({ order = "old", oldNames = true })
        local h = ns.make.client(env).optionsNative((spec()))
        t.ok(h ~= nil)
        t.eq(h.order(), "old")
        t.eq(env.settings["ZFlowOptions_count"].varType, "number")
        t.eq(env.settings["ZFlowOptions_count"].name, "A count")
        t.eq(env.settings["ZFlowOptions_count"]:GetValue(), 2)
        t.ok(initOf(env, "checkbox") ~= nil, "CreateCheckBox, the older name")
    end,

    ["options native: neither argument order reading back is nil, and no entry is listed"] = function(t)
        local env = gameEnv({ order = "none" })
        t.eq(ns.make.client(env).optionsNative((spec())), nil)
        t.eq(env.listed, nil)
    end,

    ["options native: no row made is nil, and no entry is listed"] = function(t)
        local env = gameEnv()
        t.eq(ns.make.client(env).optionsNative({ title = "Z-Flow", name = "ZFlowOptions", topics = {} }), nil)
        t.eq(env.listed, nil)
    end,

    ["options native: open goes to the topic's entry by its id, the add-on's own for none or an unknown one"] = function(t)
        local env = gameEnv()
        local h = ns.make.client(env).optionsNative((spec()))
        t.eq(h.open("advanced"), true)
        t.eq(h.open(), true)
        t.eq(h.open("nothing"), true)
        local advanced
        for _, e in ipairs(env.inits) do
            if e.cat.name == "Advanced" then advanced = e.cat end
        end
        t.eq(env.opened, { advanced.id, env.parent.id, env.parent.id })
    end,

    ["options native: a set that raises goes no further than the row"] = function(t)
        local env = gameEnv()
        local s = spec()
        s.topics[1].rows[2].set = function() error("boom") end
        ns.make.client(env).optionsNative(s)
        local ok = pcall(function() env.settings["ZFlowOptions_flag"]:SetValue(false) end)
        t.eq(ok, true)
    end,
}

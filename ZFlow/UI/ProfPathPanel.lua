local _, ns = ...

-- The profession path panel (lead section 449, P-PATH-2): one compact
-- panel for a profession's whole path, read from the plan that
-- Items/ProfPath.lua makes (the section 450 contract). Collapsed it is one
-- line; unfolded it lists the skill brackets with the current one marked,
-- then what the selected bracket still needs.
--
--   It stays where the player put it: its place is saved when it is
--   dragged and never moved again on a refresh (UI/ProfDock.lua snapped
--   back under the game's window on every refresh).
--   It opens with the game's profession window, and without it from the
--   chat word (<slash> prof) and the minimap button's menu.
--   A click on a bracket selects that bracket here, and asks the client to
--   select its recipe in the game's profession window when the client can
--   (client.selectRecipe: requested from the lead, not in Core/Client.lua
--   yet). It never crafts, buys, trains or takes anything.
--   Until Items/ProfPath.lua is there, or when it gives no plan, the one
--   line says the path is not computed yet: never a blank panel.
--
--   PPP.Summary(plan) -> text                          pure
--   PPP.RangeText(range) -> text, right                pure
--   PPP.MaterialText(m) -> text, right, tone           pure
--   PPP.View(model) -> a kit window spec               pure
--     model = { plan, open, selected, prof }
--   PPP.Plain(model) -> plain panel rows               pure
--   PPP.Declare(k, diag) -> api   api.Open(), api.Close(), api.Toggle(), api.shown(),
--     api.model()
--
-- Not seen in game: its size, its place, and whether every line fits.

ns.ProfPathPanel = {}
local PPP = ns.ProfPathPanel

PPP.NAME = "profPathPanel"
PPP.SETTING = "prof.path"
PPP.ID = "ProfPathPanel"
PPP.PATH = "layout.profPath"
PPP.WORD = "prof"
PPP.WIDTH = 360
PPP.HEAD_HEIGHT, PPP.ROW_HEIGHT, PPP.SECTION_HEIGHT = 64, 28, 36
PPP.DEFAULT_POINT = { "TOPLEFT", "TOPLEFT", 420, -120 }

PPP.TITLE = "Profession path"
PPP.NOT_YET = "Profession path: path not computed yet"
PPP.NO_PROF = "Profession path: open a profession window once"
PPP.SUMMARY = "%s %d/%d: %s"
PPP.SUMMARY_DONE = "%s %d/%d: nothing more to plan"
PPP.HEAD_RANGES = "Skill brackets"
PPP.HEAD_MATERIALS = "Shopping and farming"
PPP.RANGE = "%d-%d %s"
PPP.CRAFTS = "x%d"
PPP.CRAFTS_UNSURE = "about x%d"
PPP.TRAIN_AT = "Train at %d"
PPP.MAT_NEED = "%s: need %d"
PPP.MAT_SHORT = "short %d"
PPP.MAT_HAVE = "have all"
PPP.MAT_BANK_UNSEEN = "bank not seen"
PPP.UNNAMED = "a material"
PPP.HELP = "prof: show the profession path panel; prof plan: what each profession needs next"

local function text(v) return type(v) == "string" and v ~= "" end
local function whole(v) return type(v) == "number" and v == v and v >= 0 and v < math.huge and v == math.floor(v) end

-- The bracket the plan marks as selected, as an index into plan.ranges.
local function selectedIndex(plan, selected)
    local ranges = {}
    if type(plan) == "table" and type(plan.ranges) == "table" then ranges = plan.ranges end
    if whole(selected) and ranges[selected] then return selected end
    if whole(plan and plan.selected) and ranges[plan.selected] then return plan.selected end
    if ranges[1] then return 1 end
    return nil
end

function PPP.RangeText(range)
    if type(range) ~= "table" or not whole(range.from) or not whole(range.to) then return nil end
    local said = string.format(PPP.RANGE, range.from, range.to, text(range.recipe) and range.recipe or "?")
    local right
    if whole(range.crafts) then
        right = string.format(range.sure == true and PPP.CRAFTS or PPP.CRAFTS_UNSURE, range.crafts)
    end
    if whole(range.learnAt) then
        local train = string.format(PPP.TRAIN_AT, range.learnAt)
        right = right and (right .. ", " .. train) or train
    end
    return said, right
end

function PPP.MaterialText(m)
    if type(m) ~= "table" or not whole(m.need) then return nil end
    local said = string.format(PPP.MAT_NEED, text(m.name) and m.name or PPP.UNNAMED, m.need)
    if m.net == "unknown" or m.bankSeen == false then return said, PPP.MAT_BANK_UNSEEN, "warn" end
    if whole(m.net) then
        if m.net <= 0 then return said, PPP.MAT_HAVE, "good" end
        return said, string.format(PPP.MAT_SHORT, m.net), "warn"
    end
    return said, nil, nil
end

function PPP.Summary(plan, prof, selected)
    if type(plan) ~= "table" then
        if plan == nil and not text(prof) then return PPP.NO_PROF end
        return PPP.NOT_YET
    end
    if not (text(plan.prof) and whole(plan.skill) and whole(plan.max)) then return PPP.NOT_YET end
    local i = selectedIndex(plan, selected)
    local range = nil
    if i then range = plan.ranges[i] end
    local said = range and PPP.RangeText(range)
    if not said then return string.format(PPP.SUMMARY_DONE, plan.prof, plan.skill, plan.max) end
    return string.format(PPP.SUMMARY, plan.prof, plan.skill, plan.max, said)
end

-- What the open panel lists: { ranges = { {text, right, current} },
-- materials = { {text, right, tone} } }.
local function lists(model)
    local plan = nil
    if type(model) == "table" then plan = model.plan end
    local out = { ranges = {}, materials = {} }
    if type(plan) ~= "table" or type(plan.ranges) ~= "table" then return out end
    local at = selectedIndex(plan, model.selected)
    for i, range in ipairs(plan.ranges) do
        local said, right = PPP.RangeText(range)
        if said then out.ranges[#out.ranges + 1] = { text = said, right = right, current = i == at, index = i } end
    end
    for _, m in ipairs(type(plan.materials) == "table" and plan.materials or {}) do
        local said, right, tone = PPP.MaterialText(m)
        if said then out.materials[#out.materials + 1] = { text = said, right = right, tone = tone } end
    end
    return out
end

function PPP.Height(model)
    local l = lists(model)
    local h = PPP.HEAD_HEIGHT
    if type(model) ~= "table" or model.open ~= true then return h end
    if #l.ranges > 0 then h = h + PPP.SECTION_HEIGHT + #l.ranges * PPP.ROW_HEIGHT end
    if #l.materials > 0 then h = h + PPP.SECTION_HEIGHT + #l.materials * PPP.ROW_HEIGHT end
    return h
end

-- on = { fold(open), pick(index) }: the module's own functions; nil in a
-- pure call gives a view with no clicks.
function PPP.View(model, on)
    if type(model) ~= "table" then model = {} end
    if type(on) ~= "table" then on = {} end
    local open = model.open == true
    local l = lists(model)
    local foldable = #l.ranges > 0 or #l.materials > 0
    local head = { kind = "section", key = "head", text = PPP.Summary(model.plan, model.prof, model.selected) }
    if foldable and type(on.fold) == "function" then
        head.folded = not open
        head.onFold = function(folded) on.fold(not folded) end
    end
    local children = { head }
    if open and foldable then
        if #l.ranges > 0 then
            children[#children + 1] = { kind = "section", key = "rangesHead", text = PPP.HEAD_RANGES }
            for _, r in ipairs(l.ranges) do
                local row = { kind = "line", key = "range" .. r.index, text = r.text, right = r.right,
                    tone = nil }
                if r.current then row.tone = "good" end
                if type(on.pick) == "function" then
                    local index = r.index
                    row.onClick = function() on.pick(index) end
                end
                children[#children + 1] = row
            end
        end
        if #l.materials > 0 then
            children[#children + 1] = { kind = "section", key = "matsHead", text = PPP.HEAD_MATERIALS }
            for i, m in ipairs(l.materials) do
                children[#children + 1] = { kind = "line", key = "mat" .. i, text = m.text, right = m.right,
                    tone = m.tone }
            end
        end
    end
    return {
        id = PPP.ID, title = PPP.TITLE,
        width = PPP.WIDTH, height = PPP.Height(model),
        point = PPP.DEFAULT_POINT, escape = false,
        children = children,
    }
end

function PPP.Plain(model)
    if type(model) ~= "table" then model = {} end
    local out = { { kind = "info", text = PPP.Summary(model.plan, model.prof, model.selected) } }
    if model.open == true then
        local l = lists(model)
        for _, r in ipairs(l.ranges) do
            out[#out + 1] = { kind = "info", text = (r.current and "> " or "  ") .. r.text
                .. (text(r.right) and (" (" .. r.right .. ")") or "") }
        end
        for _, m in ipairs(l.materials) do
            out[#out + 1] = { kind = "info", text = m.text .. (text(m.right) and (" (" .. m.right .. ")") or "") }
        end
    end
    return out
end

local function point4(p)
    if type(p) ~= "table" or not text(p[1]) or not text(p[2]) then return nil end
    if type(p[3]) ~= "number" or type(p[4]) ~= "number" then return nil end
    return { p[1], p[2], p[3], p[4] }
end

function PPP.Declare(k, diag)
    local api = {}
    local ctx, host, model
    local open, selected, prof = false, nil, nil

    function api.shown() return host ~= nil and host.shown() == true end
    function api.model() return model end

    local function ask(name, ...)
        local f = ctx and ctx.client[name]
        if type(f) ~= "function" then return nil end
        local ok, a, b = pcall(f, ...)
        if ok then return a, b end
        return nil
    end

    local function saved()
        local ok, v = pcall(ctx.store.get, ctx.store, "char", PPP.PATH)
        if ok and type(v) == "table" then return v end
        return {}
    end

    local function keep(field, value)
        local v = saved()
        v[field] = value
        pcall(ctx.store.set, ctx.store, "char", PPP.PATH, v)
    end

    -- The plan, from Items/ProfPath.lua when it is there; nil otherwise.
    local function plan()
        local PATH, P = ns.ProfPath, ns.ProfPlan
        if not text(prof) or type(PATH) ~= "table" or type(PATH.Path) ~= "function" then return nil end
        local input
        if type(P) == "table" and type(P.Input) == "function" then
            local source
            if type(ctx.use) == "function" then
                local ok, s = pcall(ctx.use, P.NODE_SOURCE)
                if ok then source = s end
            end
            local ok, v = pcall(P.Input, ctx.client, ctx.store, prof, source)
            if ok then input = v end
        end
        if type(input) ~= "table" then input = { prof = prof } end
        local ok, v = pcall(PATH.Path, input)
        if ok and type(v) == "table" then return v end
        return nil
    end

    local draw
    local on = {}
    function on.fold(want)
        open = want == true
        keep("open", open)
        draw()
    end
    function on.pick(index)
        selected = index
        local range = model and model.plan and model.plan.ranges and model.plan.ranges[index]
        if type(range) == "table" and text(range.recipe) then ask("selectRecipe", range.recipe) end
        draw()
    end

    function draw()
        if not ctx or not host then return end
        local p = plan()
        if type(p) == "table" and model and type(model.plan) == "table" and model.plan.rev ~= p.rev then
            selected = nil
        end
        model = { plan = p, open = open, selected = selected, prof = prof }
        host.draw(PPP.View(model, on), PPP.Plain(model), function() end)
        -- Size only: the place is the player's (never docked again).
        host.place(nil, PPP.WIDTH, PPP.Height(model))
    end

    local function enabled() return ctx and ctx.settings:get(PPP.SETTING) ~= false end

    local function windowProf()
        local r = ask("recipes")
        if type(r) ~= "table" then r = ask("tradeSkillRows") end
        if type(r) == "table" and text(r.name) then return r.name end
        return nil
    end

    function api.Open()
        if not ctx or not host then return false end
        prof = windowProf() or prof
        draw()
        host.show(true)
        return true
    end
    function api.Close()
        if host then host.show(false) end
    end
    function api.Toggle()
        if api.shown() then
            host.show(false)
            return true
        end
        return api.Open()
    end

    k:Module({
        name = PPP.NAME,
        needs = { "client", "store", "bus", "settings" },
        settings = { {
            key = PPP.SETTING, scope = "account", type = "bool", default = true,
            label = "Profession path panel",
            help = "A small panel with your profession's whole path: the skill brackets with the current one marked, "
                .. "and what to buy or farm for it. It opens with the profession window and stays where you put it. "
                .. "It only shows information: nothing is crafted, bought or trained for you.",
            group = "professions",
            synonyms = { "profession", "professions", "path", "brackets", "recipes", "skill", "shopping" },
        } },
        provides = { Open = api.Open, Close = api.Close, Toggle = api.Toggle, Shown = api.shown },
        start = function(c)
            ctx = c
            local s = saved()
            open = s.open == true
            if text(s.prof) then prof = s.prof end
            local id = k.id or ns.id
            local panel
            if type(c.client.rowPanel) == "function" then
                local ok, p = pcall(c.client.rowPanel, { name = id.framePrefix .. "ProfPath", width = PPP.WIDTH,
                    height = PPP.HEAD_HEIGHT })
                if ok and type(p) == "table" then panel = p end
            end
            local start = point4(s.point) or PPP.DEFAULT_POINT
            if panel then
                panel.show(false)
                panel.place(start)
            end
            host = ns.KitHost.New(k, c.client, { name = id.framePrefix .. "ProfPathKit", panel = panel,
                place = function() return point4(saved().point) or PPP.DEFAULT_POINT end,
                onMoved = function(point)
                    local p = point4(point)
                    if p then keep("point", p) end
                end })
            c.bus:on(PPP.NAME, "TRADE_SKILL_SHOW", function()
                if not enabled() then return end
                local name = windowProf()
                if name then
                    prof = name
                    keep("prof", name)
                end
                draw()
                host.show(true)
            end)
            c.bus:on(PPP.NAME, "TRADE_SKILL_LIST_UPDATE", function()
                if api.shown() then draw() end
            end)
        end,
        stop = function()
            if host then host.show(false) end
            model, ctx = nil, nil
        end,
    })

    -- <slash> prof: open the panel. "prof plan" keeps the chat lines that
    -- Nav/ProfFeed.lua gives (that word is its; this only adds the bare one).
    if type(diag) == "table" and type(diag.commands) == "table" then
        local before = diag.commands[PPP.WORD]
        diag.commands[PPP.WORD] = function(rest)
            local word = tostring(rest or ""):lower():match("^%s*(%S*)")
            if word ~= "" and type(before) == "function" then return before(rest) end
            if not api.Open() and type(before) == "function" then return before(rest) end
        end
        if type(diag.help) == "table" then diag.help[PPP.WORD] = PPP.HELP end
    end
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.profPathPanel = PPP.Declare(ns, ns.diag)

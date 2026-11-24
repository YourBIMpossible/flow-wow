-- The minimap button (lead DISPATCH sections 340 and 303(g); the owner
-- asked for it): a small round button on the minimap's rim. LOOK ONLY: a
-- left click opens the settings page and does nothing else; a right click
-- opens the route menu (WHITE-QUEUE C2); a drag moves it round the rim and
-- saves the angle account-wide; hover says the title and what a click, a
-- right click and a drag do.
--
-- The route menu (MB.Menu) only asks Nav/TripRoute.lua for what its chat
-- word already does (Plan, Skip, Off) and says the result in chat in the
-- same words, switches the route window's setting, and opens the settings
-- page. It orders no route itself and nothing is moved, targeted or cast.
--
-- Setting "ui.minimapButton" (bool, account, default on): off hides the
-- button at once, on shows it (making it the first time).
-- Saved, account "layout.minimapButton" = { angle = degrees } (row
-- "ui.minimapButtonPlace"); no angle saved is MinimapPlace.DEFAULT.
--
-- Reads (through the injected client):
--   client.minimap() -> { size, square } or nil   (the rim radius and shape)
--   client.minimapButton(spec) -> h | nil, why     CLIENT NEED (Core/Client.lua)
--     spec = { name = global name, title = the add-on's title }
--     h.place(x, y), h.show(on), h.onClick(fn(button)),
--     h.onDrag(fn(dx, dy, done)), h.tip(lines), h.menu(items, pick)
-- A client that cannot make the button costs one problem line; the button
-- is not asked for again until a reload.
local _, ns = ...

local MB = {}
ns.MinimapButton = MB

MB.NAME = "minimapButton"
MB.KEY = "ui.minimapButton"
MB.PLACE_KEY = "ui.minimapButtonPlace"
MB.PATH = "layout.minimapButton"
MB.HINT = "Click: settings. Right-click: route menu. Drag: move."
MB.MENU_TITLE = "%s route"
MB.MENU_PLAN = "Plan a route from my quest log"
MB.MENU_AGAIN = "Plan the route again"
MB.MENU_SKIP = "Skip the current stop"
MB.MENU_CLEAR = "Clear the route"
MB.MENU_NONE = "No route yet"
MB.MENU_WINDOW = "Show the route window"
MB.MENU_SETTINGS = "Settings"
MB.SYNONYMS = { "minimap button", "minimap icon" }

local function MP() return ns.MinimapPlace or {} end

-- The route menu's rows (the arrows' menu shape, UI/ArrowMenu.lua).
-- state = { title = the add-on's title, route = a route is planned,
--           window = the route window's setting (nil: no such setting) }
function MB.Menu(state)
    state = type(state) == "table" and state or {}
    local has = state.route == true
    local items = {
        { title = true, text = MB.MENU_TITLE:format(tostring(state.title or "")) },
        { key = "plan", text = has and MB.MENU_AGAIN or MB.MENU_PLAN },
    }
    if has then
        items[#items + 1] = { key = "skip", text = MB.MENU_SKIP }
        items[#items + 1] = { key = "clear", text = MB.MENU_CLEAR }
    else
        items[#items + 1] = { key = "none", text = MB.MENU_NONE, disabled = true }
    end
    if state.window ~= nil then
        items[#items + 1] = { sep = true }
        items[#items + 1] = { key = "window", text = MB.MENU_WINDOW, checked = state.window == true }
    end
    items[#items + 1] = { sep = true }
    items[#items + 1] = { key = "settings", text = MB.MENU_SETTINGS }
    return items
end

function MB.Declare(k)
    local api = {}
    local ctx, button, failed, angle
    local cancels = {}

    local function id() return k.id or ns.id end

    local function problem(what, why)
        if type(k.problems) == "table" and type(k.problems.add) == "function" then
            pcall(k.problems.add, k.problems, MB.NAME, MB.NAME, what, why)
        end
    end

    local function savedAngle()
        local r = ctx.store:get("account", MB.PATH)
        local a = type(r) == "table" and MP().Normalize(r.angle) or nil
        return a or MP().DEFAULT
    end

    local function place()
        if not button or not ctx then return end
        local okM, mini = false, nil
        if type(ctx.client.minimap) == "function" then okM, mini = pcall(ctx.client.minimap) end
        if not okM or type(mini) ~= "table" then mini = {} end
        local x, y = MP().Offset(angle or savedAngle(), MP().Radius(mini.size), mini.square == true)
        button.place(x, y)
    end

    local function openSettings()
        local sp = k.use and ns.SettingsPanel and k.use(ns.SettingsPanel.NAME)
        if type(sp) ~= "table" or type(sp.Show) ~= "function" then
            problem("click", "the settings page is not ready")
            return
        end
        local ok, err = pcall(sp.Show)
        if not ok then problem("click", err) end
    end

    local function route()
        local T = ns.Nav and ns.Nav.TripRoute
        local r = k.use and T and k.use(T.NAME)
        return type(r) == "table" and r or nil
    end

    local function windowKey()
        local RT = ns.RouteTracker
        local key = RT and RT.SETTING
        if type(key) ~= "string" or ctx.settings:row(key) == nil then return nil end
        return key
    end

    local function menuState()
        local r = route()
        local lines = r and type(r.Lines) == "function" and r.Lines() or nil
        local key = windowKey()
        local window
        if key then window = ctx.settings:get(key) == true end
        return { title = id().title, route = lines ~= nil, window = window }
    end

    local function say(lines)
        local c = ctx.client
        if type(c.print) ~= "function" then return end
        for _, line in ipairs(type(lines) == "table" and lines or {}) do
            c.print(id().title .. ": " .. tostring(line))
        end
    end

    -- As the route's chat word (Nav/TripRoute.lua api.Word) does and says.
    local ROUTE = {}
    function ROUTE.plan(r, T)
        local made, why = r.Plan()
        say(made and r.Lines() or { why or T.WHY_NONE })
    end
    function ROUTE.skip(r, T)
        if r.Skip() then say(r.Lines()) else say({ T.DONE }) end
    end
    function ROUTE.clear(r, T)
        r.Off()
        say({ T.CLEARED })
    end

    local function choose(key)
        if not ctx then return end
        if key == "settings" then
            openSettings()
        elseif key == "window" then
            local row = windowKey()
            if row then
                local ok, why = ctx.settings:set(row, ctx.settings:get(row) ~= true)
                if not ok and why ~= nil then problem("menu", why) end
            end
        elseif ROUTE[key] then
            local r = route()
            if r and type(r.Plan) == "function" and type(r.Skip) == "function" and type(r.Off) == "function"
                and type(r.Lines) == "function" then
                ROUTE[key](r, ns.Nav.TripRoute)
            else
                problem("menu", "the route is not ready")
            end
        end
    end

    local function openMenu()
        if not button or not ctx or type(button.menu) ~= "function" then return end
        button.menu(MB.Menu(menuState()), function(key)
            local ok, err = pcall(choose, key)
            if not ok then problem("menu", err) end
        end)
    end

    local function dragged(dx, dy, done)
        local a = MP().Angle(dx, dy)
        if a == nil then return end
        angle = a
        place()
        if done and ctx then
            local ok, why = ctx.store:set("account", MB.PATH, { angle = a })
            if not ok and why ~= nil then problem("save", why) end
        end
    end

    local function make()
        if button or failed then return end
        local maker = ctx.client.minimapButton
        local h, why = nil, "the client has no minimap button"
        if type(maker) == "function" then
            local ok
            ok, h, why = pcall(maker, { name = id().framePrefix .. "MinimapButton", title = id().title })
            if not ok then
                why = h
                h = nil
            end
        end
        if type(h) ~= "table" then
            failed = true
            problem("make", why or "the client could not make the minimap button")
            return
        end
        button = h
        h.tip({ id().title, MB.HINT })
        h.onClick(function(which)
            local okC, err = pcall(which == "right" and openMenu or openSettings)
            if not okC then problem("click", err) end
        end)
        h.onDrag(function(dx, dy, done)
            local okD, err = pcall(dragged, dx, dy, done)
            if not okD then problem("drag", err) end
        end)
    end

    local function refresh()
        if not ctx then return end
        if ctx.settings:get(MB.KEY) == true then
            make()
            if button then
                place()
                button.show(true)
            end
        elseif button then
            button.show(false)
        end
    end

    local function safeRefresh()
        local ok, err = pcall(refresh)
        if not ok then problem("refresh", err) end
    end

    function api.shown() return button ~= nil and ctx ~= nil and ctx.settings:get(MB.KEY) == true end

    k:Module({
        name = MB.NAME,
        needs = { "client", "store", "settings" },
        settings = {
            { key = MB.KEY, scope = "account", type = "bool", default = true, group = "general.windows",
              label = "Minimap button", synonyms = MB.SYNONYMS,
              help = "A small round button on the edge of the minimap, shown while this is on. "
                  .. "A click opens these settings; a right click opens the route menu; "
                  .. "a drag moves it round the minimap." },
            { key = MB.PLACE_KEY, scope = "account", type = "table", path = MB.PATH, keepOnResetAll = true,
              group = "general.windows", label = "Minimap button place", synonyms = MB.SYNONYMS },
        },
        provides = { Shown = api.shown },
        start = function(c)
            ctx = c
            local row = c.settings:row(MB.KEY)
            local path = type(row) == "table" and row.path or ("settings." .. MB.KEY)
            local cancel = c.store:watch("account", path, safeRefresh)
            if type(cancel) == "function" then cancels[#cancels + 1] = cancel end
            safeRefresh()
        end,
        stop = function()
            for i = 1, #cancels do pcall(cancels[i]) end
            cancels = {}
            if button then pcall(button.show, false) end
            ctx = nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.minimapButton = MB.Declare(ns)

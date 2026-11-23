-- The minimap button (lead DISPATCH sections 340 and 303(g); the owner
-- asked for it): a small round button on the minimap's rim. LOOK ONLY: a
-- left click opens the settings page and does nothing else; a drag moves it
-- round the rim and saves the angle account-wide; hover says the title and
-- what a click and a drag do.
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
--     h.place(x, y), h.show(on), h.onClick(fn), h.onDrag(fn(dx, dy, done)),
--     h.tip(lines)
-- A client that cannot make the button costs one problem line; the button
-- is not asked for again until a reload.
local _, ns = ...

local MB = {}
ns.MinimapButton = MB

MB.NAME = "minimapButton"
MB.KEY = "ui.minimapButton"
MB.PLACE_KEY = "ui.minimapButtonPlace"
MB.PATH = "layout.minimapButton"
MB.HINT = "Click: settings. Drag: move."
MB.SYNONYMS = { "minimap button", "minimap icon" }

local function MP() return ns.MinimapPlace or {} end

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
        h.onClick(function()
            local okC, err = pcall(openSettings)
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
                  .. "A click opens these settings; a drag moves it round the minimap." },
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

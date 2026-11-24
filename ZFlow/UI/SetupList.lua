-- The setup checklist (G53, WHITE-QUEUE C4): one window listing the game
-- settings worth turning on, opened once on a new character and by its
-- word at any time.
--
-- Two kinds of row:
--   a tick box   one of this add-on's own settings (S.TICKS). Ticking it
--                sets that setting, as the settings page does; unticking
--                sets it back. Nothing is ticked for the player.
--   a line       one of the game's own options (S.GAME). The game's value
--                is only read (client.gameSetting): the line says whether
--                it is on, and when it is off, where the player turns it
--                on. This add-on does not change it. An option the game
--                does not say is left out.
-- Which options are listed is what the old add-on suggested
-- (Modules/Setup.lua, its "suggested" rows); that file was read, nothing
-- is copied.
--
-- NOTHING CHANGES ON ITS OWN. Opening the window writes one mark, the
-- character's "shown" at S.SHOWN_PATH, so it opens by itself only once.
-- It opens by itself at a login after the welcome (UI/Intro.lua) has been
-- closed, never over it, and never while S.SETTING is off.
--
-- Built from the kit's parts only (UI/Kit.lua, drawn by client.kitWindow):
-- this file names no template, colour, font or size.
--
--   S.Game(client, list) -> rows   (pure) { name, why, how, on } for each
--                                  option the game says
--   S.Ticks(settings, list) -> rows   (pure) { key, label, help, on } for
--                                  each setting that has a row
--   S.Declare(k, diag) -> api      api.Open(), api.Close(), api.Shown()
--   `<slash> setup` opens it.
-- Its place is kept, account wide, at S.PATH.
-- Not tested in game.
local _, ns = ...

local S = {}
ns.SetupList = S

S.NAME = "setupList"
S.ID = "setup"
S.WORD = "setup"
S.HELP = "open the setup checklist: game settings worth turning on"
S.HEADER = "Setup checklist"
S.SETTING = "ui.setupList"
S.SHOWN_PATH = "state.setupList.shown"
S.PATH = "layout.setupList"
S.WIDTH, S.HEIGHT = 520, 440
S.ABOUT = { "Tick what you want. Nothing changes until you do.",
    "You can change any of it later in the settings." }
S.OURS = "Turn on here"
S.THEIRS = "In the game's own options"
S.ON, S.OFF = "On", "Off"
S.HOW = "Press Escape, open Options, and search for: %s"
S.NONE = { "The game did not say any of its options.", "Open this again after you log in." }
S.FOOTER = "%s setup opens this again."
S.SETTINGS_BUTTON = "All settings"

-- This add-on's own settings, each a tick box. A key with no row is left out.
S.TICKS = { "game.cameraZoom", "game.chatTimes" }

-- The game's own options, read only. name: the option's name as the player
-- reads it here; find: what to search for in the game's Options; setting:
-- the game setting read; on: the value that means on.
S.GAME = {
    { setting = "autoLootDefault", on = "1", name = "Auto loot", find = "Auto Loot",
      why = "One click picks up everything a corpse holds." },
    { setting = "nameplateShowEnemies", on = "1", name = "Enemy nameplates", find = "Enemy Nameplates",
      why = "A health bar over each enemy. Quest and threat marks sit on it." },
    { setting = "instantQuestText", on = "1", name = "Instant quest text", find = "Instant Quest Text",
      why = "Quest text appears at once instead of scrolling in." },
    { setting = "autoSelfCast", on = "1", name = "Self cast", find = "Self Cast",
      why = "With no friend targeted, a heal or buff lands on you." },
    { setting = "statusText", on = "1", name = "Health and mana numbers", find = "Status Text",
      why = "Numbers on your health and mana bars, not only the bar." },
}

local function isText(v) return type(v) == "string" and v ~= "" end

function S.Ticks(settings, list)
    local out = {}
    if type(settings) ~= "table" or type(settings.row) ~= "function" then return out end
    for _, key in ipairs(type(list) == "table" and list or {}) do
        local row = settings:row(key)
        if type(row) == "table" and row.type == "bool" and isText(row.label) then
            out[#out + 1] = { key = key, label = row.label, help = isText(row.help) and row.help or nil,
                on = settings:get(key) == true }
        end
    end
    return out
end

function S.Game(client, list)
    local out = {}
    if type(client) ~= "table" or type(client.gameSetting) ~= "function" then return out end
    for _, o in ipairs(type(list) == "table" and list or {}) do
        local ok, v = pcall(client.gameSetting, o.setting)
        if ok and v ~= nil then
            out[#out + 1] = { name = o.name, why = o.why, how = S.HOW:format(o.find), on = tostring(v) == o.on }
        end
    end
    return out
end

function S.Declare(k, diag)
    local api = {}
    local ctx, handle
    local render
    local id = k.id or ns.id

    local function client() return ctx and ctx.client or k.client end
    local function settings() return ctx and ctx.settings or k.settings end

    local function tree()
        local children = {
            { kind = "header", key = "header", title = S.HEADER },
            { kind = "line", key = "about", text = S.ABOUT[1], sub = S.ABOUT[2] },
        }
        local body = {}
        local ticks = S.Ticks(settings(), S.TICKS)
        if #ticks > 0 then
            body[#body + 1] = { kind = "section", key = "ours", text = S.OURS }
            for _, r in ipairs(ticks) do
                body[#body + 1] = { kind = "row", key = "row." .. r.key, label = r.label, tooltip = r.help,
                    control = { kind = "checkbox", key = r.key, checked = r.on, onToggle = function(on)
                        local ok, err = settings():set(r.key, on == true)
                        if ok == nil and err ~= nil then k.problems:add(S.NAME, "set", tostring(err)) end
                        render()
                    end } }
            end
        end
        local game = S.Game(client(), S.GAME)
        if #game > 0 then
            body[#body + 1] = { kind = "section", key = "theirs", text = S.THEIRS }
            for i, r in ipairs(game) do
                body[#body + 1] = { kind = "line", key = "game." .. i, text = r.name,
                    sub = r.on and r.why or r.how, tooltip = r.why,
                    right = r.on and S.ON or S.OFF, tone = r.on and "good" or "warn" }
            end
        end
        if #body == 0 then
            body[#body + 1] = { kind = "empty", key = "empty", text = S.NONE[1], how = S.NONE[2] }
        end
        children[#children + 1] = { kind = "scroll", key = "body", children = body }
        local buttons
        if diag and type(diag.commands) == "table" and type(diag.commands.settings) == "function" then
            buttons = { { kind = "button", key = "settings", text = S.SETTINGS_BUTTON, onClick = function() diag.commands.settings() end } }
        end
        children[#children + 1] = { kind = "footer", key = "footer", text = S.FOOTER:format(id.slash), buttons = buttons }
        return ns.Kit.Window({ id = S.ID, title = id.title .. ": " .. S.HEADER, resizable = true,
            width = S.WIDTH, height = S.HEIGHT, children = children })
    end

    render = function()
        if not handle then return end
        local t, why = tree()
        if not t then
            k.problems:add(S.NAME, "tree", tostring(why))
            return
        end
        handle.update(t)
    end

    function api.Open()
        local c = client()
        if type(c) ~= "table" or type(c.kitWindow) ~= "function" then return false end
        local t, why = tree()
        if not t then
            k.problems:add(S.NAME, "tree", tostring(why))
            return false
        end
        if not handle then
            local point, width, height = ns.Kit.Place(k.store:get("account", S.PATH), t)
            handle = c.kitWindow(S.ID, t, {
                name = id.framePrefix .. "SetupList",
                point = point, width = width, height = height,
                onMoved = function(at, w, h)
                    if type(at) ~= "table" then return end
                    local ok, err = k.store:set("account", S.PATH,
                        { point = { at[1], at[2], at[3], at[4] }, width = w, height = h })
                    if not ok then k.problems:add(S.NAME, "place", tostring(err)) end
                end,
                onClose = function() end,
                failed = function(err) k.problems:add(S.NAME, "draw", tostring(err)) end,
            })
            if not handle then
                k.problems:add(S.NAME, "window", "the client could not draw the window")
                return false
            end
        else
            handle.update(t)
        end
        handle.show(true)
        return true
    end

    function api.Close()
        if handle then handle.close() end
    end

    function api.Shown()
        return handle ~= nil and handle.shown() == true
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[S.WORD] = function() api.Open() end
        if type(diag.help) == "table" then diag.help[S.WORD] = S.HELP end
    end

    k:Module({
        name = S.NAME,
        needs = { "client", "store", "settings" },
        settings = { { key = S.SETTING, scope = "char", type = "bool", default = true,
            label = "Setup checklist on a new character", group = "general",
            synonyms = { "setup", "checklist", "first login", "suggestions" },
            help = "Opens the setup checklist once, at a login after you have closed the welcome." } },
        provides = { Open = api.Open, Close = api.Close, Shown = api.Shown },
        start = function(c)
            ctx = c
            -- Once for a character, and never over the welcome: it waits
            -- for a login after the welcome was closed.
            local I = ns.Intro
            local welcomed = type(I) ~= "table" or c.store:get("char", I.SEEN_PATH) == true
            if welcomed and c.settings:get(S.SETTING) ~= false and c.store:get("char", S.SHOWN_PATH) ~= true then
                if api.Open() then c.store:set("char", S.SHOWN_PATH, true) end
            end
        end,
        stop = function()
            if handle then handle.close() end
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.setupList = S.Declare(ns, ns.diag)

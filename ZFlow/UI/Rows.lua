local _, ns = ...

-- The setting rows of the first-login welcome and the window buttons (F9).
-- UI/Intro.lua and UI/WindowButtons.lua read these rows and declare none:
-- a kernel without them shows the welcome and makes no button.
--
--   ui.intro           bool, this character, on: the welcome at first login
--   buttons.worldMap   bool, account, off: a button on the world map
--   buttons.merchant   bool, account, off: a button on the merchant window
--   buttons.profession bool, account, on: a button on the profession window
--   buttons.bank       bool, account, on: a button on the bank window
--   buttons.talents    bool, account, on: a button on the talent window (F-29)
--
--   UIRows.Declare(k) -> how many rows the kernel took. A row it refuses
--   is a problem of kind "setting" there (Core/Settings.lua).
local R = {}
ns.UIRows = R

R.GROUP = "general.windows" -- a topic and section of Settings/Topics.lua

function R.Declare(k)
    local made = 0
    if k:Setting({ key = "ui.intro", scope = "char", type = "bool", default = true,
        label = "Welcome at first login", group = R.GROUP, synonyms = { "welcome", "intro", "first login" },
        help = "Shows the welcome once, the first time this character logs in." }) then made = made + 1 end
    if k:Setting({ key = "buttons.worldMap", scope = "account", type = "bool", default = true,
        label = "Button on the world map", group = R.GROUP, synonyms = { "button", "map", "arrow menu" },
        help = "A button on the world map that opens the arrow menu." }) then made = made + 1 end
    if k:Setting({ key = "buttons.merchant", scope = "account", type = "bool", default = true,
        label = "Button on the merchant window", group = R.GROUP, synonyms = { "button", "merchant", "vendor", "window" },
        help = "A button on the merchant window that shows the sell list." }) then made = made + 1 end
    if k:Setting({ key = "buttons.profession", scope = "account", type = "bool", default = true,
        label = "Button on the profession window", group = R.GROUP,
        synonyms = { "button", "profession", "crafting", "window" },
        help = "A button on the profession window that opens the profession help and settings." }) then
        made = made + 1
    end
    if k:Setting({ key = "buttons.bank", scope = "account", type = "bool", default = true,
        label = "Button on the bank window", group = R.GROUP, synonyms = { "button", "bank", "window" },
        help = "A button on the bank window that says Bank list and shows the list of what to store and take out." }) then
        made = made + 1
    end
    -- F-29 (lead section 817): the talent window's button.
    if k:Setting({ key = "buttons.talents", scope = "account", type = "bool", default = true,
        label = "Button on the talent window", group = R.GROUP, synonyms = { "button", "talents", "talent", "window" },
        help = "A button on the game's talent window that says Talents and opens your talents and the build to take." }) then
        made = made + 1
    end
    return made
end

-- The addon's own: declared when this file loads.
R.made = R.Declare(ns)

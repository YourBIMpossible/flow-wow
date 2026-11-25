local _, ns = ...
-- S23 click-casting check (P-KEYS slice B): one line on the settings page,
-- where the key rows and their lines show (UI/SettingsKeys.lua), when a
-- click-cast add-on or another binding would take a Z-Flow key over. A read
-- only: it binds nothing, clears nothing, and touches no other add-on.
-- Click casting itself (Z-Flow casting from unit frames) is an owner
-- decision (lead section 243) and is not built here.
--
--   CC.Read(client, slots) -> { addons, taken, unknown }
--     slots: { { label, action, override }, ... }: each key slot's label,
--            its binding action ("CLICK <button>:LeftButton") and the key
--            held for the session only (or nil)
--     addons: the click-cast add-ons loaded (CC.ADDONS order)
--     taken:  { { label, key, by }, ... }: a slot's key whose winning
--             binding (client.bindingOverride) is something else
--     unknown: true when a read failed or gave nothing; a key not known is
--             never counted as taken
--   CC.Line(read, title) -> the one line, or nil when there is nothing to say
--
-- First guess: the add-on names below are click-cast add-ons known from
-- other clients, not checked on this one; c.bindingOverride is not seen in
-- game either. Fake client only; not tested in game.
local CC = {}
ns.ClickCheck = CC

-- First guess: Clique first, then other click-cast and unit frame healing
-- add-ons that take mouse buttons and keys over unit frames.
CC.ADDONS = { "Clique", "Clicked", "HealBot", "VuhDo" }

local function add(list, seen, key)
    if type(key) == "string" and key ~= "" and not seen[key] then
        seen[key] = true
        list[#list + 1] = key
    end
end

function CC.Read(client, slots)
    local out = { addons = {}, taken = {}, unknown = false }
    if type(client) ~= "table" then
        out.unknown = true
        return out
    end
    if type(client.addonLoaded) == "function" then
        for _, name in ipairs(CC.ADDONS) do
            local ok, loaded = pcall(client.addonLoaded, name)
            if ok and loaded == true then out.addons[#out.addons + 1] = name end
        end
    end
    local checked = {}
    for _, slot in ipairs(type(slots) == "table" and slots or {}) do
        if type(slot) == "table" and type(slot.action) == "string" then
            local keys, seen = {}, {}
            add(keys, seen, slot.override)
            if type(client.bindingKeys) == "function" then
                local ok, got = pcall(client.bindingKeys, slot.action)
                if ok and type(got) == "table" then
                    for _, key in ipairs(got) do add(keys, seen, key) end
                else
                    out.unknown = true
                end
            else
                out.unknown = true
            end
            for _, key in ipairs(keys) do
                if not checked[key] then
                    checked[key] = true
                    local ok, by = false, nil
                    if type(client.bindingOverride) == "function" then
                        ok, by = pcall(client.bindingOverride, key, slot.action)
                    end
                    if not ok or type(by) ~= "string" then
                        out.unknown = true
                    elseif by ~= "" and by ~= slot.action then
                        out.taken[#out.taken + 1] = { label = tostring(slot.label), key = key, by = by }
                    end
                end
            end
        end
    end
    return out
end

local function named(addons)
    if #addons == 1 then return addons[1] .. " is" end
    return table.concat(addons, ", ") .. " are"
end

function CC.Line(read, title)
    if type(read) ~= "table" then return nil end
    local addons = type(read.addons) == "table" and read.addons or {}
    local taken = type(read.taken) == "table" and read.taken or {}
    local who = "this add-on"
    if type(title) == "string" and title ~= "" then who = title end
    if #taken > 0 then
        local first = taken[1]
        local line = "Click casting: your " .. tostring(first.label) .. " " .. tostring(first.key)
            .. " does " .. tostring(first.by) .. ", not " .. who .. "'s key"
        if #addons > 0 then line = line .. " (" .. named(addons) .. " loaded)" end
        if #taken > 1 then line = line .. "; " .. (#taken - 1) .. " more taken" end
        return line .. "."
    end
    if #addons > 0 then
        return "Click casting: " .. named(addons) .. " loaded; it may take your keys over unit frames. Check its bindings."
    end
    return nil
end

-- F-32 (lead sections 788, 790): the `clicks` and `under` words, as Flow's
-- Modules/ClickCheck.lua (CC.What :43-49, CC.Problems :54-80, CC.Report
-- :86-104, the words :130-163), in our own words (section 757). The game's
-- own click bindings on unit frames ("Target" on the left button, "Open
-- menu" on the right, or a spell) and what is under the mouse. Read and
-- report only: nothing is bound, cleared or clicked.
--   CC.Report(bindings, spellName) -> lines   (pure)
--     bindings: { { type, actionID, button, modifiers } } (client
--     .clickBindings, a CLIENT NEED: C_ClickBindings.GetProfileInfo), nil
--     when not known; spellName(id) -> name or nil
--   CC.Problems(bindings) -> sentences: a plain left or right click on a
--     unit frame that does nothing, or whose action has no button   (pure)
--   CC.UnderLine(names) -> the line for `under`; names: client.mouseFoci()
--     (a CLIENT NEED: GetMouseFoci's frame names), nil when not known
--   CC.Start(k, diag) adds the two words.
-- The modifier's name is not read (the game's GetStringFromModifiers is
-- not asked for): a modifier is said by its number. Not tested in game.
CC.CLICKS_WORD, CC.UNDER_WORD = "clicks", "under"
CC.CLICKS_HEAD = "Clicks on unit frames (party, player, target):"
CC.CLICKS_UNKNOWN = "This client gives no click bindings to read."
CC.CLICKS_NONE = "No click bindings listed: the game's own (left button targets, right button opens the menu)."
CC.WARN = "Watch out: "
CC.FIX = "To fix it, open Click Bindings from your spellbook: put \"Target\" back on the left button and "
    .. "\"Open menu\" on the right, or reset them to the defaults."
CC.UNDER = "Under the mouse: %s"
CC.UNDER_NOTHING = "Under the mouse: nothing that takes a click (the game world)."
CC.UNDER_UNKNOWN = "What is under the mouse is not known on this client."
CC.HELP_CLICKS = "what each mouse button does on a unit frame"
CC.HELP_UNDER = "what is under the mouse right now"

-- The game's numbers (Enum.ClickBindingType, Enum.ClickBindingInteraction).
local TYPE = { SPELL = 1, MACRO = 2, INTERACTION = 3, PET = 4 }
local INTERACTION = { [1] = "Target", [2] = "Open menu" }
local DOES = { [1] = "target it", [2] = "open its menu" }
local BUTTON_ID = { LeftButton = "BUTTON1", RightButton = "BUTTON2", MiddleButton = "BUTTON3",
                    Button4 = "BUTTON4", Button5 = "BUTTON5" }
local BUTTON_NAME = { BUTTON1 = "left button", BUTTON2 = "right button", BUTTON3 = "middle button",
                      BUTTON4 = "button 4", BUTTON5 = "button 5" }

local function buttonOf(name)
    if type(name) ~= "string" then return name end
    local id = BUTTON_ID[name]
    if id == nil then id = name:upper() end
    return id
end

local function buttonWords(name)
    local words = BUTTON_NAME[buttonOf(name)]
    if words == nil then words = tostring(name) end
    return words
end

local function capital(s) return (s:gsub("^%l", string.upper)) end

local function does(b, spellName)
    if b.type == TYPE.INTERACTION then
        local d = DOES[b.actionID]
        if d == nil then d = "interaction " .. tostring(b.actionID) end
        return d
    end
    if b.type == TYPE.SPELL then
        local name = nil
        if type(spellName) == "function" then
            local ok, v = pcall(spellName, b.actionID)
            if ok and type(v) == "string" and v ~= "" then name = v end
        end
        if name == nil then name = "spell " .. tostring(b.actionID) end
        return "cast " .. name
    end
    if b.type == TYPE.MACRO then return "run a macro" end
    if b.type == TYPE.PET then return "a pet action" end
    return "nothing"
end

function CC.DeadLine(button, name, elsewhere)
    local why = "has no button"
    if elsewhere then why = "sits on another button or needs a modifier" end
    return ("A plain %s on a unit frame does nothing: \"%s\" %s."):format(button, name, why)
end

function CC.LostLine(name, button)
    return ("\"%s\" has no button: your plain %s does something else on unit frames."):format(name, button)
end

function CC.Problems(bindings)
    local out = {}
    if type(bindings) ~= "table" or #bindings == 0 then return out end
    local plain, anywhere = {}, {}
    for _, b in ipairs(bindings) do
        if type(b) == "table" then
            if (b.modifiers == nil or b.modifiers == 0) and b.button then plain[buttonOf(b.button)] = b end
            if b.type == TYPE.INTERACTION then anywhere[b.actionID] = b end
        end
    end
    local function look(button, id)
        local p = plain[button]
        if p and p.type == TYPE.INTERACTION and p.actionID == id then return end
        if not p then
            out[#out + 1] = CC.DeadLine(BUTTON_NAME[button], INTERACTION[id], anywhere[id] ~= nil)
        elseif anywhere[id] == nil then
            out[#out + 1] = CC.LostLine(INTERACTION[id], BUTTON_NAME[button])
        end
    end
    look("BUTTON1", 1)
    look("BUTTON2", 2)
    return out
end

function CC.Report(bindings, spellName)
    if type(bindings) ~= "table" then return { CC.CLICKS_UNKNOWN } end
    if #bindings == 0 then return { CC.CLICKS_NONE } end
    local out = {}
    for _, b in ipairs(bindings) do
        if type(b) == "table" then
            local head = capital(buttonWords(b.button))
            if type(b.modifiers) == "number" and b.modifiers ~= 0 then
                head = "Modifier " .. tostring(b.modifiers) .. " + " .. buttonWords(b.button)
            end
            out[#out + 1] = head .. ": " .. does(b, spellName)
        end
    end
    local problems = CC.Problems(bindings)
    for _, p in ipairs(problems) do out[#out + 1] = CC.WARN .. p end
    if #problems > 0 then out[#out + 1] = CC.FIX end
    return out
end

function CC.UnderLine(names)
    if type(names) ~= "table" then return CC.UNDER_UNKNOWN end
    local list = {}
    for _, n in ipairs(names) do
        if type(n) == "string" and n ~= "" then list[#list + 1] = n end
    end
    if #list == 0 then return CC.UNDER_NOTHING end
    return CC.UNDER:format(table.concat(list, " > "))
end

local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if ok then return v end
    return nil
end

function CC.Start(k, diag)
    local function say(text) k.client.print(k.id.title .. ": " .. text) end
    local function clicks()
        say(CC.CLICKS_HEAD)
        local lines = CC.Report(ask(k.client, "clickBindings"), function(id) return ask(k.client, "spellName", id) end)
        for _, line in ipairs(lines) do k.client.print("  " .. line) end
    end
    local function under()
        say(CC.UnderLine(ask(k.client, "mouseFoci")))
    end
    if diag and type(diag.commands) == "table" then
        diag.commands[CC.CLICKS_WORD] = clicks
        diag.commands[CC.UNDER_WORD] = under
        if type(diag.help) == "table" then
            diag.help[CC.CLICKS_WORD] = CC.HELP_CLICKS
            diag.help[CC.UNDER_WORD] = CC.HELP_UNDER
        end
    end
    return { clicks = clicks, under = under }
end

-- The addon's own: the words are added when this file loads.
ns.clickWords = CC.Start(ns, ns.diag)

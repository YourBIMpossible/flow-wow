local _, ns = ...

-- SettingsKeys (N57; lead section 249 item 2; Plexy's note 1 of section
-- 250): the rotation key and its second key, set and cleared from the
-- settings page. The key is a binding of the game's, to the rotation key's
-- secure button (Rotation/KeyFrame.lua, named framePrefix .. "RotationKey"):
-- "CLICK <button>:LeftButton". Nothing is stored by the add-on; the game
-- keeps it in its own binding set.
--
-- Nothing is bound by the add-on on its own: no binding on load, on an
-- event or on a timer. Every write follows the player's own press on the
-- page, out of combat, and is exactly what the player chose:
--   Set key      -> the capture overlay (client.keyCapture); the next key:
--                   Escape cancels; a key bound to nothing, or already one
--                   of Z-Flow's (it moves, never doubles), is set at once;
--                   a key bound to something else is asked about first:
--     Use it anyway      an override for this session only
--                        (client.overrideBindingClick); the game's own
--                        binding stays under it and is back after a reload
--     Use it and unbind  the key is taken off the other action, set, and
--                        the binding set saved
--     Pick another       the overlay again
--   Clear        -> the key unbound and the binding set saved (or, for a
--                   key used anyway, the override taken off)
-- Set and save: client.clearBinding for the slot's old keys, then
-- client.setBindingClick for each key in order, then client.saveBindings.
-- A write that fails puts the old keys back as far as the client lets,
-- saves nothing, and the page says it could not be set.
-- Refused while the game's combat lock is on or cannot be read (not known
-- counts as locked), and while the game will not say which keys are bound.
--
--   SK.New(k) -> keys
--     keys.attach(client, status)   status(text) redraws the page with text
--     keys.rows() -> the page rows: { kind = "actions", key, label, shown,
--                    group, topic, synonyms, settable, why, under,
--                    buttons = { { text, id, enabled } } } per slot, and the
--                    question row (key SK.IN_USE_KEY) under the slot asked
--     keys.matches(query) -> true when a search finds the rows
--     keys.press(id)   a button of the rows was clicked
--     keys.lines() -> "label: shown" for the text page
-- Fake client only; not tested in game.
local SK = {}
ns.SettingsKeys = SK

SK.NAME = "settingsKeys"
SK.BUTTON = "RotationKey"
SK.GROUP = "combat"
SK.SYNONYMS = { "key", "keybind", "bind", "binding", "hotkey" }
SK.SLOTS = {
    { key = "keys.rotation", n = 1, label = "Rotation key" },
    { key = "keys.rotation2", n = 2, label = "Rotation second key" },
}
SK.IN_USE_KEY = "keys.inUse"
SK.SECTION = "Keys"

SK.SET = "Set key"
SK.CLEAR = "Clear"
SK.ANYWAY = "Use it anyway"
SK.UNBIND = "Use it and unbind"
SK.OTHER = "Pick another"
SK.NOT_SET = "not set"
SK.NOT_KNOWN = "not known"
SK.SESSION = " (until you reload)"
SK.LOCKED = "Keys can't change in combat."
SK.LOCK_UNKNOWN = "The game won't say whether you are in combat, so no key is changed."
SK.UNREAD = "The game won't say which keys are bound, so no key is changed."
SK.NO_CAPTURE = "This game gives no way to catch a key here."
SK.CANCELLED = "No key set: cancelled."
SK.FAILED = "could not be set"

local function copyList(list)
    local out = {}
    for i = 1, #list do out[i] = list[i] end
    return out
end

function SK.New(k)
    local keys = { overrides = {} }
    local client, onStatus, capture
    local id = k.id or ns.id
    local title = tostring(id.title)
    local function action() return "CLICK " .. tostring(id.framePrefix) .. SK.BUTTON .. ":LeftButton" end
    local function button() return tostring(id.framePrefix) .. SK.BUTTON end

    local function status(text)
        if type(onStatus) == "function" then pcall(onStatus, text) end
    end
    local function problem(what, why)
        if type(k.problems) == "table" and type(k.problems.add) == "function" then
            pcall(k.problems.add, k.problems, SK.NAME, what, why)
        end
    end
    -- A client function under pcall: ok, then what it gave. false and
    -- "absent" for one the client lacks.
    local function ask(name, ...)
        if type(client) ~= "table" or type(client[name]) ~= "function" then return false, "absent" end
        return pcall(client[name], ...)
    end
    local function write(name, ...)
        local ok, done, why = ask(name, ...)
        if not ok then return false, tostring(done) end
        if done ~= true then return false, tostring(why or "refused") end
        return true
    end
    local function lockWhy()
        local ok, lock = ask("combatLockdown")
        if ok and lock == false then return nil end
        if ok and lock == true then return SK.LOCKED end
        return SK.LOCK_UNKNOWN
    end
    local function readKeys()
        local ok, got = ask("bindingKeys", action())
        if not ok or type(got) ~= "table" then return nil end
        return got
    end
    local function slotOf(n)
        for _, slot in ipairs(SK.SLOTS) do
            if slot.n == n then return slot end
        end
        return nil
    end
    local function shownOf(n, held)
        if keys.overrides[n] ~= nil then return keys.overrides[n] .. SK.SESSION end
        if held == nil then return SK.NOT_KNOWN end
        return held[n] or SK.NOT_SET
    end
    local function inUseText(p)
        local slot = slotOf(p.n)
        return p.key .. " already does " .. p.action .. ". Use it for " .. title .. "'s "
            .. string.lower(slot and slot.label or "key") .. "?"
    end
    local function under()
        return "Kept in the game's key bindings, not by " .. title
    end

    -- Takes this session's override off slot n and puts the others back.
    local function dropOverride(n)
        keys.overrides[n] = nil
        local ok, why = write("clearOverrideKeys")
        if not ok then return false, why end
        for _, key in pairs(keys.overrides) do
            local okSet, whySet = write("overrideBindingClick", key, button())
            if not okSet then return false, whySet end
        end
        return true
    end

    -- Sets slot n to key, the other slots kept in order; held: the keys
    -- bound now. unbindOther: the key is taken off the action it had.
    local function setKey(n, key, unbindOther, held)
        local slot = slotOf(n)
        local want = {}
        for i = 1, math.max(#held, n) do
            if i == n then
                want[#want + 1] = key
            elseif held[i] ~= nil and held[i] ~= key then
                want[#want + 1] = held[i]
            end
        end
        local fine, why = true, nil
        local function step(name, ...)
            if not fine then return end
            local ok, w = write(name, ...)
            if not ok then fine, why = false, w end
        end
        for _, old in ipairs(held) do step("clearBinding", old, action()) end
        if unbindOther then step("clearBinding", key, action()) end
        for _, k2 in ipairs(want) do step("setBindingClick", k2, button()) end
        step("saveBindings")
        if not fine then
            -- Put back what was bound, as far as the client lets; nothing saved.
            for _, k2 in ipairs(want) do write("clearBinding", k2, action()) end
            for _, old in ipairs(held) do write("setBindingClick", old, button()) end
            problem("set", why)
            status(slot.label .. " " .. SK.FAILED .. ": " .. tostring(why))
            return false
        end
        if keys.overrides[n] ~= nil then dropOverride(n) end
        for m, over in pairs(keys.overrides) do
            if over == key then dropOverride(m) end
        end
        status(slot.label .. " set to " .. key .. " and saved.")
        return true
    end

    -- The key the player pressed into the overlay for slot n.
    local function pressed(n, key)
        keys.capturing = nil
        local why = lockWhy()
        if why then return status(why) end
        local held = readKeys()
        if held == nil then return status(SK.UNREAD) end
        local ok, other = ask("bindingAction", key, action())
        if not ok or type(other) ~= "string" then
            return status("The game won't say what " .. key .. " does now; pick another key or try again.")
        end
        if other == "" or other == action() then return setKey(n, key, false, held) end
        keys.pending = { n = n, key = key, action = other }
        status(inUseText(keys.pending))
    end

    local function startCapture(n)
        local why = lockWhy()
        if why then return status(why) end
        if readKeys() == nil then return status(SK.UNREAD) end
        if capture == nil then
            local ok, h = ask("keyCapture", { name = tostring(id.framePrefix) .. "KeyCapture" })
            if ok and type(h) == "table" then capture = h end
        end
        if capture == nil or type(capture.start) ~= "function" then return status(SK.NO_CAPTURE) end
        local slot = slotOf(n)
        keys.pending, keys.capturing = nil, n
        local text = slot.label .. ": press a key. Escape cancels."
        local ok, err = pcall(capture.start, text,
            function(key) pressed(n, key) end,
            function()
                keys.capturing = nil
                status(SK.CANCELLED)
            end)
        if not ok then
            keys.capturing = nil
            problem("capture", err)
            return status(SK.NO_CAPTURE)
        end
        status(text)
    end

    local function clearSlot(n)
        local slot = slotOf(n)
        local why = lockWhy()
        if why then return status(why) end
        if keys.overrides[n] ~= nil then
            local ok, w = dropOverride(n)
            if not ok then return status(slot.label .. " " .. SK.FAILED .. ": " .. tostring(w)) end
            return status(slot.label .. " cleared.")
        end
        local held = readKeys()
        if held == nil then return status(SK.UNREAD) end
        local key = held[n]
        if key == nil then return status(slot.label .. " is not set.") end
        local ok, w = write("clearBinding", key, action())
        if ok then ok, w = write("saveBindings") end
        if not ok then
            problem("clear", w)
            return status(slot.label .. " " .. SK.FAILED .. ": " .. tostring(w))
        end
        status(slot.label .. " cleared and saved.")
    end

    local function useAnyway()
        local p = keys.pending
        if not p then return status("") end
        local why = lockWhy()
        if why then return status(why) end
        local ok, w = write("overrideBindingClick", p.key, button())
        local slot = slotOf(p.n)
        if not ok then
            problem("override", w)
            return status(slot.label .. " " .. SK.FAILED .. ": " .. tostring(w))
        end
        keys.pending = nil
        keys.overrides[p.n] = p.key
        status(slot.label .. " is " .. p.key .. " until you reload; the game's own binding stays under it.")
    end

    local function useAndUnbind()
        local p = keys.pending
        if not p then return status("") end
        local why = lockWhy()
        if why then return status(why) end
        local held = readKeys()
        if held == nil then return status(SK.UNREAD) end
        keys.pending = nil
        setKey(p.n, p.key, true, held)
    end

    function keys.attach(c, statusFn)
        client, onStatus = c, statusFn
    end

    function keys.press(what)
        if type(what) ~= "string" then return false end
        local verb, n = what:match("^(%a+):(%d+)$")
        n = tonumber(n)
        if verb == "set" and slotOf(n) then
            startCapture(n)
        elseif verb == "clear" and slotOf(n) then
            clearSlot(n)
        elseif what == "anyway" then
            useAnyway()
        elseif what == "unbind" then
            useAndUnbind()
        elseif what == "other" then
            local p = keys.pending
            keys.pending = nil
            if p then startCapture(p.n) else status("") end
        else
            return false
        end
        return true
    end

    function keys.rows()
        local held = readKeys()
        local why = lockWhy()
        if why == nil and held == nil then why = SK.UNREAD end
        local can = why == nil
        local out = {}
        for _, slot in ipairs(SK.SLOTS) do
            local has = keys.overrides[slot.n] ~= nil
            if held ~= nil and held[slot.n] ~= nil then has = true end
            out[#out + 1] = {
                kind = "actions", key = slot.key, label = slot.label, shown = shownOf(slot.n, held),
                group = SK.GROUP, topic = SK.GROUP, synonyms = copyList(SK.SYNONYMS),
                settable = can, why = why, under = under(),
                buttons = {
                    { text = SK.SET, id = "set:" .. slot.n, enabled = can },
                    { text = SK.CLEAR, id = "clear:" .. slot.n, enabled = can and has },
                },
            }
            local p = keys.pending
            if p ~= nil and p.n == slot.n then
                out[#out + 1] = {
                    kind = "actions", key = SK.IN_USE_KEY, label = inUseText(p),
                    group = SK.GROUP, topic = SK.GROUP, settable = can, why = why,
                    buttons = {
                        { text = SK.ANYWAY, id = "anyway", enabled = can },
                        { text = SK.UNBIND, id = "unbind", enabled = can },
                        { text = SK.OTHER, id = "other", enabled = can },
                    },
                }
            end
        end
        return out
    end

    function keys.matches(query)
        local Topics = ns.Settings and ns.Settings.Topics
        if type(Topics) ~= "table" or type(query) ~= "string" then return false end
        local words = Topics.Words(query)
        if #words == 0 then return false end
        for _, slot in ipairs(SK.SLOTS) do
            local row = { key = slot.key, label = slot.label, group = SK.GROUP, synonyms = SK.SYNONYMS }
            if Topics.Match(row, words) then return true end
        end
        return false
    end

    function keys.lines()
        local held = readKeys()
        local out = {}
        for _, slot in ipairs(SK.SLOTS) do out[#out + 1] = slot.label .. ": " .. shownOf(slot.n, held) end
        return out
    end

    return keys
end

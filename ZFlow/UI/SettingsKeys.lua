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
--                    actions = { { key, label, enabled } } } per slot, and the
--                    question row (key SK.IN_USE_KEY) under the slot asked
--     keys.matches(query) -> true when a search finds the rows
--     keys.press(id)   a button of the rows was clicked (ids start "keys.")
--     keys.lines() -> "label: shown" for the text page
--
-- Lead section 255: the mouseover button (Rotation/Mouseover.lua, named
-- framePrefix .. "Mouseover") has one slot of its own, the same flow and
-- refusals. One key is enough: its Shift, Ctrl and Alt parts are on the
-- button itself (N63), so the plain key is bound. Its Set key is greyed,
-- and refused with the reason, while the button is not made (its setting
-- off, or not made yet): no click is bound to a missing frame. A key on
-- the other Z-Flow button is Z-Flow's own: it moves without a question,
-- taken off that button, and the page says where it came from.
-- Fake client only; not tested in game.
local SK = {}
ns.SettingsKeys = SK

SK.NAME = "settingsKeys"
SK.BUTTON = "RotationKey"
SK.GROUP = "combat"
-- S23: the click-casting check's line (UI/ClickCheck.lua), under the rows.
SK.CLICK_KEY = "keys.clickCheck"
SK.SYNONYMS = { "key", "keybind", "bind", "binding", "hotkey" }
-- n: the slot's id; button: the secure button it binds (framePrefix ..
-- button); index: its place among that button's keys.
SK.SLOTS = {
    { key = "keys.rotation", n = 1, button = "RotationKey", index = 1, label = "Rotation key" },
    { key = "keys.rotation2", n = 2, button = "RotationKey", index = 2, label = "Rotation second key" },
    { key = "keys.mouseover", n = 3, button = "Mouseover", index = 1, label = "Mouseover key",
      synonyms = { "mouseover", "heal", "cure", "friendly", "key", "bind" }, needs = "mouseover" },
    -- S12 (P-KEYS slice A): the care key's own button (Rotation/CareKeys.lua).
    { key = "keys.care", n = 4, button = "CareKey", index = 1, label = "Care key",
      synonyms = { "care", "heal", "cure", "resurrect", "key", "bind" }, needs = "careKey" },
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
    local function button(b) return tostring(id.framePrefix) .. tostring(b or SK.BUTTON) end
    local function action(b) return "CLICK " .. button(b) .. ":LeftButton" end

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
    local function readKeys(b)
        local ok, got = ask("bindingKeys", action(b))
        if not ok or type(got) ~= "table" then return nil end
        return got
    end
    local function slotOf(n)
        for _, slot in ipairs(SK.SLOTS) do
            if slot.n == n then return slot end
        end
        return nil
    end
    local function shownOf(slot, held)
        if keys.overrides[slot.n] ~= nil then return keys.overrides[slot.n] .. SK.SESSION end
        if held == nil then return SK.NOT_KNOWN end
        return held[slot.index] or SK.NOT_SET
    end
    -- Why a slot's button cannot take a key now, or nil (section 255: the
    -- mouseover button is made only with its setting on).
    local function needWhy(slot)
        if slot.needs == "careKey" then
            local CK = ns.CareKeys
            if type(CK) ~= "table" then return "There is no care key in this version." end
            local okCare, care = false, nil
            if type(k.settings) == "table" then okCare, care = pcall(k.settings.get, k.settings, CK.SETTING) end
            if not okCare or care ~= true then
                return "Switch on \"" .. tostring(CK.LABEL) .. "\" first: the care key's button is made only then."
            end
            local careApi, careMade = k.careKey, false
            if type(careApi) == "table" and type(careApi.made) == "function" then
                local okMade, got = pcall(careApi.made)
                careMade = okMade and got == true
            end
            if not careMade then
                return "Your care key's button is not made yet: it is made outside a fight with the rotation on."
            end
            return nil
        end
        if slot.needs ~= "mouseover" then return nil end
        local M = ns.Mouseover
        if type(M) ~= "table" then return "There is no mouseover button in this version." end
        local okOn, on = false, nil
        if type(k.settings) == "table" then okOn, on = pcall(k.settings.get, k.settings, M.SETTING) end
        if not okOn or on ~= true then
            return "Switch on \"" .. tostring(M.LABEL) .. "\" first: the mouseover button is made only then."
        end
        local api, made = k.mouseover, false
        if type(api) == "table" and type(api.made) == "function" then
            local okMade, got = pcall(api.made)
            made = okMade and got == true
        end
        if not made then
            return "Your mouseover button is not made yet: it is made outside a fight once you know a heal or cure."
        end
        return nil
    end
    -- The first slot of the Z-Flow button whose action this is, or nil.
    local function ownSlotOf(act)
        for _, slot in ipairs(SK.SLOTS) do
            if action(slot.button) == act then return slot end
        end
        return nil
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
        for m, key in pairs(keys.overrides) do
            local okSet, whySet = write("overrideBindingClick", key, button(slotOf(m).button))
            if not okSet then return false, whySet end
        end
        return true
    end

    -- Sets slot n to key, the button's other keys kept in order; held: the
    -- button's keys bound now. unbindOther: the key is taken off the action
    -- it had. movedFrom: the slot of the other Z-Flow button it came from.
    local function setKey(n, key, unbindOther, held, movedFrom)
        local slot = slotOf(n)
        local b = slot.button
        local want = {}
        for i = 1, math.max(#held, slot.index) do
            if i == slot.index then
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
        for _, old in ipairs(held) do step("clearBinding", old, action(b)) end
        if unbindOther then step("clearBinding", key, action(b)) end
        for _, k2 in ipairs(want) do step("setBindingClick", k2, button(b)) end
        step("saveBindings")
        if not fine then
            -- Put back what was bound, as far as the client lets; nothing saved.
            for _, k2 in ipairs(want) do write("clearBinding", k2, action(b)) end
            for _, old in ipairs(held) do write("setBindingClick", old, button(b)) end
            if movedFrom then write("setBindingClick", key, button(movedFrom.button)) end
            problem("set", why)
            status(slot.label .. " " .. SK.FAILED .. ": " .. tostring(why))
            return false
        end
        if keys.overrides[n] ~= nil then dropOverride(n) end
        for m, over in pairs(keys.overrides) do
            if over == key then dropOverride(m) end
        end
        if movedFrom then
            status(slot.label .. " set to " .. key .. ", moved from the " .. movedFrom.label .. ", and saved.")
        else
            status(slot.label .. " set to " .. key .. " and saved.")
        end
        return true
    end

    -- The key the player pressed into the overlay for slot n.
    local function pressed(n, key)
        keys.capturing = nil
        local slot = slotOf(n)
        local why = lockWhy() or needWhy(slot)
        if why then return status(why) end
        local held = readKeys(slot.button)
        if held == nil then return status(SK.UNREAD) end
        local ok, other = ask("bindingAction", key, action(slot.button))
        if not ok or type(other) ~= "string" then
            return status("The game won't say what " .. key .. " does now; pick another key or try again.")
        end
        if other == "" or other == action(slot.button) then return setKey(n, key, false, held) end
        local own = ownSlotOf(other)
        if own then return setKey(n, key, true, held, own) end
        keys.pending = { n = n, key = key, action = other }
        status(inUseText(keys.pending))
    end

    local function startCapture(n)
        local why = lockWhy() or needWhy(slotOf(n))
        if why then return status(why) end
        if readKeys(slotOf(n).button) == nil then return status(SK.UNREAD) end
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
        local held = readKeys(slot.button)
        if held == nil then return status(SK.UNREAD) end
        local key = held[slot.index]
        if key == nil then return status(slot.label .. " is not set.") end
        local ok, w = write("clearBinding", key, action(slot.button))
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
        local slot = slotOf(p.n)
        local why = lockWhy() or needWhy(slot)
        if why then return status(why) end
        local ok, w = write("overrideBindingClick", p.key, button(slot.button))
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
        local why = lockWhy() or needWhy(slotOf(p.n))
        if why then return status(why) end
        local held = readKeys(slotOf(p.n).button)
        if held == nil then return status(SK.UNREAD) end
        keys.pending = nil
        setKey(p.n, p.key, true, held)
    end

    function keys.attach(c, statusFn)
        client, onStatus = c, statusFn
    end

    function keys.press(what)
        if type(what) ~= "string" or what:sub(1, 5) ~= "keys." then return false end
        what = what:sub(6)
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

    -- S23 (P-KEYS slice B): the click-casting check's one line
    -- (UI/ClickCheck.lua), or nil. A read only.
    local function clickLine()
        local CC = ns.ClickCheck
        if type(CC) ~= "table" or client == nil then return nil end
        local slots = {}
        for _, slot in ipairs(SK.SLOTS) do
            slots[#slots + 1] = { label = slot.label, action = action(slot.button), override = keys.overrides[slot.n] }
        end
        local ok, line = pcall(function() return CC.Line(CC.Read(client, slots), id.title) end)
        if ok and type(line) == "string" then return line end
        return nil
    end

    function keys.rows()
        local lock = lockWhy()
        local byButton = {}
        local out = {}
        for _, slot in ipairs(SK.SLOTS) do
            if byButton[slot.button] == nil then byButton[slot.button] = readKeys(slot.button) or false end
            local held = byButton[slot.button]
            if held == false then held = nil end
            local why = lock
            if why == nil and held == nil then why = SK.UNREAD end
            local can = why == nil
            local need = needWhy(slot)
            local has = keys.overrides[slot.n] ~= nil
            if held ~= nil and held[slot.index] ~= nil then has = true end
            local why2 = why
            if why2 == nil then why2 = need end
            out[#out + 1] = {
                kind = "actions", key = slot.key, label = slot.label, shown = shownOf(slot, held),
                group = SK.GROUP, topic = SK.GROUP, synonyms = copyList(slot.synonyms or SK.SYNONYMS),
                settable = can and need == nil, why = why2, under = under(),
                actions = {
                    { key = "keys.set:" .. slot.n, label = SK.SET, enabled = can and need == nil },
                    { key = "keys.clear:" .. slot.n, label = SK.CLEAR, enabled = can and has },
                },
            }
            local p = keys.pending
            if p ~= nil and p.n == slot.n then
                out[#out + 1] = {
                    kind = "actions", key = SK.IN_USE_KEY, label = inUseText(p),
                    group = SK.GROUP, topic = SK.GROUP, settable = can, why = why,
                    actions = {
                        { key = "keys.anyway", label = SK.ANYWAY, enabled = can },
                        { key = "keys.unbind", label = SK.UNBIND, enabled = can },
                        { key = "keys.other", label = SK.OTHER, enabled = can },
                    },
                }
            end
        end
        local click = clickLine()
        if click ~= nil then
            out[#out + 1] = { kind = "note", key = SK.CLICK_KEY, text = click, group = SK.GROUP, topic = SK.GROUP }
        end
        return out
    end

    function keys.matches(query)
        local Topics = ns.Settings and ns.Settings.Topics
        if type(Topics) ~= "table" or type(query) ~= "string" then return false end
        local words = Topics.Words(query)
        if #words == 0 then return false end
        for _, slot in ipairs(SK.SLOTS) do
            local row = { key = slot.key, label = slot.label, group = SK.GROUP, synonyms = slot.synonyms or SK.SYNONYMS }
            if Topics.Match(row, words) then return true end
        end
        return false
    end

    function keys.lines()
        local out = {}
        for _, slot in ipairs(SK.SLOTS) do
            out[#out + 1] = slot.label .. ": " .. shownOf(slot, readKeys(slot.button))
        end
        local click = clickLine()
        if click ~= nil then out[#out + 1] = click end
        return out
    end

    return keys
end

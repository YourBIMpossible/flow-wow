local _, ns = ...

-- The key frame (G23): ONE secure button that holds the key plan's
-- attributes, so that the form's spells sit on one button. It is set
-- outside a fight only. In a fight a change is kept as wanted and applied
-- after the fight ends (PLAYER_REGEN_ENABLED); nothing is ever set while the
-- game's lock is not a plain false.
--
-- It presses nothing. A secure button acts only on a hardware click of the
-- player; this file binds no key to it, shows it nowhere and never clicks
-- it. No state handler, no state driver, no binding is made here.
--
-- It holds the key PLAN, not the live suggestion: ns.cast.Attributes is
-- asked with no suggestion, so the button holds the row of the form you
-- are in. A suggestion changes all through a fight and the button may not.
--
-- The secure button is a client need that Core/Client.lua does not have
-- yet (CLIENT NEED 5); until it is there the module says once that nothing
-- is set:
--   client.secureButton({ name }) -> h | nil    made from K.TEMPLATE
--     h.set(attr, value) -> true, or false and why ("lockdown", "refused");
--                           it refuses by itself while the lock is not false
--     h.get(attr) -> the value held, or nil
--   client.form() -> number | nil                the form you are in (NEED 6)
--
--   K.New({ button, lockdown, form }) -> kf
--     button    the handle above, or nil
--     lockdown  function: true in a fight, false outside, nil not known
--     form      function giving the form number, or nil
--   kf:want(plan) -> status   plan: what ns.KeyPlan returned; nil: hold nothing
--   kf:try([force]) -> status tries what is wanted. A failed apply is not
--                             tried again until force is true or the wanted
--                             plan changes
--   kf:reform() -> status     the form changed: work the rows out again
--   kf:status() -> status
--   status = {
--     state     "idle" (nothing wanted yet), "waiting", "set", "cleared",
--               "failed", "noFrame"
--     reason    waiting: "lockdown" or "lockdownUnknown"; failed with no
--               parts: why the plan was refused ("plan")
--     failed    list of { attr, why }: why is "refused" (the client call
--               failed) or "notKept" (the read-back gave something else)
--     parts     how many attributes differed from what the button held
--     form, formRead   the form the rows were taken from, and whether the
--               client gave it (not read: the no-form row, 0, is used)
--     held      what the button holds, as far as this file set it
--   }
--   K.Lines(status) -> lines      the state in plain words; nil: it is off
--   K.FailLine(status) -> text    the one line said at a failure, or nil
--   K.Declare(k[, diag]) -> { status = fn }   the module on kernel k, and
--               the word K.WORD after the slash command
--
-- Not tested in game: the template, the attribute names and the two client
-- needs are first guesses until seen in this client.
-- The template and the attribute names type, spell and item are on
-- warcraft.wiki.gg (SecureActionButtonTemplate).
-- Section 246 (N63-E): the button is never given the type "macro" (a
-- macro-type secure button does not act on this client). The healing item
-- on Alt (N8) is the item type, "*type-alt" = "item", "*item-alt" =
-- "item:ID"; N8 stays PARTLY until seen in the client.
local K = {}
ns.KeyFrame = K

local D = ns.RotationDriver
local C = ns.cast

K.NAME = "rotationKeys"
K.SETTING = "rotation.keyFrame"
K.WORD = "keys"
K.TEMPLATE = "SecureActionButtonTemplate"
K.LABEL = "Keep the rotation on one button"
K.HELP = "show what your rotation button holds; keys apply tries again what could not be set"
K.SLOT_ORDER = { "key", "ctrl", "shift", "alt", "more" }

local SUBJECT = "your rotation button"

-- A plan as one text, to tell a changed plan from the same one again.
local function signature(plan)
    if plan == nil then return "clear" end
    if type(plan) ~= "table" then return "bad:" .. tostring(plan) end
    local out = { tostring(plan.condition) }
    local states = type(plan.states) == "table" and plan.states or {}
    for state = 0, ns.Rotation.STEALTH_STATE do
        local row = states[state]
        for _, slot in ipairs(K.SLOT_ORDER) do
            out[#out + 1] = type(row) == "table" and tostring(row[slot]) or "-"
        end
    end
    -- N8: the item on Alt is part of the plan; a changed item is a changed
    -- plan. Section 246 (N63-E): named as the attribute it puts on the
    -- button ("*item-alt=item:ID"), the item type, never a macro.
    if plan.altItem ~= nil then out[#out + 1] = "*item-alt=item:" .. tostring(plan.altItem) end
    -- N41 (P-KEYS slice B): a slot's unit (plan.units) is part of the plan.
    if type(plan.units) == "table" then
        for _, slot in ipairs(C.MODIFIERS) do
            if plan.units[slot] ~= nil then out[#out + 1] = "*unit-" .. slot .. "=" .. tostring(plan.units[slot]) end
        end
    end
    return table.concat(out, "|")
end

local function copy(t)
    local out = {}
    for key, value in pairs(t) do
        if type(value) == "table" then
            local inner = {}
            for k2, v2 in pairs(value) do inner[k2] = v2 end
            value = inner
        end
        out[key] = value
    end
    return out
end

function K.New(opts)
    opts = type(opts) == "table" and opts or {}
    local button = type(opts.button) == "table" and opts.button or nil
    local lockdown = type(opts.lockdown) == "function" and opts.lockdown or function() return nil end
    local formOf = type(opts.form) == "function" and opts.form or nil
    -- S12 care key (P-KEYS slice A): a button with rows of its own.
    -- opts.rows(plan) -> { { attr, value }, ... } replaces the rotation's
    -- rows; opts.signature(plan) -> text tells a changed plan. Left out:
    -- the rotation button as before.
    local rowsOf = nil
    if type(opts.rows) == "function" then rowsOf = opts.rows end
    local signature = type(opts.signature) == "function" and opts.signature or signature

    local kf = {}
    local held = {}
    local wanted, wantedSig, has = nil, nil, false
    local pending, stuck = false, false
    local applied
    local st = { state = button and "idle" or "noFrame", failed = {}, parts = 0 }

    local function now(state, fields)
        st = fields or {}
        st.state = state
        st.failed = st.failed or {}
        st.parts = st.parts or 0
        return kf:status()
    end

    function kf:status()
        local out = copy(st)
        local list = {}
        for i, row in ipairs(st.failed) do list[i] = { attr = row.attr, why = row.why } end
        out.failed = list
        out.held = copy(held)
        return out
    end

    -- One attribute. True, or false and why. Never raises.
    local function put(attr, value)
        local called, ok, why = pcall(button.set, attr, value)
        if not called then return false, "refused" end
        if ok ~= true then return false, type(why) == "string" and why or "refused" end
        if type(button.get) == "function" then
            local read, got = pcall(button.get, attr)
            if not read or got ~= value then return false, "notKept" end
        end
        return true
    end

    local function waiting(lock, fields)
        fields = fields or {}
        fields.reason = lock == true and "lockdown" or "lockdownUnknown"
        return now("waiting", fields)
    end

    function kf:try(force)
        if not button then return now("noFrame") end
        if not has then return kf:status() end
        if force then stuck = false end
        if not pending or stuck then return kf:status() end

        local lock = lockdown()
        if lock ~= false then return waiting(lock) end

        local rows, attrs, form, formRead
        if wanted == nil then
            local names = {}
            for attr in pairs(held) do names[#names + 1] = attr end
            table.sort(names)
            rows = {}
            for i, attr in ipairs(names) do rows[i] = { attr = attr } end
        elseif rowsOf then
            local made, got = pcall(rowsOf, wanted)
            if not made or type(got) ~= "table" then
                stuck = true
                return now("failed", { reason = "plan", text = "the plan could not be made into parts" })
            end
            rows = got
        else
            local f = formOf and formOf() or nil
            formRead = type(f) == "number"
            form = formRead and f or 0
            attrs = C.Attributes(nil, wanted, applied, false, form)
            if attrs.ok ~= true then
                stuck = true
                return now("failed", { reason = attrs.refused, text = attrs.reason,
                    form = form, formRead = formRead })
            end
            rows, form = attrs.button, attrs.form
        end

        local parts, failed = 0, {}
        for _, row in ipairs(rows) do
            if held[row.attr] ~= row.value then
                parts = parts + 1
                -- Asked before every single set: a fight that starts in the
                -- middle of the walk stops it, and the rest waits.
                lock = lockdown()
                if lock ~= false then return waiting(lock, { form = form, formRead = formRead }) end
                local ok, why = put(row.attr, row.value)
                if ok then
                    held[row.attr] = row.value
                elseif why == "lockdown" then
                    return waiting(true, { form = form, formRead = formRead })
                else
                    failed[#failed + 1] = { attr = row.attr, why = why }
                end
            end
        end

        local fields = { parts = parts, failed = failed, form = form, formRead = formRead }
        if #failed > 0 then
            stuck = true
            return now("failed", fields)
        end
        pending = false
        applied = attrs and attrs.plan or nil
        return now(wanted == nil and "cleared" or "set", fields)
    end

    function kf:want(plan)
        local sig = signature(plan)
        if not has or sig ~= wantedSig then
            wanted, wantedSig, has = plan, sig, true
            pending, stuck = true, false
        end
        return kf:try()
    end

    function kf:reform()
        if has then pending, stuck = true, false end
        return kf:try()
    end

    return kf
end

-- What the button holds, slot by slot: "key: Wrath; ctrl: Moonfire".
local function holds(held)
    held = type(held) == "table" and held or {}
    local out = {}
    -- Section 246 (N63-E): a spell or an item ("item:ID"); never a macro.
    local key = held.spell or held.item
    if key then out[#out + 1] = "key: " .. tostring(key) end
    for _, slot in ipairs(C.MODIFIERS) do
        local spell = held["*spell-" .. slot] or held["*item-" .. slot]
        if spell then out[#out + 1] = slot .. ": " .. tostring(spell) end
    end
    return table.concat(out, "; ")
end

local function failedParts(st)
    local names = {}
    for i, row in ipairs(st.failed) do names[i] = tostring(row.attr) .. " (" .. tostring(row.why) .. ")" end
    return table.concat(names, ", ")
end

function K.FailLine(st)
    if type(st) ~= "table" or st.state ~= "failed" then return nil end
    if #st.failed == 0 then
        return SUBJECT .. " could not be set: " .. tostring(st.text or st.reason) .. "."
    end
    return string.format("%s could not be set (%d of %d parts). It keeps what it had;"
        .. " it is tried again after your next fight or change.", SUBJECT, #st.failed, st.parts)
end

function K.Lines(st)
    if type(st) ~= "table" then
        return { SUBJECT .. " is off. Switch on \"" .. K.LABEL .. "\" in the settings to use it." }
    end
    local lines = {}
    if st.state == "noFrame" then
        lines[1] = SUBJECT .. ": this client build makes no secure button yet, so nothing is set."
    elseif st.state == "idle" then
        lines[1] = SUBJECT .. ": nothing to set yet."
    elseif st.state == "waiting" and st.reason == "lockdown" then
        lines[1] = SUBJECT .. " is waiting for the fight to end. Nothing changes in a fight."
    elseif st.state == "waiting" then
        lines[1] = SUBJECT .. " is waiting: the client did not say whether you are in a fight."
    elseif st.state == "cleared" then
        lines[1] = SUBJECT .. " holds nothing."
    elseif st.state == "set" then
        local what = holds(st.held)
        lines[1] = SUBJECT .. " is set" .. (what ~= "" and (". " .. what .. ".") or ", and the plan has no spell for it.")
    elseif st.state == "failed" then
        lines[1] = K.FailLine(st)
        if #st.failed > 0 then lines[2] = "Not set: " .. failedParts(st) .. "." end
    else
        lines[1] = SUBJECT .. ": state not known."
    end
    if st.formRead == false and (st.state == "set" or st.state == "failed") then
        lines[#lines + 1] = "form not read: the row for no form is used."
    end
    return lines
end

-- The module on kernel k. diag (optional) is what Diag.Start returned.
function K.Declare(k, diag)
    local api = {}
    local kf, client
    local noFrame, failSaid = false, false

    function api.status()
        if kf then return kf:status() end
        if noFrame then return { state = "noFrame", failed = {}, parts = 0 } end
        return nil
    end

    local function say(text)
        if client then client.print(ns.id.title .. ": " .. text) end
    end

    -- A failure is said once; again only after an apply went through.
    local function after(st)
        if st.state == "failed" then
            if not failSaid then
                failSaid = true
                local line = K.FailLine(st)
                say(line)
                k.problems:add(K.NAME, "apply", line)
            end
        elseif st.state == "set" or st.state == "cleared" then
            failSaid = false
        end
    end

    local function ensure()
        if kf then return kf end
        if noFrame or not client then return nil end
        local button = type(client.secureButton) == "function"
            and client.secureButton({ name = ns.id.framePrefix .. "RotationKey" }) or nil
        if type(button) ~= "table" or type(button.set) ~= "function" then
            noFrame = true
            k.problems:add(K.NAME, "frame", "the client made no secure button; " .. SUBJECT .. " is not set")
            return nil
        end
        kf = K.New({
            button = button,
            lockdown = client.combatLockdown,
            form = type(client.form) == "function" and client.form or nil,
        })
        return kf
    end

    local function switchedOn()
        return k.settings:get(K.SETTING) == true and k.settings:get(D.SETTING) == true
    end

    local function onView(view)
        if not (switchedOn() and type(view) == "table" and view.pack == true) then
            if kf then after(kf:want(nil)) end
            return
        end
        -- In a fight the driver has no plan to hand over: what is wanted
        -- stays as it is and waits.
        local keys = view.keys
        if type(keys) ~= "table" or keys.ok ~= true then
            if kf then after(kf:try()) end
            return
        end
        if not ensure() then return end
        after(kf:want(keys.plan))
    end

    local function run(rest)
        if k.settings:get(K.SETTING) ~= true and not kf then
            say(K.Lines(nil)[1])
            return
        end
        if kf and tostring(rest):find("apply", 1, true) then after(kf:try(true)) end
        local st = api.status()
        if k.settings:get(K.SETTING) ~= true and (st == nil or st.state == "cleared") then st = nil end
        local lines = K.Lines(st or (k.settings:get(K.SETTING) == true and { state = "idle" }) or nil)
        for i = 1, #lines do say(lines[i]) end
    end

    k:Module({
        name = K.NAME,
        needs = { "client", "store", "bus", D.NAME },
        settings = { {
            key = K.SETTING, scope = "char", type = "bool", default = false,
            label = K.LABEL,
            help = "Puts your form's spells on one hidden button, outside fights only. It presses nothing for you.",
            group = "combat.rotation", synonyms = { "key", "button", "keybind", "macro", "form", "easy key" },
        } },
        start = function(ctx)
            client = ctx.client
            ctx.bus:on(K.NAME, D.EVENT, onView)
            client.listen("PLAYER_REGEN_ENABLED", function()
                if kf then after(kf:try(true)) end
            end)
            client.listen("UPDATE_SHAPESHIFT_FORM", function()
                if kf then after(kf:reform()) end
            end)
        end,
    })

    if diag and type(diag.commands) == "table" then
        diag.commands[K.WORD] = run
        if type(diag.help) == "table" then diag.help[K.WORD] = K.HELP end
    end

    return api
end

-- The addon's own: declared when this file loads, off until the setting is
-- switched on.
ns.rotationKeys = K.Declare(ns, ns.diag)

local _, ns = ...

-- N63 (lead sections 245, 246): helpful spells on the unit under your
-- mouse. ONE secure button, made by the add-on, holds a static plan: no
-- modifier, your heal; Shift, Ctrl and Alt, your cures from the class's
-- dispel table (pack.dispels, the one P-PARTY reads in Rotation/Group.lua).
-- Each part is the spell type with the unit "mouseover": the game picks
-- the unit at the press. Nothing is retargeted and nothing is rewritten in
-- a fight; the button is never given the type "macro" (section 246, N63-E).
--
-- It presses nothing and binds nothing. A secure button acts only on a
-- hardware press of the player; this file binds no key to it, shows it
-- nowhere and never clicks it. Section 245: a key is bound only by the
-- player's own key press on the settings page, out of a fight.
--
-- It is set outside a fight only. In a fight a changed plan waits and is
-- applied after the fight ends (PLAYER_REGEN_ENABLED, or the next look
-- with the lock a plain false). Off (the default), what it set is cleared,
-- outside a fight.
--
--   M.Plan(pack, known) -> plan | nil
--       known(name) -> true, false or nil (not read). nil when there is no
--       class table. plan = { key = heal, shift, ctrl, alt = cures }: the
--       heal is the first known spell of pack.heals.self; the cures are the
--       known dispels in table order, one skipped when every kind it cures
--       is cured by one picked before it. A spell not read is left out.
--   M.Rows(plan) -> { { attr, value } }   every attribute this file sets,
--       in order; value nil clears it. No modifier: "type", "spell",
--       "unit"; a modifier: "*type-shift", "*spell-shift", "*unit-shift".
--   M.Known(client) -> known(name)   c.spellId, then c.spell(id).known
--   M.Lines(status) -> lines          what the button holds, plain words
--   M.Declare(k[, diag]) -> { status = fn }
--
-- Not tested in game: the attribute names and the unit "mouseover" on a
-- spell-type secure button are first guesses until seen in this client
-- (warcraft.wiki.gg, SecureActionButtonTemplate). The row stays PARTLY.
local M = {}
ns.Mouseover = M

M.NAME = "mouseover"
M.SETTING = "rotation.mouseover"
M.WORD = "mouseover"
M.BUTTON = "Mouseover"
M.UNIT = "mouseover"
M.EVERY = 2
M.SLOTS = { "shift", "ctrl", "alt" }
M.LABEL = "Heal and cure the unit under your mouse"
M.HELP = "show what your mouseover button holds"

local SUBJECT = "your mouseover button"

local function known(fn, name)
    local ok, v = pcall(fn, name)
    return ok and v == true
end

function M.Plan(pack, isKnown)
    if type(pack) ~= "table" or type(isKnown) ~= "function" then return nil end
    local plan = {}
    local heals = {}
    if type(pack.heals) == "table" and type(pack.heals.self) == "table" then heals = pack.heals.self end
    for _, name in ipairs(heals) do
        if type(name) == "string" and known(isKnown, name) then
            plan.key = name
            break
        end
    end
    local covered, used, slot = {}, {}, 1
    for _, rule in ipairs(type(pack.dispels) == "table" and pack.dispels or {}) do
        if slot > #M.SLOTS then break end
        local name, kinds = nil, {}
        if type(rule) == "table" then
            name = rule.spell
            if type(rule.types) == "table" then kinds = rule.types end
        end
        if type(name) == "string" and not used[name] and known(isKnown, name) then
            local adds = false
            for kind, on in pairs(kinds) do
                if on and not covered[kind] then adds = true end
            end
            if adds then
                for kind, on in pairs(kinds) do
                    if on then covered[kind] = true end
                end
                used[name] = true
                plan[M.SLOTS[slot]] = name
                slot = slot + 1
            end
        end
    end
    return plan
end

function M.Rows(plan)
    plan = type(plan) == "table" and plan or {}
    local rows = {}
    local function part(typeAttr, spellAttr, unitAttr, spell)
        if type(spell) ~= "string" then spell = nil end
        local kind, unit = nil, nil
        if spell then kind, unit = "spell", M.UNIT end
        rows[#rows + 1] = { attr = typeAttr, value = kind }
        rows[#rows + 1] = { attr = spellAttr, value = spell }
        rows[#rows + 1] = { attr = unitAttr, value = unit }
    end
    part("type", "spell", "unit", plan.key)
    for _, slot in ipairs(M.SLOTS) do
        part("*type-" .. slot, "*spell-" .. slot, "*unit-" .. slot, plan[slot])
    end
    return rows
end

function M.Known(client)
    return function(name)
        if type(client) ~= "table" or type(client.spellId) ~= "function"
            or type(client.spell) ~= "function" then
            return nil
        end
        local okId, id = pcall(client.spellId, name)
        if not okId or type(id) ~= "number" then return nil end
        local okRow, row = pcall(client.spell, id)
        if not okRow or type(row) ~= "table" then return nil end
        return row.known
    end
end

-- A plan as one text, to tell a changed plan from the same one again.
local function signature(plan)
    if type(plan) ~= "table" then return "clear" end
    local out = { tostring(plan.key) }
    for _, slot in ipairs(M.SLOTS) do out[#out + 1] = tostring(plan[slot]) end
    return table.concat(out, "|")
end

function M.Lines(st)
    if type(st) ~= "table" then
        return { SUBJECT .. " is off. Switch on \"" .. M.LABEL .. "\" in the settings to use it." }
    end
    if st.state == "noFrame" then
        return { SUBJECT .. ": this client build makes no secure button, so nothing is set." }
    elseif st.state == "waiting" then
        return { SUBJECT .. " is waiting for the fight to end. Nothing changes in a fight." }
    elseif st.state == "failed" then
        return { SUBJECT .. " could not be set; it is tried again after your next fight." }
    elseif st.state == "cleared" then
        return { SUBJECT .. " holds nothing." }
    elseif st.state ~= "set" then
        return { SUBJECT .. ": nothing to set yet (your class or spells not read)." }
    end
    local held, out = type(st.held) == "table" and st.held or {}, {}
    if held.spell then out[#out + 1] = "no modifier: " .. tostring(held.spell) end
    for _, slot in ipairs(M.SLOTS) do
        local v = held["*spell-" .. slot]
        if v then out[#out + 1] = slot .. ": " .. tostring(v) end
    end
    if #out == 0 then return { SUBJECT .. " is set, and you know no heal or cure for it." } end
    return { SUBJECT .. " is set (on the unit under your mouse). " .. table.concat(out, "; ") .. ".",
        "It has no key: bind one yourself to use it; nothing is bound for you." }
end

-- The module on kernel k. diag (optional) is what Diag.Start returned.
function M.Declare(k, diag)
    local api = {}
    local client, button
    local held = {}
    local noFrame, failedSig, failSaid = false, nil, false
    local st = nil

    -- Section 255: true once the secure button is made, so the settings
    -- page binds a key only to a frame that is there (UI/SettingsKeys.lua).
    function api.made() return button ~= nil end

    function api.status()
        if st == nil then return nil end
        local out, copy = {}, {}
        for key, v in pairs(st) do out[key] = v end
        for key, v in pairs(held) do copy[key] = v end
        out.held = copy
        return out
    end

    local function ensure()
        if button then return button end
        if noFrame or not client or type(client.secureButton) ~= "function" then
            noFrame = true
            return nil
        end
        local ok, h = pcall(client.secureButton, { name = ns.id.framePrefix .. M.BUTTON })
        if not ok or type(h) ~= "table" or type(h.set) ~= "function" then
            noFrame = true
            k.problems:add(M.NAME, "frame", "the client made no secure button; " .. SUBJECT .. " is not set")
            return nil
        end
        button = h
        return button
    end

    local function unlocked()
        if type(client.combatLockdown) ~= "function" then return false end
        local ok, lock = pcall(client.combatLockdown)
        return ok and lock == false
    end

    -- Sets each part that differs from what the button holds, asking the
    -- lock before every single set. Never raises.
    local function apply(plan, force)
        local sig = signature(plan)
        if not force and sig == failedSig then return end
        -- Nothing held and nothing to hold: no button is made for it.
        if next(held) == nil and (plan == nil or next(plan) == nil) then
            if plan ~= nil then
                st = { state = "set" }
            elseif st then
                st = { state = "cleared" }
            end
            return
        end
        if not ensure() then
            st = { state = "noFrame" }
            return
        end
        local failed = 0
        for _, row in ipairs(M.Rows(plan)) do
            if held[row.attr] ~= row.value then
                if not unlocked() then
                    st = { state = "waiting" }
                    return
                end
                local called, ok, why = pcall(button.set, row.attr, row.value)
                if called and ok == true then
                    local read, got = true, row.value
                    if type(button.get) == "function" then read, got = pcall(button.get, row.attr) end
                    if read and got == row.value then
                        held[row.attr] = row.value
                    else
                        failed = failed + 1
                    end
                elseif called and why == "lockdown" then
                    st = { state = "waiting" }
                    return
                else
                    failed = failed + 1
                end
            end
        end
        if failed > 0 then
            failedSig = sig
            st = { state = "failed", parts = failed }
            if not failSaid then
                failSaid = true
                k.problems:add(M.NAME, "apply", SUBJECT .. " could not be set (" .. failed .. " parts)")
            end
            return
        end
        failedSig, failSaid = nil, false
        st = { state = plan == nil and "cleared" or "set" }
    end

    local function look(ctx, force)
        if not client then return end
        if ctx.settings:get(M.SETTING) ~= true then
            apply(nil, force)
            return
        end
        local okClass, class = pcall(client.class)
        local pack = okClass and type(class) == "string" and type(ns.Packs) == "table" and ns.Packs[class] or nil
        local plan = M.Plan(pack, M.Known(client))
        if plan == nil then
            if st == nil then st = { state = "idle" } end
            return
        end
        apply(plan, force)
    end

    local function run()
        local s = api.status()
        if k.settings:get(M.SETTING) ~= true and (s == nil or s.state == "cleared") then s = nil end
        local lines = M.Lines(s)
        for i = 1, #lines do client.print(ns.id.title .. ": " .. lines[i]) end
    end

    k:Module({
        name = M.NAME,
        needs = { "client", "store" },
        settings = { {
            key = M.SETTING, scope = "char", type = "bool", default = false,
            label = M.LABEL,
            help = "Puts your heal (no modifier) and your cures (Shift, Ctrl, Alt) on one hidden button for the unit under your mouse, outside fights only. It binds no key and presses nothing for you.",
            group = "combat", synonyms = { "mouseover", "heal", "cure", "dispel", "cleanse", "party" },
        } },
        ticks = { { every = M.EVERY, run = function(ctx) look(ctx, false) end } },
        start = function(ctx)
            client = ctx.client
            client.listen("PLAYER_REGEN_ENABLED", function() look(ctx, true) end)
        end,
    })

    if diag and type(diag.commands) == "table" then
        diag.commands[M.WORD] = run
        if type(diag.help) == "table" then diag.help[M.WORD] = M.HELP end
    end

    return api
end

-- The addon's own: declared when this file loads, off until the setting is
-- switched on.
ns.mouseover = M.Declare(ns, ns.diag)

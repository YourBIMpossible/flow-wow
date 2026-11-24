local _, ns = ...

-- The rotation icon (WOW-ROTATION-ICON, G27 core): one icon that shows the
-- spell the rotation driver suggests, with that spell's own texture.
--
-- It shows; it presses nothing. No secure action, no key. It is on screen only while "Suggest the next spell" is on and the
-- driver has a suggestion whose texture the client gave. A spell the
-- client gives no id or no texture for is not shown: no texture is made up.
--
-- The player moves it with Ctrl held, like the arrows. The place is kept
-- in the account's layout through a setting row; nothing is stored until
-- the icon is first dragged.
--
-- Pet battles and vehicles: the client boundary has no read for either
-- today. Where client.petBattle or client.vehicle exists and answers true,
-- the icon is hidden; where neither exists the case is not handled.
--
-- Out of range: when the driver's step is farOpener (the next spell, but
-- the target is out of its range) the icon is tinted red, as the action
-- bar does, so the player sees "move closer" and not "press this now". Any
-- other suggestion puts the plain colour back.
--
-- Lead section 340: the icon says what it is in its tooltip (I.Tip): it
-- shows the next spell and casts nothing; the Flow button casts
-- (Rotation/FlowButton.lua). The Flow button's default place stands well
-- below this icon (FB.DEFAULT_POINT), so the two never stand side by side.
--
-- Cooldown text (G27): while the suggested spell has seconds of cooldown
-- left (client.spellCooldownLeft), the line under the icon says how long,
-- "8s" or "2m" (I.CooldownText). Ready, the global cooldown only, or not
-- known: no text. A look-only suggestion's words keep the line (I.Caption).
-- The text follows the driver's ticks; nothing else is timed.
--
-- Action bar glow (FLOW-PARITY D-06, Flow Modules/Rotation/Display.lua:2,
-- :151): while the icon shows a spell, the action bar buttons that hold
-- it glow (client.barGlow(name)); hidden, a look-only suggestion (another
-- player's), or no spell: no glow. Asked only when the spell changes.
-- Display only: it changes nothing a button casts.
--
-- Cooldown sweep and swing badge (FLOW-PARITY D-07, Flow Display.lua:70-80,
-- :96, :304, :355): while shown, the icon draws the suggested spell's
-- cooldown (client.spellCooldownSpan) and a badge while the swing is on.
-- Not tested in game: client.icon, client.spellTexture, the tint, the
-- caption and the tooltip on the icon (client.hoverTip) are first guesses.
local I = {}
ns.RotationIcon = I

local D = ns.RotationDriver

I.NAME = "rotationIcon"
I.SETTING = "rotationIcon.layout"
I.PATH = "layout.rotationIcon"
I.SIZE = 48 -- authored
I.DEFAULT_POINT = { "CENTER", "CENTER", 0, -160 } -- authored: below the middle

-- The spell name of a driver view, or nil when it suggests nothing. A kept
-- (stale) view is still the driver's view: the driver says so in its line.
function I.Spell(view)
    if type(view) ~= "table" then return nil end
    local s = view.suggestion
    if type(s) ~= "table" then return nil end
    local spell = s.spell
    if type(spell) ~= "string" or spell == "" then return nil end
    return spell
end

-- Lead section 340: the tooltip line. spell: the spell shown, or nil.
function I.Tip(spell)
    local what = "the next spell"
    if type(spell) == "string" and spell ~= "" then what = "the next spell, " .. spell end
    return "Rotation icon. Shows " .. what .. "; it casts nothing. Click the Flow button to cast."
end

-- The icon's mark for a driver view: "far" when the suggestion is the
-- out of range step, else nil.
function I.Mark(view)
    if type(view) ~= "table" or type(view.suggestion) ~= "table" then return nil end
    -- Lead section 243: a look-only suggestion (for another player) is
    -- marked, so the player sees the key will not cast it.
    if view.suggestion.look == true then return "look" end
    return view.suggestion.step == "farOpener" and "far" or nil
end

-- P-PARTY: the caption under the icon for a look-only suggestion (for
-- another player, Rotation/Group.lua): "<spell> on <name>", or "<spell>
-- on <party unit>" when no name was read; nil for anything else (no
-- caption). Shown live only: the name is never saved or logged.
function I.Words(view)
    if type(view) ~= "table" then return nil end
    local s = view.suggestion
    if type(s) ~= "table" or s.look ~= true then return nil end
    local spell = I.Spell(view)
    if not spell then return nil end
    local who = s.member
    if type(who) ~= "string" or who == "" then who = s.unit end
    if type(who) ~= "string" or who == "" then return spell end
    return spell .. " on " .. who
end

-- Lead section 409 item 2: true when the Flow button shows this view's
-- spell or item itself (Rotation/FlowButton.lua api.picture), and the icon
-- adds no mark (out of range, or a spell for another player).
function I.OnButton(view)
    if I.Mark(view) ~= nil then return false end
    local fb = ns.flowButton
    if type(fb) ~= "table" or type(fb.picture) ~= "function" then return false end
    local ok, shown = pcall(fb.picture, view)
    if not ok or shown == nil then return false end
    local spell = I.Spell(view)
    if spell ~= nil then
        if shown == spell then return true end
        local A = ns.cast and ns.cast.ATTACK
        return type(A) == "table" and A[shown] == true and A[spell] == true
    end
    local item = I.Item(view)
    return item ~= nil and shown == "item:" .. item
end

-- G27: below this many seconds left the text is not shown, so the global
-- cooldown after every cast does not flash a number under the icon.
I.MIN_LEFT = 1.5

-- The cooldown text for seconds left: "8s" up to a minute, then "2m",
-- rounded up (the spell is not ready at 7.2). nil when left is not a
-- finite number above I.MIN_LEFT.
function I.CooldownText(left)
    if type(left) ~= "number" or left ~= left or left == math.huge or left <= I.MIN_LEFT then return nil end
    if left <= 60 then return math.ceil(left) .. "s" end
    return math.ceil(left / 60) .. "m"
end

-- The line under the icon for a view and the suggested spell's seconds
-- left: the look-only words first (I.Words), else the cooldown text, else nil.
function I.Caption(view, left)
    local words = I.Words(view)
    if words then return words end
    if not I.Spell(view) then return nil end
    return I.CooldownText(left)
end

-- The suggested spell's seconds of cooldown left, or nil when not known.
-- D-07: the spell's cooldown start and length for the sweep; 0, 0 when
-- not known (the sweep is cleared, never guessed).
local function cooldownSpan(client, spell)
    if type(spell) ~= "string" or type(client.spellId) ~= "function"
        or type(client.spellCooldownSpan) ~= "function" then return 0, 0 end
    local okId, id = pcall(client.spellId, spell)
    if not okId or type(id) ~= "number" then return 0, 0 end
    local ok, start, length = pcall(client.spellCooldownSpan, id)
    if not ok or type(start) ~= "number" or type(length) ~= "number" then return 0, 0 end
    return start, length
end

-- D-07: is the swing on (any of ns.cast.ATTACK the client says is the
-- current spell). Only reads.
function I.Swinging(client)
    local A = ns.cast and ns.cast.ATTACK
    if type(A) ~= "table" or type(client.spellId) ~= "function"
        or type(client.currentSpell) ~= "function" then return false end
    for name in pairs(A) do
        local okId, id = pcall(client.spellId, name)
        if okId and type(id) == "number" then
            local ok, on = pcall(client.currentSpell, id)
            if ok and on == true then return true end
        end
    end
    return false
end

local function cooldownLeft(client, spell)
    if type(spell) ~= "string" or type(client.spellId) ~= "function"
        or type(client.spellCooldownLeft) ~= "function" then return nil end
    local okId, id = pcall(client.spellId, spell)
    if not okId or type(id) ~= "number" then return nil end
    local ok, left = pcall(client.spellCooldownLeft, id)
    if not ok then return nil end
    return left
end

local refused = setmetatable({}, { __mode = "k" })

-- The layout row on kernel k, declared the first time it is asked for; nil
-- when the kernel refused it (asked once, one problem).
function I.Row(k)
    local row = k.settings:row(I.SETTING)
    if row or refused[k] then return row end
    row = k:Setting({
        key = I.SETTING, scope = "account", type = "table", path = I.PATH,
        label = "Rotation icon position", group = "combat.rotation", synonyms = { "rotation", "icon", "position", "move" }, keepOnResetAll = true,
        help = "Where the suggested-spell icon stands. Resetting puts it back.",
    })
    if not row then
        refused[k] = true
        k.problems:add(I.NAME, "row", "the layout row was refused; the icon's place is not kept")
    end
    return row
end

-- Lead section 294: the line said once a session when the icon is on, a
-- fight is under way and there is nothing to suggest, so an empty icon is
-- not a silent one. Only for a real "nothing" (Twin review 17:11, F1): the
-- class pack read, no suggestion, no earlier reading kept after a failed
-- read, and a live enemy targeted. A suggestion whose picture was not read,
-- or no enemy yet, is a missing read or a wait, not "nothing".
I.EMPTY = "next spell: nothing to suggest in this fight yet"
I.EMPTY_HOW = "; the spells this character knows give no suggestion here. Type the slash command with diag to see why."

-- true only when the driver's view says there is nothing to suggest and an
-- enemy is targeted (see I.EMPTY).
function I.NothingToSuggest(client, view)
    if type(view) ~= "table" or view.pack ~= true or view.stale == true then return false end
    if I.Spell(view) ~= nil then return false end
    if type(client) ~= "table" or type(client.target) ~= "function" then return false end
    local ok, tg = pcall(client.target)
    return ok and type(tg) == "table" and tg.exists == true and tg.hostile == true and tg.dead == false
end

-- true only when the client has this read and it answers true. No read,
-- a read that raises, false or nil: not a yes.
local function says(client, name)
    local fn = client[name]
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn)
    return ok and v == true
end

-- The texture the client gives for a spell by name, or nil.
local function texture(client, spell)
    if type(client.spellId) ~= "function" or type(client.spellTexture) ~= "function" then return nil end
    local okId, id = pcall(client.spellId, spell)
    if not okId or type(id) ~= "number" then return nil end
    local ok, tex = pcall(client.spellTexture, id)
    if not ok then return nil end
    if type(tex) == "number" and tex > 0 then return tex end
    if type(tex) == "string" and tex ~= "" then return tex end
    return nil
end

-- Section 226 (CF-30): the item id of a driver view that suggests an item
-- (Well Fed food), or nil.
function I.Item(view)
    if type(view) ~= "table" or type(view.suggestion) ~= "table" then return nil end
    local id = view.suggestion.itemId
    if type(id) ~= "number" or id <= 0 or id % 1 ~= 0 then return nil end
    return id
end

-- The icon's texture for a driver view: the spell's, else the item's, as
-- the client gives it; nil when it gives none.
function I.Texture(client, view)
    local spell = I.Spell(view)
    if spell then return texture(client, spell) end
    local item = I.Item(view)
    if not item or type(client.itemTexture) ~= "function" then return nil end
    local ok, tex = pcall(client.itemTexture, item)
    if not ok then return nil end
    if type(tex) == "number" and tex > 0 then return tex end
    if type(tex) == "string" and tex ~= "" then return tex end
    return nil
end

function I.Declare(k)
    local icon
    local unglow -- D-06: clears the bar glow; set at start
    local api = {}
    function api.handle() return icon end

    k:Module({
        name = I.NAME,
        needs = { "client", "store", "bus", D.NAME },
        start = function(ctx)
            local client = ctx.client
            local row = I.Row(k)
            local saveSaid = false
            local emptySaid = false

            local function screen()
                if type(client.screen) ~= "function" then return nil end
                local ok, w, h = pcall(client.screen)
                if not ok then return nil end
                return w, h
            end
            local function savedPoint()
                if not row then return nil end
                local saved = k.settings:get(I.SETTING)
                return type(saved) == "table" and saved.point or nil
            end

            icon = type(client.icon) == "function"
                and client.icon({ name = ns.id.framePrefix .. "RotationIcon", size = I.SIZE }) or nil
            if not icon then
                icon = nil
                k.problems:add(I.NAME, "frame", "the client made no icon; the suggestion is not shown")
                return
            end

            local function mark(look)
                if type(icon.mark) == "function" then pcall(icon.mark, look) end
            end
            local function caption(words)
                if type(icon.caption) == "function" then pcall(icon.caption, words) end
            end
            local function fade(on)
                if type(icon.fade) == "function" then pcall(icon.fade, on) end
            end
            local function hide()
                caption(nil)
                mark(nil)
                icon.setTexture(nil)
                icon.show(false)
            end

            -- D-06: the spell whose bar buttons glow now; false: not asked yet.
            local glowing = false
            local function glow(spell)
                if spell == glowing then return end
                glowing = spell
                if type(client.barGlow) == "function" then pcall(client.barGlow, spell) end
            end
            unglow = function() glow(nil) end
            -- CHANGES-3: the bars change under the same spell (a dragged
            -- spell, the page, the bonus bar, a stance): scan them again.
            if type(client.listen) == "function" then
                local function rescan()
                    if type(glowing) == "string" and type(client.barGlow) == "function" then
                        pcall(client.barGlow, glowing)
                    end
                end
                for _, event in ipairs({ "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED",
                                         "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM" }) do
                    pcall(client.listen, event, rescan)
                end
            end

            hide()
            local shownSpell = nil
            if type(client.hoverTip) == "function" then
                pcall(client.hoverTip, { frame = ns.id.framePrefix .. "RotationIcon",
                    text = function() return I.Tip(shownSpell) end })
            end
            local w, h = screen()
            icon.place(ns.Nav.ClampPoint(savedPoint(), I.SIZE, w, h)
                or ns.Nav.ClampPoint(I.DEFAULT_POINT, I.SIZE, w, h)
                or I.DEFAULT_POINT)

            icon.onMoved(function(point)
                local sw, sh = screen()
                local to = ns.Nav.ClampPoint(point, I.SIZE, sw, sh)
                if not to then return end
                icon.place(to)
                if not row then return end
                local ok, reason = k.settings:set(I.SETTING, { point = to })
                if not ok and not saveSaid then
                    saveSaid = true
                    k.problems:add(I.NAME, "save",
                        "the icon's place was not kept (" .. tostring(reason) .. ")")
                end
            end, function(err) k.fault(I.NAME, err) end)

            ctx.bus:on(I.NAME, D.EVENT, function(view)
                if not icon then return end
                local tex = k.settings:get(D.SETTING) == true and I.Texture(client, view) or nil
                -- G55 (UI/Reveal.lua): a new player's icon waits for its
                -- stage. No reveal module, or any doubt: shown.
                local held = type(ns.Reveal) == "table" and type(ns.Reveal.Open) == "function"
                    and ns.Reveal.Open(k, "icon") == false
                shownSpell = nil
                if not tex or held or says(client, "petBattle") or says(client, "vehicle") then
                    hide()
                    glow(nil)
                    if not tex and not held and not emptySaid and k.settings:get(D.SETTING) == true
                        and I.NothingToSuggest(client, view)
                        and type(client.inCombat) == "function" and client.inCombat() == true
                        and type(client.print) == "function" then
                        emptySaid = true
                        pcall(client.print, ns.id.title .. ": " .. I.EMPTY .. I.EMPTY_HOW)
                    end
                    return
                end
                if icon.setTexture(tex) then
                    shownSpell = I.Spell(view)
                    mark(I.Mark(view))
                    caption(I.Caption(view, cooldownLeft(client, shownSpell)))
                    icon.show(true)
                    -- Lead section 409 item 2: one picture for the next
                    -- spell. While the Flow button shows this same spell
                    -- the icon stays on but draws nothing beside it; it is
                    -- seen only for what the button does not show, such as
                    -- the new suggestion in a fight while the locked button
                    -- keeps what it had, out of range or another player's.
                    fade(I.OnButton(view))
                    glow(I.Mark(view) ~= "look" and shownSpell or nil)
                    -- D-07: the sweep and the swing badge (display only).
                    if type(icon.cooldown) == "function" then
                        pcall(icon.cooldown, cooldownSpan(client, shownSpell))
                    end
                    if type(icon.swing) == "function" then pcall(icon.swing, I.Swinging(client)) end
                else
                    hide()
                    glow(nil)
                end
            end)
        end,
        stop = function()
            if unglow then unglow() end
            if icon then
                icon.setTexture(nil)
                icon.show(false)
            end
        end,
    })
    return api
end

-- The addon's own icon: declared when this file loads, made at login.
ns.rotationIcon = I.Declare(ns)

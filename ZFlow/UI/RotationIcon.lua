local _, ns = ...

-- The rotation icon (WOW-ROTATION-ICON, G27 core): one icon that shows the
-- spell the rotation driver suggests, with that spell's own texture.
--
-- It shows; it presses nothing. No secure action, no key, no action-bar
-- glow. It is on screen only while "Suggest the next spell" is on and the
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
-- Not tested in game: client.icon, client.spellTexture and the tint are
-- first guesses.
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
            local function hide()
                caption(nil)
                mark(nil)
                icon.setTexture(nil)
                icon.show(false)
            end

            hide()
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
                if not tex or held or says(client, "petBattle") or says(client, "vehicle") then
                    hide()
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
                    mark(I.Mark(view))
                    caption(I.Words(view))
                    icon.show(true)
                else
                    hide()
                end
            end)
        end,
        stop = function()
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

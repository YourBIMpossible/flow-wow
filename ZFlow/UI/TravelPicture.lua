local _, ns = ...

-- TravelPicture (B-28): the travel spell's or the hearthstone's picture
-- where the quest arrow stood, with the arrow at half size beside it, so
-- the player sees that the cast is the next thing to do and the arrow is
-- where it leads after (legacy Flow 0.35.377 Modules/Nav/TravelIcon.lua).
-- What to show and where is worked out by Nav/TravelIcon.lua
-- (N.TravelPictureIcon, N.TravelPicture); this file reads the client for
-- the picture and moves one frame.
--
-- SHOWS ONLY. The picture takes no mouse and holds no action: nothing here
-- casts, uses an item, or changes a secure frame. Nothing is saved or
-- printed. Not tested in game.
--
-- CLIENT NEED. On a client without it there is no picture and the arrow is
-- left as the layout put it.
--   client.picture(spec) -> handle or nil       (Core/Client.lua)
--     spec = { name, size, art, level }
--     handle.place(point), handle.show(on), handle.setTexture(tex) -> bool,
--     handle.alpha(n)
--
--   TravelPicture.New(client, spec) -> p or nil
--     spec: { name, size, level } for the frame (UI/Arrow.lua gives the
--     arrow frame's size, so the picture's point is the arrow's own).
--   p.draw(arrow, ops, step) -> true when the picture is up
--     arrow  the quest arrow's handle (client.arrow)
--     ops    what the layout said of it: { shown, point, scale }
--     step   the quest arrow's step (after N.TravelVia), or nil
--     Call it after the arrow was placed and scaled as ops says: with a
--     picture the arrow is put beside it at half size; an arrow in the
--     player's hand is not moved.
--   p.hide()
--   p.unshift(key, point) -> point
--     The point to save for an arrow let go at point: the quest arrow's is
--     moved back to where the picture belongs while the picture is up.
ns.TravelPicture = ns.TravelPicture or {}
local TP = ns.TravelPicture
local N = ns.Nav

TP.UNKNOWN_SPELL = "Interface\\Icons\\INV_Misc_QuestionMark"
TP.HEARTH = "Interface\\Icons\\INV_Misc_Rune_01"

local function texture(client, icon)
    if icon.kind == "hearth" then
        return client.itemTexture(N.PICTURE_HEARTH_ITEM) or TP.HEARTH
    end
    local id = icon.spell and client.spellId(icon.spell) or nil
    return (id and client.spellTexture(id)) or TP.UNKNOWN_SPELL
end

function TP.New(client, spec)
    if type(client) ~= "table" or type(client.picture) ~= "function" then return nil end
    spec = type(spec) == "table" and spec or {}
    local handle = client.picture({ name = spec.name, size = spec.size or N.ARROW_SIZE,
                                    art = N.PICTURE_SIZE, level = spec.level })
    if not handle then return nil end
    local p, shift, up = {}, nil, false

    local function down(arrow, ops)
        -- The picture was up: the arrow goes back to the layout's place
        -- and size, whether or not the caller lays it out again.
        if up and type(arrow) == "table" and type(ops) == "table" then
            if not arrow.dragging() then arrow.place(ops.point) end
            arrow.scale(ops.scale)
        end
        up, shift = false, nil
        handle.show(false)
        return false
    end

    function p.draw(arrow, ops, step)
        if type(arrow) ~= "table" or type(ops) ~= "table" or not ops.shown then return down(arrow, ops) end
        local icon = N.TravelPictureIcon(step)
        local pic = icon and N.TravelPicture(icon, ops.point, client.screen()) or nil
        if not pic or not handle.setTexture(texture(client, pic.icon)) then return down(arrow, ops) end
        handle.place(pic.at)
        handle.alpha(pic.alpha)
        handle.show(true)
        if not arrow.dragging() then arrow.place(pic.arrow.point) end
        arrow.scale(pic.arrow.scale)
        up, shift = true, pic.shift
        return true
    end

    function p.hide()
        up, shift = false, nil
        handle.show(false)
    end

    function p.unshift(key, point)
        if key ~= "quest" or not shift then return point end
        return N.TravelPictureBack(point, shift)
    end

    return p
end

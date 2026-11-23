local _, ns = ...
-- S29 move handle (P-KEYS slice C): a grip that moves a frame of the add-on
-- out of a fight, for frames the player cannot Ctrl-drag, such as a row of
-- secure buttons. The client grip (client.moveHandle) only starts a move
-- while InCombatLockdown answers a plain false; let go, the place is kept
-- on the screen (ns.Nav.ClampPoint), placed, and handed to save, which
-- keeps it in the add-on own saved settings. Nothing else is written. The
-- S29 alignment guides (UI/MoveGuides.lua) are asked to look again for the
-- frame, which they line up while it moves.
--
-- First guess, not tested in game: the drag itself.
local MH = {}
ns.MoveHandle = MH

MH.GRIP = 10 -- pixels: the width of the grip

-- MH.Attach(k, client, spec) -> handle or nil. spec = { target (frame
-- name), width, height (the frame, to keep it on the screen), place(point),
-- save(point) }. nil when the client has no grip or no such frame.
function MH.Attach(k, client, spec)
    if type(client) ~= "table" or type(client.moveHandle) ~= "function" then return nil end
    if type(spec) ~= "table" or type(spec.target) ~= "string" then return nil end
    local function screen()
        if type(client.screen) ~= "function" then return nil end
        local ok, w, h = pcall(client.screen)
        if not ok then return nil end
        return w, h
    end
    local function onMoved(point)
        local sw, sh = screen()
        local to = ns.Nav.ClampPoint(point, spec.width, sw, sh, spec.height)
        if not to then return end
        if type(spec.place) == "function" then pcall(spec.place, to) end
        if type(spec.save) == "function" then pcall(spec.save, to) end
    end
    local ok, handle = pcall(client.moveHandle, {
        target = spec.target, width = MH.GRIP, height = spec.height, onMoved = onMoved,
    })
    if not ok or type(handle) ~= "table" then return nil end
    local guides = nil
    if type(k) == "table" then guides = k.moveGuides end
    if type(guides) == "table" and type(guides.again) == "function" then pcall(guides.again) end
    return handle
end

local _, ns = ...

-- One panel drawn by the shared kit, with the plain panel behind it (lead
-- section 297 item 5: every kit element has a plain-panel fallback). A
-- module hands over its kit view (a window spec for UI/Kit.lua) and the
-- plain panel's rows at each draw. The kit window is drawn while the client
-- makes one; the first time the kit or the client refuses it, the plain
-- panel takes over for the rest of the session, shown as the kit window
-- was, and one problem line says why. A host with no plain panel says
-- nothing: nothing can draw, and that is the client's, not the kit's.
--
-- LOOK ONLY. Nothing here sells, buys, moves, casts or clicks anything: the
-- view's parts carry the module's own functions, and the host only hands
-- them to the kit.
--
--   KitHost.New(k, client, opts) -> host
--     opts.name      the kit window's frame name (Escape needs one); not the
--                    plain panel's own name
--     opts.panel     the plain panel (client.rowPanel), or nil
--     opts.onClose   told when the player closes the kit window
--     opts.place     place() -> where the kit window first stands
--                    ({ anchor, screen anchor, x, y }), or nil for the
--                    view's own point; asked when the window is first made
--     opts.onMoved   onMoved(point) after the player drags the kit window
--   host.draw(view, rows, act)   view for the kit; rows and act for the
--                                plain panel
--   host.show(on)
--   host.shown() -> true | false   false once the player closed it
--   host.plain() -> true | false   the plain panel has taken over
--   host.dead()  -> true | false   nothing can draw: no kit, no plain panel
local KitHost = ns.KitHost or {}
ns.KitHost = KitHost

-- The kind of its lines in the problem list (k.problems).
KitHost.PROBLEM = "kitHost"
KitHost.FELL = "The kit window could not be drawn; the plain panel is used."
KitHost.CLICK = "A click on the kit window raised."
KitHost.NO_KIT = "no kit on this client"
KitHost.NO_WINDOW = "the client made no window"

function KitHost.New(k, client, opts)
    if type(opts) ~= "table" then opts = {} end
    local panel = opts.panel
    local host = {}
    -- handle: the kit window once drawn. plain: the plain panel has taken
    -- over. want: what show() last asked, for a window not drawn yet.
    local handle, plain, want = nil, false, false

    local function problem(id, text, detail)
        if type(k) == "table" and type(k.problems) == "table" then
            k.problems:add(KitHost.PROBLEM, tostring(id), text, tostring(detail))
        end
    end

    local function kitShown()
        if handle == nil then return false end
        local ok, shown = pcall(handle.shown)
        return ok and shown == true
    end

    -- The kit window drawn from the view, or nil and why not.
    local function kit(view)
        local Kit = ns.Kit
        if type(client.kitWindow) ~= "function" or type(Kit) ~= "table" or type(Kit.Window) ~= "function" then
            return nil, KitHost.NO_KIT
        end
        local tree, why = Kit.Window(view)
        if not tree then return nil, why end
        local building, told = true, nil
        local point
        if handle == nil and type(opts.place) == "function" then
            local okP, at = pcall(opts.place)
            if okP and type(at) == "table" then point = at end
        end
        local ok, h = pcall(client.kitWindow, view.id, tree, {
            name = opts.name,
            point = point,
            onClose = opts.onClose,
            onMoved = opts.onMoved,
            failed = function(err)
                if building then
                    told = err
                else
                    problem(view.id, KitHost.CLICK, err)
                end
            end,
        })
        building = false
        if not ok then return nil, h end
        if type(h) ~= "table" then return nil, told or KitHost.NO_WINDOW end
        return h
    end

    -- The plain panel takes over, shown as the kit window was.
    local function fall(id, why)
        if handle ~= nil then
            want = kitShown()
            pcall(handle.show, false)
            handle = nil
        end
        plain = true
        -- With no plain panel the client draws nothing at all (no frames):
        -- there is no hand-over to report.
        if panel ~= nil then problem(id, KitHost.FELL, why) end
    end

    function host.draw(view, rows, act)
        local fell = false
        if not plain then
            local id = type(view) == "table" and view.id or nil
            local h, why = kit(view)
            if h then
                -- A window drawn for the first time is shown when show()
                -- already asked; one drawn again keeps how it stands, so a
                -- window the player closed stays closed.
                if h ~= handle then
                    handle = h
                    if want then pcall(h.show, true) end
                end
                return
            end
            fall(id, why)
            fell = true
        end
        if panel then
            panel.draw(rows, act)
            -- Only at the hand-over: a plain panel the player closed stays
            -- closed when it is drawn again.
            if fell then panel.show(want) end
        end
    end

    function host.show(on)
        want = on == true
        if plain then
            if panel then panel.show(want) end
        elseif handle ~= nil then
            pcall(handle.show, want)
        end
    end

    function host.shown()
        if plain then
            if panel then return panel.shown() == true end
            return false
        end
        return kitShown()
    end

    function host.plain() return plain end
    function host.dead() return plain and panel == nil end

    return host
end

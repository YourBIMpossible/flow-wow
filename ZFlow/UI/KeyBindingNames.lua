local _, ns = ...

-- The Key Bindings screen entry (FLOW-PARITY F-19; lead sections 580 item
-- 10, 850), as Flow's Bindings.xml: ZFlow/Bindings.xml declares one CLICK
-- binding on the rotation key button (Rotation/KeyFrame.lua makes it, named
-- ns.id.framePrefix .. "RotationKey") under the ZFLOW heading. The game
-- reads Bindings.xml from the add-on's folder by itself; nothing here binds
-- a key or changes a secure attribute. A key the player picks in the game's
-- screen is the game's own binding.
--
-- The game shows the heading and the entry by two global names. Setting
-- globals is Core/Client.lua's (a lead patch); this file only says them:
--   KeyBindingNames.Globals() -> { [global name] = text }

local KB = {}
ns.KeyBindingNames = KB

KB.HEADER = "ZFLOW"
KB.ACTION = "CLICK " .. ns.id.framePrefix .. "RotationKey:LeftButton"
KB.HEADER_TEXT = "Z-Flow"
KB.NAME_TEXT = "Z-Flow key: cast the suggested spell"

function KB.Globals()
    return {
        ["BINDING_HEADER_" .. KB.HEADER] = KB.HEADER_TEXT,
        ["BINDING_NAME_" .. KB.ACTION] = KB.NAME_TEXT,
    }
end

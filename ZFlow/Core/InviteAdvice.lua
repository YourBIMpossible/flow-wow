local _, ns = ...

-- P-INVITES (FEATURE-PLAN G58), advice text only. Pure: no client call.
-- With the setting on (invites.friends, off when not set), a friend's or
-- guild member's invite is named as one to accept; anyone else is left to
-- the player. Nothing accepts or declines: the acting half is held.
--   InviteAdvice.Advise(invite, settings)
--     invite    { inviter = name, friend = bool, guild = bool }
--     settings  { friends = bool }
--     returns   { accept = bool, text = words, look = true }, or nil with
--               no invite

local I = {}
ns.InviteAdvice = I

function I.Advise(invite, settings)
    if type(invite) ~= "table" then return nil end
    local who = type(invite.inviter) == "string" and invite.inviter ~= "" and invite.inviter or "Someone"
    local on = type(settings) == "table" and settings.friends == true
    local known
    if invite.friend == true then known = "a friend" elseif invite.guild == true then known = "in your guild" end
    if on and known then
        return { accept = true, look = true, text = who .. " invited you and is " .. known .. ": accept the invite." }
    end
    return { accept = false, look = true, text = who .. " invited you: up to you." }
end

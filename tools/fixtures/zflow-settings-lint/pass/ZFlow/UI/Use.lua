local _, ns = ...
local X = {}
X.SETTING = "b.two"
-- settings:get("nope") in a comment is not a call
function X.Read(ctx) return ctx.settings:get(X.SETTING), ctx.settings:get("a.one") end
function X.Any(ctx, key) return ctx.settings:get(key) end
return X

-- A comment may say price unknown - check vendor; comments are not user text.
local F = {}
F.TEXT = "price unknown—check vendor"
F.ESCAPED = "price unknown\226\128\148check vendor"
F.LINE = "3 x Thread: price unknown—check vendor"
return F

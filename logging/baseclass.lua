local baseclass = {}

local oo = require "loop.simple"

-- This class will be parent of all classes used for rewriting Python modules.
-- Probably I'd add MRO here later.
local Base = oo.class({})

baseclass.Base = Base

function Base.__init(cls, ...)
    local self = {}
    oo.rawnew(cls, self)
    cls.__create(self, ...)
    return self
end

-- All classes inherited from Base will always have __create method.
function Base.__create(self, ...)
end

-- Shortcut for creating a new class that defaults parent to Base.
function baseclass.class(class_table, parent)
    return oo.class(class_table or {}, parent or baseclass.Base)
end

return baseclass
require 'lunit'
package.path =  ";../?.lua;../?/init.lua;" .. package.path
module( "test_baseclass", package.seeall, lunit.testcase )

local oo = require 'loop.simple'
local baseclass = require('logging.baseclass')

function test_simple_create()
    local cls = baseclass.class()
    function cls:__create()
        self.x = 1
    end
    local obj = cls()
    assert_equal(1, obj.x)
end

function test_method_from_constructor()
    local cls = baseclass.class()
    function cls:__create()
        self.x = 1
    end
    function cls:add_x(val)
        self.x = self.x + val
    end
    local obj = cls()
    obj:add_x(42)
    assert_equal(43, obj.x)
end

function test_parent_implicitly_not_called()
    local parent = baseclass.class()
    function parent:__create()
        self.parent_called = true
    end
    local child = baseclass.class({}, parent)
    function child:__create()
        self.child_called = true
    end
    local obj = child()
    assert_true(obj.child_called)
    assert_nil(obj.parent_called)
end

function test_parent_explicit_call()
    local parent = baseclass.class()
    function parent:__create(x)
        self.parent_called = true
        self.x = x
    end
    local child = baseclass.class({}, parent)
    function child:__create(x, y)
        self.y = y
        self.child_called = true
        assert_nil(self.parent_called)
        oo.superclass(child).__create(self, x)
        assert_true(self.parent_called)
    end
    local obj = child('x val', 'y val')
    assert_true(obj.child_called)
    assert_equal('x val', obj.x)
    assert_equal('y val', obj.y)
end

function test_child_with_no_ctor()
    local parent = baseclass.class()
    function parent:__create(x)
        self.parent_called = true
        self.x = x
    end
    local child = baseclass.class({}, parent)
    function child:add_x(val)
        self.x = self.x .. val
    end
    local obj = child('lua')
    assert_equal('lua', obj.x)
    assert_true(obj.parent_called)

    obj:add_x(' is awesome')
    assert_equal('lua is awesome', obj.x)
end

function test_long_inheritance()
    local A = baseclass.class()
    function A:__create()
        self.x = 'A'
    end
    local B = baseclass.class({}, A)

    local C = baseclass.class({}, B)
    function C:__create()
        oo.superclass(C).__create(self)
        self.x = self.x .. 'B'
    end
    local D = baseclass.class({}, C)

    local E = baseclass.class({}, D)
    function E:__create()
        oo.superclass(E).__create(self)
        self.x = self.x .. 'E'
    end

    local obj = E()
    assert_equal('ABE', obj.x)

    local obj2 = E()
    assert_equal('ABE', obj2.x)

end
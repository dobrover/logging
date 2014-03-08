require 'lunit'
package.path =  ";../?.lua;../?/init.lua;" .. package.path

local helpers = require('logging.helpers')

module( "test_helpers_general", package.seeall, lunit.testcase )

function test_interpolate()
    local f = helpers.interpolate
    assert_equal("test", f("test"))
    assert_equal("test", f("test", {}))
    assert_equal("test a b", f("test %s %s", {'a', 'b'}))
    assert_equal("test % %%", f("test %% %%%%"))
    assert_equal("test % %x%", f("test %% %%%s%%", {'x'}))
    -- Keyword arguments
    assert_equal("test x y", f("test %(a)s %(b)s", {a='x', b='y'}))
    assert_equal("test %(a)s", f("test %%(a)s"))
    assert_equal("test %(a)s !x!", f("test %%(a)s !%(a)s!", {a='x'}))
    assert_equal("test %(a)s !&!", f("test %%(a)s !%(a)s!", {a='&'}))
    assert_equal("test %(a)s !&&!", f("test %%(a)s !%(a)s!", {a='&&'}))
    assert_equal('test %%42', f("test %%%%%(a)d", {a=42}))
    assert_equal('y x', f("%(b)s %(a)s", {a='x', b='y'}))
    -- If we forget to add format type, it won't be replaced
    assert_equal('%(a) x', f('%(a) %(b)s', {a='y', b='x'}))
    -- Mixed format not allowed
    assert_error('Interpolate should not allow mixed keys!',
                 function () f( '%(a) %(b)', {1, a='b'}) end)
end

function test_time()
    assert_equal('number', type(helpers.time()))
end

module( "test_helpers_list", package.seeall, lunit.testcase )

function test_append()
    list = helpers.list()
    list:append(1)
    list:append(2)
    list:append(3)
    assert_equal('[1, 2, 3]', tostring(list))
end

function test_remove()
    list = helpers.list({1, 2, 3})
    list:remove(2)
    assert_equal('[1, 3]', tostring(list))
    assert_error('Exceptions should be raised if deleting unexistent element', function () list:remove(42) end)
    list:remove(1)
    assert_equal('[3]', tostring(list))
    list:remove(3)
    assert_equal('[]', tostring(list))
    assert_error('Should not be able to remove from empty list', function () list:remove(42) end)
    list:append(42)
    assert_error('Should not be able to delete nil', function() list:remove(nil) end)
    assert_equal('[42]', tostring(list))
    -- Multiple remove
    list = helpers.list{1,2,2,3,3,3,4,4,4,4,5,5,5,5,5}
    for i = 1, 5 do
        for j = 1, i do
            list:remove(i)
        end
    end
    assert_equal('[]', tostring(list))
end

function test_remove_at()
    list = helpers.list({1, 2, 3, 4, 5, 6, 7, 8, 9, 10})
    for i = 1, 5 do
        list:remove_at(i)
    end
    assert_equal('[2, 4, 6, 8, 10]', tostring(list))
    list = helpers.list{1,2,3}
    assert_error('Remove at wrong position', function () list:remove_at(4) end)
    assert_error('Remove at negative position', function () list:remove_at(-1) end)
end

function test_insert()
    list = helpers.list()
    list:insert(1)
    assert_equal('[1]', tostring(list))
    list:insert(2, 2)
    assert_equal('[1, 2]', tostring(list))
    list:insert(2, 42)
    assert_equal('[1, 42, 2]', tostring(list))
    list:insert(43)
    assert_equal('[43, 1, 42, 2]', tostring(list))
    list:insert(5, 46)
    assert_equal('[43, 1, 42, 2, 46]', tostring(list))


    list_before = tostring(list)
    length_before = #list
    for i = 1, #list + 1 do
        list:insert(i, i*100)
        assert_equal(i*100, list[i])
        assert_equal(length_before + 1, #list)
        list:remove_at(i)
    end
    assert_equal(list_before, tostring(list))

    list = helpers.list({1, 2, 3})
    assert_error('Insert at pos > #list + 1', function () list:insert(5, 47) end)
    assert_error('Insert at pos < 1', function () list:insert(0, 47) end)
end

function test_count()
    list = helpers.list{1, 2, 2, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 5}
    for i = 1,5 do
        assert_equal(i, list:count(i))
    end
    assert_equal(0, list:count(42))
end
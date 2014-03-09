require 'lunit'
package.path =  ";../?.lua;../?/init.lua;" .. package.path

-- Returns a copy of table
local function copy(tbl)
    local new_table = {}
    for k, v in pairs(tbl) do
        new_table[k] = v
    end
    return new_table
end

local logging = require 'logging'
local common = require 'common'
local stringio = require 'pl.stringio'

module( "test_logging_general", package.seeall, lunit.testcase )

local saved_levels = nil

function setup()
    saved_levels = logging.levels
    logging.levels = copy(saved_levels)
end

function teardown()
    logging.levels = saved_levels
end

function test_addLevelName()
    assert_equal('Level 42', logging.getLevelName(42))
    logging.addLevelName(42, 'Answer to everything')
    assert_equal('Answer to everything', logging.getLevelName(42))
end

function test_checkLevel()
    assert_equal(43, logging._checkLevel(43))
    assert_equal(50, logging._checkLevel('CRITICAL'))
    assert_equal(nil, logging._checkLevel({}))
end

module( "test_LogRecord", package.seeall, lunit.testcase )

local creation_args = {name='root', level=30, pathname='me.lua', lineno=42, msg='Hello! %(world)s', args=nil, exc_info=nil}

function test_creation()
    local lr = logging.LogRecord
    local args = copy(creation_args)
    args.args = {world='Earth'}
    local r = lr(args)
    assert_equal('Earth', r.args.world)

    args = copy(creation_args)
    args.args = 'test'
    r = lr(args)
    assert_equal('test', r.args[1])

    local obj = copy(r)
    r = lr({obj=obj})
    assert_equal('test', r.args[1])
    assert_equal('me.lua', r.pathname)
end

function test_getMessage()
    local args = copy(creation_args)
    args.args = {world='Earth'}
    r = logging.LogRecord(args)
    assert_equal('Hello! Earth', r:getMessage())

    args.msg = 'test'
    args.args = nil
    r = logging.LogRecord(args)
    assert_equal('test', r:getMessage())

    args.msg = 'test %d'
    args.args = 42
    r = logging.LogRecord(args)
    assert_equal('test 42', r:getMessage())
end

module( "test_Formatter", package.seeall, lunit.testcase )

function test_format()
    local args = copy(creation_args)
    args.msg = 'major %(name)s'
    args.args = {name='Tom'}
    r = logging.LogRecord(args)
    fmt = logging.Formatter()
    assert_equal('major Tom', fmt:format(r))

    fmt = logging.Formatter('%(message)s %(levelname)s %(lineno)d')
    assert_equal('major Tom WARNING 42', fmt:format(r))

    fmt = logging.Formatter('%(asctime)s %(message)s')
    s = fmt:format(r)
    assert_true(s:find(':') ~= nil)
    assert_true(s:find('major Tom') ~= nil)
    assert_true(s:find('-') ~= nil)

    fmt = logging.Formatter('%(asctime)s', '%Y')
    s = fmt:format(r)
    -- Probably add some mocks?
    assert_equal(os.date('%Y'), s) --don't launch me on New Year eve. 
end

module( "test_BufferingFormatter", package.seeall, lunit.testcase )

local function get_recs()
    local args = copy(creation_args)
    r1 = logging.LogRecord(args)
    r1.msg = 'Hello, %(world)s'
    r1.args = {world='earth'}
    r2 = logging.LogRecord(args)
    r2.msg = 'How are you, %(major)s'
    r2.args = {major='tom'}
    r3 = logging.LogRecord(args)
    r3.msg = 'Bye, %(major)s, bye %(world)s'
    r3.args = {major='tom', world='earth'}
    return {r1, r2, r3}
end


function test_buffering_formatter()
    local args = copy(creation_args)
    bf = logging.BufferingFormatter()
    assert_equal('Hello, earthHow are you, tomBye, tom, bye earth', bf:format(get_recs()))
end

function test_buffering_formatter_inherited()
    child = common.baseclass.class({}, logging.BufferingFormatter)
    function child:formatHeader(recs) return ("Begin %d"):format(#recs) end
    function child:formatFooter(recs) return ("End %d"):format(#recs) end
    bf = child()
    assert_equal('Begin 3Hello, earthHow are you, tomBye, tom, bye earthEnd 3', bf:format(get_recs()))
end

function test_custom_formatter()
    fmt = logging.Formatter('%(levelname)s %(message)s|')
    bf = logging.BufferingFormatter(fmt)
    assert_equal('WARNING Hello, earth|WARNING How are you, tom|WARNING Bye, tom, bye earth|', bf:format(get_recs()))
end

module( "test_Filter", package.seeall, lunit.testcase )

function test_filter()
    local args = copy(creation_args)
    r = logging.LogRecord(args)
    f1 = logging.Filter('')
    f2 = logging.Filter('a')
    f3 = logging.Filter('a.bb')
    f4 = logging.Filter('a.c')
    r.name = 'lol'
    assert_true(f1:filter(r))
    assert_false(f2:filter(r))
    r.name = 'a'
    assert_true(f2:filter(r))
    assert_false(f3:filter(r))
    r.name = 'a.bbb'
    assert_false(f3:filter(r))
    r.name = 'a.bb.b'
    assert_true(f3:filter(r))
    r.name = 'a.c.bb'
    assert_true(f4:filter(r))
    r.name = 'a.c'
    assert_true(f4:filter(r))
end

module( "test_Filterer", package.seeall, lunit.testcase)

function test_filterer()
    f = logging.Filterer()
    a = logging.Filter('a')
    ac = logging.Filter('a.c')
    ad = logging.Filter('a.d')
    f:addFilter(a)
    f:addFilter(ac)
    f:addFilter(ad)
    r = logging.LogRecord(copy(creation_args))
    r.name = 'a'
    assert_false(f:filter(r))
    r.name = 'a.c'
    assert_false(f:filter(r))
    f:removeFilter(ad)
    assert_true(f:filter(r))
    f:addFilter(ad)
    assert_false(f:filter(r))
    r.name = 'a.d.d'
    f:removeFilter(ac)
    assert_true(f:filter(r))
    r.name = 'root'
    f:removeFilter(a)
    f:removeFilter(ac)
    f:removeFilter(ad)
    assert_true(f:filter(r))
end

module( "test_Handler", package.seeall, lunit.testcase)

function test_handler_create()
    hc = logging.Handler
    h = hc()
    local found = false
    for i,v in ipairs(logging._handlersShutdownList) do
        if v.value == h then
            found = true
        end
    end
    assert_true(found, "Handler not in handler shutdown list!")
    h = nil
    collectgarbage()
    assert_nil(common.table.index(logging._handlersShutdownList, h))
    h = hc()
    h:setName('a')
    assert_equal(h, logging._handlers['a'])
    h = h
    h = nil
    collectgarbage()
    local c = 0
    for k,v in pairs(logging._handlers) do
        c = c + 1
    end
    assert_equal(0, c)
end

function test_handler_functions()
    h = logging.Handler()
    h:setLevel(40)
    assert_equal(40, h.level)

    r = logging.LogRecord(copy(creation_args))
    r.msg = 'test %s'
    r.args = {1}
    assert_equal('test 1', h:format(r))

    h:setFormatter(logging.Formatter('%(levelname)s %(message)s'))
    assert_equal('WARNING test 1', h:format(r))

    h:setFormatter(nil)
    assert_equal('test 1', h:format(r))

    assert_error('emit should raise notimplementederror', function () h:emit(r) end)

    child = common.baseclass.class({}, logging.Handler)
    local emitted = {}
    function child:emit(record)
        table.insert(emitted, record)
    end
    h = child()
    h:handle(r)
    assert_equal(r, emitted[1])

    h:addFilter(logging.Filter('a.c'))
    args = copy(creation_args)
    r2 = logging.LogRecord(copy(creation_args))
    r2.name = 'a.b'
    h:handle(r2)
    assert_equal(1, #emitted)

    r2.name = 'a.c'
    h:handle(r2)
    assert_equal(r2, emitted[2])

    h:setName('b')
    h:close()

    assert_nil(logging._handlers['b'])

end

module( "test_streamhandler", package.seeall, lunit.testcase)

function test_streamhandler_simple()
    h = logging.StreamHandler()
    assert_equal(io.stderr, h.stream)

    f = stringio.create()
    h = logging.StreamHandler(f)
    r = logging.LogRecord(creation_args)
    r.msg = 'hello %(world)s'
    r.args = {world='earth'}
    h:handle(r)
    r.msg = 'bye %(major)s'
    r.args = {major='tom'}
    h:handle(r)
    assert_equal('hello earth\nbye tom\n', f:value())


    h:flush()
    called = false
    f.flush = function(self)
        assert_equal(self, f)
        called = true
    end
    h:flush()
    assert_true(called)
    -- Check that parent constructor is called
    assert_equal(0, h.level)
end

module( "test_filehandler", package.seeall, lunit.testcase)

local fname = nil
function setup()
    random_name = {}
    for i = 1,32 do
        table.insert(random_name, string.char(math.random(65,90)))
    end
    random_name = table.concat(random_name)
    fname = '/tmp/'..random_name
end

function teardown()
    os.remove(fname)
end

function test_filehandler_simple()
    h = logging.FileHandler(fname)
    r = logging.LogRecord(creation_args)
    r.msg = 'hello %(world)s'
    r.args = {world='earth'}
    h:handle(r)
    r.msg = 'bye %(major)s'
    r.args = {major='tom'}
    h:handle(r)
    h:flush()
    resf = io.open(fname, 'rb'):read('*all')
    assert_equal('hello earth\nbye tom\n', resf)
    os.remove(fname)
    h:close()

    h = logging.FileHandler(fname, 'wb', true)
    r = logging.LogRecord(creation_args)
    r.msg = 'hello! %(world)s'
    r.args = {world='earth'}
    h:handle(r)
    r.msg = 'bye! %(major)s'
    r.args = {major='tom'}
    h:handle(r)
    h:close()
    resf = io.open(fname, 'rb'):read('*all')
    assert_equal('hello! earth\nbye! tom\n', resf)
    os.remove(fname)
end



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
local oo = require 'loop.simple'
local kw = common.table.kw
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

local creation_args = {name='root', level=30, pathname='me.lua', lineno=42, msg='Hello! %s', args={n=0}, exc_info=nil}

function test_creation()
    local lr = logging.LogRecord
    local args = copy(creation_args)
    args.args = {'Earth', n=1}
    local r = lr(args)
    assert_equal('Earth', r.args[1])

    local obj = copy(r)
    r = lr({obj=obj})
    assert_equal('Earth', r.args[1])
    assert_equal('me.lua', r.pathname)

    args.msg = nil
    assert_error(function () lr(args) end)
end

function test_getMessage()
    local args = copy(creation_args)
    args.args = {'Earth', n=1}
    r = logging.LogRecord(args)
    assert_equal('Hello! Earth', r:getMessage())

    args.msg = 'test %s %s %s'
    args.args = {[1]='a', [2]=nil, [3]='b', n=3}
    r = logging.LogRecord(args)
    assert_equal('test a nil b', r:getMessage())

    args.msg = 'test %d'
    args.args = {42, n=1}
    r = logging.LogRecord(args)
    assert_equal('test 42', r:getMessage())
end

module( "test_Formatter", package.seeall, lunit.testcase )

function test_format()
    local args = copy(creation_args)
    args.msg = 'major %s'
    args.args = {'Tom', n=1}
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
    r1.msg = 'Hello, %s'
    r1.args = {'earth', n=1}
    r2 = logging.LogRecord(args)
    r2.msg = 'How are you, %s'
    r2.args = {'tom', n=1}
    r3 = logging.LogRecord(args)
    r3.msg = 'Bye, %s, bye %s'
    r3.args = {'tom', 'earth', n=2}
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
    r.args = {1, n=1}
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

function test_handler_formatter()
    assert_error(function() 
        h = logging.Handler()
        h:setFormatter("String")
    end)
end

module( "test_streamhandler", package.seeall, lunit.testcase)

function test_streamhandler_simple()
    h = logging.StreamHandler()
    assert_equal(io.stderr, h.stream)

    f = stringio.create()
    h = logging.StreamHandler(f)
    r = logging.LogRecord(creation_args)
    r.msg = 'hello %s'
    r.args = {'earth', n=1}
    h:handle(r)
    r.msg = 'bye %s'
    r.args = {'tom', n=1}
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

-- Tests issue #1
-- https://github.com/dobrover/logging/issues/1
function test_streamhandler_flush_after_emit()
    local stream = stringio.create()
    local handler = logging.StreamHandler(stream)
    local r = logging.LogRecord(creation_args)
    local flush_called = 0
    stream.flush = function(self)
        flush_called = flush_called + 1
    end
    for i = 1,3 do
        handler:handle(r)
        -- Flush should be called after each handle.
        assert_equal(i, flush_called)
    end
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
    r.msg = 'hello %s'
    r.args = {'earth', n=1}
    h:handle(r)
    r.msg = 'bye %s'
    r.args = {'tom', n=1}
    h:handle(r)
    h:flush()
    resf = io.open(fname, 'rb'):read('*all')
    assert_equal('hello earth\nbye tom\n', resf)
    os.remove(fname)
    h:close()

    h = logging.FileHandler(fname, 'wb', true)
    r = logging.LogRecord(creation_args)
    r.msg = 'hello! %s'
    r.args = {'earth', n=1}
    h:handle(r)
    r.msg = 'bye! %s'
    r.args = {'tom', n=1}
    h:handle(r)
    h:close()
    resf = io.open(fname, 'rb'):read('*all')
    assert_equal('hello! earth\nbye! tom\n', resf)
    os.remove(fname)
end

module( "test_logger_tree", package.seeall, lunit.testcase)

function test_check_logger_class()
    assert_equal(logging.Logger, logging._checkLoggerClass(logging.Logger))
    anothercls = common.baseclass.class()
    assert_error(function () logging._checkLoggerClass(anothercls) end)
    childcls = common.baseclass.class({}, logging.Logger)
    assert_equal(childcls, logging._checkLoggerClass(childcls))

    logging.setLoggerClass(childcls)
    assert_equal(childcls, logging.getLoggerClass())

    assert_error(function () logging.setLoggerClass(anothercls) end)
    logging.setLoggerClass(logging.Logger)
end

function test_manager()
    root = logging.RootLogger(0)
    manager = logging.Manager(root)
    a = manager:getLogger('a')
    ab = manager:getLogger('a.b')
    ac = manager:getLogger('a.c')
    assert_equal(a, ab.parent)
    assert_equal(a, ac.parent)
    assert_equal(root, a.parent)
    assert_true(oo.instanceof(a, logging.Logger))
end

function test_manager_setclass()
    manager = logging.Manager(logging.RootLogger(0))
    manager.root.manager = manager
    childcls = common.baseclass.class({}, logging.Logger)
    anothercls = common.baseclass.class()
    assert_error(function () manager:setLoggerClass(anothercls) end)
    manager:setLoggerClass(childcls)
    log = manager:getLogger('a.b.c')
    assert_true(oo.instanceof(log, childcls))

end

function test_manager_skip_child()
    root = logging.RootLogger(0)
    manager = logging.Manager(root)
    root.manager = manager
    deep = manager:getLogger('a.b.c.d.e.f')
    shallow = manager:getLogger('a.b.c.d')
    assert_equal(shallow, deep.parent)
    assert_equal(root, shallow.parent)
    between = manager:getLogger('a.b.c.d.e')
    assert_equal(between, deep.parent)
    assert_equal(shallow, between.parent)
    another_branch = manager:getLogger('a.b.c.banana')
    assert_equal(root, another_branch.parent)
    abc = manager:getLogger('a.b.c')
    assert_equal(between, deep.parent)
    assert_equal(shallow, between.parent)
    assert_equal(abc, shallow.parent)
    assert_equal(abc, another_branch.parent)
    assert_equal(abc, manager:getLogger('a.b.c'))
end

module( "test_logger", package.seeall, lunit.testcase)

function test_logger_general()
    root = logging.RootLogger(0)
    manager = logging.Manager(root)
    root.manager = manager
    abc = manager:getLogger('abc')
    abc:setLevel(logging.WARNING)
    assert_equal(logging.WARNING, abc.level)
    abcde = abc:getChild('d.e')
    assert_equal(manager:getLogger('abc.d.e'), abcde)
    assert_equal(manager:getLogger('test.test'), root:getChild('test.test'))

    x = manager:getLogger('x')
    y = manager:getLogger('x.y')
    z = manager:getLogger('x.y.z')
    x:setLevel(10)
    y:setLevel(20)
    z:setLevel(30)
    assert_equal(30, z:getEffectiveLevel())
    z:setLevel(0)
    assert_equal(20, z:getEffectiveLevel())
    y:setLevel(0)
    assert_equal(10, z:getEffectiveLevel())
    assert_equal(10, y:getEffectiveLevel())
    x:setLevel(0)
    assert_equal(0, z:getEffectiveLevel())
    root:setLevel(42)
    assert_equal(42, z:getEffectiveLevel())
    y:setLevel(21)
    assert_equal(21, z:getEffectiveLevel())
    assert_equal(21, y:getEffectiveLevel())

    x:setLevel(10)
    y:setLevel(20)
    z:setLevel(30)
    assert_true(z:isEnabledFor(30))
    assert_true(z:isEnabledFor(31))
    assert_false(z:isEnabledFor(29))
    z:setLevel(0)
    assert_true(z:isEnabledFor(29))
    -- Disable all messages <= 20
    manager.disable = 20
    assert_true(z:isEnabledFor(29))
    manager.disable = 29
    assert_false(z:isEnabledFor(29))
end

function test_logger_callhandlers()
    r1 = logging.LogRecord(creation_args)
    root = logging.RootLogger(0)
    manager = logging.Manager(root)
    root.manager = manager
    abc = manager:getLogger('a.b.c')
    ab = manager:getLogger('a.b')
    a = manager:getLogger('a')
    abc_h1_s = stringio.create()
    abc_h1 = logging.StreamHandler(abc_h1_s)
    abc_h2_s = stringio.create()
    abc_h2 = logging.StreamHandler(abc_h2_s)
    abc:addHandler(abc_h1)
    abc:addHandler(abc_h2)
    a_h_s = stringio.create()
    a_h = logging.StreamHandler(a_h_s)
    a:addHandler(a_h)
    abc_h1:setLevel(40)
    abc_h2:setLevel(50)
    a_h:setLevel(30)
    r1.levelno = 60
    r1.msg = 'msg60'
    abc:handle(r1)
    r1.levelno = 50
    r1.msg = 'msg50'
    abc:handle(r1)
    r1.levelno = 40
    r1.msg = 'msg40'
    abc:handle(r1)
    r1.levelno = 30
    r1.msg = 'msg30'
    abc:handle(r1)
    r1.levelno = 20
    r1.msg = 'msg20'
    abc:handle(r1)

    abc.propagate = false
    r1.levelno = 60
    r1.msg = 'abconly'
    abc:handle(r1)

    abc.propagate = true
    abc.disabled = true
    r1.msg = 'fornobody'
    abc:handle(r1)

    abc.disabled = false
    abc.propagate = false
    abc:removeHandler(abc_h1)
    r1.msg = 'for_h2_s'
    r1.levelno = 60
    abc:handle(r1)

    assert_equal('msg60\nmsg50\nmsg40\nabconly\n', abc_h1_s:value())
    assert_equal('msg60\nmsg50\nabconly\nfor_h2_s\n', abc_h2_s:value())
    assert_equal('msg60\nmsg50\nmsg40\nmsg30\n', a_h_s:value())
end

function test_logger_log()
    root = logging.RootLogger(0)
    manager = logging.Manager(root)
    root.manager = manager
    mylogcls = common.baseclass.class({}, logging.Logger)
    function mylogcls:handle(record)
        self.handled = self.handled or {}
        table.insert(self.handled, record)
    end
    manager:setLoggerClass(mylogcls)
    l = manager:getLogger('logger')
    l:log(20, "hello %s %s %s", "world", nil, "dear!")
    r = l.handled[1]
    assert_equal('hello %s %s %s', r.msg)
    assert_equal('world', r.args[1])
    assert_equal(nil, r.args[2])
    assert_equal('dear!', r.args[3])
    assert_equal(3, r.args.n)
    assert_equal(20, r.levelno)
    assert_error(function () l:log('s', "msg") end)

    l:setLevel(30)
    l:log(20, "msg")
    assert_nil(l.handled[2])

    l:log(30, "msg %s", "world", kw{exc_msg="Error!", exc_tb='tb', extra={x='y'}})
    r = l.handled[2]
    assert_equal("Error!", r.exc_info.exc_msg)
    assert_equal("tb", r.exc_info.exc_tb)
    assert_equal('y', r.x)

    assert_error(function () l:log(30, "msg", kw{extra={asctime=1}}) end)
    assert_error(function () l:log(30, "msg", kw{extra={levelname=1}}) end)
    curline = debug.getinfo(1, "l").currentline
    function testme()
        l:log(30, "msg")
    end
    curline_end = debug.getinfo(1, "l").currentline
    testme()
    r = l.handled[3]

    assert_true(curline < r.lineno)
    assert_true(r.lineno < curline_end)

    assert_not_nil(r.pathname:find('test_logging.lua'))

end

function test_logger_nohandlers()
    root = logging.RootLogger(0)
    manager = logging.Manager(root)
    root.manager = manager

    l = manager:getLogger('newname')
    old_stderr = io.stderr
    io.stderr = stringio.create()
    l:info("hello!")
    assert_equal("No handlers could be found for logger 'newname'\n" ,io.stderr:value())
    io.stderr = old_stderr
end

function test_logger_exception()
    root = logging.RootLogger(0)
    manager = logging.Manager(root)
    root.manager = manager

    l = manager:getLogger('newname')
    l:setLevel(10)
    sio = stringio.create()
    h = logging.StreamHandler(sio)
    l:addHandler(h)
    l:info("test", kw{exc_msg="error", exc_tb="traceback"})
    assert_equal("test\ntraceback\nerror\n",sio:value())
end

module( "test_logger_adapter", package.seeall, lunit.testcase)

function test_logger_adapter_simple()
    root = logging.RootLogger(0)
    manager = logging.Manager(root)
    l = manager:getLogger('hello')
    l:setLevel(20)
    la = logging.LoggerAdapter(l, {hello='world'})
    sio = stringio.create()
    h = logging.StreamHandler(sio)
    l:addHandler(h)
    fmt = logging.Formatter("%(hello)s %(message)s")
    h:setFormatter(fmt)
    la:info("Hello!")
    assert_equal('world Hello!\n', sio:value())

    assert_false(la:isEnabledFor(10))
    assert_true(la:isEnabledFor(20))

    sio = stringio.create()
    l:removeHandler(h)
    h = logging.StreamHandler(sio)
    l:addHandler(h)
    la:exception("Yup")
    assert_not_nil(sio:value():find('Yup\n'))
    assert_not_nil(sio:value():find('test_logging.lua'))
    assert_not_nil(sio:value():find(logging.NO_EXC_MESSAGE))

    sio = stringio.create()
    l:removeHandler(h)
    h = logging.StreamHandler(sio)
    l:addHandler(h)
    la:log(20, "Yuppy")
    assert_equal('Yuppy\n', sio:value())
end

module( "test_logging_misc", package.seeall, lunit.testcase)

function test_logging_misc_simple()
    package.loaded.logging = nil
    local logging = require 'logging'
    local sio = stringio.create()
    logging.basicConfig{stream=sio, format="%(levelname)s %(message)s", level=30}
    logging.info("Test1")
    logging.error("Test2")

   logging.disable(30)
   
   logging.warn("No!")
   logging.error("Yes!")

    assert_equal('ERROR Test2\nERROR Yes!\n', sio:value())

    package.loaded.logging = nil
    local logging = require 'logging'
    local sio = stringio.create()
    logging.basicConfig{stream=sio, format="%(levelname)s %(message)s", level=30}

    logging.log(42, "An answer")

    assert_equal("Level 42 An answer\n", sio:value())
end

function test_logging_shutdown()
    package.loaded.logging = nil
    local logging =require 'logging'
    local execlog = ''
    myhdlr = common.baseclass.class({}, logging.Handler)
    function myhdlr:flush()
        execlog = execlog .. '|' .. self._name .. '.flush()'
    end
    function myhdlr:close()
        execlog = execlog .. '|' .. self._name .. '.close()'
    end
    h1 = myhdlr()
    h1:setName('h1')
    h2 = myhdlr()
    h2:setName('h2')
    -- Emulate shutdown
    logging.shutdown()
    assert_equal('|h2.flush()|h2.close()|h1.flush()|h1.close()', execlog)
end

function test_nullhandler()
    nh = logging.NullHandler()
    root = logging.RootLogger(0)
    manager = logging.Manager(root)
    l = manager:getLogger('hello')
    l:addHandler(nh)
    l:info("Enter the void")
end
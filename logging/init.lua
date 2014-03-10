local logging = {}

local oo = require "loop.simple"
local path = require "pl.path"

local common = require 'common'

--------------------------------------------------------------------------------
-- Level manipulation
--------------------------------------------------------------------------------

logging._startTime = common.time.time()
-- TODO: Move all class declarations to the top.

-- raiseExceptions is used to see if exceptions during handling should be
-- propagated
logging.raiseExceptions = true

logging._srcfile = true

local CRITICAL = 50
local FATAL = CRITICAL
local ERROR = 40
local WARNING = 30
local WARN = WARNING
local INFO = 20
local DEBUG = 10
local NOTSET = 0

logging.CRITICAL = CRITICAL
logging.FATAL = FATAL
logging.ERROR = ERROR
logging.WARNING = WARNING
logging.WARN = WARN
logging.INFO = INFO
logging.DEBUG = DEBUG
logging.NOTSET = NOTSET

logging.levels = {
    CRITICAL = CRITICAL,
    FATAL = CRITICAL,
    ERROR = ERROR,
    WARNING = WARNING,
    WARN = WARNING,
    INFO = INFO,
    DEBUG = DEBUG,
    NOTSET = NOTSET,
    [CRITICAL] = "CRITICAL",
    [ERROR] = "ERROR",
    [WARNING] = "WARNING",
    [INFO] = "INFO",
    [DEBUG] = "DEBUG",
    [NOTSET] = "NOTSET",
}

function logging.getLevelName(level)
    if logging.levels[level] ~= nil then
        return logging.levels[level]
    else
        return ("Level %d"):format(level)
    end
end

function logging.addLevelName(level, levelName)
    logging.levels[level] = levelName
    logging.levels[levelName] = level
end


function logging._checkLevel(level_or_name)
    if type(level_or_name) == 'number' then
        return level_or_name
    end
    if type(level_or_name) == 'string' then
        return logging.levels[level_or_name]
    end
    return nil
end

local LogRecord = common.baseclass.class()
logging.LogRecord = LogRecord

local Formatter = common.baseclass.class()
logging.Formatter = Formatter

local BufferingFormatter = common.baseclass.class()
logging.BufferingFormatter = BufferingFormatter

local Filter = common.baseclass.class()
logging.Filter = Filter

local Filterer = common.baseclass.class()
logging.Filterer = Filterer

local Handler = common.baseclass.class({}, Filterer)
logging.Handler = Handler

local StreamHandler = common.baseclass.class({}, Handler)
logging.StreamHandler = StreamHandler

local FileHandler = common.baseclass.class({}, StreamHandler)
logging.FileHandler = FileHandler

local PlaceHolder = common.baseclass.class()
logging.PlaceHolder = PlaceHolder

local Manager = common.baseclass.class()
logging.Manager = Manager

local Logger = common.baseclass.class({}, Filterer)
logging.Logger = Logger

local RootLogger = common.baseclass.class({}, Logger)
logging.RootLogger = RootLogger

local LoggerAdapter = common.baseclass.class()
logging.LoggerAdapter = LoggerAdapter

logging._loggerClass = Logger

--------------------------------------------------------------------------------
-- LogRecord
--------------------------------------------------------------------------------

function LogRecord:__create(args)
    -- If we have to restore from table, just set it as object
    if args.obj ~= nil then
        for k, v in pairs(args.obj) do
            self[k] = v
        end
        return
    end
    local ct = common.time.time()
    self.name = args.name
    self.levelno = args.level
    self.levelname = logging.getLevelName(self.levelno)
    self.pathname = args.pathname
    self.lineno = args.lineno
    self.msg = args.msg
    self.args = args.args
    -- args are either nil or a single element, or a table.
    if self.args ~= nil and type(self.args) ~= 'table' then
        self.args = {self.args}
    end
    self.exc_info = args.exc_info
    self.created = ct
    self.msecs = (ct - math.floor(ct)) * 1000
    self.relative_created = ct - logging._startTime
    self.funcName = args.func
end

function LogRecord:__tostring()
    return ('<LogRecord: %s, %s, %s, %s, "%s">'):format(
        self.name, self.levelno, self.pathname, self.lineno, self.msg
    )
end

function LogRecord:getMessage()
    if self.args then

        return self.msg:format(unpack(self.args))
    else
        return self.msg
    end
end

--------------------------------------------------------------------------------
-- Formatter
--------------------------------------------------------------------------------

function Formatter:__create(fmt, datefmt)
    self._fmt = fmt
    if not self._fmt then
        self._fmt = '%(message)s'
    end
    self.datefmt = datefmt
end

function Formatter:formatTime(record, datefmt)
    -- TODO: localtime ?
    if datefmt then
        return os.date(datefmt, record.created)
    else
        local s = os.date("%Y-%m-%d %H:%M:%S", record.created)
        return ("%s,%03d"):format(s, record.msecs)
    end
end

function Formatter:usesTime()
    return self._fmt:find("%%%(asctime%)") ~= nil
end

function Formatter:formatException(ei)
    local r = {}
    if ei.exc_tb then
        table.insert(r, ei.exc_tb)
    end
    if ei.exc_msg then
        table.insert(r, ei.exc_msg)
    end
    return table.concat(r, '\n')
end

function Formatter:format(record)
    record.message = record:getMessage()
    if self:usesTime() then
        record.asctime = self:formatTime(record, self.datefmt)
    end
    local s = common.string.interpolate(self._fmt, record)
    if record.exc_info then
        if not record.exc_text then
            record.exc_text = self:formatException(record.exc_info)
        end
    end
    if record.exc_text then
        if record.exc_text:len() > 0 and record.exc_text:sub(-1, -1) ~= '\n' then
            s = s .. '\n'
        end
        s = s .. record.exc_text
    end
    return s
end

logging._defaultFormatter = logging.Formatter()

--------------------------------------------------------------------------------
-- BufferingFormatter
--------------------------------------------------------------------------------

function BufferingFormatter:__create(linefmt)
    self.linefmt = linefmt
    if not self.linefmt then
        self.linefmt = logging._defaultFormatter
    end
end

function BufferingFormatter:formatHeader(records)
    return ""
end

function BufferingFormatter:formatFooter(records)
    return ""
end

function BufferingFormatter:format(records)
    rv = {}
    if #records > 0 then
        table.insert(rv, self:formatHeader(records))
        for i, record in ipairs(records) do
            table.insert(rv, self.linefmt:format(record))
        end
        table.insert(rv, self:formatFooter(records))
    end
    return table.concat(rv)
end

--------------------------------------------------------------------------------
-- Filter
--------------------------------------------------------------------------------

function Filter:__create(name)
    self.name = name or ''
end

function Filter:filter(record)
    if self.name:len() == 0 or self.name == record.name then
        return true
    end
    if record.name:sub(1, self.name:len()) ~= self.name then
        return false
    end
    return record.name:sub(self.name:len() + 1, self.name:len() + 1) == '.'
end

--------------------------------------------------------------------------------
-- Filterer
--------------------------------------------------------------------------------

function Filterer:__create()
    self.filters = {}
end

function Filterer:addFilter(filter)
    if not common.table.index(self.filters, filter) then
        table.insert(self.filters, filter)
    end
end

function Filterer:removeFilter(filter_to_remove)
    local i = common.table.index(self.filters, filter_to_remove)
    if i then
        table.remove(self.filters, i)
    end
end

function Filterer:filter(record)
    for i, filter in ipairs(self.filters) do
        if not filter:filter(record) then
            return false
        end
    end
    return true
end

--------------------------------------------------------------------------------
-- Keep weak refernces to handlers in order to be able to name/shutdown them
--------------------------------------------------------------------------------

-- Weak table with weak values (v for values, k for keys)
logging._handlers = setmetatable({}, {__mode="v"})
logging._handlersShutdownList = setmetatable({}, {__mode="v"})

local function weakref(value)
    local tbl = setmetatable({}, {__mode="v"})
    tbl.value = value
    return tbl
end

function logging._addHandlerRef(handler)
    table.insert(logging._handlersShutdownList, weakref(handler))
end

function logging._removeHandlerRef(handler)
    local i = common.table.index(logging._handlers, handler)
    if i then
        table.remove(logging._handlersShutdownList, i)
    end
end

--------------------------------------------------------------------------------
-- Handler
--------------------------------------------------------------------------------

function Handler:__create(level)
    oo.superclass(Handler).__create(self)
    self.level = level or NOTSET
    self.level = logging._checkLevel(self.level)
    self._name = nil
    self.formatter = nil
    logging._addHandlerRef(self)
end

function Handler:getName()
    return self._name
end

function Handler:setName(name)
    if self._name ~= nil and logging._handlers[self._name] ~= nil then
        logging._handlers[self._name] = nil
    end
    self._name = name
    if self._name ~= nil then
        logging._handlers[self._name] = self
    end
end

function Handler:setLevel(level)
    self.level = logging._checkLevel(level)
end

function Handler:format(record)
    local fmt = nil
    if self.formatter then
        fmt = self.formatter
    else
        fmt = logging._defaultFormatter
    end
    return fmt:format(record)
end

function Handler:emit(record)
    error("emit must be implemented by subclasses.")
end

function Handler:handle(record)
    local rv = self:filter(record)
    if rv then
        self:emit(record)
    end
    return rv
end

function Handler:setFormatter(formatter)
    self.formatter = formatter
end

function Handler:flush()

end

function Handler:handleError(record, err)
    if logging.raiseExceptions  and io.stderr then
        -- TODO: Implement traceback?
        io.stderr:write(err .. '\n')
        io.stderr:write(('Logged from file %s, line %s\n'):format(
            record.filename, record.lineno)
        )
    end
end

function Handler:close()
    self:setName(nil) -- remove from _handlers list
end

function Handler:__gc()
    logging._removeHandlerRef(self)
    self:close()
end

function StreamHandler:__create(stream)
    oo.superclass(StreamHandler).__create(self)
    self.stream = stream or io.stderr
end

function StreamHandler:flush()
    if self.stream.flush then
        self.stream:flush()
    end
end

function StreamHandler:emit(record)
    -- TODO: Try-finally?  Handlerror?
    local msg = self:format(record)
    self.stream:write(msg .. '\n')

end

function FileHandler:__create(filename, mode, delay)
    self.baseFilename = path.abspath(filename)
    self.mode = mode or 'a'
    self.delay = delay or false
    if delay then
        oo.superclass(FileHandler).__create(self)
        self.stream = nil
    else
        oo.superclass(FileHandler).__create(self, self:_open())
    end
end

function FileHandler:close()
    if self.stream then
        self:flush()
        if self.stream.close then
            self.stream:close()
        end
        oo.superclass(FileHandler).close(self)
        self.stream = nil
    end
end

function FileHandler:_open()
    local f, err = io.open(self.baseFilename, self.mode)
    if not f then
        -- TODO: What to do here?
        error(err)
    end
    return f
end

function FileHandler:emit(record)
    if not self.stream then
        self.stream = self:_open()
    end
    oo.superclass(FileHandler).emit(self, record)
end


function PlaceHolder:__create(alogger)
    self.loggerMap = {}
    self.loggerMap[alogger] = true
end

function PlaceHolder:append(alogger)
    if not self.loggerMap[alogger] then
        self.loggerMap[alogger] = true
    end
end

function logging._checkLoggerClass(klass)
    if klass ~= logging.Logger then
        if not oo.subclassof(klass, logging.Logger) then
            error("Logger not derived from logging.Logger: " .. klass)
        end
    end
    return klass
end

function logging.setLoggerClass(klass)
    logging._loggerClass = logging._checkLoggerClass(klass)            
end

function logging.getLoggerClass()
    return logging._loggerClass
end

--------------------------------------------------------------------------------
-- Manager
--------------------------------------------------------------------------------

function Manager:__create(rootnode)
    self.root = rootnode
    self.root.root = self.root
    self.disable = 0
    self.emittedNoHandlerWarning = false
    self.loggerDict = {}
    self.loggerClass = nil
end

function Manager:getLogger(name)
    local rv = nil
    if type(name) ~= 'string' then
        error('A logger name must be string')
    end
    local existing_logger = self.loggerDict[name]
    if existing_logger then
        rv = existing_logger
        if oo.instanceof(rv, logging.PlaceHolder) then
            local ph = rv
            rv = (self.loggerClass or logging._loggerClass)(name)
            rv.manager = self
            self.loggerDict[name] = rv
            self:_fixupChildren(ph, rv)
            self:_fixupParents(rv)
        end
    else
        rv = (self.loggerClass or logging._loggerClass)(name)
        rv.manager = self
        self.loggerDict[name] = rv
        self:_fixupParents(rv)
    end
    return rv
end

function Manager:setLoggerClass(klass)
    self.loggerClass = logging._checkLoggerClass(klass)
end

function Manager:_fixupParents(alogger)
    local name = alogger.name
    local name_len = name:len()
    local rv = nil
    for i = name_len, 1, -1 do
        if rv then
            break
        end
        if name:sub(i,i) == '.' then
            local logger_name = name:sub(1, i - 1)
            if not self.loggerDict[logger_name] then
                self.loggerDict[logger_name] = logging.PlaceHolder(alogger)
            else
                local obj = self.loggerDict[logger_name]
                if oo.instanceof(obj, logging.Logger) then
                    rv = obj
                else
                    assert(oo.instanceof(obj, logging.PlaceHolder))
                    obj:append(alogger)
                end
            end
        end
    end
    if not rv then
        rv = self.root
    end
    alogger.parent = rv
end


function Manager:_fixupChildren(ph, alogger)
    local name = alogger.name
    local namelen = name:len()
    for c, v in pairs(ph.loggerMap) do
        -- If childs parent is below, ignore it.
        if c.parent.name:sub(1, namelen) ~= name then
            -- for all c c.parent will be equal
            alogger.parent = c.parent
            c.parent = alogger
        end
    end
end

--------------------------------------------------------------------------------
-- Logger
--------------------------------------------------------------------------------

function Logger:__create(name, level)
    oo.superclass(Logger).__create(self)
    self.name = name
    self.level = logging._checkLevel(level or NOTSET)
    self.parent = nil
    self.propagate = true
    self.handlers = {}
    self.disabled = false    
end

function Logger:setLevel(level)
    self.level = logging._checkLevel(level)
end

-- info, debug, error, etc, functions are defined below
-- in a loop
function Logger:exception(args)
    args.exc_info = true
    self:error(args)
end

function Logger:log(level, args)
    if type(level) ~= 'number' then
        if logging.raiseExceptions then
            error("level must be an integer")
        else
            return
        end
    end
    if self:isEnabledFor(level) then
        self:_log(level, args)
    end
end

function Logger:findCaller()
    -- TODO: Investigate why can't get fname.
    local current_file = debug.getinfo(1, "S").source
    local info = nil
    if current_file then
        local i = 2
        while true do
            info = debug.getinfo(i, "nSflu")
            if info.source ~= current_file then
                local fname = info.name
                local lineno = info.currentline
                local pathname = info.source
                return pathname, lineno, fname
            end

            i = i + 1
        end
    end
    return "(unknown file)", 0, "(unknown function)"
end

function Logger:makeRecord(name, level, fn, lno, msg, args, exc_info, func, extra)
    local rv = LogRecord({
        name=name, level=level, pathname=fn,
        lineno=lno, msg=msg, args=args, exc_info=exc_info,
        func=func
    })
    if extra then
        for k, v in pairs(extra) do
            if k == 'message' or k == 'asctime' or rv[k] then
                error(("Attempt to overwrite '%s' in LogRecord"):format(k))
            end
            rv[k] = v    
        end
    end
    return rv
end

function Logger:_log(level, args)
    local fn, lno, func = nil, nil, nil
    if logging._srcfile then
        -- TODO: Handle exception?
        fn, lno, func = self:findCaller()
    else
        fn, lno, func = "(unknown file)", 0, "(unknown function)"
    end
    exc_info = {exc_msg='', exc_tb=''}
    if args.exc_msg then
        exc_info.exc_msg = args.exc_msg
    end
    if args.exc_tb then
        exc_info.exc_tb = args.exc_tb
    end

    args.exc_info = exc_info

    local msg = args[1]
    local actual_args = {}
    for i, v in ipairs(args) do
        if i ~= 1 then
            table.insert(actual_args, v)
        end
    end
    local exc_info = args.exc_info
    local extra = args.extra
    local record = self:makeRecord(self.name, level, fn, lno, msg, actual_args, exc_info, func, extra)
    self:handle(record)
end

function Logger:handle(record)
    if not self.disabled and self:filter(record) then
        self:callHandlers(record)
    end
end

function Logger:addHandler(hdlr)
    if not hdlr then
        error("Handler cannot be nil!")
    end
    if not common.table.index(self.handlers, hdlr) then
        table.insert(self.handlers, hdlr)
    end
end

function Logger:removeHandler(hdlr)
    if not hdlr then
        error("Handler cannot be nil!")
    end
    local i = common.table.index(self.handlers, hdlr)
    if not i then
        error("Trying to remove handler not in handlers list!")
    end
    if i then
        table.remove(self.handlers, i)
    end
end

function Logger:callHandlers(record)
    local c = self
    local found_handler = false
    while c do
        for i, hdlr in ipairs(c.handlers) do
            found_handler = true
            if record.levelno >= hdlr.level then
                hdlr:handle(record)
            end
        end
        if not c.propagate then
            c = nil
        else
            c = c.parent
        end
    end
    if (not found_handler and logging.raiseExceptions
        and not self.manager.emittedNoHandlerWarning) then
        io.stderr:write(("No handlers could be found for logger '%s'\n"):format(self.name))
        self.manager.emittedNoHandlerWarning = true
    end
end

function Logger:getEffectiveLevel()
    local logger = self
    while logger do
        if logger.level ~= NOTSET then
            return logger.level
        end
        logger = logger.parent
    end
    return NOTSET
end

function Logger:isEnabledFor(level)
    if self.manager.disable >= level then
        return false
    end
    return level >= self:getEffectiveLevel()
end

function Logger:getChild(suffix)
    if self.root ~= self then
        suffix = self.name .. '.' .. suffix
    end
    return self.manager:getLogger(suffix)
end

--------------------------------------------------------------------------------
-- RootLogger
--------------------------------------------------------------------------------

function RootLogger:__create(level)
    oo.superclass(RootLogger).__create(self, 'root', level)
end

--------------------------------------------------------------------------------
-- LoggerAdapter
--------------------------------------------------------------------------------

function LoggerAdapter:__create(logger, extra)
    self.logger = logger
    self.extra = extra
end

function LoggerAdapter:process(args)
    args.extra = self.extra
end

function LoggerAdapter:log(level, args)
    self:process(args)
    self.logger:log(level, args)
end

function LoggerAdapter:exception(args)
    self:process(args)
    args.exc_info = true
    self.logger.error(args)
end

function LoggerAdapter:isEnabledFor(level)
    return self.logger:isEnabledFor(level)
end

--------------------------------------------------------------------------------
-- Logging functions for module, Logger, LoggerAdapter
--------------------------------------------------------------------------------

for k, v in pairs(logging.levels) do
    if type(k) == 'string' then
        local level, levelname = v, k
        levelname = levelname:lower()
        Logger[levelname] = function (self, args)
            if self:isEnabledFor(level) then
                self:_log(level, args)
            end
        end
        LoggerAdapter[levelname] = function (self, args)
            self:process(args)
            self.logger[levelname](self.logger, args)
        end
        logging[levelname] = function (args)
            -- TODO: Fucntion
        end
    end 
end

--------------------------------------------------------------------------------
-- Default settings
--------------------------------------------------------------------------------

logging.root = RootLogger(WARNING)
Logger.root = logging.root
Logger.manager = Manager(Logger.root)

return common.package(logging, ...)
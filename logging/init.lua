local logging = {}

local oo = require "loop.simple"
local path = require "pl.path"

local common = require 'common'

--------------------------------------------------------------------------------
-- Level manipulation
--------------------------------------------------------------------------------

logging._startTime = common.time.time()


-- raiseExceptions is used to see if exceptions during handling should be
-- propagated
logging.raiseExceptions = true

logging.levels = {
    CRITICAL = 50,
    ERROR = 40,
    WARNING = 30,
    WARN = 30,
    INFO = 20,
    DEBUG = 10,
    NOTSET = 0,
    [50] = "CRITICAL",
    [40] = "ERROR",
    [30] = "WARNING",
    [20] = "INFO",
    [10] = "DEBUG",
    [0] = "NOTSET",
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

--------------------------------------------------------------------------------
-- LogRecord
--------------------------------------------------------------------------------

local LogRecord = common.baseclass.class()
logging.LogRecord = LogRecord

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
        return common.string.interpolate(self.msg, self.args)
    else
        return self.msg
    end
end

--------------------------------------------------------------------------------
-- Formatter
--------------------------------------------------------------------------------

local Formatter = common.baseclass.class()
logging.Formatter = Formatter

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
    error("Not implemented!")
end

function Formatter:format(record)
    record.message = record:getMessage()
    if self:usesTime() then
        record.asctime = self:formatTime(record, self.datefmt)
    end
    local s = common.string.interpolate(self._fmt, record)
    -- TODO: Add exception info here
    return s
end

logging._defaultFormatter = logging.Formatter()

--------------------------------------------------------------------------------
-- BufferingFormatter
--------------------------------------------------------------------------------

local BufferingFormatter = common.baseclass.class()
logging.BufferingFormatter = BufferingFormatter

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

local Filter = common.baseclass.class()
logging.Filter = Filter


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
local Filterer = common.baseclass.class()
logging.Filterer = Filterer

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

local Handler = common.baseclass.class({}, Filterer)
logging.Handler = Handler

function Handler:__create(level)
    oo.superclass(Handler).__create(self)
    self.level = level or logging.levels.NOTSET
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

local StreamHandler = common.baseclass.class({}, Handler)
logging.StreamHandler = StreamHandler

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

local FileHandler = common.baseclass.class({}, StreamHandler)
logging.FileHandler = FileHandler

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

local PlaceHolder = common.baseclass.class()
logging.PlaceHolder = PlaceHolder

function PlaceHolder:__create(alogger)
    self.loggerMap = {}
    self.loggerMap[alogger] = true
end

function PlaceHolder:append(alogger)
    if not self.loggerMap[alogger] then
        self.loggerMap[alogger] = true
    end
end

logging._loggerClass = nil

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

local Manager = common.baseclass.class()
logging.Manager = Manager

function Manager:__create(rootnode)
    self.root = rootnode
    self.disable = false
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
        if oo.instanceof(rv, PlaceHolder) then
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
                self.loggerDict[logger_name] = PlaceHolder(alogger)
            else
                local obj = self.loggerDict[logger_name]
                if oo.instanceof(obj, Logger) then
                    rv = obj
                else
                    assert(oo.instanceof(obj, PlaceHolder))
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

return common.package(logging, ...)
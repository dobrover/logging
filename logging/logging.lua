local logging = {}

local oo = require "loop.simple"

local helpers = require "logging.helpers"
local baseclass = require "logging.baseclass"

--------------------------------------------------------------------------------
-- Level manipulation
--------------------------------------------------------------------------------

logging._startTime = helpers.time()

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

logging.LogRecord = baseclass.class()

function logging.LogRecord:__create(args)
    -- If we have to restore from table, just set it as object
    if args.obj ~= nil then
        for k, v in pairs(args.obj) do
            self[k] = v
        end
        return
    end
    local ct = helpers.time()
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

function logging.LogRecord:__tostring()
    return ('<LogRecord: %s, %s, %s, %s, "%s">'):format(
        self.name, self.levelno, self.pathname, self.lineno, self.msg
    )
end

function logging.LogRecord:getMessage()
    if self.args then
        return helpers.interpolate(self.msg, self.args)
    else
        return self.msg
    end
end

--------------------------------------------------------------------------------
-- Formatter
--------------------------------------------------------------------------------

logging.Formatter = baseclass.class()

function logging.Formatter:__create(fmt, datefmt)
    self._fmt = fmt
    if not self._fmt then
        self._fmt = '%(message)s'
    end
    self.datefmt = datefmt
end

function logging.Formatter:formatTime(record, datefmt)
    -- TODO: localtime ?
    if datefmt then
        return os.date(datefmt, record.created)
    else
        local s = os.date("%Y-%m-%d %H:%M:%S", record.created)
        return ("%s,%03d"):format(s, record.msecs)
    end
end

function logging.Formatter:usesTime()
    return self._fmt:find("%%%(asctime%)") ~= nil
end

function logging.Formatter:formatException(ei)
    error("Not implemented!")
end

function logging.Formatter:format(record)
    record.message = record:getMessage()
    if self:usesTime() then
        record.asctime = self:formatTime(record, self.datefmt)
    end
    local s = helpers.interpolate(self._fmt, record)
    -- TODO: Add exception info here
    return s
end

logging._defaultFormatter = logging.Formatter()

--------------------------------------------------------------------------------
-- BufferingFormatter
--------------------------------------------------------------------------------

logging.BufferingFormatter = baseclass.class()

function logging.BufferingFormatter:__init(linefmt)
    linefmt = linefmt ~= nil and linefmt or logging._defaultFormatter
    return oo.rawnew(self, {linefmt=linefmt})
end

function logging.BufferingFormatter:formatHeader(records)
    return ""
end

function logging.BufferingFormatter:formatFooter(records)
    return ""
end

function logging.BufferingFormatter:format(records)
    rv = {}
    if #records > 0 then
        rv[#rv + 1] = self:formatHeader(records)
        for i, record in ipairs(records) do
            rv[#rv + 1] = self.linefmt:format(record)
        end
        rv[#rv + 1] = self:formatFooter(records)
    end
    return table.concat(rv)
end

--------------------------------------------------------------------------------
-- Filter
--------------------------------------------------------------------------------

logging.Filter = baseclass.class()

function logging.Filter:__create(name)
    self.name = name or ''
end

function logging.Filter:filter(record)
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

logging.Filterer = baseclass.class()

function logging.Filterer:__create()
    self.filters = {}
end
-- create d/s : list
function logging.Filterer:_getFilterPosition(filter_searched)
    for i, filter in ipairs(self.filters) do
        if filter_searched == filter then
            return i
        end
    end
    return -1
end

function logging.Filterer:addFilter(filter)
    -- Ordered add
    if self:_getFilterPosition(filter) == -1 then
        self.filters[#self.filters + 1] = filter
    end
end

function logging.Filterer:removeFilter(filter_to_remove)
    local i = self:_getFilterPosition(filter_to_remove)
    if i == -1 then return end
    local new_filters = {}
    for pos, filter in ipairs(self.filters) do
        if pos ~= i then
            new_filters[#new_filters + 1] = filter
        end
    end
    self.filters = new_filters
end

function logging.Filterer:filter(record)
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
    logging._handlersShutdownList[#logging._handlersShutdownList + 1] = weakref(handler)
end

--------------------------------------------------------------------------------
-- Handler
--------------------------------------------------------------------------------

logging.Handler = baseclass.class({}, logging.Filterer)

function logging.Handler.__create(cls, args, self)
    cls:__parent_create(args, self)
    self.level = args.level ~= nil and args.level or logging.levels.NOTSET
    self._name = nil
    self.level = logging._checkLevel(self.level)
    self.formatter = nil
    logging._addHandlerRef(self)
end

function logging.Handler:getName()
    return self._name
end

function logging.Handler:setName(name)
    if self._name ~= nil and logging._handlers[self._name] ~= nil then
        logging._handlers[self._name] = nil
    end
    self._name = name
    if self._name ~= nil then
        logging._handlers[self._name] = self
    end
end

function logging.Handler:__gc()
    self:setName(nil) -- remove from _handlers list

end

return logging
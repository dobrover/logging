local logging = require 'logging'

logging.basicConfig{
    filename='root.log',
    level=logging.WARN,
    format="%(asctime)s %(levelname)s %(pathname)s %(lineno)s %(name)s %(message)s"
}

local logAhttp = logging.getLogger('A.http')
local logAparse = logging.getLogger('A.parse')

logAparse:setLevel(logging.INFO)
logAhttp:setLevel(logging.DEBUG)

local httphdlr = logging.FileHandler('http.log')
httphdlr:setFormatter(logging.Formatter("%(asctime)s %(name)s %(levelname)s %(message)s"))

local parsehdlr = logging.FileHandler('parse.log')

logAhttp:addHandler(httphdlr)
logAparse:addHandler(parsehdlr)

local screenhdlr = logging.StreamHandler()
screenhdlr:setFormatter(logging.Formatter("%(asctime)s %(name)s %(levelname)s %(message)s", "%H:%M:%S"))
logAhttp:addHandler(screenhdlr)

screenhdlr:setLevel(logging.ERROR)
logging:info{"Started!"}
logAhttp:info{"Downloading web page!"}
logAhttp:info{"Downloaded!"}
logAparse:info{"Parsing web page!"}
logAparse:debug{"Met %s tag, don't worry", "<a>"}
logAparse:warn{"Oops, a minor exception while parsing", exc_msg="Unclosed HTML tag!"}
logAparse:info{"Parsed!"}

logAhttp:info{"Getting another page"}
logAhttp:error{"Could not download page %s", "http://google.com/"}
logging:info{"Finished!"}
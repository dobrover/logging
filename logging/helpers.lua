local helpers = {}

-- Number of non-nil elements in a table.
function helpers.table_length(tbl)
  local count = 0
  for _ in pairs(tbl) do count = count + 1 end
  return count
end

-- Interpolate, see tests. 
function helpers.interpolate(s, tab)
    tab = tab or {}
    local has_number_keys, has_non_number_keys = false, false
    for k, v in pairs(tab) do
        if type(k) == 'number' then
            has_number_keys = true
        else
            has_non_number_keys = true
        end
        if has_number_keys and has_non_number_keys then
            error("Can't mix integer keys with non-integer in string interpolation!")
        end
    end
    if not has_non_number_keys then
        return s:format(unpack(tab))
    else
        -- The idea here is the following.
        -- We use & symbol as escape sequence begin.
        -- If we see '%%' in string, we should replace it with
        -- something that doesn't end with %% and that will be converted
        -- later back.
        -- So, we replace '%%' with '&%%2'. Note that we should also do this to strings by which
        -- %(name)s is replaced.
        -- After we have done all replacements, we just replace back '&%%2' -> '%%' and '&&' to '&'.
        local function escape(str)
            return str:gsub('&', '&&'):gsub('%%%%', '&%%2')
        end
        local function unescape(str)
            return str:gsub('%&%%2', '%%'):gsub('&&', '&')
        end
        s = escape(s)
        s = (s:gsub('%%%((%a%w*)%)([-0-9%.]*[cdeEfgGiouxXsq])',
            function(k, fmt) 
                local string_fmt = fmt:len() and fmt or 's'
                local result = tab[k] and ("%"..string_fmt ):format(tab[k]) or '%('..k..')'..fmt 
                return escape(result)
            end)
        )
        return unescape(s)
    end
end

-- Try getting time in milliseconds
local succeed, socket = pcall(require, "socket")
local get_time = nil
if succeed and socket ~= nil then
    get_time = function ()
        return socket.gettime()
    end
else
    get_time = function()
        return os.time()
    end
end

helpers.time = get_time

----------------------------------------------------------------
-- Python-like list with append O(1), remove O(n),
--  presence test O(n), insert O(n), count O(n)
-- TODO: Probably move to collections repo?
----------------------------------------------------------------


local list_meta = {

    append = function(list, obj)
        list[#list + 1] = obj
    end,

    remove = function(list, obj)
        if not obj then
            error("Trying to delete nil object")
        end
        local to_delete_pos = nil
        for i, v in ipairs(list) do
            if v == obj then
                to_delete_pos = i
                break
            end
        end
        if not to_delete_pos then
            error("No such element: " .. tostring(obj))
        end
        list:remove_at(to_delete_pos)
    end,

    count = function(list, obj)
        local count = 0
        for i, v in ipairs(list) do
            if v == obj then
                count = count + 1
            end
        end
        return count
    end,

    insert = function(list, index, obj)
        if not obj then
            obj = index
            index = 1
        end
        local list_len = #list
        if index < 1 or index > list_len + 1 then
            error(("Cannot insert element %s at position %d"):format(list, index))
        end
        for i = list_len, index, -1 do
            list[i + 1] = list[i]
        end
        list[index] = obj
    end,

    remove_at = function(list, index)
        local list_len = #list
        if index < 1 or index > list_len then
            error(("Cannot remove element at position %d"):format(index))
        end
        for i = index, list_len do
            list[i] = list[i + 1]
        end
        list[list_len] = nil
    end,

    __tostring = function(list)
        local values = table.concat(list, ', ')
        return '[' .. values .. ']'
    end,
}
list_meta.__index = list_meta

function helpers.list(tbl)
    local list = setmetatable({}, list_meta)
    for i, v in ipairs(tbl or {}) do
        list[i] = v
    end
    return list
end

return helpers
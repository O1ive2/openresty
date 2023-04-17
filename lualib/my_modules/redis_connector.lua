local redis = require "resty.redis"
local json = require "cjson"

local function new()
    local red = redis:new()
    red:set_timeout(1000) -- 1 second

    local ok, err = red:connect("127.0.0.1", 6379)
    if not ok then
        ngx.say("failed to connect: ", err)
        return
    end

    return red
end

local function close(red)
    local ok, err = red:set_keepalive(10000, 100)
    if not ok then
        ngx.say("failed to set keepalive: ", err)
        return
    end
end

local function set_value(red, key, value)
    local ok, err = red:set(key, json.encode(value))
    if not ok then
        ngx.say("failed to set value: ", err)
        return
    end
end

local function get_value(red, key)
    local res, err = red:get(key)
    if not res then
        ngx.say("failed to get value: ", err)
        return
    end

    if res == ngx.null then
        return nil
    else
        return json.decode(res)
    end
end

return {
    new = new,
    close = close,
    set_value = set_value,
    get_value = get_value
}

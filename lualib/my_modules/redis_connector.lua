-- redis_connector.lua
local redis = require "resty.redis"
local cjson = require "cjson"

local function connect_to_redis()
    local client = redis:new()
    client:set_timeout(1000)
    local ok, err = client:connect("127.0.0.1", 6379)
    if not ok then
        print("Failed to connect to Redis: ", err)
        return nil
    end
    return client
end

local function is_virtual_url_exists(virtual_url)
    local client = connect_to_redis()
    if not client then return false end
    local exists = client:hexists("url", virtual_url)
    client:close()
    return exists == 1
end

local function get_data_in_url_table(virtual_url)
    local client = connect_to_redis()
    if not client then return false end

    local data, err = client:hget("url", virtual_url)
    if err then
        print("Error getting data: ", err)
        client:close()
        return false
    end
    return cjson.decode(data)
end

local function update_data(virtual_url, updated_fields)
    local client = connect_to_redis()
    if not client then return false end

    local data_json, err = client:hget("url", virtual_url)
    if err then
        print("Error getting data: ", err)
        client:close()
        return false
    end

    local data = cjson.decode(data_json)
    for field, value in pairs(updated_fields) do
        data[field] = value
    end

    local updated_data_json = cjson.encode(data)
    local ok, err = client:hset("url", virtual_url, updated_data_json)
    client:close()
    if not ok then
        print("Error updating data: ", err)
        return false
    end

    return true
end

local function is_url_in_whitelist( url )
    local client = connect_to_redis()
    if not client then return false end

    local is_member, err = client:sismember("whitelist", url)
    if err then
        ngx.log(ngx.ERR, "Failed to check whitelist: ", err)
        return nil, err
    end

    client:close()
    return is_member == 1
end

local function add_to_whitelist(ip_address)
    local client = connect_to_redis()
    if not client then return false end

    local ok, err = client:sadd("whitelist", ip_address)
    client:close()
    if not ok then
        print("Error adding to whitelist: ", err)
        return false
    end

    return true
end

local function remove_from_whitelist(ip_address)
    local client = connect_to_redis()
    if not client then return false end

    local ok, err = client:srem("whitelist", ip_address)
    client:close()
    if not ok then
        print("Error removing from whitelist: ", err)
        return false
    end

    return true
end

local function add_url_user(url, user)
    local client = connect_to_redis()
    if not client then return false end

    local ok, err = client:hset("url_user", url, user)
    client:close()
    if not ok then
        print("Error adding user URL: ", err)
        return false
    end

    return true
end

local function get_user_by_url(url)
    local client = connect_to_redis()
    if not client then return nil end

    local user, err = client:hget("url_user", url)
    client:close()
    if not user then
        print("Error getting user URL: ", err)
        return nil
    end

    return user
end

local function add_user_cookie(user, cookie)
    local client = connect_to_redis()
    if not client then return false end

    local ok, err = client:hset("user_cookie", user, cookie)
    client:close()
    if not ok then
        print("Error adding user_cookie record: ", err)
        return false
    end

    return true
end

local function get_cookie_by_user(user)
    local client = connect_to_redis()
    if not client then return nil end

    local cookie, err = client:hget("user_cookie", user)
    client:close()
    if not user then
        print("Error getting cookie by user: ", err)
        return nil
    end

    return cookie
end

local function delete_user_cookie(user)
    local client = connect_to_redis()
    if not client then return false end

    local ok, err = client:hdel("user_cookie", user)
    client:close()
    if not ok then
        print("Error deleting user_cookie record: ", err)
        return false
    end

    return true
end

return {
    is_virtual_url_exists = is_virtual_url_exists,
    update_data = update_data,
    add_to_whitelist = add_to_whitelist,
    remove_from_whitelist = remove_from_whitelist,
    add_url_user = add_url_user,
    get_user_by_url = get_user_by_url,
    add_user_cookie = add_user_cookie,
    get_cookie_by_user = get_cookie_by_user,
    delete_user_cookie = delete_user_cookie,
    is_url_in_whitelist = is_url_in_whitelist,
    get_data_in_url_table = get_data_in_url_table,
}

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

local function add_user_url(user, urls)
    local client = connect_to_redis()
    if not client then return false end


    local ok, err = client:hset("user_url", user, cjson.encode(urls))
    client:close()
    if not ok then
        print("Error adding user URL: ", err)
        return false
    end

    return true
end

local function get_url_by_user(user)
    local client = connect_to_redis()
    if not client then return nil end

    local urls, err = client:hget("user_url", user)
    client:close()
    if not urls then
        print("Error getting user URL: ", err)
        return nil
    end

    return cjson.decode(urls)
end

local function add_cookie_user(cookie, user)
    local client = connect_to_redis()
    if not client then return false end

    local ok, err = client:hset("cookie_user", cookie, user)
    client:close()
    if not ok then
        print("Error adding cookie_user record: ", err)
        return false
    end

    return true
end

local function get_user_by_cookie(cookie)
    local client = connect_to_redis()
    if not client then return nil end

    local user, err = client:hget("user_cookie", cookie)
    client:close()
    if not user then
        print("Error getting user_by_cookie: ", err)
        return nil
    end

    return cookie
end

local function delete_cookie_user(cookie)
    local client = connect_to_redis()
    if not client then return false end

    local ok, err = client:hdel("user_cookie", cookie)
    client:close()
    if not ok then
        print("Error deleting cookie_user record: ", err)
        return false
    end

    return true
end

local function generate_random_key()
    local key_length = 16
    local key = ""
    local characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

    for i = 1, key_length do
        local index = math.random(#characters)
        key = key .. characters:sub(index, index)
    end

    return key
end

local function add_user_key(user)
    local client = connect_to_redis()
    if not client then return false end

    local key = generate_random_key()
    local ok, err = client:hset("user_key", user, key)
    client:close()
    if not ok then
        print("Error add_user_key: ", err)
        return false
    end

    return true
end

local function get_key_by_user(user)
    local client = connect_to_redis()
    if not client then return false end

    local key = generate_random_key()
    local key, err = client:hget("user_key", user)
    client:close()
    if not key then
        print("Error add_user_key: ", err)
        return false
    end

    return key
end

return {
    is_virtual_url_exists = is_virtual_url_exists,
    update_data = update_data,
    add_to_whitelist = add_to_whitelist,
    remove_from_whitelist = remove_from_whitelist,
    add_user_url = add_user_url,
    get_url_by_user = get_url_by_user,
    add_cookie_user = add_cookie_user,
    get_user_by_cookie = get_user_by_cookie,
    delete_cookie_user = delete_cookie_user,
    is_url_in_whitelist = is_url_in_whitelist,
    get_data_in_url_table = get_data_in_url_table,
    get_key_by_user = get_key_by_user,
    add_user_key = add_user_key,
}

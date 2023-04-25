local url = require("socket.url")
local aes = require "resty.aes"
local redis_connector = require "redis_connector"
local uuid = require "resty.jit-uuid"
local redis = require "resty.redis"
uuid.seed()


local function encrypt_path(key, path)
    local path_to_encrypt = string.sub(path, 2)
    local aes_256_cbc_sha512x2 = aes:new(key, nil, aes.cipher(128, "cbc"), {iv = "1234567890123456"})
    local encrypted = aes_256_cbc_sha512x2:encrypt(path_to_encrypt)
    local encoded = ngx.encode_base64(encrypted)
    return '/' .. encoded
end

local function is_absolute_url(url)
    return url:find("http://") == 1 or url:find("https://") == 1
end

-- 
local function process_absolute_url(key, url_string, user)
    local in_whitelist, err = redis_connector.is_url_in_whitelist(url_string)
    if in_whitelist then
        return url_string
    else
        local parsed_url = url.parse(url_string)
        local path = parsed_url.path
        local encrypted_path = encrypt_path(key, path)
        
        parsed_url.path = encrypted_path
        local result_url = url.build(parsed_url)

        local urls, err1 = redis_connector.get_url_by_user(user)
        if err1 then
            ngx.log(ngx.ERR,"Error get_url_by_user:" ,err1)
            return
        end
        -- 5.4
        urls[url_string] = encrypted_path
        
        local _, err2 = redis_connector.add_user_url(user, urls)
        if err2 then
            ngx.log(ngx.ERR,"Error add_user_url:" ,err2)
            return 
        end

        local info = {
            real_url = url_string,
            is_first = true,
            expire_time = os.time() + 100,000,000,
            access_count = 0,
            last_access = os.time()
        }
        local _, err3 = redis_connector.add_url_table_data(result_url,info)
        if err3 then
            ngx.log(ngx.ERR,"Error add_url_table_data:" ,err3)
        end

        return result_url
    end

    

    
end

local function process_relative_url(key, base_url, relative_path, user)
    local combined_url = url.absolute(base_url, relative_path)
    return process_absolute_url(key, combined_url, user)
end


local function process_url(key, base_url, url, user)
    local replaced_url
    if is_absolute_url(url) then
        replaced_url = process_absolute_url(key, url, user)
    else
        replaced_url = process_relative_url(key, base_url, url, user)
    end
    return replaced_url
end

local function processed_response(base_url, response, user)
    local patterns = {
        '(href)=["\']([^"\']+)["\']',
        '(src)=["\']([^"\']+)["\']',
        '(action)=["\']([^"\']+)["\']'
    }

    local key, err = redis_connector.get_key_by_user(user)    
    if err then
        ngx.log(ngx.ERR, 'Error get_key_by_user:'..err)
        return
    end

    -- 存储原始 URL 信息
    local url_infos = {}

    -- 提取 URL 信息
    for _, pattern in ipairs(patterns) do
        response = string.gsub(response, pattern, function(attr, url)
            table.insert(url_infos, {attr = attr, url = url})
            return attr .. "=\""  .. url  .. "\""
        end)
    end

    -- 处理 URL
    local replaced_urls = {}
    for _, url_info in ipairs(url_infos) do
        local replaced_url = process_url(key, base_url, url_info.url, user)
        replaced_urls[url_info.url] = replaced_url
    end

    -- 使用处理后的 URL 替换原始 URL
    for original_url, replaced_url in pairs(replaced_urls) do
        response = string.gsub(response, original_url, replaced_url)
    end

    return response
end


local function is_external_link(url, protected_server_url)
    return not string.find(url, protected_server_url)
end

local _M = {}

function _M.process_url_rewrite(base_url,res)
    local first_access = ngx.var.cookie_is_first_access
    local cookie = ngx.var.cookie_value
    -- 4.1
    if first_access == "true" then
        -- 4.2
        local unique_identifier = uuid()
        local _, err = redis_connector.add_cookie_user(cookie, unique_identifier)
        local _, err1 = redis_connector.add_user_key(unique_identifier)
        if err then
            ngx.log(ngx.ERR, "Error add_cookie_user:"..err)
            return 
        end

        if err1 then
            ngx.log(ngx.ERR, "Error add_user_key:"..err1)
            return 
        end
    else
        -- 4.3
        local client_cookies = ngx.var.http_cookie or ""
        local cookie_name = "value"
        local new_value = uuid()
        local new_cookie = new_value..'; Path=/; HttpOnly; Expires=' .. ngx.cookie_time(ngx.time() + 60 * 60 * 24 * 365)
        local update_cookies = string.gsub(client_cookies, cookie_name .. "=(.-);", cookie_name .. "=" .. new_cookie .. ";")
        ngx.header['Set-Cookie'] = update_cookies
        local user, err0 = redis_connector.get_user_by_cookie(cookie)
        if err0 then 
            ngx.log(ngx.ERR, 'Error get_user_by_cookie:'..err0)
            return 
        end

        local _, err = redis_connector.delete_cookie_user(cookie)
        if err then 
            ngx.log(ngx.ERR, 'Error delete_cookie_user:'..err)
            return 
        end

        local _, err2 = redis_connector.add_cookie_user(new_value, user)
        local _, err1 = redis_connector.add_user_key(user)
        if err2 then 
            ngx.log(ngx.ERR, 'Error add_cookie_user:'..err2)
            return 
        end

        if err1 then
            ngx.log(ngx.ERR, "Error add_user_key:"..err1)
            return 
        end
    end

    local _cookie = ngx.var.cookie_value

    local user, err = redis_connector.get_user_by_cookie(_cookie)

    if err then
        ngx.log(ngx.ERR, 'Error get_user_by_cookie:'..err)
        return 
    end

    -- 5.1 - 5.9
    return processed_response(base_url, res, user)

end

return _M
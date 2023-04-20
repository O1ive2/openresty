local url = require("socket.url")
local aes = require "resty.aes"
local redis_connector = require "redis_connector"

-- 5.2
local function is_in_whitelist(url)
    local is_whitelisted, err = redis_connector.is_url_in_whitelist(url)

    if err then
        ngx.log(ngx.ERR, "Error checking whitelist: ", err)
        return
    end

    if is_whitelisted then
        -- turn 5.9
        return true
    end

    -- turn 5.3
    return false
end

-- 5.3
local function check_in_user_url(url,cookie)
    local user, err = redis_connector.get_user_by_cookie(cookie)
    if err then
        ngx.log(ngx.ERR, "Error get_user_by_cookie: ", err)
        return 
    end
    
    local urls ,err2 = redis_connector.get_url_by_user(user)
    if err2 then
        ngx.log(ngx.ERR, "Error get_url_by_user: ", err2)
        return 
    end

    if urls and urls[url]then
        -- turn 5.7
        return true

    else
        --turn 5.4
        return false
    end

end

local function encrypt_path(key, path)
    local path_to_encrypt = string.sub(path, 2)
    local aes_256_cbc_sha512x2 = aes:new(key, nil, aes.cipher(128, "cbc"), {iv = "1234567890123456"})
    local encrypted = aes_256_cbc_sha512x2:encrypt(path_to_encrypt)
    ngx.log(ngx.ERR, 'path_to_encrypt:'..path_to_encrypt)
    local encoded = ngx.encode_base64(encrypted)
    ngx.log(ngx.ERR, 'encoded:'..encoded)
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
        end

        urls[url_string] = encrypted_path
        
        local _, err2 = redis_connector.add_user_url(user, urls)
        if err2 then
            ngx.log(ngx.ERR,"Error add_user_url:" ,err2)
        end

        local info = {
            real_url = url_string,
            is_first = true,
            expire_time = os.time() + 100,000,000,
            access_count = 0,
            last_access = os.time()
        }
        local _, err3 = redis_connector.update_data( encrypted_path,info)
        if err3 then
            ngx.log(ngx.ERR,"Error update_data:" ,err3)
        end

        return result_url
    end

    
end

local function process_relative_url(key, base_url, relative_path, user)
    local base_url_ends_with_slash = string.sub(base_url, -1) == "/"
    local relative_path_starts_with_slash = string.sub(relative_path, 1, 1) == "/"

    local combined_url

    if base_url_ends_with_slash and relative_path_starts_with_slash then
        combined_url = base_url .. string.sub(relative_path, 2)
    elseif not base_url_ends_with_slash and not relative_path_starts_with_slash then
        combined_url = base_url .. "/" .. relative_path
    else
        combined_url = base_url .. relative_path
    end

    return process_absolute_url(key, combined_url, user)
end

-- 5.4
local function processed_response(base_url, response, user)
    local patterns = {
        '(href)=["\']([^"\']+)["\']',
        '(src)=["\']([^"\']+)["\']',
        '(action)=["\']([^"\']+)["\']'
    }

    local processed_response = response

    local key = redis_connector.get_key_by_user(user)

    for _, pattern in ipairs(patterns) do
        processed_response, _ = string.gsub(processed_response, pattern, function(attr, url)
            local replaced_url
            if is_absolute_url(url) then
                replaced_url = process_absolute_url(key, url, user)
            else
                replaced_url = process_relative_url(key, base_url, url, user)
            end

            ngx.log(ngx.ERR, "Matched string: ", url)
            ngx.log(ngx.ERR, "Replaced URL: ", replaced_url)

            
            return attr .. "=\""  .. replaced_url  .. "\""
        end)
    end
    ngx.log(ngx.ERR,'process_response END')
    return processed_response
end


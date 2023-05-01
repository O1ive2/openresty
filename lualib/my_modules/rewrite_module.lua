local url = require("socket.url")
local aes = require "resty.aes"
local redis_connector = require "redis_connector"
local uuid = require "resty.jit-uuid"
local redis = require "resty.redis"
uuid.seed()

local _M = {}

local function table_to_string(table)
    local result = ""
    for k, v in pairs(table) do
        result = result .. tostring(k) .. "=" .. tostring(v) .. ", "
    end
    return "{" .. string.sub(result, 1, -3) .. "}"
end

local function encrypt_path(key, path)
    ngx.log(ngx.ERR, 'key: ',key)
    local path_to_encrypt = string.sub(path, 2)
    local aes_256_cbc_sha512x2 = aes:new(key, nil, aes.cipher(128, "cbc"), {iv = "1234567890123456"})
    local encrypted = aes_256_cbc_sha512x2:encrypt(path_to_encrypt)
    local encoded = ngx.encode_base64(encrypted)
    encoded = string.gsub(encoded, "/", "_") -- 将 '/' 替换为 '_'
    return '/' .. encoded
end

local function is_absolute_url(url)
    ngx.log(ngx.ERR, '5.1 - 5.2')
    return url:find("http://") == 1 or url:find("https://") == 1
end

-- 
local function process_absolute_url(key, url_string, user)
    ngx.log(ngx.ERR, '5.2 - 5.3')
    local urls, err0 = redis_connector.get_url_by_user(user)
    if urls and urls[url_string] then
        ngx.log(ngx.ERR, '5.3 - 5.7')
        local vir_url = urls[url_string]
        local new_expire_time = ngx.time() + 60 * 60 * 24 * 365
        local _, err = redis_connector.update_data(vir_url, {expire_time = new_expire_time})
        ngx.log(ngx.ERR, '5.7 - 5.8')
        if err then
            ngx.log(ngx.ERR,"Error update_data:" ,err)
            return
        end
    else
        local is_protect_link = _M.is_protect_link(url_string)
        local in_whitelist, err = redis_connector.is_url_in_whitelist(url_string)
        if err then
            ngx.log(ngx.ERR,"Error is_url_in_whitelist:" ,err)
            return
        end
        if is_protect_link then
            ngx.log(ngx.ERR, 'it is protect link ')
            if in_whitelist then
                ngx.log(ngx.ERR, 'it is in whitelist')
                return url_string
            else
                ngx.log(ngx.ERR, 'it is not in whitelist')
                ngx.log(ngx.ERR, '5.3 - 5.4')
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
                urls[url_string] = result_url
                ngx.log(ngx.ERR, '5.4 - 5.5')
                
                local _, err2 = redis_connector.add_user_url(user, urls)
                if err2 then
                    ngx.log(ngx.ERR,"Error add_user_url:" ,err2)
                    return 
                end
        
                ngx.log(ngx.ERR, '5.5 - 5.6')
                local info = {
                    real_url = url_string,
                    expire_time = ngx.time() + 60 * 60 * 24 * 365,
                    last_access = 0,
                    access_count = 0
                }
                local _, err3 = redis_connector.add_url_table_data(result_url,info)
                if err3 then
                    ngx.log(ngx.ERR,"Error add_url_table_data:" ,err3)
                    return
                end
                ngx.log(ngx.ERR, '5.6 - 5.8')
                return result_url
            end
        else
            ngx.log(ngx.ERR, 'it not protect link ')
            return url_string 
        end
    end
end

local function process_relative_url(key, base_url, relative_path, user)
    local combined_url = url.absolute(base_url, relative_path)
    return process_absolute_url(key, combined_url, user)
end




local function process_url(key, base_url, url, user)
    local replaced_url
    if is_absolute_url(url) then
        ngx.log(ngx.ERR, 'it is_absolute_url!')
        replaced_url = process_absolute_url(key, url, user)
    else
        ngx.log(ngx.ERR, 'it is not absolute_url!')
        replaced_url = process_relative_url(key, base_url, url, user)
    end
    return replaced_url
end

function _M.processed_response(base_url, response, user)
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
            ngx.log(ngx.ERR, "attr:",attr," url:",url)
            return attr .. "=\""  .. url  .. "\""
        end)
    end



    -- 处理 URL
    local replaced_urls = {}
    for _, url_info in ipairs(url_infos) do
        local replaced_url = process_url(key, base_url, url_info.url, user)
        ngx.log(ngx.ERR, '5.8 - 5.9')
        replaced_urls[url_info.url] = replaced_url
    end


    -- 使用处理后的 URL 替换原始 URL
    for original_url, replaced_url in pairs(replaced_urls) do
        response = string.gsub(response, original_url, replaced_url)
    end


    return response
end


function _M.is_protect_link(url)
    local pattern1 = "https?://rws%.com"
    local pattern2 = "https?://pwb%.com"
    local pattern3 = "https?://192.168.38.128"
    local start_index1  = string.find(url, pattern1)
    local start_index2  = string.find(url, pattern2)
    local start_index3 = string.find(url, pattern3)
    if start_index1 or start_index2 or start_index3 then
        return true
    else
        return false
    end
end

return _M
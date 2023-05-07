local url = require("socket.url")
local redis_connector = require "redis_connector"
local aes = require "resty.aes"
local uuid = require "resty.jit-uuid"

uuid.seed()

local _M = {}

local function escape(s)
    return s:gsub("([^%w])", "%%%1")
end

local function table_to_string(table)
    local result = ""
    for k, v in pairs(table) do
        result = result .. tostring(k) .. "=" .. tostring(v) .. ", "
    end
    return "{" .. string.sub(result, 1, -3) .. "}"
end

local function encrypt_path(key, path)
    local path_to_encrypt = string.sub(path, 2)
    local aes_256_cbc_sha512x2, err = aes:new(key, nil, aes.cipher('128', "cbc"), {iv = "1234567890123456"})
    local encrypted = aes_256_cbc_sha512x2:encrypt(path_to_encrypt)
    local encoded = ngx.encode_base64(encrypted)
    local hash = ngx.md5(path)
    encoded = string.gsub(encoded, "/", "~")
    encoded = string.gsub(encoded, "=", "-")
    encoded = string.gsub(encoded, "+", "^")

    return '/' .. encoded .. '_' .. hash
end

function _M.decrypt_path(key, encrypted_path)
    local path_to_decrypt = string.sub(encrypted_path, 2)
    path_to_decrypt = string.gsub(path_to_decrypt, "~", "/")
    path_to_decrypt = string.gsub(path_to_decrypt, "-", "=")
    path_to_decrypt = string.gsub(path_to_decrypt, "%^", "+")
    local decoded = ngx.decode_base64(path_to_decrypt)

    if decoded == nil then
        return false
    end

    local aes_256_cbc_sha512x2,err = aes:new(key, nil, aes.cipher("128", "cbc"), {iv = "1234567890123456"})

    if not aes_256_cbc_sha512x2 then
        ngx.log(ngx.ERR,'aes err:',err)
    end

    local decrypted = aes_256_cbc_sha512x2:decrypt(decoded)

    -- ngx.log(ngx.ERR,'decrypted:',decrypted)

    if decrypted == nil then
        return false
    end

    local decrypted_path = "/" .. decrypted

    return decrypted_path
end

local function is_absolute_url(url)
    return url:find("http://") == 1 or url:find("https://") == 1
end


local function process_absolute_url(key, url_string, type)
    local is_protect_link = _M.is_protect_link(url_string)
    local in_whitelist, err = redis_connector.is_url_in_whitelist(url_string)
    if err then
        ngx.log(ngx.ERR,"Error is_url_in_whitelist:" ,err)
        return
    end
    
    if is_protect_link then
        -- ngx.log(ngx.ERR, 'it is protect link ')
        if in_whitelist then
            -- ngx.log(ngx.ERR, 'it is in whitelist')
            -- return url_string
        else
            -- ngx.log(ngx.ERR, 'it is not in whitelist')
            local parsed_url = url.parse(url_string)
            local path = parsed_url.path
            local encrypted_path = path
            if path then
                encrypted_path = encrypt_path(key, path)
            end

            if type and type == 'action' then
                parsed_url.path = encrypted_path .. '_form'
            else
                parsed_url.path = encrypted_path
            end
            local result_url = url.build(parsed_url)
            
            return result_url
        end
    else
        -- ngx.log(ngx.ERR, 'it is not protect url')
        -- return url_string
    end
end

local function process_relative_url(key, base_url, relative_path, type)
    local combined_url = url.absolute(base_url, relative_path)
    -- ngx.log(ngx.ERR, 'relative:',relative_path,' absolute:', combined_url)
    return process_absolute_url(key, combined_url ,type)
end


local function process_url(key, base_url, url,type)
    local replaced_url
    if is_absolute_url(url) then
        replaced_url = process_absolute_url(key, url, type)
    else
        replaced_url = process_relative_url(key, base_url, url, type)
    end
    return replaced_url
end


function _M.processed_css(base_url, response, key)
    response = string.gsub(response, 'cbs.hdu.edu.cn', 'rws.com')
    local patterns = {
        '@import%s+"([^"]*)"%s*',
        "@import%s+'([^']*)'%s*"
    }

    local patterns_1 = {
        'url%("([^"]*)"%)',
        "url%('([^']*)'%)",
        'url%(([^"\'%s]+)%)'
    }

    -- 存储原始 URL 信息
    local url_infos = {}

    -- 提取 URL 信息
    for _, pattern in ipairs(patterns) do
        response = string.gsub(response, pattern, function(url)
            table.insert(url_infos, {url = url})
            return '@import url("' .. url .. '")'
        end)
    end

    for _, pattern in ipairs(patterns_1) do
        response = string.gsub(response, pattern, function(url)
            table.insert(url_infos, {url = url})
            return 'url("' .. url .. '")'
        end)
    end

    -- 处理 URL
    local replaced_urls = {}
    for _, url_info in ipairs(url_infos) do
        local replaced_url = process_url(key, base_url, url_info.url)
        replaced_urls[url_info.url] = replaced_url
    end


    -- 使用处理后的 URL 替换原始 URL
    for original_url, replaced_url in pairs(replaced_urls) do
        response = string.gsub(response, escape(original_url), replaced_url)
    end

    return response
end


function _M.is_protect_link(url_string)
    local parsed_url = url.parse(url_string)
    local scheme = parsed_url.scheme and (parsed_url.scheme .. "://") or ""
    local host = parsed_url.host or ""

    local scheme_and_host = scheme .. host

    local is_in_whitelist = redis_connector.is_url_in_whitelist(scheme_and_host)
    if is_in_whitelist then
        return true
    else
        return false    
    end
    
end

function _M.processed_response(base_url, response, key)
    local patterns = {
        '(href)=["\']([^"\']+)["\']',
        '(src)=["\']([^"\']+)["\']',
        '(action)=["\']([^"\']+)["\']'
    }

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
        local replaced_url = process_url(key, base_url, url_info.url, url_info.attr)
        replaced_urls[url_info.url] = replaced_url
    end


    -- 使用处理后的 URL 替换原始 URL
    for original_url, replaced_url in pairs(replaced_urls) do
        -- ngx.log(ngx.ERR, 'original_url:', original_url, ' replaced_url:', replaced_url)
        response = string.gsub(response, escape(original_url), replaced_url)
    end


    response = string.gsub(response, 'cbs.hdu.edu.cn', 'rws.com')
    return response
end

return _M
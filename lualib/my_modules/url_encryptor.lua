local http = require("resty.http")
local url = require("socket.url")
local aes = require "resty.aes"
local str = require "resty.string"


-- 3
local function encrypt_path(key, path)
    local path_to_encrypt = string.sub(path, 2)
    local aes_256_cbc_sha512x2 = aes:new(key, nil, aes.cipher(128, "cbc"), {iv = "1234567890123456"})
    local encrypted = aes_256_cbc_sha512x2:encrypt(path_to_encrypt)
    local encoded = ngx.encode_base64(encrypted)
    ngx.log(ngx.ERR, 'encoded:'..encoded)
    return '/' .. encoded
end

-- 它将相对URL转换为绝对URL
local function resolve(base_url, relative_url)
    local base_parsed = url.parse(base_url)
    local relative_parsed = url.parse(relative_url)

    if relative_parsed.scheme then
        return url.build(relative_parsed)
    end

    local result = {}
    result.scheme = base_parsed.scheme
    result.host = base_parsed.host
    result.port = base_parsed.port
    result.userinfo = base_parsed.userinfo

    if relative_parsed.path then
        if string.sub(relative_parsed.path, 1, 1) == "/" then
            result.path = relative_parsed.path
        else
            if not base_parsed.path then
                result.path = "/" .. relative_parsed.path
            else
                result.path = string.gsub(base_parsed.path, "/?[^/]*$", "") .. "/" .. relative_parsed.path
            end
        end
    else
        result.path = base_parsed.path
    end

    result.params = relative_parsed.params
    result.query = relative_parsed.query
    result.fragment = relative_parsed.fragment

    return url.build(result)
end

local function is_absolute_url(url)
    return url:find("http://") == 1 or url:find("https://") == 1
end

-- 2

local function process_absolute_url(key, base_url, url_string)
    local parsed_url = url.parse(url_string)
    local path = parsed_url.path
    ngx.log(ngx.ERR, 'path:'..path)
    local encrypted_path = encrypt_path(key, path)
    parsed_url.path = encrypted_path
    local result_url = url.build(parsed_url)
    return result_url
end

local function process_relative_url(key, base_url, relative_path)
    local absolute_url = base_url .. relative_path
    return process_absolute_url(key, base_url, absolute_url)
end

-- 1
local function process_response(key, base_url, response)
    ngx.log(ngx.ERR,'process_response,process_response,process_response')
    -- local pattern = "(%w+)=['\"]([^'\"]+)['\"]"
    local patterns = {
        '(href)=["\']([^"\']+)["\']',
        '(src)=["\']([^"\']+)["\']',
        '(action)=["\']([^"\']+)["\']'
    }
    -- local processed_response, _ = string.gsub(response, pattern, function(attr, url)
    --     ngx.log(ngx.ERR, "attr: ", attr)
    --     ngx.log(ngx.ERR, "url: ", url)
    --     local replaced_url
    --     if is_absolute_url(url) then
    --         replaced_url = process_absolute_url(key, base_url, url)
    --     else
    --         replaced_url = process_relative_url(key, base_url, url)
    --     end
    
    --     ngx.log(ngx.ERR, "Matched string: ", url)
    --     ngx.log(ngx.ERR, "Replaced URL: ", replaced_url)
    
    --     return attr .. "=\"" .. replaced_url .. "\""
    -- end)

    local processed_response = response

    for _, pattern in ipairs(patterns) do
        processed_response, _ = string.gsub(processed_response, pattern, function(attr, url)
            local replaced_url
            if is_absolute_url(url) then
                replaced_url = process_absolute_url(key, base_url, url)
            else
                replaced_url = process_relative_url(key, base_url, url)
            end

            ngx.log(ngx.ERR, "Matched string: ", url)
            ngx.log(ngx.ERR, "Replaced URL: ", replaced_url)

            return attr .. "=\"" .. replaced_url .. "\""
        end)
    end
    ngx.log(ngx.ERR,'process_response END')
    return processed_response
end

local _M = {}

function _M.fetch_and_encrypt_url(key, target_url)
    local httpc = http.new()
    local res, err = httpc:request_uri(target_url, {
        method = "GET",
    })

    if not res then
        return nil, err
    end

    local content = res.body
    local processed_content = process_response(key, target_url, content)
    return processed_content
end

return _M

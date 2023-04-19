local http = require("resty.http")
local url = require("socket.url")
local aes = require "resty.aes"
local str = require "resty.string"


-- 3
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

    return process_absolute_url(key, base_url, combined_url)
end


-- 1
local function process_response(key, base_url, response)
    local patterns = {
        '(href)=["\']([^"\']+)["\']',
        '(src)=["\']([^"\']+)["\']',
        '(action)=["\']([^"\']+)["\']'
    }

    local processed_response = response

    for _, pattern in ipairs(patterns) do
        processed_response, _ = string.gsub(processed_response, pattern, function(attr, url)
            local replaced_url
            if is_absolute_url(url) then
                replaced_url = process_absolute_url(key, base_url, url)
            else
                replaced_url = process_relative_url(key, base_url, url)
            end

            local prefix = ""
            if attr == "href" or attr == "src" then
                prefix = "/regular/"
            elseif attr == "action" then
                prefix = "/form/"
            end

            ngx.log(ngx.ERR, "Matched string: ", url)
            ngx.log(ngx.ERR, "Replaced URL: ", prefix .. replaced_url)

            return attr .. "=\""  .. replaced_url .. prefix .. "\""
        end)
    end
    ngx.log(ngx.ERR,'process_response END')
    return processed_response
end

local _M = {}

function _M.fetch_and_encrypt_url(key, target_url)
    ngx.log(ngx.ERR, 'target_url:'..target_url)
    local httpc = http.new()
    local res, err = httpc:request_uri(target_url, {
        method = "GET",
        follow_redirects = true
    })

    if not res then
        return nil, err
    end

    local content = res.body
    local processed_content = process_response(key, target_url, content)
    return processed_content
end

return _M

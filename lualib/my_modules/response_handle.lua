local rewrite_module = require('my_modules.rewrite_module')
local redis_connector = require('my_modules.redis_connector')
local uuid = require "resty.jit-uuid"
local ffi_zlib = require('resty.ffi-zlib')
uuid.seed()

local _M = {}

local function table_to_string(table)
    local result = ""
    for k, v in pairs(table) do
        result = result .. tostring(k) .. "=" .. tostring(v) .. ", "
    end
    return "{" .. string.sub(result, 1, -3) .. "}"
end

local function update_cookie_table(new_cookie)
    local cookie_header = ngx.var.http_cookie

    local cookies = {}
    if cookie_header then
        for cookie in string.gmatch(cookie_header, "([^;]+)") do
            local trimmed_cookie = string.gsub(cookie, "^%s*(.-)%s*$", "%1")
            table.insert(cookies, trimmed_cookie)
        end
    end
    ngx.log(ngx.ERR, 'old cookie table:', table_to_string(cookies))

    if new_cookie then
        table.insert(cookies, new_cookie)
    end

    ngx.log(ngx.ERR, 'new cookie table:', table_to_string(cookies))

    return cookies
end

function _M.get_cookie_value(cookie_name)
    local cookie_header = ngx.var.http_cookie

    if not cookie_name or not cookie_header then
        return nil
    end

    local cookie_pattern = cookie_name .. "=([^;]+)"
    local match = string.match(cookie_header, cookie_pattern)

    if match then
        return match
    else
        return nil
    end
end

function _M.decompress_gzip(compressed_body)
    -- 定义一个输入函数，它会从压缩过的数据中返回全部数据
    local function input_function()
        return compressed_body
    end

    -- 定义一个输出函数，它会接收解压缩后的数据
    local decompressed_body = ""
    local function output_function(data)
        decompressed_body = decompressed_body .. data
        return true
    end

    -- 使用 ffi-zlib 的 inflateGzip 函数进行解压缩
    local ok, err = ffi_zlib.inflateGzip(input_function, output_function)

    return decompressed_body

end

function _M.compress_gzip(decompressed_body)
    local compressed_body = ""

    local function input_function(chunk_size)
        if #decompressed_body == 0 then
            return nil
        end
        local chunk = decompressed_body:sub(1, chunk_size)
        decompressed_body = decompressed_body:sub(chunk_size + 1)
        return chunk
    end

    local function output_function(data)
        compressed_body = compressed_body .. data
        return true
    end

    local options = {
        level = 9,  -- 使用最高压缩级别
    }

    local ok, err = ffi_zlib.deflateGzip(input_function, output_function, nil, options)

    if not ok then
        return nil, err
    else
        return compressed_body
    end
end

function _M.is_html(content_type)
    if content_type then
        local mime = content_type:match("^%s*(.-)%s*;") or content_type
        if mime:lower() == "text/html" then
            return true
        end
    end
    return false
end

function  _M.response_handle(response_body, is_first_access, user)
    ngx.log(ngx.ERR, 'cur user:',user )
    ngx.log(ngx.ERR, '3 - 4.1')
    if is_first_access == true then
        ngx.log(ngx.ERR, '4.1 - 4.2')
        user = uuid()

        -- local client_cookies = ngx.var.http_cookie or ""
        -- local user_cookie = "user=".. user .. '; Path=/; HttpOnly; Expires=' .. ngx.cookie_time(ngx.time() + 60 * 60 * 24 * 365)
        -- local updated_cookies = client_cookies .. "; " .. user_cookie
        
        -- ngx.header['Set-Cookie'] = updated_cookies
        -- ngx.log(ngx.ERR, '1.updated_cookies:', updated_cookies)

        local user_dict = ngx.shared.user_dict

        user_dict:set('user', user)

        local _, err = redis_connector.add_user_key(user)
        if err then
            ngx.log(ngx.ERR,"Error add_user_key:" ,err)
            return 
        end
    else
        ngx.log(ngx.ERR, '4.1 - 4.3')
        local old_cookie_value = ngx.var.cookie_value
        -- ngx.log(ngx.ERR,"old_cookie_value:" ,old_cookie_value)
        -- user = redis_connector.get_user_by_cookie(old_cookie_value)
        -- ngx.log(ngx.ERR,"get_user_by_cookie user:" ,user)
        ngx.log(ngx.ERR,"old user:" ,user)
        
        local _, err = redis_connector.delete_cookie_user(old_cookie_value)
        if err then
            ngx.log(ngx.ERR,"Error delete_cookie_user:" ,err)
            return 
        end

        local _, err1 = redis_connector.delete_cookie_ip(old_cookie_value)

        if err then
            ngx.log(ngx.ERR,"Error delete_cookie_ip:" ,err1)
            return 
        end
    end

    

    local new_cookie_value = uuid()
    
    local value_cookie = "value="..new_cookie_value .. '; Path=/; HttpOnly; Expires=' .. ngx.cookie_time(ngx.time() + 60 * 60 * 24 * 365)
        
    ngx.header['Set-Cookie'] = value_cookie

    local ip_addr = ngx.var.remote_addr

    local _ ,err = redis_connector.add_cookie_user(new_cookie_value, user)
    if err then
        ngx.log(ngx.ERR,"Error add_cookie_user:" ,err)
        return 
    end
    local _, err1 = redis_connector.add_cookie_ip(new_cookie_value, ip_addr)

    if err1 then
        ngx.log(ngx.ERR,"Error add_cookie_ip:" ,err1)
        return 
    end

    local base_url = ngx.var.scheme .. '://' .. ngx.var.host .. ngx.var.uri

    ngx.log(ngx.ERR, '5')
    local rewrite_html = rewrite_module.processed_response(base_url,response_body, user)

    ngx.log(ngx.ERR, 'rewrite_html:',rewrite_html)

    return rewrite_html

end

return _M
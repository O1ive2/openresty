local process_uri = require('my_modules.check_transform_moudle')
local redis_connector = require('my_modules.redis_connector')
local url = require("socket.url")
local uuid = require "resty.jit-uuid"
local response_handle = require("my_modules.new_response_handle")
local rewrite_module = require("my_modules.new_rewrite_module")

ngx.log(ngx.ERR,'1 - 2.1')
uuid.seed()

local user_dict = ngx.shared.user_dict
local user = user_dict:get('user')

local value_cookie = ngx.var.cookie_value

local scheme = ngx.var.scheme
local host = ngx.var.host
local uri = ngx.var.uri
local request_url = scheme .. "://" .. host .. uri

local parsed_url = url.parse(request_url)
local path = parsed_url.path
local encrypted_path  = path

local path_parts = {}
for part in string.gmatch(encrypted_path, "([^_]+)") do
    table.insert(path_parts, part)
end

local encrypted = path_parts[1]
local original_hash = path_parts[2]
local type = path_parts[3]

local uri_params = ngx.var.request_uri
local is_form_request = false
local query_string
if type and type == 'form' then
    is_form_request = true
    local question_mark_pos = string.find(uri_params, "?")
    query_string = string.sub(uri_params, question_mark_pos)
end

if redis_connector.is_url_in_whitelist(request_url) then
    if process_uri.is_dynamic_request() then 
        if process_uri.is_in_whitelist(request_url) then 
            local res = ngx.location.capture("/rewrite"..uri)
            
            local is_gzip = false
            for k, v in pairs(res.header) do
                ngx.ctx[k] = v
                if k == 'Content-Encoding' and v == 'gzip' then
                    is_gzip = true
                end
            end
            ngx.ctx.modified_headers = res.header
            local response_body = res.body

            if is_gzip then
                ngx.log(ngx.ERR,'it is gzip decompress')
                response_body = response_handle.decompress_gzip(response_body)
            end
                
            local content_type = res.header["Content-Type"]
            ngx.ctx.content_type = content_type


            local modified_body = response_handle.response_handle(response_body, true, user, content_type, request_url)

            if is_gzip then
                ngx.log(ngx.ERR,'it is gzip compress')
                modified_body = response_handle.compress_gzip(modified_body)
            end
            -- 将修改后的响应数据存储在 ngx.ctx 中
            ngx.ctx.modified_body = modified_body
        else
            process_uri.block_request_and_log("Whitelisted URL not found")
        end

    else
        process_uri.block_request_and_log("Request is a dynamic request.")
    end

elseif value_cookie and redis_connector.get_user_by_cookie(value_cookie) == user then
    local user_info, getErr = redis_connector.get_info_by_user(user)
    if getErr then
        ngx.log(ngx.ERR, 'getErr:',getErr)
    end

    if user_info and user_info.access_count > 10000 then
        ngx.log(ngx.ERR, 'user access_count is max!')
        ngx.exit(ngx.HTTP_FORBIDDEN)
    end

    if user_info and ngx.time() > user_info.expire_time then
        ngx.log(ngx.ERR, 'user is expire!')
        ngx.exit(ngx.HTTP_FORBIDDEN)
    end

    local key, err = redis_connector.get_key_by_user(user)
    ngx.log(ngx.ERR, 'encrypted:',encrypted)
    local real_uri = encrypted and rewrite_module.decrypt_path(key, encrypted)
    local decrypted_path_hash = real_uri and ngx.md5(real_uri)

    if decrypted_path_hash ~= original_hash then
        ngx.log(ngx.ERR,'decrypted_path_hash:',decrypted_path_hash, 'original_hash:',original_hash)
        process_uri.block_request_and_log("Request blocked: decrypted_path_hash and original_hash not match!")
    end


    parsed_url.path = real_uri
    request_url = url.build(parsed_url)

    local res
    local base_url
    if is_form_request then
        res = ngx.location.capture("/rewrite"..real_uri .. query_string)
        base_url = scheme .. "://" .. host .. real_uri .. query_string
    else    
        res = ngx.location.capture("/rewrite"..real_uri)
        base_url = scheme .. "://" .. host .. real_uri
    end

    local is_gzip = false
    for k, v in pairs(res.header) do
        ngx.ctx[k] = v
        if k == 'Content-Encoding' and v == 'gzip' then
            is_gzip = true
        end
    end

    local response_body = res.body
    if is_gzip then
        ngx.log(ngx.ERR,'it is gzip decompress')
        response_body = response_handle.decompress_gzip(response_body)
    end
    local content_type = res.header["Content-Type"]

    ngx.ctx.content_type = content_type
 
    local modified_body = response_handle.response_handle(response_body, false, user, content_type, base_url)

    if is_gzip then
        ngx.log(ngx.ERR,'it is gzip compress')
        modified_body = response_handle.compress_gzip(modified_body)
    else
        ngx.ctx.content_length = string.len(modified_body)
    end
    -- 将修改后的响应数据存储在 ngx.ctx 中
    ngx.ctx.modified_headers = res.header
    ngx.ctx.modified_body = modified_body
else
    process_uri.block_request_and_log("request_url not in whitelist and user not match the cookie")
end

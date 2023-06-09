local process_uri = require('my_modules.check_transform_moudle')
local redis_connector = require('my_modules.redis_connector')
local url = require("socket.url")
local uuid = require "resty.jit-uuid"
local response_handle = require("my_modules.new_response_handle")
local rewrite_module = require("my_modules.new_rewrite_module")

local method = ngx.req.get_method()
-- 获取请求 URI 和查询参数
local uri = ngx.var.request_uri
local args = ngx.req.get_uri_args()
-- 获取请求头
local headers = ngx.req.get_headers()
ngx.req.read_body()

-- ngx.log(ngx.ERR,'1 - 2.1')
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
                response_body = response_handle.decompress_gzip(response_body)
            end
                
            local content_type = res.header["Content-Type"]
            ngx.ctx.content_type = content_type


            local modified_body = response_handle.response_handle(response_body, true, user, content_type, request_url)

            if is_gzip then
                -- ngx.log(ngx.ERR,'it is gzip compress')
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
        ngx.log(ngx.ERR, 'The number of user visits to reach the maximum.')
        ngx.exit(ngx.HTTP_FORBIDDEN)
    end

    if user_info and ngx.time() > user_info.expire_time then
        ngx.log(ngx.ERR, 'The user identity has expired.')
        ngx.exit(ngx.HTTP_FORBIDDEN)
    end

    if not process_uri.is_ip_user_match(user) then
        process_uri.block_request_and_log("User and IP do not match.")
    end

    local key, err = redis_connector.get_key_by_user(user)
    -- ngx.log(ngx.ERR, 'encrypted:',encrypted)
    local real_uri = encrypted and rewrite_module.decrypt_path(key, encrypted)
    
    local decrypted_path_hash = real_uri and ngx.md5(real_uri)
    

    if query_string and not is_form_request then
        process_uri.block_request_and_log("Dynamic requests are not allowed.")
    end

    if decrypted_path_hash ~= original_hash then
        ngx.log(ngx.ERR,'decrypted_path_hash:',decrypted_path_hash, 'original_hash:',original_hash)
        process_uri.block_request_and_log("The hash value of the decryption path does not match the original hash value.")
    end




    parsed_url.path = real_uri
    request_url = url.build(parsed_url)

    local res
    local base_url
    if is_form_request then
        headers["referer"] = nil
        -- ngx.ctx.modified_referer = "https://cbs.hdu.edu.cn/main.htm"
        headers["Content-Type"] = "application/x-www-form-urlencoded"
        headers["Accept-Encoding"] = "gzip, deflate"
        headers["Upgrade-Insecure-Requests"] = "1"
        headers["Host"] = "rws.com"
        headers["Origin"] = "http://rws.com"
        headers["Referer"] = "https://cbs.hdu.edu.cn/main.htm"
        headers["vary"] = "accept-encoding"
        headers["X-Frame-Options"] = "SAMEORIGIN"
        headers["X-Application-Context"] = "application"
        -- headers["Postman-Token"] = "66b0f2e2-d3cd-4025-9098-e8f8fe267673"
        for k, v in pairs(headers) do
            ngx.log(ngx.ERR, k, ": ", v)
        end
        res = ngx.location.capture("/form" ..real_uri,
        {
            method = ngx["HTTP_" .. method],
            args = ngx.req.get_uri_args(),
            headers = headers,
            always_forward_body = true
        })
        -- ngx.status = res.status
        ngx.log(ngx.ERR, 'form_body:',response_handle.decompress_gzip(res.body))
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
        -- ngx.log(ngx.ERR,'it is gzip decompress')
        response_body = response_handle.decompress_gzip(response_body)
    end
    local content_type = res.header["Content-Type"]

    ngx.ctx.content_type = content_type
 
    local modified_body = response_handle.response_handle(response_body, false, user, content_type, base_url)

    if is_gzip then
        -- ngx.log(ngx.ERR,'it is gzip compress')
        modified_body = response_handle.compress_gzip(modified_body)
    else
        ngx.ctx.content_length = string.len(modified_body)
    end
    -- 将修改后的响应数据存储在 ngx.ctx 中
    ngx.ctx.modified_headers = res.header
    ngx.ctx.modified_body = modified_body
else
    process_uri.block_request_and_log("The user does not exist.")
end

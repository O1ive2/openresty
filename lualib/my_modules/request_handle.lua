local process_uri = require('my_modules.check_transform_moudle')
local redis_connector = require('my_modules.redis_connector')
local url = require("socket.url")
local uuid = require "resty.jit-uuid"
local response_handle = require("my_modules.response_handle")

uuid.seed()

local user_dict = ngx.shared.user_dict
local user = user_dict:get('user')

local scheme = ngx.var.scheme
local host = ngx.var.host
local uri = ngx.var.uri
local request_url = scheme .. "://" .. host .. uri
ngx.log(ngx.ERR, '2.1')

local real_url_info  = redis_connector.get_data_in_url_table(request_url)
ngx.log(ngx.ERR, '2.2')

if real_url_info and next(real_url_info) == nil then
    ngx.log(ngx.ERR, '2.2 - 2.3')


    if process_uri.is_dynamic_request() then 
        ngx.log(ngx.ERR, '2.3 - 2.4')

        if process_uri.is_in_whitelist(request_url) then 
            ngx.log(ngx.ERR, '2.4 - 3')
            ngx.log(ngx.ERR, '1.real_url:',uri )

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

            local modified_body = response_handle.response_handle(response_body, true, user, content_type)

            if is_gzip then
                ngx.log(ngx.ERR,'it is gzip compress')
                modified_body = response_handle.compress_gzip(modified_body)
            end
            
            -- 将修改后的响应数据存储在 ngx.ctx 中
            ngx.ctx.modified_body = modified_body

        else
            process_uri.block_request_and_log("Whitelisted URL not found:",request_url)
        end

    else
        process_uri.block_request_and_log("Request is a dynamic request.")
    end

else 
    ngx.log(ngx.ERR, '2.2 - 2.5')
    local cookie_value = ngx.var.cookie_value

    if process_uri.is_ip_user_match(user) then
        ngx.log(ngx.ERR, '2.5 - 2.6 - 2.7 - 2.8')

        if not process_uri.is_url_expire(request_url)then 
            ngx.log(ngx.ERR, 'gg1:')
            ngx.exec("/main.htm")
        end

        if not process_uri.is_max_count(request_url)then 
            ngx.log(ngx.ERR, 'gg2:')
            ngx.exec("/main.htm")
        end

        if not process_uri.is_access_too_fast(request_url)then 
            ngx.log(ngx.ERR, 'gg3:')
            ngx.exec("/main.htm")
        end

        ngx.log(ngx.ERR, '2.9')
        local real_url = real_url_info['real_url']

        local parsed_url = url.parse(real_url)
        local real_uri = parsed_url.path

        real_url_info.access_count = real_url_info.access_count + 1
        real_url_info.last_access = ngx.time()
        redis_connector.update_data(request_url, real_url_info)

        ngx.log(ngx.ERR, '2.9 - 3')
        ngx.log(ngx.ERR, '2.real_url:',real_uri )

        local res = ngx.location.capture("/rewrite"..real_uri)
        

        -- if res.status == ngx.HTTP_OK then
            -- ngx.log(ngx.ERR, 'pure body:', res.body)
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
 
            
            local modified_body = response_handle.response_handle(response_body, false, user, content_type)

            if is_gzip then
                ngx.log(ngx.ERR,'it is gzip compress')
                modified_body = response_handle.compress_gzip(modified_body)
            end
            -- 将修改后的响应数据存储在 ngx.ctx 中
            ngx.ctx.modified_headers = res.header
            ngx.ctx.modified_body = modified_body

        -- else
        --     --处理错误
        --     ngx.log(ngx.ERR, 'Error capture :',res.status)
        --     return 
        -- end
    else
        process_uri.block_request_and_log("Cookie url not match.")
    end

end
-- local allowed_origins = {
--     "http://rws.com",
--     "http://wbp.com",
--     "https://127.0.0.1",
--     "http://192.168.38.128/"
-- }

-- local origin = ngx.req.get_headers()["Origin"]

-- if origin then
--     for i, allowed_origin in ipairs(allowed_origins) do
--         if allowed_origin == origin then
--             ngx.header["Access-Control-Allow-Origin"] = allowed_origin
--             ngx.header["Access-Control-Allow-Credentials"] = "true"
--             break
--         end
--     end
-- end

local process_uri = require('my_modules.check_transform_moudle')
local redis_connector = require('my_modules.redis_connector')
local url = require("socket.url")
local uuid = require "resty.jit-uuid"
local response_handle = require("my_modules.response_handle")
uuid.seed()

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
            -- ngx.ctx.new_uri = uri
            -- ngx.var.is_first_access = true

            -- local new_uri= ngx.ctx.new_uri
            -- ngx.req.set_uri(new_uri)
            -- ngx.ctx.content_type = content_type
            local res = ngx.location.capture(uri)
            
            if res.status == ngx.HTTP_OK then
                for k, v in pairs(res.header) do
                    ngx.log(ngx.ERR, 'ngx header:', k ,':', v)
                    ngx.ctx[k] = v
                end
                ngx.log(ngx.ERR, 'pure body:',res.body)
                local content_type = res.header["Content-Type"]
                ngx.log(ngx.ERR, 'content_type:',content_type)
                ngx.ctx.content_type = content_type
                local modified_body = response_handle.response_handle(res.body, true)
                -- 将修改后的响应数据存储在 ngx.ctx 中
                ngx.ctx.modified_body = modified_body

            else
                -- 处理错误
                ngx.log(ngx.ERR, 'Error capture :',res.status)
                return 
            end
        else
            process_uri.block_request_and_log("Whitelisted URL not found:",request_url)
        end

    else
        process_uri.block_request_and_log("Request is a dynamic request.")
    end

else 
    ngx.log(ngx.ERR, '2.2 - 2.5')
    local cookie_value = ngx.var.cookie_value

    if process_uri.is_cookie_match(cookie_value) then
        ngx.log(ngx.ERR, '2.5 - 2.6 - 2.7 - 2.8')

        if not process_uri.is_url_expire(request_url)then 
            ngx.log(ngx.ERR, 'gg1:')
            ngx.exec("/index.html")
        end

        if not process_uri.is_max_count(request_url)then 
            ngx.log(ngx.ERR, 'gg2:')
            ngx.exec("/index.html")
        end

        if not process_uri.is_access_too_fast(request_url)then 
            ngx.log(ngx.ERR, 'gg3:')
            ngx.exec("/index.html")
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
        -- ngx.ctx.new_uri = real_uri
        -- ngx.var.is_first_access = false

        -- local new_uri= ngx.ctx.new_uri
        -- ngx.req.set_uri(new_uri)
        local res = ngx.location.capture(real_uri)

        if res.status == ngx.HTTP_OK then
            for k, v in pairs(res.header) do
                ngx.log(ngx.ERR, 'ngx header:', k ,':', v)
                ngx.ctx[k] = v
            end
            local content_type = res.header["Content-Type"]
            ngx.log(ngx.ERR, 'content_type:',content_type)
            ngx.log(ngx.ERR, 'pure body:',res.body)

                ngx.ctx.content_type = content_type
                local modified_body = response_handle.response_handle(res.body, false)
                -- 将修改后的响应数据存储在 ngx.ctx 中
                ngx.ctx.modified_body = modified_body

        else
            --处理错误
            ngx.log(ngx.ERR, 'Error capture :',res.status)
            return 
        end
    else
        process_uri.block_request_and_log("Cookie url not match.")
    end
end
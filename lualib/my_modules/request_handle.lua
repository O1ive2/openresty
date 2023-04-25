local process_uri = require('my_modules.check_transform_moudle')
local redis_connector = require('my_modules.redis_connector')
local url = require("socket.url")

local scheme = ngx.var.scheme
local host = ngx.var.host
local uri = ngx.var.uri
local request_url = scheme .. "://" .. host .. uri

local real_url_info  = redis_connector.get_data_in_url_table(request_url)

if real_url_info and next(real_url_info) == nil then

    if process_uri.is_dynamic_request() then

        if process_uri.is_in_whitelist(request_url) then 
            local new_cookie = 'is_first_access=true; Path=/; HttpOnly; Expires=' .. ngx.cookie_time(ngx.time() + 60 * 60 * 24 * 365)
            ngx.header['Set-Cookie'] = new_cookie
            
            ngx.req.set_uri(uri)
        else
            process_uri.block_request_and_log("Whitelisted URL not found")
        end

    else
        process_uri.block_request_and_log("Request is a dynamic request.")
    end

else 

    if process_uri.is_cookie_match(request_url) then

        process_uri.is_url_expire(request_url)

        process_uri.is_max_count(request_url)

        process_uri.is_access_too_fast(request_url)

        local real_url = real_url_info['real_url']

        local parsed_url = url.parse(real_url)
        local real_uri = parsed_url.path

        real_url_info.access_count = real_url_info.access_count + 1
        real_url_info.last_access = os.time()
        redis_connector.update_data(request_url, real_url_info)

        local new_cookie = 'is_first_access=false; Path=/; HttpOnly; Expires=' .. ngx.cookie_time(ngx.time() + 60 * 60 * 24 * 365)
        ngx.header['Set-Cookie'] = new_cookie

        ngx.req.set_uri(real_uri)
    else
        process_uri.block_request_and_log("Cookie url not match.")
    end
end
local rewrite_module = require('my_modules.rewrite_module')
local redis_connector = require('my_modules.redis_connector')
local uuid = require "resty.jit-uuid"
uuid.seed()

local _M = {}

function  _M.response_handle(response_body, is_first_access)
    

    ngx.log(ngx.ERR, '3 - 4.1')


    local user

    if is_first_access == true then
        ngx.log(ngx.ERR, '4.1 - 4.2')
        user = uuid()
        local _, err = redis_connector.add_user_key(user)
        if err then
            ngx.log(ngx.ERR,"Error delete_cookie_user:" ,err)
            return 
        end
    else
        ngx.log(ngx.ERR, '4.1 - 4.3')
        local old_cookie_value = ngx.var.cookie_value
        user = redis_connector.get_user_by_cookie(old_cookie_value)

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

    ngx.header['Set-Cookie'] = "value="..new_cookie_value .. '; Path=/; HttpOnly; Expires=' .. ngx.cookie_time(ngx.time() + 60 * 60 * 24 * 365)

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

    -- ngx.arg[1] = rewrite_html

    return rewrite_html

end

return _M
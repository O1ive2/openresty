local redis_connector = require "redis_connector"
local http = require "resty.http"
local uuid = require "resty.jit-uuid"
local rewrite_module = require 'my_modules.rewrite_module'
uuid.seed()

local function set_cookie_if_not_exists()
    local cookie_value = ngx.var.cookie_value
    if not cookie_value then
        
        cookie_value = uuid()
        ngx.header['Set-Cookie'] = 'value=' .. cookie_value .. '; Path=/; HttpOnly; Expires=' .. ngx.cookie_time(ngx.time() + 60 * 60 * 24 * 365)
    end

    return cookie_value
end

local function get_current_url()
    local scheme = ngx.var.scheme -- 获取协议（http 或 https）
    local host = ngx.var.host -- 获取主机名
    local uri = ngx.var.request_uri -- 获取请求的 URI
    return scheme .. "://" .. host .. uri
end

-- 2.1 判断是否为表单请求
local function is_form_request(url)
    local uri = ngx.var.scheme .. "://" .. ngx.var.host .. ngx.var.uri

    if string.len(url) >= string.len(uri) then
        return url
    else
        return false
    end
end

-- 2.2 判断是否存在该虚拟url
local function is_url_in_url_table(url)
    local  is_virtual_url_exists,err= redis_connector.is_virtual_url_exists(url) 
    if err then 
        ngx.log(ngx.ERR, "Error checking if URL exists in the url table: ", err)
    end

    if is_virtual_url_exists then
        -- to 2.3
        return true
    else
        -- to 2.5
        return false
    end
end

local function block_request_and_log(reason)
    ngx.log(ngx.ERR, "Request blocked: ", reason)
    return ngx.exit(ngx.HTTP_FORBIDDEN)
end

-- 2.3 判断是否为动态请求
local function is_dynamic_request()
    -- 获取请求方法
    local method = ngx.req.get_method()

    -- 获取请求路径
    local path = ngx.var.uri

    -- 获取请求查询参数
    local uri_args = ngx.req.get_uri_args()

    -- 动态请求方法的列表
    local dynamic_methods = { "POST", "PUT", "DELETE", "PATCH" }

    -- 根据请求方法判断请求是否为动态
    for _, dynamic_method in ipairs(dynamic_methods) do
        if method == dynamic_method then
            
            return block_request_and_log("Request type is dynamic request!")
        end
    end

    -- 如果 URL 中包含查询参数，则判断为动态页面请求
    if next(uri_args) ~= nil then
        return block_request_and_log("Request type is dynamic request!")
    end
    return true

end

-- 2.4
local function is_in_whitelist(request_url)
    local is_whitelisted, err = redis_connector.is_url_in_whitelist(request_url)

    if err then
        ngx.log(ngx.ERR, "Error checking whitelist: ", err)
        return
    end

    if is_whitelisted then
        local new_cookie = 'is_first_access=true; Path=/; HttpOnly; Expires=' .. ngx.cookie_time(ngx.time() + 60 * 60 * 24 * 365)
        ngx.header['Set-Cookie'] = new_cookie
        local httpc = http.new()
            local res, err = httpc:request_uri(request_url, {
                method = "GET",
                follow_redirects = true
            })

            if not res then
                return nil, err
            end

            local encrypted_html, err1 = rewrite_module.process_url_rewrite(request_url,res.body)

            if not encrypted_html then
                ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
                ngx.say("Error: ", err1)
            else
                ngx.header.content_type = "text/html; charset=utf-8"
                ngx.say(encrypted_html)
            end
    else 
        return block_request_and_log("Whitelisted URL not found")
    end
end

-- 2.5
local function is_cookie_match(request_url)
    local cur_cookie = ngx.var.cookie_value

    local user, err2 = redis_connector.get_user_by_cookie(cur_cookie)
    if err2 then
        ngx.log(ngx.ERR, "Cantnot find user by cookie: ", err2)
        return
    end

    local urls ,err1 = redis_connector.get_url_by_user(user)
    if err1 then
        ngx.log(ngx.ERR, "Cantnot find url by current user: ", err1)
        return
    end

    local info ,err3 = redis_connector.get_data_in_url_table(request_url)

    if err3 then
        ngx.log(ngx.ERR, "Cantnot find : ", err3)
        return
    end
    
    if urls and info then
        if urls[info['real_url']] == request_url then
            ngx.log(ngx.ERR, "cookie url match")
            return true
        end
    end

    return false
end

-- 2.6 
local function is_url_expire(url)
    local info, err = redis_connector.get_data_in_url_table(url)
    local cur_time = os.time()
    if err then
        ngx.log(ngx.ERR, "Get data error: ", err)
        return
    end
    if info then 
        if info.expire_time < cur_time then
            ngx.log(ngx.ERR, 'Vitural url is expire')
            ngx.ngx.exec("/html")
            return
        end
    end
end


-- 2.7
local function is_max_count(url)
    local info, err = redis_connector.get_data_in_url_table(url)
    if err then
        ngx.log(ngx.ERR, "Get data error: ", err)
        return
    end
    if info then 
        if info.access_count >= 1000 then
            ngx.log(ngx.ERR, 'Access count is max')
            ngx.ngx.exec("/html")
            return
        end
    end
end

-- 2.8
local function is_access_too_fast(url)
    local info, err = redis_connector.get_data_in_url_table(url)
    local cur_time = os.time()
    if err then
        ngx.log(ngx.ERR, "Get data error: ", err)
        return
    end
    if info then 
        if info.last_access - cur_time < 3 then
            ngx.log(ngx.ERR, 'Access too fast')
            ngx.exec("/html")
            return
        end
    end
end

-- 2.9
local function pop_to_real_url(url)
    local info, err = redis_connector.get_data_in_url_table(url)
    if err then
        ngx.log(ngx.ERR, "Get data error: ", err)
        return false
    end
    local update_data = {}
    if info then 
        update_data.access_count = info.access_count + 1
        update_data.last_access = os.time()
        local _ , err1 redis_connector.update_data(url, update_data)
        if err1 then
            ngx.log(ngx.ERR, "Update url data failed:"..err1)
            return false
        end
        return info.real_url
    end
end



-- 判断URL是否为系统要防护的Web服务器外的链接地址


local function handle_request(request_url, target_url)
    -- 在这里处理请求，例如检查 URL 和 Cookie 等
    local cookie = set_cookie_if_not_exists()
    -- local request_url = get_current_url()

    -- 2.1
    request_url = is_form_request(request_url)

    -- 2.2
    if is_url_in_url_table(request_url) then 
        -- 2.5
        local client_cookies = ngx.var.http_cookie or ""
        local new_cookie = 'is_first_access=false; Path=/; HttpOnly; Expires=' .. ngx.cookie_time(ngx.time() + 60 * 60 * 24 * 365)
        client_cookies = client_cookies .. "; " .. new_cookie
        ngx.header['Set-Cookie'] = client_cookies

        if is_cookie_match(request_url) then 
            -- 2.6
            is_url_expire(request_url)

            -- 2.7
            is_max_count(request_url)

            -- 2.8
            is_access_too_fast(request_url)
        else
            return block_request_and_log("Cookie and current url cannot match")
        end

        -- 2.9
        local real_url = pop_to_real_url(request_url)

        if real_url then

            local httpc = http.new()
            local res, err = httpc:request_uri(real_url, {
                method = "GET",
                follow_redirects = true
            })

            if not res then
                return nil, err
            end

            local encrypted_html, err1 = rewrite_module.process_url_rewrite(real_url,res)

            if not encrypted_html then
                ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
                ngx.say("Error: ", err1)
            else
                ngx.header.content_type = "text/html; charset=utf-8"
                ngx.say(encrypted_html)
            end
        end
    else
        -- 2.3
        is_dynamic_request() 
        -- 2.4
        is_in_whitelist(request_url)

            
    end
end

local _M = {}

function _M.fetch_and_encrypt_url(request_url, target_url)
    local httpc = http.new()
    local res, err = httpc:request_uri(request_url, {
        method = "GET",
    })

    if not res then
        ngx.log(ngx.ERR,'not res:',err)
        return nil, err
    end

    local content = res.body
    local processed_content = handle_request(request_url,target_url)
    return processed_content
end

return _M
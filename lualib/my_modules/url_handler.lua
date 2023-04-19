local redis_connector = require "redis_connector"
local http = require "resty.http"

local function get_current_url()
    local scheme = ngx.var.scheme -- 获取协议（http 或 https）
    local host = ngx.var.host -- 获取主机名
    local uri = ngx.var.request_uri -- 获取请求的 URI
    return scheme .. "://" .. host .. uri
end

-- 解析用户请求和提取URL和Cookie：
local function parse_request()
    local request_uri = ngx.var.request_uri
    local cookie_value = ngx.var.cookie_name -- 替换 name 为您要提取的cookie名称

    -- 返回URL和Cookie值
    return request_uri, cookie_value
end

-- 2.1 判断是否为表单请求
local function is_form_request(url)
    local pattern = "(/form/)$"
    if string.match(url, pattern) then
        local last_question_mark = string.find(url, "?[^?]*$")
        if last_question_mark then
            return string.sub(url, 1, last_question_mark - 1)
        else
            return url
        end
    else
        return nil
    end
end

-- 2.2 判断是否存在该虚拟url
local function is_url_in_url_table(url)
    local  is_virtual_url_exists,err= redis_connector.is_virtual_url_exists(url) 
    if err then 
        ngx.log(ngx.ERR, "Error checking if URL exists in the url table: ", err)
        return false
    else 
        return redis_connector.update_data(url, {is_first = false})
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

end


-- 2.4
local function is_in_whitelist()
    local request_url = get_current_url()
    local is_whitelisted, err = redis_connector.is_url_in_whitelist(request_url)

    if err then
        ngx.log(ngx.ERR, "Error checking whitelist: ", err)
        return
    end

    if is_whitelisted then
        ngx.log(ngx.NOTICE, "Whitelisted URL found: ", request_url)
        return ngx.exec("/api")
    end
end

-- 2.5
local function is_cookie_match()
    local request_url = get_current_url()
    local cur_cookie = ngx.var.cookie_name

    
    local user ,err1 = redis_connector.get_user_by_url(request_url)
    if err1 then
        ngx.log(ngx.ERR, "Cantnot find user by current url: ", err1)
        return
    end

    local cookie_of_user, err2 = redis_connector.get_cookie_by_user(user)
    if err2 then
        ngx.log(ngx.ERR, "Cantnot find cookie by user: ", err2)
        return
    end

    if cookie_of_user == cur_cookie then 
        return true
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
        if info.last_access - cur_time < 1000 then
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
        return
    end
    local update_data = {}
    if info then 
        update_data.access_count = info.access_count + 1
        update_data.last_access = os.time()
        local _ , err1 redis_connector.update_data(url, update_data)
        if err1 then
            ngx.log(ngx.ERR, "Update url data failed:"..err1)
        end
        ngx.exec(info.real_url)
    end
end


-- 判断URL是否为系统要防护的Web服务器外的链接地址
local function is_external_link(url, protected_server_url)
    return not string.find(url, protected_server_url)
end



-- 检查请求频率
local function is_request_rate_exceeded(key, max_rate)
    -- 使用Redis的INCRBY命令计算请求次数，然后使用EXPIRE设置超时
    -- 检查请求次数是否超过 max_rate
    -- 返回 true 或 false
end

local function rewrite_urls(response)
    -- 在这里添加您的地址重写模块代码，处理 response 变量中的内容
    -- ...
end



local function handle_request()
    -- 在这里处理请求，例如检查 URL 和 Cookie 等
    -- ...

    -- 将请求转发到后端服务器并获取响应
    local res = ngx.location.capture("/proxy_pass")
    if res.status ~= ngx.HTTP_OK then
        ngx.status = res.status
        return ngx.exit(res.status)
    end

    -- 对响应中的 URL 进行重写
    local rewritten_response = rewrite_urls(res.body)

    -- 将重写后的响应发送给客户端
    ngx.say(rewritten_response)
end

return {
    handle_request = handle_request,
}
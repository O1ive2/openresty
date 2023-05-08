local redis_connector = require "redis_connector"
local http = require "resty.http"
local uuid = require "resty.jit-uuid"
local rewrite_module = require 'my_modules.rewrite_module'
uuid.seed()

local _M = {}

function  _M.table_to_string(tbl)
    local result, done = {}, {}
    for k, v in ipairs(tbl) do
        table.insert(result, tostring(v))
        done[k] = true
    end
    for k, v in pairs(tbl) do
        if not done[k] then
            table.insert(result, k .. "=" .. tostring(v))
        end
    end
    return "{" .. table.concat(result, ", ") .. "}"
end

function _M.block_request_and_log(reason)
    ngx.log(ngx.ERR, "Request blocked: ", reason)
    return ngx.exit(ngx.HTTP_FORBIDDEN)
end

-- 2.3 判断是否为动态请求
function _M.is_dynamic_request()
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
            
            return _M.block_request_and_log("Request type is dynamic request!")
        end
    end

    -- 如果 URL 中包含查询参数，则判断为动态页面请求
    if next(uri_args) ~= nil then
        return _M.block_request_and_log("Request type is dynamic request!")
    end
    return true

end

-- 2.4
function _M.is_in_whitelist(request_url)
    local is_whitelisted, err = redis_connector.is_url_in_whitelist(request_url)


    if err then
        ngx.log(ngx.ERR, "Error checking whitelist: ", err)
        return
    end

    if is_whitelisted then
        return true
    else 
        return false
    end
end

-- 2.5
function _M.is_cookie_match(cookie_value)

    ngx.log(ngx.ERR, 'cookie_value:', cookie_value)
    

    local ip = redis_connector.get_ip_by_cookie(cookie_value)



    local cur_ip = ngx.var.remote_addr

    ngx.log(ngx.ERR, 'cur_ip:',cur_ip,'  ip:',ip)

    if ip == cur_ip then
        return true
    else
        return false
    end
end

function _M.is_ip_user_match(user)
    local ip = redis_connector.get_ip_by_user(user)

    local cur_ip = ngx.var.remote_addr

    if ip == cur_ip then
        return true
    else
        return false
    end
end

-- 2.6 
function _M.is_url_expire(url)
    local info, err = redis_connector.get_data_in_url_table(url)
    local cur_time = ngx.time()
    if err then
        ngx.log(ngx.ERR, "Get data error: ", err)
        return false
    end

    if info and tonumber(info.expire_time) < cur_time then
        ngx.log(ngx.ERR, '2.6 failed')
        ngx.log(ngx.ERR, 'Vitural url is expire')
        return false
    end

    return true
end


-- 2.7
function _M.is_max_count(url)
    local info, err = redis_connector.get_data_in_url_table(url)
    if err then
        ngx.log(ngx.ERR, "Get data error: ", err)
        return false
    end
    if info and tonumber(info.access_count) >= 1000 then
        ngx.log(ngx.ERR, 'Access count is max')
        ngx.log(ngx.ERR, '2.7 failed')
        return false
    end
    return true
end

-- 2.8
function _M.is_access_too_fast(url)
    local info, err = redis_connector.get_data_in_url_table(url)
    local cur_time = ngx.time()
    if err then
        ngx.log(ngx.ERR, "Get data error: ", err)
        return false
    end


    if info and cur_time - tonumber( info.last_access )  < 3 then
        ngx.log(ngx.ERR, 'Access too fast')
        ngx.log(ngx.ERR, '2.8 failed')
        return false
    end

    return true
end


return _M
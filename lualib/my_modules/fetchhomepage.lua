
local check_transform_moudle = require('check_transform_moudle')

local scheme = ngx.var.scheme -- 获取协议（http 或 https）
local host = ngx.var.host
local uri = ngx.var.request_uri -- 获取请求的 URI


local request_url =  scheme .. "://pwb.com" .. uri

local target_url = scheme .. "://".. host .. uri


local encrypted_html, err = check_transform_moudle.fetch_and_encrypt_url(request_url, target_url)


if not encrypted_html then
    ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
    ngx.say("Error: ", err)
else
    ngx.header.content_type = "text/html; charset=utf-8"
    ngx.say(encrypted_html)
end

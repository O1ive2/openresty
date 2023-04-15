local http = require "resty.http"

-- 创建HTTP客户端
local httpc = http.new()

-- 发送HTTP请求
local res, err = httpc:request_uri("http://example.com/index.html", {
    method = "GET"
})

-- 检查请求结果
if not res then
    ngx.log(ngx.ERR, "failed to request: ", err)
    ngx.exit(500)
end

-- 将HTML文件输出到客户端
ngx.header.content_type = "text/html"
ngx.say(res.body)

-- 关闭HTTP客户端
httpc:close()
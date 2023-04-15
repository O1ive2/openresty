local resty_aes = require "resty.aes"

-- 生成随机密钥
local function generate_key()
    math.randomseed(os.time())
    local key = ""
    for i=1, 16 do
        key = key .. string.char(math.random(0, 255))
    end
    return key
end

-- 获取请求的 URL 前缀
local function get_url_prefix()
    return ngx.var.scheme .. "://" .. ngx.var.host
end

-- 将所有链接转换成绝对 URL
local function convert_links_to_absolute_url(content)
    local url_prefix = get_url_prefix()
    content = string.gsub(content, "(href=[\"'])(/[^\"']+)([\"'])", function(match)
        return match:gsub("/[^\"']+", url_prefix .. "%1")
    end)
    return content
end

-- 加密 URL 中除域名外的部分
local function encrypt_url(url, key)
    local aes = resty_aes:new(key)
    local path = url:gsub("^https?://[^/]+", "")
    path = ngx.encode_base64(aes:encrypt(path))
    return url:gsub("/[^/]+", path)
end

-- 处理响应
local function handle_response()
    -- 获取响应内容
    local content = ngx.arg[1]

    -- 将所有链接转换为绝对 URL
    content = convert_links_to_absolute_url(content)

    -- 生成随机密钥并加密 URL
    local key = generate_key()
    content = string.gsub(content, "https?://[^\"'<>]+", function(url)
        return encrypt_url(url, key)
    end)

    -- 发送替换后的响应数据
    ngx.arg[1] = content
end

-- 设置响应处理函数
ngx.header.content_handler = "lua"
ngx.header.content_type = "text/html"
ngx.arg[2] = handle_response

-- sudo /usr/local/openresty/nginx/sbin/nginx -s reload
-- sudo /usr/local/openresty/nginx/sbin/nginx -t

-- 定义变量，用于存储AES加密密钥
local aes_key = "qwertyuiopasdfgh"
local aes = require 'resty.aes'

-- 定义函数，用于加密URL的路径
local function encrypt_url_path(url)
    ngx.log(ngx.ERR,'url:'..url)
    local domain = ngx.re.match(url, "^http?://([^/]+)")[1]
    ngx.log(ngx.ERR,'domain:'..domain)
    local path = ngx.re.match(url, "^http?://[^/]+(.*)")[1]
    ngx.log(ngx.ERR,'path:'..path)
    local aes_cipher = aes:new(aes_key, nil, aes.cipher(128, "cbc"), {iv = "1234567890123456"})
    if not aes_cipher then
        ngx.log(ngx.ERR, "Failed to create AES cipher")
        return nil
    end
    local encrypted_path = ngx.encode_base64(aes_cipher:encrypt(path))
    ngx.log(ngx.ERR,'encrypt:'..encrypted_path)
    return string.format("%s://%s/%s", ngx.var.scheme, domain, encrypted_path)
end

local res = ngx.location.capture("/test.html")
if res.status == 200 then
    -- 从响应正文中提取所有URL，并将其替换为加密后的URL
    local body = res.body
    
    local matches, err = ngx.re.gmatch(body, '(http?://[^"\'%s]+)', "ijo")

    
    if matches then
        for match, err in matches do 
            ngx.print(match[0])
            local url = match[0]
            local encrypted_url = encrypt_url_path(url)
            ngx.print(encrypted_url)
            body = string.gsub(body, url, encrypted_url, 1)
        end
    end
    -- 返回更改后的响应
    ngx.header.content_type = "text/html"
    ngx.print(body)
else
    ngx.status = res.status
    ngx.say(res.body..'faild')
end
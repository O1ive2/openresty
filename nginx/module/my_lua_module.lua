-- 密钥
local key = "my-secret-key"

-- -- 加密函数
-- local function encrypt(url)
--     local aes = require "resty.aes"
--     local cipher = assert(aes:new(key, aes.cipher(128, "cbc"), aes.hash.md5, 2))
--     return ngx.encode_base64(cipher:encrypt(url))
-- end

-- -- 解密函数
-- local function decrypt(encrypted_url)
--     local aes = require "resty.aes"
--     local cipher = assert(aes:new(key, aes.cipher(128, "cbc"), aes.hash.md5, 2))
--     return cipher:decrypt(ngx.decode_base64(encrypted_url))
-- end

-- -- 哈希函数
-- local function hash(url)
--     local resty_sha1 = require "resty.sha1"
--     local sha1 = resty_sha1:new()
--     sha1:update(url)
--     return ngx.encode_base64(sha1:final())
-- end


-- 密钥
local key = "my-secret-key"

-- 加密函数
local function encrypt(id)
    local aes = require "resty.aes"
    local cipher = assert(aes:new(key, aes.cipher(128, "cbc"), aes.hash.md5, 2))
    return ngx.encode_base64(cipher:encrypt(id))
end

-- 哈希函数
local function hash(id)
    local resty_sha1 = require "resty.sha1"
    local sha1 = resty_sha1:new()
    sha1:update(id)
    return ngx.encode_base64(sha1:final())
end

-- 生成短网址
local function generate_short_url(id)
    local hashed_id = hash(id)
    local encrypted_id = encrypt(id)
    return "/s/" .. hashed_id .. "/" .. encrypted_id
end

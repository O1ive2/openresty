local url_encryptor = require("url_encryptor")

local key = "qwertyuiopasdfgh"
local target_url = "http://127.0.0.1/html/"

local encrypted_html, err = url_encryptor.fetch_and_encrypt_url(key, target_url)


if not encrypted_html then
    ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
    ngx.say("Error: ", err)
else
    ngx.header.content_type = "text/html; charset=utf-8"
    ngx.say(encrypted_html)
end
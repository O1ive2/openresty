local redis = require("redis")
local client = redis.connect("127.0.0.1", 6379) -- 修改为你的Redis服务器地址和端口

local script = [[
    local hash_tables = {
        "cookie_ip",
        "cookie_user",
        "url",
        "user_key",
        "user_url",
        "user_ip"
    }

    local key_name = "test"
    local value = "test"

    for _, hash_table in ipairs(hash_tables) do
        redis.call("DEL", hash_table) -- 删除哈希表
        redis.call("HSET", hash_table, key_name, value) -- 重新创建哈希表并添加键值对
    end

    return "哈希表已重置并添加新的键值对"
]]

local result = client:eval(script, 0)
print(result)
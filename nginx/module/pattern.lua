local redis = require 'redis'
local cjson = require 'cjson'

-- 连接到 Redis 服务器
local client = redis.connect('127.0.0.1', 6379)

-- 虚拟 URL 及其相关信息
local virtual_url_data = {
    real_url = 'http://real-url.com',
    timeout_threshold = 3600,
    access_rate_limit = 60,
    max_access_count = 1000
}

-- 将信息序列化为 JSON 字符串
local json_data = cjson.encode(virtual_url_data)

-- 将 JSON 字符串存储到 Redis 的哈希表中
client:hset('url', 'virtual_url_1', json_data)

-- local redis = require 'redis'
-- local cjson = require 'cjson'

-- -- 连接到 Redis 服务器
-- local client = redis.connect('127.0.0.1', 6379)

-- -- 要查询的虚拟 URL
-- local virtual_url = "virtual_url_1"

-- -- 获取 JSON 字符串并反序列化为 Lua 表格
-- local json_data = client:hget('url', virtual_url)
-- local virtual_url_data = cjson.decode(json_data)

-- -- 打印获取到的值
-- print("Virtual URL: " .. virtual_url)
-- print("Real URL: " .. virtual_url_data.real_url)
-- print("Timeout Threshold: " .. virtual_url_data.timeout_threshold)
-- print("Access Rate Limit: " .. virtual_url_data.access_rate_limit)
-- print("Max Access Count: " .. virtual_url_data.max_access_count)


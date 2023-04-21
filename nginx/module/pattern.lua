function make_absolute_url(base_url, relative_url)
    local url = require("socket.url")  -- 请确保安装了 LuaSocket 库

    print('base_url:', base_url)

    print('relative_url', relative_url)

    -- 解析基本 URL
    local parsed_base_url = url.parse(base_url)
    print('parsed_base_url',parsed_base_url)
    -- 解析相对 URL
    local parsed_relative_url = url.parse(relative_url)
    print('parsed_relative_url',parsed_relative_url)
    -- 合并两个 URL
    local parsed_absolute_url = url.absolute(base_url, relative_url)
    print('parsed_absolute_url',parsed_absolute_url)
    -- 返回绝对 URL 字符串
    return url.build(parsed_absolute_url)
end

local base_url = "https://example.com/folder/page.html"
local relative_url = "../other-folder/other-page.html"

local absolute_url = make_absolute_url(base_url, relative_url)
print(absolute_url)
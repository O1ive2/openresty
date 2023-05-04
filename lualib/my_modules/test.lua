-- local css_content = [=[
--     .news_icon{background:url(images/list-1.gif);height:16px; background-position: 0px 2px;background-repeat: no-repeat;width:10px;display:block;float:left;}
--         .news_icon_td{background:url(images/list-1.gif);height:16px;background-position: 0px 2px;background-repeat: no-repeat;width:10px;}
--         .div_more a{float:right;width:46px;height:14px;display:block;background:url(images/more.gif);}
--         .scrollnews_li{background:url(images/dot.jpg);background-position: 0px 24px;background-repeat:repeat-x;}
--         .scrollnews3_ul li{background:url(images/dot.jpg);background-position: 0px 24px;background-repeat:repeat-x;padding-left:10px;float:left;}
--         @import url("cms-ie6.min.css");
--         ndex-titlebg{background: url(Index_TitleBg.png) no-re

-- ]=]

-- local function escape(s)
--     return s:gsub("([^%w])", "%%%1")
-- end

-- local patterns = {
--     '@import%s+"([^"]*)"%s*',
--     "@import%s+'([^']*)'%s*"
-- }

-- local patterns_1 = {
--     'url%("([^"]*)"%)',
--     "url%('([^']*)'%)",
--     'url%(([^"\'%s]+)%)'
-- }
-- local url_infos = {}
-- for _, pattern in ipairs(patterns) do
--     css_content = string.gsub(css_content, pattern, function(url)
--         table.insert(url_infos, {url = url})
--         return '@import url("' .. url .. '")'
--     end)
-- end

-- -- 提取 URL 信息
-- for _, pattern in ipairs(patterns_1) do
--     css_content = string.gsub(css_content, pattern, function(url)
--         table.insert(url_infos, {url = url})
--         return 'url("' .. url .. '");'
--     end)
-- end

-- local replaced_urls = {}
-- for _, url_info in ipairs(url_infos) do
--     local replaced_url = 'qqqqqqqqqqqqqqqqqqqqqq'
--     replaced_urls[url_info.url] = replaced_url
-- end

-- for original_url, replaced_url in pairs(replaced_urls) do
--     print('original_url:',original_url, 'replaced_url:',replaced_url)
--     css_content = string.gsub(css_content, escape(original_url), replaced_url)
-- end

-- print(css_content)


local url_string = 'http://cbs.edu.cn/main.htm'
local url = string.gsub(url_string, 'cbs.edu.cn', 'rws.com')
print(url)